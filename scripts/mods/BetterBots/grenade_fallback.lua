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
local _bot_slot_for_unit
local _is_suppressed
local _perf

-- Late-bound cross-module refs (set via wire)
local _build_context
local _evaluate_grenade_heuristic
local _equipped_grenade_ability
local _is_combat_ability_active
local _is_grenade_enabled
local _normalize_grenade_context
local _query_weapon_switch_lock
local _resolve_bot_target_unit_fn
local _resolve_grenade_projectile_data
local _solve_ballistic_rotation

-- State tracking (weak-keyed by unit)
local _grenade_state_by_unit
local _last_grenade_charge_event_by_unit
local _weapon_template_by_inventory_item_name
local _projectile_template_by_inventory_item_name

-- Timing constants
local WIELD_TIMEOUT_S = 2.0 -- Abort if slot hasn't changed; covers slowest standard wield (~1.5s)
local AIM_DELAY_S = 0.15 -- Minimum hold before queueing aim_hold (lets wield animation settle)
local DEFAULT_THROW_DELAY_S = 0.3 -- Default hold after aim_hold before releasing
local UNWIELD_TIMEOUT_S = 3.0 -- Wait for auto-unwield after throw; force if exceeded
local RETRY_COOLDOWN_S = 2.0 -- Shared cooldown after a throw attempt finishes or aborts
local SLOT_LOCK_RETRY_S = 0.35 -- Fast retry when another BetterBots sequence is holding a different slot
local BALLISTIC_GRAVITY_EPSILON = 0.5 -- Gravity below this treated as non-ballistic (flat aim)
local ACCEPTABLE_ACCURACY = 0.1 -- Trajectory solver convergence tolerance (radians)

-- Maps player-ability names → throw profile.
-- Number value: throw_delay seconds, uses default aim_hold/aim_released/auto-unwield.
-- Boolean true: supported but defers to _resolve_template_entry for dynamic profile
--   selection (used by psyker_throwing_knives for aimed vs fast dispatch).
-- Table value: {
--   aim_input, followup_input, followup_delay, release_input, throw_delay,
--   auto_unwield, component
-- } for custom chains.
--   aim_input:     input to queue after wield (nil = auto-fires, skip to wait_unwield)
--   followup_input: optional second input before the final release (e.g. charged Chain Lightning)
--   followup_delay: seconds between aim_input and followup_input
--   release_input: input to queue after throw_delay (nil = skip wait_throw)
--   throw_delay:   seconds between aim and release (default DEFAULT_THROW_DELAY_S);
--                  only used when both aim_input and release_input are non-nil
--   auto_unwield:  engine auto-chains unwield? (default true; false = force immediately)
--   component:     ActionInputParser component (nil = "weapon_action" with slot wield;
--                  "grenade_ability_action" = ability-based, no slot change)
local SUPPORTED_THROW_TEMPLATES = {
	-- Veteran (standard generator, chain_time=0.1)
	veteran_frag_grenade = DEFAULT_THROW_DELAY_S,
	veteran_smoke_grenade = DEFAULT_THROW_DELAY_S,
	-- Veteran (handleless generator, chain_time=0.8)
	veteran_krak_grenade = 1.0,
	-- Zealot (standard/handleless)
	zealot_fire_grenade = DEFAULT_THROW_DELAY_S,
	zealot_shock_grenade = 1.0,
	-- Psyker blitz (wielded grenade-slot weapon templates)
	psyker_throwing_knives = true,
	psyker_chain_lightning = {
		-- Use the charged crowd-control path, not the light quick-stun path:
		-- charge_heavy -> shoot_heavy_hold -> shoot_heavy_hold_release.
		aim_input = "charge_heavy",
		followup_input = "shoot_heavy_hold",
		followup_delay = 0.8,
		release_input = "shoot_heavy_hold_release",
		throw_delay = 0.9,
		auto_unwield = true,
		allow_external_wield_cleanup = true,
		confirmation_action = "action_spread_charged",
	},
	psyker_smite = {
		aim_input = "charge_power_sticky",
		followup_input = "use_power",
		followup_delay = 2.0,
		auto_unwield = true,
		allow_external_wield_cleanup = true,
		confirmation_action = "action_use_power",
	},
	-- Ogryn (standard generator with per-template overrides)
	ogryn_grenade_box = 1.1, -- chain_time=0.9
	ogryn_grenade_box_cluster = 1.1, -- chain_time=0.9
	ogryn_grenade_frag = 0.8, -- chain_time=0.6
	ogryn_grenade_friend_rock = 0.6, -- chain_time=0.4
	-- Arbites (standard generator, chain_time=0.1)
	adamant_grenade = DEFAULT_THROW_DELAY_S,
	adamant_grenade_improved = DEFAULT_THROW_DELAY_S,
	-- Hive Scum (handleless generator, chain_time=0.8)
	broker_flash_grenade = 1.0,
	broker_flash_grenade_improved = 1.0,
	broker_tox_grenade = DEFAULT_THROW_DELAY_S,
	-- Arbites shock mine (mine generator, aim_hold chain_time=0.8)
	adamant_shock_mine = 1.0,
	-- Zealot throwing knives (auto-fires on wield via quick_throw, auto-unwields after last charge)
	zealot_throwing_knives = {
		auto_unwield = true,
	},
	-- Arbites whistle (ability-based: fires through grenade_ability_action, no slot wield)
	adamant_whistle = {
		component = "grenade_ability_action",
		aim_input = "aim_pressed",
		release_input = "aim_released",
		throw_delay = 0.15,
	},
	-- Hive Scum missile launcher (queue shoot_charge, rest auto-chains; DLC-blocked)
	broker_missile_launcher = {
		aim_input = "shoot_charge",
		auto_unwield = true,
	},
}

