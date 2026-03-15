local Settings = dofile("scripts/mods/BetterBots/settings.lua")
local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
local helper = require("tests.test_helper")

local function mock_mod(overrides)
	return {
		mod = {
			get = function(_, setting_id)
				return overrides and overrides[setting_id]
			end,
		},
	}
end

describe("settings", function()
	describe("resolve_preset", function()
		it("defaults to balanced when mod returns nil", function()
			Settings.init(mock_mod({}))
			assert.equals("balanced", Settings.resolve_preset())
		end)

		it("accepts testing preset", function()
			Settings.init(mock_mod({ behavior_profile = "testing" }))
			assert.equals("testing", Settings.resolve_preset())
		end)

		it("accepts aggressive preset", function()
			Settings.init(mock_mod({ behavior_profile = "aggressive" }))
			assert.equals("aggressive", Settings.resolve_preset())
		end)

		it("accepts balanced preset", function()
			Settings.init(mock_mod({ behavior_profile = "balanced" }))
			assert.equals("balanced", Settings.resolve_preset())
		end)

		it("accepts conservative preset", function()
			Settings.init(mock_mod({ behavior_profile = "conservative" }))
			assert.equals("conservative", Settings.resolve_preset())
		end)

		it("migrates standard to balanced silently", function()
			Settings.init(mock_mod({ behavior_profile = "standard" }))
			assert.equals("balanced", Settings.resolve_preset())
		end)

		it("falls back to balanced for unknown values", function()
			Settings.init(mock_mod({ behavior_profile = "broken" }))
			assert.equals("balanced", Settings.resolve_preset())
		end)
	end)

	describe("is_testing_profile", function()
		it("returns true only for testing preset", function()
			Settings.init(mock_mod({ behavior_profile = "testing" }))
			assert.is_true(Settings.is_testing_profile())
		end)

		it("returns false for balanced preset", function()
			Settings.init(mock_mod({ behavior_profile = "balanced" }))
			assert.is_false(Settings.is_testing_profile())
		end)

		it("returns false for aggressive preset", function()
			Settings.init(mock_mod({ behavior_profile = "aggressive" }))
			assert.is_false(Settings.is_testing_profile())
		end)

		it("returns false for conservative preset", function()
			Settings.init(mock_mod({ behavior_profile = "conservative" }))
			assert.is_false(Settings.is_testing_profile())
		end)

		it("returns false when mod returns nil (defaults to balanced)", function()
			Settings.init(mock_mod({}))
			assert.is_false(Settings.is_testing_profile())
		end)
	end)

	describe("category gates", function()
		it("disables stance templates when enable_stances is off", function()
			Settings.init(mock_mod({ enable_stances = false }))

			assert.is_false(Settings.is_combat_template_enabled("psyker_overcharge_stance"))
			assert.is_false(Settings.is_combat_template_enabled("ogryn_gunlugger_stance"))
			assert.is_false(Settings.is_combat_template_enabled("adamant_stance"))
			assert.is_false(Settings.is_combat_template_enabled("broker_focus"))
			assert.is_false(Settings.is_combat_template_enabled("broker_punk_rage"))
		end)

		it("enables stance templates when enable_stances is true", function()
			Settings.init(mock_mod({ enable_stances = true }))

			assert.is_true(Settings.is_combat_template_enabled("psyker_overcharge_stance"))
			assert.is_true(Settings.is_combat_template_enabled("ogryn_gunlugger_stance"))
		end)

		it("disables charge templates when enable_charges is off", function()
			Settings.init(mock_mod({ enable_charges = false }))

			assert.is_false(Settings.is_combat_template_enabled("zealot_dash"))
			assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash"))
			assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash_improved"))
			assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash_improved_double"))
			assert.is_false(Settings.is_combat_template_enabled("ogryn_charge"))
			assert.is_false(Settings.is_combat_template_enabled("ogryn_charge_increased_distance"))
			assert.is_false(Settings.is_combat_template_enabled("adamant_charge"))
		end)

		it("disables shout templates when enable_shouts is off", function()
			Settings.init(mock_mod({ enable_shouts = false }))

			assert.is_false(Settings.is_combat_template_enabled("psyker_shout"))
			assert.is_false(Settings.is_combat_template_enabled("ogryn_taunt_shout"))
			assert.is_false(Settings.is_combat_template_enabled("adamant_shout"))
		end)

		it("disables stealth templates when enable_stealth is off", function()
			Settings.init(mock_mod({ enable_stealth = false }))

			assert.is_false(Settings.is_combat_template_enabled("veteran_stealth_combat_ability"))
			assert.is_false(Settings.is_combat_template_enabled("zealot_invisibility"))
		end)

		it("disables deployable items when enable_deployables is off", function()
			Settings.init(mock_mod({ enable_deployables = false }))

			assert.is_false(Settings.is_item_ability_enabled("zealot_relic"))
			assert.is_false(Settings.is_item_ability_enabled("psyker_force_field"))
			assert.is_false(Settings.is_item_ability_enabled("psyker_force_field_improved"))
			assert.is_false(Settings.is_item_ability_enabled("psyker_force_field_dome"))
			assert.is_false(Settings.is_item_ability_enabled("adamant_area_buff_drone"))
			assert.is_false(Settings.is_item_ability_enabled("broker_ability_stimm_field"))
		end)

		it("disables all grenades when enable_grenades is off", function()
			Settings.init(mock_mod({ enable_grenades = false }))

			assert.is_false(Settings.is_grenade_enabled("veteran_frag_grenade"))
			assert.is_false(Settings.is_grenade_enabled("psyker_throwing_knives"))
			assert.is_false(Settings.is_grenade_enabled("unknown_grenade"))
		end)

		it("enables all grenades when enable_grenades is true", function()
			Settings.init(mock_mod({ enable_grenades = true }))

			assert.is_true(Settings.is_grenade_enabled("veteran_frag_grenade"))
		end)

		it("leaves unknown combat templates enabled", function()
			Settings.init(mock_mod({
				enable_stances = false,
				enable_charges = false,
				enable_shouts = false,
				enable_stealth = false,
			}))

			assert.is_true(Settings.is_combat_template_enabled("unknown_template"))
		end)

		it("leaves unknown item abilities enabled", function()
			Settings.init(mock_mod({ enable_deployables = false }))

			assert.is_true(Settings.is_item_ability_enabled("unknown_item"))
		end)

		it("defaults enabled when mod returns nil (nil means on)", function()
			Settings.init(mock_mod({}))

			assert.is_true(Settings.is_combat_template_enabled("zealot_dash"))
			assert.is_true(Settings.is_item_ability_enabled("zealot_relic"))
			assert.is_true(Settings.is_grenade_enabled("veteran_frag_grenade"))
		end)
	end)

	describe("veteran dual-category gate", function()
		it("gates as stance when class_tag is ranger", function()
			local ability_ext = helper.make_veteran_ability_extension("ranger", "veteran_combat_ability")

			Settings.init(mock_mod({ enable_stances = false }))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))

			Settings.init(mock_mod({ enable_stances = true }))
			assert.is_true(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))
		end)

		it("gates as stance when class_tag is base", function()
			local ability_ext = helper.make_veteran_ability_extension("base", "veteran_combat_ability")

			Settings.init(mock_mod({ enable_stances = false }))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))
		end)

		it("gates as shout when class_tag is squad_leader", function()
			local ability_ext = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability")

			Settings.init(mock_mod({ enable_shouts = false }))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))

			Settings.init(mock_mod({ enable_shouts = true }))
			assert.is_true(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))
		end)

		it("falls back to stances when class_tag is unknown", function()
			local ability_ext = helper.make_veteran_ability_extension("unknown_tag", "veteran_combat_ability")

			Settings.init(mock_mod({ enable_stances = false }))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))
		end)

		it("falls back to stances when ability_extension is nil", function()
			Settings.init(mock_mod({ enable_stances = false }))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", nil))
		end)

		it("veteran_combat_ability not disabled by enable_stealth alone", function()
			local ability_ext = helper.make_veteran_ability_extension("ranger", "veteran_combat_ability")

			Settings.init(mock_mod({ enable_stealth = false, enable_stances = true }))
			assert.is_true(Settings.is_combat_template_enabled("veteran_combat_ability", ability_ext))
		end)
	end)

	describe("is_feature_enabled", function()
		it("returns true when feature setting is true", function()
			Settings.init(mock_mod({ enable_sprint = true }))
			assert.is_true(Settings.is_feature_enabled("sprint"))
		end)

		it("returns false when feature setting is false", function()
			Settings.init(mock_mod({ enable_sprint = false }))
			assert.is_false(Settings.is_feature_enabled("sprint"))
		end)

		it("returns true when feature setting is nil (default-on)", function()
			Settings.init(mock_mod({}))
			assert.is_true(Settings.is_feature_enabled("sprint"))
		end)

		it("returns true for all known features when settings return nil", function()
			Settings.init(mock_mod({}))

			assert.is_true(Settings.is_feature_enabled("sprint"))
			assert.is_true(Settings.is_feature_enabled("pinging"))
			assert.is_true(Settings.is_feature_enabled("special_penalty"))
			assert.is_true(Settings.is_feature_enabled("poxburster"))
		end)

		it("returns true for unknown feature names", function()
			Settings.init(mock_mod({ unknown_feature_setting = false }))
			assert.is_true(Settings.is_feature_enabled("completely_unknown_feature"))
		end)

		it("gates pinging feature correctly", function()
			Settings.init(mock_mod({ enable_pinging = false }))
			assert.is_false(Settings.is_feature_enabled("pinging"))
		end)

		it("gates special_penalty feature correctly", function()
			Settings.init(mock_mod({ enable_special_penalty = false }))
			assert.is_false(Settings.is_feature_enabled("special_penalty"))
		end)

		it("gates poxburster feature correctly", function()
			Settings.init(mock_mod({ enable_poxburster = false }))
			assert.is_false(Settings.is_feature_enabled("poxburster"))
		end)
	end)

	describe("heuristic coverage", function()
		it("every template in CATEGORY_ tables has heuristic coverage", function()
			-- Read all template names from the CATEGORY_ tables in settings.lua.
			-- We use the source file to discover them, same pattern as the old test.
			local handle = assert(io.open("scripts/mods/BetterBots/settings.lua", "r"))
			local source = assert(handle:read("*a"))
			handle:close()

			local template_names = {}
			-- Match all CATEGORY_ block names and collect templates from each
			for block_name in source:gmatch("local%s+(CATEGORY_%w+)%s*=%s*%b{}") do
				local block = source:match("local%s+" .. block_name .. "%s*=%s*(%b{})")
				for name in block:gmatch("([a-z0-9_]+)%s*=") do
					template_names[name] = true
				end
			end

			-- veteran_combat_ability is handled via dual-category gate, NOT in CATEGORY_ tables.
			-- The test above would never find it in a CATEGORY_ block, but assert it's absent
			-- to catch regressions.
			assert.is_nil(template_names["veteran_combat_ability"],
				"veteran_combat_ability must NOT appear in any CATEGORY_ table (uses dual-category gate)")

			Heuristics.init({
				fixed_time = function()
					return 0
				end,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = 6,
				is_testing_profile = function()
					return false
				end,
				resolve_preset = function()
					return "balanced"
				end,
			})

			for template_name in pairs(template_names) do
				local result, rule = Heuristics.evaluate_heuristic(template_name, helper.make_context({
					num_nearby = 1,
				}), {
					conditions = helper.make_conditions(false),
					ability_extension = helper.make_veteran_ability_extension("ranger", template_name),
				})

				assert.are_not.equal(
					"fallback_unhandled_template",
					rule,
					string.format(
						"settings template %s is missing heuristic coverage (result=%s, rule=%s)",
						template_name,
						tostring(result),
						tostring(rule)
					)
				)
			end
		end)
	end)
end)
