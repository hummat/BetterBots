local Settings = dofile("scripts/mods/BetterBots/settings.lua")
local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local helper = require("tests.test_helper")

local function mock_mod(overrides)
	return {
		mod = {
			get = function(_, setting_id)
				return overrides and overrides[setting_id]
			end,
		},
		combat_ability_identity = CombatAbilityIdentity,
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

	describe("ammo policy settings", function()
		it("returns default ammo thresholds when mod returns nil", function()
			Settings.init(mock_mod({}))

			assert.are.equal(0.20, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.80, Settings.human_ammo_reserve_threshold())
		end)

		it("normalizes numeric slider values into percentages", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = 25,
				bot_human_ammo_reserve_threshold = 85,
			}))

			assert.are.equal(0.25, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.85, Settings.human_ammo_reserve_threshold())
		end)

		it("accepts stringified slider values from DMF", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = "15",
				bot_human_ammo_reserve_threshold = "95",
			}))

			assert.are.equal(0.15, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.95, Settings.human_ammo_reserve_threshold())
		end)

		it("accepts full bot ranged ammo threshold extremes", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = 0,
				bot_human_ammo_reserve_threshold = 100,
			}))

			assert.are.equal(0.00, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(1.00, Settings.human_ammo_reserve_threshold())
		end)

		it("falls back to defaults for invalid ammo slider values", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = "bad",
				bot_human_ammo_reserve_threshold = -1,
			}))

			assert.are.equal(0.20, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.80, Settings.human_ammo_reserve_threshold())
		end)
	end)

	describe("grenade pickup settings", function()
		it("returns default grenade thresholds when mod returns nil", function()
			Settings.init(mock_mod({}))

			assert.are.equal(0, Settings.bot_grenade_charges_threshold())
			assert.are.equal(1.00, Settings.human_grenade_reserve_threshold())
		end)

		it("reads numeric grenade slider values", function()
			Settings.init(mock_mod({
				bot_grenade_charges_threshold = 2,
				bot_human_grenade_reserve_threshold = 75,
			}))

			assert.are.equal(2, Settings.bot_grenade_charges_threshold())
			assert.are.equal(0.75, Settings.human_grenade_reserve_threshold())
		end)

		it("accepts stringified grenade slider values from DMF", function()
			Settings.init(mock_mod({
				bot_grenade_charges_threshold = "1",
				bot_human_grenade_reserve_threshold = "100",
			}))

			assert.are.equal(1, Settings.bot_grenade_charges_threshold())
			assert.are.equal(1.00, Settings.human_grenade_reserve_threshold())
		end)

		it("falls back to defaults for invalid grenade slider values", function()
			Settings.init(mock_mod({
				bot_grenade_charges_threshold = "bad",
				bot_human_grenade_reserve_threshold = 101,
			}))

			assert.are.equal(0, Settings.bot_grenade_charges_threshold())
			assert.are.equal(1.00, Settings.human_grenade_reserve_threshold())
		end)
	end)

	describe("mule pickup settings", function()
		it("disables bot grimoire pickup by default", function()
			Settings.init(mock_mod({}))

			assert.is_false(Settings.is_bot_grimoire_pickup_enabled())
		end)

		it("enables bot grimoire pickup when setting is on", function()
			Settings.init(mock_mod({
				enable_bot_grimoire_pickup = true,
			}))

			assert.is_true(Settings.is_bot_grimoire_pickup_enabled())
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

	describe("veteran semantic stance/shout gate", function()
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
		it("returns true for all known features when settings return nil", function()
			Settings.init(mock_mod({}))

			assert.is_true(Settings.is_feature_enabled("pinging"))
			assert.is_true(Settings.is_feature_enabled("poxburster"))
			assert.is_true(Settings.is_feature_enabled("melee_improvements"))
			assert.is_true(Settings.is_feature_enabled("ranged_improvements"))
			assert.is_true(Settings.is_feature_enabled("engagement_leash"))
			assert.is_true(Settings.is_feature_enabled("smart_targeting"))
			assert.is_true(Settings.is_feature_enabled("daemonhost_avoidance"))
			assert.is_true(Settings.is_feature_enabled("target_type_hysteresis"))
			assert.is_true(Settings.is_feature_enabled("human_likeness"))
		end)

		it("returns true for unknown feature names", function()
			Settings.init(mock_mod({ unknown_feature_setting = false }))
			assert.is_true(Settings.is_feature_enabled("completely_unknown_feature"))
		end)

		it("sprint and special_penalty are no longer feature gates (replaced by sliders)", function()
			Settings.init(mock_mod({}))
			-- These are now unknown feature names — default to enabled (fail-open)
			assert.is_true(Settings.is_feature_enabled("sprint"))
			assert.is_true(Settings.is_feature_enabled("special_penalty"))
		end)

		it("gates pinging feature correctly", function()
			Settings.init(mock_mod({ enable_pinging = false }))
			assert.is_false(Settings.is_feature_enabled("pinging"))
		end)

		it("gates poxburster feature correctly", function()
			Settings.init(mock_mod({ enable_poxburster = false }))
			assert.is_false(Settings.is_feature_enabled("poxburster"))
		end)

		it("gates melee_improvements feature correctly", function()
			Settings.init(mock_mod({ enable_melee_improvements = false }))
			assert.is_false(Settings.is_feature_enabled("melee_improvements"))
		end)

		it("gates ranged_improvements feature correctly", function()
			Settings.init(mock_mod({ enable_ranged_improvements = false }))
			assert.is_false(Settings.is_feature_enabled("ranged_improvements"))
		end)

		it("gates engagement_leash feature correctly", function()
			Settings.init(mock_mod({ enable_engagement_leash = false }))
			assert.is_false(Settings.is_feature_enabled("engagement_leash"))
		end)

		it("gates target_type_hysteresis feature correctly", function()
			Settings.init(mock_mod({ enable_target_type_hysteresis = false }))
			assert.is_false(Settings.is_feature_enabled("target_type_hysteresis"))
		end)

		it("gates human_likeness feature correctly", function()
			Settings.init(mock_mod({ enable_human_likeness = false }))
			assert.is_false(Settings.is_feature_enabled("human_likeness"))
		end)
	end)

	describe("slider settings", function()
		describe("player_tag_bonus", function()
			it("returns default 3 when mod returns nil", function()
				Settings.init(mock_mod({}))
				assert.equals(3, Settings.player_tag_bonus())
			end)

			it("returns configured value", function()
				Settings.init(mock_mod({ player_tag_bonus = 7 }))
				assert.equals(7, Settings.player_tag_bonus())
			end)

			it("returns 0 when set to 0 (disabled)", function()
				Settings.init(mock_mod({ player_tag_bonus = 0 }))
				assert.equals(0, Settings.player_tag_bonus())
			end)

			it("accepts stringified values from DMF", function()
				Settings.init(mock_mod({ player_tag_bonus = "5" }))
				assert.equals(5, Settings.player_tag_bonus())
			end)

			it("falls back to default for invalid values", function()
				Settings.init(mock_mod({ player_tag_bonus = "bad" }))
				assert.equals(3, Settings.player_tag_bonus())
			end)

			it("clamps out-of-range values to default", function()
				Settings.init(mock_mod({ player_tag_bonus = 99 }))
				assert.equals(3, Settings.player_tag_bonus())
			end)
		end)

		describe("melee_horde_light_bias", function()
			it("returns default 4 when mod returns nil", function()
				Settings.init(mock_mod({}))
				assert.equals(4, Settings.melee_horde_light_bias())
			end)

			it("returns configured value", function()
				Settings.init(mock_mod({ melee_horde_light_bias = 8 }))
				assert.equals(8, Settings.melee_horde_light_bias())
			end)

			it("returns 0 when set to 0 (disabled)", function()
				Settings.init(mock_mod({ melee_horde_light_bias = 0 }))
				assert.equals(0, Settings.melee_horde_light_bias())
			end)
		end)

		describe("sprint_follow_distance", function()
			it("returns default 12 when mod returns nil", function()
				Settings.init(mock_mod({}))
				assert.equals(12, Settings.sprint_follow_distance())
			end)

			it("returns configured value", function()
				Settings.init(mock_mod({ sprint_follow_distance = 20 }))
				assert.equals(20, Settings.sprint_follow_distance())
			end)

			it("returns 0 when set to 0 (disabled)", function()
				Settings.init(mock_mod({ sprint_follow_distance = 0 }))
				assert.equals(0, Settings.sprint_follow_distance())
			end)

			it("migrates legacy enable_sprint=false to 0", function()
				Settings.init(mock_mod({ enable_sprint = false }))
				assert.equals(0, Settings.sprint_follow_distance())
			end)

			it("prefers slider value when both legacy and slider are set", function()
				Settings.init(mock_mod({ enable_sprint = false, sprint_follow_distance = 20 }))
				assert.equals(20, Settings.sprint_follow_distance())
			end)
		end)

		describe("special_chase_penalty_range", function()
			it("returns default 18 when mod returns nil", function()
				Settings.init(mock_mod({}))
				assert.equals(18, Settings.special_chase_penalty_range())
			end)

			it("returns configured value", function()
				Settings.init(mock_mod({ special_chase_penalty_range = 24 }))
				assert.equals(24, Settings.special_chase_penalty_range())
			end)

			it("returns 0 when set to 0 (disabled)", function()
				Settings.init(mock_mod({ special_chase_penalty_range = 0 }))
				assert.equals(0, Settings.special_chase_penalty_range())
			end)

			it("migrates legacy enable_special_penalty=false to 0", function()
				Settings.init(mock_mod({ enable_special_penalty = false }))
				assert.equals(0, Settings.special_chase_penalty_range())
			end)

			it("prefers slider value when both legacy and slider are set", function()
				Settings.init(mock_mod({
					enable_special_penalty = false,
					special_chase_penalty_range = 24,
				}))
				assert.equals(24, Settings.special_chase_penalty_range())
			end)
		end)
	end)

	describe("new feature gates", function()
		it("gates smart_targeting feature correctly", function()
			Settings.init(mock_mod({ enable_smart_targeting = false }))
			assert.is_false(Settings.is_feature_enabled("smart_targeting"))
		end)

		it("defaults smart_targeting to enabled", function()
			Settings.init(mock_mod({}))
			assert.is_true(Settings.is_feature_enabled("smart_targeting"))
		end)

		it("gates daemonhost_avoidance feature correctly", function()
			Settings.init(mock_mod({ enable_daemonhost_avoidance = false }))
			assert.is_false(Settings.is_feature_enabled("daemonhost_avoidance"))
		end)

		it("defaults daemonhost_avoidance to enabled", function()
			Settings.init(mock_mod({}))
			assert.is_true(Settings.is_feature_enabled("daemonhost_avoidance"))
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

			-- veteran_combat_ability is handled via semantic identity, NOT in CATEGORY_ tables.
			-- The test above would never find it in a CATEGORY_ block, but assert it's absent
			-- to catch regressions.
			assert.is_nil(
				template_names["veteran_combat_ability"],
				"veteran_combat_ability must NOT appear in any CATEGORY_ table (uses semantic identity)"
			)

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
				combat_ability_identity = CombatAbilityIdentity,
			})

			for template_name in pairs(template_names) do
				local result, rule = Heuristics.evaluate_heuristic(
					template_name,
					helper.make_context({
						num_nearby = 1,
					}),
					{
						conditions = helper.make_conditions(false),
						ability_extension = helper.make_veteran_ability_extension("ranger", template_name),
					}
				)

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
