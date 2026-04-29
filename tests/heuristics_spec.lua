local helper = require("test_helper")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local Heuristics = helper.load_split_heuristics({
	combat_ability_identity = CombatAbilityIdentity,
})

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

		it("holds low-health-only stealth panic for Martyrdom", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					health_pct = 0.20,
					talents = {
						zealot_martyrdom = 1,
					},
				})
			)
			assert.is_false(ok)
			assert.matches("martyrdom_low_health", rule)
		end)

		it("still activates on low toughness emergency for Martyrdom", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 3,
					toughness_pct = 0.15,
					health_pct = 0.20,
					talents = {
						zealot_martyrdom = 1,
					},
				})
			)
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

		it("preserves peril longer with Warp Siphon damage talents", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					peril_pct = 0.80,
					talents = {
						psyker_damage_based_on_warp_charge = 1,
						psyker_warp_glass_cannon = 1,
					},
				})
			)
			assert.is_false(ok)
			assert.matches("preserve_peril", rule)
		end)

		it("uses an even later peril threshold with vent-on-shout talent", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					peril_pct = 0.85,
					talents = {
						psyker_damage_based_on_warp_charge = 1,
						psyker_warp_glass_cannon = 1,
						psyker_shout_vent_warp_charge = 1,
					},
				})
			)
			assert.is_false(ok)
			assert.matches("preserve_peril", rule)
		end)

		it("still vents at very high peril with the talent-aware threshold", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					peril_pct = 0.90,
					talents = {
						psyker_damage_based_on_warp_charge = 1,
						psyker_warp_glass_cannon = 1,
						psyker_shout_vent_warp_charge = 1,
					},
				})
			)
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

		it("widens the high-peril ceiling for Warp Unbound builds", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.95,
					opportunity_target_enemy = "opp_unit",
					talents = {
						psyker_overcharge_stance_infinite_casting = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("keeps Warp Unbound as the final high-peril ceiling when combined with reduced-warp-charge", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.95,
					opportunity_target_enemy = "opp_unit",
					talents = {
						psyker_overcharge_reduced_warp_charge = true,
						psyker_overcharge_stance_infinite_casting = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("target_window", rule)
		end)

		it("lowers the threat gate for Disrupt Destiny or weakspot-kill Scrier builds", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.50,
					challenge_rating_sum = 3.2,
					talents = {
						psyker_new_mark_passive = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("threat_window_build", rule)
		end)

		it("treats weakspot-kill Scrier builds as aggressive even without Disrupt Destiny", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					peril_pct = 0.50,
					challenge_rating_sum = 3.2,
					talents = {
						psyker_overcharge_weakspot_kill_bonuses = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("threat_window_build", rule)
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

		it("does not spend Scrier's Gaze on a lone enemy in the zero-peril fallback for aggressive builds", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					peril_pct = 0,
					challenge_rating_sum = 2.0,
					talents = {
						psyker_new_mark_passive = true,
					},
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
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

		it("logs once when build-aware psyker heuristics receive a nil talents table", function()
			local debug_logs = {}
			local DiagnosticHeuristics = helper.load_split_heuristics({
				combat_ability_identity = CombatAbilityIdentity,
				debug_log = function(key, fixed_t, message)
					debug_logs[#debug_logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
			})
			local first_context = ctx({
				num_nearby = 3,
				peril_pct = 0.50,
				challenge_rating_sum = 6.0,
			})
			local second_context = ctx({
				num_nearby = 3,
				peril_pct = 0.50,
				challenge_rating_sum = 6.0,
			})

			first_context.talents = nil
			second_context.talents = nil

			DiagnosticHeuristics.evaluate_heuristic(T, first_context)
			DiagnosticHeuristics.evaluate_heuristic(T, second_context)

			assert.equals(1, #debug_logs)
			assert.equals("missing_talents_context:psyker", debug_logs[1].key)
			assert.matches(
				"psyker heuristic context missing talents table; build-aware checks falling back to untuned defaults",
				debug_logs[1].message,
				1,
				true
			)
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

		it("allows armor-pen builds to spend Point-Blank Barrage on hard range targets", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 8,
					challenge_rating_sum = 2.0,
					target_is_super_armor = true,
					talents = {
						ogryn_special_ammo_armor_pen = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("armor_pen_target", rule)
		end)

		it("allows armor-pen builds to spend Point-Blank Barrage on the current priority target", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy = "priority_unit",
					priority_target_enemy = "priority_unit",
					target_enemy_distance = 8,
					challenge_rating_sum = 1.0,
					talents = {
						ogryn_special_ammo_armor_pen = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("armor_pen_target", rule)
		end)

		it(
			"does not spend armor-pen Barrage on a non-priority current target just because another priority enemy exists",
			function()
				local ok, rule = evaluate(
					T,
					ctx({
						num_nearby = 1,
						target_enemy = "current_unit",
						priority_target_enemy = "other_priority_unit",
						target_enemy_distance = 8,
						challenge_rating_sum = 1.0,
						talents = {
							ogryn_special_ammo_armor_pen = true,
						},
					})
				)
				assert.is_false(ok)
				assert.matches("block_low_threat", rule)
			end
		)

		it("lets fire-shots builds trigger on medium-range crowd pressure", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 2,
					target_enemy_distance = 7,
					target_enemy_type = "melee",
					challenge_rating_sum = 2.0,
					talents = {
						ogryn_special_ammo_fire_shots = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("fire_shots_pressure", rule)
		end)

		it("relaxes the close-range block for no-movement-penalty builds", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 3.5,
					challenge_rating_sum = 3.0,
					urgent_target_enemy = "urgent",
					talents = {
						ogryn_special_ammo_movement = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("urgent_target", rule)
		end)

		it("uses toughness-regen builds as ranged sustain instead of only damage burst", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 8,
					target_enemy_type = "ranged",
					toughness_pct = 0.45,
					challenge_rating_sum = 2.0,
					talents = {
						ogryn_ranged_stance_toughness_regen = true,
					},
				})
			)
			assert.is_true(ok)
			assert.matches("toughness_regen_sustain", rule)
		end)

		it("does not use toughness-regen sustain when toughness is above the threshold", function()
			local ok, rule = evaluate(
				T,
				ctx({
					num_nearby = 1,
					target_enemy_distance = 8,
					target_enemy_type = "ranged",
					toughness_pct = 0.65,
					challenge_rating_sum = 2.0,
					talents = {
						ogryn_ranged_stance_toughness_regen = true,
					},
				})
			)
			assert.is_false(ok)
			assert.matches("hold", rule)
		end)

		it("logs once when build-aware ogryn heuristics receive a nil talents table", function()
			local debug_logs = {}
			local DiagnosticHeuristics = helper.load_split_heuristics({
				combat_ability_identity = CombatAbilityIdentity,
				debug_log = function(key, fixed_t, message)
					debug_logs[#debug_logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
			})
			local first_context = ctx({
				num_nearby = 1,
				target_enemy_distance = 8,
				challenge_rating_sum = 3.0,
				urgent_target_enemy = "urgent",
			})
			local second_context = ctx({
				num_nearby = 1,
				target_enemy_distance = 8,
				challenge_rating_sum = 3.0,
				urgent_target_enemy = "urgent",
			})

			first_context.talents = nil
			second_context.talents = nil

			DiagnosticHeuristics.evaluate_heuristic(T, first_context)
			DiagnosticHeuristics.evaluate_heuristic(T, second_context)

			assert.equals(1, #debug_logs)
			assert.equals("missing_talents_context:ogryn", debug_logs[1].key)
			assert.matches(
				"ogryn heuristic context missing talents table; build-aware checks falling back to untuned defaults",
				debug_logs[1].message,
				1,
				true
			)
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

	-- interaction protection branches (#37 Task 3)
	describe("interaction protection", function()
		local eval_item = Heuristics.evaluate_item_heuristic

		describe("ogryn_taunt", function()
			it("activates with ally interacting and 1 enemy", function()
				local ok, rule = evaluate(
					"ogryn_taunt_shout",
					ctx({
						ally_interacting = true,
						num_nearby = 1,
						toughness_pct = 0.50,
					})
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)

			it("blocks when too fragile overrides interactor protection", function()
				local ok, rule = evaluate(
					"ogryn_taunt_shout",
					ctx({
						ally_interacting = true,
						num_nearby = 2,
						toughness_pct = 0.15,
						health_pct = 0.25,
					})
				)
				assert.is_false(ok)
				assert.matches("too_fragile", rule)
			end)

			it("holds with 0 enemies despite ally interacting", function()
				local ok, rule = evaluate(
					"ogryn_taunt_shout",
					ctx({
						ally_interacting = true,
						num_nearby = 0,
						toughness_pct = 0.50,
					})
				)
				assert.is_false(ok)
				assert.matches("low_value", rule)
			end)
		end)

		describe("force_field", function()
			it("activates with ranged threats during interaction", function()
				local ok, rule = eval_item(
					"psyker_force_field",
					ctx({
						ally_interacting = true,
						ranged_count = 1,
						num_nearby = 0,
						target_enemy = "unit",
					})
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)

			it("activates with 2+ melee during interaction", function()
				local ok, rule = eval_item(
					"psyker_force_field",
					ctx({
						ally_interacting = true,
						ranged_count = 0,
						num_nearby = 2,
						target_enemy = "unit",
					})
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)
		end)

		describe("zealot_relic", function()
			it("activates with ally interacting and allies in coherency", function()
				local ok, rule = eval_item(
					"zealot_relic",
					ctx({
						ally_interacting = true,
						allies_in_coherency = 1,
						num_nearby = 1,
					})
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)
		end)

		describe("drone", function()
			it("activates at lowered threshold with ally interacting", function()
				local ok, rule = eval_item(
					"adamant_area_buff_drone",
					ctx({
						ally_interacting = true,
						num_nearby = 3,
						allies_in_coherency = 2,
					})
				)
				assert.is_true(ok)
				assert.matches("team_horde", rule)
			end)

			it("holds at 3 enemies without ally interacting", function()
				local ok, rule = eval_item(
					"adamant_area_buff_drone",
					ctx({
						ally_interacting = false,
						num_nearby = 3,
						allies_in_coherency = 2,
					})
				)
				assert.is_false(ok)
				assert.matches("hold", rule)
			end)
		end)

		describe("stimm_field", function()
			it("activates unconditionally with ally interacting", function()
				local ok, rule = eval_item(
					"broker_ability_stimm_field",
					ctx({
						ally_interacting = true,
						allies_in_coherency = 1,
					})
				)
				assert.is_true(ok)
				assert.matches("stimm_protect_interactor", rule)
			end)
		end)

		describe("adamant_shout", function()
			it("activates with 1 enemy during interaction", function()
				local ok, rule = evaluate(
					"adamant_shout",
					ctx({
						ally_interacting = true,
						num_nearby = 1,
					})
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)
		end)

		describe("veteran_voc", function()
			it("activates with 1 enemy during interaction", function()
				local ok, rule = evaluate(
					"veteran_combat_ability",
					ctx({
						ally_interacting = true,
						num_nearby = 1,
						toughness_pct = 0.90,
					}),
					{
						ability_extension = helper.make_veteran_ability_extension("squad_leader", "veteran_shout"),
						conditions = helper.make_conditions(false),
					}
				)
				assert.is_true(ok)
				assert.matches("protect_interactor", rule)
			end)
		end)

		describe("charge suppression", function()
			it("zealot_dash blocks when ally interacting within 12m", function()
				local ok, rule = evaluate(
					"zealot_dash",
					ctx({
						ally_interacting = true,
						ally_interacting_distance = 8,
						target_enemy = "enemy",
						target_enemy_distance = 10,
						target_ally_needs_aid = true,
						target_ally_distance = 10,
					})
				)
				assert.is_false(ok)
				assert.matches("block_protecting_interactor", rule)
			end)

			it("zealot_dash does not block when ally beyond 12m", function()
				local ok, rule = evaluate(
					"zealot_dash",
					ctx({
						ally_interacting = true,
						ally_interacting_distance = 15,
						target_enemy = "enemy",
						target_enemy_distance = 10,
						target_ally_needs_aid = true,
						target_ally_distance = 10,
					})
				)
				assert.is_true(ok)
				assert.matches("ally_aid", rule)
			end)

			it("zealot_dash overrides ally_aid when protecting interactor", function()
				local ok, rule = evaluate(
					"zealot_dash",
					ctx({
						ally_interacting = true,
						ally_interacting_distance = 6,
						target_enemy = "enemy",
						target_enemy_distance = 8,
						target_ally_needs_aid = true,
						target_ally_distance = 5,
					})
				)
				assert.is_false(ok)
				assert.matches("block_protecting_interactor", rule)
			end)

			it("ogryn_charge blocks when ally interacting within 12m", function()
				local ok, rule = evaluate(
					"ogryn_charge",
					ctx({
						ally_interacting = true,
						ally_interacting_distance = 8,
						target_enemy = "enemy",
						target_enemy_distance = 10,
					})
				)
				assert.is_false(ok)
				assert.matches("block_protecting_interactor", rule)
			end)

			it("adamant_charge blocks when ally interacting within 12m", function()
				local ok, rule = evaluate(
					"adamant_charge",
					ctx({
						ally_interacting = true,
						ally_interacting_distance = 8,
						target_enemy = "enemy",
						target_enemy_distance = 10,
					})
				)
				assert.is_false(ok)
				assert.matches("block_protecting_interactor", rule)
			end)
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
		before_each(function()
			helper.init_split_heuristics(Heuristics, {
				combat_ability_identity = CombatAbilityIdentity,
			})
		end)

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

		it("uses frag grenades on severe elite packs even without bleed talent", function()
			local local_ctx = helper.make_context({
				num_nearby = 3,
				elite_count = 3,
				challenge_rating_sum = 4.5,
				target_enemy_distance = 8,
				talents = {},
			})
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx)
			assert.is_true(result)
			assert.matches("pressure", rule)
		end)

		it("lets bleed lower the frag elite-pack threshold", function()
			local local_ctx = helper.make_context({
				num_nearby = 3,
				elite_count = 2,
				special_count = 1,
				challenge_rating_sum = 4.0,
				target_enemy_distance = 8,
			})
			local baseline_result, baseline_rule =
				Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx)
			assert.is_false(baseline_result)
			assert.matches("hold", baseline_rule)

			local local_ctx_bleed = helper.make_context({
				num_nearby = 3,
				elite_count = 2,
				special_count = 1,
				challenge_rating_sum = 4.0,
				target_enemy_distance = 8,
				talents = {
					veteran_grenade_apply_bleed = 1,
				},
			})
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx_bleed)
			assert.is_true(result)
			assert.matches("pressure", rule)
		end)

		it("holds frag grenades on small elite groups without enough pressure", function()
			local local_ctx = helper.make_context({
				num_nearby = 3,
				elite_count = 2,
				challenge_rating_sum = 3.5,
				target_enemy_distance = 8,
				talents = {},
			})
			local result, rule = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("revalidation hysteresis relaxes frag horde threshold by one nearby", function()
			-- Frag needs num_nearby >= 6 on the initial check. At 5 nearby
			-- the default call should hold, but once the bot has committed
			-- to an aim window the revalidation check must accept to avoid
			-- aborting an already-queued throw over a one-enemy dip.
			local baseline = helper.make_context({ num_nearby = 5, challenge_rating_sum = 3.0 })
			local baseline_result = Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", baseline)
			assert.is_false(baseline_result)

			local revalidate = helper.make_context({ num_nearby = 5, challenge_rating_sum = 3.0 })
			local relaxed_result, relaxed_rule =
				Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", revalidate, { revalidation = true })
			assert.is_true(relaxed_result)
			assert.matches("horde", relaxed_rule)
			-- The relaxation must not mutate the caller's context.
			assert.equals(5, revalidate.num_nearby)
		end)

		it("revalidation hysteresis does not rescue truly empty context", function()
			-- Threshold relaxation is one enemy, not unbounded: 0 nearby
			-- must still hold even on the revalidation path.
			local local_ctx = helper.make_context({ num_nearby = 0, challenge_rating_sum = 0 })
			local result, rule =
				Heuristics.evaluate_grenade_heuristic("veteran_frag_grenade", local_ctx, { revalidation = true })
			assert.is_false(result)
			assert.matches("hold", rule)
			assert.equals(0, local_ctx.num_nearby)
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
					target_is_super_armor = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("holds krak grenades against non-armored specials so plasma can handle them", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					target_enemy = "hound",
					target_breed_name = "chaos_hound",
					target_is_elite_special = true,
					target_is_special = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("uses krak grenades against named high-armor elites", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					target_enemy = "mauler",
					target_breed_name = "renegade_executor",
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

		it("uses standard Ogryn box on mixed elite packs outside melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_box",
				helper.make_context({
					num_nearby = 4,
					elite_count = 2,
					special_count = 1,
					challenge_rating_sum = 4.5,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
				})
			)
			assert.is_true(result)
			assert.matches("priority_pack", rule)
		end)

		it("uses Ogryn frag as a scarce nuke against monsters", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_frag",
				helper.make_context({
					target_enemy = "plague_ogryn",
					target_is_monster = true,
					monster_count = 1,
					target_enemy_distance = 10,
				})
			)
			assert.is_true(result)
			assert.matches("monster", rule)
		end)

		it("uses Ogryn frag on high-challenge mixed packs", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_frag",
				helper.make_context({
					num_nearby = 5,
					elite_count = 3,
					special_count = 1,
					challenge_rating_sum = 6.0,
					target_enemy = "crusher",
					target_is_elite_special = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_true(result)
			assert.matches("priority_pack", rule)
		end)

		it("holds Ogryn frag on ordinary horde pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_frag",
				helper.make_context({
					num_nearby = 6,
					challenge_rating_sum = 3.5,
					target_enemy = "poxwalker",
					target_enemy_distance = 8,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
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
					target_is_super_armor = true,
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

		it("uses zealot shock grenades to interrupt clustered elite pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 4,
					elite_count = 2,
					challenge_rating_sum = 4.0,
					target_enemy = "rager",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.90,
				})
			)
			assert.is_true(result)
			assert.matches("interrupt", rule)
		end)

		it("uses broker flash grenades to interrupt clustered specials without needing low toughness", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_flash_grenade",
				helper.make_context({
					num_nearby = 4,
					special_count = 2,
					challenge_rating_sum = 4.0,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
				})
			)
			assert.is_true(result)
			assert.matches("interrupt", rule)
		end)

		it("holds broker flash grenades on isolated priority targets in calm states", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_flash_grenade",
				helper.make_context({
					num_nearby = 1,
					special_count = 1,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("uses broker tox grenades on monsters at safe range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_tox_grenade",
				helper.make_context({
					target_enemy = "plague_ogryn",
					target_is_monster = true,
					monster_count = 1,
					target_enemy_distance = 10,
				})
			)
			assert.is_true(result)
			assert.matches("monster", rule)
		end)

		it("uses broker tox grenades on high-challenge mixed packs", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_tox_grenade",
				helper.make_context({
					num_nearby = 5,
					elite_count = 2,
					special_count = 1,
					challenge_rating_sum = 4.5,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 9,
				})
			)
			assert.is_true(result)
			assert.matches("priority_pack", rule)
		end)

		it(
			"fires disruption interrupt_target when priority pressure is low but the focused target is elite/special",
			function()
				-- Isolates the target-interrupt branch from interrupt_pack: priority_pressure
				-- below pack_targets, challenge_rating_sum below pack_challenge, but a
				-- focused elite/special in a ≥3 cluster at safe distance.
				local result, rule = Heuristics.evaluate_grenade_heuristic(
					"broker_flash_grenade",
					helper.make_context({
						num_nearby = 3,
						special_count = 1,
						elite_count = 0,
						challenge_rating_sum = 1.0,
						target_enemy = "trapper",
						target_is_elite_special = true,
						target_enemy_distance = 8,
						toughness_pct = 0.95,
					})
				)
				assert.is_true(result)
				assert.matches("interrupt_target", rule)
			end
		)

		it("fires disruption crowd on pure trash pressure with no priority target", function()
			-- Isolates the crowd branch: no elite/special, no focused priority
			-- target, but a crowd at or above crowd_nearby and crowd_challenge.
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_flash_grenade",
				helper.make_context({
					num_nearby = 5,
					elite_count = 0,
					special_count = 0,
					challenge_rating_sum = 2.5,
					target_enemy = "poxwalker",
					target_is_elite_special = false,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
				})
			)
			assert.is_true(result)
			assert.matches("crowd", rule)
		end)

		it("relaxes disruption pack_nearby by one while an ally is interacting", function()
			-- num_nearby = pack_nearby - 1. Without the ally relaxation the pack
			-- branch must NOT fire; the -1 offset is the only thing that flips
			-- the throw from hold to interrupt_pack.
			local baseline_ok, baseline_rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 3,
					elite_count = 2,
					special_count = 0,
					challenge_rating_sum = 3.5,
					target_enemy = "rager",
					target_is_elite_special = false,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					ally_interacting = false,
				})
			)
			assert.is_false(baseline_ok, "baseline without ally_interacting must hold")
			assert.matches("hold", baseline_rule)

			local ally_ok, ally_rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 3,
					elite_count = 2,
					special_count = 0,
					challenge_rating_sum = 3.5,
					target_enemy = "rager",
					target_is_elite_special = false,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					ally_interacting = true,
				})
			)
			assert.is_true(ally_ok, "ally_interacting must relax pack_nearby by one")
			assert.matches("interrupt_pack", ally_rule)
		end)

		it("relaxes disruption crowd_nearby by one while an ally is interacting", function()
			-- num_nearby = crowd_nearby - 1. No elite/special, no focused priority,
			-- so only the crowd branch (or the defensive fallback) can fire.
			local baseline_ok = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 4,
					elite_count = 0,
					special_count = 0,
					challenge_rating_sum = 2.5,
					target_enemy = "poxwalker",
					target_is_elite_special = false,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					ally_interacting = false,
				})
			)
			assert.is_false(baseline_ok, "baseline without ally_interacting must hold")

			local ally_ok, ally_rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 4,
					elite_count = 0,
					special_count = 0,
					challenge_rating_sum = 2.5,
					target_enemy = "poxwalker",
					target_is_elite_special = false,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					ally_interacting = true,
				})
			)
			assert.is_true(ally_ok, "ally_interacting must relax crowd_nearby by one")
			assert.matches("crowd", ally_rule)
		end)

		it("relaxes denial pack_nearby by one while an ally is interacting", function()
			-- num_nearby = pack_nearby - 1 for broker_tox (pack_nearby = 4, so num_nearby = 3).
			-- Without the relaxation the priority_pack branch fails and horde fallback
			-- (min_nearby 6) cannot fire at 3; should return false.
			local baseline_ok = Heuristics.evaluate_grenade_heuristic(
				"broker_tox_grenade",
				helper.make_context({
					num_nearby = 3,
					elite_count = 2,
					special_count = 0,
					monster_count = 0,
					challenge_rating_sum = 4.0,
					target_enemy = "shocktrooper",
					target_is_elite_special = true,
					target_is_monster = false,
					target_enemy_distance = 8,
					ally_interacting = false,
				})
			)
			assert.is_false(baseline_ok, "baseline without ally_interacting must hold")

			local ally_ok, ally_rule = Heuristics.evaluate_grenade_heuristic(
				"broker_tox_grenade",
				helper.make_context({
					num_nearby = 3,
					elite_count = 2,
					special_count = 0,
					monster_count = 0,
					challenge_rating_sum = 4.0,
					target_enemy = "shocktrooper",
					target_is_elite_special = true,
					target_is_monster = false,
					target_enemy_distance = 8,
					ally_interacting = true,
				})
			)
			assert.is_true(ally_ok, "ally_interacting must relax pack_nearby by one")
			assert.matches("priority_pack", ally_rule)
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
					target_enemy = "gunner",
					num_nearby = 3,
					ranged_count = 2,
					target_enemy_distance = 10,
				})
			)
			assert.is_true(result)
			assert.matches("ranged", rule)
		end)

		it("lets charged staffs own ranged pack pressure instead of Assail", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					current_weapon_template_name = "forcestaff_p1_m1",
					target_enemy = "rifleman",
					target_enemy_type = "ranged",
					target_enemy_distance = 10,
					num_nearby = 4,
					challenge_rating_sum = 2.5,
					ranged_count = 2,
				})
			)
			assert.is_false(result)
			assert.matches("staff_pack", rule)
		end)

		it("still uses Assail on specials while a charged staff is wielded", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					current_weapon_template_name = "forcestaff_p1_m1",
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_is_special = true,
					target_enemy_distance = 10,
					num_nearby = 4,
					challenge_rating_sum = 2.5,
					ranged_count = 2,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("lets charged staffs own ordinary elite packs instead of Assail", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					current_weapon_template_name = "forcestaff_p4_m1",
					target_enemy = "rager",
					target_is_elite = true,
					target_is_elite_special = true,
					target_enemy_distance = 10,
					num_nearby = 3,
					challenge_rating_sum = 3.0,
					elite_count = 2,
				})
			)
			assert.is_false(result)
			assert.matches("staff_pack", rule)
		end)

		it("holds Assail ranged pressure when no target unit is resolved", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					num_nearby = 3,
					ranged_count = 2,
					target_enemy_distance = 10,
				})
			)
			assert.is_false(result)
			assert.matches("hold", rule)
		end)

		it("holds Assail crowd soften when the balanced shard reserve is not met", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "poxwalker",
					target_enemy_distance = 7,
					num_nearby = 5,
					challenge_rating_sum = 2.5,
					grenade_charges_remaining = 4,
				})
			)
			assert.is_false(result)
			assert.matches("low_charges", rule)
		end)

		it("uses Assail crowd soften when the balanced shard reserve is met", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "poxwalker",
					target_enemy_distance = 7,
					num_nearby = 5,
					challenge_rating_sum = 2.5,
					grenade_charges_remaining = 5,
				})
			)
			assert.is_true(result)
			assert.matches("crowd", rule)
		end)

		it("still starts Assail crowd soften with enough shards while a charged staff is wielded", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					current_weapon_template_name = "forcestaff_p1_m1",
					target_enemy = "poxwalker",
					target_enemy_distance = 7,
					num_nearby = 5,
					challenge_rating_sum = 2.5,
					grenade_charges_remaining = 5,
				})
			)
			assert.is_true(result)
			assert.matches("crowd", rule)
		end)

		it("lets aggressive Assail crowd soften start one shard earlier than balanced", function()
			local context = helper.make_context({
				target_enemy = "poxwalker",
				target_enemy_distance = 7,
				num_nearby = 5,
				challenge_rating_sum = 2.5,
				grenade_charges_remaining = 4,
			})

			local ok_agg, rule_agg = Heuristics.evaluate_grenade_heuristic("psyker_throwing_knives", context, {
				preset = "aggressive",
			})
			local ok_bal, rule_bal = Heuristics.evaluate_grenade_heuristic("psyker_throwing_knives", context, {
				preset = "balanced",
			})

			assert.is_true(ok_agg)
			assert.matches("crowd", rule_agg)
			assert.is_false(ok_bal)
			assert.matches("low_charges", rule_bal)
		end)

		it("makes conservative Assail crowd soften require one more shard than balanced", function()
			local context = helper.make_context({
				target_enemy = "poxwalker",
				target_enemy_distance = 7,
				num_nearby = 5,
				challenge_rating_sum = 2.5,
				grenade_charges_remaining = 5,
			})

			local ok_bal, rule_bal = Heuristics.evaluate_grenade_heuristic("psyker_throwing_knives", context, {
				preset = "balanced",
			})
			local ok_con, rule_con = Heuristics.evaluate_grenade_heuristic("psyker_throwing_knives", context, {
				preset = "conservative",
			})

			assert.is_true(ok_bal)
			assert.matches("crowd", rule_bal)
			assert.is_false(ok_con)
			assert.matches("low_charges", rule_con)
		end)

		it("holds Assail crowd soften when the remaining shard count is unavailable", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "poxwalker",
					target_enemy_distance = 7,
					num_nearby = 5,
					challenge_rating_sum = 2.5,
					grenade_charges_remaining = nil,
				})
			)
			assert.is_false(result)
			assert.matches("unknown_charges", rule)
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

		it("uses Assail below the configured warp peril threshold", function()
			helper.init_split_heuristics(Heuristics, {
				combat_ability_identity = CombatAbilityIdentity,
				warp_weapon_peril_threshold = function()
					return 0.95
				end,
			})

			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_throwing_knives",
				helper.make_context({
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
					peril_pct = 0.90,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("holds Assail at or above the configured warp peril threshold", function()
			helper.init_split_heuristics(Heuristics, {
				combat_ability_identity = CombatAbilityIdentity,
				warp_weapon_peril_threshold = function()
					return 0.95
				end,
			})

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

		it("paces fire grenades after a recent confirmed throw", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_fire_grenade",
				helper.make_context({
					target_enemy = "poxwalker",
					target_enemy_distance = 10,
					num_nearby = 6,
					challenge_rating_sum = 3.0,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("paces smoke grenades after a recent confirmed throw", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_smoke_grenade",
				helper.make_context({
					target_enemy = "gunner",
					target_enemy_distance = 10,
					ranged_count = 3,
					toughness_pct = 0.35,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("lets aggressive non-explosive pacing reopen at six seconds while balanced still blocks", function()
			local context = helper.make_context({
				target_enemy = "gunner",
				target_enemy_distance = 10,
				ranged_count = 3,
				toughness_pct = 0.35,
				seconds_since_last_grenade_charge = 6.0,
			})

			local ok_agg, rule_agg = Heuristics.evaluate_grenade_heuristic("veteran_smoke_grenade", context, {
				preset = "aggressive",
			})
			local ok_bal, rule_bal = Heuristics.evaluate_grenade_heuristic("veteran_smoke_grenade", context, {
				preset = "balanced",
			})

			assert.is_true(ok_agg)
			assert.matches("pressure", rule_agg)
			assert.is_false(ok_bal)
			assert.matches("recent", rule_bal)
		end)

		it("allows fire grenades again once the pacing window expires", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_fire_grenade",
				helper.make_context({
					target_enemy = "poxwalker",
					target_enemy_distance = 10,
					num_nearby = 6,
					challenge_rating_sum = 3.0,
					seconds_since_last_grenade_charge = 9.0,
				})
			)
			assert.is_true(result)
			assert.matches("horde", rule)
		end)

		it("keeps conservative non-explosive pacing closed at nine seconds while balanced already allows", function()
			local context = helper.make_context({
				target_enemy = "poxwalker",
				target_enemy_distance = 10,
				num_nearby = 6,
				challenge_rating_sum = 3.0,
				seconds_since_last_grenade_charge = 9.0,
			})

			local ok_bal, rule_bal = Heuristics.evaluate_grenade_heuristic("zealot_fire_grenade", context, {
				preset = "balanced",
			})
			local ok_con, rule_con = Heuristics.evaluate_grenade_heuristic("zealot_fire_grenade", context, {
				preset = "conservative",
			})

			assert.is_true(ok_bal)
			assert.matches("horde", rule_bal)
			assert.is_false(ok_con)
			assert.matches("recent", rule_con)
		end)

		it("paces zealot shock grenades after a recent confirmed throw", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_shock_grenade",
				helper.make_context({
					num_nearby = 4,
					elite_count = 2,
					challenge_rating_sum = 4.0,
					target_enemy = "rager",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.90,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("paces broker flash grenades after a recent confirmed throw", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_flash_grenade",
				helper.make_context({
					num_nearby = 4,
					special_count = 2,
					challenge_rating_sum = 4.0,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("paces improved broker flash grenades after a recent confirmed throw", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"broker_flash_grenade_improved",
				helper.make_context({
					num_nearby = 4,
					special_count = 2,
					challenge_rating_sum = 4.0,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 8,
					toughness_pct = 0.95,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("paces shock mines after a recent confirmed deploy", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"adamant_shock_mine",
				helper.make_context({
					num_nearby = 5,
					challenge_rating_sum = 3.5,
					elite_count = 3,
					target_enemy = "rager",
					target_enemy_distance = 8,
					seconds_since_last_grenade_charge = 4.0,
				})
			)
			assert.is_false(result)
			assert.matches("recent", rule)
		end)

		it("keeps zealot throwing knives opted out of the melee gate", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "gunner",
					target_breed_name = "cultist_gunner",
					target_is_elite_special = true,
					target_enemy_distance = 7,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("allows zealot throwing knives against berserker specials", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					target_enemy = "netgunner",
					target_breed_name = "renegade_netgunner",
					target_is_elite_special = true,
					target_enemy_distance = 20,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("holds zealot throwing knives against super armor targets", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					target_enemy = "mauler",
					target_breed_name = "renegade_executor",
					target_is_elite_special = true,
					target_is_super_armor = true,
					target_enemy_distance = 20,
				})
			)
			assert.is_false(result)
			assert.matches("super_armor", rule)
		end)

		it("holds zealot throwing knives against monsters", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					target_enemy = "chaos_spawn",
					target_is_monster = true,
					target_enemy_distance = 20,
				})
			)
			assert.is_false(result)
			assert.matches("monster", rule)
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

		it("de-prioritizes manual Smite on ordinary elite or special targets when smite-on-hit is equipped", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					talents = { psyker_smite_on_hit = 1 },
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 12,
					peril_pct = 0.50,
				})
			)
			assert.is_false(result)
			assert.matches("proc_cover", rule)
		end)

		it("keeps manual Smite live for bombers when smite-on-hit is equipped", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					talents = { psyker_smite_on_hit = 1 },
					target_enemy = "poxburster",
					target_is_elite_special = true,
					target_is_bomber = true,
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

		it("blocks Smite under close melee pressure on non-hard targets", function()
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
			assert.is_false(result)
			assert.matches("melee_pressure", rule)
		end)

		it("still allows Smite on super-armor targets under moderate pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					num_nearby = 3,
					target_enemy = "crusher",
					target_is_super_armor = true,
					target_enemy_distance = 7,
					peril_pct = 0.50,
				})
			)
			assert.is_true(result)
			assert.matches("super_armor", rule)
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

		describe("interaction protection - grenade thresholds", function()
			local evaluate_grenade = Heuristics.evaluate_grenade_heuristic

			it("horde grenade activates at lower threshold with ally interacting", function()
				local ok, rule = evaluate_grenade(
					"veteran_frag_grenade",
					ctx({
						ally_interacting = true,
						num_nearby = 5,
						challenge_rating_sum = 2.5,
						target_enemy_distance = 8,
					})
				)
				assert.is_true(ok)
				assert.matches("horde", rule)
			end)

			it("horde grenade holds at normal threshold without ally interacting", function()
				local ok = evaluate_grenade(
					"veteran_frag_grenade",
					ctx({
						ally_interacting = false,
						num_nearby = 5,
						challenge_rating_sum = 2.5,
						target_enemy_distance = 8,
					})
				)
				assert.is_false(ok)
			end)

			it("chain_lightning activates at lower crowd with ally interacting", function()
				local ok, rule = evaluate_grenade(
					"psyker_chain_lightning",
					ctx({
						ally_interacting = true,
						num_nearby = 3,
					})
				)
				assert.is_true(ok)
				assert.matches("crowd", rule)
			end)

			it("chain_lightning holds at normal threshold without ally interacting", function()
				local ok = evaluate_grenade(
					"psyker_chain_lightning",
					ctx({
						ally_interacting = false,
						num_nearby = 3,
					})
				)
				assert.is_false(ok)
			end)

			it("defensive grenade activates at lower count with ally interacting", function()
				local ok, rule = evaluate_grenade(
					"veteran_smoke_grenade",
					ctx({
						ally_interacting = true,
						num_nearby = 3,
						toughness_pct = 0.30,
						target_enemy_distance = 8,
					})
				)
				assert.is_true(ok)
				assert.matches("pressure", rule)
			end)

			it("mine activates at lower density with ally interacting", function()
				local ok, rule = evaluate_grenade(
					"adamant_shock_mine",
					ctx({
						ally_interacting = true,
						num_nearby = 4,
						challenge_rating_sum = 3.0,
						target_enemy_distance = 8,
					})
				)
				assert.is_true(ok)
				assert.matches("hold_point", rule)
			end)

			it("single-target blitz unchanged with ally interacting", function()
				local ok_with = evaluate_grenade(
					"veteran_krak_grenade",
					ctx({
						ally_interacting = true,
						num_nearby = 1,
						target_enemy_distance = 8,
					})
				)
				local ok_without = evaluate_grenade(
					"veteran_krak_grenade",
					ctx({
						ally_interacting = false,
						num_nearby = 1,
						target_enemy_distance = 8,
					})
				)
				assert.equals(ok_with, ok_without)
			end)
		end)
	end)

	describe("build_context", function()
		local saved_managers
		local saved_position_lookup
		local saved_script_unit
		local saved_alive
		local saved_unit
		local liquid_results_return_mode
		local liquid_area_system
		local side_system
		local current_fixed_t
		local captured_liquid_results
		local script_unit_extensions
		local game_object_ids
		local game_object_fields
		local unit_alive_lookup

		before_each(function()
			liquid_results_return_mode = "table"
			liquid_area_system = nil
			side_system = nil
			current_fixed_t = 42
			captured_liquid_results = {}
			saved_managers = rawget(_G, "Managers")
			saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
			saved_script_unit = rawget(_G, "ScriptUnit")
			saved_alive = rawget(_G, "ALIVE")
			saved_unit = rawget(_G, "Unit")
			script_unit_extensions = nil
			game_object_ids = {}
			game_object_fields = {}
			unit_alive_lookup = {}

			_G.Managers = {
				state = {
					extension = {
						system = function(_, system_name)
							if system_name == "liquid_area_system" then
								return liquid_area_system
							end
							if system_name == "side_system" then
								return side_system
							end

							assert.is_true(false, "unexpected system lookup: " .. tostring(system_name))
						end,
					},
					unit_spawner = {
						game_object_id = function(_, unit)
							return game_object_ids[unit]
						end,
					},
					game_session = {
						game_session = function()
							return "test_game_session"
						end,
					},
				},
			}
			_G.GameSession = {
				game_object_field = function(game_session, game_object_id, field_name)
					assert.equals("test_game_session", game_session)
					local fields = game_object_fields[game_object_id]
					return fields and fields[field_name] or nil
				end,
			}
			_G.POSITION_LOOKUP = {
				hazard_bot = "hazard_pos",
				target_enemy = "target_pos",
				mastiff = "dog_pos",
			}
			_G.ALIVE = {
				mastiff = true,
			}
			_G.Unit = {
				alive = function(unit)
					return unit_alive_lookup[unit] == true
				end,
			}
			_G.ScriptUnit = {
				has_extension = function(unit, extension_name)
					local extensions = script_unit_extensions and script_unit_extensions[unit]
					return extensions and extensions[extension_name] or nil
				end,
			}
			liquid_area_system = helper.make_liquid_area_system_double({
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
			})
			helper.init_split_heuristics(Heuristics, {
				fixed_time = function()
					return current_fixed_t
				end,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = 6,
				is_testing_profile = function()
					return false
				end,
				combat_ability_identity = CombatAbilityIdentity,
			})
		end)

		after_each(function()
			_G.Managers = saved_managers
			_G.POSITION_LOOKUP = saved_position_lookup
			_G.ScriptUnit = saved_script_unit
			_G.ALIVE = saved_alive
			_G.Unit = saved_unit
			_G.GameSession = nil
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
			_G.ALIVE.target_enemy = true
			script_unit_extensions = {
				hazard_bot = {
					companion_spawner_system = helper.make_companion_spawner_extension({
						companion_units = { "mastiff" },
					}),
				},
				target_enemy = {
					unit_data_system = helper.make_minion_unit_data_extension({
						name = "chaos_poxwalker",
						tags = { minion = true },
					}),
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

		it("captures the live companion when ALIVE is missing but Unit.alive succeeds", function()
			_G.ALIVE.mastiff = nil
			unit_alive_lookup.mastiff = true
			script_unit_extensions = {
				hazard_bot = {
					companion_spawner_system = helper.make_companion_spawner_extension({
						companion_units = { "mastiff" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals("mastiff", context.companion_unit)
			assert.equals("dog_pos", context.companion_position)
		end)

		it("treats waking daemonhost stages as dormant even if aggro_state already flipped", function()
			_G.ALIVE.target_enemy = true
			game_object_ids.target_enemy = "daemonhost_go"
			game_object_fields.daemonhost_go = { stage = 5 }
			script_unit_extensions = {
				target_enemy = {
					unit_data_system = helper.make_minion_unit_data_extension({
						name = "chaos_daemonhost",
						tags = { monster = true },
					}),
				},
			}

			helper.init_split_heuristics(Heuristics, {
				fixed_time = function()
					return current_fixed_t
				end,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = 6,
				is_testing_profile = function()
					return false
				end,
				combat_ability_identity = CombatAbilityIdentity,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
				is_daemonhost_avoidance_enabled = function()
					return true
				end,
			})

			local context = Heuristics.build_context("hazard_bot", {
				perception = {
					target_enemy = "target_enemy",
				},
			})

			assert.is_true(context.target_is_dormant_daemonhost)
		end)

		it("counts grenadiers (no breed.ranged, game_object_type=minion_ranged) as ranged", function()
			local grenadier_breed = {
				tags = { minion = true, special = true },
				game_object_type = "minion_ranged",
				challenge_rating = 2,
			}
			script_unit_extensions = {
				hazard_bot = {
					perception_system = helper.make_bot_perception_extension({
						enemies = { "grenadier_unit" },
					}),
				},
				grenadier_unit = {
					unit_data_system = helper.make_minion_unit_data_extension(grenadier_breed),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals(1, context.ranged_count)
			assert.equals(0, context.melee_count)
		end)

		it("captures the current weapon template in context", function()
			script_unit_extensions = {
				hazard_bot = {
					unit_data_system = helper.make_player_unit_data_extension({
						weapon_action = { template_name = "forcestaff_p1_m1" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals("forcestaff_p1_m1", context.current_weapon_template_name)
		end)

		it("defaults when no allies are interacting", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot" },
					},
				},
			})

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interacting_distance)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("detects shield interactions via interacting character state", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "interacting" },
						interacting_character_state = { interaction_template = "scanning" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("scanning", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
		end)

		it("detects live ally interactions when ALIVE is missing but Unit.alive succeeds", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			unit_alive_lookup.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "interacting" },
						interacting_character_state = { interaction_template = "scanning" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("scanning", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
		end)

		it("detects shield interactions via minigame character state", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "minigame" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("minigame", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
		end)

		it("detects escort interactions via luggable slot", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "walking" },
						inventory = { wielded_slot = "slot_luggable" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("luggable", context.ally_interaction_type)
			assert.equals("ally_unit", context.ally_interacting_unit)
			assert.equals("escort", context.ally_interaction_profile)
		end)

		it("skips self when scanning ally interactions", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot" },
					},
				},
			})
			script_unit_extensions = {
				hazard_bot = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "minigame" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("ignores non-shield interaction types", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			_G.ALIVE.ally_unit = true
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "interacting" },
						interacting_character_state = { interaction_template = "ammunition" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("ignores dead allies", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					hazard_bot = {
						valid_player_units = { "hazard_bot", "ally_unit" },
					},
				},
			})
			script_unit_extensions = {
				ally_unit = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "minigame" },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.is_false(context.ally_interacting)
			assert.is_nil(context.ally_interaction_type)
			assert.is_nil(context.ally_interacting_unit)
			assert.is_nil(context.ally_interaction_profile)
		end)

		it("picks the closest interacting ally", function()
			side_system = helper.make_side_system_double({
				side_by_unit = {
					bot_unit = {
						valid_player_units = { "bot_unit", "far_ally", "close_ally" },
					},
				},
			})
			_G.ALIVE.far_ally = true
			_G.ALIVE.close_ally = true
			_G.POSITION_LOOKUP.bot_unit = { x = 0, y = 0, z = 0 }
			_G.POSITION_LOOKUP.far_ally = { x = 20, y = 0, z = 0 }
			_G.POSITION_LOOKUP.close_ally = { x = 5, y = 0, z = 0 }
			script_unit_extensions = {
				far_ally = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "minigame" },
					}),
				},
				close_ally = {
					unit_data_system = helper.make_player_unit_data_extension({
						character_state = { state_name = "minigame" },
					}),
				},
			}

			local context = Heuristics.build_context("bot_unit", nil)

			assert.is_true(context.ally_interacting)
			assert.equals("close_ally", context.ally_interacting_unit)
			assert.equals("shield", context.ally_interaction_profile)
			assert.is_true(math.abs(context.ally_interacting_distance - 5) < 0.001)
		end)

		it("exposes empty talents + zero current_stacks for vanilla bots lacking extensions", function()
			local context = Heuristics.build_context("hazard_bot", nil)

			assert.are.same({}, context.talents)
			assert.equals(0, context.current_stacks("zealot_martyrdom_base"))
			assert.equals(0, context.current_stacks("any_other_buff"))
		end)

		it("surfaces talent tiers and buff stacks when player extensions are present", function()
			script_unit_extensions = {
				hazard_bot = {
					talent_system = helper.make_player_talent_extension({
						talents = {
							zealot_martyrdom = 1,
							zealot_blazing_piety = 3,
						},
					}),
					buff_system = helper.make_player_buff_extension({
						stacks = {
							zealot_martyrdom_base = 2,
							psyker_warp_charge = 4,
						},
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals(1, context.talents["zealot_martyrdom"])
			assert.equals(3, context.talents["zealot_blazing_piety"])
			assert.is_nil(context.talents["zealot_not_taken"])
			assert.equals(2, context.current_stacks("zealot_martyrdom_base"))
			assert.equals(4, context.current_stacks("psyker_warp_charge"))
			assert.equals(0, context.current_stacks("absent_buff"))
		end)

		it("keeps current_stacks at zero when only the talent extension is present", function()
			script_unit_extensions = {
				hazard_bot = {
					talent_system = helper.make_player_talent_extension({
						talents = { zealot_martyrdom = 1 },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.equals(1, context.talents["zealot_martyrdom"])
			assert.equals(0, context.current_stacks("zealot_martyrdom_base"))
		end)

		it("keeps talents empty when only the buff extension is present", function()
			script_unit_extensions = {
				hazard_bot = {
					buff_system = helper.make_player_buff_extension({
						stacks = { psyker_warp_charge = 5 },
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.are.same({}, context.talents)
			assert.equals(5, context.current_stacks("psyker_warp_charge"))
		end)

		it("falls back to empty talents when the talent extension returns nil", function()
			script_unit_extensions = {
				hazard_bot = {
					talent_system = helper.make_player_talent_extension({
						talents = nil,
					}),
				},
			}

			local context = Heuristics.build_context("hazard_bot", nil)

			assert.are.same({}, context.talents)
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

	-- Issue #17: Dormant daemonhost must not be treated as a priority target.
	-- The bot's target_enemy can be a dormant daemonhost (vanilla target
	-- selection quirk); in that case every monster-aware heuristic must
	-- refuse to fire. Once the daemonhost aggroes on the bot, normal
	-- self-defense behavior resumes (ctx.target_is_dormant_daemonhost=false).
	describe("dormant daemonhost carve-out (#17)", function()
		-- Every template that uses the _grenade_priority_target dispatch or
		-- the _grenade_assail monster fast-path. Each must refuse the decision
		-- when target_is_dormant_daemonhost is true. Most resume normal
		-- self-defense when the DH has aggroed on this bot (flag=false);
		-- Zealot knives still hold because their own policy blocks monsters.
		describe("priority-target grenades/blitzes", function()
			local priority_grenades = {
				{ template = "psyker_smite", distance = 12, peril_pct = 0.30 },
				{ template = "psyker_throwing_knives", distance = 10, peril_pct = 0.30 },
				{ template = "veteran_krak_grenade", distance = 10 },
				{ template = "zealot_throwing_knives", distance = 10, blocks_aggroed_monster = true },
				{ template = "ogryn_grenade_friend_rock", distance = 12 },
				{ template = "broker_missile_launcher", distance = 14 },
			}

			for _, grenade in ipairs(priority_grenades) do
				it("refuses " .. grenade.template .. " against dormant daemonhost", function()
					local result, rule = Heuristics.evaluate_grenade_heuristic(
						grenade.template,
						helper.make_context({
							target_enemy = "daemonhost_unit",
							target_is_monster = true,
							target_is_dormant_daemonhost = true,
							target_enemy_distance = grenade.distance,
							peril_pct = grenade.peril_pct,
						})
					)
					assert.is_false(result)
					assert.matches("daemonhost", rule)
				end)

				it("approves " .. grenade.template .. " when daemonhost aggroed on bot", function()
					-- target_is_dormant_daemonhost=false means DH is either
					-- not a DH, or it is aggroed on this specific bot. Either
					-- way, self-defense behavior must still fire.
					local result, rule = Heuristics.evaluate_grenade_heuristic(
						grenade.template,
						helper.make_context({
							target_enemy = "daemonhost_unit",
							target_is_monster = true,
							target_is_dormant_daemonhost = false,
							target_enemy_distance = grenade.distance,
							peril_pct = grenade.peril_pct,
						})
					)
					if grenade.blocks_aggroed_monster then
						assert.is_false(result)
						assert.matches("monster", rule)
						return
					end
					assert.is_true(result)
					if grenade.template == "psyker_smite" then
						assert.matches("monster", rule)
					else
						assert.matches("priority", rule)
					end
				end)
			end
		end)

		describe("adamant_stance monster_pressure", function()
			it("refuses monster_pressure clause against dormant daemonhost", function()
				local ok, rule = evaluate(
					"adamant_stance",
					ctx({
						target_is_monster = true,
						target_is_dormant_daemonhost = true,
						target_enemy_distance = 5,
						toughness_pct = 0.80,
						num_nearby = 0,
					})
				)
				assert.is_false(ok)
				assert.is_not.matches("monster_pressure", rule or "")
			end)

			it("keeps monster_pressure clause against aggroed daemonhost", function()
				local ok, rule = evaluate(
					"adamant_stance",
					ctx({
						target_is_monster = true,
						target_is_dormant_daemonhost = false,
						target_enemy_distance = 5,
						toughness_pct = 0.80,
						num_nearby = 0,
					})
				)
				assert.is_true(ok)
				assert.matches("monster_pressure", rule)
			end)
		end)

		describe("adamant_area_buff_drone monster_fight", function()
			local eval_item = Heuristics.evaluate_item_heuristic

			it("refuses drone monster_fight against dormant daemonhost", function()
				local ok, rule = eval_item(
					"adamant_area_buff_drone",
					ctx({
						num_nearby = 1,
						allies_in_coherency = 1,
						target_is_monster = true,
						target_is_dormant_daemonhost = true,
					})
				)
				assert.is_false(ok)
				assert.is_not.matches("monster", rule or "")
			end)

			it("keeps drone monster_fight against aggroed daemonhost", function()
				local ok, rule = eval_item(
					"adamant_area_buff_drone",
					ctx({
						num_nearby = 1,
						allies_in_coherency = 1,
						target_is_monster = true,
						target_is_dormant_daemonhost = false,
					})
				)
				assert.is_true(ok)
				assert.matches("monster", rule)
			end)
		end)

		describe("daemonhost_avoidance setting toggle", function()
			after_each(function()
				-- Restore default (avoidance enabled) for the rest of the suite.
				helper.init_split_heuristics(Heuristics, {
					combat_ability_identity = CombatAbilityIdentity,
				})
			end)

			it("does not block dormant DH when avoidance is disabled", function()
				helper.init_split_heuristics(Heuristics, {
					combat_ability_identity = CombatAbilityIdentity,
					is_daemonhost_avoidance_enabled = function()
						return false
					end,
				})

				local result, rule = Heuristics.evaluate_grenade_heuristic(
					"psyker_smite",
					helper.make_context({
						target_enemy = "daemonhost_unit",
						target_is_monster = true,
						target_is_dormant_daemonhost = true,
						target_enemy_distance = 12,
						peril_pct = 0.30,
					})
				)
				assert.is_true(result)
				assert.matches("monster", rule)
			end)
		end)
	end)
end)
