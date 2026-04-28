local M = {}

local _debug_log
local _debug_enabled
local _fixed_time

local VOIDBLAST_TEMPLATE_NAME = "forcestaff_p1_m1"
local VOIDBLAST_CHARGE_ACTION_NAME = "action_charge"
local VOIDBLAST_CHARGED_FIRE_INPUT = "trigger_explosion"
local VOIDBLAST_MIN_LEAD_TIME = 0.3
local VOIDBLAST_MAX_LEAD_TIME = 0.6

local _voidblast_anchor_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _voidblast_fallback_logged_scratchpads = setmetatable({}, { __mode = "k" })

function M.scratchpad_player_unit(scratchpad)
	local action_input_extension = scratchpad and scratchpad.action_input_extension or nil
	local unit = action_input_extension and action_input_extension._betterbots_player_unit or nil

	return unit or scratchpad and scratchpad.__bb_weakspot_self_unit or nil
end

local function current_weapon_action_template_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.template_name or nil
end

local function current_weapon_action_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.current_action_name or nil
end

function M.is_voidblast_staff(scratchpad)
	local unit = M.scratchpad_player_unit(scratchpad)

	return current_weapon_action_template_name(unit) == VOIDBLAST_TEMPLATE_NAME
end

function M.is_charge_active(scratchpad)
	if not M.is_voidblast_staff(scratchpad) then
		return false
	end

	if scratchpad and scratchpad.charging_shot then
		return true
	end

	local unit = M.scratchpad_player_unit(scratchpad)
	local current_action_name = current_weapon_action_name(unit)
	if current_action_name == VOIDBLAST_CHARGE_ACTION_NAME then
		return true
	end

	return scratchpad and scratchpad.aiming_shot and scratchpad.aim_action_input == "charge" or false
end

function M.should_lock_anchor(scratchpad)
	return scratchpad and M.is_charge_active(scratchpad) or false
end

function M.charged_fire_input(scratchpad)
	if not M.is_voidblast_staff(scratchpad) then
		return nil
	end

	local aim_fire_action_input = scratchpad and scratchpad.aim_fire_action_input or nil
	local fire_action_input = scratchpad and scratchpad.fire_action_input or nil

	if aim_fire_action_input and aim_fire_action_input ~= fire_action_input then
		return aim_fire_action_input
	end

	return VOIDBLAST_CHARGED_FIRE_INPUT
end

function M.forced_fire_input(scratchpad)
	if not scratchpad then
		return nil
	end

	if M.is_charge_active(scratchpad) then
		local fire_action_input = scratchpad.fire_action_input
		local charged_fire_input = M.charged_fire_input(scratchpad)
		if charged_fire_input and charged_fire_input ~= fire_action_input then
			return charged_fire_input
		end
	end

	local fire_action_input = scratchpad.fire_action_input
	if scratchpad.aiming_shot then
		local aim_fire_action_input = scratchpad.aim_fire_action_input
		if aim_fire_action_input and aim_fire_action_input ~= fire_action_input then
			return aim_fire_action_input
		end

		return nil
	end

	if scratchpad.charging_shot then
		local charged_fire_input = M.charged_fire_input(scratchpad)
		if charged_fire_input and charged_fire_input ~= fire_action_input then
			return charged_fire_input
		end
	end

	return nil
end

function M.should_force_charged_fire(scratchpad)
	return scratchpad and M.is_charge_active(scratchpad) and M.forced_fire_input(scratchpad) ~= nil or false
end

function M.clear_anchor(scratchpad, suppress_reanchor)
	if scratchpad then
		scratchpad.__bb_voidblast_anchor = nil
		scratchpad.__bb_voidblast_anchor_suppressed = suppress_reanchor and true or nil
	end
end

local function vector3_flat(v)
	if Vector3 and Vector3.flat then
		return Vector3.flat(v)
	end

	return nil
end

local function vector3_normalize(v)
	if Vector3 and Vector3.normalize then
		return Vector3.normalize(v)
	end

	return nil
end

local function vector3_up()
	if Vector3 and Vector3.up then
		return Vector3.up()
	end

	return nil
end

local function vector3_length_squared(v)
	if Vector3 and Vector3.length_squared then
		return Vector3.length_squared(v)
	end

	return v and (v.x * v.x + v.y * v.y + v.z * v.z) or 0
