local function load_smart_targeting()
	local ok, smart_targeting = pcall(dofile, "scripts/mods/BetterBots/smart_targeting.lua")
	assert.is_true(ok, "smart_targeting.lua should load")
	return smart_targeting
end

describe("smart_targeting", function()
	it("prefers the bot perception target enemy", function()
		local SmartTargeting = load_smart_targeting()
		local target = SmartTargeting.resolve_bot_target_unit({
			target_enemy = "enemy_1",
			priority_target_enemy = "enemy_2",
		})

		assert.equals("enemy_1", target)
	end)

	it("returns nil when the bot has no current perception target", function()
		local SmartTargeting = load_smart_targeting()
		assert.is_nil(SmartTargeting.resolve_bot_target_unit({}))
	end)
end)
