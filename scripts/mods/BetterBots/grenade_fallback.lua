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
local _event_log -- luacheck: ignore 231 — TODO: emit grenade_queued/grenade_complete events
local _bot_slot_for_unit -- luacheck: ignore 231 — TODO: include in EventLog emissions
local _is_suppressed

-- Late-bound cross-module refs (set via wire)
local _build_context
local _evaluate_grenade_heuristic
local _equipped_grenade_ability
local _is_combat_ability_active

-- State tracking (weak-keyed by unit)
local _grenade_state_by_unit
local _last_grenade_charge_event_by_unit

-- Timing constants
local WIELD_TIMEOUT_S = 2.0 -- Abort if slot hasn't changed; covers slowest standard wield (~1.5s)
local AIM_DELAY_S = 0.15 -- Minimum hold before queueing aim_hold (lets wield animation settle)
local DEFAULT_THROW_DELAY_S = 0.3 -- Default hold after aim_hold before releasing
local UNWIELD_TIMEOUT_S = 3.0 -- Wait for auto-unwield after throw; force if exceeded
-- Same cooldown for success and failure; split if tuning requires it.
local RETRY_COOLDOWN_S = 2.0 -- Minimum gap between throw attempts

-- Maps player-ability names → throw profile.
-- Number value: throw_delay seconds, uses default aim_hold/aim_released/auto-unwield.
-- Table value: { aim_input, release_input, throw_delay, auto_unwield, component } for custom chains.
--   aim_input:     input to queue after wield (nil = auto-fires, skip to wait_unwield)
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
	-- Psyker — no throwable grenades (smite/chain lightning/knives are blitz)
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

local function _reset_state(state, next_try_t)
	state.stage = nil
	state.deadline_t = nil
	state.wait_t = nil
	state.throw_delay = nil
	state.grenade_name = nil
	state.release_t = nil
	state.unwield_requested_t = nil
	state.aim_input = nil
	state.release_input = nil
	state.auto_unwield = nil
	state.component = nil
	if next_try_t then
		state.next_try_t = next_try_t
	end
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

-- Returns true while any grenade stage is active.
-- Used to block incoming wield action inputs from the BT for the full sequence,
-- including wait_unwield — where the wield_slot redirect must be off so that
-- action_unwield_to_previous can switch the slot, but the BT must still not
-- be able to wield a different weapon and abort the throw mid-air.
local function should_block_wield_input(unit)
	local state = _grenade_state_by_unit[unit]
	if not state or not state.stage then
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

