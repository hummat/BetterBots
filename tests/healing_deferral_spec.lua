local HealingDeferral = dofile("scripts/mods/BetterBots/healing_deferral.lua")

describe("healing_deferral", function()
	describe("resolve_settings", function()
		it("returns defaults when settings are absent", function()
			HealingDeferral.init({
				mod = {
					get = function()
						return nil
					end,
				},
			})

			local settings = HealingDeferral.resolve_settings()

			assert.are.equal("stations_and_deployables", settings.mode)
			assert.are.equal(0.9, settings.human_threshold)
			assert.are.equal(0.25, settings.emergency_threshold)
		end)

		it("supports strict no-override mode", function()
			HealingDeferral.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "healing_deferral_mode" then
							return "stations_only"
						end
						if setting_id == "healing_deferral_human_threshold" then
							return "100"
						end
						if setting_id == "healing_deferral_emergency_threshold" then
							return "never"
						end
					end,
				},
			})

			local settings = HealingDeferral.resolve_settings()

			assert.are.equal("stations_only", settings.mode)
			assert.are.equal(1.0, settings.human_threshold)
			assert.are.equal(0, settings.emergency_threshold)
		end)

		it("supports disabling the feature entirely", function()
			HealingDeferral.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "healing_deferral_mode" then
							return "off"
						end
					end,
				},
			})

			local settings = HealingDeferral.resolve_settings()

			assert.are.equal("off", settings.mode)
			assert.are.equal(0.9, settings.human_threshold)
			assert.are.equal(0.25, settings.emergency_threshold)
		end)

		it("falls back to defaults for invalid values", function()
			HealingDeferral.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "healing_deferral_mode" then
							return "bad"
						end
						if setting_id == "healing_deferral_human_threshold" then
							return "wat"
						end
						if setting_id == "healing_deferral_emergency_threshold" then
							return "oops"
						end
					end,
				},
			})

			local settings = HealingDeferral.resolve_settings()

			assert.are.equal("stations_and_deployables", settings.mode)
			assert.are.equal(0.9, settings.human_threshold)
			assert.are.equal(0.25, settings.emergency_threshold)
		end)
	end)

	describe("any_human_needs_healing", function()
		local function health_pct(unit)
			return unit.health_pct
		end

		it("returns true when a human is below threshold", function()
			local humans = {
				{ health_pct = 0.7 },
			}

			assert.is_true(HealingDeferral.any_human_needs_healing(humans, 0.9, health_pct))
		end)

		it("returns false when all humans are above threshold", function()
			local humans = {
				{ health_pct = 0.95 },
			}

			assert.is_false(HealingDeferral.any_human_needs_healing(humans, 0.9, health_pct))
		end)

		it("returns false with no humans", function()
			assert.is_false(HealingDeferral.any_human_needs_healing({}, 0.9, health_pct))
		end)
	end)

	describe("should_defer_healing", function()
		it("defers when a human needs healing and the bot is healthy", function()
			assert.is_true(HealingDeferral.should_defer_healing(0.6, true, 0.25))
		end)

		it("does not defer when the bot is critically low", function()
			assert.is_false(HealingDeferral.should_defer_healing(0.2, true, 0.25))
		end)

		it("does not defer when humans are healthy", function()
			assert.is_false(HealingDeferral.should_defer_healing(0.6, false, 0.25))
		end)

		it("supports strict deferral with no emergency override", function()
			assert.is_true(HealingDeferral.should_defer_healing(0.01, true, 0))
		end)
	end)

	describe("should_defer_resource", function()
		it("does not defer when the mode is off", function()
			local settings = {
				mode = "off",
				emergency_threshold = 0.25,
			}

			assert.is_false(HealingDeferral.should_defer_resource("health_station", 0.8, true, settings))
		end)

		it("defers health stations in station-only mode", function()
			local settings = {
				mode = "stations_only",
				emergency_threshold = 0.25,
			}

			assert.is_true(HealingDeferral.should_defer_resource("health_station", 0.8, true, settings))
		end)

		it("does not defer deployables in station-only mode", function()
			local settings = {
				mode = "stations_only",
				emergency_threshold = 0.25,
			}

			assert.is_false(HealingDeferral.should_defer_resource("health_deployable", 0.8, true, settings))
		end)

		it("defers deployables in the default mode", function()
			local settings = {
				mode = "stations_and_deployables",
				emergency_threshold = 0.25,
			}

			assert.is_true(HealingDeferral.should_defer_resource("health_deployable", 0.8, true, settings))
		end)
	end)

	describe("apply deferral", function()
		it("clears health station demand", function()
			local component = {
				needs_health = true,
				needs_health_queue_number = 3,
			}

			HealingDeferral.apply_health_station_deferral(component)

			assert.is_false(component.needs_health)
			assert.are.equal(0, component.needs_health_queue_number)
		end)

		it("clears med-crate assignment", function()
			local pickup_component = {
				health_deployable = {},
				health_deployable_distance = 12,
				health_deployable_valid_until = 99,
			}

			HealingDeferral.apply_health_deployable_deferral(pickup_component)

			assert.is_nil(pickup_component.health_deployable)
			assert.are.equal(math.huge, pickup_component.health_deployable_distance)
			assert.are.equal(-math.huge, pickup_component.health_deployable_valid_until)
		end)
	end)
end)
