-- tests/team_cooldown_spec.lua

describe("team_cooldown", function()
	local TeamCooldown

	before_each(function()
		package.loaded["scripts/mods/BetterBots/team_cooldown"] = nil
		TeamCooldown = require("scripts/mods/BetterBots/team_cooldown")
		TeamCooldown.reset()
	end)

	local unit_a = { _test_id = "bot_a" }
	local unit_b = { _test_id = "bot_b" }
	local unit_c = { _test_id = "bot_c" }

	describe("record + is_suppressed", function()
		it("never suppresses the bot that recorded the activation", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed, reason = TeamCooldown.is_suppressed(unit_a, "ogryn_taunt_shout", 10.5)
			assert.is_false(suppressed)
			assert.is_nil(reason)
		end)

		it("suppresses a different bot in the same category within the window", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed, reason = TeamCooldown.is_suppressed(unit_b, "adamant_shout", 12)
			assert.is_true(suppressed)
			assert.is_string(reason)
			assert.truthy(string.find(reason, "taunt"))
		end)

		it("does not suppress a different bot in a different category", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_dash", 10.5)
			assert.is_false(suppressed)
		end)

		it("lifts suppression after the window expires", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			-- taunt window is 8s
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 18.1)
			assert.is_false(suppressed)
		end)

		it("suppresses just before the window expires", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 17.9)
			assert.is_true(suppressed)
		end)

		it("overwrites previous activation with newer one", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			TeamCooldown.record(unit_b, "psyker_shout", 14)
			-- unit_a should now be suppressed by unit_b's later activation
			local suppressed = TeamCooldown.is_suppressed(unit_a, "psyker_shout", 15)
			assert.is_true(suppressed)
			-- unit_b should NOT be suppressed (it's the recorder)
			local suppressed_b = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 15)
			assert.is_false(suppressed_b)
		end)
	end)

	describe("unknown templates", function()
		it("passes through unsuppressed for templates not in the category map", function()
			TeamCooldown.record(unit_a, "some_unknown_template", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "some_unknown_template", 10.5)
			assert.is_false(suppressed)
		end)

		it("passes through unsuppressed for stance templates", function()
			TeamCooldown.record(unit_a, "psyker_overcharge_stance", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "psyker_overcharge_stance", 10.5)
			assert.is_false(suppressed)
		end)
	end)

	describe("emergency overrides", function()
		it("bypasses suppression for psyker_shout_high_peril", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 11, "psyker_shout_high_peril")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for zealot_stealth_emergency", function()
			-- zealot_invisibility is not in CATEGORY_MAP (stance), so this tests
			-- that emergency check runs before category lookup
			TeamCooldown.record(unit_a, "zealot_dash", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_dash", 11, "zealot_stealth_emergency")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for ogryn_charge_escape", function()
			TeamCooldown.record(unit_a, "ogryn_charge", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_charge", 11, "ogryn_charge_escape")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for any rule containing _rescue", function()
			TeamCooldown.record(unit_a, "zealot_dash", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_dash", 11, "zealot_dash_rescue")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for adamant_charge_rescue", function()
			TeamCooldown.record(unit_a, "adamant_charge", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "adamant_charge", 11, "adamant_charge_rescue")
			assert.is_false(suppressed)
		end)

		it("does NOT bypass for non-emergency rules", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 11, "psyker_shout_surrounded")
			assert.is_true(suppressed)
		end)
	end)

	describe("suppression windows per category", function()
		it("taunt window is 8s", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 17.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 18.1))
		end)

		it("aoe_shout window is 6s", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "psyker_shout", 15.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "psyker_shout", 16.1))
		end)

		it("dash window is 4s", function()
			TeamCooldown.record(unit_a, "zealot_dash", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "zealot_dash", 13.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "zealot_dash", 14.1))
		end)
	end)

	describe("reset", function()
		it("clears all state", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			TeamCooldown.reset()
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 10.5)
			assert.is_false(suppressed)
		end)
	end)

	describe("three bots", function()
		it("third bot is suppressed by second bot after first window expires", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			TeamCooldown.record(unit_b, "psyker_shout", 17) -- after unit_a's window (6s)
			-- unit_c within unit_b's window
			local suppressed = TeamCooldown.is_suppressed(unit_c, "psyker_shout", 20)
			assert.is_true(suppressed)
			-- unit_a is also suppressed by unit_b
			local suppressed_a = TeamCooldown.is_suppressed(unit_a, "psyker_shout", 20)
			assert.is_true(suppressed_a)
		end)
	end)
end)
