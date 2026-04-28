-- BtBotShootAction helpers for scratchpad normalization, stale ADS suppression,
-- plasma may-fire diagnostics, and shared shoot scratchpad unit resolution.
local M = {}

local _debug_log
local _debug_enabled
local _fixed_time

local _stale_shoot_action_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _plasma_may_fire_logged_scratchpads = setmetatable({}, { __mode = "k" })

local function find_action_for_start_input(actions, input_name)
	for action_name, action in pairs(actions or {}) do
		if action.start_input == input_name then
			return action_name, action
		end
	end

	return nil, nil
end

local function find_unaim_action_for_action(weapon_template, action)
	local actions = weapon_template and weapon_template.actions or {}
	local unaim_input = action and action.stop_input
	if unaim_input then
		local unaim_action_name = find_action_for_start_input(actions, unaim_input)

		return unaim_input, unaim_action_name
	end

	for input_name, chain_entry in pairs((action and action.allowed_chain_actions) or {}) do
		local action_name = chain_entry and chain_entry.action_name
		local target_action = action_name and actions[action_name]
		if target_action and target_action.kind == "unaim" then
			return input_name, action_name
		end
	end

	return nil, nil
end

local function has_hold_start_input(weapon_template, input_name)
	local input_def = weapon_template and weapon_template.action_inputs and weapon_template.action_inputs[input_name]
	local seq = input_def and input_def.input_sequence
	local first = seq and seq[1]

	return first and first.input == "action_two_hold" and first.value == true
end

local function weapon_template_supports_input(weapon_template, input_name)
	if type(input_name) ~= "string" then
		return false
	end

	local action_inputs = weapon_template and weapon_template.action_inputs or nil

	return type(action_inputs) == "table" and action_inputs[input_name] ~= nil or false
end

local DIRECT_FIRE_INPUT_PREFERENCE = { "shoot_pressed", "shoot_charge", "shoot" }

local function find_direct_fire_input(weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs or {}
	local actions = weapon_template and weapon_template.actions or {}
	local candidates = {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def and input_def.input_sequence
		local first = seq and seq[1]
		if first and first.input == "action_one_pressed" and first.value == true and not first.hold_input then
			local action_name = find_action_for_start_input(actions, input_name)
			if action_name then
				candidates[#candidates + 1] = input_name
			end
		end
	end

	if #candidates == 0 then
		return nil
	end

	for _, preferred in ipairs(DIRECT_FIRE_INPUT_PREFERENCE) do
		for _, input_name in ipairs(candidates) do
			if input_name == preferred then
				return input_name
			end
		end
	end

	return candidates[1]
end

local function clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad)
	if not scratchpad then
		return false
	end

	local changed = false

	if
		scratchpad.aim_action_input
		and not weapon_template_supports_input(weapon_template, scratchpad.aim_action_input)
	then
		scratchpad.aim_action_input = nil
		changed = true
	end

	if scratchpad.aim_action_input == nil and scratchpad.aim_action_name ~= nil then
		scratchpad.aim_action_name = nil
		changed = true
	end

	if
		scratchpad.unaim_action_input
		and (
			scratchpad.aim_action_input == nil
			or not weapon_template_supports_input(weapon_template, scratchpad.unaim_action_input)
		)
	then
		scratchpad.unaim_action_input = nil
		changed = true
	end

	if scratchpad.unaim_action_input == nil and scratchpad.unaim_action_name ~= nil then
		scratchpad.unaim_action_name = nil
		changed = true
	end

	return changed
end

local function find_bt_shoot_aim_chain(weapon_template, aim_fire_input)
	for action_name, action in pairs(weapon_template and weapon_template.actions or {}) do
		local start_input = action.start_input
		if start_input and has_hold_start_input(weapon_template, start_input) then
			local chain_entry = (action.allowed_chain_actions or {})[aim_fire_input]
			if chain_entry then
				local unaim_input, unaim_action_name = find_unaim_action_for_action(weapon_template, action)

				return start_input, action_name, unaim_input, unaim_action_name
			end
		end
	end

	return nil, nil, nil, nil
end

function M.normalize_bt_shoot_scratchpad(weapon_template, scratchpad)
	if not weapon_template or not scratchpad then
		return false
	end

	local changed = false
	if
		scratchpad.fire_action_input
		and not weapon_template_supports_input(weapon_template, scratchpad.fire_action_input)
	then
		local fire_input = find_direct_fire_input(weapon_template)
		if fire_input then
			scratchpad.fire_action_input = fire_input
			changed = true
		end
	end

	if
		scratchpad.aim_fire_action_input
		and not weapon_template_supports_input(weapon_template, scratchpad.aim_fire_action_input)
		and weapon_template_supports_input(weapon_template, scratchpad.fire_action_input)
	then
		scratchpad.aim_fire_action_input = scratchpad.fire_action_input
		changed = true
	end

	if not scratchpad.aim_fire_action_input then
		return clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad) or changed
	end

	local aim_input, aim_action_name, unaim_input, unaim_action_name =
		find_bt_shoot_aim_chain(weapon_template, scratchpad.aim_fire_action_input)
	if not aim_input then
		return clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad) or changed
	end

	if scratchpad.aim_action_input ~= aim_input then
		scratchpad.aim_action_input = aim_input
		changed = true
	end

	if aim_action_name and scratchpad.aim_action_name ~= aim_action_name then
		scratchpad.aim_action_name = aim_action_name
		changed = true
	end

	if unaim_input and scratchpad.unaim_action_input ~= unaim_input then
		scratchpad.unaim_action_input = unaim_input
		changed = true
	end

	if unaim_action_name and scratchpad.unaim_action_name ~= unaim_action_name then
		scratchpad.unaim_action_name = unaim_action_name
		changed = true
	end

	return changed
