-- grenade_fallback.lua — bot grenade throw state machine (#4)
-- Wields grenade slot, aims, throws, and returns to previous weapon.
-- Only activates when charges are available and the heuristic permits.

-- Dependencies (set via init/wire)
local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled -- luacheck: ignore 231
local _fixed_time
local _event_log -- luacheck: ignore 231 — TODO: emit grenade_queued/grenade_complete events
local _bot_slot_for_unit -- luacheck: ignore 231 — TODO: include in EventLog emissions
local _is_suppressed

-- Late-bound cross-module refs (set via wire)
local _build_context
local _evaluate_grenade_heuristic
local _equipped_grenade_ability

-- State tracking (weak-keyed by unit)
local _grenade_state_by_unit
local _last_grenade_charge_event_by_unit

-- Timing constants
local WIELD_TIMEOUT_S = 2.0 -- Abort if slot hasn't changed; covers slowest standard wield (~1.5s)
local AIM_DELAY_S = 0.15 -- Minimum hold before queueing aim_hold (lets wield animation settle)
local THROW_DELAY_S = 0.3 -- Minimum hold after aim_hold before releasing
local UNWIELD_TIMEOUT_S = 3.0 -- Wait for auto-unwield after throw; force if exceeded
-- Same cooldown for success and failure; split if tuning requires it.
local RETRY_COOLDOWN_S = 2.0 -- Minimum gap between throw attempts

local function _reset_state(state, next_try_t)
	state.stage = nil
	state.deadline_t = nil
	state.wait_t = nil
	state.action_input_extension = nil
	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local function _queue_weapon_input(state, input_name)
	local ext = state.action_input_extension
	if not ext then
		_debug_log(
			"grenade_no_ext:" .. input_name,
			_fixed_time(),
			"grenade _queue_weapon_input skipped: no action_input_extension for " .. input_name
		)
		return
	end
	ext:bot_queue_action_input("weapon_action", input_name, nil)
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

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")

	-- If unit_data_extension is gone mid-sequence, abort cleanly.
	if not unit_data_extension and state.stage then
		_debug_log(
			"grenade_no_unit_data:" .. tostring(unit),
			fixed_t,
			"grenade aborted stage=" .. tostring(state.stage) .. ": unit_data_system missing"
		)
		_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"

	if state.stage == "wield" then
		if wielded_slot == "slot_grenade_ability" then
			state.stage = "wait_aim"
			state.wait_t = fixed_t + AIM_DELAY_S
			_debug_log("grenade_wield_ok:" .. tostring(unit), fixed_t, "grenade wield confirmed, waiting for aim")
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			_debug_log(
				"grenade_wield_timeout:" .. tostring(unit),
				fixed_t,
				"grenade wield timeout, resetting with retry"
			)
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		end

		return
	end

	if state.stage == "wait_aim" then
		if wielded_slot ~= "slot_grenade_ability" then
			_debug_log(
				"grenade_aim_lost_wield:" .. tostring(unit),
				fixed_t,
				"grenade lost wield during aim (slot=" .. tostring(wielded_slot) .. ")"
			)
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			_queue_weapon_input(state, "aim_hold")
			state.stage = "wait_throw"
			state.wait_t = fixed_t + THROW_DELAY_S
			_debug_log("grenade_aim_hold:" .. tostring(unit), fixed_t, "grenade queued aim_hold")
		end

		return
	end

	if state.stage == "wait_throw" then
		if wielded_slot ~= "slot_grenade_ability" then
			_debug_log(
				"grenade_throw_lost_wield:" .. tostring(unit),
				fixed_t,
				"grenade lost wield during throw (slot=" .. tostring(wielded_slot) .. ")"
			)
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			_queue_weapon_input(state, "aim_released")
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			_debug_log("grenade_aim_released:" .. tostring(unit), fixed_t, "grenade queued aim_released")
		end

		return
	end

	if state.stage == "wait_unwield" then
		if wielded_slot ~= "slot_grenade_ability" then
			_debug_log(
				"grenade_unwield_ok:" .. tostring(unit),
				fixed_t,
				"grenade throw complete, slot returned to " .. tostring(wielded_slot)
			)
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			_queue_weapon_input(state, "unwield_to_previous")
			_debug_log(
				"grenade_unwield_forced:" .. tostring(unit),
				fixed_t,
				"grenade forced unwield_to_previous on timeout"
			)
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		end

		return
	end

	-- Unknown stage — log and reset rather than falling through to idle.
	if state.stage ~= nil then
		_debug_log(
			"grenade_unknown_stage:" .. tostring(unit),
			fixed_t,
			"grenade unknown stage=" .. tostring(state.stage) .. ", resetting"
		)
		_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	-- Idle: check if we can and should throw a grenade.
	-- Guards mirror ability_queue.lua: block during interactions and suppressed states.
	local behavior = blackboard and blackboard.behavior
	if behavior and behavior.current_interaction_unit ~= nil then
		return
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		_debug_log(
			"grenade_suppress:" .. tostring(suppress_reason),
			fixed_t,
			"grenade blocked: suppressed (" .. tostring(suppress_reason) .. ")"
		)
		return
	end

	-- NOTE: No mutual exclusion with AbilityQueue yet. Both state machines run
	-- independently. In practice the heuristic + cooldown gates make simultaneous
	-- activation rare, but a shared "ability_in_progress" flag would be cleaner.

	local ability_extension, grenade_ability = _equipped_grenade_ability(unit)
	if not ability_extension or not grenade_ability then
		return
	end

	if not ability_extension:can_use_ability("grenade_ability") then
		return
	end

	local context = _build_context(unit, blackboard)
	local grenade_name = grenade_ability.name or "unknown"
	local should_throw, rule = _evaluate_grenade_heuristic(grenade_name, context)
	if not should_throw then
		_debug_log(
			"grenade_blocked:" .. tostring(unit),
			fixed_t,
			"grenade blocked for " .. grenade_name .. " (rule=" .. tostring(rule) .. ")"
		)
		return
	end

	local action_input_extension = ScriptUnit.extension(unit, "action_input_system")
	if not action_input_extension then
		return
	end

	action_input_extension:bot_queue_action_input("weapon_action", "grenade_ability", nil)

	state.stage = "wield"
	state.deadline_t = fixed_t + WIELD_TIMEOUT_S
	state.action_input_extension = action_input_extension

	_debug_log(
		"grenade_wield:" .. tostring(unit),
		fixed_t,
		"grenade queued wield for " .. grenade_name .. " (rule=" .. tostring(rule) .. ")"
	)
end

-- Called from BetterBots.lua use_ability_charge hook for grenade_ability.
-- Stores the event for observability; no read path within this module yet.
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
	end,
	wire = function(refs)
		_build_context = refs.build_context
		_evaluate_grenade_heuristic = refs.evaluate_grenade_heuristic
		_equipped_grenade_ability = refs.equipped_grenade_ability
	end,
	try_queue = try_queue,
	record_charge_event = record_charge_event,
}
