local HumanLikeness = dofile("scripts/mods/BetterBots/human_likeness.lua")

describe("human_likeness", function()
	it("patches opportunity target reaction times to 2-5", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({})
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(2, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(5, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("leaves opportunity target reaction times unchanged when disabled", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			is_enabled = function()
				return false
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
			is_enabled = function()
				return enabled
			end,
		})
		HumanLikeness.patch_bot_settings(BotSettings)

		enabled = false
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(10, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(20, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("treats rescue and panic style rules as jitter bypass", function()
		HumanLikeness.init({})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("ogryn_charge_ally_aid"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("zealot_relic_panic"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_hazard"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("ogryn_taunt_last_stand"))
		assert.is_false(HumanLikeness.should_bypass_ability_jitter("veteran_shout_mixed_pack"))
	end)

	it("treats emergency escape rules as jitter bypass", function()
		HumanLikeness.init({})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("zealot_stealth_emergency"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_high_peril"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("ogryn_charge_escape"))
	end)

	it("shrinks leash only when challenge pressure rises", function()
		HumanLikeness.init({})

		assert.equals(20, HumanLikeness.scale_engage_leash(20, 0))
		assert.is_true(HumanLikeness.scale_engage_leash(20, 20) < 20)
		assert.equals(10, HumanLikeness.scale_engage_leash(20, 30))
	end)

	it("clamps leash to MIN_LEASH_FLOOR when base leash is small", function()
		HumanLikeness.init({})

		-- At max pressure (30), leash = max(6, 10*0.5) = 6 (floor wins)
		assert.equals(6, HumanLikeness.scale_engage_leash(10, 30))
		-- At max pressure (30), leash = max(6, 8*0.5) = 6 (floor wins over 4)
		assert.equals(6, HumanLikeness.scale_engage_leash(8, 30))
	end)

	it("bypasses jitter and leash scaling when disabled", function()
		HumanLikeness.init({
			is_enabled = function()
				return false
			end,
		})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_mixed_pack"))
		assert.equals(20, HumanLikeness.scale_engage_leash(20, 30))
	end)
end)
