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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_ally_needs_aid = true,
					target_ally_distance = 15,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally aid when too far", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_ally_needs_aid = true,
					target_ally_distance = 25,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 2,
					num_nearby = 3,
				})
			)
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks super armor targets", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					target_is_super_armor = true,
				})
			)
			assert.is_false(ok)
			assert.matches("super_armor", rule)
		end)

		it("activates on priority target at range", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					priority_target_enemy = "priority_unit",
				})
			)
			assert.is_true(ok)
			assert.matches("priority_target", rule)
		end)

		it("activates on low toughness gap close", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 10,
					toughness_pct = 0.20,
					num_nearby = 2,
				})
			)
			assert.is_true(ok)
			assert.matches("low_toughness", rule)
		end)

		it("activates on elite at range", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 10,
					target_is_elite_special = true,
				})
			)
			assert.is_true(ok)
			assert.matches("elite_special_gap", rule)
		end)

		it("activates on combat gap close with multiple enemies", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					num_nearby = 2,
				})
			)
			assert.is_true(ok)
			assert.matches("combat_gap_close", rule)
		end)

		it("holds when conditions not met", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					toughness_pct = 0.80,
					num_nearby = 1,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates for ally rescue at range", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					target_ally_needs_aid = true,
					target_ally_distance = 10,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally rescue when ally too close", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					target_ally_needs_aid = true,
					target_ally_distance = 2,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("blocks ally rescue when target too close", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 2,
					target_ally_needs_aid = true,
					target_ally_distance = 10,
				})
			)
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("shares logic with targeted dash variants", function()
			for _, variant in ipairs({
				"zealot_targeted_dash",
				"zealot_targeted_dash_improved",
				"zealot_targeted_dash_improved_double",
			}) do
				local ok, rule = evaluate(
					variant,
					ctx({
						target_enemy = "unit",
						target_enemy_distance = 10,
						target_is_elite_special = true,
					})
				)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_ally_needs_aid = true,
					target_ally_distance = 10,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.20,
					toughness_pct = 0.60,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.50,
					opportunity_target_enemy = "opp_unit",
				})
			)
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("activates on high challenge rating in peril window", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 3,
					peril_pct = 0.50,
					challenge_rating_sum = 6.0,
				})
			)
			assert.is_true(ok)
			assert.matches("threat_window", rule)
		end)

		it("bypasses peril gate when peril is 0 (bot no warp attacks)", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 3,
					peril_pct = 0,
					challenge_rating_sum = 6.0,
				})
			)
			assert.is_true(ok)
			assert.matches("threat_window", rule)
		end)

		it("bypasses peril gate for target window at peril 0", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0,
					opportunity_target_enemy = "opp_unit",
				})
			)
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("activates at peril 0 with combat density", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 3,
					peril_pct = 0,
					challenge_rating_sum = 2.0,
				})
			)
			assert.is_true(ok)
			assert.matches("combat_density", rule)
		end)

		it("still blocks at peril 0 with low threat", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					peril_pct = 0,
					challenge_rating_sum = 2.0,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- ogryn_charge
	describe("ogryn_charge", function()
		local T = "ogryn_charge"

		it("blocks when target too close", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 3,
				})
			)
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("activates on priority target", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 8,
					priority_target_enemy = "priority",
				})
			)
			assert.is_true(ok)
			assert.matches("priority_target", rule)
		end)

		it("activates for ally aid", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_ally_needs_aid = true,
					target_ally_distance = 10,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks when ally too close for charge", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_ally_needs_aid = true,
					target_ally_distance = 5,
					num_nearby = 1,
					target_enemy = "unit",
					target_enemy_distance = 8,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates as escape when overwhelmed", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 4,
					toughness_pct = 0.15,
					target_enemy = "unit",
					target_enemy_distance = 8,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 3,
					toughness_pct = 0.15,
					health_pct = 0.25,
				})
			)
			assert.is_false(ok)
			assert.matches("too_fragile", rule)
		end)

		it("activates for ally aid when healthy", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_ally_needs_aid = true,
					toughness_pct = 0.50,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("activates for horde control", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 4,
					toughness_pct = 0.50,
					health_pct = 0.40,
				})
			)
			assert.is_true(ok)
			assert.matches("horde_control", rule)
		end)

		it("blocks low-value use", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					challenge_rating_sum = 1.0,
					toughness_pct = 0.80,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 3,
					challenge_rating_sum = 3.0,
				})
			)
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks low threat", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 10,
					challenge_rating_sum = 1.0,
				})
			)
			assert.is_false(ok)
			assert.matches("low_threat", rule)
		end)

		it("activates on urgent target", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 8,
					challenge_rating_sum = 3.0,
					urgent_target_enemy = "urgent",
				})
			)
			assert.is_true(ok)
			assert.matches("urgent_target", rule)
		end)

		it("activates on ranged pack", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_enemy_distance = 10,
					target_enemy_type = "ranged",
					challenge_rating_sum = 3.0,
					elite_count = 1,
					special_count = 1,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					target_is_monster = true,
					target_enemy_distance = 5,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy = "unit",
					target_enemy_distance = 2,
				})
			)
			assert.is_false(ok)
			assert.matches("too_close", rule)
		end)

		it("blocks with no pressure", function()
			local ok, rule = evaluate(T, ctx({ num_nearby = 0 }))
			assert.is_false(ok)
			assert.matches("no_pressure", rule)
		end)

		it("activates on density", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_enemy_distance = 6,
				})
			)
			assert.is_true(ok)
			assert.matches("density", rule)
		end)

		it("activates on elite at range", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_is_elite_special = true,
					target_enemy_distance = 6,
				})
			)
			assert.is_true(ok)
			assert.matches("elite_special", rule)
		end)

		it("activates for ally rescue at range", function()
			local ok, rule = evaluate(
				T,
				ctx({
					target_enemy_distance = 6,
					target_ally_needs_aid = true,
					target_ally_distance = 10,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("blocks ally rescue when ally too close", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 6,
					target_ally_needs_aid = true,
					target_ally_distance = 2,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					elite_count = 1,
					toughness_pct = 0.45,
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_enemy_type = "ranged",
				})
			)
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
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_enemy_type = "ranged",
					toughness_pct = 0.80,
				})
			)
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
				local ok, rule = evaluate(
					T,
					ctx({
						target_ally_needs_aid = true,
						target_ally_distance = 8,
					}),
					voc_opts()
				)
				assert.is_true(ok)
				assert.matches("voc_ally_aid", rule)
			end)

			it("blocks ally aid when too far", function()
				local ok, rule = evaluate(
					T,
					ctx({
						target_ally_needs_aid = true,
						target_ally_distance = 15,
						toughness_pct = 0.90,
						num_nearby = 1,
					}),
					voc_opts()
				)
				assert.is_false(ok)
				assert.matches("voc_block_safe_state", rule)
			end)

			it("blocks in safe state", function()
				local ok, rule = evaluate(T, ctx({ toughness_pct = 0.90, num_nearby = 1 }), voc_opts())
				assert.is_false(ok)
				assert.matches("voc_block_safe_state", rule)
			end)

			it("activates in hazard with nearby enemies", function()
				local ok, rule = evaluate(
					T,
					ctx({
						in_hazard = true,
						num_nearby = 1,
						toughness_pct = 0.90,
					}),
					voc_opts()
				)
				assert.is_true(ok)
				assert.matches("voc_hazard", rule)
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
				local ok, rule = evaluate(
					T,
					ctx({
						num_nearby = 6,
						target_enemy_type = "melee",
					}),
					ranger_opts(false)
				)
				assert.is_false(ok)
				assert.matches("block_surrounded", rule)
			end)

			it("activates when vanilla condition passes", function()
				local ok, rule = evaluate(T, ctx({ num_nearby = 2 }), ranger_opts(true))
				assert.is_true(ok)
				assert.matches("target_elite_special", rule)
			end)

			it("activates on urgent target with few enemies", function()
				local ok, rule = evaluate(
					T,
					ctx({
						num_nearby = 2,
						urgent_target_enemy = "urgent",
					}),
					ranger_opts(false)
				)
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
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 5,
					toughness_pct = 0.20,
					allies_in_coherency = 2,
				})
			)
			assert.is_false(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("does not block overwhelmed if toughness ok", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 6,
					toughness_pct = 0.50,
					allies_in_coherency = 2,
					avg_ally_toughness_pct = 0.30,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on team low toughness", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 1,
					allies_in_coherency = 2,
					avg_ally_toughness_pct = 0.30,
				})
			)
			assert.is_true(ok)
			assert.matches("team_low_toughness", rule)
		end)

		it("activates on self critical toughness even without allies", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 2,
					toughness_pct = 0.20,
					allies_in_coherency = 0,
				})
			)
			assert.is_true(ok)
			assert.matches("self_critical", rule)
		end)

		it("blocks with no allies when toughness is fine", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 2,
					toughness_pct = 0.60,
					allies_in_coherency = 0,
				})
			)
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("holds in safe state with allies", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 1,
					allies_in_coherency = 2,
					avg_ally_toughness_pct = 0.80,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("blocks self_critical when num_nearby too high", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 3,
					toughness_pct = 0.20,
					allies_in_coherency = 0,
				})
			)
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("does not block overwhelmed at exact threshold", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					num_nearby = 5,
					toughness_pct = 0.30,
					allies_in_coherency = 2,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates in hazard with nearby enemies", function()
			local ok, rule = eval_item(
				"zealot_relic",
				ctx({
					in_hazard = true,
					num_nearby = 2,
					allies_in_coherency = 0,
				})
			)
			assert.is_true(ok)
			assert.matches("hazard", rule)
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
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 2,
					toughness_pct = 0.90,
				})
			)
			assert.is_false(ok)
			assert.matches("safe", rule)
		end)

		it("activates under pressure", function()
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 4,
					toughness_pct = 0.30,
				})
			)
			assert.is_true(ok)
			assert.matches("pressure", rule)
		end)

		it("activates on ally aid", function()
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 1,
					target_ally_needs_aid = true,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("activates on ranged pressure without num_nearby gate", function()
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 0,
					target_enemy_type = "ranged",
					toughness_pct = 0.40,
					target_enemy = true,
				})
			)
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
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 2,
					toughness_pct = 0.60,
					target_enemy = true,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on ally aid even when toughness is high", function()
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 1,
					toughness_pct = 0.95,
					target_ally_needs_aid = true,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("does not block safe at exact boundary", function()
			local ok, rule = eval_item(
				"psyker_force_field",
				ctx({
					num_nearby = 4,
					toughness_pct = 0.80,
					target_enemy = true,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- adamant_area_buff_drone (item-based)
	describe("adamant_area_buff_drone", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks with no allies", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 5,
					allies_in_coherency = 0,
				})
			)
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("blocks with few enemies", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 2,
					allies_in_coherency = 2,
				})
			)
			assert.is_false(ok)
			assert.matches("low_value", rule)
		end)

		it("activates on team horde", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 5,
					allies_in_coherency = 2,
				})
			)
			assert.is_true(ok)
			assert.matches("team_horde", rule)
		end)

		it("activates on monster fight with ally", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 3,
					allies_in_coherency = 1,
					target_is_monster = true,
				})
			)
			assert.is_true(ok)
			assert.matches("monster", rule)
		end)

		it("activates on monster fight even with few enemies", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 1,
					allies_in_coherency = 1,
					target_is_monster = true,
				})
			)
			assert.is_true(ok)
			assert.matches("monster", rule)
		end)

		it("activates when overwhelmed", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 6,
					allies_in_coherency = 1,
					toughness_pct = 0.40,
				})
			)
			assert.is_true(ok)
			assert.matches("overwhelmed", rule)
		end)

		it("holds in moderate state", function()
			local ok, rule = eval_item(
				"adamant_area_buff_drone",
				ctx({
					num_nearby = 3,
					allies_in_coherency = 1,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)
	end)

	-- broker_ability_stimm_field (item-based)
	describe("broker_ability_stimm_field", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		it("blocks with no allies", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 3,
					allies_in_coherency = 0,
				})
			)
			assert.is_false(ok)
			assert.matches("no_allies", rule)
		end)

		it("activates on ally corruption", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 2,
					allies_in_coherency = 1,
					max_ally_corruption_pct = 0.40,
				})
			)
			assert.is_true(ok)
			assert.matches("corruption", rule)
		end)

		it("activates on ally corruption during lull", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 0,
					allies_in_coherency = 2,
					max_ally_corruption_pct = 0.50,
				})
			)
			assert.is_true(ok)
			assert.matches("corruption", rule)
		end)

		it("does not activate on low corruption", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 2,
					allies_in_coherency = 1,
					max_ally_corruption_pct = 0.20,
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("activates on ally aid with pressure", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 3,
					allies_in_coherency = 1,
					target_ally_needs_aid = true,
				})
			)
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("holds in safe state", function()
			local ok, rule = eval_item(
				"broker_ability_stimm_field",
				ctx({
					num_nearby = 2,
					allies_in_coherency = 2,
				})
			)
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
		it("uses anti-horde rules for frag grenades", function()
			local local_ctx = helper.make_context({ num_nearby = 6, challenge_rating_sum = 3.0 })
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx)
			assert.is_true(result)
			assert.matches("horde", rule)
		end)

		it("holds frag grenades for small groups", function()
			local local_ctx = helper.make_context({ num_nearby = 3, challenge_rating_sum = 1.0 })
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("returns false for nil context", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", nil)
			assert.is_false(result)
			assert.equals("grenade_no_context", rule)
		end)

		it("uses anti-elite rules for krak grenades", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					target_enemy = "crusher",
					target_is_elite_special = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("holds krak grenades against trash", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					num_nearby = 5,
					target_enemy = "poxwalker",
					target_enemy_distance = 7,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("blocks horde grenades in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_box",
				helper.make_context({
					num_nearby = 6,
					challenge_rating_sum = 3.5,
					target_enemy = "poxwalker",
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("keeps horde grenades available outside melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_box",
				helper.make_context({
					num_nearby = 6,
					challenge_rating_sum = 3.5,
					target_enemy = "poxwalker",
					target_enemy_distance = 8,
				})
			)
			assert.is_true(result)
			assert.matches("horde", rule)
		end)

		it("blocks priority grenades under crowd pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_friend_rock",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
				})
			)
			assert.is_false(result)
			assert.matches("priority_melee_pressure", rule)
		end)

		it("blocks krak grenades in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					num_nearby = 2,
					target_enemy = "crusher",
					target_is_elite_special = true,
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("blocks krak grenades under crowd pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "crusher",
					target_is_elite_special = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_false(result)
			assert.matches("priority_melee_pressure", rule)
		end)

		it("uses defensive smoke only under pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_smoke_grenade",
				helper.make_context({
					num_nearby = 4,
					ranged_count = 2,
					toughness_pct = 0.25,
				})
			)
			assert.is_true(result)
			assert.matches("pressure", rule)
		end)

		it("holds smoke grenades in safe states", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_smoke_grenade",
				helper.make_context({
					num_nearby = 4,
					toughness_pct = 0.90,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("keeps defensive smoke available under crowd pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_smoke_grenade",
				helper.make_context({
					num_nearby = 4,
					ranged_count = 2,
					toughness_pct = 0.25,
					target_enemy = "gunner",
					target_enemy_distance = 8,
				})
			)
			assert.is_true(result)
			assert.matches("pressure", rule)
		end)

		it("blocks shock mine only in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"adamant_shock_mine",
				helper.make_context({
					num_nearby = 5,
					challenge_rating_sum = 3.5,
					elite_count = 3,
					target_enemy = "rager",
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("keeps shock mine available under crowd pressure when not in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"adamant_shock_mine",
				helper.make_context({
					num_nearby = 5,
					challenge_rating_sum = 3.5,
					elite_count = 3,
					target_enemy = "rager",
					target_enemy_distance = 8,
				})
			)
			assert.is_true(result)
			assert.matches("elite_pack", rule)
		end)

		it("uses Assail against elite targets at safe peril", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
					peril_pct = 0.30,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("uses Assail under ranged pressure without a flagged priority target", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					num_nearby = 3,
					ranged_count = 2,
					target_enemy_distance = 10,
				})
			)
			assert.is_true(result)
			assert.matches("ranged", rule)
		end)

		it("holds Assail on super armor", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "crusher",
					target_enemy_distance = 10,
					target_is_super_armor = true,
					peril_pct = 0.30,
				})
			)
			assert.is_false(result)
			assert.matches("super_armor", rule)
		end)

		it("holds Assail at high peril", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
					peril_pct = 0.95,
				})
			)
			assert.is_false(result)
			assert.matches("peril", rule)
		end)

		it("keeps zealot throwing knives opted out of the melee gate", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 7,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("uses Smite on priority targets at safe peril", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 12,
					peril_pct = 0.50,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("holds Smite at high peril", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 12,
					peril_pct = 0.90,
				})
			)
			assert.is_false(result)
			assert.matches("peril", rule)
		end)

		it("keeps Smite opted out of the melee gate", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 7,
					peril_pct = 0.50,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("uses Chain Lightning for low-peril crowd control", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_chain_lightning",
				helper.make_context({
					num_nearby = 5,
					peril_pct = 0.40,
				})
			)
			assert.is_true(result)
			assert.matches("crowd", rule)
		end)

		it("holds Chain Lightning on sparse fights", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_chain_lightning",
				helper.make_context({
					num_nearby = 2,
					peril_pct = 0.40,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		describe("adamant_whistle", function()
			local saved_vector3

			before_each(function()
				saved_vector3 = rawget(_G, "Vector3")
				_G.Vector3 = {
					distance_squared = function(a, b)
						local dx = a[1] - b[1]
						local dy = a[2] - b[2]
						local dz = a[3] - b[3]
						return dx * dx + dy * dy + dz * dz
					end,
				}
			end)

			after_each(function()
				_G.Vector3 = saved_vector3
			end)

			it("uses whistle when the companion is close enough to an elite target", function()
				local result, rule = Heuristics.evaluate_grenade_heuristic(
					"adamant_whistle",
					helper.make_context({
						target_enemy = "gunner",
						target_enemy_position = { 8, 0, 0 },
						target_is_elite_special = true,
						companion_unit = "mastiff",
						companion_position = { 1, 0, 0 },
					})
				)
				assert.is_true(result)
				assert.matches("priority_target", rule)
			end)

			it("holds whistle when the companion is too far from the target", function()
				local result, rule = Heuristics.evaluate_grenade_heuristic(
					"adamant_whistle",
					helper.make_context({
						target_enemy = "gunner",
						target_enemy_position = { 11, 0, 0 },
						target_is_elite_special = true,
						companion_unit = "mastiff",
						companion_position = { 0, 0, 0 },
					})
				)
				assert.is_false(result)
				assert.matches("companion_far", rule)
			end)
		end)

		describe("grenade preset offsets", function()
			local evaluate_grenade = Heuristics.evaluate_grenade_heuristic

			it("aggressive frag triggers at lower density than balanced", function()
				-- frag base: min_nearby=6. aggressive offset=-1 → 5. balanced offset=0 → 6.
				local c = helper.make_context({ num_nearby = 5, challenge_rating_sum = 2.0 })
				local ok_agg = evaluate_grenade("veteran_frag_grenade", c, { preset = "aggressive" })
				local ok_bal = evaluate_grenade("veteran_frag_grenade", c, { preset = "balanced" })
				assert.is_true(ok_agg)
				assert.is_false(ok_bal)
			end)

			it("conservative chain_lightning requires more enemies than balanced", function()
				-- balanced crowd=4, conservative crowd=5
				local c = helper.make_context({ num_nearby = 4, peril_pct = 0.30 })
				local ok_bal = evaluate_grenade("psyker_chain_lightning", c, { preset = "balanced" })
				local ok_con = evaluate_grenade("psyker_chain_lightning", c, { preset = "conservative" })
				assert.is_true(ok_bal)
				assert.is_false(ok_con)
			end)
		end)
	end)

	describe("build_context", function()
		local saved_managers
		local saved_position_lookup
		local saved_script_unit
		local saved_alive
		local liquid_results_return_mode
		local side_system
		local current_fixed_t
		local captured_liquid_results
		local script_unit_extensions

		before_each(function()
			liquid_results_return_mode = "table"
			side_system = nil
			current_fixed_t = 42
			captured_liquid_results = {}
			saved_managers = rawget(_G, "Managers")
			saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
			saved_script_unit = rawget(_G, "ScriptUnit")
			saved_alive = rawget(_G, "ALIVE")
			script_unit_extensions = nil

			_G.Managers = {
				state = {
					extension = {
						system = function(_, system_name)
							if system_name == "liquid_area_system" then
								return {
									find_liquid_areas_in_position = function(_, position, results)
										captured_liquid_results[#captured_liquid_results + 1] = results

										if position == "hazard_pos" then
											results[1] = {
												source_side_name = function()
													return "enemy"
												end,
												area_template_name = function()
													return "cultist_grenadier_gas"
												end,
											}

											if liquid_results_return_mode == "number" then
												return 1
											end
										end

										return results
									end,
								}
							end
							if system_name == "side_system" then
								return side_system
							end

							assert.is_true(false, "unexpected system lookup: " .. tostring(system_name))
						end,
					},
				},
			}
			_G.POSITION_LOOKUP = {
				hazard_bot = "hazard_pos",
				target_enemy = "target_pos",
				mastiff = "dog_pos",
			}
			_G.ALIVE = {
				mastiff = true,
			}
			_G.ScriptUnit = {
				has_extension = function(unit, extension_name)
					local extensions = script_unit_extensions and script_unit_extensions[unit]
					return extensions and extensions[extension_name] or nil
				end,
			}
			Heuristics.init({
				fixed_time = function()
					return current_fixed_t
				end,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = 6,
				is_testing_profile = function()
					return false
				end,
			})
		end)

		after_each(function()
			_G.Managers = saved_managers
			_G.POSITION_LOOKUP = saved_position_lookup
			_G.ScriptUnit = saved_script_unit
			_G.ALIVE = saved_alive
		end)

		it("marks context as hazardous when hostile liquid overlaps the bot position", function()
			local context = Heuristics.build_context("hazard_bot", nil)
			assert.is_true(context.in_hazard)
		end)

		it("handles liquid area api returning the results table instead of a count", function()
			liquid_results_return_mode = "table"

			local ok, context = pcall(Heuristics.build_context, "hazard_bot", nil)

			assert.is_true(ok)
			assert.is_true(context.in_hazard)
		end)

		it("reuses the liquid overlap buffer across frames", function()
			local first_context = Heuristics.build_context("hazard_bot", nil)
			current_fixed_t = 43
			local second_context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(first_context.in_hazard)
			assert.is_true(second_context.in_hazard)
			assert.are.equal(2, #captured_liquid_results)
			assert.are.equal(captured_liquid_results[1], captured_liquid_results[2])
		end)

		it("captures the live companion unit and positions in context", function()
			script_unit_extensions = {
				hazard_bot = {
					companion_spawner_system = {
						companion_units = function()
							return { "mastiff" }
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", {
				perception = {
					target_enemy = "target_enemy",
				},
			})

			assert.equals("mastiff", context.companion_unit)
			assert.equals("dog_pos", context.companion_position)
			assert.equals("target_pos", context.target_enemy_position)
		end)

		it("counts grenadiers (no breed.ranged, game_object_type=minion_ranged) as ranged", function()
			local grenadier_breed = {
				tags = { minion = true, special = true },
				game_object_type = "minion_ranged",
				challenge_rating = 2,
			}
			script_unit_extensions = {
				hazard_bot = {
					perception_system = {
						enemies_in_proximity = function()
							return { "grenadier_unit" }, 1
						end,
					},
				},
				grenadier_unit = {
					unit_data_system = {
						breed = function()
							return grenadier_breed
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals(1, context.ranged_count)
			assert.equals(0, context.melee_count)
		end)

		it("defaults when no allies are interacting", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot" },
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interacting_distance)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("detects shield interactions via interacting character state", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			}
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "interacting" }
							end
							if component_name == "interacting_character_state" then
								return { interaction_template = "scanning" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("scanning", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
		end)

		it("detects shield interactions via minigame character state", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			}
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("minigame", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
		end)

		it("detects escort interactions via luggable slot", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			}
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "walking" }
							end
							if component_name == "inventory" then
								return { wielded_slot = "slot_luggable" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("luggable", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("escort", context.ally_interaction_profile)
		end)

		it("skips self when scanning ally interactions", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot" },
					},
				},
			}
			script_unit_extensions = {
				hazard_bot = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("ignores non-shield interaction types", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			}
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "interacting" }
							end
							if component_name == "interacting_character_state" then
								return { interaction_template = "ammunition" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("ignores dead allies", function()
			side_system = {
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			}
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("picks the closest interacting ally", function()
			side_system = {
				side_by_unit = {
					bot_unit = {
						valid_player_units = { "bot_unit", "far_ally", "close_ally" },
					},
				},
			}
			_G.ALIVE.far_ally = true
			_G.ALIVE.close_ally = true
			_G.POSITION_LOOKUP.bot_unit = { x = 0, y = 0, z = 0 }
			_G.POSITION_LOOKUP.far_ally = { x = 20, y = 0, z = 0 }
			_G.POSITION_LOOKUP.close_ally = { x = 5, y = 0, z = 0 }
			script_unit_extensions = {
				far_ally = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
						end,
					},
				},
				close_ally = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
						end,
					},
				},
			}

			local context = Heuristics.build_context("bot_unit", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("close_ally", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
			assert.is_true(math.abs(context.ally_interacting_distance - 5) < 0.001)
		end)
	end)

	describe("behavior_profile", function()
		it("keeps standard combat behavior unchanged", function()
			local ok, rule = evaluate("psyker_shout", helper.make_context({ num_nearby = 2 }), {
				behavior_profile = "standard",
			})

			assert.is_false(ok)
			assert.equals("psyker_shout_hold", rule)
		end)

		it("makes combat heuristics more lenient in testing mode", function()
			local ok, rule = evaluate("psyker_shout", helper.make_context({ num_nearby = 2 }), {
				behavior_profile = "testing",
			})

			assert.is_true(ok)
			assert.matches("testing_profile", rule)
		end)

		it("makes grenade heuristics more lenient in testing mode", function()
			local ok, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					num_nearby = 3,
					peril_pct = 0.30,
				}),
				{
					behavior_profile = "testing",
				}
			)

			assert.is_true(ok)
			assert.matches("testing_profile", rule)
		end)

		it("keeps grenade peril blocks in testing mode", function()
			local ok, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 12,
					peril_pct = 0.90,
				}),
				{
					behavior_profile = "testing",
				}
			)

			assert.is_false(ok)
			assert.matches("peril", rule)
		end)

		it("makes item heuristics more lenient in testing mode", function()
			local ok, rule = Heuristics.evaluate_item_heuristic(
				"psyker_force_field_dome",
				helper.make_context({
					num_nearby = 2,
					toughness_pct = 0.50,
				}),
				{
					behavior_profile = "testing",
				}
			)

			assert.is_true(ok)
			assert.matches("testing_profile", rule)
		end)

		it("keeps grenade super armor blocks in testing mode", function()
			local ok, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "crusher",
					target_enemy_distance = 10,
					target_is_super_armor = true,
					peril_pct = 0.30,
					num_nearby = 3,
				}),
				{
					behavior_profile = "testing",
				}
			)

			assert.is_false(ok)
			assert.matches("super_armor", rule)
		end)
	end)

	describe("preset thresholds", function()
		it("aggressive triggers veteran_stealth at higher toughness than balanced", function()
			-- balanced critical_toughness = 0.25, aggressive = 0.35
			-- toughness 0.30 is < 0.35 (aggressive fires) but not < 0.25 (balanced doesn't)
			local borderline = ctx({ num_nearby = 3, toughness_pct = 0.30 })
			local ok_agg = evaluate("veteran_stealth_combat_ability", borderline, { preset = "aggressive" })
			local ok_bal = evaluate("veteran_stealth_combat_ability", borderline, { preset = "balanced" })
			assert.is_true(ok_agg)
			assert.is_false(ok_bal)
		end)

		it("balanced triggers zealot_dash elite gap at wider range than conservative", function()
			-- balanced elite_max_dist = 20, conservative = 15
			-- distance 17 is < 20 (balanced fires) but not < 15 (conservative doesn't)
			local borderline = ctx({
				target_enemy = "unit",
				target_enemy_distance = 17,
				target_is_elite_special = true,
			})
			local ok_bal = evaluate("zealot_dash", borderline, { preset = "balanced" })
			local ok_con = evaluate("zealot_dash", borderline, { preset = "conservative" })
			assert.is_true(ok_bal)
			assert.is_false(ok_con)
		end)

		it("aggressive triggers ogryn_taunt horde control with fewer enemies than balanced", function()
			-- aggressive horde_nearby = 2, balanced = 3
			-- num_nearby 2 is >= 2 (aggressive fires) but not >= 3 (balanced doesn't)
			local borderline = ctx({ num_nearby = 2, toughness_pct = 0.40, health_pct = 0.30 })
			local ok_agg = evaluate("ogryn_taunt_shout", borderline, { preset = "aggressive" })
			local ok_bal = evaluate("ogryn_taunt_shout", borderline, { preset = "balanced" })
			assert.is_true(ok_agg)
			assert.is_false(ok_bal)
		end)

		it("aggressive triggers psyker_shout surrounded with fewer enemies than balanced", function()
			-- aggressive surrounded = 2, balanced = 3
			-- num_nearby 2 is >= 2 (aggressive fires) but not >= 3 (balanced doesn't)
			local borderline = ctx({ num_nearby = 2 })
			local ok_agg = evaluate("psyker_shout", borderline, { preset = "aggressive" })
			local ok_bal = evaluate("psyker_shout", borderline, { preset = "balanced" })
			assert.is_true(ok_agg)
			assert.is_false(ok_bal)
		end)

		it("balanced triggers force_field pressure while conservative does not", function()
			-- balanced: pressure_nearby = 3, pressure_toughness = 0.40
			-- conservative: pressure_nearby = 4, pressure_toughness = 0.25
			-- num_nearby 3 meets balanced threshold but not conservative
			local borderline = ctx({ num_nearby = 3, toughness_pct = 0.35, target_enemy = "unit" })
			local ok_bal = Heuristics.evaluate_item_heuristic("psyker_force_field", borderline, { preset = "balanced" })
			local ok_con =
				Heuristics.evaluate_item_heuristic("psyker_force_field", borderline, { preset = "conservative" })
			assert.is_true(ok_bal)
			assert.is_false(ok_con)
		end)

		it("balanced preset matches hardcoded defaults exactly", function()
			-- Verify that balanced produces identical results to no-preset calls
			local scenarios = {
				{ "psyker_shout", ctx({ num_nearby = 3, peril_pct = 0.50 }) },
				{
					"ogryn_charge",
					ctx({ target_enemy = "unit", target_enemy_distance = 10, opportunity_target_enemy = "opp" }),
				},
				{ "adamant_stance", ctx({ toughness_pct = 0.25 }) },
			}
			for _, scenario in ipairs(scenarios) do
				local template, context_val = scenario[1], scenario[2]
				local ok_default, rule_default = evaluate(template, context_val)
				local ok_balanced, rule_balanced = evaluate(template, context_val, { preset = "balanced" })
				assert.are.equal(ok_default, ok_balanced)
				assert.are.equal(rule_default, rule_balanced)
			end
		end)
	end)
end)