local ASSAIL_FAST_PROFILE = {
	aim_input = "shoot",
	auto_unwield = true,
	allow_external_wield_cleanup = true,
	require_charge_confirmation = true,
}

local ASSAIL_AIMED_PROFILE = {
	aim_input = "zoom",
	followup_input = "zoom_shoot",
	followup_delay = 0.5,
	auto_unwield = true,
	allow_external_wield_cleanup = true,
	confirmation_action = "action_rapid_zoomed",
	require_charge_confirmation = true,
}

local EXCLUDED_FLAT_GRENADE_NAMES = {
	adamant_shock_mine = true,
	adamant_whistle = true,
	broker_missile_launcher = true,
	psyker_chain_lightning = true,
	psyker_smite = true,
	psyker_throwing_knives = true,
}

local function _extract_projectile_template(weapon_template)
	if not weapon_template then
		return nil
	end

	if weapon_template.projectile_template then
		return weapon_template.projectile_template
	end

	local actions = weapon_template.actions
	if not actions then
		return nil
	end

	for _, action in pairs(actions) do
		if action.projectile_template then
			return action.projectile_template
		end
	end

	return nil
end

local function _prime_weapon_template_index(WeaponTemplates)
	_weapon_template_by_inventory_item_name = {}

	for _, weapon_template in pairs(WeaponTemplates or {}) do
		local projectile_template = _extract_projectile_template(weapon_template)
		local item_name = projectile_template and projectile_template.item_name
		if item_name and not _weapon_template_by_inventory_item_name[item_name] then
			_weapon_template_by_inventory_item_name[item_name] = weapon_template
		end
	end
end

local function _weapon_template_by_item_name(inventory_item_name)
	if not inventory_item_name then
		return nil
	end

	if not _weapon_template_by_inventory_item_name then
		_prime_weapon_template_index(require("scripts/settings/equipment/weapon_templates/weapon_templates"))
	end

	return _weapon_template_by_inventory_item_name[inventory_item_name]
end

