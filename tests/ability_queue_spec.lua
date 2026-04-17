local test_helper = require("tests.test_helper")

local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local AbilityQueue = dofile("scripts/mods/BetterBots/ability_queue.lua")
AbilityQueue.init({ shared_rules = SharedRules })

describe("ability_queue", function()
	local saved_script_unit = _G.ScriptUnit
	local saved_require = require
	local function make_perf_stub()
		local calls = {}
		return {
			calls = calls,
			begin = function()
				return {}
			end,
			finish = function(tag, _start_clock, _elapsed_s, opts)
				calls[#calls + 1] = {
					tag = tag,
					include_total = not (opts and opts.include_total == false),
				}
			end,
		}
	end

	after_each(function()
		_G.ScriptUnit = saved_script_unit
		rawset(_G, "require", saved_require)
	end)

	describe("_action_input_is_bot_queueable", function()
		it("accepts parser-level stance inputs even when action validation rejects them", function()
			local action_input_extension = test_helper.make_player_action_input_extension({
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							veteran_combat_ability = {
								stance_pressed = {
									buffer_time = 0.5,
								},
							},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				action_input_is_currently_valid = function()
					return false
				end,
			})

			assert.is_true(
				AbilityQueue._action_input_is_bot_queueable(
					action_input_extension,
					ability_extension,
					"combat_ability_action",
					"veteran_combat_ability",
					"stance_pressed",
					nil,
					0
				)
			)
		end)

		it("falls back to action validation for direct action inputs", function()
			local action_input_extension = test_helper.make_player_action_input_extension({
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							zealot_dash = {},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				action_input_is_currently_valid = function(_, component_name, action_input, used_input, fixed_t)
					return component_name == "combat_ability_action"
						and action_input == "aim_pressed"
						and used_input == nil
						and fixed_t == 0
				end,
			})

			assert.is_true(
				AbilityQueue._action_input_is_bot_queueable(
					action_input_extension,
					ability_extension,
					"combat_ability_action",
					"zealot_dash",
					"aim_pressed",
					nil,
					0
				)
			)
		end)

		it("rejects inputs that are unknown to both parser and action validation", function()
			local action_input_extension = test_helper.make_player_action_input_extension({
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				action_input_is_currently_valid = function()
					return false
				end,
			})

			assert.is_false(
				AbilityQueue._action_input_is_bot_queueable(
					action_input_extension,
					ability_extension,
					"combat_ability_action",
					"psyker_shout",
					"missing_input",
					nil,
					0
				)
			)
		end)
	end)

	describe("template fallback fast paths", function()
		it("skips heuristic dispatch while combat ability is not usable", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local decision_calls = 0
			local queued_inputs = 0
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function(_, ability_type)
					return ability_type ~= "combat_ability"
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function()
					queued_inputs = queued_inputs + 1
				end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
				extension = function(_, system_name)
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			local state_by_unit = {}
			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 10
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = state_by_unit,
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						decision_calls = decision_calls + 1
						return true, "test_rule", { num_nearby = 3 }
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})

			assert.equals(0, decision_calls)
			assert.equals(0, queued_inputs)
		end)

		it("suppresses fallback queueing when team cooldown blocks the semantic ability family", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local queued_inputs = 0
			local recorded_team_key
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
				_equipped_abilities = {
					combat_ability = {
						name = "veteran_combat_ability_shout",
						ability_template_tweak_data = { class_tag = "squad_leader" },
					},
				},
			})
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function()
					queued_inputs = queued_inputs + 1
				end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							veteran_combat_ability = {
								combat_ability_pressed = {},
							},
						},
					},
				},
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "veteran_combat_ability" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
				extension = function(_, system_name)
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						veteran_combat_ability = {
							ability_meta_data = {
								activation = { action_input = "combat_ability_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 10
				end,
				equipped_combat_ability = function()
					return ability_extension, ability_extension._equipped_abilities.combat_ability
				end,
				equipped_combat_ability_name = function()
					return "veteran_combat_ability_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = {},
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "veteran_voc_surrounded", { num_nearby = 3 }
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function(_unit, team_key)
						recorded_team_key = team_key
						return true, "team_cd:aoe_shout"
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return { semantic_key = "veteran_combat_ability_shout" }
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return true
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", { perception = {} })

			assert.equals("veteran_combat_ability_shout", recorded_team_key)
			assert.equals(0, queued_inputs)
		end)

		it("records breakdown buckets for the template fallback path", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local perf = make_perf_stub()
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function() end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
				extension = function(_, system_name)
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 10
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = {},
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
				perf = perf,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "test_rule", { num_nearby = 2 }
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return false
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return nil
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return true
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})

			assert.same({
				ability_queue_template_setup = true,
				ability_queue_input_validation = true,
				ability_queue_decision = true,
				ability_queue_queue = true,
			}, {
				ability_queue_template_setup = perf.calls[1]
						and perf.calls[1].tag == "ability_queue.template_setup"
						and perf.calls[1].include_total == false
					or false,
				ability_queue_input_validation = perf.calls[2]
						and perf.calls[2].tag == "ability_queue.input_validation"
						and perf.calls[2].include_total == false
					or false,
				ability_queue_decision = perf.calls[3]
						and perf.calls[3].tag == "ability_queue.decision"
						and perf.calls[3].include_total == false
					or false,
				ability_queue_queue = perf.calls[4]
						and perf.calls[4].tag == "ability_queue.queue"
						and perf.calls[4].include_total == false
					or false,
			})
		end)

		it("records a separate breakdown bucket for delegated item fallback", function()
			saved_script_unit = _G.ScriptUnit

			local perf = make_perf_stub()
			local delegated = 0
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "none" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					return nil
				end,
			}

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 10
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "zealot_relic" }
				end,
				equipped_combat_ability_name = function()
					return "zealot_relic"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = {},
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
				perf = perf,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						error("should not reach heuristics")
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function()
						delegated = delegated + 1
					end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
			})

			AbilityQueue.try_queue("bot_unit", {})

			assert.equals(1, delegated)
			assert.same({
				tag = "ability_queue.item_fallback",
				include_total = false,
			}, perf.calls[1])
		end)

		it("injects ability templates once across repeated fallback ticks", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local decision_calls = 0
			local inject_calls = 0
			local require_calls = 0
			local fixed_t = 10
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function() end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
				extension = function(_, system_name)
					if system_name == "action_input_system" then
						return action_input_extension
					end
					return nil
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					require_calls = require_calls + 1
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return fixed_t
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = {},
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						decision_calls = decision_calls + 1
						return false, "test_rule", { num_nearby = 0 }
					end,
				},
				MetaData = {
					inject = function()
						inject_calls = inject_calls + 1
					end,
				},
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return false
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return nil
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return true
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})
			fixed_t = 11
			AbilityQueue.try_queue("bot_unit", {})

			assert.equals(2, decision_calls)
			assert.equals(1, inject_calls)
			assert.equals(1, require_calls)
		end)
	end)

	describe("combat ability jitter", function()
		it("schedules delayed queueing for non-emergency rules", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local queued_inputs = 0
			local fixed_t = 10
			local state_by_unit = {}
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function()
					queued_inputs = queued_inputs + 1
				end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
				extension = function(_, system_name)
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return fixed_t
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = state_by_unit,
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "psyker_shout_mixed_pack", {}
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return false
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return nil
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return false
					end,
					random_ability_jitter_delay = function()
						return 1.0
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(0, queued_inputs)
			assert.equals(11, state_by_unit.bot_unit.pending_ready_t)

			fixed_t = 11
			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(1, queued_inputs)
		end)

		it("clears pending jitter when heuristics reject on next tick", function()
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local queued_inputs = 0
			local fixed_t = 10
			local state_by_unit = {}
			local heuristics_approve = true
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function()
					queued_inputs = queued_inputs + 1
				end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
				extension = function(_, system_name)
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return fixed_t
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = state_by_unit,
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						if heuristics_approve then
							return true, "psyker_shout_mixed_pack", {}
						else
							return false, nil, { num_nearby = 0 }
						end
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return false
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return nil
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return false
					end,
					random_ability_jitter_delay = function()
						return 1.0
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			-- First tick: heuristics approve → jitter scheduled
			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(0, queued_inputs)
			local first_pending_ready_t = state_by_unit.bot_unit.pending_ready_t
			assert.is_not_nil(first_pending_ready_t)

			-- Switch heuristics to reject
			heuristics_approve = false

			-- Advance past jitter delay
			fixed_t = 12

			-- Second tick: heuristics reject → should NOT queue AND should clear pending state
			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(0, queued_inputs)
			assert.is_nil(state_by_unit.bot_unit.pending_ready_t)

			-- Switch heuristics back to approve
			heuristics_approve = true

			-- Third tick: should schedule NEW jitter (old pending was cleared)
			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(0, queued_inputs)
			local new_pending_ready_t = state_by_unit.bot_unit.pending_ready_t
			assert.is_not_nil(new_pending_ready_t)
			assert.are_not.equals(first_pending_ready_t, new_pending_ready_t)
		end)
	end)

	describe("human-likeness jitter buckets", function()
		local function run_pending_jitter_rule(rule, delay)
			saved_script_unit = _G.ScriptUnit
			saved_require = require

			local fixed_t = 10
			local state_by_unit = {}
			local action_input_extension = test_helper.make_player_action_input_extension({
				bot_queue_action_input = function() end,
				action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			})
			local ability_extension = test_helper.make_player_ability_extension({
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			})
			local unit_data_extension = test_helper.make_player_unit_data_extension({
				combat_ability_action = { template_name = "psyker_shout" },
			})

			_G.ScriptUnit = {
				has_extension = function(_, system_name)
					if system_name == "unit_data_system" then
						return unit_data_extension
					end
					if system_name == "ability_system" then
						return ability_extension
					end
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
				extension = function(_, system_name)
					if system_name == "action_input_system" then
						return action_input_extension
					end
				end,
			}
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
					return {}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return fixed_t
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = state_by_unit,
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						return true, rule, {}
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
					emit_decision = function() end,
				},
				EngagementLeash = {
					is_movement_ability = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return false
					end,
				},
				CombatAbilityIdentity = {
					resolve = function()
						return nil
					end,
				},
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return false
					end,
					random_ability_jitter_delay = function(asked_rule)
						assert.equals(rule, asked_rule)
						return delay
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})
			return state_by_unit.bot_unit.pending_ready_t
		end

		it("uses defensive jitter for defensive rules", function()
			assert.equals(10.2, run_pending_jitter_rule("veteran_voc_critical_toughness", 0.2))
		end)

		it("uses opportunistic jitter for opportunistic rules", function()
			assert.equals(10.8, run_pending_jitter_rule("ogryn_charge_priority_target", 0.8))
		end)
	end)
end)