end

function M.current_weapon_action_template_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.template_name or nil
end

function M.scratchpad_player_unit(scratchpad)
	local action_input_extension = scratchpad and scratchpad.action_input_extension or nil
	local unit = action_input_extension and action_input_extension._betterbots_player_unit or nil

	return unit or scratchpad and scratchpad.__bb_weakspot_self_unit or nil
end

local function parser_accepts_weapon_action_input(action_input_extension, template_name, action_input)
	local parser = action_input_extension
		and action_input_extension._action_input_parsers
		and action_input_extension._action_input_parsers.weapon_action
	local sequence_configs = parser
		and parser._ACTION_INPUT_SEQUENCE_CONFIGS
		and parser._ACTION_INPUT_SEQUENCE_CONFIGS[template_name]

	if sequence_configs == nil then
		return true
	end

	return sequence_configs[action_input] ~= nil
end

function M.accepts_weapon_action_input(action_input_extension, template_name, action_input)
	return parser_accepts_weapon_action_input(action_input_extension, template_name, action_input)
end

function M.should_suppress_stale_shoot_action(scratchpad, action_input)
	local action_input_extension = scratchpad and scratchpad.action_input_extension or nil
	local unit = M.scratchpad_player_unit(scratchpad)
	local template_name = M.current_weapon_action_template_name(unit)
	if not action_input_extension or not template_name then
		return false, template_name
	end
	if type(action_input) ~= "string" then
		return true, template_name
	end

	return not parser_accepts_weapon_action_input(action_input_extension, template_name, action_input), template_name
end

function M.should_suppress_stale_shoot_unaim(scratchpad)
	local suppress, template_name =
		M.should_suppress_stale_shoot_action(scratchpad, scratchpad and scratchpad.unaim_action_input)
	if suppress then
		return true, template_name
	end

	if scratchpad and scratchpad.aim_action_input == nil and scratchpad.aiming_shot then
		local unit = M.scratchpad_player_unit(scratchpad)
		return true, M.current_weapon_action_template_name(unit)
	end

	return false, template_name
end

