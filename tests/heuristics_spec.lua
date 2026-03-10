local helper = require("test_helper")
local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")

local ctx = helper.make_context
local evaluate = Heuristics.evaluate_heuristic

describe("heuristics", function()
	-- veteran_stealth_combat_ability
	describe("veteran_stealth", function()
		local T = "veteran_stealth_combat_ability"

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("activates on critical toughness + crowd", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, toughness_pct = 0.10 }))
			assert.is_true(ok)
			assert.matches("critical_toughness", rule)
		end)

		it("activates on low health", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 2, health_pct = 0.30 }))
			assert.is_true(ok)
			assert.matches("low_health", rule)
		end)

		it("activates on ally aid within range", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_ally_needs_aid = true,
				target_ally_distance = 15,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally aid when too far", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_ally_needs_aid = true,
				target_ally_distance = 25,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates when overwhelmed", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 7, toughness_pct = 0.35 }))
			assert.is_true(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("holds when not threatened enough", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, toughness_pct = 0.80, health_pct = 0.90 }))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- zealot_dash (covers all zealot_targeted_dash variants too)
	describe("zealot_dash", function()
		local T = "zealot_dash"

		it("blocks with no target", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3 }))
			assert.is_false(ok)
			assert.matches("no_target", rule)
		end)

		it("blocks when target too close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 2,
				num_nearby = 3,
			}))
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks super armor targets", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				target_is_super_armor = true,
			}))
			assert.is_false(ok)
			assert.matches("super_armor", rule)
		end)

		it("activates on priority target at range", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				priority_target_enemy = "priority_unit",
			}))
			assert.is_true(ok)
			assert.matches("priority_target", rule)
		end)

		it("activates on low toughness gap close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 10,
				toughness_pct = 0.20,
				num_nearby = 2,
			}))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates on elite at range", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 10,
				target_is_elite_special = true,
			}))
			assert.is_true(ok)
			assert.matches("elite_special_gap", rule)
		end)

		it("activates on combat gap close with multiple enemies", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				num_nearby = 2,
			}))
			assert.is_true(ok)
			assert.matches("combat_gap_close", rule)
		end)

		it("holds when conditions not met", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				toughness_pct = 0.80,
				num_nearby = 1,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates for ally rescue at range", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally rescue when ally too close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				target_ally_needs_aid = true,
				target_ally_distance = 2,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("blocks ally rescue when target too close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 2,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("shares logic with targeted dash variants", function()
			for _, variant in ipairs({
				"zealot_targeted_dash",
				"zealot_targeted_dash_improved",
				"zealot_targeted_dash_improved_double",
			}) do
				local ok, rule = evaluate(variant, ctx({
					target_enemy = "unit",
					target_enemy_distance = 10,
					target_is_elite_special = true,
				}))
				assert.is_true(ok, variant .. " should activate")
				assert.matches("zealot_dash", rule)
			end
		end)
	end)

	-- zealot_invisibility
	describe("zealot_invisibility", function()
		local T = "zealot_invisibility"

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("activates on emergency", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, toughness_pct = 0.15 }))
			assert.is_true(ok)
			assert.matches("emergency", rule)
		end)

		it("activates on low health alone", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, health_pct = 0.20 }))
			assert.is_true(ok)
			assert.matches("emergency", rule)
		end)

		it("activates when overwhelmed", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 5, toughness_pct = 0.45 }))
			assert.is_true(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("activates for ally reposition", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_true(ok)
			assert.matches("ally_reposition", rule)
		end)

		it("holds in safe state", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 2, toughness_pct = 0.80, health_pct = 0.90 }))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- psyker_shout
	describe("psyker_shout", function()
		local T = "psyker_shout"

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("activates on high peril", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, peril_pct = 0.80 }))
			assert.is_true(ok)
			assert.matches("high_peril", rule)
		end)

		it("activates when surrounded", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3 }))
			assert.is_true(ok)
			assert.matches("surrounded", rule)
		end)

		it("activates on low toughness", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, toughness_pct = 0.15 }))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("blocks low-value use", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				peril_pct = 0.20,
				toughness_pct = 0.60,
			}))
			assert.is_false(ok)
			assert.matches("low_value", rule)
		end)
	end)

	-- psyker_overcharge_stance
	describe("psyker_stance", function()
		local T = "psyker_overcharge_stance"

		it("returns nil when peril missing", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3 }))
			assert.is_nil(ok)
			assert.matches("missing_peril", rule)
		end)

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0, peril_pct = 0.50 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("blocks on low health", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, peril_pct = 0.50, health_pct = 0.20 }))
			assert.is_false(ok)
			assert.matches("low_health", rule)
		end)

		it("blocks outside peril window", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, peril_pct = 0.15 }))
			assert.is_false(ok)
			assert.matches("peril_window", rule)

			ok, rule = evaluate(T, ctx({ num_nearby = 3, peril_pct = 0.95 }))
			assert.is_false(ok)
			assert.matches("peril_window", rule)
		end)

		it("activates with opportunity target in peril window", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				peril_pct = 0.50,
				opportunity_target_enemy = "opp_unit",
			}))
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("activates on high challenge rating in peril window", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 3,
				peril_pct = 0.50,
				challenge_rating_sum = 6.0,
			}))
			assert.is_true(ok)
			assert.matches("threat_window", rule)
		end)

		it("bypasses peril gate when peril is 0 (bot no warp attacks)", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 3,
				peril_pct = 0,
				challenge_rating_sum = 6.0,
			}))
			assert.is_true(ok)
			assert.matches("threat_window", rule)
		end)

		it("bypasses peril gate for target window at peril 0", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				peril_pct = 0,
				opportunity_target_enemy = "opp_unit",
			}))
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("activates at peril 0 with combat density", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 3,
				peril_pct = 0,
				challenge_rating_sum = 2.0,
			}))
			assert.is_true(ok)
			assert.matches("combat_density", rule)
		end)

		it("still blocks at peril 0 with low threat", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				peril_pct = 0,
				challenge_rating_sum = 2.0,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- ogryn_charge
	describe("ogryn_charge", function()
		local T = "ogryn_charge"

		it("blocks when target too close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 3,
			}))
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("activates on priority target", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 8,
				priority_target_enemy = "priority",
			}))
			assert.is_true(ok)
			assert.matches("priority_target", rule)
		end)

		it("activates for ally aid", function()
			local ok, rule = evaluate(T, ctx({
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks when ally too close for charge", function()
			local ok, rule = evaluate(T, ctx({
				target_ally_needs_aid = true,
				target_ally_distance = 5,
				num_nearby = 1,
				target_enemy = "unit",
				target_enemy_distance = 8,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates as escape when overwhelmed", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 4,
				toughness_pct = 0.15,
				target_enemy = "unit",
				target_enemy_distance = 8,
			}))
			assert.is_true(ok)
			assert.matches("escape", rule)
		end)

		it("blocks with no pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_pressure", rule)
		end)
	end)

	-- ogryn_taunt_shout
	describe("ogryn_taunt", function()
		local T = "ogryn_taunt_shout"

		it("blocks when too fragile", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 3,
				toughness_pct = 0.15,
				health_pct = 0.25,
			}))
			assert.is_false(ok)
			assert.matches("too_fragile", rule)
		end)

		it("activates for ally aid when healthy", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_ally_needs_aid = true,
				toughness_pct = 0.50,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("activates for horde control", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 4,
				toughness_pct = 0.50,
				health_pct = 0.40,
			}))
			assert.is_true(ok)
			assert.matches("horde_control", rule)
		end)

		it("blocks low-value use", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				challenge_rating_sum = 1.0,
				toughness_pct = 0.80,
			}))
			assert.is_false(ok)
			assert.matches("low_value", rule)
		end)
	end)

	-- ogryn_gunlugger_stance
	describe("ogryn_gunlugger", function()
		local T = "ogryn_gunlugger_stance"

		it("blocks under melee pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 4, target_enemy_distance = 10 }))
			assert.is_false(ok)
			assert.matches("melee_pressure", rule)
		end)

		it("blocks when target too close", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				target_enemy_distance = 3,
				challenge_rating_sum = 3.0,
			}))
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks low threat", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				target_enemy_distance = 10,
				challenge_rating_sum = 1.0,
			}))
			assert.is_false(ok)
			assert.matches("low_threat", rule)
		end)

		it("activates on urgent target", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				target_enemy_distance = 8,
				challenge_rating_sum = 3.0,
				urgent_target_enemy = "urgent",
			}))
			assert.is_true(ok)
			assert.matches("urgent_target", rule)
		end)

		it("activates on ranged pack", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_enemy_distance = 10,
				target_enemy_type = "ranged",
				challenge_rating_sum = 3.0,
				elite_count = 1,
				special_count = 1,
			}))
			assert.is_true(ok)
			assert.matches("ranged_pack", rule)
		end)
	end)

	-- adamant_stance
	describe("adamant_stance", function()
		local T = "adamant_stance"

		it("activates on low toughness", function()
			local ok, rule = evaluate(T, ctx({ toughness_pct = 0.25 }))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates when surrounded", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, toughness_pct = 0.55 }))
			assert.is_true(ok)
			assert.matches("surrounded", rule)
		end)

		it("activates on monster pressure", function()
			local ok, rule = evaluate(T, ctx({
				target_is_monster = true,
				target_enemy_distance = 5,
			}))
			assert.is_true(ok)
			assert.matches("monster_pressure", rule)
		end)

		it("blocks in safe state", function()
			local ok, rule = evaluate(T, ctx({ toughness_pct = 0.80, num_nearby = 1 }))
			assert.is_false(ok)
			assert.matches("safe_state", rule)
		end)
	end)

	-- adamant_charge
	describe("adamant_charge", function()
		local T = "adamant_charge"

		it("blocks when target too close", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy = "unit",
				target_enemy_distance = 2,
			}))
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks with no pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_pressure", rule)
		end)

		it("activates on density", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_enemy_distance = 6,
			}))
			assert.is_true(ok)
			assert.matches("density", rule)
		end)

		it("activates on elite at range", function()
			local ok, rule = evaluate(T, ctx({
				target_is_elite_special = true,
				target_enemy_distance = 6,
			}))
			assert.is_true(ok)
			assert.matches("elite_special", rule)
		end)

		it("activates for ally rescue at range", function()
			local ok, rule = evaluate(T, ctx({
				target_enemy_distance = 6,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally rescue when ally too close", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 1,
				target_enemy_distance = 6,
				target_ally_needs_aid = true,
				target_ally_distance = 2,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- adamant_shout
	describe("adamant_shout", function()
		local T = "adamant_shout"

		it("activates on low toughness + crowd", function()
			local ok, rule = evaluate(T, ctx({ toughness_pct = 0.20, num_nearby = 2 }))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates on high density", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 5, toughness_pct = 0.45 }))
			assert.is_true(ok)
			assert.matches("density", rule)
		end)

		it("activates on elite pressure", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				elite_count = 1,
				toughness_pct = 0.45,
			}))
			assert.is_true(ok)
			assert.matches("elite_pressure", rule)
		end)

		it("holds when safe", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, toughness_pct = 0.80 }))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- broker_focus
	describe("broker_focus", function()
		local T = "broker_focus"

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("activates on low toughness", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, toughness_pct = 0.35 }))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates on ranged pressure", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_enemy_type = "ranged",
			}))
			assert.is_true(ok)
			assert.matches("ranged_pressure", rule)
		end)

		it("activates on density", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 5 }))
			assert.is_true(ok)
			assert.matches("density", rule)
		end)

		it("holds when safe", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 2, toughness_pct = 0.80 }))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- broker_punk_rage
	describe("broker_rage", function()
		local T = "broker_punk_rage"

		it("blocks with no enemies", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_enemies", rule)
		end)

		it("activates on low toughness", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, toughness_pct = 0.35 }))
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates on melee pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 3, melee_count = 2 }))
			assert.is_true(ok)
			assert.matches("melee_pressure", rule)
		end)

		it("activates on elite pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 1, elite_count = 1 }))
			assert.is_true(ok)
			assert.matches("elite_pressure", rule)
		end)

		it("blocks ranged-only low count", function()
			local ok, rule = evaluate(T, ctx({
				num_nearby = 2,
				target_enemy_type = "ranged",
				toughness_pct = 0.80,
			}))
			assert.is_false(ok)
			assert.matches("ranged_only", rule)
		end)
	end)

	-- veteran_combat_ability (needs opts for class_tag resolution)
	describe("veteran_combat_ability", function()
		local T = "veteran_combat_ability"

		describe("squad_leader (VoC)", function()
			local function voc_opts(conditions_result)
				return {
					ability_extension = helper.make_veteran_ability_extension("squad_leader", "veteran_shout"),
					conditions = helper.make_conditions(conditions_result or false),
				}
			end

			it("activates when surrounded", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 4 }), voc_opts())
				assert.is_true(ok)
				assert.matches("voc_surrounded", rule)
			end)

			it("activates on low toughness + enemies", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 2, toughness_pct = 0.40 }), voc_opts())
				assert.is_true(ok)
				assert.matches("voc_low_toughness", rule)
			end)

			it("activates on critical toughness with few enemies", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 1, toughness_pct = 0.20 }), voc_opts())
				assert.is_true(ok)
				assert.matches("voc_critical_toughness", rule)
			end)

			it("activates for ally aid", function()
				local ok, rule = evaluate(T, ctx({
					target_ally_needs_aid = true,
					target_ally_distance = 8,
				}), voc_opts())
				assert.is_true(ok)
				assert.matches("voc_ally_aid", rule)
			end)

			it("blocks ally aid when too far", function()
				local ok, rule = evaluate(T, ctx({
					target_ally_needs_aid = true,
					target_ally_distance = 15,
					toughness_pct = 0.90,
					num_nearby = 1,
				}), voc_opts())
				assert.is_false(ok)
				assert.matches("voc_block_safe_state", rule)
			end)

			it("blocks in safe state", function()
				local ok, rule = evaluate(T, ctx({ toughness_pct = 0.90, num_nearby = 1 }), voc_opts())
				assert.is_false(ok)
				assert.matches("voc_block_safe_state", rule)
			end)
		end)

		describe("ranger (Executioner Stance)", function()
			local function ranger_opts(vanilla_result)
				return {
					ability_extension = helper.make_veteran_ability_extension("ranger", "veteran_stance"),
					conditions = helper.make_conditions(vanilla_result),
				}
			end

			it("blocks when surrounded by melee", function()
				local ok, rule = evaluate(T, ctx({
					num_nearby = 6,
					target_enemy_type = "melee",
				}), ranger_opts(false))
				assert.is_false(ok)
				assert.matches("block_surrounded", rule)
			end)

			it("activates when vanilla condition passes", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 2 }), ranger_opts(true))
				assert.is_true(ok)
				assert.matches("target_elite_special", rule)
			end)

			it("activates on urgent target with few enemies", function()
				local ok, rule = evaluate(T, ctx({
					num_nearby = 2,
					urgent_target_enemy = "urgent",
				}), ranger_opts(false))
				assert.is_true(ok)
				assert.matches("urgent_target", rule)
			end)

			it("holds when no conditions met", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 2 }), ranger_opts(false))
				assert.is_false(ok)
				assert.matches("stance_hold", rule)
			end)
		end)

		describe("unknown variant", function()
			it("returns nil for unresolved class_tag", function()
				local opts = {
					ability_extension = helper.make_veteran_ability_extension(nil, "something_new"),
					conditions = helper.make_conditions(false),
				}
				local ok, rule = evaluate(T, ctx({ num_nearby = 3 }), opts)
				assert.is_nil(ok)
				assert.matches("veteran_variant", rule)
			end)
		end)
	end)

	-- zealot_relic (item-based)
	describe("zealot_relic", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks when overwhelmed and fragile", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 5, toughness_pct = 0.20, allies_in_coherency = 2,
			}))
			assert.is_false(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("does not block overwhelmed if toughness ok", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 6, toughness_pct = 0.50, allies_in_coherency = 2,
				avg_ally_toughness_pct = 0.30,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on team low toughness", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 1, allies_in_coherency = 2, avg_ally_toughness_pct = 0.30,
			}))
			assert.is_true(ok)
			assert.matches("team_low_toughness", rule)
		end)

		it("activates on self critical toughness even without allies", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 2, toughness_pct = 0.20, allies_in_coherency = 0,
			}))
			assert.is_true(ok)
			assert.matches("self_critical", rule)
		end)

		it("blocks with no allies when toughness is fine", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 2, toughness_pct = 0.60, allies_in_coherency = 0,
			}))
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("holds in safe state with allies", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 1, allies_in_coherency = 2, avg_ally_toughness_pct = 0.80,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("blocks self_critical when num_nearby too high", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 3, toughness_pct = 0.20, allies_in_coherency = 0,
			}))
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("does not block overwhelmed at exact threshold", function()
			local ok, rule = eval_item("zealot_relic", ctx({
				num_nearby = 5, toughness_pct = 0.30, allies_in_coherency = 2,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("returns false for unknown item ability", function()
			local ok, rule = eval_item("unknown_ability_xyz", ctx({ num_nearby = 5 }))
			assert.is_false(ok)
			assert.matches("unknown_item", rule)
		end)
	end)

	-- force_field (item-based)
	describe("force_field", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks with no threats", function()
			local ok, rule = eval_item("psyker_force_field", ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_threats", rule)
		end)

		it("blocks when safe", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 2, toughness_pct = 0.90,
			}))
			assert.is_false(ok)
			assert.matches("safe", rule)
		end)

		it("activates under pressure", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 4, toughness_pct = 0.30,
			}))
			assert.is_true(ok)
			assert.matches("pressure", rule)
		end)

		it("activates on ally aid", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 1, target_ally_needs_aid = true,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("activates on ranged pressure without num_nearby gate", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 0, target_enemy_type = "ranged", toughness_pct = 0.40,
				target_enemy = true,
			}))
			assert.is_true(ok)
			assert.matches("ranged", rule)
		end)

		it("all variants use same heuristic", function()
			local c = ctx({ num_nearby = 4, toughness_pct = 0.30 })
			local ok1, rule1 = eval_item("psyker_force_field", c)
			local ok2, rule2 = eval_item("psyker_force_field_improved", c)
			local ok3, rule3 = eval_item("psyker_force_field_dome", c)
			assert.is_true(ok1)
			assert.is_true(ok2)
			assert.is_true(ok3)
			assert.are.equal(rule1, rule2)
			assert.are.equal(rule2, rule3)
		end)

		it("holds in moderate state", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 2, toughness_pct = 0.60, target_enemy = true,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on ally aid even when toughness is high", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 1, toughness_pct = 0.95, target_ally_needs_aid = true,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("does not block safe at exact boundary", function()
			local ok, rule = eval_item("psyker_force_field", ctx({
				num_nearby = 4, toughness_pct = 0.80, target_enemy = true,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- adamant_area_buff_drone (item-based)
	describe("adamant_area_buff_drone", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks with no allies", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 5, allies_in_coherency = 0,
			}))
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("blocks with few enemies", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 2, allies_in_coherency = 2,
			}))
			assert.is_false(ok)
			assert.matches("low_value", rule)
		end)

		it("activates on team horde", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 5, allies_in_coherency = 2,
			}))
			assert.is_true(ok)
			assert.matches("team_horde", rule)
		end)

		it("activates on monster fight with ally", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 3, allies_in_coherency = 1, target_is_monster = true,
			}))
			assert.is_true(ok)
			assert.matches("monster", rule)
		end)

		it("activates on monster fight even with few enemies", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 1, allies_in_coherency = 1, target_is_monster = true,
			}))
			assert.is_true(ok)
			assert.matches("monster", rule)
		end)

		it("activates when overwhelmed", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 6, allies_in_coherency = 1, toughness_pct = 0.40,
			}))
			assert.is_true(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("holds in moderate state", function()
			local ok, rule = eval_item("adamant_area_buff_drone", ctx({
				num_nearby = 3, allies_in_coherency = 1,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- broker_ability_stimm_field (item-based)
	describe("broker_ability_stimm_field", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks with no allies", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 3, allies_in_coherency = 0,
			}))
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("activates on ally corruption", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 2, allies_in_coherency = 1,
				max_ally_corruption_pct = 0.40,
			}))
			assert.is_true(ok)
			assert.matches("corruption", rule)
		end)

		it("activates on ally corruption during lull", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 0, allies_in_coherency = 2,
				max_ally_corruption_pct = 0.50,
			}))
			assert.is_true(ok)
			assert.matches("corruption", rule)
		end)

		it("does not activate on low corruption", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 2, allies_in_coherency = 1,
				max_ally_corruption_pct = 0.20,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on ally aid with pressure", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 3, allies_in_coherency = 1,
				target_ally_needs_aid = true,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("holds in safe state", function()
			local ok, rule = eval_item("broker_ability_stimm_field", ctx({
				num_nearby = 2, allies_in_coherency = 2,
			}))
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- unknown template
	describe("unknown template", function()
		it("returns nil with unhandled rule", function()
			local ok, rule = evaluate("nonexistent_template", ctx({ num_nearby = 5 }))
			assert.is_nil(ok)
			assert.equals("fallback_unhandled_template", rule)
		end)
	end)

	describe("evaluate_grenade_heuristic", function()
		it("returns true when enemies are nearby", function()
			local ctx = helper.make_context({ num_nearby = 3 })
			local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", ctx)
			assert.is_true(result)
			assert.equals("grenade_generic", rule)
		end)

		it("returns false when no enemies", function()
			local ctx = helper.make_context({ num_nearby = 0 })
			local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", ctx)
			assert.is_false(result)
			assert.equals("grenade_no_enemies", rule)
		end)

		it("returns false for nil context", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", nil)
			assert.is_false(result)
			assert.equals("grenade_no_context", rule)
		end)
	end)
end)
