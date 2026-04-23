-- Weapon action hooks: overheat bridge, vent translation, peril guard,
-- _may_fire() validation, ADS logging, and diagnostic weapon logging.
local DEFAULT_WARP_WEAPON_PERIL_THRESHOLD = 0.99

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit
local _perf
local _ammo
local _is_enabled
local _is_weakspot_aim_enabled
local _close_range_ranged_policy
local _warp_weapon_peril_threshold
local _missing_shoot_extension_warned = {}

local NORMAL_RANGED_AMMO_THRESHOLD = 0.5
local BETTERBOTS_RANGED_AMMO_THRESHOLD = 0.2

local OVERHEAT_PATCH_SENTINEL = "__bb_overheat_slot_percentage_installed"
local SHOOT_ACTION_PATCH_SENTINEL = "__bb_weapon_action_bt_bot_shoot_action_installed"
local _shoot_action_hooks_installed = false
local _missing_bt_bot_shoot_action_warned = false

-- One-shot set: each unique bot:template:action:raw_input combo logged once
-- per load. Mirrors the ability_queue.lua context dump pattern.
local _weapon_logged_combos = {}
local _stream_action_logged_combos = {}
local _weakspot_aim_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _stale_shoot_action_logged_scratchpads = setmetatable({}, { __mode = "k" })

local STREAM_CONFIRM_ACTIONS = {
	flamer_p1_m1 = {
		brace_pressed = "brace_start",
		shoot_braced = "stream_fire",
		shoot_braced_release = "fire_release",
		brace_release = "brace_end",
	},
	forcestaff_p2_m1 = {
		trigger_charge_flame = "stream_fire",
		charge_release = "charge_release",
	},
}

local VOIDBLAST_TEMPLATE_NAME = "forcestaff_p1_m1"
local VOIDBLAST_CHARGE_ACTION_NAME = "action_charge"
-- forcestaff_p1_m1 action_charge chains into action_trigger_explosion in the
-- decompiled weapon template, so this is the charged release input we must force.
local VOIDBLAST_CHARGED_FIRE_INPUT = "trigger_explosion"
-- Keep the lead bounded to the charge window; longer prediction drifts too far
-- before the shot can actually release.
local VOIDBLAST_MIN_LEAD_TIME = 0.3
local VOIDBLAST_MAX_LEAD_TIME = 0.6
local _voidblast_anchor_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _voidblast_fallback_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _voidblast_retarget_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _bt_shoot_scratchpad_context = setmetatable({}, { __mode = "k" })

local function _find_action_for_start_input(actions, input_name)
	for action_name, action in pairs(actions or {}) do
		if action.start_input == input_name then
			return action_name, action
		end
	end

	return nil, nil
end

local function _is_head_spine_aim_table(aim_at_node)
	if type(aim_at_node) ~= "table" then
		return false
	end

	local has_head = false
	local has_spine = false

	for i = 1, #aim_at_node do
		local node_name = aim_at_node[i]
		if node_name == "j_head" then
			has_head = true
		elseif node_name == "j_spine" then
			has_spine = true
		end
	end

	return has_head and has_spine
end

local function _find_unaim_action_for_action(weapon_template, action)
	local actions = weapon_template and weapon_template.actions or {}
	local unaim_input = action and action.stop_input
	if unaim_input then
		local unaim_action_name = _find_action_for_start_input(actions, unaim_input)

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

local function _has_hold_start_input(weapon_template, input_name)
	local input_def = weapon_template and weapon_template.action_inputs and weapon_template.action_inputs[input_name]
	local seq = input_def and input_def.input_sequence
	local first = seq and seq[1]

	return first and first.input == "action_two_hold" and first.value == true
end

local function _weapon_template_supports_input(weapon_template, input_name)
	if type(input_name) ~= "string" then
		return false
	end

	local action_inputs = weapon_template and weapon_template.action_inputs or nil

	return type(action_inputs) == "table" and action_inputs[input_name] ~= nil or false
end

local function _clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad)
	if not scratchpad then
		return false
	end

	local changed = false

	if
		scratchpad.aim_action_input
		and not _weapon_template_supports_input(weapon_template, scratchpad.aim_action_input)
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
		and not _weapon_template_supports_input(weapon_template, scratchpad.unaim_action_input)
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

local function _find_bt_shoot_aim_chain(weapon_template, aim_fire_input)
	for action_name, action in pairs(weapon_template and weapon_template.actions or {}) do
		local start_input = action.start_input
		if start_input and _has_hold_start_input(weapon_template, start_input) then
			local chain_entry = (action.allowed_chain_actions or {})[aim_fire_input]
			if chain_entry then
				local unaim_input, unaim_action_name = _find_unaim_action_for_action(weapon_template, action)

				return start_input, action_name, unaim_input, unaim_action_name
			end
		end
	end

	return nil, nil, nil, nil
end

