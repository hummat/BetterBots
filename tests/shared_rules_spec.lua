local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")

describe("shared_rules", function()
	it("allows parser-backed action inputs immediately", function()
		local ok = SharedRules.action_input_is_bot_queueable({
			_action_input_parsers = {
				combat_ability_action = {
					_ACTION_INPUT_SEQUENCE_CONFIGS = {
						zealot_relic = {
							channel = {},
						},
					},
				},
			},
		}, {
			action_input_is_currently_valid = function()
				return false
			end,
		}, "combat_ability_action", "zealot_relic", "channel", nil, 0)

		assert.is_true(ok)
	end)

	it("falls back to action_input_is_currently_valid when parser has no sequence", function()
		local ok = SharedRules.action_input_is_bot_queueable({}, {
			action_input_is_currently_valid = function(_, component_name, action_input)
				return component_name == "combat_ability_action" and action_input == "channel"
			end,
		}, "combat_ability_action", "zealot_relic", "channel", nil, 0)

		assert.is_true(ok)
	end)

	it("treats unknown daemonhost state as non-aggroed", function()
		local is_safe, aggro_state, stage = SharedRules.is_non_aggroed_daemonhost("daemonhost_1")

		assert.is_true(is_safe)
		assert.is_nil(aggro_state)
		assert.is_nil(stage)
	end)
end)
