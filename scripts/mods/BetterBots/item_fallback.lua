local _mod
local _debug_log
local _debug_enabled
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _last_charge_event_by_unit
local _fallback_queue_dumped_by_key
local _ITEM_WIELD_TIMEOUT_S
local _ITEM_SEQUENCE_RETRY_S
local _ITEM_CHARGE_CONFIRM_TIMEOUT_S
local _ITEM_DEFAULT_START_DELAY_S
local _event_log
local _bot_slot_for_unit

-- Late-bound cross-module refs, set via wire()
local _build_context
local _context_snapshot
local _fallback_state_snapshot
local _evaluate_item_heuristic

local function _emit_item_event(event_type, unit, ability_name, state, fixed_t, extra)
	if not _event_log or not _event_log.is_enabled() then
		return
	end

	local ev = {
		t = fixed_t,
		event = event_type,
		bot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or nil,
		ability = ability_name,
		stage = state.item_stage,
		profile = state.item_profile_name,
		attempt_id = state.attempt_id,
	}

	if extra then
		for k, v in pairs(extra) do
			ev[k] = v
		end
	end

	_event_log.emit(ev)
end

local LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY = {
	zealot_relic = true,
}

local LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
	adamant_area_buff_drone = true,
}

local ITEM_SEQUENCE_PROFILES = {
	channel = {
		required_inputs = { "channel", "wield_previous" },
		start_input = "channel",
		start_delay_after_wield = 0,
		unwield_input = nil,
		unwield_delay = 5.6,
		charge_confirm_timeout = 1.5,
	},
	press_release = {
		required_inputs = { "ability_pressed", "ability_released", "unwield_to_previous" },
		start_input = "ability_pressed",
		start_delay_after_wield = 0,
		followup_input = "ability_released",
		followup_delay = 0.6,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.7,
	},
	force_field_regular = {
		required_inputs = { "aim_force_field", "place_force_field", "unwield_to_previous" },
		start_input = "aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "place_force_field",
		followup_delay = 0.35,
		unwield_input = "unwield_to_previous",
		unwield_delay = 1.6,
		charge_confirm_timeout = 2.2,
	},
	force_field_instant = {
		required_inputs = { "instant_aim_force_field", "instant_place_force_field", "unwield_to_previous" },
		start_input = "instant_aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "instant_place_force_field",
		followup_delay = 0.12,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.5,
		charge_confirm_timeout = 2.0,
	},
	drone_regular = {
		required_inputs = { "aim_drone", "release_drone", "unwield_to_previous" },
		start_input = "aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "release_drone",
		followup_delay = 0.35,
		unwield_input = "unwield_to_previous",
		unwield_delay = 2.3,
		charge_confirm_timeout = 2.2,
	},
	drone_instant = {
		required_inputs = { "instant_aim_drone", "instant_release_drone", "unwield_to_previous" },
		start_input = "instant_aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "instant_release_drone",
		followup_delay = 0.1,
		unwield_input = "unwield_to_previous",
		unwield_delay = 1.1,
		charge_confirm_timeout = 2.0,
	},
}

local ITEM_DEFAULT_PROFILE_ORDER = {
	"channel",
	"press_release",
	"force_field_regular",
	"force_field_instant",
	"drone_regular",
	"drone_instant",
}

local ITEM_PROFILE_ORDER_BY_ABILITY = {
	zealot_relic = { "channel" },
	psyker_force_field = { "force_field_regular", "force_field_instant" },
	psyker_force_field_improved = { "force_field_regular", "force_field_instant" },
	psyker_force_field_dome = { "force_field_regular", "force_field_instant" },
	adamant_area_buff_drone = { "drone_regular", "drone_instant" },
	broker_ability_stimm_field = { "press_release" },
}