local function _weapon_log_context(unit)
	local bot_slot = _bot_slot_for_unit(unit) or "?"
	local wielded_slot = "none"
	local weapon_template_name = "none"
	local warp_charge_template_name = "none"
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	if unit_data_extension then
		local inventory_component = unit_data_extension:read_component("inventory")
		local weapon_action_component = unit_data_extension:read_component("weapon_action")
		local weapon_tweaks_component = unit_data_extension:read_component("weapon_tweak_templates")
		wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
		weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
		warp_charge_template_name = weapon_tweaks_component and weapon_tweaks_component.warp_charge_template_name
			or "none"
	end

	return bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name
end

local M = {}

function M._stream_action_phase(template_name, action_input)
	local actions = STREAM_CONFIRM_ACTIONS[template_name]

	return actions and actions[action_input] or nil
end

function M.log_stream_action(bot_slot, template_name, action_input)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end

	local phase = M._stream_action_phase(template_name, action_input)
	if not phase then
		return false
	end

	local combo_key = tostring(bot_slot) .. ":" .. tostring(template_name) .. ":" .. tostring(action_input)
	if _stream_action_logged_combos[combo_key] then
		return true
	end

	_stream_action_logged_combos[combo_key] = true
	_debug_log(
		"stream_action:" .. combo_key,
		_fixed_time(),
		"stream action queued for "
			.. tostring(template_name)
			.. " via "
			.. tostring(action_input)
			.. " (phase="
			.. tostring(phase)
			.. ", bot="
			.. tostring(bot_slot)
			.. ")"
	)

	return true
end

function M.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
	if not unit or not weapon_template or not scratchpad or not scratchpad.aim_at_node then
		return nil
	end

	local attack_meta_data = weapon_template.attack_meta_data or {}
	if not _is_head_spine_aim_table(attack_meta_data.aim_at_node) then
		return nil
	end

	if scratchpad.aim_at_node ~= "j_head" and scratchpad.aim_at_node ~= "j_spine" then
		return nil
	end

	local bot_slot, _, weapon_template_name = _weapon_log_context(unit)

	return {
		bot_slot = bot_slot,
		weapon_template_name = weapon_template_name,
		selected_node = scratchpad.aim_at_node,
	}
end

function M.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end
	if _is_weakspot_aim_enabled and not _is_weakspot_aim_enabled() then
		return false
	end

	if _weakspot_aim_logged_scratchpads[scratchpad] then
		return true
	end

	local context = M.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
	if not context then
		return false
	end

	_weakspot_aim_logged_scratchpads[scratchpad] = true
	_debug_log(
		"weakspot_aim:" .. tostring(unit),
		_fixed_time(),
		"weakspot aim selected "
			.. tostring(context.selected_node)
			.. " (weapon="
			.. tostring(context.weapon_template_name)
			.. ", bot="
			.. tostring(context.bot_slot)
			.. ")"
	)

	return true
end

function M._normalize_bt_shoot_scratchpad(weapon_template, scratchpad)
	if not weapon_template or not scratchpad then
		return false
	end

	if not scratchpad.aim_fire_action_input then
		return _clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad)
	end

	local aim_input, aim_action_name, unaim_input, unaim_action_name =
		_find_bt_shoot_aim_chain(weapon_template, scratchpad.aim_fire_action_input)
	if not aim_input then
		return _clear_stale_bt_shoot_aim_inputs(weapon_template, scratchpad)
	end

	local changed = false

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

local function _current_weapon_action_template_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.template_name or nil
end

local function _current_weapon_action_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.current_action_name or nil
end

local function _scratchpad_player_unit(scratchpad)
	local action_input_extension = scratchpad and scratchpad.action_input_extension or nil
	local unit = action_input_extension and action_input_extension._betterbots_player_unit or nil

	return unit or scratchpad and scratchpad.__bb_weakspot_self_unit or nil
end

local function _parser_accepts_weapon_action_input(action_input_extension, template_name, action_input)
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

local function _should_suppress_stale_shoot_action(scratchpad, action_input)
	local action_input_extension = scratchpad and scratchpad.action_input_extension or nil
	local unit = _scratchpad_player_unit(scratchpad)
	local template_name = _current_weapon_action_template_name(unit)
	if not action_input_extension or not template_name then
		return false, template_name
	end
	if type(action_input) ~= "string" then
		return true, template_name
	end

	return not _parser_accepts_weapon_action_input(action_input_extension, template_name, action_input), template_name
end

local function _log_stale_shoot_action(scratchpad, phase, action_input, template_name)
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

	_debug_log(
		"stale_shoot_action:" .. tostring(phase) .. ":" .. tostring(template_name or "unknown"),
		_fixed_time(),
		"suppressed stale shoot "
			.. tostring(phase)
			.. " input "
			.. tostring(action_input)
			.. " for "
			.. tostring(template_name or "unknown")
	)
end

local function _is_voidblast_staff(scratchpad)
	local unit = _scratchpad_player_unit(scratchpad)

	return _current_weapon_action_template_name(unit) == VOIDBLAST_TEMPLATE_NAME
end

local function _is_voidblast_charge_active(scratchpad)
	if not _is_voidblast_staff(scratchpad) then
		return false
	end

	if scratchpad and scratchpad.charging_shot then
		return true
	end

	local unit = _scratchpad_player_unit(scratchpad)
	local current_action_name = _current_weapon_action_name(unit)
	if current_action_name == VOIDBLAST_CHARGE_ACTION_NAME then
		return true
	end

	return scratchpad and scratchpad.aiming_shot and scratchpad.aim_action_input == "charge" or false
