local saved_script_unit = rawget(_G, "ScriptUnit")
local BotTargeting = dofile("scripts/mods/BetterBots/bot_targeting.lua")

describe("bot_targeting", function()
	after_each(function()
		_G.ScriptUnit = saved_script_unit
	end)

	it("resolves target_enemy before lower-priority slots", function()
		local target = BotTargeting.resolve_bot_target_unit({
			urgent_target_enemy = "urgent",
			opportunity_target_enemy = "opportunity",
			priority_target_enemy = "priority",
			target_enemy = "target",
		})

		assert.equals("target", target)
	end)

	it("detects elite/special/monster tags", function()
		_G.ScriptUnit = {
			has_extension = function()
				return {
					breed = function()
						return {
							tags = { elite = true },
						}
					end,
				}
			end,
		}

		assert.is_true(BotTargeting.is_elite_special_monster("unit"))
	end)

	it("falls back to tostring(unit) when breed name is unavailable", function()
		_G.ScriptUnit = {
			has_extension = function()
				return nil
			end,
		}

		assert.equals("unit_1", BotTargeting.target_name("unit_1"))
	end)
end)
