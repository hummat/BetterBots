-- Runtime helpers for the grenade/blitz state machine:
-- context augmentation, confirmation tracking, event emission, and stage advancement.
local M = {}

local _debug_log
local _debug_enabled
local _fixed_time
local _event_log
local _bot_slot_for_unit
local _perf
local _grenade_state_by_unit
local _last_grenade_charge_event_by_unit
local _grenade_aim
local _equipped_grenade_ability
local _normalize_grenade_context
local _query_weapon_switch_lock
local _grenade_charge_query_failure_logged

local DEFAULT_THROW_DELAY_S = 0.3
local RETRY_COOLDOWN_S = 2.0
local SLOT_LOCK_RETRY_S = 0.35
local ACTIVE_WEAPON_CHARGE_ACTION = "action_charge"

local function copy_context(context)
	local copy = {}
	for key, value in pairs(context) do
		copy[key] = value
	end
	return copy
end

local function target_breed(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system") or nil
	return unit_data_extension and unit_data_extension:breed() or nil
end

local function augment_grenade_context(unit, context, grenade_name)
	if not context then
		return nil
	end

	local prepared = copy_context(context)
	local breed = target_breed(prepared.target_enemy)
	local target_tags = breed and breed.tags or nil

	prepared.target_is_elite = prepared.target_is_elite or (target_tags and target_tags.elite == true) or false
	prepared.target_is_special = prepared.target_is_special or (target_tags and target_tags.special == true) or false
	prepared.target_is_elite_special = prepared.target_is_elite_special
		or prepared.target_is_elite
		or prepared.target_is_special

	if _equipped_grenade_ability then
		local ability_extension = select(1, _equipped_grenade_ability(unit))
		if ability_extension and ability_extension.remaining_ability_charges then
			local ok, charges = pcall(ability_extension.remaining_ability_charges, ability_extension, "grenade_ability")
			if ok then
				prepared.grenade_charges_remaining = charges
			elseif _debug_enabled() then
				local combo_key = tostring(unit) .. ":" .. tostring(grenade_name)
				if not _grenade_charge_query_failure_logged[combo_key] then
					_grenade_charge_query_failure_logged[combo_key] = true
					_debug_log(
						"grenade_charge_query_failed:" .. tostring(unit),
						_fixed_time(),
						"grenade charge query failed for " .. tostring(grenade_name) .. " (" .. tostring(charges) .. ")"
					)
				end
			end
		end
	end

	local charge_event = _last_grenade_charge_event_by_unit and _last_grenade_charge_event_by_unit[unit]
	if charge_event and charge_event.grenade_name == grenade_name and charge_event.fixed_t ~= nil then
		prepared.seconds_since_last_grenade_charge = math.max(0, _fixed_time() - charge_event.fixed_t)
	end

	return prepared
end

function M.prepare_grenade_context(unit, context, grenade_name)
	if not context then
		return nil
	end

	local aim_unit = _grenade_aim.resolve_aim_unit(context, grenade_name)
	if _normalize_grenade_context then
		context = _normalize_grenade_context(unit, context, aim_unit)
	end

	return augment_grenade_context(unit, context, grenade_name)
end

function M.finish_child_perf(tag, start_clock)
	if start_clock and _perf then
		_perf.finish(tag, start_clock, nil, { include_total = false })
	end
end

function M.reset_state(unit, state, next_try_t)
	local cleared_aim, clear_reason = _grenade_aim.clear_bot_aim(unit)
	if not cleared_aim and _debug_enabled() and state and state.stage then
		_debug_log(
			"grenade_clear_aim:" .. tostring(unit),
			_fixed_time(),
			"grenade aim cleanup skipped (" .. tostring(clear_reason) .. ")"
		)
	end
	state.stage = nil
	state.deadline_t = nil
	state.wait_t = nil
	state.throw_delay = nil
	state.grenade_name = nil
	state.release_t = nil
	state.unwield_requested_t = nil
	state.aim_input = nil
	state.followup_input = nil
	state.followup_delay = nil
	state.followup_delay_index = nil
	state.followup_shots_remaining = nil
	state.release_input = nil
	state.auto_unwield = nil
	state.component = nil
	state.allow_external_wield_cleanup = nil
	state.continue_followup_until_depleted = nil
	state.confirmation_action = nil
	state.confirmation_logged = nil
	state.require_charge_confirmation = nil
	state.stop_followup_peril_pct = nil
	state.last_blocked_foreign_input = nil
	state.aim_unit = nil
	state.aim_distance = nil
	state.precision_target_retained_logged = nil
	state.attempt_id = nil
	if next_try_t then
		state.next_try_t = next_try_t
	end
end

function M.distance_bucket(distance)
	if not distance then
		return "unknown"
	end
	if distance < 8 then
		return "close"
	end
	if distance < 16 then
		return "mid"
	end
	return "far"
end

function M.has_confirmed_charge(state, unit)
	local charge_event = _last_grenade_charge_event_by_unit[unit]
	if not charge_event or charge_event.grenade_name ~= state.grenade_name then
		return false
	end

	local charge_t = charge_event.fixed_t
	local release_t = state.release_t

	return charge_t ~= nil and release_t ~= nil and charge_t >= release_t
end

function M.active_weapon_charge_blocks_grenade_start(unit_data_extension, wielded_slot)
	if not unit_data_extension or wielded_slot == "slot_grenade_ability" then
		return false
	end

	local weapon_action = unit_data_extension:read_component("weapon_action")
	if not weapon_action or weapon_action.current_action_name ~= ACTIVE_WEAPON_CHARGE_ACTION then
		return false
	end

	return true, weapon_action.template_name, weapon_action.current_action_name
end

function M.next_followup_delay(state)
	local delay = state.followup_delay
	if type(delay) == "table" then
		local idx = state.followup_delay_index or 1
		local resolved = delay[idx] or delay[#delay] or DEFAULT_THROW_DELAY_S
		local len = #delay
		if len > 0 then
			state.followup_delay_index = idx % len + 1
		end
		return resolved
	end

	return delay or DEFAULT_THROW_DELAY_S
end

function M.resolve_stop_followup_peril_pct(state)
	local threshold = state.stop_followup_peril_pct
	if type(threshold) == "function" then
		return threshold()
	end

	return threshold
end

function M.should_block_wield_input(unit)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage then
		return false
	end
	if state.stage == "wait_unwield" and state.allow_external_wield_cleanup then
		-- Assail has no chain-time gate here; keep the BT from switching away
		-- before the projectile actually consumes a charge.
		if
			state.require_charge_confirmation
			and not M.has_confirmed_charge(state, unit)
			and (not state.deadline_t or _fixed_time() < state.deadline_t)
		then
			return true, state.grenade_name or "grenade_ability"
		end
		return false
	end
	return true, state.grenade_name or "grenade_ability"
end

function M.should_lock_weapon_switch(unit)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage then
		return false
	end

	-- In wait_unwield the throw is already done; we want the post-throw
	-- action_unwield_to_previous chain to proceed unblocked.
	if state.stage == "wait_unwield" then
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	if not inventory_component or inventory_component.wielded_slot ~= "slot_grenade_ability" then
		return false
	end

	local grenade_name = state.grenade_name
	if not grenade_name and _equipped_grenade_ability then
		local grenade_ability = select(2, _equipped_grenade_ability(unit))
		grenade_name = grenade_ability and grenade_ability.name or "grenade_ability"
	end

	return true, grenade_name or "grenade_ability", "sequence", "slot_grenade_ability"
end

function M.foreign_weapon_switch_lock(unit, desired_slot)
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

local function expected_weapon_action_input(state)
	if not state or not state.stage then
		return nil
	end

	if state.stage == "wait_aim" then
		return state.aim_input
	end

	if state.stage == "wield" and not state.component then
		return "grenade_ability"
	end

	if state.stage == "wait_followup" then
		return state.followup_input
	end

	if state.stage == "wait_throw" then
		return state.release_input
	end

	if state.stage == "wait_unwield" and not state.allow_external_wield_cleanup then
		return "unwield_to_previous"
	end

	return nil
end

function M.should_block_weapon_action_input(unit, action_input)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage or action_input == "wield" then
		return false
	end

	local expected_input = expected_weapon_action_input(state)
	if expected_input and action_input == expected_input then
		return false
	end

	return true, state.grenade_name or "grenade_ability", state.stage
end

function M.queue_weapon_input(unit, input_name, component)
	local ext = ScriptUnit.has_extension(unit, "action_input_system")
	if not ext then
		if _debug_enabled() then
			_debug_log(
				"grenade_no_ext:" .. input_name .. ":" .. tostring(unit),
				_fixed_time(),
				"grenade _queue_weapon_input skipped: no action_input_extension for " .. input_name
			)
		end
		return false
	end
	ext:bot_queue_action_input(component or "weapon_action", input_name, nil)

	return true
end

function M.abort_missing_action_input(unit, state, fixed_t, input_name, stage_t0)
	if _debug_enabled() then
		_debug_log(
			"grenade_queue_missing:" .. tostring(state.stage) .. ":" .. tostring(unit),
			fixed_t,
			"grenade blocked during "
				.. tostring(state.stage)
				.. ": missing action_input_system for "
				.. tostring(input_name)
		)
	end
	M.emit_event(
		"blocked",
		unit,
		state.grenade_name,
		state,
		fixed_t,
		{ reason = "action_input_missing", input = tostring(input_name), stage = tostring(state.stage) }
	)
	M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
	M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
end

function M.abort_slot_locked(unit, state, fixed_t, blocking_ability, lock_reason, held_slot, perf_tag, start_clock)
	if _debug_enabled() then
		_debug_log(
			"grenade_slot_locked:" .. tostring(unit),
			fixed_t,
			"grenade blocked during "
				.. tostring(state.stage)
				.. " by "
				.. tostring(blocking_ability)
				.. " "
				.. tostring(lock_reason)
				.. " (held_slot="
				.. tostring(held_slot)
				.. ")"
		)
	end

	M.emit_event("blocked", unit, state.grenade_name, state, fixed_t, {
		reason = "slot_locked",
		blocked_by = blocking_ability,
		lock_reason = lock_reason,
		held_slot = held_slot,
	})
	M.reset_state(unit, state, fixed_t + SLOT_LOCK_RETRY_S)
	M.finish_child_perf(perf_tag, start_clock)
end

function M.describe_action_component_state(unit, component_name)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return " (component=" .. tostring(component_name) .. ", template=no_unit_data, action=no_unit_data)"
	end

	local action_component = unit_data_extension:read_component(component_name)
	if not action_component then
		return " (component=" .. tostring(component_name) .. ", template=missing, action=missing)"
	end

	return " (component="
		.. tostring(component_name)
		.. ", template="
		.. tostring(action_component.template_name)
		.. ", action="
		.. tostring(action_component.current_action_name)
		.. ")"
end

function M.emit_decision(unit, grenade_name, should_throw, rule, context, fixed_t)
	if not (_event_log and _event_log.is_enabled and _event_log.is_enabled() and _event_log.emit_decision) then
		return
	end

	_event_log.emit_decision(
		fixed_t,
		_bot_slot_for_unit and _bot_slot_for_unit(unit) or nil,
		grenade_name,
		grenade_name,
		should_throw,
		rule,
		"grenade",
		context
	)
end

function M.emit_event(event_type, unit, grenade_name, state, fixed_t, extra)
	if not _event_log or not _event_log.is_enabled() then
		return
	end

	local ev = {
		t = fixed_t,
		event = event_type,
		bot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or nil,
		ability = grenade_name,
		stage = state.stage,
		attempt_id = state.attempt_id,
		source = "grenade",
	}

	if extra then
		for k, v in pairs(extra) do
			ev[k] = v
		end
	end

	_event_log.emit(ev)
end

function M.record_charge_event(unit, grenade_name, fixed_t)
	_last_grenade_charge_event_by_unit[unit] = {
		grenade_name = grenade_name,
		fixed_t = fixed_t,
	}
end

function M.handle_wait_unwield(unit, state, fixed_t, unit_data_extension, wielded_slot, stage_t0)
	-- Ability-based blitz: no slot change occurred, no unwield needed.
	-- Just wait for charge confirmation or timeout, then reset.
	if state.component then
		if M.has_confirmed_charge(state, unit) or fixed_t >= (state.deadline_t or 0) then
			local charge_ok = M.has_confirmed_charge(state, unit)
			if _debug_enabled() then
				local reason = charge_ok and "charge confirmed" or "timeout"
				local component_state = M.describe_action_component_state(unit, state.component)
				_debug_log(
					"grenade_ability_complete:" .. tostring(unit),
					fixed_t,
					"ability blitz complete (" .. reason .. ")" .. component_state
				)
			end
			M.emit_event(
				charge_ok and "complete" or "blocked",
				unit,
				state.grenade_name,
				state,
				fixed_t,
				{ reason = charge_ok and "charge_confirmed" or "timeout" }
			)
			M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		end
		M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	-- Psyker blitz templates like Chain Lightning and Smite exit on generic
	-- wield transitions, not unwield_to_previous. Release our block and let
	-- the normal weapon-switch path unwind them.
	if state.allow_external_wield_cleanup then
		if wielded_slot ~= "slot_grenade_ability" then
			if _debug_enabled() then
				_debug_log(
					"grenade_external_cleanup_slot:" .. tostring(unit),
					fixed_t,
					"grenade released cleanup lock without explicit unwield (slot changed)"
				)
			end
			M.emit_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "slot_changed" })
			M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		local action_confirmed = false
		if state.confirmation_action and unit_data_extension then
			local weapon_action = unit_data_extension:read_component("weapon_action")
			action_confirmed = weapon_action and weapon_action.current_action_name == state.confirmation_action
		end

		if _debug_enabled() and action_confirmed and not state.confirmation_logged then
			state.confirmation_logged = true
			_debug_log(
				"grenade_external_action:" .. tostring(unit),
				fixed_t,
				"grenade external action confirmed for "
					.. tostring(state.grenade_name)
					.. " (action="
					.. tostring(state.confirmation_action)
					.. ", aim_target="
					.. tostring(state.aim_unit or "none")
					.. ", dist_bucket="
					.. M.distance_bucket(state.aim_distance)
					.. ")"
			)
		end

		if action_confirmed and not state.require_charge_confirmation then
			if _debug_enabled() then
				state.confirmation_logged = true
				_debug_log(
					"grenade_external_cleanup_action:" .. tostring(unit),
					fixed_t,
					"grenade released cleanup lock without explicit unwield (action confirmed)"
				)
			end
			M.emit_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "action_confirmed" })
			M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if M.has_confirmed_charge(state, unit) then
			if _debug_enabled() then
				_debug_log(
					"grenade_external_cleanup_charge:" .. tostring(unit),
					fixed_t,
					"grenade released cleanup lock without explicit unwield (charge confirmed)"
				)
			end
			M.emit_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "charge_confirmed" })
			M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			if _debug_enabled() then
				_debug_log(
					"grenade_external_cleanup_timeout:" .. tostring(unit),
					fixed_t,
					"grenade released cleanup lock without explicit unwield (timeout)"
				)
			end
			M.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "timeout" })
			M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		end
		M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if wielded_slot ~= "slot_grenade_ability" then
		if _debug_enabled() then
			_debug_log(
				"grenade_unwield_ok:" .. tostring(unit),
				fixed_t,
				"grenade throw complete, slot returned to " .. tostring(wielded_slot)
			)
		end
		M.emit_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "slot_returned" })
		M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	-- For non-auto-unwield templates, force unwield immediately.
	-- The engine won't auto-chain unwield_to_previous for these.
	if state.auto_unwield == false and not state.unwield_requested_t then
		if not M.queue_weapon_input(unit, "unwield_to_previous") then
			M.abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
			return
		end
		state.unwield_requested_t = fixed_t
		if _debug_enabled() then
			_debug_log(
				"grenade_force_unwield:" .. tostring(unit),
				fixed_t,
				"grenade forced unwield_to_previous (no auto-unwield)"
			)
		end
		M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if not state.unwield_requested_t and M.has_confirmed_charge(state, unit) then
		if not M.queue_weapon_input(unit, "unwield_to_previous") then
			M.abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
			return
		end
		state.unwield_requested_t = fixed_t
		if _debug_enabled() then
			_debug_log(
				"grenade_unwield_requested:" .. tostring(unit),
				fixed_t,
				"grenade queued unwield_to_previous after charge confirmation"
			)
		end
		M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if fixed_t >= (state.deadline_t or 0) then
		if not M.queue_weapon_input(unit, "unwield_to_previous") then
			M.abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
			return
		end
		if _debug_enabled() then
			_debug_log(
				"grenade_unwield_forced:" .. tostring(unit),
				fixed_t,
				"grenade forced unwield_to_previous on timeout"
			)
		end
		M.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "unwield_timeout" })
		M.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
	end

	M.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
end

function M.init(deps)
	deps = deps or {}
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled or function()
		return false
	end
	_fixed_time = deps.fixed_time
	_event_log = deps.event_log
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_perf = deps.perf
	_grenade_state_by_unit = deps.grenade_state_by_unit
	_last_grenade_charge_event_by_unit = deps.last_grenade_charge_event_by_unit
	_grenade_aim = deps.grenade_aim
	DEFAULT_THROW_DELAY_S = deps.default_throw_delay_s or DEFAULT_THROW_DELAY_S
	RETRY_COOLDOWN_S = deps.retry_cooldown_s or RETRY_COOLDOWN_S
	SLOT_LOCK_RETRY_S = deps.slot_lock_retry_s or SLOT_LOCK_RETRY_S
	ACTIVE_WEAPON_CHARGE_ACTION = deps.active_weapon_charge_action or ACTIVE_WEAPON_CHARGE_ACTION
	_grenade_charge_query_failure_logged = {}
end

function M.wire(refs)
	refs = refs or {}
	_equipped_grenade_ability = refs.equipped_grenade_ability
	_normalize_grenade_context = refs.normalize_grenade_context
	_query_weapon_switch_lock = refs.query_weapon_switch_lock
end

return M