end

local function _should_lock_voidblast_anchor(scratchpad)
	return scratchpad and _is_voidblast_charge_active(scratchpad) or false
end

local function _voidblast_charged_fire_input(scratchpad)
	if not _is_voidblast_staff(scratchpad) then
		return nil
	end

	local aim_fire_action_input = scratchpad and scratchpad.aim_fire_action_input or nil
	local fire_action_input = scratchpad and scratchpad.fire_action_input or nil

	if aim_fire_action_input and aim_fire_action_input ~= fire_action_input then
		return aim_fire_action_input
	end

	return VOIDBLAST_CHARGED_FIRE_INPUT
end

local function _forced_bt_shoot_fire_input(scratchpad)
	if not scratchpad then
		return nil
	end

	if _is_voidblast_charge_active(scratchpad) then
		local fire_action_input = scratchpad.fire_action_input
		local charged_fire_input = _voidblast_charged_fire_input(scratchpad)
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
		local charged_fire_input = _voidblast_charged_fire_input(scratchpad)
		if charged_fire_input and charged_fire_input ~= fire_action_input then
			return charged_fire_input
		end
	end

	return nil
end

local function _should_force_voidblast_charged_fire(scratchpad)
	return scratchpad and _is_voidblast_charge_active(scratchpad) and _forced_bt_shoot_fire_input(scratchpad) ~= nil
		or false
end

local function _clear_voidblast_anchor(scratchpad)
	if scratchpad then
		scratchpad.__bb_voidblast_anchor = nil
	end
end

local function _vector3_flat(v)
	if Vector3 and Vector3.flat then
		return Vector3.flat(v)
	end

	return nil
end

local function _vector3_normalize(v)
	if Vector3 and Vector3.normalize then
		return Vector3.normalize(v)
	end

	return nil
end

local function _vector3_up()
	if Vector3 and Vector3.up then
		return Vector3.up()
	end

	return nil
end

local function _vector3_length_squared(v)
	if Vector3 and Vector3.length_squared then
		return Vector3.length_squared(v)
	end

	return v and (v.x * v.x + v.y * v.y + v.z * v.z) or 0
end

local function _voidblast_lead_time(scratchpad)
	local minimum_charge_time = scratchpad and scratchpad.minimum_charge_time or 0
	local lead_time = math.max(VOIDBLAST_MIN_LEAD_TIME, minimum_charge_time or 0)

	return math.min(VOIDBLAST_MAX_LEAD_TIME, lead_time)
end

local function _voidblast_aim_rotation(current_position, anchor_position)
	if not current_position or not anchor_position then
		return nil, "missing_anchor_position"
	end

	local delta = anchor_position - current_position
	if _vector3_length_squared(delta) <= 1e-6 then
		return nil, "degenerate_anchor_delta"
	end

	local direction = _vector3_normalize(delta)
	local up = _vector3_up()
	if not direction or not up or not Quaternion or not Quaternion.look then
		return nil, "missing_rotation_math"
	end

	return Quaternion.look(direction, up), nil
end

local function _log_voidblast_fallback(scratchpad, self_unit, target_unit, reason)
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

