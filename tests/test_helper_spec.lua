local test_helper = require("tests.test_helper")

describe("test_helper audited builders", function()
	local function assert_rejects_unknown_override(make_builder)
		local ok, err = pcall(make_builder)

		assert.is_false(ok)
		assert.matches("unknown audited override key", tostring(err), 1, true)
	end

	it("rejects unknown overrides on audited extension builders", function()
		local cases = {
			function()
				test_helper.make_player_unit_data_extension(nil, { invented_api = function() end })
			end,
			function()
				test_helper.make_minion_unit_data_extension(nil, { invented_api = function() end })
			end,
			function()
				test_helper.make_player_ability_extension({
					overrides = { invented_api = function() end },
				})
			end,
			function()
				test_helper.make_player_action_input_extension({
					overrides = { invented_api = function() end },
				})
			end,
			function()
				test_helper.make_bot_perception_extension({
					overrides = { invented_api = function() end },
				})
			end,
			function()
				test_helper.make_minion_perception_extension({
					overrides = { invented_api = function() end },
				})
			end,
			function()
				test_helper.make_smart_tag_extension(nil, { invented_api = function() end })
			end,
			function()
				test_helper.make_coherency_extension(1, { invented_api = function() end })
			end,
			function()
				test_helper.make_player_talent_extension({
					overrides = { invented_api = function() end },
				})
			end,
			function()
				test_helper.make_companion_spawner_extension({
					overrides = { invented_api = function() end },
				})
			end,
		}

		for i = 1, #cases do
			assert_rejects_unknown_override(cases[i])
		end
	end)

	it("allows current audited player unit data methods from decompiled source", function()
		local breed = { name = "chaos_traitor_gunner" }
		local extension = test_helper.make_player_unit_data_extension(nil, {
			breed = function()
				return breed
			end,
			breed_name = function()
				return breed.name
			end,
			is_companion = function()
				return false
			end,
		})

		assert.same(breed, extension:breed())
		assert.equals("chaos_traitor_gunner", extension:breed_name())
		assert.is_false(extension:is_companion())
	end)
end)