function M.log_stale_shoot_action(scratchpad, phase, action_input, template_name)
	if not (_debug_enabled and _debug_enabled()) or not scratchpad then
		return
	end

	local logged_phases = _stale_shoot_action_logged_scratchpads[scratchpad]
	if not logged_phases then
		logged_phases = {}
		_stale_shoot_action_logged_scratchpads[scratchpad] = logged_phases
	end
	if logged_phases[phase] then
		return
	end
	logged_phases[phase] = true

	local unit = M.scratchpad_player_unit(scratchpad)
	_debug_log(
		"stale_shoot_action:" .. tostring(phase) .. ":" .. tostring(template_name or "unknown") .. ":" .. tostring(unit),
		_fixed_time(),
		"suppressed stale shoot "
			.. tostring(phase)
			.. " input "
			.. tostring(action_input)
			.. " for "
			.. tostring(template_name or "unknown")
			.. " (bot="
			.. tostring(unit)
			.. ")"
	)
end

local function is_plasmagun_scratchpad(scratchpad)
	local unit = M.scratchpad_player_unit(scratchpad)

	return M.current_weapon_action_template_name(unit) == "plasmagun_p1_m1"
end

local function may_fire_block_reason(scratchpad, range_squared, t)
	if not scratchpad then
		return "missing_scratchpad"
	end

	if scratchpad.fire_input_request_id then
		return "pending_fire"
	end

	if scratchpad.obstructed then
		return "obstructed"
	end

	if scratchpad.aiming_shot and t < (scratchpad.aim_done_t or 0) then
		return "aiming"
	end

	local charging = scratchpad.charging_shot
	local minimum_charge_time = scratchpad.minimum_charge_time
	local sufficiently_charged = not minimum_charge_time
		or not scratchpad.always_charge_before_firing and not charging
		or charging and scratchpad.charge_start_time and minimum_charge_time <= t - scratchpad.charge_start_time
	if not sufficiently_charged then
		return "charge"
	end

	local max_range_sq = charging and scratchpad.max_range_sq_charged or scratchpad.max_range_sq
	if max_range_sq and max_range_sq <= range_squared then
		return "range"
	end

	local weapon_extension = scratchpad.weapon_extension
	if weapon_extension and weapon_extension.action_input_is_currently_valid then
		local fixed_frame = rawget(_G, "FixedFrame")
		local fixed_t = fixed_frame and fixed_frame.get_latest_fixed_time and fixed_frame.get_latest_fixed_time() or t
		local ok, valid = pcall(
			weapon_extension.action_input_is_currently_valid,
			weapon_extension,
			"weapon_action",
			scratchpad.fire_action_input,
			nil,
			fixed_t
		)
		if ok and not valid then
			return "invalid_input"
		elseif not ok then
			return "input_check_failed"
		end
	end

	return "vanilla_false"
end

function M.log_plasma_may_fire_block(scratchpad, range_squared, t)
	if not (_debug_enabled and _debug_enabled()) or not is_plasmagun_scratchpad(scratchpad) then
		return
	end

	local reason = may_fire_block_reason(scratchpad, range_squared, t)
	local logged_reasons = _plasma_may_fire_logged_scratchpads[scratchpad]
	if not logged_reasons then
		logged_reasons = {}
		_plasma_may_fire_logged_scratchpads[scratchpad] = logged_reasons
	end
	if logged_reasons[reason] then
		return
	end
	logged_reasons[reason] = true

	_debug_log(
		"plasma_may_fire_block:" .. tostring(reason) .. ":" .. tostring(M.scratchpad_player_unit(scratchpad)),
		_fixed_time(),
		"plasma _may_fire blocked (reason="
			.. tostring(reason)
			.. ", fire="
			.. tostring(scratchpad and scratchpad.fire_action_input)
			.. ", aim_fire="
			.. tostring(scratchpad and scratchpad.aim_fire_action_input)
			.. ", aiming="
			.. tostring(scratchpad and scratchpad.aiming_shot)
			.. ", charging="
			.. tostring(scratchpad and scratchpad.charging_shot)
			.. ", obstructed="
			.. tostring(scratchpad and scratchpad.obstructed)
			.. ")",
		1
	)
end

function M.init(deps)
	deps = deps or {}
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_stale_shoot_action_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_plasma_may_fire_logged_scratchpads = setmetatable({}, { __mode = "k" })
end

return M