local function _projectile_template_by_item_name(inventory_item_name)
	if not inventory_item_name then
		return nil
	end

	if not _projectile_template_by_inventory_item_name then
		_projectile_template_by_inventory_item_name = {}
		local ProjectileTemplates = require("scripts/settings/projectile/projectile_templates")

		for _, projectile_template in pairs(ProjectileTemplates) do
			local item_name = projectile_template and projectile_template.item_name
			if item_name and not _projectile_template_by_inventory_item_name[item_name] then
				_projectile_template_by_inventory_item_name[item_name] = projectile_template
			end
		end
	end

	return _projectile_template_by_inventory_item_name[inventory_item_name]
end

local function _default_resolve_grenade_projectile_data(unit, grenade_name)
	if EXCLUDED_FLAT_GRENADE_NAMES[grenade_name] then
		return {
			mode = "flat",
			reason = "excluded_family",
		}
	end

	local grenade_ability = _equipped_grenade_ability and select(2, _equipped_grenade_ability(unit))
	local inventory_item_name = grenade_ability and grenade_ability.inventory_item_name
	if not inventory_item_name then
		return {
			mode = "flat",
			reason = "inventory_item_missing",
		}
	end

	local weapon_template = _weapon_template_by_item_name(inventory_item_name)
	local projectile_template = weapon_template and _extract_projectile_template(weapon_template)
		or _projectile_template_by_item_name(inventory_item_name)
	if not projectile_template then
		return {
			mode = "flat",
			reason = "projectile_template_missing",
		}
	end

	local locomotion_template = projectile_template and projectile_template.locomotion_template
	local integrator_parameters = locomotion_template and locomotion_template.integrator_parameters
	local trajectory_parameters = locomotion_template and locomotion_template.trajectory_parameters
	local throw_parameters = trajectory_parameters and trajectory_parameters.throw
	local spawn_parameters = locomotion_template and locomotion_template.spawn_projectile_parameters
	local speed = throw_parameters and (throw_parameters.speed_maximal or throw_parameters.speed_initial)
		or spawn_parameters and spawn_parameters.initial_speed
	local gravity = integrator_parameters and integrator_parameters.gravity

	if not speed then
		return {
			mode = "flat",
			reason = "speed_missing",
		}
	end

	if not gravity or gravity <= BALLISTIC_GRAVITY_EPSILON then
		return {
			mode = "flat",
			reason = "non_ballistic_projectile",
		}
	end

	return {
		mode = "ballistic",
		speed = speed,
		gravity = gravity,
	}
end

local function _target_velocity(target_unit)
	-- Player units use PlayerUnitDataExtension (has read_component); minions use
	-- MinionUnitDataExtension (has breed/faction only). Guard the component path.
	local unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if unit_data_extension and unit_data_extension.read_component then
		local locomotion_component = unit_data_extension:read_component("locomotion")
		if locomotion_component and locomotion_component.velocity_current then
			return locomotion_component.velocity_current
		end
	end

	local locomotion_extension = ScriptUnit.has_extension(target_unit, "locomotion_system")
	if locomotion_extension and locomotion_extension.current_velocity then
		return locomotion_extension:current_velocity()
	end

	return Vector3.zero()
end

local _Trajectory

local function _default_solve_ballistic_rotation(unit, aim_unit, projectile_data)
	if not _Trajectory then
		_Trajectory = require("scripts/utilities/trajectory")
	end

	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit]
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[aim_unit]
	if not unit_position or not target_position then
		return nil, "position_lookup_missing"
	end

	local target_velocity = _target_velocity(aim_unit)
	local angle, solved_target_position = _Trajectory.angle_to_hit_moving_target(
		unit_position,
		target_position,
		projectile_data.speed,
		target_velocity,
		projectile_data.gravity,
		ACCEPTABLE_ACCURACY,
		false
	)
	if not angle then
		return nil, "trajectory_solver_failed"
	end

	local delta_flat = Vector3.flat(solved_target_position - unit_position)
	if Vector3.length_squared(delta_flat) < 0.001 then
		return nil, "degenerate_direction"
	end
	local flat_direction = Vector3.normalize(delta_flat)
	local look_rotation = Quaternion.look(flat_direction, Vector3.up())
	return Quaternion.multiply(look_rotation, Quaternion(Vector3.right(), angle))