local function _reset_item_sequence_state(state, next_try_t)
	state.item_stage = nil
	state.item_ability_name = nil
	state.item_wield_deadline_t = nil
	state.item_stage_deadline_t = nil
	state.item_attempt_t = nil
	state.item_charge_confirmed = nil
	state.item_profile_name = nil
	state.item_profile_key = nil
	state.item_profile_count = nil
	state.item_start_input = nil
	state.item_wait_t = nil
	state.item_followup_input = nil
	state.item_followup_delay = nil
	state.item_unwield_input = nil
	state.item_unwield_delay = nil
	state.item_charge_confirm_timeout = nil

	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local function _ordered_item_profile_ids(ability_name)
	local ordered_ids = {}
	local seen = {}
	local preferred_ids = ITEM_PROFILE_ORDER_BY_ABILITY[ability_name]

	if preferred_ids then
		for i = 1, #preferred_ids do
			local profile_name = preferred_ids[i]

			if not seen[profile_name] then
				ordered_ids[#ordered_ids + 1] = profile_name
				seen[profile_name] = true
			end
		end
	end

	for i = 1, #ITEM_DEFAULT_PROFILE_ORDER do
		local profile_name = ITEM_DEFAULT_PROFILE_ORDER[i]

		if not seen[profile_name] then
			ordered_ids[#ordered_ids + 1] = profile_name
		end
	end

	return ordered_ids
end

local function _action_inputs_include_all(action_inputs, required_inputs)
	if not action_inputs then
		return false
	end

	for i = 1, #required_inputs do
		if action_inputs[required_inputs[i]] == nil then
			return false
		end
	end

	return true
end

local function _item_cast_sequences_for_weapon(ability_name, weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs
	if not action_inputs then
		return {}
	end

	local ordered_ids = _ordered_item_profile_ids(ability_name)
	local sequence_candidates = {}

	for i = 1, #ordered_ids do
		local profile_name = ordered_ids[i]
		local profile = ITEM_SEQUENCE_PROFILES[profile_name]

		if profile and _action_inputs_include_all(action_inputs, profile.required_inputs) then
			sequence_candidates[#sequence_candidates + 1] = {
				profile_name = profile_name,
				start_input = profile.start_input,
				start_delay_after_wield = profile.start_delay_after_wield,
				followup_input = profile.followup_input,
				followup_delay = profile.followup_delay,
				unwield_input = profile.unwield_input,
				unwield_delay = profile.unwield_delay,
				charge_confirm_timeout = profile.charge_confirm_timeout,
			}
		end
	end

	return sequence_candidates
end

local function _select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
	local sequence_candidates = _item_cast_sequences_for_weapon(ability_name, weapon_template)

	if #sequence_candidates == 0 then
		return nil
	end

	if not state.item_profile_index_by_key then
		state.item_profile_index_by_key = {}
	end

	local profile_key = ability_name .. ":" .. tostring(weapon_template_name)
	local selected_index = state.item_profile_index_by_key[profile_key] or 1
	local candidate_count = #sequence_candidates

	if selected_index > candidate_count then
		selected_index = 1
	end

	state.item_profile_index_by_key[profile_key] = selected_index

	return sequence_candidates[selected_index], profile_key, selected_index, candidate_count
end

local function _rotate_item_cast_profile(state)
	local profile_key = state.item_profile_key
	local profile_count = state.item_profile_count or 0
	local index_by_key = state.item_profile_index_by_key

	if not profile_key or not index_by_key or profile_count <= 1 then
		return false
	end

	local current_index = index_by_key[profile_key] or 1
	local next_index = current_index + 1
	if next_index > profile_count then
		next_index = 1
	end

	index_by_key[profile_key] = next_index
	return next_index ~= current_index
end

local function _schedule_item_sequence_retry(state, fixed_t, rotate_profile)
	if rotate_profile then
		_rotate_item_cast_profile(state)
	end

	_reset_item_sequence_state(state, fixed_t + _ITEM_SEQUENCE_RETRY_S)
end

local function schedule_retry(unit, fixed_t, retry_delay_s)
	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	local retry_t = fixed_t + (retry_delay_s or _ITEM_SEQUENCE_RETRY_S)
	local next_try_t = state.next_try_t
	if not next_try_t or retry_t < next_try_t then
		state.next_try_t = retry_t
	end
end

local function should_lock_weapon_switch(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	if not inventory_component or inventory_component.wielded_slot ~= "slot_combat_ability" then
		return false
	end

	local ability_name = _equipped_combat_ability_name(unit)
	local combat_ability_component = unit_data_extension:read_component("combat_ability")
	local combat_ability_active = combat_ability_component and combat_ability_component.active == true

	if combat_ability_active and LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY[ability_name] then
		return true, ability_name, "active"
	end

	local state = _fallback_state_by_unit[unit]
	local staged_ability_name = state and state.item_ability_name
	if
		state
		and state.item_stage
		and staged_ability_name
		and LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE[staged_ability_name]
	then
		return true, staged_ability_name, "sequence"
	end

	return false
end

local function _item_attempt_charge_confirmed(unit, state, ability_name)
	local attempt_t = state.item_attempt_t
	if not attempt_t then
		return false
	end

	local charge_event = _last_charge_event_by_unit[unit]
	if not charge_event then
		return false
	end

	if charge_event.fixed_t < attempt_t then
		return false
	end

	return charge_event.ability_name == ability_name
end

local function _queue_weapon_action_input(state, input_name)
	local action_input_extension = state.action_input_extension
	if not action_input_extension then
		return
	end

	action_input_extension:bot_queue_action_input("weapon_action", input_name, nil)
end

local function _sanitize_dump_name_fragment(value)
	local fragment = tostring(value or "unknown")
	fragment = string.gsub(fragment, "[^%w_%-]", "_")

	return fragment
end

local function _dump_fallback_queue_context_once(kind, ability_name, payload)
	if not _debug_enabled() then
		return
	end

	local key = tostring(kind) .. ":" .. tostring(ability_name)
	if _fallback_queue_dumped_by_key[key] then
		return
	end

	_fallback_queue_dumped_by_key[key] = true

	_mod:echo("BetterBots DEBUG: one-shot context dump for " .. key)
	_mod:dump(payload, "betterbots_" .. _sanitize_dump_name_fragment(key), 3)
end

local function _queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)
	_queue_weapon_action_input(state, state.item_start_input)
	if _debug_enabled() then
		_debug_log(
			"fallback_item_start:" .. ability_name,
			fixed_t,
			"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_start_input)
		)
	end

	if _event_log and _event_log.is_enabled() then
		state.attempt_id = _event_log.next_attempt_id()
		_emit_item_event("queued", unit, ability_name, state, fixed_t, {
			input = state.item_start_input,
			source = "item",
		})
	end

	state.item_attempt_t = fixed_t
	state.item_charge_confirmed = false

	if state.item_followup_input then
		state.item_stage = "waiting_followup"
		state.item_wait_t = fixed_t + (state.item_followup_delay or 0.2)
		state.item_stage_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
		_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_start_input })
	else
		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + state.item_unwield_delay
		state.item_stage_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
		_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_start_input })
	end

	local context = _build_context(unit, blackboard)
	_dump_fallback_queue_context_once("item", ability_name, {
		fixed_t = fixed_t,
		ability_name = ability_name,
		item_profile_name = state.item_profile_name,
		item_start_input = state.item_start_input,
		item_followup_input = state.item_followup_input,
		item_unwield_input = state.item_unwield_input,
		context = _context_snapshot(context),
		fallback_state = _fallback_state_snapshot(state, fixed_t),
	})
