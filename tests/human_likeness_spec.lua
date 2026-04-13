local HumanLikeness = dofile("scripts/mods/BetterBots/human_likeness.lua")

describe("human_likeness", function()
	it("patches opportunity target reaction times from the medium timing profile", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = true,
					reaction_min = 2,
					reaction_max = 4,
					defensive_jitter_min_s = 0.10,
					defensive_jitter_max_s = 0.25,
					opportunistic_jitter_min_s = 0.25,
					opportunistic_jitter_max_s = 0.70,
				}
			end,
			get_pressure_leash_config = function()
				return { enabled = false }
			end,
		})
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(2, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(4, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("leaves reaction times unchanged when the timing profile is off", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = false,
					reaction_min = 10,
					reaction_max = 20,
					defensive_jitter_min_s = 0,
					defensive_jitter_max_s = 0,
					opportunistic_jitter_min_s = 0,
					opportunistic_jitter_max_s = 0,
				}
			end,
			get_pressure_leash_config = function()
				return { enabled = false }
			end,
		})
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(10, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(20, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("restores original reaction times when toggled off after patching", function()
		local enabled = true
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			get_timing_config = function()
				if enabled then
					return {
						enabled = true,
						reaction_min = 2,
						reaction_max = 4,
						defensive_jitter_min_s = 0.10,
						defensive_jitter_max_s = 0.25,
						opportunistic_jitter_min_s = 0.25,
						opportunistic_jitter_max_s = 0.70,
					}
				end

				return {
					enabled = false,
					reaction_min = 10,
					reaction_max = 20,
					defensive_jitter_min_s = 0,
					defensive_jitter_max_s = 0,
					opportunistic_jitter_min_s = 0,
					opportunistic_jitter_max_s = 0,
				}
			end,
			get_pressure_leash_config = function()
				return { enabled = false }
			end,
		})
		HumanLikeness.patch_bot_settings(BotSettings)

		enabled = false
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(10, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(20, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("classifies emergency rules as immediate timing", function()
		HumanLikeness.init({})

		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("zealot_stealth_emergency"))
		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("ogryn_charge_escape"))
		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("psyker_shout_high_peril"))
	end)

	it("classifies survival pressure rules as defensive timing", function()
		HumanLikeness.init({})

		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("veteran_voc_critical_toughness"))
		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("drone_overwhelmed"))
		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("force_field_pressure"))
	end)

	it("classifies target-selection rules as opportunistic timing", function()
		HumanLikeness.init({})

		assert.equals("opportunistic", HumanLikeness.jitter_bucket_for_rule("ogryn_charge_priority_target"))
		assert.equals("opportunistic", HumanLikeness.jitter_bucket_for_rule("adamant_charge_density"))
	end)

	it("returns defensive jitter from the timing config", function()
		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = true,
					reaction_min = 2,
					reaction_max = 4,
					defensive_jitter_min_s = 0.10,
					defensive_jitter_max_s = 0.25,
					opportunistic_jitter_min_s = 0.25,
					opportunistic_jitter_max_s = 0.70,
				}
			end,
		})

		local delay = HumanLikeness.random_ability_jitter_delay("veteran_voc_critical_toughness")
		assert.is_true(delay >= 0.10)
		assert.is_true(delay <= 0.25)
	end)

	it("bypasses non-emergency jitter and leash scaling when both profiles are off", function()
		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = false,
					reaction_min = 10,
					reaction_max = 20,
					defensive_jitter_min_s = 0,
					defensive_jitter_max_s = 0,
					opportunistic_jitter_min_s = 0,
					opportunistic_jitter_max_s = 0,
				}
			end,
			get_pressure_leash_config = function()
				return {
					enabled = false,
					start_rating = 12,
					full_rating = 30,
					scale_multiplier = 0.65,
					floor_m = 7,
				}
			end,
		})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_mixed_pack"))
		assert.equals(20, HumanLikeness.scale_engage_leash(20, 30))
	end)

	it("uses the pressure leash profile to scale engage range", function()
		HumanLikeness.init({
			get_pressure_leash_config = function()
				return {
					enabled = true,
					start_rating = 12,
					full_rating = 30,
					scale_multiplier = 0.65,
					floor_m = 7,
				}
			end,
		})

		assert.equals(20, HumanLikeness.scale_engage_leash(20, 0))
		assert.is_true(HumanLikeness.scale_engage_leash(20, 20) < 20)
		assert.equals(13, HumanLikeness.scale_engage_leash(20, 30))
	end)
end)
