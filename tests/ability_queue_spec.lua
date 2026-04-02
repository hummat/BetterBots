local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local AbilityQueue = dofile("scripts/mods/BetterBots/ability_queue.lua")
AbilityQueue.init({ shared_rules = SharedRules })

describe("ability_queue", function()
	describe("_action_input_is_bot_queueable", function()
		it("accepts parser-level stance inputs even when action validation rejects them", function()
			local action_input_extension = {
				_action_input_parsers = {
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
			}
			local ability_extension = {
				action_input_is_currently_valid = function()
					return false
				end,
			}

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
			local action_input_extension = {
				_action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							zealot_dash = {},
						},
					},
				},
			}
			local ability_extension = {
				action_input_is_currently_valid = function(_, component_name, action_input, used_input, fixed_t)
					return component_name == "combat_ability_action"
						and action_input == "aim_pressed"
						and used_input == nil
						and fixed_t == 0
				end,
			}

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
			local action_input_extension = {
				_action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {},
						},
					},
				},
			}
			local ability_extension = {
				action_input_is_currently_valid = function()
					return false
				end,
			}

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
end)
