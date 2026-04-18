-- grenade_fallback_spec.lua — tests for grenade throw state machine (#4)

local test_helper = require("tests.test_helper")

-- Controllable mock time
local _mock_time = 0
local _original_require = require

-- Mock extensions per unit
local _extensions = {}

-- Recorded action_input calls
local _recorded_inputs = {}
local _debug_logs = {}
local _event_decisions = {}
local _event_emissions = {}
local _aim_calls = {}
local _grenade_state_by_unit = {}
local _last_grenade_charge_event_by_unit = {}
local _perf_calls = {}
local unit
local _saved_globals = {}

-- Mock ability_extension
local _can_use_grenade = true

local mock_ability_extension = test_helper.make_player_ability_extension({
	can_use_ability = function(_self, ability_name)
		if ability_name == "grenade_ability" then
			return _can_use_grenade
		end
		return false
	end,
})

-- Mock action_input_extension
local mock_action_input_extension = test_helper.make_player_action_input_extension({
	bot_queue_action_input = function(_self, component, input_name, extra)
		_recorded_inputs[#_recorded_inputs + 1] = {
			component = component,
			input = input_name,
			extra = extra,
			stage_at_queue = _grenade_state_by_unit[unit] and _grenade_state_by_unit[unit].stage or nil,
		}
	end,
})

local mock_bot_unit_input = test_helper.make_bot_unit_input({
	set_aiming = function(_self, aiming, soft, use_rotation)
		_aim_calls[#_aim_calls + 1] = {
			method = "set_aiming",
			aiming = aiming,
			soft = soft,
			use_rotation = use_rotation,
		}
	end,
	set_aim_rotation = function(_self, rotation)
		_aim_calls[#_aim_calls + 1] = {
			method = "set_aim_rotation",
			rotation = rotation,
		}
	end,
	set_aim_position = function(_self, position)
		_aim_calls[#_aim_calls + 1] = {
			method = "set_aim_position",
			position = position,
		}
	end,
})

local mock_input_extension = test_helper.make_player_input_extension({
	bot_unit_input = mock_bot_unit_input,
})

-- Mock unit_data component state
local _wielded_slot = "slot_secondary"
local _component_state_by_name = {}

-- Mock ScriptUnit
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
local _query_weapon_switch_lock = function()
	return false
end

-- Load the module
local GrenadeFallback = dofile("scripts/mods/BetterBots/grenade_fallback.lua")

setup(function()
	_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")

	rawset(_G, "ScriptUnit", {
		has_extension = function(u, system_name)
			local exts = _extensions[u]
			return exts and exts[system_name] or nil
		end,
	})
end)

teardown(function()
	rawset(_G, "ScriptUnit", _saved_globals.ScriptUnit)
end)

unit = "bot_unit_1"
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
	_G.require = _original_require
	_can_use_grenade = true
	_wielded_slot = "slot_secondary"
	_heuristic_result = true
	_heuristic_rule = "grenade_generic"
	_is_suppressed_result = false
	_is_suppressed_reason = nil
	_combat_ability_active = false
	_debug_enabled_result = false
	_grenades_enabled_result = true
	_query_weapon_switch_lock = function()
		return false
	end
	_recorded_inputs = {}
	_debug_logs = {}
	_event_decisions = {}
	_event_emissions = {}
	_aim_calls = {}
	_grenade_state_by_unit = {}
	_last_grenade_charge_event_by_unit = {}
	_perf_calls = {}
	_component_state_by_name = {}
	_component_state_by_name.weapon_action = {
		template_name = "autogun_p1_m1",
		current_action_name = "none",
	}
	blackboard = {}

	_extensions[unit] = {
		ability_system = mock_ability_extension,
		action_input_system = mock_action_input_extension,
		input_system = mock_input_extension,
		unit_data_system = test_helper.make_player_unit_data_extension({
			inventory = { wielded_slot = _wielded_slot },
			weapon_action = _component_state_by_name.weapon_action,
		}, {
			read_component = function(_self, component_name)
				if component_name == "inventory" then
					return { wielded_slot = _wielded_slot }
				end
				return _component_state_by_name[component_name]
			end,
		}),
	}

	_G.POSITION_LOOKUP = {
		[unit] = { x = 0, y = 0, z = 0 },
		enemy_1 = { x = 10, y = 0, z = 0 },
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
			next_attempt_id = function()
				return 7
			end,
			emit = function(event)
				_event_emissions[#_event_emissions + 1] = event
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
		perf = {
			begin = function()
				return {}
			end,
			finish = function(tag, _start_clock, _elapsed_s, opts)
				_perf_calls[#_perf_calls + 1] = {
					tag = tag,
					include_total = not (opts and opts.include_total == false),
				}
			end,
		},
	})

	GrenadeFallback.wire({
		build_context = function()
			return { num_nearby = 3, target_enemy = "enemy_1" }
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
		query_weapon_switch_lock = function(unit_arg)
			return _query_weapon_switch_lock(unit_arg)
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

local function perf_tags()
	local tags = {}
	for i = 1, #_perf_calls do
		local call = _perf_calls[i]
		tags[#tags + 1] = call.tag .. ":" .. tostring(call.include_total)
	end
	return tags
end

describe("grenade_fallback", function()
	it("test helper exposes engine-accurate player/minion extension builders", function()
		local player_ext = test_helper.make_player_unit_data_extension({
			locomotion = { velocity_current = { x = 1, y = 2, z = 3 } },
		})
		local minion_ext = test_helper.make_minion_unit_data_extension({
			name = "chaos_poxwalker",
			tags = {},
		})
		local minion_locomotion = test_helper.make_minion_locomotion_extension({ x = 4, y = 5, z = 6 })

		assert.is_function(player_ext.read_component)
		assert.is_nil(player_ext.breed)
		assert.is_function(minion_ext.breed)
		assert.is_nil(minion_ext.read_component)
		assert.is_function(minion_locomotion.current_velocity)
	end)

	before_each(function()
		reset()
	end)

	describe("perf breakdowns", function()
		it("records idle-path profile resolution and launch buckets", function()
			GrenadeFallback.try_queue(unit, blackboard)

			assert.same({
				"grenade_fallback.build_context:false",
				"grenade_fallback.heuristic:false",
				"grenade_fallback.profile_resolution:false",
				"grenade_fallback.launch:false",
			}, perf_tags())
		end)

		it("records a stage-machine bucket while advancing an active sequence", function()
			GrenadeFallback.try_queue(unit, blackboard)
			_perf_calls = {}

			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			assert.same({
				"grenade_fallback.stage_machine:false",
			}, perf_tags())
		end)
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

		it("does not block wield cleanup for chain lightning in wait_unwield", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 4, peril_pct = 0.2 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
			assert.is_false(GrenadeFallback.should_block_wield_input(unit))
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

	describe("should_block_weapon_action_input", function()
		it("does not block outside an active grenade sequence", function()
			assert.is_false(GrenadeFallback.should_block_weapon_action_input(unit, "charge_release"))
		end)

		it("allows the initial grenade wield input during item-based grenade wield stage", function()
			advance_to_stage("wield")

			assert.is_false(GrenadeFallback.should_block_weapon_action_input(unit, "grenade_ability"))
			assert.is_true(GrenadeFallback.should_block_weapon_action_input(unit, "zoom"))
		end)

		it("blocks foreign weapon actions during Assail cleanup", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, ranged_count = 2, target_enemy_distance = 10 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			assert.is_true(GrenadeFallback.should_block_weapon_action_input(unit, "charge_release"))
			assert.is_false(GrenadeFallback.should_block_weapon_action_input(unit, "wield"))
		end)

		it("aborts instead of throwing blind when bot aim cannot be established", function()
			_debug_enabled_result = true
			_extensions[unit].input_system = nil

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.is_truthy(find_debug_log("grenade aim unavailable"))
			assert.equals(1, #_recorded_inputs)
			assert.equals("grenade_ability", _recorded_inputs[1].input)
		end)

		it("never enters state machine when no target_enemy is available", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					-- ranged_count triggers the heuristic, but no target_enemy
					return { num_nearby = 3, ranged_count = 2, target_enemy_distance = 12 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)

			-- Should never have entered the state machine — no wield queued
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.equals(0, #_recorded_inputs)
		end)

		it("normalizes priority-only targets before evaluating and selecting Assail profile", function()
			local seen_context
			local BotTargeting = dofile("scripts/mods/BetterBots/bot_targeting.lua")
			local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
			local Heuristics = test_helper.load_split_heuristics({
				combat_ability_identity = CombatAbilityIdentity,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = "super_armor",
			})
			_extensions.enemy_1 = {
				unit_data_system = test_helper.make_minion_unit_data_extension({
					name = "chaos_traitor_gunner",
					tags = { special = true },
					ranged = true,
					game_object_type = "minion_ranged",
				}),
			}

			GrenadeFallback.wire({
				build_context = function()
					return {
						num_nearby = 1,
						target_enemy = nil,
						target_enemy_distance = nil,
						priority_target_enemy = "enemy_1",
					}
				end,
				evaluate_grenade_heuristic = function(_, context)
					seen_context = context
					return true, "grenade_assail_priority_target"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
				bot_targeting = BotTargeting,
				normalize_grenade_context = Heuristics.normalize_grenade_context,
			})

			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals("enemy_1", seen_context.target_enemy)
			assert.equals(10, seen_context.target_enemy_distance)
			assert.equals("ranged", seen_context.target_enemy_type)
			assert.is_true(seen_context.target_is_elite_special)
			assert.equals(1, #_recorded_inputs)
			assert.equals("weapon_action", _recorded_inputs[1].component)
			assert.equals("grenade_ability", _recorded_inputs[1].input)
			assert.equals("zoom", _grenade_state_by_unit[unit].aim_input)
		end)

		it("allows the expected Smite followup input", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 1, peril_pct = 0.1 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_smite_priority_target"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_smite" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			assert.is_false(GrenadeFallback.should_block_weapon_action_input(unit, "use_power"))
			assert.is_true(GrenadeFallback.should_block_weapon_action_input(unit, "charge_release"))
		end)

		it("aborts when grenade slot is lost during wait_followup", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 1, peril_pct = 0.1 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_smite_priority_target"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_smite" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			_wielded_slot = "slot_secondary"
			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.truthy(find_debug_log("grenade lost wield during followup"))
		end)

		it("allows the expected Chain Lightning release input", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 5 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

			assert.is_false(GrenadeFallback.should_block_weapon_action_input(unit, "shoot_heavy_hold_release"))
			assert.is_true(GrenadeFallback.should_block_weapon_action_input(unit, "charge_release"))
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

	it("logs the interaction guard on idle-path deferrals", function()
		_debug_enabled_result = true
		blackboard.behavior = {
			current_interaction_unit = "med_station",
		}

		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(0, #_recorded_inputs)
		assert.is_truthy(find_debug_log("grenade blocked: interacting with med_station"))
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

	it("marks the grenade sequence active before queueing grenade_ability", function()
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("wield", _recorded_inputs[1].stage_at_queue)
	end)

	it("defers item grenade activation while the bot is unarmed", function()
		_wielded_slot = "slot_unarmed"
		_component_state_by_name.weapon_action.template_name = "unarmed"
		_debug_enabled_result = true

		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(0, #_recorded_inputs)
		assert.is_nil(_grenade_state_by_unit[unit].stage)
		assert.truthy(find_debug_log("grenade deferred while unarmed"))
	end)

	it("retries item grenade activation after leaving unarmed", function()
		_wielded_slot = "slot_unarmed"
		_component_state_by_name.weapon_action.template_name = "unarmed"

		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(0, #_recorded_inputs)
		assert.is_nil(_grenade_state_by_unit[unit].stage)

		_wielded_slot = "slot_secondary"
		_component_state_by_name.weapon_action.template_name = "autogun_p1_m1"
		_mock_time = _mock_time + 0.1
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals(1, #_recorded_inputs)
		assert.equals("weapon_action", _recorded_inputs[1].component)
		assert.equals("grenade_ability", _recorded_inputs[1].input)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)
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

	it("logs grenade release target context once per actual throw", function()
		_debug_enabled_result = true
		advance_to_stage("wait_throw")
		_recorded_inputs = {}

		_mock_time = _mock_time + 1.0
		GrenadeFallback.try_queue(unit, blackboard)

		assert.truthy(find_debug_log("grenade releasing toward enemy_1"))
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

	it("drives bot aim toward the current target while waiting to throw", function()
		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_true(_aim_calls[1].aiming)
		assert.is_false(_aim_calls[1].soft)
		assert.is_false(_aim_calls[1].use_rotation)
		assert.equals("set_aim_position", _aim_calls[2].method)
		assert.same(POSITION_LOOKUP.enemy_1, _aim_calls[2].position)
	end)

	it("uses aim rotation for supported ballistic projectiles", function()
		local mock_rotation = { yaw = 1, pitch = 2 }

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 30,
					gravity = 12.5,
				}
			end,
			solve_ballistic_rotation = function()
				return mock_rotation
			end,
		})

		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_true(_aim_calls[1].use_rotation)
		assert.equals("set_aim_rotation", _aim_calls[2].method)
		assert.same(mock_rotation, _aim_calls[2].rotation)
	end)

	it("resolves standard grenade ballistics from projectile templates", function()
		local mock_rotation = { yaw = 5, pitch = 6 }

		_G.require = function(path)
			if path == "scripts/settings/equipment/weapon_templates/weapon_templates" then
				return {}
			end

			if path == "scripts/settings/projectile/projectile_templates" then
				return {
					veteran_frag_grenade = {
						item_name = "content/items/weapons/player/grenade_frag",
						locomotion_template = {
							integrator_parameters = {
								gravity = 12.5,
							},
							trajectory_parameters = {
								throw = {
									speed_maximal = 30,
								},
							},
						},
					},
				}
			end

			return _original_require(path)
		end

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension,
					{
						name = "veteran_frag_grenade",
						inventory_item_name = "content/items/weapons/player/grenade_frag",
					}
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			solve_ballistic_rotation = function(_unit, _aim_unit, projectile_data)
				assert.equals("ballistic", projectile_data.mode)
				assert.equals(30, projectile_data.speed)
				assert.equals(12.5, projectile_data.gravity)
				return mock_rotation
			end,
		})

		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_true(_aim_calls[1].use_rotation)
		assert.equals("set_aim_rotation", _aim_calls[2].method)
		assert.same(mock_rotation, _aim_calls[2].rotation)
	end)

	it("uses ballistic aim for zealot throwing knives during auto-fire wield", function()
		local mock_rotation = { yaw = 3, pitch = 4 }

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 15 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_knives_pressure"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "zealot_throwing_knives" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 75,
					gravity = 17.5,
				}
			end,
			solve_ballistic_rotation = function()
				return mock_rotation
			end,
		})

		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_aim_calls = {}

		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_true(_aim_calls[1].use_rotation)
		assert.equals("set_aim_rotation", _aim_calls[2].method)
		assert.same(mock_rotation, _aim_calls[2].rotation)
	end)

	it("falls back to flat aim for excluded projectile families", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_missile_launcher"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "broker_missile_launcher" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "flat",
					reason = "excluded_family",
				}
			end,
		})

		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_false(_aim_calls[1].use_rotation)
		assert.equals("set_aim_position", _aim_calls[2].method)
		assert.same(POSITION_LOOKUP.enemy_1, _aim_calls[2].position)
	end)

	it("falls back to flat aim when ballistic solver fails", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 75,
					gravity = 17.5,
				}
			end,
			solve_ballistic_rotation = function()
				return nil, "trajectory_solver_failed"
			end,
		})

		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_false(_aim_calls[1].use_rotation)
		assert.equals("set_aim_position", _aim_calls[2].method)
		assert.same(POSITION_LOOKUP.enemy_1, _aim_calls[2].position)
	end)

	it("logs ballistic aim path when debug is enabled", function()
		_debug_enabled_result = true

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 30,
					gravity = 12.5,
				}
			end,
			solve_ballistic_rotation = function()
				return { yaw = 1, pitch = 2 }
			end,
		})

		advance_to_stage("wait_aim")
		_debug_logs = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.truthy(find_debug_log("grenade aim ballistic"))
	end)

	it("does not crash when target has minion-style unit_data (no read_component)", function()
		-- MinionUnitDataExtension has breed() but no read_component.
		-- _target_velocity must guard read_component before calling it.
		-- Regression: without the guard this crashes with
		-- "attempt to call method 'read_component' (a nil value)".
		_extensions.enemy_1 = {
			unit_data_system = test_helper.make_minion_unit_data_extension({ name = "chaos_poxwalker" }),
		}

		-- Mock engine math globals so the default solver can run end-to-end.
		-- Real Vector3 is C userdata with operator overloads; we emulate with metatables.
		local saved_vector3 = _G.Vector3
		local saved_quaternion = _G.Quaternion
		local saved_require = require

		local vec_mt = {
			__sub = function(a, b)
				return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
			end,
		}
		local function vec(x, y, z)
			return setmetatable({ x = x, y = y, z = z }, vec_mt)
		end

		_G.POSITION_LOOKUP[unit] = vec(0, 0, 0)
		_G.POSITION_LOOKUP.enemy_1 = vec(10, 0, 0)

		_G.Vector3 = {
			zero = function()
				return vec(0, 0, 0)
			end,
			flat = function(v)
				return vec(v.x, 0, v.z)
			end,
			normalize = function(v)
				return v
			end,
			up = function()
				return vec(0, 1, 0)
			end,
			right = function()
				return vec(1, 0, 0)
			end,
			length_squared = function(_v)
				return 100
			end,
		}
		local mock_rotation = { yaw = 5, pitch = 6 }
		local mock_trajectory = {
			angle_to_hit_moving_target = function()
				return 0.5, vec(10, 0, 2)
			end,
		}
		rawset(_G, "require", function(path)
			if path == "scripts/utilities/trajectory" then
				return mock_trajectory
			end
			return saved_require(path)
		end)
		_G.Quaternion = setmetatable({
			look = function()
				return mock_rotation
			end,
			multiply = function()
				return mock_rotation
			end,
		}, {
			__call = function()
				return mock_rotation
			end,
		})

		-- Do NOT inject solve_ballistic_rotation — exercise the default solver
		-- which calls _target_velocity internally.
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 30,
					gravity = 12.5,
				}
			end,
		})

		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[1].method)
		assert.is_true(_aim_calls[1].use_rotation)
		assert.equals("set_aim_rotation", _aim_calls[2].method)

		_extensions.enemy_1 = nil
		_G.POSITION_LOOKUP[unit] = { x = 0, y = 0, z = 0 }
		_G.POSITION_LOOKUP.enemy_1 = { x = 10, y = 0, z = 0 }
		_G.Vector3 = saved_vector3
		_G.Quaternion = saved_quaternion
		rawset(_G, "require", saved_require)
	end)

	it("clears bot aim when the grenade state resets", function()
		advance_to_stage("wait_aim")
		_aim_calls = {}

		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_secondary"
		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)

		assert.equals("set_aiming", _aim_calls[#_aim_calls].method)
		assert.is_false(_aim_calls[#_aim_calls].aiming)
	end)

	it("abandons the throw if wait_aim revalidation fails", function()
		advance_to_stage("wait_aim")
		_recorded_inputs = {}
		_aim_calls = {}
		_heuristic_result = false
		_heuristic_rule = "grenade_hold"

		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)

		assert.is_nil(_grenade_state_by_unit[unit].stage)
		assert.equals(0, #_recorded_inputs)
		assert.equals("set_aiming", _aim_calls[#_aim_calls].method)
		assert.is_false(_aim_calls[#_aim_calls].aiming)
	end)

	it("aborts when target despawns mid-sequence (position disappears)", function()
		_debug_enabled_result = true
		advance_to_stage("wait_aim")
		_aim_calls = {}

		-- Target's position disappears (enemy died/despawned)
		_G.POSITION_LOOKUP = {}

		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)

		assert.is_nil(_grenade_state_by_unit[unit].stage)
		assert.truthy(find_debug_log("grenade aim unavailable"))
	end)

	it("retains stale aim target when context loses target_enemy", function()
		advance_to_stage("wait_aim")
		_aim_calls = {}

		-- Context stops providing target_enemy but POSITION_LOOKUP still valid
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
		})

		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)

		-- Sequence continues using sticky aim from original target
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)
		assert.equals("set_aim_position", _aim_calls[#_aim_calls].method)
		assert.same(POSITION_LOOKUP.enemy_1, _aim_calls[#_aim_calls].position)
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
		_debug_enabled_result = true
		-- Wire with a blitz template that uses a different input chain
		GrenadeFallback.wire({
			build_context = function()
				return { target_enemy = "enemy_1", num_nearby = 3 }
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
		assert.truthy(find_debug_log("unsupported grenade template unknown_psyker_blitz"))
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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
					return { target_enemy = "enemy_1", num_nearby = 3 }
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

		it("supports Assail as an aimed homing blitz", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, target_enemy_distance = 12, ranged_count = 2 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
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
			assert.equals("zoom", _recorded_inputs[1].input)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("zoom_shoot", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("supports Assail as a fast close-range blitz under crowd pressure", function()
			GrenadeFallback.wire({
				build_context = function()
					return {
						target_enemy = "enemy_1",
						num_nearby = 5,
						challenge_rating_sum = 2.5,
						target_enemy_distance = 4,
					}
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_crowd_soften"
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

		it("does not queue invalid unwield_to_previous cleanup for Assail", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, ranged_count = 2, target_enemy_distance = 10 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			GrenadeFallback.record_charge_event(unit, "psyker_throwing_knives", _mock_time + 0.1)
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals(0, #_recorded_inputs)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
		end)

		it("does not reset Assail state on action_rapid_zoomed confirmation alone", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, ranged_count = 2, target_enemy_distance = 10 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			-- Advance aimed Assail to wait_unwield: wield → wait_aim → zoom → zoom_shoot
			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			-- Simulate the engine entering action_rapid_zoomed (knife throw animation)
			-- but NO charge consumption yet
			_component_state_by_name.weapon_action = {
				current_action_name = "action_rapid_zoomed",
			}

			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			-- Bug: previously this would reset state, letting the BT switch to staff
			-- before the knife charge was consumed.
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("holds Assail wield lock until charge consumption even with action confirmation", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, ranged_count = 2, target_enemy_distance = 10 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			-- Advance aimed Assail to wait_unwield
			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			-- action_rapid_zoomed fires but no charge yet — lock must hold
			_component_state_by_name.weapon_action = {
				current_action_name = "action_rapid_zoomed",
			}
			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)
			assert.is_true(GrenadeFallback.should_block_wield_input(unit))
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			-- Now charge is consumed — state should reset
			GrenadeFallback.record_charge_event(unit, "psyker_throwing_knives", _mock_time + 0.15)
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
		end)

		it("releases Assail wield lock on timeout when charge event never arrives", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3, ranged_count = 2, target_enemy_distance = 10 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_assail_ranged_pressure"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			-- Advance aimed Assail to wait_unwield
			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.6
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			-- No charge event — wield lock must hold
			assert.is_true(GrenadeFallback.should_block_wield_input(unit))

			-- Advance past UNWIELD_TIMEOUT_S (3.0s) — timeout must release everything
			_mock_time = _mock_time + 3.1
			GrenadeFallback.try_queue(unit, blackboard)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.is_false(GrenadeFallback.should_block_wield_input(unit))
		end)

		it("supports Chain Lightning charged crowd-control sequence", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 5 }
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
			assert.equals("charge_heavy", _recorded_inputs[1].input)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot_heavy_hold", _recorded_inputs[1].input)
			assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shoot_heavy_hold_release", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("does not queue invalid unwield_to_previous cleanup for Chain Lightning", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 4, peril_pct = 0.2 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_recorded_inputs = {}
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			_recorded_inputs = {}
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 3.1
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(0, #_recorded_inputs)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
		end)

		it("completes Chain Lightning cleanup immediately on charged action confirmation", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 4, peril_pct = 0.2 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			_component_state_by_name.weapon_action = {
				current_action_name = "action_spread_charged",
			}

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals(0, #_recorded_inputs)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.truthy(find_debug_log("grenade external action confirmed for psyker_chain_lightning"))
			assert.truthy(find_debug_log("grenade released cleanup lock without explicit unwield (action confirmed)"))
		end)

		it("completes Chain Lightning cleanup when the engine unwields away from grenade slot", function()
			_debug_enabled_result = true
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 4, peril_pct = 0.2 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_chain_lightning_crowd"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_chain_lightning" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			_mock_time = _mock_time + 1.0
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

			_wielded_slot = "slot_secondary"
			_recorded_inputs = {}
			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			assert.equals(0, #_recorded_inputs)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.truthy(find_debug_log("grenade released cleanup lock without explicit unwield (slot changed)"))
		end)

		it("supports Smite sticky-charge startup", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 1 }
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
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)
		end)

		it("queues explicit Smite use_power after sticky charge", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 1, peril_pct = 0.1 }
				end,
				evaluate_grenade_heuristic = function()
					return true, "grenade_smite_priority_target"
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "psyker_smite" }
				end,
			})

			GrenadeFallback.try_queue(unit, blackboard)
			_wielded_slot = "slot_grenade_ability"

			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("charge_power_sticky", _recorded_inputs[1].input)
			assert.equals("wait_followup", _grenade_state_by_unit[unit].stage)

			_recorded_inputs = {}
			_mock_time = _mock_time + 2.1
			GrenadeFallback.try_queue(unit, blackboard)
			assert.equals(1, #_recorded_inputs)
			assert.equals("use_power", _recorded_inputs[1].input)
			assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		end)

		it("ability-based blitz completes on charge confirm without unwield", function()
			GrenadeFallback.wire({
				build_context = function()
					return { target_enemy = "enemy_1", num_nearby = 3 }
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

	describe("event log emissions (#59)", function()
		local function find_events(event_type)
			local found = {}
			for i = 1, #_event_emissions do
				if _event_emissions[i].event == event_type then
					found[#found + 1] = _event_emissions[i]
				end
			end
			return found
		end

		it("emits queued event with attempt_id and rule on item-based grenade start", function()
			_heuristic_result = true
			_heuristic_rule = "frag_horde"
			GrenadeFallback.try_queue(unit, blackboard)

			local queued = find_events("queued")
			assert.equals(1, #queued)
			assert.equals("veteran_frag_grenade", queued[1].ability)
			assert.equals("frag_horde", queued[1].rule)
			assert.equals("grenade", queued[1].source)
			assert.equals("slot1", queued[1].bot)
			assert.equals(7, queued[1].attempt_id)
			assert.equals("grenade_ability", queued[1].input)
			assert.equals("wield", queued[1].stage)
		end)

		it("emits grenade_stage events through standard throw lifecycle", function()
			_heuristic_result = true
			_heuristic_rule = "frag_horde"
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield succeeds
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Aim delay passes
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Throw delay passes
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			local stages = find_events("grenade_stage")
			assert.is_true(#stages >= 3) -- wait_aim, wait_throw (from aim), wait_unwield (from release)
		end)

		it("emits complete event when slot returns after throw", function()
			_heuristic_result = true
			_heuristic_rule = "frag_horde"
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Aim
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Throw
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			-- Slot returns
			_wielded_slot = "slot_secondary"
			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			local complete = find_events("complete")
			assert.equals(1, #complete)
			assert.equals("slot_returned", complete[1].reason)
			assert.equals("grenade", complete[1].source)
			assert.equals(7, complete[1].attempt_id)
		end)

		it("emits blocked event on wield timeout", function()
			_heuristic_result = true
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield never succeeds, time out
			_mock_time = _mock_time + 3.0
			GrenadeFallback.try_queue(unit, blackboard)

			local blocked = find_events("blocked")
			assert.equals(1, #blocked)
			assert.equals("wield_timeout", blocked[1].reason)
			assert.equals("wield", blocked[1].stage)
		end)

		it(
			"emits slot_locked before the initial grenade_ability queue when another ability already holds a different slot",
			function()
				_debug_enabled_result = true
				_heuristic_result = true
				_query_weapon_switch_lock = function()
					return true, "zealot_relic", "active", "slot_combat_ability"
				end

				GrenadeFallback.try_queue(unit, blackboard)

				local blocked = find_events("blocked")
				assert.equals(1, #blocked)
				assert.equals("slot_locked", blocked[1].reason)
				assert.equals("wield", blocked[1].stage)
				assert.equals("zealot_relic", blocked[1].blocked_by)
				assert.equals("slot_combat_ability", blocked[1].held_slot)
				assert.equals(10.35, _grenade_state_by_unit[unit].next_try_t)
				assert.is_nil(_grenade_state_by_unit[unit].stage)
				assert.equals(0, #_recorded_inputs)
				assert.is_not_nil(find_debug_log("grenade blocked during wield by zealot_relic active"))
			end
		)

		it("emits slot_locked instead of wield_timeout when another ability holds a different slot", function()
			_debug_enabled_result = true
			_heuristic_result = true
			GrenadeFallback.try_queue(unit, blackboard)

			_query_weapon_switch_lock = function()
				return true, "zealot_relic", "active", "slot_combat_ability"
			end

			_mock_time = _mock_time + 0.1
			GrenadeFallback.try_queue(unit, blackboard)

			local blocked = find_events("blocked")
			assert.equals(1, #blocked)
			assert.equals("slot_locked", blocked[1].reason)
			assert.equals("wield", blocked[1].stage)
			assert.equals("zealot_relic", blocked[1].blocked_by)
			assert.equals("slot_combat_ability", blocked[1].held_slot)
			assert.equals(10.45, _grenade_state_by_unit[unit].next_try_t)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.is_not_nil(find_debug_log("grenade blocked during wield by zealot_relic active"))
		end)

		it("emits blocked event on lost wield during aim", function()
			_heuristic_result = true
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield succeeds
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield lost during aim
			_wielded_slot = "slot_secondary"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			local blocked = find_events("blocked")
			assert.equals(1, #blocked)
			assert.equals("lost_wield", blocked[1].reason)
			assert.equals("wait_aim", blocked[1].stage)
		end)

		it("emits blocked event and resets immediately when action_input_system disappears mid-sequence", function()
			_debug_enabled_result = true
			_heuristic_result = true
			GrenadeFallback.try_queue(unit, blackboard)

			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			_extensions[unit].action_input_system = nil
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			local blocked = find_events("blocked")
			assert.equals(1, #blocked)
			assert.equals("action_input_missing", blocked[1].reason)
			assert.equals("wait_aim", blocked[1].stage)
			assert.equals("aim_hold", blocked[1].input)
			assert.is_nil(_grenade_state_by_unit[unit].stage)
			assert.is_truthy(find_debug_log("missing action_input_system for aim_hold"))
		end)

		it("emits blocked event on revalidation failure", function()
			_heuristic_result = true
			_heuristic_rule = "frag_horde"
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield succeeds
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Heuristic changes mind before aim fires
			_heuristic_result = false
			_heuristic_rule = "frag_horde_too_few"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			local blocked = find_events("blocked")
			assert.equals(1, #blocked)
			assert.equals("revalidation", blocked[1].reason)
			assert.equals("frag_horde_too_few", blocked[1].rule)
		end)

		it("emits complete event for auto-fire template (zealot knives)", function()
			-- Override to zealot_throwing_knives
			GrenadeFallback.wire({
				build_context = function()
					return { num_nearby = 3, target_enemy = "enemy_1" }
				end,
				evaluate_grenade_heuristic = function()
					return _heuristic_result, _heuristic_rule
				end,
				equipped_grenade_ability = function()
					return mock_ability_extension, { name = "zealot_throwing_knives" }
				end,
				is_combat_ability_active = function()
					return false
				end,
				is_grenade_enabled = function()
					return true
				end,
			})

			_heuristic_result = true
			GrenadeFallback.try_queue(unit, blackboard)

			-- Wield triggers auto-fire → wait_unwield
			_wielded_slot = "slot_grenade_ability"
			_mock_time = _mock_time + 0.2
			GrenadeFallback.try_queue(unit, blackboard)

			-- Slot returns
			_wielded_slot = "slot_secondary"
			_mock_time = _mock_time + 0.5
			GrenadeFallback.try_queue(unit, blackboard)

			local queued = find_events("queued")
			assert.equals(1, #queued)
			local complete = find_events("complete")
			assert.equals(1, #complete)
			assert.equals("slot_returned", complete[1].reason)
		end)
	end)
end)
