local HealingDeferral = dofile("scripts/mods/BetterBots/healing_deferral.lua")

describe("healing_deferral", function()
	describe("init", function()
		it("loads Health via require when no explicit dependency is passed", function()
			local saved_preload = package.preload["scripts/utilities/health"]
			local saved_loaded = package.loaded["scripts/utilities/health"]

			package.loaded["scripts/utilities/health"] = nil
			package.preload["scripts/utilities/health"] = function()
				return {
					current_health_percent = function(unit)
						return unit.health_pct
					end,
				}
			end

			HealingDeferral.init({
				mod = {
					get = function()
						return nil
					end,
				},
				fixed_time = function()
					return 0
				end,
			})

			assert.is_true(HealingDeferral.any_human_needs_healing({
				{ health_pct = 0.7 },
			}, 0.9))

			package.preload["scripts/utilities/health"] = saved_preload
			package.loaded["scripts/utilities/health"] = saved_loaded
		end)
	end)

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
							return 100
						end
						if setting_id == "healing_deferral_emergency_threshold" then
							return 0
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

		it("caches settings within the same fixed frame and refreshes on the next frame", function()
			local current_t = 10
			local get_calls = 0

			HealingDeferral.init({
				mod = {
					get = function(_, setting_id)
						get_calls = get_calls + 1
						if setting_id == "healing_deferral_mode" then
							return "stations_only"
						end
						if setting_id == "healing_deferral_human_threshold" then
							return 75
						end
						if setting_id == "healing_deferral_emergency_threshold" then
							return 10
						end
					end,
				},
				fixed_time = function()
					return current_t
				end,
			})

			local settings_a = HealingDeferral.resolve_settings()
			local settings_b = HealingDeferral.resolve_settings()

			assert.are.equal(3, get_calls)
			assert.are.equal(settings_a, settings_b)

			current_t = 11
			local settings_c = HealingDeferral.resolve_settings()

			assert.are.equal(6, get_calls)
			assert.are_not.equal(settings_a, settings_c)
			assert.are.equal("stations_only", settings_c.mode)
			assert.are.equal(0.75, settings_c.human_threshold)
			assert.are.equal(0.10, settings_c.emergency_threshold)
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

		it("treats a recent health request as human need even when everyone is healthy", function()
			local humans = {
				{ health_pct = 0.95 },
			}

			assert.is_true(HealingDeferral.any_human_needs_healing(humans, 0.9, health_pct, function()
				return true
			end))
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

		it("keeps Martyrdom bots off health stations even when no human needs healing", function()
			local settings = {
				mode = "stations_and_deployables",
				emergency_threshold = 0.25,
			}

			assert.is_true(HealingDeferral.should_defer_resource("health_station", 0.05, false, settings, true))
		end)

		it("keeps Martyrdom bots off deployables even when critically low", function()
			local settings = {
				mode = "stations_and_deployables",
				emergency_threshold = 0.25,
			}

			assert.is_true(HealingDeferral.should_defer_resource("health_deployable", 0.05, true, settings, true))
		end)
	end)

	describe("should_skip_health_station_use", function()
		it("does not skip medicae for corruption-only damage", function()
			assert.is_false(HealingDeferral.should_skip_health_station_use(0.7, 0.3, 0.3, 4, true))
		end)

		it("does not skip medicae for slight missing health", function()
			assert.is_false(HealingDeferral.should_skip_health_station_use(0.85, 0.15, 0, 4, true))
		end)

		it("does not reserve the last charge once human reserve is satisfied", function()
			assert.is_false(HealingDeferral.should_skip_health_station_use(0.5, 0.5, 0.1, 1, true))
		end)

		it("allows medicae when health is missing and spare charges remain", function()
			assert.is_false(HealingDeferral.should_skip_health_station_use(0.5, 0.5, 0.1, 2, true))
		end)

		it("skips medicae only when the bot is already full", function()
			assert.is_true(HealingDeferral.should_skip_health_station_use(1.0, 0, 0, 4, true))
		end)
	end)

	describe("install_behavior_ext_hooks", function()
		local update_health_stations_hook
		local saved_script_unit

		local function install_hook_fixture(opts)
			local station_unit = {}

			saved_script_unit = rawget(_G, "ScriptUnit")
			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit == station_unit and system_name == "health_station_system" then
						return {
							charge_amount = function()
								return opts.charge_amount
							end,
						}
					end

					return nil
				end,
			}

			HealingDeferral.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "healing_deferral_mode" then
							return "stations_and_deployables"
						end
						if setting_id == "healing_deferral_human_threshold" then
							return opts.human_threshold or 90
						end
						if setting_id == "healing_deferral_emergency_threshold" then
							return 25
						end
					end,
					hook_safe = function(_, _, method_name, fn)
						if method_name == "_update_health_stations" then
							update_health_stations_hook = fn
						end
					end,
				},
				health_module = {
					current_health_percent = function(unit)
						if opts.bot_health_by_unit and opts.bot_health_by_unit[unit] then
							return opts.bot_health_by_unit[unit]
						end
						if unit == "bot1" then
							return opts.bot_health_pct
						end

						return opts.human_health_pct
					end,
					permanent_damage_taken_percent = function(unit)
						if unit == "bot1" then
							return opts.bot_permanent_damage_pct or 0
						end

						return 0
					end,
				},
				fixed_time = function()
					return 0
				end,
			})

			HealingDeferral.install_behavior_ext_hooks({})

			return station_unit
		end

		after_each(function()
			_G.ScriptUnit = saved_script_unit
		end)

		it("promotes slight bot damage into health-station demand when humans are above reserve", function()
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.95,
				human_health_pct = 0.95,
				charge_amount = 1,
			})
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_true(self._health_station_component.needs_health)
			assert.are.equal(1, self._health_station_component.needs_health_queue_number)
		end)

		it("promotes corruption-only damage into health-station demand when humans are above reserve", function()
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.70,
				bot_permanent_damage_pct = 0.30,
				human_health_pct = 0.95,
				charge_amount = 4,
			})
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_true(self._health_station_component.needs_health)
			assert.are.equal(1, self._health_station_component.needs_health_queue_number)
		end)

		it("defers a healthier bot when the last station charge is needed by a worse bot", function()
			local station_unit = install_hook_fixture({
				bot_health_by_unit = {
					bot1 = 0.95,
					bot2 = 0.10,
					human1 = 0.95,
				},
				charge_amount = 1,
			})
			local self = {
				_health_station_component = {
					needs_health = true,
					needs_health_queue_number = 1,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
					valid_bot_units = { "bot1", "bot2" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
		end)

		it("allows a healthier bot when spare station charges cover worse bots", function()
			local station_unit = install_hook_fixture({
				bot_health_by_unit = {
					bot1 = 0.95,
					bot2 = 0.10,
					human1 = 0.95,
				},
				charge_amount = 2,
			})
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
					valid_bot_units = { "bot1", "bot2" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_true(self._health_station_component.needs_health)
			assert.are.equal(1, self._health_station_component.needs_health_queue_number)
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

	describe("install_bot_group_hooks", function()
		it("installs BotGroup deployable hooks only once per shared class table", function()
			local hook_safe_calls = 0
			local BotGroup = {
				_update_pickups_and_deployables_near_player = function() end,
			}

			HealingDeferral.init({
				mod = {
					hook_safe = function(_, target, method_name)
						if target == BotGroup and method_name == "_update_pickups_and_deployables_near_player" then
							hook_safe_calls = hook_safe_calls + 1
						end
					end,
				},
				health_module = {
					current_health_percent = function()
						return 1
					end,
				},
				fixed_time = function()
					return 0
				end,
			})

			HealingDeferral.install_bot_group_hooks(BotGroup)
			HealingDeferral.install_bot_group_hooks(BotGroup)

			assert.equals(1, hook_safe_calls)
		end)
	end)
end)
