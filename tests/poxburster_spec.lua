local Poxburster = dofile("scripts/mods/BetterBots/poxburster.lua")

local function distance(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z

	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

describe("poxburster", function()
	describe("should_suppress_poxburster_positions", function()
		it("suppresses when the poxburster is near a human player", function()
			local should_suppress, reason = Poxburster.should_suppress_poxburster_positions(
				{ x = 20, y = 0, z = 0 },
				{ x = 0, y = 0, z = 0 },
				{
					{ x = 18, y = 0, z = 0 },
				},
				5,
				8,
				distance
			)

			assert.is_true(should_suppress)
			assert.are.equal("near_human_player", reason)
		end)

		it("does not suppress when bot and humans are both safely far", function()
			local should_suppress, reason = Poxburster.should_suppress_poxburster_positions(
				{ x = 20, y = 0, z = 0 },
				{ x = 0, y = 0, z = 0 },
				{
					{ x = 40, y = 0, z = 0 },
				},
				5,
				8,
				distance
			)

			assert.is_false(should_suppress)
			assert.is_nil(reason)
		end)

		it("still suppresses when the poxburster is too close to the bot", function()
			local should_suppress, reason = Poxburster.should_suppress_poxburster_positions(
				{ x = 3, y = 0, z = 0 },
				{ x = 0, y = 0, z = 0 },
				{
					{ x = 20, y = 0, z = 0 },
				},
				5,
				8,
				distance
			)

			assert.is_true(should_suppress)
			assert.are.equal("too_close_to_bot", reason)
		end)
	end)
end)
