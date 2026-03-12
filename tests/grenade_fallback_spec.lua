-- grenade_fallback_spec.lua — tests for grenade throw state machine (#4)

-- Controllable mock time
local _mock_time = 0

-- Mock extensions per unit
local _extensions = {}

-- Recorded action_input calls
local _recorded_inputs = {}
local _debug_logs = {}
local _event_decisions = {}

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
local _component_state_by_name = {}

local mock_unit_data_extension = {
	read_component = function(_self, component_name)
		if component_name == "inventory" then
			return { wielded_slot = _wielded_slot }
		end
		return _component_state_by_name[component_name]
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

-- Mock combat ability lock
local _combat_ability_active = false
local _debug_enabled_result = false
local _grenades_enabled_result = true

-- Load the module
local GrenadeFallback = dofile("scripts/mods/BetterBots/grenade_fallback.lua")

-- Shared state tables (weak-keyed in production, plain here)
local _grenade_state_by_unit = {}
local _last_grenade_charge_event_by_unit = {}

local unit = "bot_unit_1"
local blackboard = {}

local function find_debug_log(pattern)
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			return _debug_logs[i]
		end
	end

	return nil
end

local function reset()
	_mock_time = 10.0
	_can_use_grenade = true
	_wielded_slot = "slot_secondary"
	_heuristic_result = true
	_heuristic_rule = "grenade_generic"
	_is_suppressed_result = false
	_is_suppressed_reason = nil
	_combat_ability_active = false
	_debug_enabled_result = false
	_grenades_enabled_result = true
	_recorded_inputs = {}
	_debug_logs = {}
	_event_decisions = {}
	_grenade_state_by_unit = {}
	_last_grenade_charge_event_by_unit = {}
	_component_state_by_name = {}
	blackboard = {}

	_extensions[unit] = {
		ability_system = mock_ability_extension,
		action_input_system = mock_action_input_extension,
		unit_data_system = mock_unit_data_extension,
	}

	GrenadeFallback.init({
		mod = { echo = function() end },
		debug_log = function(key, fixed_t, message)
			_debug_logs[#_debug_logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
			}
		end,
		debug_enabled = function()
			return _debug_enabled_result
		end,
		fixed_time = function()
			return _mock_time
		end,
		event_log = {
			is_enabled = function()
				return true
			end,
			emit_decision = function(_fixed_t, bot_slot, ability_name, template_name, result, rule, source, context)
				_event_decisions[#_event_decisions + 1] = {
					bot = bot_slot,
					ability = ability_name,
					template = template_name,
					result = result,
					rule = rule,
					source = source,
					context = context,
				}
			end,
		},
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
		is_combat_ability_active = function()
			return _combat_ability_active
		end,
		is_grenade_enabled = function()
			return _grenades_enabled_result
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

	it("does nothing when grenade gating is disabled", function()
		_grenades_enabled_result = false
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("does nothing when heuristic blocks", function()
		_heuristic_result = false
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
	end)

	it("emits grenade decision events when heuristic blocks", function()
		_heuristic_result = false
		_heuristic_rule = "grenade_smoke_hold"
		_debug_enabled_result = true

		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_event_decisions)
		assert.equals("slot1", _event_decisions[1].bot)
		assert.equals("veteran_frag_grenade", _event_decisions[1].ability)
		assert.equals("veteran_frag_grenade", _event_decisions[1].template)
		assert.is_false(_event_decisions[1].result)
		assert.equals("grenade", _event_decisions[1].source)
		assert.equals("grenade_smoke_hold", _event_decisions[1].rule)
		assert.truthy(find_debug_log("grenade held veteran_frag_grenade"))
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

	it("emits grenade decision events when heuristic passes", function()
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_event_decisions)
		assert.equals("slot1", _event_decisions[1].bot)
		assert.is_true(_event_decisions[1].result)
		assert.equals("grenade_generic", _event_decisions[1].rule)
		assert.equals("grenade", _event_decisions[1].source)
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

	it("defers to combat ability when weapon lock is active", function()
		_combat_ability_active = true
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
				return mock_ability_extension, { name = "unknown_psyker_blitz" }
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

		it("ability-based blitz queues inputs on grenade_ability_action without wield", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "adamant_whistle" }
				end,
			})

			-- Idle → queues aim_pressed on grenade_ability_action, goes to wait_throw (no wield)
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)
			assert.equals(1, #_recorded_inputs)
			assert.equals("aim_pressed", _recorded_inputs[1].input)
			assert.equals("grenade_ability_action", _recorded_inputs[1].component)

			-- wait_throw → queues aim_released on grenade_ability_action
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("aim_released", _recorded_inputs[1].input)
			assert.equals("grenade_ability_action", _recorded_inputs[1].component)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("logs grenade ability component state when whistle activates", function()
			_debug_enabled_result = true
			_component_state_by_name.grenade_ability_action = {
				template_name = "adamant_whistle",
				current_action_name = "none",
			}

			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "adamant_whistle" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)

			local log_entry = find_debug_log("ability blitz activated adamant_whistle")
			assert.truthy(log_entry)
			assert.truthy(string.find(log_entry.message, "template=adamant_whistle", 1, true))
			assert.truthy(string.find(log_entry.message, "action=none", 1, true))
		end)

		it("logs grenade ability component state when whistle times out", function()
			_debug_enabled_result = true
			_component_state_by_name.grenade_ability_action = {
				template_name = "adamant_whistle",
				current_action_name = "none",
			}

			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "adamant_whistle" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)

			_component_state_by_name.grenade_ability_action.current_action_name = "action_aim"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			_mock_time = _mock_time + 5.0
			GrenadeFallback.try_queue(unit, blackboard)

			local log_entry = find_debug_log("ability blitz complete (timeout")
			assert.truthy(log_entry)
			assert.truthy(string.find(log_entry.message, "template=adamant_whistle", 1, true))
			assert.truthy(string.find(log_entry.message, "action=action_aim", 1, true))
		end)

		it("skips aim/throw stages for auto-fire templates", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "zealot_throwing_knives" }
				end,
			})

			-- Idle → wield
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			-- Wield confirmed → straight to wait_unwield (no wait_aim/wait_throw)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			_recorded_inputs = {}
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
			assert.equals(0, #_recorded_inputs) -- no aim/throw inputs queued
		end)

		it("completes auto-fire item templates on charge confirm without stable grenade slot", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "zealot_throwing_knives" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			_mock_time = _mock_time + 0.2
			GrenadeFallback.record_charge_event(unit, "zealot_throwing_knives", _mock_time)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.05
			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals(0, #_recorded_inputs)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.truthy(_grenade_state_by_unit[unit].next_try_t)
		end)

		it("skips wait_throw when release_input is nil", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "broker_missile_launcher" }
				end,
			})

			-- Idle → wield
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			-- Wield confirmed → wait_aim
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

			-- wait_aim → queues shoot_charge, skips to wait_unwield
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot_charge", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("supports Assail as a single-shot wielded blitz", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_anti_elite"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("supports Chain Lightning light-cast channel", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 5 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot_light_pressed", _recorded_inputs[1].input)
			assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot_light_hold_release", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("supports Smite sticky-charge startup", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 1 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_smite_priority"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_smite" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wield", _grenade_state_by_unit[unit].stage)

			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("charge_power_sticky", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("ability-based blitz completes on charge confirm without unwield", function()
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_generic"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "adamant_whistle" }
				end,
			})

			-- Idle → aim_pressed → wait_throw
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

			-- wait_throw → aim_released → wait_unwield
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			-- Simulate charge consumed
			local release_t = _mock_time
			_mock_time = _mock_time + 0.1
			GrenadeFallback.record_charge_event(unit, "adamant_whistle", _mock_time)

			-- Next tick: should complete without queueing unwield_to_previous
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.05
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(0, #_recorded_inputs) -- no unwield queued
			assert.is_nil(_grenade_state_by_unit[unit].stage) -- state reset
		end)
	end)
end)
