local MetaData = dofile("scripts/mods/BetterBots/meta_data.lua")

local function make_mock_mod()
	local messages = {}
	return {
		echo = function(_, msg)
			messages[#messages + 1] = msg
		end,
		messages = messages,
	}
end

local function noop_debug_log() end

describe("meta_data", function()
	before_each(function()
		MetaData.init({
			mod = make_mock_mod(),
			patched_ability_templates = {},
			debug_log = noop_debug_log,
			debug_enabled = function()
				return false
			end,
			META_PATCH_VERSION = 1,
		})
	end)

	describe("inject", function()
		it("injects meta_data for tier 2 templates", function()
			local templates = {
				zealot_dash = {},
				ogryn_charge = {},
				psyker_shout = {},
			}

			MetaData.inject(templates)

			assert.is_table(templates.zealot_dash.ability_meta_data)
			assert.equals("aim_pressed", templates.zealot_dash.ability_meta_data.activation.action_input)
			assert.is_table(templates.ogryn_charge.ability_meta_data)
			assert.is_table(templates.psyker_shout.ability_meta_data)
		end)

		it("does not overwrite existing meta_data", function()
			local existing = { activation = { action_input = "custom" } }
			local templates = {
				zealot_dash = { ability_meta_data = existing },
			}

			MetaData.inject(templates)

			assert.equals(existing, templates.zealot_dash.ability_meta_data)
		end)

		it("overrides veteran meta_data when action_input differs", function()
			local templates = {
				veteran_combat_ability = {
					ability_meta_data = {
						activation = { action_input = "stance_pressed" },
					},
				},
			}

			MetaData.inject(templates)

			assert.equals(
				"combat_ability_pressed",
				templates.veteran_combat_ability.ability_meta_data.activation.action_input
			)
		end)

		it("skips veteran override when action_input already correct", function()
			local correct_meta = {
				activation = { action_input = "combat_ability_pressed", min_hold_time = 0.075 },
				wait_action = { action_input = "combat_ability_released" },
			}
			local templates = {
				veteran_combat_ability = { ability_meta_data = correct_meta },
			}

			MetaData.inject(templates)

			assert.equals(correct_meta, templates.veteran_combat_ability.ability_meta_data)
		end)

		it("is idempotent for the same table", function()
			local templates = { zealot_dash = {} }

			MetaData.inject(templates)
			local first_meta = templates.zealot_dash.ability_meta_data

			MetaData.inject(templates)
			assert.equals(first_meta, templates.zealot_dash.ability_meta_data)
		end)

		it("ignores templates not in the tier 2 list", function()
			local templates = {
				some_unknown_ability = {},
			}

			MetaData.inject(templates)

			assert.is_nil(templates.some_unknown_ability.ability_meta_data)
		end)

		it("handles missing template gracefully", function()
			local templates = {}

			assert.has_no.errors(function()
				MetaData.inject(templates)
			end)
		end)
	end)
end)
