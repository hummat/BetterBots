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

	it("treats rescue and panic style rules as jitter bypass", function()
		HumanLikeness.init({})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("ogryn_charge_ally_aid"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("zealot_relic_panic"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_hazard"))
		assert.is_false(HumanLikeness.should_bypass_ability_jitter("veteran_shout_mixed_pack"))
	end)

	it("shrinks leash only when challenge pressure rises", function()
		HumanLikeness.init({})

		assert.equals(20, HumanLikeness.scale_engage_leash(20, 0))
		assert.is_true(HumanLikeness.scale_engage_leash(20, 20) < 20)
		assert.equals(10, HumanLikeness.scale_engage_leash(20, 30))
	end)
end)