end

local function _resolve_template_entry(grenade_name, context, rule)
	if grenade_name ~= "psyker_throwing_knives" then
		return SUPPORTED_THROW_TEMPLATES[grenade_name]
	end

	local target_distance = context and context.target_enemy_distance or 0
	local rule_text = tostring(rule or "")

	if
		target_distance >= 8
		and (string.find(rule_text, "priority", 1, true) or string.find(rule_text, "ranged_pressure", 1, true))
	then
		return ASSAIL_AIMED_PROFILE
	end

	return ASSAIL_FAST_PROFILE
end

local function _resolve_aim_unit(context)
	if _resolve_bot_target_unit_fn then
		return _resolve_bot_target_unit_fn(context)
	end

	if not context then
		return nil
	end

	return context.target_enemy
		or context.priority_target_enemy
		or context.opportunity_target_enemy
		or context.urgent_target_enemy
end

local function _prepare_grenade_context(unit, context)
	if not context then
		return nil
	end

	local aim_unit = _resolve_aim_unit(context)
	if _normalize_grenade_context then
		context = _normalize_grenade_context(unit, context, aim_unit)
	end

	return context
end

local function _finish_child_perf(tag, start_clock)
	if start_clock and _perf then
		_perf.finish(tag, start_clock, nil, { include_total = false })
	end
end

-- Aim the bot toward a target unit for grenade/blitz release. For ballistic grenades,
-- solves a trajectory arc; falls back to flat aim when the solver fails or projectile
-- data is unavailable. Returns (success, aim_mode, reason).
local function _set_bot_aim(unit, aim_unit, grenade_name)
	if not aim_unit then
		return false, nil, "no_target_unit"
	end

	if not POSITION_LOOKUP then
		return false, nil, "position_lookup_unavailable"
	end

	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local bot_unit_input = input_extension and input_extension.bot_unit_input and input_extension:bot_unit_input()
	if not bot_unit_input then
		return false, nil, "bot_input_missing"
	end

	local projectile_data = _resolve_grenade_projectile_data and _resolve_grenade_projectile_data(unit, grenade_name)
		or nil
	if projectile_data and projectile_data.mode == "ballistic" then
		local wanted_rotation, reason = _solve_ballistic_rotation(unit, aim_unit, projectile_data)
		if wanted_rotation then
			bot_unit_input:set_aiming(true, false, true)
			bot_unit_input:set_aim_rotation(wanted_rotation)

			return true, "ballistic", nil
		end

		local aim_position = POSITION_LOOKUP[aim_unit]
		if not aim_position then
			return false, nil, "target_position_missing"
		end

		bot_unit_input:set_aiming(true, false, false)
		bot_unit_input:set_aim_position(aim_position)

		return true, "flat", reason
	end

	local aim_position = POSITION_LOOKUP[aim_unit]
	if not aim_position then
		return false, nil, "target_position_missing"
	end

	bot_unit_input:set_aiming(true, false, false)
	bot_unit_input:set_aim_position(aim_position)

	return true, "flat", projectile_data and projectile_data.reason or "projectile_data_unavailable"
end

-- Release explicit bot aim state on reset so grenade sequences do not leave the
-- bot stuck in an aimed posture after completion or abort.
local function _clear_bot_aim(unit)
	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local bot_unit_input = input_extension and input_extension.bot_unit_input and input_extension:bot_unit_input()
	if not bot_unit_input then
		return false, "bot input missing"
	end

	bot_unit_input:set_aiming(false, false, false)
	return true
end

