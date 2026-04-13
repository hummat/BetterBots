local Hysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")

describe("target_type_hysteresis", function()
	it("uses raw winner when current type is none", function()
		local chosen = Hysteresis.choose_target_type("none", 12, 8)
		assert.equals("melee", chosen)
	end)

	it("keeps current melee type on close scores", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.4)
		assert.equals("melee", chosen)
	end)

	it("keeps current ranged type on close scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 10.4, 10)
		assert.equals("ranged", chosen)
	end)

	it("flips when the opposite type wins by more than the margin", function()
		local chosen = Hysteresis.choose_target_type("ranged", 14, 10)
		assert.equals("melee", chosen)
	end)

	it("applies momentum bonus to the current type", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.49)
		assert.equals("melee", chosen)
	end)

	it("scales margin with larger scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 100, 108)
		assert.equals("ranged", chosen)
	end)

	it("reports when hysteresis suppresses a raw flip", function()
		local analysis = Hysteresis.analyze_target_type_choice("melee", 10, 10.4)

		assert.equals("ranged", analysis.raw_target_enemy_type)
		assert.equals("melee", analysis.chosen_type)
		assert.is_true(analysis.suppressed_raw_flip)
	end)

	it("does not report a suppressed raw flip when the winner clears the margin", function()
		local analysis = Hysteresis.analyze_target_type_choice("ranged", 14, 10)

		assert.equals("melee", analysis.raw_target_enemy_type)
		assert.equals("melee", analysis.chosen_type)
		assert.is_false(analysis.suppressed_raw_flip)
	end)
end)
