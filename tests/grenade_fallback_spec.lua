-- grenade_fallback_spec.lua — tests for grenade throw state machine (#4)

-- Controllable mock time
local _mock_time = 0

-- Mock extensions per unit
local _extensions = {}

-- Recorded action_input calls
local _recorded_inputs = {}

-- Mock ability_extension
local _can_use_grenade = true

local mock_ability_extension = {
	can_use_ability = function(_self, ability_name)
		if ability_name == "grenade_ability" then
			return _can_use_grenade
		end
		return false
	end,
}

-- Mock action_input_extension
local mock_action_input_extension = {
	bot_queue_action_input = function(_self, component, input_name, extra)
		_recorded_inputs[#_recorded_inputs + 1] = {
			component = component,
			input = input_name,
			extra = extra,
		}
	end,
}

-- Mock unit_data_extension
local _wielded_slot = "slot_secondary"

local mock_unit_data_extension = {
	read_component = function(_self, component_name)
		if component_name == "inventory" then
			return { wielded_slot = _wielded_slot }
		end
		return nil
	end,
}

-- Mock ScriptUnit
_G.ScriptUnit = {
	has_extension = function(u, system_name)
		local exts = _extensions[u]
		return exts and exts[system_name] or nil
	end,
}

-- Mock heuristic result
local _heuristic_result = true
local _heuristic_rule = "grenade_generic"

-- Mock suppression
local _is_suppressed_result = false
local _is_suppressed_reason = nil

-- Load the module
local GrenadeFallback = dofile("scripts/mods/BetterBots/grenade_fallback.lua")

-- Shared state tables (weak-keyed in production, plain here)
local _grenade_state_by_unit = {}
local _last_grenade_charge_event_by_unit = {}

local unit = "bot_unit_1"
local blackboard = {}

local function reset()
	_mock_time = 10.0
	_can_use_grenade = true
	_wielded_slot = "slot_secondary"
	_heuristic_result = true
	_heuristic_rule = "grenade_generic"
	_is_suppressed_result = false
	_is_suppressed_reason = nil
	_recorded_inputs = {}
	_grenade_state_by_unit = {}
	_last_grenade_charge_event_by_unit = {}
	blackboard = {}

	_extensions[unit] = {
		ability_system = mock_ability_extension,
		action_input_system = mock_action_input_extension,
		unit_data_system = mock_unit_data_extension,
	}

	GrenadeFallback.init({
		mod = { echo = function() end },
		debug_log = function() end,
		debug_enabled = function()
			return false
		end,
		fixed_time = function()
			return _mock_time
		end,
		event_log = nil,
		bot_slot_for_unit = function()
			return "slot1"
		end,
		is_suppressed = function()
			return _is_suppressed_result, _is_suppressed_reason
		end,
		grenade_state_by_unit = _grenade_state_by_unit,
		last_grenade_charge_event_by_unit = _last_grenade_charge_event_by_unit,
	})

	GrenadeFallback.wire({
		build_context = function()
			return { num_nearby = 3 }
		end,
		evaluate_grenade_heuristic = function(_name, _ctx)
			return _heuristic_result, _heuristic_rule
		end,
		equipped_grenade_ability = function(_u)
			return mock_ability_extension, { name = "veteran_frag_grenade" }
		end,
	})
end

-- Helper: advance state machine from idle to a target stage
local function advance_to_stage(target_stage)
	GrenadeFallback.try_queue(unit, blackboard)
	if target_stage == "wield" then
		return
	end

	_wielded_slot = "slot_grenade_ability"
	_mock_time = _mock_time + 0.5
	GrenadeFallback.try_queue(unit, blackboard)
	if target_stage == "wait_aim" then
		return
	end

	_mock_time = _mock_time + 0.5
	GrenadeFallback.try_queue(unit, blackboard)
	if target_stage == "wait_throw" then
		return
	end

	_mock_time = _mock_time + 0.5
	GrenadeFallback.try_queue(unit, blackboard)
	-- now in wait_unwield
end

describe("grenade_fallback", function()
	before_each(function()
		reset()
	end)

	describe("should_block_wield_input", function()
		it("does not block outside an active grenade sequence", function()
			assert.is_false(GrenadeFallback.should_block_wield_input(unit))
		end)

		it("blocks in wield stage", function()
			advance_to_stage("wield")
			assert.is_true(GrenadeFallback.should_block_wield_input(unit))
		end)

		it("blocks in wait_unwield so BT cannot abort the throw mid-air", function()
			advance_to_stage("wait_unwield")
			assert.is_true(GrenadeFallback.should_block_wield_input(unit))
		end)
	end)

	describe("should_lock_weapon_switch", function()
		it("does not lock outside an active grenade sequence", function()
			local should_lock = GrenadeFallback.should_lock_weapon_switch(unit)
			assert.is_false(should_lock)
		end)

		it("locks weapon switches to keep grenade slot during active sequence", function()
			advance_to_stage("wait_aim")
			local should_lock, grenade_name, reason, slot_to_keep = GrenadeFallback.should_lock_weapon_switch(unit)
			assert.is_true(should_lock)
			assert.equals("veteran_frag_grenade", grenade_name)
			assert.equals("sequence", reason)
			assert.equals("slot_grenade_ability", slot_to_keep)
		end)

		it("does not lock after grenade slot is already lost", function()
			advance_to_stage("wait_aim")
			_wielded_slot = "slot_secondary"
			local should_lock = GrenadeFallback.should_lock_weapon_switch(unit)
			assert.is_false(should_lock)
		end)

		it("does not lock in wait_unwield so post-throw auto-chain can proceed", function()
			advance_to_stage("wait_unwield")
			local should_lock = GrenadeFallback.should_lock_weapon_switch(unit)
			assert.is_false(should_lock)
		end)
	end)

	it("does nothing when grenade charges depleted", function()
		_can_use_grenade = false
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("does nothing when heuristic blocks", function()
		_heuristic_result = false
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("queues grenade_ability wield when idle and heuristic passes", function()
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("grenade_ability", _recorded_inputs[1].input)
		assert.is_nil(_recorded_inputs[1].extra)
		local state = _grenade_state_by_unit[unit]
		assert.equals("wield", state.stage)
	end)

	it("waits in wield stage until slot changes", function()
		advance_to_stage("wield")
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Still on secondary slot — should remain in wield
		_recorded_inputs = {}
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)
		assert.equals(0, #_recorded_inputs)

		-- Slot changes to grenade — should transition to wait_aim
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)
	end)

	it("times out wield stage and retries", function()
		advance_to_stage("wield")

		_mock_time = 13.0
		_recorded_inputs = {}
		GrenadeFallback.try_queue(unit, blackboard)

		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.truthy(state.next_try_t > _mock_time)
	end)

	it("queues aim_hold in wait_aim stage", function()
		advance_to_stage("wait_aim")
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

		_recorded_inputs = {}
		_mock_time = _mock_time + 1.0
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("aim_hold", _recorded_inputs[1].input)
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)
	end)

	it("queues aim_released in wait_throw stage", function()
		advance_to_stage("wait_throw")
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

		_recorded_inputs = {}
		_mock_time = _mock_time + 1.0
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("aim_released", _recorded_inputs[1].input)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)

	it("completes when slot leaves grenade in wait_unwield", function()
		advance_to_stage("wait_unwield")
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		_wielded_slot = "slot_secondary"
		_recorded_inputs = {}
		_mock_time = _mock_time + 1.0
		GrenadeFallback.try_queue(unit, blackboard)

		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.truthy(state.next_try_t > _mock_time)
	end)

	it("forces unwield on timeout in wait_unwield", function()
		advance_to_stage("wait_unwield")
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		_recorded_inputs = {}
		_mock_time = _mock_time + 5.0
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("unwield_to_previous", _recorded_inputs[1].input)
		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
	end)

	it("queues explicit unwield after grenade charge confirmation", function()
		advance_to_stage("wait_unwield")
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		_mock_time = _mock_time + 0.1
		_last_grenade_charge_event_by_unit[unit] = {
			grenade_name = "veteran_frag_grenade",
			fixed_t = _mock_time,
		}

		_recorded_inputs = {}
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("unwield_to_previous", _recorded_inputs[1].input)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)

	it("ignores stale grenade charge events from before the current throw", function()
		advance_to_stage("wait_unwield")
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		_last_grenade_charge_event_by_unit[unit] = {
			grenade_name = "veteran_frag_grenade",
			fixed_t = _mock_time - 1.0,
		}

		_recorded_inputs = {}
		_mock_time = _mock_time + 0.1
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(0, #_recorded_inputs)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)

	it("respects retry cooldown between throws", function()
		-- Complete a throw cycle
		advance_to_stage("wait_unwield")
		_wielded_slot = "slot_secondary"
		_mock_time = _mock_time + 1.0
		GrenadeFallback.try_queue(unit, blackboard)

		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)

		-- Try again within cooldown
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("resets when wield lost during wait_aim", function()
		advance_to_stage("wait_aim")
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

		-- Slot changes away (e.g., stagger forced weapon switch)
		_wielded_slot = "slot_secondary"
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.1
		GrenadeFallback.try_queue(unit, blackboard)

		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.equals(0, #_recorded_inputs)
	end)

	it("resets when wield lost during wait_throw", function()
		advance_to_stage("wait_throw")
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

		-- Slot changes away
		_wielded_slot = "slot_secondary"
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.1
		GrenadeFallback.try_queue(unit, blackboard)

		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.equals(0, #_recorded_inputs)
	end)

	it("blocks when suppressed", function()
		_is_suppressed_result = true
		_is_suppressed_reason = "dodging"
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("blocks during interaction", function()
		blackboard = { behavior = { current_interaction_unit = "revive_target" } }
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("blocks unsupported blitz templates", function()
		-- Wire with a blitz template that uses a different input chain
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "psyker_chain_lightning" }
			end,
		})
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	describe("record_charge_event", function()
		it("records grenade charge event", function()
			GrenadeFallback.record_charge_event(unit, "frag_grenade", 5.0)
			assert.truthy(_last_grenade_charge_event_by_unit[unit])
			assert.equals("frag_grenade", _last_grenade_charge_event_by_unit[unit].grenade_name)
			assert.equals(5.0, _last_grenade_charge_event_by_unit[unit].fixed_t)
		end)
	end)

	describe("profile-driven blitz templates", function()
		it("treats number entries as default aim_hold/aim_released profile", function()
			-- Wire with shock_mine (number entry = same as standard grenades)
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "adamant_shock_mine" }
				end,
			})
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("grenade_ability", _recorded_inputs[1].input)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)
		end)
	end)
end)