end

local function lead_time(scratchpad)
	local minimum_charge_time = scratchpad and scratchpad.minimum_charge_time or 0
	local resolved = math.max(VOIDBLAST_MIN_LEAD_TIME, minimum_charge_time or 0)

	return math.min(VOIDBLAST_MAX_LEAD_TIME, resolved)
end

function M.aim_rotation(current_position, anchor_position)
	if not current_position or not anchor_position then
		return nil, "missing_anchor_position"
	end

	local delta = anchor_position - current_position
	if vector3_length_squared(delta) <= 1e-6 then
		return nil, "degenerate_anchor_delta"
	end

	local direction = vector3_normalize(delta)
	local up = vector3_up()
	if not direction or not up or not Quaternion or not Quaternion.look then
		return nil, "missing_rotation_math"
	end

	return Quaternion.look(direction, up), nil
end

function M.log_fallback(scratchpad, self_unit, target_unit, reason)
	if not (_debug_enabled and _debug_enabled()) or not scratchpad or not reason then
		return nil
	end

	local logged_reasons = _voidblast_fallback_logged_scratchpads[scratchpad]
	if not logged_reasons then
		logged_reasons = {}
		_voidblast_fallback_logged_scratchpads[scratchpad] = logged_reasons
	end
	if logged_reasons[reason] then
		return nil
	end
	logged_reasons[reason] = true

	_debug_log(
		"voidblast_fallback:" .. tostring(self_unit) .. ":" .. tostring(reason),
		_fixed_time(),
		"voidblast aim fallback (reason="
			.. tostring(reason)
			.. ", bot="
			.. tostring(self_unit)
			.. ", target="
			.. tostring(target_unit)
			.. ")"
	)
end

local function target_velocity(self, target_unit, target_breed)
	if not (self and self._target_velocity) then
		return nil, nil
	end

	local ok, velocity = pcall(self._target_velocity, self, target_unit, target_breed)
	if not ok then
		return nil, "target_velocity_unavailable"
	end

	return velocity, nil
end

function M.resolve_anchor_state(self, self_unit, scratchpad, target_unit)
	if not M.should_lock_anchor(scratchpad) then
		M.clear_anchor(scratchpad)
		return nil, nil
	end
	if scratchpad.__bb_voidblast_anchor_suppressed then
		return nil, "anchor_suppressed"
	end

	local state = scratchpad.__bb_voidblast_anchor
	if state and state.target_unit then
		target_unit = state.target_unit
	end

	local target_position = POSITION_LOOKUP and target_unit and POSITION_LOOKUP[target_unit] or nil
	if not target_position then
		return nil, "missing_target_position"
	end

	local resolved_lead_time = lead_time(scratchpad)
	local velocity, velocity_reason = target_velocity(self, target_unit, scratchpad.target_breed)
	if velocity_reason then
		M.clear_anchor(scratchpad, true)
		return nil, velocity_reason
	end

	local anchor_position = target_position
	local flat_velocity = velocity and vector3_flat(velocity) or nil
	if flat_velocity then
		anchor_position = anchor_position + flat_velocity * resolved_lead_time
	end

	state = state or {}
	state.target_unit = target_unit
	state.position = anchor_position
	state.lead_time = resolved_lead_time
	scratchpad.__bb_voidblast_anchor = state

	if _debug_enabled and _debug_enabled() and not _voidblast_anchor_logged_scratchpads[scratchpad] then
		_voidblast_anchor_logged_scratchpads[scratchpad] = true
		_debug_log(
			"voidblast_anchor:" .. tostring(self_unit) .. ":" .. tostring(target_unit),
			_fixed_time(),
			"voidblast anchor locked (lead="
				.. string.format("%.2f", resolved_lead_time)
				.. ", bot="
				.. tostring(self_unit)
				.. ", target="
				.. tostring(target_unit)
				.. ", pos="
				.. string.format("%.2f", anchor_position.x)
				.. ","
				.. string.format("%.2f", anchor_position.y)
				.. ","
				.. string.format("%.2f", anchor_position.z)
				.. ")"
		)
	end

	return state
end

function M.init(deps)
	deps = deps or {}
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_voidblast_anchor_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_voidblast_fallback_logged_scratchpads = setmetatable({}, { __mode = "k" })
end

return M
