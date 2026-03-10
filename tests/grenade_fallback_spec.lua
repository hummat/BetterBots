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
	has_extension = function(unit, system_name)
		local exts = _extensions[unit]
		return exts and exts[system_name] or nil
	end,
	extension = function(unit, system_name)
		local exts = _extensions[unit]
		return exts and exts[system_name] or nil
	end,
}

-- Mock heuristic result
local _heuristic_result = true
local _heuristic_rule = "grenade_generic"

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
	_recorded_inputs = {}
	_grenade_state_by_unit = {}
	_last_grenade_charge_event_by_unit = {}

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
			return mock_ability_extension, { name = "frag_grenade" }
		end,
	})
end

describe("grenade_fallback", function()
	before_each(function()
		reset()
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
		-- State should transition to "wield"
		local state = _grenade_state_by_unit[unit]
		assert.equals("wield", state.stage)
	end)

	it("waits in wield stage until slot changes", function()
		-- Start a wield
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Still on secondary slot — should remain in wield
		_recorded_inputs = {}
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)
		assert.equals(0, #_recorded_inputs)

		-- Slot changes to grenade — should transition to wait_aim
		_wielded_slot = "slot_grenade_ability"
		_recorded_inputs = {}
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)
	end)

	it("times out wield stage and retries", function()
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Advance past wield timeout (2.0s)
		_mock_time = 13.0
		_recorded_inputs = {}
		GrenadeFallback.try_queue(unit, blackboard)

		-- Should reset to idle with retry cooldown
		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.truthy(state.next_try_t > _mock_time)
	end)

	it("queues aim_hold in wait_aim stage", function()
		-- Get to wait_aim stage
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

		-- Advance past aim delay (0.15s)
		_recorded_inputs = {}
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		-- Should have queued aim_hold
		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("aim_hold", _recorded_inputs[1].input)
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)
	end)

	it("queues aim_released in wait_throw stage", function()
		-- Get to wait_throw stage
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		_recorded_inputs = {}
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

		-- Advance past throw delay (0.3s)
		_recorded_inputs = {}
		_mock_time = 11.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("aim_released", _recorded_inputs[1].input)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)

	it("completes when slot leaves grenade in wait_unwield", function()
		-- Get to wait_unwield stage
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		-- Slot returns to secondary
		_wielded_slot = "slot_secondary"
		_recorded_inputs = {}
		_mock_time = 12.0
		GrenadeFallback.try_queue(unit, blackboard)

		-- Should reset to idle with retry cooldown
		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)
		assert.truthy(state.next_try_t > _mock_time)
	end)

	it("forces unwield on timeout in wait_unwield", function()
		-- Get to wait_unwield stage
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		-- Stay on grenade slot and advance past unwield timeout (3.0s)
		_recorded_inputs = {}
		_mock_time = 15.0
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("unwield_to_previous", _recorded_inputs[1].input)
		-- Should have reset
		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
	end)

	it("respects retry cooldown between throws", function()
		-- Complete a throw cycle
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = 10.5
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.0
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = 11.5
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_secondary"
		_mock_time = 12.0
		GrenadeFallback.try_queue(unit, blackboard)

		-- Now in cooldown
		local state = _grenade_state_by_unit[unit]
		assert.is_nil(state.stage)
		assert.truthy(state.next_try_t)

		-- Try again within cooldown
		_recorded_inputs = {}
		_mock_time = 12.5
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
end)