local function _queue_weapon_input(unit, input_name, component)
	local ext = ScriptUnit.has_extension(unit, "action_input_system")
	if not ext then
		if _debug_enabled() then
			_debug_log(
				"grenade_no_ext:" .. input_name,
				_fixed_time(),
				"grenade _queue_weapon_input skipped: no action_input_extension for " .. input_name
			)
		end
		return
	end
	ext:bot_queue_action_input(component or "weapon_action", input_name, nil)
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
		if _debug_enabled() then
			_debug_log(
				"grenade_no_unit_data:" .. tostring(unit),
				fixed_t,
				"grenade aborted stage=" .. tostring(state.stage) .. ": unit_data_system missing"
			)
		end
		_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		return
	end

	local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"

	if state.stage == "wield" then
		if wielded_slot == "slot_grenade_ability" then
			if not state.aim_input then
				-- Auto-fire template: skip aim/throw, go straight to wait_unwield
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
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
				if _debug_enabled() then
					_debug_log(
						"grenade_wield_ok:" .. tostring(unit),
						fixed_t,
						"grenade wield confirmed, waiting for aim"
					)
				end
			end
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
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		end

		return
	end

	if state.stage == "wait_aim" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			if _debug_enabled() then
				_debug_log(
					"grenade_aim_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during aim (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local aim = state.aim_input or "aim_hold"
			_queue_weapon_input(unit, aim, state.component)
			if state.release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			else
				-- No release needed: skip to wait_unwield (e.g. missile auto-chains)
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
			end
			if _debug_enabled() then
				_debug_log("grenade_aim:" .. tostring(unit), fixed_t, "grenade queued " .. aim)
			end
		end

		return
	end

	if state.stage == "wait_throw" then
		if not state.component and wielded_slot ~= "slot_grenade_ability" then
			if _debug_enabled() then
				_debug_log(
					"grenade_throw_lost_wield:" .. tostring(unit),
					fixed_t,
					"grenade lost wield during throw (slot=" .. tostring(wielded_slot) .. ")"
				)
			end
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		if fixed_t >= (state.wait_t or 0) then
			local release = state.release_input or "aim_released"
			_queue_weapon_input(unit, release, state.component)
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			if _debug_enabled() then
				_debug_log("grenade_release:" .. tostring(unit), fixed_t, "grenade queued " .. release)
			end
		end

		return
	end

	if state.stage == "wait_unwield" then
		-- Ability-based blitz: no slot change occurred, no unwield needed.
		-- Just wait for charge confirmation or timeout, then reset.
		if state.component then
			if _has_confirmed_charge(state, unit) or fixed_t >= (state.deadline_t or 0) then
				if _debug_enabled() then
					local reason = _has_confirmed_charge(state, unit) and "charge confirmed" or "timeout"
					_debug_log(
						"grenade_ability_complete:" .. tostring(unit),
						fixed_t,
						"ability blitz complete (" .. reason .. ")"
					)
				end
				_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			end
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
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
			return
		end

		-- For non-auto-unwield templates, force unwield immediately.
		-- The engine won't auto-chain unwield_to_previous for these.
		if state.auto_unwield == false and not state.unwield_requested_t then
			_queue_weapon_input(unit, "unwield_to_previous")
			state.unwield_requested_t = fixed_t
			if _debug_enabled() then
				_debug_log(
					"grenade_force_unwield:" .. tostring(unit),
					fixed_t,
					"grenade forced unwield_to_previous (no auto-unwield)"
				)
			end
			return
		end

		if not state.unwield_requested_t and _has_confirmed_charge(state, unit) then
			_queue_weapon_input(unit, "unwield_to_previous")
			state.unwield_requested_t = fixed_t
			if _debug_enabled() then
				_debug_log(
					"grenade_unwield_requested:" .. tostring(unit),
					fixed_t,
					"grenade queued unwield_to_previous after charge confirmation"
				)
			end
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			_queue_weapon_input(unit, "unwield_to_previous")
			if _debug_enabled() then
				_debug_log(
					"grenade_unwield_forced:" .. tostring(unit),
					fixed_t,
					"grenade forced unwield_to_previous on timeout"
				)
			end
			_reset_state(state, fixed_t + RETRY_COOLDOWN_S)
		end

		return
	end

	-- Unknown stage — log and reset rather than falling through to idle.
	if state.stage ~= nil then
		if _debug_enabled() then
			_debug_log(
				"grenade_unknown_stage:" .. tostring(unit),
				fixed_t,
				"grenade unknown stage=" .. tostring(state.stage) .. ", resetting"
			)
		end
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
		if _debug_enabled() then
			_debug_log(
				"grenade_suppress:" .. tostring(suppress_reason),
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
		return
	end

	local ability_extension, grenade_ability = _equipped_grenade_ability(unit)
	if not ability_extension or not grenade_ability then
		return
	end

	if not ability_extension:can_use_ability("grenade_ability") then
		return
	end

	local grenade_name = grenade_ability.name or "unknown"

	local template_entry = SUPPORTED_THROW_TEMPLATES[grenade_name]
	if not template_entry then
		return
	end

	-- Resolve profile: number = default aim_hold/aim_released; table = custom profile.
	local aim_input, release_input, throw_delay, auto_unwield, component
	if type(template_entry) == "number" then
		aim_input = "aim_hold"
		release_input = "aim_released"
		throw_delay = template_entry
		auto_unwield = true
	else
		aim_input = template_entry.aim_input
		release_input = template_entry.release_input
		throw_delay = template_entry.throw_delay or DEFAULT_THROW_DELAY_S
		auto_unwield = template_entry.auto_unwield ~= false -- default true
		component = template_entry.component
	end

	local context = _build_context(unit, blackboard)
	local should_throw, rule = _evaluate_grenade_heuristic(grenade_name, context)
	if not should_throw then
		return
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		return
	end

	state.throw_delay = throw_delay
	state.grenade_name = grenade_name
	state.aim_input = aim_input
	state.release_input = release_input
	state.auto_unwield = auto_unwield
	state.component = component

	if component then
		-- Ability-based blitz: queue aim input directly on the ability component.
		-- No slot wield needed — the ability fires from any weapon slot.
		if aim_input then
			action_input_extension:bot_queue_action_input(component, aim_input, nil)
			if release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (throw_delay or DEFAULT_THROW_DELAY_S)
			else
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
			end
		else
			-- Ability-based auto-fire: just wait for charge confirmation
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
		end
		if _debug_enabled() then
			_debug_log(
				"grenade_ability_activate:" .. tostring(unit),
				fixed_t,
				"ability blitz activated " .. grenade_name .. " on " .. component .. " (rule=" .. tostring(rule) .. ")"
			)
		end
	else
		-- Item-based grenade: wield the grenade slot first.
		action_input_extension:bot_queue_action_input("weapon_action", "grenade_ability", nil)
		state.stage = "wield"
		state.deadline_t = fixed_t + WIELD_TIMEOUT_S
		if _debug_enabled() then
			_debug_log(
				"grenade_wield:" .. tostring(unit),
				fixed_t,
				"grenade queued wield for " .. grenade_name .. " (rule=" .. tostring(rule) .. ")"
			)
		end
	end
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
		_is_combat_ability_active = refs.is_combat_ability_active
	end,
	try_queue = try_queue,
	record_charge_event = record_charge_event,
	should_block_wield_input = should_block_wield_input,
	should_lock_weapon_switch = should_lock_weapon_switch,
}
