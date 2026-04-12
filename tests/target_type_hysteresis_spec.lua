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
end)
