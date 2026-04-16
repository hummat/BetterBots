local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local saved_blackboards = rawget(_G, "BLACKBOARDS")
local saved_managers = rawget(_G, "Managers")
local saved_game_session = rawget(_G, "GameSession")

describe("shared_rules", function()
	after_each(function()
		rawset(_G, "BLACKBOARDS", saved_blackboards)
		rawset(_G, "Managers", saved_managers)
		rawset(_G, "GameSession", saved_game_session)
	end)

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

	it("treats daemonhost stage 6 as aggroed even when perception is stale", function()
		rawset(_G, "BLACKBOARDS", {
			daemonhost_1 = {
				perception = {
					aggro_state = "alerted",
				},
			},
		})
		rawset(_G, "Managers", {
			state = {
				unit_spawner = {
					game_object_id = function(_, unit)
						assert.equals("daemonhost_1", unit)
						return 42
					end,
				},
				game_session = {
					game_session = function()
						return "session"
					end,
				},
			},
		})
		rawset(_G, "GameSession", {
			game_object_field = function(session, game_object_id, field_name)
				assert.equals("session", session)
				assert.equals(42, game_object_id)
				assert.equals("stage", field_name)
				return SharedRules.DAEMONHOST_STAGE_AGGROED
			end,
		})

		local is_safe, aggro_state, stage = SharedRules.is_non_aggroed_daemonhost("daemonhost_1")

		assert.is_false(is_safe)
		assert.equals("alerted", aggro_state)
		assert.equals(SharedRules.DAEMONHOST_STAGE_AGGROED, stage)
	end)
end)