local function _refresh_bot_aim(unit, state, context, fixed_t)
	local resolved_aim_unit = _resolve_aim_unit(context)
	if resolved_aim_unit then
		state.aim_unit = resolved_aim_unit
	end
	state.aim_distance = context and context.target_enemy_distance or nil

	if not state.aim_unit then
		if _debug_enabled() then
			_debug_log(
				"grenade_aim_no_target:" .. tostring(unit),
				fixed_t,
				"grenade aim unavailable (no target unit resolved)"
			)
		end
		return false
	end

	local aim_ok, aim_mode, aim_reason = _set_bot_aim(unit, state.aim_unit, state.grenade_name)
	if aim_ok then
		if _debug_enabled() then
			if aim_mode == "ballistic" then
				_debug_log("grenade_aim_ballistic:" .. tostring(unit), fixed_t, "grenade aim ballistic")
			else
				_debug_log(
					"grenade_aim_flat_fallback:" .. tostring(unit),
					fixed_t,
					"grenade aim flat fallback (" .. tostring(aim_reason) .. ")"
				)
			end
		end
		return true
	end

	if _debug_enabled() then
		_debug_log(
			"grenade_aim_unavailable:" .. tostring(unit),
			fixed_t,
			"grenade aim unavailable (" .. tostring(aim_reason) .. ")"
		)
	end

	return false
end

local function _reset_state(unit, state, next_try_t)
	local cleared_aim, clear_reason = _clear_bot_aim(unit)
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
	state.release_input = nil
	state.auto_unwield = nil
	state.component = nil
	state.allow_external_wield_cleanup = nil
	state.confirmation_action = nil
	state.confirmation_logged = nil
	state.require_charge_confirmation = nil
	state.last_blocked_foreign_input = nil
	state.aim_unit = nil
	state.aim_distance = nil
	state.attempt_id = nil
	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local function _distance_bucket(distance)
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

local function _has_confirmed_charge(state, unit)
	local charge_event = _last_grenade_charge_event_by_unit[unit]
	if not charge_event or charge_event.grenade_name ~= state.grenade_name then
		return false
	end

	local charge_t = charge_event.fixed_t
	local release_t = state.release_t

	return charge_t ~= nil and release_t ~= nil and charge_t >= release_t
end

-- Block BT weapon switches for the full grenade sequence, including wait_unwield.
-- The post-throw unwield chain must stay free to run, but the BT still must not
-- switch to another weapon and cut the throw sequence short.
local function should_block_wield_input(unit)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage then
		return false
	end
	if state.stage == "wait_unwield" and state.allow_external_wield_cleanup then
		-- Assail has no chain-time gate here; keep the BT from switching away
		-- before the projectile actually consumes a charge.
		if
			state.require_charge_confirmation
			and not _has_confirmed_charge(state, unit)
			and (not state.deadline_t or _fixed_time() < state.deadline_t)
		then
			return true, state.grenade_name or "grenade_ability"
		end
		return false
	end
	return true, state.grenade_name or "grenade_ability"
end

local function should_lock_weapon_switch(unit)
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

local function _expected_weapon_action_input(state)
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

local function should_block_weapon_action_input(unit, action_input)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage or action_input == "wield" then
		return false
	end

	local expected_input = _expected_weapon_action_input(state)
	if expected_input and action_input == expected_input then
		return false
	end

	return true, state.grenade_name or "grenade_ability", state.stage
end

local function _queue_weapon_input(unit, input_name, component)
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

local _emit_grenade_decision
local _emit_grenade_event

local function _abort_missing_action_input(unit, state, fixed_t, input_name, stage_t0)
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
	_emit_grenade_event(
		"blocked",
		unit,
		state.grenade_name,
		state,
		fixed_t,
		{ reason = "action_input_missing", input = tostring(input_name), stage = tostring(state.stage) }
	)
	_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
	_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
end