local function _resolve_voidblast_anchor_state(self, self_unit, scratchpad, target_unit)
	if not _should_lock_voidblast_anchor(scratchpad) then
		_clear_voidblast_anchor(scratchpad)
		return nil, nil
	end

	local state = scratchpad.__bb_voidblast_anchor
	if state and state.position then
		return state, nil
	end

	local target_position = POSITION_LOOKUP and target_unit and POSITION_LOOKUP[target_unit] or nil
	if not target_position then
		return nil, "missing_target_position"
	end

	local lead_time = _voidblast_lead_time(scratchpad)
	local target_velocity = self
			and self._target_velocity
			and self:_target_velocity(target_unit, scratchpad.target_breed)
		or nil
	local anchor_position = target_position
	local flat_velocity = target_velocity and _vector3_flat(target_velocity) or nil
	if flat_velocity then
		anchor_position = anchor_position + flat_velocity * lead_time
	end

	state = {
		target_unit = target_unit,
		position = anchor_position,
		lead_time = lead_time,
	}
	scratchpad.__bb_voidblast_anchor = state

	if _debug_enabled and _debug_enabled() and not _voidblast_anchor_logged_scratchpads[scratchpad] then
		_voidblast_anchor_logged_scratchpads[scratchpad] = true
		_debug_log(
			"voidblast_anchor:" .. tostring(self_unit) .. ":" .. tostring(target_unit),
			_fixed_time(),
			"voidblast anchor locked (lead="
				.. string.format("%.2f", lead_time)
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
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_perf = deps.perf
	_ammo = deps.ammo
	_is_enabled = deps.is_enabled
	_is_weakspot_aim_enabled = deps.is_weakspot_aim_enabled or function()
		return true
	end
	_close_range_ranged_policy = deps.close_range_ranged_policy
	_warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold
		or function()
			return DEFAULT_WARP_WEAPON_PERIL_THRESHOLD
		end
	_missing_shoot_extension_warned = {}
	_missing_bt_bot_shoot_action_warned = false
	_stream_action_logged_combos = {}
	_shoot_action_hooks_installed = false
	_voidblast_anchor_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_voidblast_fallback_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_voidblast_retarget_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_bt_shoot_scratchpad_context = setmetatable({}, { __mode = "k" })
end

local function _ammo_api()
	if _ammo ~= nil then
		return _ammo or nil
	end

	local ok, ammo = pcall(require, "scripts/utilities/ammo")
	if ok then
		_ammo = ammo
	elseif _mod and _mod.warning then
		_ammo = false
		_mod:warning("BetterBots: ammo utility unavailable; dead-zone ranged fire detection disabled")
	end

	return _ammo or nil
end

local function _dead_zone_target_breed(unit)
	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local perception = blackboard and blackboard.perception
	local target_unit = perception and perception.target_enemy
	if not target_unit then
		return nil
	end

	local target_unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if not target_unit_data_extension or not target_unit_data_extension.breed then
		return nil
	end

	return target_unit_data_extension:breed()
end

function M.dead_zone_ranged_fire_context(unit, action_input)
	if action_input ~= "shoot_pressed" and action_input ~= "shoot_charge" then
		return nil
	end

	local bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name = _weapon_log_context(unit)
	if wielded_slot ~= "slot_secondary" or warp_charge_template_name ~= "none" then
		return nil
	end

	local ammo = _ammo_api()
	local ammo_pct = ammo and ammo.current_slot_percentage and ammo.current_slot_percentage(unit, "slot_secondary")
		or nil
	if not ammo_pct or ammo_pct <= BETTERBOTS_RANGED_AMMO_THRESHOLD or ammo_pct > NORMAL_RANGED_AMMO_THRESHOLD then
		return nil
	end

	local breed = _dead_zone_target_breed(unit)
	local tags = breed and breed.tags or nil
	if tags and (tags.elite or tags.special or tags.monster) then
		return nil
	end

	return {
		action_input = action_input,
		ammo_pct = ammo_pct,
		bot_slot = bot_slot,
		target_breed_name = breed and breed.name or "unknown",
		weapon_template_name = weapon_template_name,
	}
end

function M.log_dead_zone_ranged_fire(unit, action_input)
	local context = M.dead_zone_ranged_fire_context(unit, action_input)
	if not context then
		return false
	end

	_debug_log(
		"ranged_dead_zone_fire:" .. tostring(context.bot_slot) .. ":" .. tostring(context.weapon_template_name),
		_fixed_time(),
		"ranged dead-zone override kept normal shot (ammo="
			.. string.format("%.2f", context.ammo_pct)
			.. ", target="
			.. tostring(context.target_breed_name)
			.. ", weapon="
			.. tostring(context.weapon_template_name)
			.. ", action="
			.. tostring(context.action_input)
			.. ")",
		10
	)

	return true
end

function M.register_hooks(deps)
	local should_lock_weapon_switch = deps.should_lock_weapon_switch
	local should_block_wield_input = deps.should_block_wield_input or should_lock_weapon_switch
	local should_block_weapon_action_input = deps.should_block_weapon_action_input
	local rewrite_weapon_action_input = deps.rewrite_weapon_action_input
	local observe_queued_weapon_action = deps.observe_queued_weapon_action
	local install_weakspot_aim = deps.install_weakspot_aim

	-- Overheat bridge (#30): warp weapons have no overheat_configuration,
	-- so slot_percentage returns 0 and the BT vent node never fires. Bridge
	-- warp_charge.current_percentage so should_vent_overheat triggers for peril.
	-- Also guards against plasma-style nested thresholds that crash vanilla.
	_mod:hook_require("scripts/utilities/overheat", function(Overheat)
		if not Overheat or rawget(Overheat, OVERHEAT_PATCH_SENTINEL) then
			return
		end
		Overheat[OVERHEAT_PATCH_SENTINEL] = true

		local _orig_slot_percentage = Overheat.slot_percentage
		Overheat.slot_percentage = function(unit, slot_name, threshold_type)
			local vis_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
			if vis_ext then
				local cfg = Overheat.configuration(vis_ext, slot_name)
				if cfg and not cfg[threshold_type] then
					return 0
				end
				if not cfg then
					local ude = ScriptUnit.has_extension(unit, "unit_data_system")
					if ude then
						local tweaks = ude:read_component("weapon_tweak_templates")
						if tweaks and tweaks.warp_charge_template_name ~= "none" then
							local warp = ude:read_component("warp_charge")
							if warp then
								return warp.current_percentage
							end
						end
					end
				end
			end
			return _orig_slot_percentage(unit, slot_name, threshold_type)
		end
	end)

	-- Shoot-action hooks: weakspot handoff, scratchpad cleanup, close-range ADS
	-- policy, and the _may_fire() validation fix.
	local _ads_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action",
		function(BtBotShootAction)
			if not BtBotShootAction then
				if not _missing_bt_bot_shoot_action_warned and _mod and _mod.warning then
					_missing_bt_bot_shoot_action_warned = true
					_mod:warning("BetterBots: bt_bot_shoot_action hook_require resolved nil")
				end
				return
			end
			if _shoot_action_hooks_installed or rawget(BtBotShootAction, SHOOT_ACTION_PATCH_SENTINEL) then
				return
			end
			_shoot_action_hooks_installed = true
			BtBotShootAction[SHOOT_ACTION_PATCH_SENTINEL] = true

			local PlayerUnitVisualLoadout =
				require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
			local _close_range_ads_logged_scratchpads = setmetatable({}, { __mode = "k" })

			if install_weakspot_aim then
				install_weakspot_aim(BtBotShootAction)
			end

			_mod:hook_safe(BtBotShootAction, "enter", function(_self, unit, _breed, _blackboard, scratchpad)
				if _is_enabled and not _is_enabled() then
					return
				end

				if scratchpad then
					-- This is a post-hook, so the first _set_new_aim_target call inside
					-- vanilla enter cannot rely on __bb_weakspot_self_unit functionally.
					-- Today the field is only used for weakspot logging context.
					scratchpad.__bb_weakspot_self_unit = unit
				end

				local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
				local visual_loadout_extension = ScriptUnit.has_extension(unit, "visual_loadout_system")
				if not unit_data_extension or not visual_loadout_extension then
					local unit_key = tostring(unit)
					if _debug_enabled() then
						_debug_log(
							"shoot_scratchpad_missing_ext:" .. unit_key,
							_fixed_time(),
							"shoot scratchpad normalization skipped: missing unit_data_system or visual_loadout_system"
						)
					end
					if not _missing_shoot_extension_warned[unit_key] and _mod and _mod.warning then
						_missing_shoot_extension_warned[unit_key] = true
						_mod:warning(
							"BetterBots: shoot scratchpad normalization skipped for "
								.. unit_key
								.. " because unit_data_system or visual_loadout_system is missing"
						)
					end
					return
				end

				local inventory_component = unit_data_extension:read_component("inventory")
				local weapon_template =
					PlayerUnitVisualLoadout.wielded_weapon_template(visual_loadout_extension, inventory_component)
				if M._normalize_bt_shoot_scratchpad(weapon_template, scratchpad) and _debug_enabled() then
					_debug_log(
						"shoot_scratchpad_normalized:" .. tostring(unit),
						_fixed_time(),
						"normalized shoot scratchpad aim cleanup (aim="
							.. tostring(scratchpad.aim_action_input)
							.. ", unaim="
							.. tostring(scratchpad.unaim_action_input)
							.. ")"
					)
				end

				scratchpad.close_range_ranged_policy = _close_range_ranged_policy
						and _close_range_ranged_policy(weapon_template)
					or nil
				M.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
			end)

			_mod:hook(BtBotShootAction, "_update_aim", function(func, self, unit, scratchpad, action_data, dt, t)
				if _is_enabled and not _is_enabled() then
					return func(self, unit, scratchpad, action_data, dt, t)
				end

				local perception_component = scratchpad and scratchpad.perception_component or nil
				local locked_target = scratchpad
						and scratchpad.__bb_voidblast_anchor
						and scratchpad.__bb_voidblast_anchor.target_unit
					or nil
				local should_lock = _should_lock_voidblast_anchor(scratchpad) and perception_component and locked_target
				local locked_perception_component = should_lock and perception_component or nil
				local original_target = locked_perception_component and locked_perception_component.target_enemy or nil

				_bt_shoot_scratchpad_context[unit] = scratchpad
				if locked_perception_component and original_target ~= locked_target then
					if
						_debug_enabled
						and _debug_enabled()
						and not _voidblast_retarget_logged_scratchpads[scratchpad]
					then
						_voidblast_retarget_logged_scratchpads[scratchpad] = true
						_debug_log(
							"voidblast_retarget:" .. tostring(_scratchpad_player_unit(scratchpad)),
							_fixed_time(),
							"voidblast anchor held through retarget (from="
								.. tostring(original_target)
								.. ", to="
								.. tostring(locked_target)
								.. ")"
						)
					end

					locked_perception_component.target_enemy = locked_target
				end

				local ok, done, evaluate = pcall(func, self, unit, scratchpad, action_data, dt, t)
				_bt_shoot_scratchpad_context[unit] = nil

				if locked_perception_component and original_target ~= locked_target then
					locked_perception_component.target_enemy = original_target
				end

				if not ok then
					if _debug_enabled and _debug_enabled() then
						_debug_log(
							"voidblast_retarget_restore_error:" .. tostring(_scratchpad_player_unit(scratchpad) or unit),
							t,
							"restored Voidblast locked target after vanilla _update_aim error"
								.. " (bot="
								.. tostring(_scratchpad_player_unit(scratchpad) or unit)
								.. ", target="
								.. tostring(original_target)
								.. ")",
							nil,
							"info"
						)
					end
					error(done, 0)
				end

				return done, evaluate
			end)

			_mod:hook(
				BtBotShootAction,
				"_wanted_aim_rotation",
				function(
					func,
					self,
					self_unit,
					target_unit,
					target_breed,
					current_position,
					projectile_template,
					aim_at_node
				)
					if _is_enabled and not _is_enabled() then
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					local scratchpad = _bt_shoot_scratchpad_context[self_unit]
					local state, state_reason =
						_resolve_voidblast_anchor_state(self, self_unit, scratchpad, target_unit)
					if not state then
						if state_reason then
							_log_voidblast_fallback(scratchpad, self_unit, target_unit, state_reason)
						end
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					local wanted_rotation, rotation_reason = _voidblast_aim_rotation(current_position, state.position)
					if not wanted_rotation then
						if rotation_reason then
							_log_voidblast_fallback(scratchpad, self_unit, target_unit, rotation_reason)
						end
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					return wanted_rotation, state.position
				end
			)

			_mod:hook(BtBotShootAction, "_should_aim", function(func, self, t, scratchpad, action_data)
				if _is_enabled and not _is_enabled() then
					return func(self, t, scratchpad, action_data)
				end

				local should_aim = func(self, t, scratchpad, action_data)
				if not should_aim then
					return false
				end

				local policy = scratchpad and scratchpad.close_range_ranged_policy
				local perception_component = scratchpad and scratchpad.perception_component or nil
				local target_enemy_distance = perception_component and perception_component.target_enemy_distance or nil
				local target_enemy_distance_sq = target_enemy_distance and target_enemy_distance * target_enemy_distance
					or nil

				if
					not policy
					or not policy.hipfire_distance_sq
					or not target_enemy_distance_sq
					or target_enemy_distance_sq > policy.hipfire_distance_sq
				then
					local suppress, template_name =
						_should_suppress_stale_shoot_action(scratchpad, scratchpad and scratchpad.aim_action_input)
					if suppress then
						_log_stale_shoot_action(
							scratchpad,
							"aim",
							scratchpad and scratchpad.aim_action_input,
							template_name
						)
						return false
					end
					return should_aim
				end

				if not _close_range_ads_logged_scratchpads[scratchpad] and _debug_enabled() then
					_close_range_ads_logged_scratchpads[scratchpad] = true
					_debug_log(
						"close_range_hipfire:" .. tostring(scratchpad),
						_fixed_time(),
						"close-range hipfire suppressed ADS (family="
							.. tostring(policy.family or "?")
							.. ", distance="
							.. string.format("%.2f", target_enemy_distance)
							.. ")"
					)
				end

				return false
			end)

			_mod:hook(BtBotShootAction, "_start_aiming", function(func, self, t, scratchpad)
				if _is_enabled and not _is_enabled() then
					return func(self, t, scratchpad)
				end

				local suppress, template_name =
					_should_suppress_stale_shoot_action(scratchpad, scratchpad and scratchpad.aim_action_input)
				if suppress then
					if scratchpad then
						scratchpad.aiming_shot = false
						scratchpad.aim_done_t = 0
					end
					_log_stale_shoot_action(
						scratchpad,
						"aim",
						scratchpad and scratchpad.aim_action_input,
						template_name
					)
					return nil
				end

				local result = func(self, t, scratchpad)
				if scratchpad and not _ads_logged_scratchpads[scratchpad] then
					_ads_logged_scratchpads[scratchpad] = true
					if _debug_enabled() then
						local gestalt = scratchpad.ranged_gestalt or "?"
						_mod:echo("BetterBots DEBUG: bot ADS confirmed (ranged_gestalt=" .. tostring(gestalt) .. ")")
					end
				end
				return result
			end)

			_mod:hook(BtBotShootAction, "_stop_aiming", function(func, self, scratchpad)
				if _is_enabled and not _is_enabled() then
					return func(self, scratchpad)
				end

				local suppress, template_name =
					_should_suppress_stale_shoot_action(scratchpad, scratchpad and scratchpad.unaim_action_input)
				if suppress then
					if scratchpad and scratchpad.aiming_shot then
						scratchpad.aiming_shot = false
						scratchpad.aim_done_t = 0
					end
					_log_stale_shoot_action(
						scratchpad,
						"unaim",
						scratchpad and scratchpad.unaim_action_input,
						template_name
					)
					return nil
				end

				return func(self, scratchpad)
			end)

			-- #43: vanilla _may_fire() validates fire_action_input even though
			-- _fire() dispatches aim_fire_action_input while aiming. Swap only
			-- for this validation call so ADS/charge weapons validate the input
			-- they will actually queue.
			local _may_fire_logged = setmetatable({}, { __mode = "k" })
			_mod:hook(BtBotShootAction, "_may_fire", function(func, self, unit, scratchpad, range_squared, t)
				if _is_enabled and not _is_enabled() then
					return func(self, unit, scratchpad, range_squared, t)
				end
				local perf_t0 = _perf and _perf.begin()
				local forced_fire_action_input = _forced_bt_shoot_fire_input(scratchpad)
				if not scratchpad or not forced_fire_action_input then
					local result = func(self, unit, scratchpad, range_squared, t)
					if perf_t0 then
						_perf.finish("weapon_action.may_fire", perf_t0)
					end
					return result
				end

				if not _may_fire_logged[scratchpad] and _debug_enabled() then
					_may_fire_logged[scratchpad] = true
					_debug_log(
						"may_fire_swap:" .. tostring(forced_fire_action_input),
						_fixed_time(),
						"_may_fire swap: fire="
							.. tostring(scratchpad.fire_action_input)
							.. " -> aim_fire="
							.. tostring(forced_fire_action_input)
					)
				end

				local fire_action_input = scratchpad.fire_action_input
				scratchpad.fire_action_input = forced_fire_action_input

				local may_fire = func(self, unit, scratchpad, range_squared, t)

				scratchpad.fire_action_input = fire_action_input
				if perf_t0 then
					_perf.finish("weapon_action.may_fire", perf_t0)
				end

				return may_fire
			end)

			local _voidblast_fire_override_logged = setmetatable({}, { __mode = "k" })
			_mod:hook(BtBotShootAction, "_fire", function(func, self, scratchpad, action_data, bot_unit_input, t)
				if _is_enabled and not _is_enabled() then
					return func(self, scratchpad, action_data, bot_unit_input, t)
				end

				if not _should_force_voidblast_charged_fire(scratchpad) then
					return func(self, scratchpad, action_data, bot_unit_input, t)
				end

				local charged_fire_input = _forced_bt_shoot_fire_input(scratchpad)
				local aiming_shot = scratchpad.aiming_shot
				local aim_fire_action_input = scratchpad.aim_fire_action_input
				scratchpad.aiming_shot = true
				scratchpad.aim_fire_action_input = charged_fire_input

				if not _voidblast_fire_override_logged[scratchpad] and _debug_enabled() then
					_voidblast_fire_override_logged[scratchpad] = true
					_debug_log(
						"voidblast_fire_override:" .. tostring(_scratchpad_player_unit(scratchpad)),
						_fixed_time(),
						"voidblast charged fire override (fire="
							.. tostring(scratchpad.fire_action_input)
							.. " -> charged_fire="
							.. tostring(charged_fire_input)
							.. ")"
					)
				end

				local ok, result_a, result_b, result_c, result_d =
					pcall(func, self, scratchpad, action_data, bot_unit_input, t)
				scratchpad.aim_fire_action_input = aim_fire_action_input
				scratchpad.aiming_shot = aiming_shot

				if not ok then
					error(result_a, 0)
				end

				return result_a, result_b, result_c, result_d
			end)
		end
	)

	-- bot_queue_action_input: wield lock, vent translation, peril guard,
	-- and diagnostic weapon logging.
	_mod:hook_require(
		"scripts/extension_systems/action_input/player_unit_action_input_extension",
		function(PlayerUnitActionInputExtension)
			_mod:hook_safe(PlayerUnitActionInputExtension, "extensions_ready", function(self, _world, unit)
				self._betterbots_player_unit = unit
			end)

			_mod:hook(
				PlayerUnitActionInputExtension,
				"bot_queue_action_input",
				function(func, self, id, action_input, raw_input)
					if _is_enabled and not _is_enabled() then
						return func(self, id, action_input, raw_input)
					end
					local perf_t0 = _perf and _perf.begin()
					local unit = self._betterbots_player_unit
					local original_action_input = action_input
					if unit and id == "weapon_action" and action_input == "wield" then
						local should_block, ability_name = should_block_wield_input(unit)
						if should_block then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								local _, _, lock_reason = should_lock_weapon_switch(unit)
								_debug_log(
									"lock_wield:" .. tostring(ability_name),
									fixed_t,
									"blocked weapon switch while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(lock_reason or "sequence")
										.. " (raw_input="
										.. tostring(raw_input)
										.. ")"
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					if unit and id == "weapon_action" and rewrite_weapon_action_input then
						local rewritten_action_input, rewritten_raw_input =
							rewrite_weapon_action_input(unit, action_input, raw_input)
						action_input = rewritten_action_input or action_input
						if rewritten_raw_input ~= nil then
							raw_input = rewritten_raw_input
						end
					end

					if unit and id == "weapon_action" and (action_input == "zoom" or action_input == "unzoom") then
						local template_name = _current_weapon_action_template_name(unit)
						if
							template_name
							and not _parser_accepts_weapon_action_input(self, template_name, action_input)
						then
							if _debug_enabled() then
								_debug_log(
									"drop_unsupported_weapon_action:"
										.. tostring(template_name)
										.. ":"
										.. tostring(action_input),
									_fixed_time(),
									"dropped unsupported queued weapon action "
										.. tostring(action_input)
										.. " for "
										.. tostring(template_name)
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					if
						unit
						and id == "weapon_action"
						and action_input ~= "wield"
						and should_block_weapon_action_input
					then
						local should_block, ability_name, block_reason =
							should_block_weapon_action_input(unit, action_input)
						if should_block then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								_debug_log(
									"lock_weapon_action:" .. tostring(ability_name) .. ":" .. tostring(action_input),
									fixed_t,
									"blocked foreign weapon action "
										.. tostring(action_input)
										.. " while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(block_reason or "sequence")
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					-- BtBotReloadAction queues "reload" but warp weapons have
					-- "vent" not "reload". Translate before the peril guard so
					-- venting is not blocked at critical peril.
					if unit and id == "weapon_action" and action_input == "reload" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local tweaks = ude:read_component("weapon_tweak_templates")
							if tweaks and tweaks.warp_charge_template_name ~= "none" then
								if _debug_enabled() then
									_debug_log(
										"vent_translate:" .. tostring(unit),
										_fixed_time(),
										"translated reload -> vent (warp weapon)"
									)
								end
								action_input = "vent"
							end
						end
					end

					if unit and id == "weapon_action" and action_input ~= "wield" and action_input ~= "vent" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local warp = ude:read_component("warp_charge")
							local peril_threshold = _warp_weapon_peril_threshold and _warp_weapon_peril_threshold()
								or DEFAULT_WARP_WEAPON_PERIL_THRESHOLD
							if warp and warp.current_percentage >= peril_threshold then
								local tweaks = ude:read_component("weapon_tweak_templates")
								if tweaks and tweaks.warp_charge_template_name ~= "none" then
									if _debug_enabled() then
										_debug_log(
											"peril_block:" .. tostring(action_input),
											_fixed_time(),
											"blocked "
												.. tostring(action_input)
												.. " (peril="
												.. string.format("%.0f%%", warp.current_percentage * 100)
												.. ", warp weapon)"
										)
									end
									if perf_t0 then
										_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
									end
									return nil
								end
							end
						end
					end

					-- Log bot weapon actions (except wield) with bot/template tags
					-- so charged inputs can be attributed to the correct bot and
					-- staff family. One-shot per unique combo.
					if id == "weapon_action" and action_input ~= "wield" and _debug_enabled() then
						local bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name =
							_weapon_log_context(unit)
						local combo_key = tostring(bot_slot)
							.. ":"
							.. tostring(weapon_template_name)
							.. ":"
							.. tostring(action_input)
							.. ":"
							.. tostring(raw_input)
						if not _weapon_logged_combos[combo_key] then
							_weapon_logged_combos[combo_key] = true
							_debug_log(
								"bot_weapon:" .. combo_key,
								_fixed_time(),
								"bot weapon: bot="
									.. tostring(bot_slot)
									.. " slot="
									.. tostring(wielded_slot)
									.. " weapon_template="
									.. tostring(weapon_template_name)
									.. " warp_template="
									.. tostring(warp_charge_template_name)
									.. " action="
									.. tostring(action_input)
									.. " raw_input="
									.. tostring(raw_input)
							)
						end

						M.log_dead_zone_ranged_fire(unit, action_input)
					end

					local result = func(self, id, action_input, raw_input)
					if result ~= nil and id == "weapon_action" and unit then
						if observe_queued_weapon_action then
							observe_queued_weapon_action(unit, action_input, original_action_input)
						end
					end
					if result ~= nil and id == "weapon_action" and unit and _debug_enabled() then
						local bot_slot, _, weapon_template_name = _weapon_log_context(unit)
						M.log_stream_action(bot_slot, weapon_template_name, action_input)
					end
					if perf_t0 then
						_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
					end
					return result
				end
			)
		end
	)

	-- Wield slot redirect: keep combat ability slot wielded during item fallback.
	_mod:hook_require(
		"scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout",
		function(PlayerUnitVisualLoadout)
			_mod:hook(
				PlayerUnitVisualLoadout,
				"wield_slot",
				function(func, slot_to_wield, player_unit, t, skip_wield_action)
					local perf_t0 = _perf and _perf.begin()
					local should_lock, ability_name, lock_reason, slot_to_keep = should_lock_weapon_switch(player_unit)
					if should_lock then
						slot_to_keep = slot_to_keep or "slot_combat_ability"
						if slot_to_wield ~= slot_to_keep then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								_debug_log(
									"lock_wield_direct:" .. tostring(ability_name),
									fixed_t,
									"redirected wield_slot("
										.. tostring(slot_to_wield)
										.. ") -> "
										.. tostring(slot_to_keep)
										.. " while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(lock_reason)
								)
							end
							local result = func(slot_to_keep, player_unit, t, skip_wield_action)
							if perf_t0 then
								_perf.finish("weapon_action.wield_slot", perf_t0)
							end
							return result
						end
					end

					local result = func(slot_to_wield, player_unit, t, skip_wield_action)
					if perf_t0 then
						_perf.finish("weapon_action.wield_slot", perf_t0)
					end
					return result
				end
			)
		end
	)

	-- WeaponSystem.queue_perils_of_the_warp_elite_kills_achievement calls
	-- player:account_id() unconditionally; bot-backed player objects can return nil.
	_mod:hook_require("scripts/extension_systems/weapon/weapon_system", function(WeaponSystem)
		_mod:hook(
			WeaponSystem,
			"queue_perils_of_the_warp_elite_kills_achievement",
			function(func, self, player, explosion_queue_index)
				local account_id = nil
				if player and type(player.account_id) == "function" then
					account_id = player:account_id()
				end

				if account_id == nil then
					_debug_log(
						"skip_perils_nil_account",
						_fixed_time(),
						"skipped perils achievement queue with nil account_id"
					)
					return nil
				end

				return func(self, player, explosion_queue_index)
			end
		)
	end)
end

return M
