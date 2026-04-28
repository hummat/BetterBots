local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
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
local _query_weapon_switch_lock
local _item_profiles

local ABILITY_STATE_FAIL_RETRY_S = 0.35

-- Late-bound cross-module refs, set via wire()
local _build_context
local _context_snapshot
local _fallback_state_snapshot
local _evaluate_item_heuristic
local _is_item_ability_enabled

local function _emit_item_event(event_type, unit, ability_name, state, fixed_t, extra)
	if not _event_log or not _event_log.is_enabled() then
		return
	end

	local ev = {
		t = fixed_t,
		event = event_type,
		bot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or nil,
		ability = ability_name,
		rule = state.item_rule,
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
	state.item_rule = nil

	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local function _schedule_item_sequence_retry(state, fixed_t, rotate_profile)
	if rotate_profile then
		_item_profiles.rotate_profile(state)
	end

	_reset_item_sequence_state(state, fixed_t + _ITEM_SEQUENCE_RETRY_S)
end

local function _schedule_item_fast_retry(state, fixed_t)
	local retry_t = fixed_t + ABILITY_STATE_FAIL_RETRY_S

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	if not state.next_try_t or retry_t < state.next_try_t then
		state.next_try_t = retry_t
	end
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

local function on_state_change_finish(func, self, reason, data, t, time_in_action)
	local action_settings = self._action_settings
	local ability_type = action_settings and action_settings.ability_type
	local use_ability_charge = action_settings and action_settings.use_ability_charge
	local player = self._player
	local unit = self._player_unit
	local wanted_state_name = self._wanted_state_name
	local character_state_component = self._character_sate_component
	local current_state_name = character_state_component and character_state_component.state_name or nil
	local failed_state_transition = wanted_state_name ~= nil and current_state_name ~= wanted_state_name
	local is_bot = player and not player:is_human_controlled()

	func(self, reason, data, t, time_in_action)

	if
		not is_bot
		or not unit
		or ability_type ~= "combat_ability"
		or not use_ability_charge
		or not failed_state_transition
	then
		return
	end

	local fixed_t = _fixed_time()
	local ability_name = _equipped_combat_ability_name(unit)
	M.schedule_retry(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
	if _debug_enabled() then
		_debug_log(
			"state_fail_retry:" .. tostring(ability_name) .. ":" .. tostring(reason),
			fixed_t,
			"combat ability state transition failed for "
				.. tostring(ability_name)
				.. " (wanted="
				.. tostring(wanted_state_name)
				.. ", current="
				.. tostring(current_state_name)
				.. ", reason="
				.. tostring(reason)
				.. "); scheduled fast retry"
		)
	end
end

local function _interaction_pending_or_active(unit_data_extension)
	local interaction_component = unit_data_extension:read_component("interaction")

	-- Character-state interaction entry requests slot_unarmed before the
	-- full interacting state is settled. Treat any live target as protected
	-- so relic slot locking cannot override that transition and crash the
	-- interaction state machine.
	return interaction_component and interaction_component.target_unit ~= nil
end

local function _foreign_weapon_switch_lock(unit, desired_slot)
	if not _query_weapon_switch_lock then
		return false
	end

	local should_lock, blocking_ability, lock_reason, slot_to_keep = _query_weapon_switch_lock(unit)
	if not should_lock then
		return false
	end

	slot_to_keep = slot_to_keep or desired_slot
	if slot_to_keep == desired_slot then
		return false
	end

	return true, blocking_ability or "ability", lock_reason or "sequence", slot_to_keep
end

local function _block_item_for_slot_lock(unit, state, ability_name, fixed_t, blocking_ability, lock_reason, held_slot)
	if _debug_enabled() then
		_debug_log(
			"fallback_item_slot_locked:" .. ability_name .. ":" .. tostring(unit),
			fixed_t,
			"fallback item blocked "
				.. ability_name
				.. " (slot locked by "
				.. tostring(blocking_ability)
				.. " "
				.. tostring(lock_reason)
				.. ")"
		)
	end

	_emit_item_event("blocked", unit, ability_name, state, fixed_t, {
		reason = "slot_locked",
		blocked_by = blocking_ability,
		lock_reason = lock_reason,
		held_slot = held_slot,
	})
	_schedule_item_fast_retry(state, fixed_t)
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

	if _interaction_pending_or_active(unit_data_extension) then
		return false
	end

	local ability_name = _equipped_combat_ability_name(unit)
	local combat_ability_component = unit_data_extension:read_component("combat_ability")
	local combat_ability_active = combat_ability_component and combat_ability_component.active == true

	if combat_ability_active and _item_profiles.should_lock_active_ability(ability_name) then
		return true, ability_name, "active", "slot_combat_ability"
	end

	local state = _fallback_state_by_unit[unit]
	local staged_ability_name = state and state.item_ability_name
	if
		state
		and state.item_stage
		and staged_ability_name
		and _item_profiles.should_lock_sequence(staged_ability_name)
	then
		return true, staged_ability_name, "sequence", "slot_combat_ability"
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
			"fallback item queued "
				.. ability_name
				.. " input="
				.. tostring(state.item_start_input)
				.. " (rule="
				.. tostring(state.item_rule)
				.. ")"
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
	if _is_item_ability_enabled and not _is_item_ability_enabled(ability_name) then
		return false, "item_disabled"
	end

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
		local can_use, rule = can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
		if not can_use then
			return
		end
		state.item_rule = rule
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
					.. ", rule="
					.. tostring(state.item_rule)
					.. ")"
			)
		end
	end

	if state.item_stage == "waiting_wield" then
		if wielded_slot ~= "slot_combat_ability" then
			local blocked, blocking_ability, lock_reason, held_slot =
				_foreign_weapon_switch_lock(unit, "slot_combat_ability")
			if blocked then
				_block_item_for_slot_lock(unit, state, ability_name, fixed_t, blocking_ability, lock_reason, held_slot)
				return
			end

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
				_item_profiles.select_sequence(state, ability_name, weapon_template_name, weapon_template)
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

		local rotated = _item_profiles.rotate_profile(state)
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

	local blocked, blocking_ability, lock_reason, held_slot = _foreign_weapon_switch_lock(unit, "slot_combat_ability")
	if blocked then
		_block_item_for_slot_lock(unit, state, ability_name, fixed_t, blocking_ability, lock_reason, held_slot)
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

M.init = function(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
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
	_item_profiles = deps.item_profiles
	assert(_item_profiles, "BetterBots: item_fallback requires item_profiles")
end

M.wire = function(refs)
	_build_context = refs.build_context
	_context_snapshot = refs.context_snapshot
	_fallback_state_snapshot = refs.fallback_state_snapshot
	_evaluate_item_heuristic = refs.evaluate_item_heuristic
	_is_item_ability_enabled = refs.is_item_ability_enabled
	_query_weapon_switch_lock = refs.query_weapon_switch_lock
end

M.try_queue_item = try_queue_item
M.can_use_item_fallback = can_use_item_fallback
M.should_lock_weapon_switch = should_lock_weapon_switch
M.reset_item_sequence_state = _reset_item_sequence_state
M.schedule_retry = schedule_retry
M.on_state_change_finish = on_state_change_finish

return M