end

local function _transition_to_charge_confirmation(state, fixed_t)
	state.item_stage = "waiting_charge_confirmation"
	state.item_wait_t = fixed_t + (state.item_charge_confirm_timeout or _ITEM_CHARGE_CONFIRM_TIMEOUT_S)
	state.item_stage_deadline_t = state.item_wait_t
end

local function _current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, action_input)
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"

	if not action_input then
		return true, weapon_template_name
	end

	local weapon_template = rawget(WeaponTemplates, weapon_template_name)
	local supports_input = weapon_template
		and weapon_template.action_inputs
		and weapon_template.action_inputs[action_input] ~= nil

	return supports_input and true or false, weapon_template_name
end

local function can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
	if not ability_extension:can_use_ability("combat_ability") then
		return false, "item_cooldown_not_ready"
	end

	if not _evaluate_item_heuristic or not _build_context then
		return false, "item_heuristics_not_wired"
	end

	local context = _build_context(unit, blackboard)
	return _evaluate_item_heuristic(ability_name, context)
end

local function try_queue_item(unit, unit_data_extension, ability_extension, state, fixed_t, combat_ability, blackboard)
	local ability_name = combat_ability and combat_ability.name or "unknown"
	local has_item_flow = combat_ability and not combat_ability.ability_template and combat_ability.inventory_item_name
	if not has_item_flow then
		_reset_item_sequence_state(state)
		return
	end

	if state.item_ability_name and state.item_ability_name ~= ability_name then
		_reset_item_sequence_state(state, fixed_t + 0.5)
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	if not state.item_stage then
		if not can_use_item_fallback(unit, ability_extension, ability_name, blackboard) then
			return
		end
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
	local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")
	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")

	state.action_input_extension = action_input_extension
	state.item_ability_name = ability_name

	if not state.item_charge_confirmed and _item_attempt_charge_confirmed(unit, state, ability_name) then
		state.item_charge_confirmed = true
		if _debug_enabled() then
			_debug_log(
				"fallback_item_charge_confirmed:" .. ability_name,
				fixed_t,
				"fallback item confirmed charge consume for "
					.. ability_name
					.. " (profile="
					.. tostring(state.item_profile_name)
					.. ")"
			)
		end
	end

	if state.item_stage == "waiting_wield" then
		if wielded_slot ~= "slot_combat_ability" then
			if fixed_t >= (state.item_wield_deadline_t or 0) then
				if _debug_enabled() then
					_debug_log(
						"fallback_item_wield_timeout:" .. ability_name,
						fixed_t,
						"fallback item blocked " .. ability_name .. " (wield timeout)"
					)
				end
				_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "wield_timeout" })
				_schedule_item_sequence_retry(state, fixed_t, false)
			end

			return
		end

		if not state.item_start_input then
			local weapon_template = rawget(WeaponTemplates, weapon_template_name)
			local sequence, profile_key, selected_index, candidate_count =
				_select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
			if not sequence then
				if _debug_enabled() then
					_debug_log(
						"fallback_item_unsupported:" .. ability_name .. ":" .. weapon_template_name,
						fixed_t,
						"fallback item blocked "
							.. ability_name
							.. " (unsupported weapon template="
							.. tostring(weapon_template_name)
							.. ")"
					)
				end
				_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "unsupported_template" })
				_schedule_item_sequence_retry(state, fixed_t, false)
				return
			end

			state.item_profile_name = sequence.profile_name
			state.item_profile_key = profile_key
			state.item_profile_count = candidate_count
			state.item_start_input = sequence.start_input
			state.item_followup_input = sequence.followup_input
			state.item_followup_delay = sequence.followup_delay
			state.item_unwield_input = sequence.unwield_input
			state.item_unwield_delay = sequence.unwield_delay or 0.3
			state.item_charge_confirm_timeout = sequence.charge_confirm_timeout or _ITEM_CHARGE_CONFIRM_TIMEOUT_S
			state.item_stage = "waiting_start"
			state.item_wait_t = fixed_t + (sequence.start_delay_after_wield or _ITEM_DEFAULT_START_DELAY_S)
			state.item_stage_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
			_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_start_input })

			if _debug_enabled() then
				_debug_log(
					"fallback_item_profile:" .. ability_name .. ":" .. weapon_template_name,
					fixed_t,
					"fallback item selected profile "
						.. tostring(state.item_profile_name)
						.. " ("
						.. tostring(selected_index)
						.. "/"
						.. tostring(candidate_count)
						.. ") for "
						.. ability_name
				)
			end
		end

		if fixed_t >= (state.item_wait_t or 0) then
			_queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)
		end

		return
	end

	if state.item_stage == "waiting_start" then
		if wielded_slot ~= "slot_combat_ability" then
			if _debug_enabled() then
				_debug_log(
					"fallback_item_start_lost_wield:" .. ability_name,
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (lost combat-ability wield before start; slot="
						.. tostring(wielded_slot)
						.. ")"
				)
			end
			_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "lost_wield_before_start" })
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_start_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_start_input)

		if not supports_start_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				if _debug_enabled() then
					_debug_log(
						"fallback_item_start_input_drift:"
							.. ability_name
							.. ":"
							.. tostring(state.item_start_input)
							.. ":"
							.. tostring(current_template_name),
						fixed_t,
						"fallback item blocked "
							.. ability_name
							.. " (start input drift; input="
							.. tostring(state.item_start_input)
							.. ", template="
							.. tostring(current_template_name)
							.. ")"
					)
				end
				_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "start_input_drift" })
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		_queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)

		return
	end

	if state.item_stage == "waiting_followup" then
		if wielded_slot ~= "slot_combat_ability" then
			if _debug_enabled() then
				_debug_log(
					"fallback_item_followup_lost_wield:" .. ability_name,
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (lost combat-ability wield before followup; slot="
						.. tostring(wielded_slot)
						.. ")"
				)
			end
			_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "lost_wield_before_followup" })
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_followup_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_followup_input)

		if not supports_followup_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				if _debug_enabled() then
					_debug_log(
						"fallback_item_followup_input_drift:"
							.. ability_name
							.. ":"
							.. tostring(state.item_followup_input)
							.. ":"
							.. tostring(current_template_name),
						fixed_t,
						"fallback item blocked "
							.. ability_name
							.. " (followup input drift; input="
							.. tostring(state.item_followup_input)
							.. ", template="
							.. tostring(current_template_name)
							.. ")"
					)
				end
				_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "followup_input_drift" })
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_followup_input then
			_queue_weapon_action_input(state, state.item_followup_input)
			if _debug_enabled() then
				_debug_log(
					"fallback_item_followup:" .. ability_name,
					fixed_t,
					"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_followup_input)
				)
			end
		end

		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + (state.item_unwield_delay or 0.3)
		state.item_stage_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
		_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_followup_input })
		return
	end

	if state.item_stage == "waiting_unwield" then
		if wielded_slot ~= "slot_combat_ability" then
			if _debug_enabled() then
				_debug_log(
					"fallback_item_unwield_lost_slot:" .. ability_name,
					fixed_t,
					"fallback item continuing charge confirmation for "
						.. ability_name
						.. " (lost combat-ability wield during unwield stage; slot="
						.. tostring(wielded_slot)
						.. ")"
				)
			end
			_transition_to_charge_confirmation(state, fixed_t)
			_emit_item_event("item_stage", unit, ability_name, state, fixed_t)
			return
		end

		local supports_unwield_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_unwield_input)

		if not supports_unwield_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				if _debug_enabled() then
					_debug_log(
						"fallback_item_unwield_input_drift:"
							.. ability_name
							.. ":"
							.. tostring(state.item_unwield_input)
							.. ":"
							.. tostring(current_template_name),
						fixed_t,
						"fallback item blocked "
							.. ability_name
							.. " (unwield input drift; input="
							.. tostring(state.item_unwield_input)
							.. ", template="
							.. tostring(current_template_name)
							.. ")"
					)
				end
				_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "unwield_input_drift" })
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_unwield_input then
			_queue_weapon_action_input(state, state.item_unwield_input)
			if _debug_enabled() then
				_debug_log(
					"fallback_item_unwield:" .. ability_name,
					fixed_t,
					"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_unwield_input)
				)
			end
		end

		_transition_to_charge_confirmation(state, fixed_t)
		_emit_item_event("item_stage", unit, ability_name, state, fixed_t)
		return
	end

	if state.item_stage == "waiting_charge_confirmation" then
		if state.item_charge_confirmed then
			_reset_item_sequence_state(state, fixed_t + _ITEM_SEQUENCE_RETRY_S)
			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		local rotated = _rotate_item_cast_profile(state)
		if _debug_enabled() then
			_debug_log(
				"fallback_item_no_charge:" .. ability_name,
				fixed_t,
				"fallback item finished without charge consume for "
					.. ability_name
					.. " (profile="
					.. tostring(state.item_profile_name)
					.. ", rotated="
					.. tostring(rotated)
					.. ")"
			)
		end
		_reset_item_sequence_state(state, fixed_t + _ITEM_SEQUENCE_RETRY_S)
		return
	end

	if wielded_slot == "slot_combat_ability" then
		state.item_stage = "waiting_wield"
		state.item_wield_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
		_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = "combat_ability" })
		return
	end

	local current_weapon_template = rawget(WeaponTemplates, weapon_template_name)
	if
		not (
			current_weapon_template
			and current_weapon_template.action_inputs
			and current_weapon_template.action_inputs.combat_ability
		)
	then
		if _debug_enabled() then
			_debug_log(
				"fallback_item_no_wield_input:" .. ability_name .. ":" .. weapon_template_name,
				fixed_t,
				"fallback item blocked "
					.. ability_name
					.. " (weapon template lacks combat_ability input: "
					.. tostring(weapon_template_name)
					.. ")"
			)
		end
		state.next_try_t = fixed_t + _ITEM_SEQUENCE_RETRY_S
		return
	end

	_queue_weapon_action_input(state, "combat_ability")
	state.item_stage = "waiting_wield"
	state.item_wield_deadline_t = fixed_t + _ITEM_WIELD_TIMEOUT_S
	_emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = "combat_ability" })

	if _debug_enabled() then
		_debug_log(
			"fallback_item_wield:" .. ability_name,
			fixed_t,
			"fallback item queued " .. ability_name .. " input=combat_ability (wield slot_combat_ability)"
		)
	end
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_equipped_combat_ability_name = deps.equipped_combat_ability_name
		_fallback_state_by_unit = deps.fallback_state_by_unit
		_last_charge_event_by_unit = deps.last_charge_event_by_unit
		_fallback_queue_dumped_by_key = deps.fallback_queue_dumped_by_key
		_ITEM_WIELD_TIMEOUT_S = deps.ITEM_WIELD_TIMEOUT_S
		_ITEM_SEQUENCE_RETRY_S = deps.ITEM_SEQUENCE_RETRY_S
		_ITEM_CHARGE_CONFIRM_TIMEOUT_S = deps.ITEM_CHARGE_CONFIRM_TIMEOUT_S
		_ITEM_DEFAULT_START_DELAY_S = deps.ITEM_DEFAULT_START_DELAY_S
		_event_log = deps.event_log
		_bot_slot_for_unit = deps.bot_slot_for_unit
	end,
	wire = function(refs)
		_build_context = refs.build_context
		_context_snapshot = refs.context_snapshot
		_fallback_state_snapshot = refs.fallback_state_snapshot
		_evaluate_item_heuristic = refs.evaluate_item_heuristic
	end,
	try_queue_item = try_queue_item,
	can_use_item_fallback = can_use_item_fallback,
	should_lock_weapon_switch = should_lock_weapon_switch,
	schedule_retry = schedule_retry,
}
