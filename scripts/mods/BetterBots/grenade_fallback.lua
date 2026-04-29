-- grenade_fallback.lua — bot blitz/grenade state machine (#4)
-- Handles two activation modes:
--   Item-based grenades: wield grenade slot → aim → throw → unwield (weapon_action component)
--   Ability-based blitz: queue inputs directly on grenade_ability_action (no slot change)
-- Supports standard grenades (aim_hold/aim_released), whistle (aim_pressed/aim_released),
-- auto-fire (zealot knives), and fire-and-wait (missile launcher) patterns.
-- Only activates when charges are available and the heuristic permits.
-- Dependencies (set via init/wire)
local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _fixed_time
local _event_log
local _is_suppressed
local _perf
local _warp_weapon_peril_threshold

-- Late-bound cross-module refs (set via wire)
local _build_context
local _evaluate_grenade_heuristic
local _equipped_grenade_ability
local _is_combat_ability_active
local _is_grenade_enabled
local _grenade_profiles
local _grenade_aim
local _grenade_runtime

-- State tracking (weak-keyed by unit)
local _grenade_state_by_unit

-- Timing constants
local WIELD_TIMEOUT_S = 2.0 -- Abort if slot hasn't changed; covers slowest standard wield (~1.5s)
local AIM_DELAY_S = 0.15 -- Minimum hold before queueing aim_hold (lets wield animation settle)
local DEFAULT_THROW_DELAY_S = 0.3 -- Default hold after aim_hold before releasing
local UNWIELD_TIMEOUT_S = 3.0 -- Wait for auto-unwield after throw; force if exceeded
local RETRY_COOLDOWN_S = 2.0 -- Shared cooldown after a throw attempt finishes or aborts
local SLOT_LOCK_RETRY_S = 0.35 -- Fast retry when another BetterBots sequence is holding a different slot
local IDLE_DECISION_INTERVAL_S = 0.15 -- Coarse idle cadence for negative grenade/blitz decisions (~4-5 fixed frames)
local ACTIVE_WEAPON_CHARGE_ACTION = "action_charge"

local function try_queue(unit, blackboard)
	local fixed_t = _fixed_time()

	local state = _grenade_state_by_unit[unit]
	if not state then
		state = {}
		_grenade_state_by_unit[unit] = state
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	local stage_t0 = state.stage and _perf and _perf.begin() or nil
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")

	-- If unit_data_extension is gone mid-sequence, abort cleanly.
	if not unit_data_extension and state.stage then
		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_no_unit_data:" .. tostring(unit),
				fixed_t,
				"grenade aborted stage=" .. tostring(state.stage) .. ": unit_data_system missing"
			)
		end
		_grenade_runtime.emit_event(
			"blocked",
			unit,
			state.grenade_name,
			state,
			fixed_t,
			{ reason = "unit_data_missing" }
		)
		_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
	if not state.stage then
		local charge_active, template_name, action_name =
			_grenade_runtime.active_weapon_charge_blocks_grenade_start(unit_data_extension, wielded_slot)
		if charge_active then
			if _debug_enabled() then
				_debug_log(
					"grenade_defer_weapon_charge:" .. tostring(unit),
					fixed_t,
					"grenade deferred during active weapon charge (weapon="
						.. tostring(template_name)
						.. ", action="
						.. tostring(action_name)
						.. ")"
				)
			end
			return
		end

		if state.next_idle_eval_t and fixed_t < state.next_idle_eval_t then
			return
		end
	end

	local active_context
	if state.stage and state.stage ~= "wait_unwield" then
		active_context = _build_context(unit, blackboard)
		active_context = _grenade_runtime.prepare_grenade_context(unit, active_context, state.grenade_name)
		if not _grenade_aim.refresh_bot_aim(unit, state, active_context, fixed_t) then
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			_grenade_runtime.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "aim_lost" })
			_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end
	end

	if state.stage == "wield" then
		if not state.aim_input and _grenade_runtime.has_confirmed_charge(state, unit) then
			if wielded_slot == "slot_grenade_ability" then
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.unwield_requested_t = nil
				_grenade_runtime.emit_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
				if _debug_enabled() then
					_debug_log(
						"grenade_auto_fire:" .. tostring(unit),
						fixed_t,
						"grenade auto-fire confirmed, waiting for unwield"
					)
				end
			else
				if _debug_enabled() then
					_debug_log(
						"grenade_auto_fire_complete:" .. tostring(unit),
						fixed_t,
						"grenade auto-fire complete without stable grenade slot (slot=" .. tostring(wielded_slot) .. ")"
					)
				end
				_grenade_runtime.emit_event(
					"complete",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = "auto_fire" }
				)
				_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			end
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if wielded_slot == "slot_grenade_ability" then
			if not state.aim_input then
				-- Auto-fire template: skip aim/throw, go straight to wait_unwield
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
				_grenade_runtime.emit_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
				if _debug_enabled() then
					_debug_log(
						"grenade_auto_fire:" .. tostring(unit),
						fixed_t,
						"grenade auto-fire, waiting for unwield"
					)
				end
			else
				state.stage = "wait_aim"
				state.wait_t = fixed_t + AIM_DELAY_S
				_grenade_runtime.emit_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
				if _debug_enabled() then
					_debug_log(
						"grenade_wield_ok:" .. tostring(unit),
						fixed_t,
						"grenade wield confirmed, waiting for aim"
					)
				end
			end
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		local blocked, blocking_ability, lock_reason, held_slot =
			_grenade_runtime.foreign_weapon_switch_lock(unit, "slot_grenade_ability")
		if blocked then
			_grenade_runtime.abort_slot_locked(
				unit,
				state,
				fixed_t,
				blocking_ability,
				lock_reason,
				held_slot,
				"grenade_fallback.stage_machine",
				stage_t0
			)
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			if _debug_enabled() then
				_debug_log(
					"grenade_wield_timeout:" .. tostring(unit),
					fixed_t,
					"grenade wield timeout, resetting with retry"
				)
			end
			_grenade_runtime.emit_event(
				"blocked",
				unit,
				state.grenade_name,
				state,
				fixed_t,
				{ reason = "wield_timeout" }
			)
			_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		end

		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_aim" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_aim_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during aim (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_grenade_runtime.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local context = active_context
				or _grenade_runtime.prepare_grenade_context(unit, _build_context(unit, blackboard), state.grenade_name)
			-- Pass `revalidation = true` so density-gated grenades get one
			-- enemy's worth of hysteresis on the re-check; prevents every
			-- frag attempt from losing the race when num_nearby dips
			-- across the aim window (see evaluate_grenade_heuristic).
			local should_throw, rule = _evaluate_grenade_heuristic(state.grenade_name, context, { revalidation = true })
			if not should_throw then
				if _debug_enabled() then
					_debug_log(
						"grenade_revalidate_block:" .. tostring(unit),
						fixed_t,
						"grenade aim aborted after revalidation (rule=" .. tostring(rule) .. ")"
					)
				end
				_grenade_runtime.emit_event(
					"blocked",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = "revalidation", rule = rule }
				)
				_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
				return
			end

			local aim = state.aim_input or "aim_hold"
			if not _grenade_runtime.queue_weapon_input(unit, aim, state.component) then
				_grenade_runtime.abort_missing_action_input(unit, state, fixed_t, aim, stage_t0)
				return
			end
			if state.followup_input then
				state.stage = "wait_followup"
				state.wait_t = fixed_t + _grenade_runtime.next_followup_delay(state)
			elseif state.release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			else
				-- No release needed: skip to wait_unwield (e.g. missile auto-chains)
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
			end
			_grenade_runtime.emit_event("grenade_stage", unit, state.grenade_name, state, fixed_t, { input = aim })
			if _debug_enabled() then
				_debug_log(
					"grenade_aim:" .. tostring(unit),
					fixed_t,
					"grenade queued " .. tostring(aim) .. " for " .. tostring(state.grenade_name)
				)
			end
		end

		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_followup" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_followup_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during followup (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_grenade_runtime.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		local stop_followup_peril_pct = _grenade_runtime.resolve_stop_followup_peril_pct(state)
		local active_peril_pct = active_context and active_context.peril_pct or nil
		if stop_followup_peril_pct and active_peril_pct == nil then
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			if _debug_enabled() then
				_debug_log(
					"grenade_followup_stop_peril:" .. tostring(unit),
					fixed_t,
					"grenade followup stopped at peril guard for "
						.. tostring(state.grenade_name)
						.. " (peril unavailable)"
				)
			end
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if stop_followup_peril_pct and active_peril_pct >= stop_followup_peril_pct then
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			if _debug_enabled() then
				_debug_log(
					"grenade_followup_stop_peril:" .. tostring(unit),
					fixed_t,
					"grenade followup stopped at peril for "
						.. tostring(state.grenade_name)
						.. " ("
						.. tostring(active_peril_pct)
						.. ")"
				)
			end
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local followup = state.followup_input
			if not _grenade_runtime.queue_weapon_input(unit, followup, state.component) then
				_grenade_runtime.abort_missing_action_input(unit, state, fixed_t, followup, stage_t0)
				return
			end
			if state.continue_followup_until_depleted then
				local remaining = math.max((state.followup_shots_remaining or 0) - 1, 0)
				state.followup_shots_remaining = remaining
				if remaining > 0 then
					state.stage = "wait_followup"
					state.wait_t = fixed_t + _grenade_runtime.next_followup_delay(state)
				else
					state.stage = "wait_unwield"
					state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
					state.release_t = fixed_t
					state.unwield_requested_t = nil
				end
			elseif state.release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			else
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
			end
			_grenade_runtime.emit_event(
				"grenade_stage",
				unit,
				state.grenade_name,
				state,
				fixed_t,
				{ input = tostring(followup) }
			)
			if _debug_enabled() then
				_debug_log(
					"grenade_followup:" .. tostring(unit),
					fixed_t,
					"grenade queued " .. tostring(followup) .. " for " .. tostring(state.grenade_name)
				)
			end
		end

		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_throw" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_throw_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during throw (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_grenade_runtime.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local release = state.release_input or "aim_released"
			if not _grenade_runtime.queue_weapon_input(unit, release, state.component) then
				_grenade_runtime.abort_missing_action_input(unit, state, fixed_t, release, stage_t0)
				return
			end
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			_grenade_runtime.emit_event("grenade_stage", unit, state.grenade_name, state, fixed_t, { input = release })
			if _debug_enabled() then
				local component_state = state.component
						and _grenade_runtime.describe_action_component_state(unit, state.component)
					or ""
				_debug_log(
					"grenade_release:" .. tostring(unit),
					fixed_t,
					"grenade releasing toward "
						.. tostring(state.aim_unit or "none")
						.. " via "
						.. release
						.. component_state
						.. " (dist_bucket="
						.. _grenade_runtime.distance_bucket(state.aim_distance)
						.. ")"
						.. _grenade_aim.aim_target_log_suffix(unit, state.aim_unit)
				)
			end
		end

		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_unwield" then
		_grenade_runtime.handle_wait_unwield(unit, state, fixed_t, unit_data_extension, wielded_slot, stage_t0)
		return
	end

	-- Unknown stage — log and reset rather than falling through to idle.
	if state.stage ~= nil then
		_grenade_runtime.finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_unknown_stage:" .. tostring(unit),
				fixed_t,
				"grenade unknown stage=" .. tostring(state.stage) .. ", resetting"
			)
		end
		_grenade_runtime.emit_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "unknown_stage" })
		_grenade_runtime.reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	-- Idle: check if we can and should throw a grenade.
	-- Guards mirror ability_queue.lua: block during interactions and suppressed states.
	local behavior = blackboard and blackboard.behavior
	if behavior and behavior.current_interaction_unit ~= nil then
		if _debug_enabled() then
			_debug_log(
				"grenade_interaction_block:" .. tostring(unit),
				fixed_t,
				"grenade blocked: interacting with " .. tostring(behavior.current_interaction_unit)
			)
		end
		return
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"grenade_suppress:" .. tostring(suppress_reason) .. ":" .. tostring(unit),
				fixed_t,
				"grenade blocked: suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return
	end

	-- Mutual exclusion: don't start a grenade sequence while the combat ability
	-- holds the weapon lock — the wield_slot hook would redirect our wield to
	-- slot_combat_ability and we'd time out. Defer until the combat sequence ends.
	if _is_combat_ability_active and _is_combat_ability_active(unit) then
		if _debug_enabled() then
			_debug_log(
				"grenade_combat_ability_active:" .. tostring(unit),
				fixed_t,
				"grenade blocked: combat ability active"
			)
		end
		return
	end

	local ability_extension, grenade_ability = _equipped_grenade_ability(unit)
	if not ability_extension then
		if _debug_enabled() then
			_debug_log("grenade_no_ability_ext:" .. tostring(unit), fixed_t, "grenade blocked: no ability extension")
		end
		return
	end

	if not grenade_ability then
		if _debug_enabled() then
			_debug_log(
				"grenade_no_equipped_ability:" .. tostring(unit),
				fixed_t,
				"grenade blocked: no equipped grenade ability"
			)
		end
		return
	end

	if not ability_extension:can_use_ability("grenade_ability") then
		if _debug_enabled() then
			_debug_log("grenade_cannot_use:" .. tostring(unit), fixed_t, "grenade blocked: can_use_ability=false")
		end
		return
	end

	local grenade_name = grenade_ability.name or "unknown"
	if _is_grenade_enabled and not _is_grenade_enabled(grenade_name) then
		if _debug_enabled() then
			_debug_log(
				"grenade_disabled:" .. tostring(grenade_name) .. ":" .. tostring(unit),
				fixed_t,
				"grenade blocked: category disabled for " .. tostring(grenade_name)
			)
		end
		return
	end

	-- Resolve profile: number = default aim_hold/aim_released; table = custom profile.
	local ctx_t0 = _perf and _perf.begin() or nil
	local context = _build_context(unit, blackboard)
	context = _grenade_runtime.prepare_grenade_context(unit, context, grenade_name)
	if ctx_t0 and _perf then
		_perf.finish("grenade_fallback.build_context", ctx_t0, nil, { include_total = false })
	end
	local heur_t0 = _perf and _perf.begin() or nil
	local should_throw, rule = _evaluate_grenade_heuristic(grenade_name, context)
	if heur_t0 and _perf then
		_perf.finish("grenade_fallback.heuristic", heur_t0, nil, { include_total = false })
	end
	_grenade_runtime.emit_decision(unit, grenade_name, should_throw, rule, context, fixed_t)
	if not should_throw then
		state.next_idle_eval_t = fixed_t + IDLE_DECISION_INTERVAL_S
		-- Gate filters zero-signal holds. Non-psyker bots always have
		-- peril_pct == 0 because the engine zero-initializes the
		-- warp_charge component on every player unit (see
		-- player_unit_talent_extension._init_components), so
		-- `peril_pct ~= nil` on its own lets every frame log for
		-- veteran/zealot/ogryn. Require >0 so only real psyker peril
		-- keeps the gate open.
		if
			_debug_enabled()
			and (
				(context and context.num_nearby and context.num_nearby > 0)
				or (context and context.target_enemy)
				or (context and context.peril_pct ~= nil and context.peril_pct > 0)
			)
		then
			_debug_log(
				"grenade_decision_block:" .. grenade_name .. ":" .. tostring(unit),
				fixed_t,
				"grenade held "
					.. grenade_name
					.. " (rule="
					.. tostring(rule)
					.. ", nearby="
					.. tostring(context and context.num_nearby or 0)
					.. ", peril="
					.. tostring(context and context.peril_pct)
					.. ")"
			)
		end
		return
	end
	state.next_idle_eval_t = nil

	local profile_t0 = _perf and _perf.begin() or nil
	local template_entry = _grenade_profiles.resolve_template_entry(grenade_name, context, rule)
	if not template_entry then
		_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_unsupported:" .. grenade_name .. ":" .. tostring(unit),
				fixed_t,
				"unsupported grenade template " .. grenade_name .. " (rule=" .. tostring(rule) .. ")"
			)
		end
		return
	end

	local aim_input, followup_input, followup_delay, release_input, throw_delay
	local auto_unwield, component, confirmation_action
	local continue_followup_until_depleted = false
	if type(template_entry) == "number" then
		aim_input = "aim_hold"
		release_input = "aim_released"
		throw_delay = template_entry
		auto_unwield = true
	else
		aim_input = template_entry.aim_input
		followup_input = template_entry.followup_input
		followup_delay = template_entry.followup_delay
		release_input = template_entry.release_input
		throw_delay = template_entry.throw_delay or DEFAULT_THROW_DELAY_S
		auto_unwield = template_entry.auto_unwield ~= false -- default true
		component = template_entry.component
		confirmation_action = template_entry.confirmation_action
		continue_followup_until_depleted = template_entry.continue_followup_until_depleted == true
	end

	local depletion_burst_charges_remaining = continue_followup_until_depleted
			and context
			and context.grenade_charges_remaining
		or nil
	if continue_followup_until_depleted and depletion_burst_charges_remaining == nil then
		_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_burst_unknown_charges:" .. tostring(unit),
				fixed_t,
				"grenade burst unavailable for " .. tostring(grenade_name) .. " (charges unknown)"
			)
		end
		_grenade_runtime.emit_event("blocked", unit, grenade_name, state, fixed_t, { reason = "charges_unknown" })
		return
	end

	-- Pre-flight: don't enter the state machine without a target for aimed throws.
	-- Wielding auto-fire templates (zealot knives) triggers the throw immediately,
	-- so aborting after wield is too late — the charge is already consumed.
	if aim_input then
		local aim_unit = _grenade_aim.resolve_aim_unit(context, grenade_name)
		if not aim_unit then
			_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
			return
		end

		if not _grenade_aim.has_line_of_sight(unit, aim_unit) then
			_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
			if _debug_enabled() then
				_debug_log(
					_grenade_aim.aim_target_log_key("grenade_aim_unavailable", unit, aim_unit),
					fixed_t,
					"grenade aim unavailable for "
						.. tostring(grenade_name)
						.. " (no_los)"
						.. _grenade_aim.aim_target_log_suffix(unit, aim_unit)
				)
			end
			_grenade_runtime.emit_event("blocked", unit, grenade_name, state, fixed_t, { reason = "no_los" })
			return
		end

		state.aim_unit = aim_unit
		state.aim_distance = context and context.target_enemy_distance or nil
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
		return
	end
	_grenade_runtime.finish_child_perf("grenade_fallback.profile_resolution", profile_t0)

	local launch_t0 = _perf and _perf.begin() or nil
	state.throw_delay = throw_delay
	state.grenade_name = grenade_name
	state.aim_input = aim_input
	state.followup_input = followup_input
	state.followup_delay = followup_delay
	state.followup_delay_index = nil
	state.followup_shots_remaining = continue_followup_until_depleted
			and math.max((depletion_burst_charges_remaining or 0) - 1, 0)
		or nil
	state.release_input = release_input
	state.release_t = nil
	state.auto_unwield = auto_unwield
	state.component = component
	state.allow_external_wield_cleanup = type(template_entry) == "table"
		and template_entry.allow_external_wield_cleanup == true
	state.continue_followup_until_depleted = continue_followup_until_depleted
	state.confirmation_action = confirmation_action
	state.confirmation_logged = nil
	state.require_charge_confirmation = type(template_entry) == "table"
		and template_entry.require_charge_confirmation == true
	state.stop_followup_peril_pct = type(template_entry) == "table" and template_entry.stop_followup_peril_pct or nil

	if _event_log and _event_log.is_enabled() then
		state.attempt_id = _event_log.next_attempt_id()
	end

	if component then
		-- Ability-based blitz: queue aim input directly on the ability component.
		-- No slot wield needed — the ability fires from any weapon slot.
		if aim_input then
			if release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (throw_delay or DEFAULT_THROW_DELAY_S)
			else
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
			end
			action_input_extension:bot_queue_action_input(component, aim_input, nil)
		else
			-- Ability-based auto-fire: just wait for charge confirmation
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
		end
		_grenade_runtime.emit_event("queued", unit, grenade_name, state, fixed_t, {
			rule = rule,
			input = aim_input,
			component = component,
		})
		if _debug_enabled() then
			local component_state = _grenade_runtime.describe_action_component_state(unit, component)
			_debug_log(
				"grenade_ability_activate:" .. tostring(unit),
				fixed_t,
				"ability blitz activated "
					.. grenade_name
					.. " on "
					.. component
					.. " (rule="
					.. tostring(rule)
					.. ")"
					.. component_state
			)
		end
	else
		local weapon_action = unit_data_extension and unit_data_extension:read_component("weapon_action")
		local weapon_template_name = weapon_action and weapon_action.template_name or "none"

		if wielded_slot == "slot_unarmed" or weapon_template_name == "unarmed" then
			if _debug_enabled() then
				_debug_log(
					"grenade_unarmed:" .. grenade_name .. ":" .. tostring(unit),
					fixed_t,
					"grenade deferred while unarmed (slot="
						.. tostring(wielded_slot)
						.. ", template="
						.. tostring(weapon_template_name)
						.. ")"
				)
			end
			return
		end

		local blocked, blocking_ability, lock_reason, held_slot =
			_grenade_runtime.foreign_weapon_switch_lock(unit, "slot_grenade_ability")
		if blocked then
			state.stage = "wield"
			_grenade_runtime.abort_slot_locked(
				unit,
				state,
				fixed_t,
				blocking_ability,
				lock_reason,
				held_slot,
				"grenade_fallback.launch",
				launch_t0
			)
			return
		end

		-- Item-based grenade: wield the grenade slot first.
		state.stage = "wield"
		state.deadline_t = fixed_t + WIELD_TIMEOUT_S
		if not aim_input then
			state.release_t = fixed_t
		end
		action_input_extension:bot_queue_action_input("weapon_action", "grenade_ability", nil)
		_grenade_runtime.emit_event("queued", unit, grenade_name, state, fixed_t, {
			rule = rule,
			input = "grenade_ability",
		})
		if _debug_enabled() then
			_debug_log(
				"grenade_wield:" .. tostring(unit),
				fixed_t,
				"grenade queued wield for " .. grenade_name .. " (rule=" .. tostring(rule) .. ")"
			)
		end
	end
	_grenade_runtime.finish_child_perf("grenade_fallback.launch", launch_t0)
