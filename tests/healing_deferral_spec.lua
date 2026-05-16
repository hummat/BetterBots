local HealingDeferral = dofile("scripts/mods/BetterBots/healing_deferral.lua")
local test_helper = dofile("tests/test_helper.lua")

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
			assert.is_false(settings.require_station_tag)
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
						if setting_id == "healing_deferral_require_station_tag" then
							return true
						end
					end,
				},
			})

			local settings = HealingDeferral.resolve_settings()

			assert.are.equal("stations_only", settings.mode)
			assert.are.equal(1.0, settings.human_threshold)
			assert.are.equal(0, settings.emergency_threshold)
			assert.is_true(settings.require_station_tag)
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

			assert.are.equal(4, get_calls)
			assert.are.equal(settings_a, settings_b)

			current_t = 11
			local settings_c = HealingDeferral.resolve_settings()

			assert.are.equal(8, get_calls)
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

	describe("install_interaction_hooks", function()
		it("logs health-station heal details after the engine applies healing", function()
			local hook_handler
			local health_by_unit = {
				bot1 = 0.50,
			}
			local permanent_health_by_unit = {
				bot1 = 0.30,
			}
			local damage_by_unit = {
				bot1 = 50,
			}
			local permanent_damage_by_unit = {
				bot1 = 30,
			}
			local charges_by_station = {
				station1 = 2,
			}
			local debug_logs = {}
			local saved_script_unit = rawget(_G, "ScriptUnit")
			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit == "station1" and system_name == "health_station_system" then
						return {
							charge_amount = function()
								return charges_by_station.station1
							end,
						}
					end

					return nil
				end,
			}
			HealingDeferral.init({
				mod = {
					hook = function(_, target, method_name, handler)
						assert.equals("stop", method_name)
						assert.is_table(target)
						hook_handler = handler
					end,
				},
				debug_log = function(_, _, message)
					debug_logs[#debug_logs + 1] = message
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 10
				end,
				health_module = {
					current_health_percent = function(unit)
						return health_by_unit[unit]
					end,
					permanent_damage_taken_percent = function(unit)
						return permanent_health_by_unit[unit]
					end,
					damage_taken = function(unit)
						return damage_by_unit[unit]
					end,
					permanent_damage_taken = function(unit)
						return permanent_damage_by_unit[unit]
					end,
				},
				bot_slot_for_unit = function(unit)
					return unit == "bot1" and 5 or nil
				end,
			})

			local HealthStationInteraction = {}
			HealingDeferral.install_interaction_hooks(HealthStationInteraction)
			local stop_result = hook_handler(function(_, _, interactor_unit)
				health_by_unit[interactor_unit] = 1.0
				permanent_health_by_unit[interactor_unit] = 0.10
				damage_by_unit[interactor_unit] = 0
				permanent_damage_by_unit[interactor_unit] = 10
				charges_by_station.station1 = 1
				return "engine_result"
			end, {}, nil, "bot1", { target_unit = "station1", duration = 3 }, 20, "success", true)
			_G.ScriptUnit = saved_script_unit

			assert.equals("engine_result", stop_result)
			assert.is_truthy(debug_logs[1])
			local expected_log = "health station heal applied: bot=5 result=success"
				.. " health=50.0%->100.0% perm=30.0%->10.0%"
				.. " damage=50.0->0.0 permanent_damage=30.0->10.0"
				.. " charges=2->1 duration=3.00s"
			assert.equals(expected_log, debug_logs[1])
		end)

		it("does not log health-station stop details for non-bot interactors", function()
			local hook_handler
			local debug_logs = {}
			HealingDeferral.init({
				mod = {
					hook = function(_, _, _, handler)
						hook_handler = handler
					end,
				},
				debug_log = function(_, _, message)
					debug_logs[#debug_logs + 1] = message
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 10
				end,
				health_module = {
					current_health_percent = function()
						return 0.5
					end,
				},
				bot_slot_for_unit = function()
					return nil
				end,
			})

			local HealthStationInteraction = {}
			HealingDeferral.install_interaction_hooks(HealthStationInteraction)
			hook_handler(function()
				return "engine_result"
			end, {}, nil, "human1", { target_unit = "station1" }, 20, "success", true)

			assert.equals(0, #debug_logs)
		end)

		it("logs no-op health-station stops separately from applied heals", function()
			local hook_handler
			local debug_logs = {}
			HealingDeferral.init({
				mod = {
					hook = function(_, _, _, handler)
						hook_handler = handler
					end,
				},
				debug_log = function(_, _, message)
					debug_logs[#debug_logs + 1] = message
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 10
				end,
				health_module = {
					current_health_percent = function()
						return 1.0
					end,
					permanent_damage_taken_percent = function()
						return 0
					end,
					damage_taken = function()
						return 0
					end,
					permanent_damage_taken = function()
						return 0
					end,
				},
				bot_slot_for_unit = function(unit)
					return unit == "bot1" and 5 or nil
				end,
			})

			local HealthStationInteraction = {}
			HealingDeferral.install_interaction_hooks(HealthStationInteraction)
			hook_handler(function()
				return "engine_result"
			end, {}, nil, "bot1", { target_unit = "station1", duration = 3 }, 20, "success", true)

			assert.is_truthy(debug_logs[1])
			local expected_log = "health station no-op: bot=5 result=success"
				.. " health=100.0%->100.0% perm=0.0%->0.0%"
				.. " damage=0.0->0.0 permanent_damage=0.0->0.0"
				.. " charges=unknown->unknown duration=3.00s"
			assert.equals(expected_log, debug_logs[1])
		end)

		it("registers the health-station interaction hook through hook_require", function()
			local hooked_path
			local installed_target
			HealingDeferral.init({
				mod = {
					hook_require = function(_, path, callback)
						hooked_path = path
						callback({})
					end,
					hook = function(_, target)
						installed_target = target
					end,
				},
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
			})

			HealingDeferral.register_hooks()

			assert.equals("scripts/extension_systems/interaction/interactions/health_station_interaction", hooked_path)
			assert.is_table(installed_target)
		end)
	end)

	describe("install_behavior_ext_hooks", function()
		local update_health_stations_hook
		local saved_script_unit
		local debug_logs

		local function find_debug_log(pattern)
			for i = 1, #debug_logs do
				if string.find(debug_logs[i], pattern, 1, true) then
					return debug_logs[i]
				end
			end

			return nil
		end

		local function install_hook_fixture(opts)
			local station_unit = {}
			local martyrdom_units = opts.martyrdom_units or {}
			local station_units = opts.station_units or { station_unit }
			local interactor_extensions = opts.interactor_extensions or {}
			debug_logs = {}

			saved_script_unit = rawget(_G, "ScriptUnit")
			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if system_name == "health_station_system" then
						local is_station = false
						for i = 1, #station_units do
							if unit == station_units[i] then
								is_station = true
								break
							end
						end
						if not is_station then
							return nil
						end

						return {
							charge_amount = function()
								return opts.charge_amount
							end,
						}
					end

					if system_name == "interactor_system" then
						return interactor_extensions[unit]
					end

					if
						system_name == "talent_system"
						and ((unit == "bot1" and opts.bot_has_martyrdom) or martyrdom_units[unit])
					then
						return {
							talents = function()
								return {
									zealot_martyrdom = true,
								}
							end,
						}
					end

					return nil
				end,
			}
			local position_lookup
			local vector3
			if opts.position_lookup then
				position_lookup = opts.position_lookup
			elseif opts.bot_position or opts.station_position then
				position_lookup = {
					bot1 = opts.bot_position or { x = 0, y = 0, z = 0 },
					[station_unit] = opts.station_position or { x = 0, y = 0, z = 0 },
				}
			end
			if position_lookup then
				vector3 = {
					distance = function(a, b)
						local dx = a.x - b.x
						local dy = a.y - b.y
						local dz = a.z - b.z

						return math.sqrt(dx * dx + dy * dy + dz * dz)
					end,
					distance_squared = function(a, b)
						local dx = a.x - b.x
						local dy = a.y - b.y
						local dz = a.z - b.z

						return dx * dx + dy * dy + dz * dz
					end,
				}
			end

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
						if setting_id == "healing_deferral_require_station_tag" then
							return opts.require_station_tag == true
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
				debug_log = function(_, _, message)
					debug_logs[#debug_logs + 1] = message
				end,
				debug_enabled = function()
					return opts.debug_enabled == true
				end,
				health_station_recently_tagged = opts.health_station_recently_tagged,
				position_lookup = position_lookup,
				vector3 = vector3,
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
				},
				_bot_group = {
					_bot_data = {
						bot1 = {},
						bot2 = {},
					},
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
				},
				_bot_group = {
					_bot_data = {
						bot1 = {},
						bot2 = {},
					},
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_true(self._health_station_component.needs_health)
			assert.are.equal(1, self._health_station_component.needs_health_queue_number)
		end)

		it("blocks bot health-station demand when ping-only mode is enabled and the station was not tagged", function()
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function()
					return false
				end,
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
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
		end)

		it("allows normal health-station priority when ping-only mode is enabled and the station was tagged", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
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

		it("refreshes destination when a tagged ping-only health station is allowed", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
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
			assert.is_true(self._follow_component.needs_destination_refresh)
		end)

		it("keeps an explicit health-station tag after the tag window expires", function()
			local station_unit = install_hook_fixture({
				debug_enabled = true,
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				bot_position = {
					x = 0,
					y = 0,
					z = 0,
				},
				station_position = {
					x = 3,
					y = 4,
					z = 0,
				},
				health_station_recently_tagged = function()
					return false
				end,
			})
			local reserved, reason = HealingDeferral.reserve_tagged_health_station("bot1", station_unit)
			assert.is_true(reserved, reason)
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_perception_component = {
					target_level_unit = nil,
					target_level_unit_distance = math.huge,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_true(self._health_station_component.needs_health)
			assert.are.equal(1, self._health_station_component.needs_health_queue_number)
			assert.equals(station_unit, self._perception_component.target_level_unit)
			assert.are.equal(25, self._perception_component.target_level_unit_distance)
			assert.is_true(self._follow_component.needs_destination_refresh)
			assert.is_truthy(find_debug_log("health station permitted: explicit human smart-tag order"))
		end)

		it("opens the vanilla health-station condition when the assigned bot can already interact", function()
			local can_interact_args
			local bot_position = {
				x = 1,
				y = 2,
				z = 0,
			}
			local destination = {
				value = nil,
				store = function(self, value)
					self.value = value
				end,
			}
			local station_unit = install_hook_fixture({
				debug_enabled = true,
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				bot_position = bot_position,
				interactor_extensions = {
					bot1 = test_helper.make_interactor_extension({
						can_interact = function(_, target, interaction_type)
							can_interact_args = { target = target, interaction_type = interaction_type }
							return true
						end,
					}),
				},
				health_station_recently_tagged = function()
					return false
				end,
			})
			local reserved, reason = HealingDeferral.reserve_tagged_health_station("bot1", station_unit)
			assert.is_true(reserved, reason)
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_behavior_component = {
					interaction_unit = nil,
					target_level_unit_destination = destination,
				},
				_perception_component = {
					target_level_unit = nil,
					target_level_unit_distance = math.huge,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.same({ target = station_unit, interaction_type = "health_station" }, can_interact_args)
			assert.equals(station_unit, self._behavior_component.interaction_unit)
			assert.equals(bot_position, destination.value)
			assert.is_false(self._follow_component.needs_destination_refresh)
			assert.is_truthy(find_debug_log("health station interaction opened"))
		end)

		it(
			"keeps refreshing the health-station destination when can_interact is true but the bot is too far away",
			function()
				local can_interact_args
				local bot_position = {
					x = 0,
					y = 0,
					z = 0,
				}
				local original_destination = {
					x = 10,
					y = 20,
					z = 0,
				}
				local destination = {
					value = original_destination,
					store = function(self, value)
						self.value = value
					end,
				}
				local station_unit = install_hook_fixture({
					debug_enabled = true,
					bot_health_pct = 0.50,
					human_health_pct = 0.95,
					charge_amount = 2,
					require_station_tag = true,
					bot_position = bot_position,
					station_position = {
						x = 3,
						y = 0,
						z = 0,
					},
					interactor_extensions = {
						bot1 = test_helper.make_interactor_extension({
							max_interaction_distance = 2.5,
							can_interact = function(_, target, interaction_type)
								can_interact_args = { target = target, interaction_type = interaction_type }
								return true
							end,
						}),
					},
					health_station_recently_tagged = function()
						return false
					end,
				})
				local reserved, reason = HealingDeferral.reserve_tagged_health_station("bot1", station_unit)
				assert.is_true(reserved, reason)
				local self = {
					_health_station_component = {
						needs_health = false,
						needs_health_queue_number = 0,
					},
					_follow_component = {
						needs_destination_refresh = false,
					},
					_behavior_component = {
						interaction_unit = nil,
						target_level_unit_destination = destination,
					},
					_perception_component = {
						target_level_unit = nil,
						target_level_unit_distance = math.huge,
					},
					_side = {
						valid_human_units = { "human1" },
					},
				}

				update_health_stations_hook(self, "bot1")

				assert.same({ target = station_unit, interaction_type = "health_station" }, can_interact_args)
				assert.is_nil(self._behavior_component.interaction_unit)
				assert.equals(original_destination, destination.value)
				assert.is_true(self._follow_component.needs_destination_refresh)
				assert.is_truthy(find_debug_log("health station destination refresh requested from human smart-tag"))
				assert.is_nil(find_debug_log("health station interaction opened"))
			end
		)

		it("keeps refreshing the health-station destination when station position is unavailable", function()
			local bot_position = {
				x = 0,
				y = 0,
				z = 0,
			}
			local original_destination = {
				x = 10,
				y = 20,
				z = 0,
			}
			local destination = {
				value = original_destination,
				store = function(self, value)
					self.value = value
				end,
			}
			local station_unit = install_hook_fixture({
				debug_enabled = true,
				bot_health_pct = 0.50,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				position_lookup = {
					bot1 = bot_position,
				},
				interactor_extensions = {
					bot1 = test_helper.make_interactor_extension({
						can_interact = function()
							return true
						end,
					}),
				},
				health_station_recently_tagged = function()
					return false
				end,
			})
			local reserved, reason = HealingDeferral.reserve_tagged_health_station("bot1", station_unit)
			assert.is_true(reserved, reason)
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_behavior_component = {
					interaction_unit = nil,
					target_level_unit_destination = destination,
				},
				_perception_component = {
					target_level_unit = nil,
					target_level_unit_distance = math.huge,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_nil(self._behavior_component.interaction_unit)
			assert.equals(original_destination, destination.value)
			assert.is_true(self._follow_component.needs_destination_refresh)
			assert.is_truthy(find_debug_log("health station destination refresh requested from human smart-tag"))
			assert.is_nil(find_debug_log("health station interaction opened"))
		end)

		it("clears an explicit health-station tag when the bot becomes full", function()
			local bot_health_by_unit = {
				bot1 = 0.50,
			}
			local station_unit = install_hook_fixture({
				bot_health_by_unit = bot_health_by_unit,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function()
					return false
				end,
			})
			local reserved, reason = HealingDeferral.reserve_tagged_health_station("bot1", station_unit)
			assert.is_true(reserved, reason)
			bot_health_by_unit.bot1 = 1.0
			local self = {
				_health_station_component = {
					needs_health = true,
					needs_health_queue_number = 1,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_perception_component = {
					target_level_unit = nil,
					target_level_unit_distance = math.huge,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
			assert.is_false(self._follow_component.needs_destination_refresh)
			assert.is_nil(HealingDeferral.reserved_health_station("bot1"))
		end)

		it("logs human health reserve detail when a tagged station defers to a human", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				debug_enabled = true,
				bot_health_pct = 0.50,
				human_health_pct = 0.80,
				human_threshold = 90,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
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

			assert.is_false(self._health_station_component.needs_health)
			assert.is_truthy(find_debug_log("deferred health station to human player"))
			assert.is_truthy(find_debug_log("bot_health=50%"))
			assert.is_truthy(find_debug_log("lowest_human_health=80%"))
			assert.is_truthy(find_debug_log("threshold=90%"))
		end)

		it("does not let a tagged ping-only health station override Martyrdom preservation", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.50,
				charge_amount = 2,
				require_station_tag = true,
				bot_has_martyrdom = true,
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
			assert.is_false(self._follow_component.needs_destination_refresh)
		end)

		it("does not let a tagged ping-only health station make a full-health bot heal", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 1.0,
				human_health_pct = 0.95,
				charge_amount = 2,
				require_station_tag = true,
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
			local self = {
				_health_station_component = {
					needs_health = true,
					needs_health_queue_number = 1,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
			assert.is_false(self._follow_component.needs_destination_refresh)
		end)

		it("does not defer a tagged health station to a non-critical Martyrdom human", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.30,
				human_threshold = 90,
				charge_amount = 2,
				require_station_tag = true,
				martyrdom_units = {
					human1 = true,
				},
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
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
			assert.is_true(self._follow_component.needs_destination_refresh)
		end)

		it("still defers a tagged health station to a critical Martyrdom human", function()
			local tagged_station
			local station_unit = install_hook_fixture({
				bot_health_pct = 0.50,
				human_health_pct = 0.10,
				human_threshold = 90,
				charge_amount = 2,
				require_station_tag = true,
				martyrdom_units = {
					human1 = true,
				},
				health_station_recently_tagged = function(unit)
					return unit == tagged_station
				end,
			})
			tagged_station = station_unit
			local self = {
				_health_station_component = {
					needs_health = false,
					needs_health_queue_number = 0,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_perception_component = {
					target_level_unit = station_unit,
				},
				_side = {
					valid_human_units = { "human1" },
				},
			}

			update_health_stations_hook(self, "bot1")

			assert.is_false(self._health_station_component.needs_health)
			assert.are.equal(0, self._health_station_component.needs_health_queue_number)
			assert.is_false(self._follow_component.needs_destination_refresh)
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