local function _abort_slot_locked(unit, state, fixed_t, blocking_ability, lock_reason, held_slot, perf_tag, start_clock)
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

	_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, {
		reason = "slot_locked",
		blocked_by = blocking_ability,
		lock_reason = lock_reason,
		held_slot = held_slot,
	})
	_reset_state(unit, state, fixed_t + SLOT_LOCK_RETRY_S)
	_finish_child_perf(perf_tag, start_clock)
end

local function _describe_action_component_state(unit, component_name)
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

_emit_grenade_decision = function(unit, grenade_name, should_throw, rule, context, fixed_t)
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

_emit_grenade_event = function(event_type, unit, grenade_name, state, fixed_t, extra)
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
		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_no_unit_data:" .. tostring(unit),
				fixed_t,
				"grenade aborted stage=" .. tostring(state.stage) .. ": unit_data_system missing"
			)
		end
		_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "unit_data_missing" })
		_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
	local active_context
	if state.stage and state.stage ~= "wait_unwield" then
		active_context = _build_context(unit, blackboard)
		active_context = _prepare_grenade_context(unit, active_context)
		if not _refresh_bot_aim(unit, state, active_context, fixed_t) then
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "aim_lost" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end
	end

	if state.stage == "wield" then
		if not state.aim_input and _has_confirmed_charge(state, unit) then
			if wielded_slot == "slot_grenade_ability" then
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.unwield_requested_t = nil
				_emit_grenade_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
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
				_emit_grenade_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "auto_fire" })
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			end
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if wielded_slot == "slot_grenade_ability" then
			if not state.aim_input then
				-- Auto-fire template: skip aim/throw, go straight to wait_unwield
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
				_emit_grenade_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
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
				_emit_grenade_event("grenade_stage", unit, state.grenade_name, state, fixed_t)
				if _debug_enabled() then
					_debug_log(
						"grenade_wield_ok:" .. tostring(unit),
						fixed_t,
						"grenade wield confirmed, waiting for aim"
					)
				end
			end
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		local blocked, blocking_ability, lock_reason, held_slot =
			_foreign_weapon_switch_lock(unit, "slot_grenade_ability")
		if blocked then
			_abort_slot_locked(
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
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "wield_timeout" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		end

		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_aim" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_aim_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during aim (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local context = active_context or _prepare_grenade_context(unit, _build_context(unit, blackboard))
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
				_emit_grenade_event(
					"blocked",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = "revalidation", rule = rule }
				)
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
				return
			end

			local aim = state.aim_input or "aim_hold"
			if not _queue_weapon_input(unit, aim, state.component) then
				_abort_missing_action_input(unit, state, fixed_t, aim, stage_t0)
				return
			end
			if state.followup_input then
				state.stage = "wait_followup"
				state.wait_t = fixed_t + (state.followup_delay or DEFAULT_THROW_DELAY_S)
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
			_emit_grenade_event("grenade_stage", unit, state.grenade_name, state, fixed_t, { input = aim })
			if _debug_enabled() then
				_debug_log("grenade_aim:" .. tostring(unit), fixed_t, "grenade queued " .. aim)
			end
		end

		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_followup" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_followup_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during followup (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local followup = state.followup_input
			if not _queue_weapon_input(unit, followup, state.component) then
				_abort_missing_action_input(unit, state, fixed_t, followup, stage_t0)
				return
			end
			if state.release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			else
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
			end
			_emit_grenade_event(
				"grenade_stage",
				unit,
				state.grenade_name,
				state,
				fixed_t,
				{ input = tostring(followup) }
			)
			if _debug_enabled() then
				_debug_log("grenade_followup:" .. tostring(unit), fixed_t, "grenade queued " .. tostring(followup))
			end
		end

		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_throw" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			if _debug_enabled() then
				_debug_log(
					"grenade_throw_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during throw (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "lost_wield" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local release = state.release_input or "aim_released"
			if not _queue_weapon_input(unit, release, state.component) then
				_abort_missing_action_input(unit, state, fixed_t, release, stage_t0)
				return
			end
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			_emit_grenade_event("grenade_stage", unit, state.grenade_name, state, fixed_t, { input = release })
			if _debug_enabled() then
				local component_state = state.component and _describe_action_component_state(unit, state.component)
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
						.. _distance_bucket(state.aim_distance)
						.. ")"
				)
			end
		end

		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	if state.stage == "wait_unwield" then
		-- Ability-based blitz: no slot change occurred, no unwield needed.
		-- Just wait for charge confirmation or timeout, then reset.
		if state.component then
			if _has_confirmed_charge(state, unit) or fixed_t >= (state.deadline_t or 0) then
				local charge_ok = _has_confirmed_charge(state, unit)
				if _debug_enabled() then
					local reason = charge_ok and "charge confirmed" or "timeout"
					local component_state = _describe_action_component_state(unit, state.component)
					_debug_log(
						"grenade_ability_complete:" .. tostring(unit),
						fixed_t,
						"ability blitz complete (" .. reason .. ")" .. component_state
					)
				end
				_emit_grenade_event(
					charge_ok and "complete" or "blocked",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = charge_ok and "charge_confirmed" or "timeout" }
				)
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			end
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
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
				_emit_grenade_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "slot_changed" })
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
				_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
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
						.. _distance_bucket(state.aim_distance)
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
				_emit_grenade_event(
					"complete",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = "action_confirmed" }
				)
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
				_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
				return
			end

			if _has_confirmed_charge(state, unit) then
				if _debug_enabled() then
					_debug_log(
						"grenade_external_cleanup_charge:" .. tostring(unit),
						fixed_t,
						"grenade released cleanup lock without explicit unwield (charge confirmed)"
					)
				end
				_emit_grenade_event(
					"complete",
					unit,
					state.grenade_name,
					state,
					fixed_t,
					{ reason = "charge_confirmed" }
				)
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
				_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
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
				_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "timeout" })
				_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			end
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
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
			_emit_grenade_event("complete", unit, state.grenade_name, state, fixed_t, { reason = "slot_returned" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		-- For non-auto-unwield templates, force unwield immediately.
		-- The engine won't auto-chain unwield_to_previous for these.
		if state.auto_unwield == false and not state.unwield_requested_t then
			if not _queue_weapon_input(unit, "unwield_to_previous") then
				_abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
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
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if not state.unwield_requested_t and _has_confirmed_charge(state, unit) then
			if not _queue_weapon_input(unit, "unwield_to_previous") then
				_abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
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
			_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			if not _queue_weapon_input(unit, "unwield_to_previous") then
				_abort_missing_action_input(unit, state, fixed_t, "unwield_to_previous", stage_t0)
				return
			end
			if _debug_enabled() then
				_debug_log(
					"grenade_unwield_forced:" .. tostring(unit),
					fixed_t,
					"grenade forced unwield_to_previous on timeout"
				)
			end
			_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "unwield_timeout" })
			_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
		end

		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		return
	end

	-- Unknown stage — log and reset rather than falling through to idle.
	if state.stage ~= nil then
		_finish_child_perf("grenade_fallback.stage_machine", stage_t0)
		if _debug_enabled() then
			_debug_log(
				"grenade_unknown_stage:" .. tostring(unit),
				fixed_t,
				"grenade unknown stage=" .. tostring(state.stage) .. ", resetting"
			)
		end
		_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, { reason = "unknown_stage" })
		_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
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
	context = _prepare_grenade_context(unit, context)
	if ctx_t0 and _perf then
		_perf.finish("grenade_fallback.build_context", ctx_t0, nil, { include_total = false })
	end
	local heur_t0 = _perf and _perf.begin() or nil
	local should_throw, rule = _evaluate_grenade_heuristic(grenade_name, context)
	if heur_t0 and _perf then
		_perf.finish("grenade_fallback.heuristic", heur_t0, nil, { include_total = false })
	end
	_emit_grenade_decision(unit, grenade_name, should_throw, rule, context, fixed_t)
	if not should_throw then
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

	local profile_t0 = _perf and _perf.begin() or nil
	local template_entry = _resolve_template_entry(grenade_name, context, rule)
	if not template_entry then
		_finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
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
	end

	-- Pre-flight: don't enter the state machine without a target for aimed throws.
	-- Wielding auto-fire templates (zealot knives) triggers the throw immediately,
	-- so aborting after wield is too late — the charge is already consumed.
	if aim_input then
		local aim_unit = _resolve_aim_unit(context)
		if not aim_unit then
			_finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
			return
		end
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		_finish_child_perf("grenade_fallback.profile_resolution", profile_t0)
		return
	end
	_finish_child_perf("grenade_fallback.profile_resolution", profile_t0)

	local launch_t0 = _perf and _perf.begin() or nil
	state.throw_delay = throw_delay
	state.grenade_name = grenade_name
	state.aim_input = aim_input
	state.followup_input = followup_input
	state.followup_delay = followup_delay
	state.release_input = release_input
	state.release_t = nil
	state.auto_unwield = auto_unwield
	state.component = component
	state.allow_external_wield_cleanup = type(template_entry) == "table"
		and template_entry.allow_external_wield_cleanup == true
	state.confirmation_action = confirmation_action
	state.confirmation_logged = nil
	state.require_charge_confirmation = type(template_entry) == "table"
		and template_entry.require_charge_confirmation == true

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
		_emit_grenade_event("queued", unit, grenade_name, state, fixed_t, {
			rule = rule,
			input = aim_input,
			component = component,
		})
		if _debug_enabled() then
			local component_state = _describe_action_component_state(unit, component)
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
			_foreign_weapon_switch_lock(unit, "slot_grenade_ability")
		if blocked then
			state.stage = "wield"
			_abort_slot_locked(
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
		_emit_grenade_event("queued", unit, grenade_name, state, fixed_t, {
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
	_finish_child_perf("grenade_fallback.launch", launch_t0)
end

-- Called from BetterBots.lua use_ability_charge hook for grenade_ability.
-- Used by _has_confirmed_charge() to confirm blitz/grenade completion.
local function record_charge_event(unit, grenade_name, fixed_t)
	_last_grenade_charge_event_by_unit[unit] = {
		grenade_name = grenade_name,
		fixed_t = fixed_t,
	}
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
		_event_log = deps.event_log
		_bot_slot_for_unit = deps.bot_slot_for_unit
		_is_suppressed = deps.is_suppressed
		_grenade_state_by_unit = deps.grenade_state_by_unit
		_last_grenade_charge_event_by_unit = deps.last_grenade_charge_event_by_unit
		_perf = deps.perf
		_weapon_template_by_inventory_item_name = nil
		_projectile_template_by_inventory_item_name = nil
	end,
	wire = function(refs)
		_build_context = refs.build_context
		_evaluate_grenade_heuristic = refs.evaluate_grenade_heuristic
		_equipped_grenade_ability = refs.equipped_grenade_ability
		_is_combat_ability_active = refs.is_combat_ability_active
		_is_grenade_enabled = refs.is_grenade_enabled
		_normalize_grenade_context = refs.normalize_grenade_context
		_query_weapon_switch_lock = refs.query_weapon_switch_lock
		_resolve_grenade_projectile_data = refs.resolve_grenade_projectile_data
			or _default_resolve_grenade_projectile_data
		_solve_ballistic_rotation = refs.solve_ballistic_rotation or _default_solve_ballistic_rotation
		local bot_targeting = refs.bot_targeting
		_resolve_bot_target_unit_fn = bot_targeting and bot_targeting.resolve_bot_target_unit or nil
	end,
	try_queue = try_queue,
	record_charge_event = record_charge_event,
	prime_weapon_templates = _prime_weapon_template_index,
	should_block_wield_input = should_block_wield_input,
	should_lock_weapon_switch = should_lock_weapon_switch,
	should_block_weapon_action_input = should_block_weapon_action_input,
}