end

-- Called from BetterBots.lua use_ability_charge hook for grenade_ability.
-- Used by _grenade_runtime.has_confirmed_charge() to confirm blitz/grenade completion.
local function record_charge_event(unit, grenade_name, fixed_t)
	_grenade_runtime.record_charge_event(unit, grenade_name, fixed_t)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
		_event_log = deps.event_log
		_is_suppressed = deps.is_suppressed
		_grenade_state_by_unit = deps.grenade_state_by_unit
		_perf = deps.perf
		_warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold
		_grenade_profiles = deps.grenade_profiles
		assert(_grenade_profiles, "BetterBots: grenade_fallback requires grenade_profiles")
		_grenade_profiles.init({
			warp_weapon_peril_threshold = _warp_weapon_peril_threshold,
		})
		_grenade_aim = deps.grenade_aim
		assert(_grenade_aim, "BetterBots: grenade_fallback requires grenade_aim")
		_grenade_aim.init({
			mod = _mod,
			debug_log = _debug_log,
			debug_enabled = _debug_enabled,
			grenade_profiles = _grenade_profiles,
		})
		_grenade_runtime = deps.grenade_runtime
		assert(_grenade_runtime, "BetterBots: grenade_fallback requires grenade_runtime")
		_grenade_runtime.init({
			debug_log = _debug_log,
			debug_enabled = _debug_enabled,
			fixed_time = _fixed_time,
			event_log = deps.event_log,
			bot_slot_for_unit = deps.bot_slot_for_unit,
			perf = _perf,
			grenade_state_by_unit = _grenade_state_by_unit,
			last_grenade_charge_event_by_unit = deps.last_grenade_charge_event_by_unit,
			grenade_aim = _grenade_aim,
			default_throw_delay_s = DEFAULT_THROW_DELAY_S,
			retry_cooldown_s = RETRY_COOLDOWN_S,
			slot_lock_retry_s = SLOT_LOCK_RETRY_S,
			active_weapon_charge_action = ACTIVE_WEAPON_CHARGE_ACTION,
		})
	end,
	wire = function(refs)
		_build_context = refs.build_context
		_evaluate_grenade_heuristic = refs.evaluate_grenade_heuristic
		_equipped_grenade_ability = refs.equipped_grenade_ability
		_is_combat_ability_active = refs.is_combat_ability_active
		_is_grenade_enabled = refs.is_grenade_enabled
		_grenade_runtime.wire({
			equipped_grenade_ability = _equipped_grenade_ability,
			normalize_grenade_context = refs.normalize_grenade_context,
			query_weapon_switch_lock = refs.query_weapon_switch_lock,
		})
		_grenade_aim.wire({
			bot_targeting = refs.bot_targeting,
			equipped_grenade_ability = _equipped_grenade_ability,
			resolve_grenade_projectile_data = refs.resolve_grenade_projectile_data,
			solve_ballistic_rotation = refs.solve_ballistic_rotation,
		})
	end,
	try_queue = try_queue,
	record_charge_event = record_charge_event,
	prime_weapon_templates = function(WeaponTemplates)
		return _grenade_aim.prime_weapon_templates(WeaponTemplates)
	end,
	should_block_wield_input = function(unit)
		return _grenade_runtime.should_block_wield_input(unit)
	end,
	should_lock_weapon_switch = function(unit)
		return _grenade_runtime.should_lock_weapon_switch(unit)
	end,
	should_block_weapon_action_input = function(unit, action_input)
		return _grenade_runtime.should_block_weapon_action_input(unit, action_input)
	end,
}
