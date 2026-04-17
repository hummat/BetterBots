local GestaltInjector = dofile("scripts/mods/BetterBots/gestalt_injector.lua")

describe("gestalt_injector", function()
	before_each(function()
		GestaltInjector.init({
			default_ranged_gestalt = "killshot",
			default_melee_gestalt = "linesman",
			injected_units = {},
		})
	end)

	it("injects defaults when gestalts are nil", function()
		local out, injected = GestaltInjector.inject(nil, "unit_a")

		assert.equals("killshot", out.ranged)
		assert.equals("linesman", out.melee)
		assert.is_true(injected)
	end)

	it("preserves an existing ranged gestalt", function()
		local out, injected = GestaltInjector.inject({ ranged = "custom" }, "unit_b")

		assert.equals("custom", out.ranged)
		assert.is_false(injected)
	end)

	it("fills nothing when only ranged is present", function()
		local out, injected = GestaltInjector.inject({ ranged = "killshot" }, "unit_c")

		assert.equals("killshot", out.ranged)
		assert.is_nil(out.melee)
		assert.is_false(injected)
	end)

	it("deduplicates first-time injection tracking per unit", function()
		local _, first = GestaltInjector.inject(nil, "unit_d")
		local _, second = GestaltInjector.inject(nil, "unit_d")

		assert.is_true(first)
		assert.is_false(second)
	end)
end)
