local AmmoPolicy = dofile("scripts/mods/BetterBots/ammo_policy.lua")

describe("ammo_policy", function()
	local update_hook
	local captured_hook_require = {}
	local debug_logs
	local saved_unit

	before_each(function()
		update_hook = nil
		captured_hook_require = {}
		debug_logs = {}
		saved_unit = rawget(_G, "Unit")
	end)

	after_each(function()
		_G.Unit = saved_unit
	end)

	local function install_module(overrides)
		AmmoPolicy.init({
			mod = {
				hook_safe = function(_, _, _, fn)
					update_hook = fn
				end,
				hook = function(_, target, method_name, handler)
					local original = target[method_name]
					target[method_name] = function(...)
						return handler(original, ...)
					end
				end,
				hook_require = function(_, path, callback)
					captured_hook_require[path] = callback
				end,
			},
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return overrides and overrides.debug_enabled or false
			end,
			fixed_time = function()
				return 100
			end,
			perf = nil,
			ammo_module = overrides and overrides.ammo_module,
			ability_extension = overrides and overrides.ability_extension,
			nearby_grenade_pickups = overrides and overrides.nearby_grenade_pickups,
			bot_slot_for_unit = overrides and overrides.bot_slot_for_unit,
			settings = overrides and overrides.settings,
			is_enabled = overrides and overrides.is_enabled,
		})
	end

	local function find_debug_log(pattern)
		for i = 1, #debug_logs do
			if string.find(debug_logs[i].message, pattern, 1, true) then
				return debug_logs[i]
			end
		end

		return nil
	end

	it("registers a BotBehaviorExtension _update_ammo hook", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.2
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})

		assert.is_function(update_hook)
	end)

	it("registers an AmmunitionInteraction stop hook for pickup success logging", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0
				end,
				uses_ammo = function()
					return true
				end,
			},
		})

		AmmoPolicy.register_hooks()

		assert.is_function(
			captured_hook_require["scripts/extension_systems/interaction/interactions/ammunition_interaction"]
		)
	end)

	it("sets needs_ammo when bot is at threshold and all eligible humans are above reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.20 or 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("defers ammo to human when bot is above threshold and human is below reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.50 or 0.75
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = true },
		}

		update_hook(self, "bot1")

		assert.is_false(self._pickup_component.needs_ammo)
	end)

	it("logs when grenade charge state cannot resolve an ability extension", function()
		install_module({
			debug_enabled = true,
			ammo_module = {
				current_total_percentage = function()
					return 0.50
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function()
				return nil
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = {} },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_truthy(find_debug_log("grenade pickup skipped: no ability extension"))
	end)

	it("logs when _update_ammo runs without a pickup component", function()
		install_module({
			debug_enabled = true,
			ammo_module = {
				current_total_percentage = function()
					return 0.50
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = {} },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = nil,
		}

		update_hook(self, "bot1")

		assert.is_truthy(find_debug_log("ammo policy skipped: no pickup_component"))
	end)

	it("allows desperate bot to pick up even when human is below reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.15 or 0.75
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("ignores humans whose loadouts do not use ammo", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.15 or 0.10
				end,
				uses_ammo = function(unit)
					return unit == "bot1"
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human_staff" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("preserves explicit ammo pickup orders", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.50 or 0.10
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return "pickup_unit"
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("reuses human ammo scan for bots on the same side in the same frame", function()
		local uses_ammo_calls = 0
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.95
				end,
				uses_ammo = function()
					uses_ammo_calls = uses_ammo_calls + 1
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local side = { valid_human_units = { "human1" } }
		local self_a = {
			_side = side,
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}
		local self_b = {
			_side = side,
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self_a, "bot1")
		update_hook(self_b, "bot2")

		assert.equals(1, uses_ammo_calls)
	end)

	it("allows bot to top off when all humans are above reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.70 or 0.95
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("treats no eligible humans as reserve guard satisfied", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.10 or 0.10
				end,
				uses_ammo = function(unit)
					return unit == "bot1"
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "staff_user" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("logs when bot defers ammo to human", function()
		install_module({
			debug_enabled = true,
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.50 or 0.75
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = true },
		}

		update_hook(self, "bot1")

		assert.is_false(self._pickup_component.needs_ammo)
		assert.is_truthy(find_debug_log("ammo pickup deferred to human"))
	end)

	it("logs when desperate bot picks up despite human reserve low", function()
		install_module({
			debug_enabled = true,
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.15 or 0.75
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
		assert.is_truthy(find_debug_log("ammo pickup permitted: bot desperate"))
	end)

	it("logs when all eligible humans allow ammo pickup", function()
		install_module({
			debug_enabled = true,
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.20 or 0.95
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
		assert.is_truthy(find_debug_log("ammo pickup permitted: all eligible humans above reserve"))
	end)

	it("binds nearby grenade pickup when bot is empty and eligible humans are stocked", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 0
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 1
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
					}
				end
			end,
			nearby_grenade_pickups = function(_, unit)
				assert.equals("bot1", unit)
				return "small_grenade_pickup", 3
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = nil,
				ammo_pickup_distance = math.huge,
				ammo_pickup_valid_until = -math.huge,
			},
		}

		update_hook(self, "bot1")

		assert.equals("small_grenade_pickup", self._pickup_component.ammo_pickup)
		assert.equals(3, self._pickup_component.ammo_pickup_distance)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("binds nearby grenade pickup when humans are above reserve and bot is not full", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 1
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 3
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
					}
				end
			end,
			nearby_grenade_pickups = function(_, unit)
				assert.equals("bot1", unit)
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 0.5
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = nil,
				ammo_pickup_distance = math.huge,
				ammo_pickup_valid_until = -math.huge,
			},
		}

		update_hook(self, "bot1")

		assert.equals("small_grenade_pickup", self._pickup_component.ammo_pickup)
		assert.equals(2, self._pickup_component.ammo_pickup_distance)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("binds nearby grenade pickup when humans are above reserve and bot has spare charges", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 3
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 1
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 2
						end,
					}
				end
			end,
			nearby_grenade_pickups = function(_, unit)
				assert.equals("bot1", unit)
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 0.5
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = nil,
				ammo_pickup_distance = math.huge,
				ammo_pickup_valid_until = -math.huge,
			},
		}

		update_hook(self, "bot1")

		assert.equals("small_grenade_pickup", self._pickup_component.ammo_pickup)
		assert.equals(2, self._pickup_component.ammo_pickup_distance)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("does not bind grenade pickup when bot is already full", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 3
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 3
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 1
						end,
						max_ability_charges = function(_, ability_type)
							assert.equals("grenade_ability", ability_type)
							return 1
						end,
					}
				end
			end,
			nearby_grenade_pickups = function(_, unit)
				assert.equals("bot1", unit)
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = nil,
				ammo_pickup_distance = math.huge,
				ammo_pickup_valid_until = -math.huge,
			},
		}

		update_hook(self, "bot1")

		assert.is_nil(self._pickup_component.ammo_pickup)
		assert.equals(math.huge, self._pickup_component.ammo_pickup_distance)
		assert.equals(-math.huge, self._pickup_component.ammo_pickup_valid_until)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("defers grenade pickup to low-reserve human but preserves ammo decision", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.10 or 0.95
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 1
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 1
						end,
					}
				end
			end,
			nearby_grenade_pickups = function()
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = "small_clip_pickup",
				ammo_pickup_distance = 4,
				ammo_pickup_valid_until = 102,
			},
		}

		update_hook(self, "bot1")

		assert.equals("small_clip_pickup", self._pickup_component.ammo_pickup)
		assert.equals(4, self._pickup_component.ammo_pickup_distance)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("clears reserved grenade pickup when a human newly needs the refill", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.10 or 0.95
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 1
						end,
					}
				end

				if unit == "human1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 1
						end,
					}
				end
			end,
			nearby_grenade_pickups = function()
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = "small_grenade_pickup",
				ammo_pickup_distance = 2,
				ammo_pickup_valid_until = 102,
			},
		}

		update_hook(self, "bot1")

		assert.is_nil(self._pickup_component.ammo_pickup)
		assert.equals(math.huge, self._pickup_component.ammo_pickup_distance)
		assert.equals(-math.huge, self._pickup_component.ammo_pickup_valid_until)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("clears reserved grenade pickup when ammo policy is disabled at runtime", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			is_enabled = function()
				return false
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		_G.Unit = {
			get_data = function(unit, key)
				assert.equals("pickup_type", key)
				if unit == "small_grenade_pickup" then
					return "small_grenade"
				end
			end,
		}

		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = true,
				ammo_pickup = "small_grenade_pickup",
				ammo_pickup_distance = 2,
				ammo_pickup_valid_until = 102,
			},
		}

		update_hook(self, "bot1")

		assert.is_nil(self._pickup_component.ammo_pickup)
		assert.equals(math.huge, self._pickup_component.ammo_pickup_distance)
		assert.equals(-math.huge, self._pickup_component.ammo_pickup_valid_until)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("ignores grenade pickup for cooldown-only blitz users", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 0
						end,
					}
				end
			end,
			nearby_grenade_pickups = function()
				return "small_grenade_pickup", 2
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return nil
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = nil,
				ammo_pickup_distance = math.huge,
				ammo_pickup_valid_until = -math.huge,
			},
		}

		update_hook(self, "bot1")

		assert.is_nil(self._pickup_component.ammo_pickup)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("preserves explicit ammo pickup orders over grenade arbitration", function()
		install_module({
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit == "bot1" then
					return {
						remaining_ability_charges = function()
							return 0
						end,
						max_ability_charges = function()
							return 1
						end,
					}
				end
			end,
			nearby_grenade_pickups = function()
				return "small_grenade_pickup", 1
			end,
			settings = {
				bot_ranged_ammo_threshold = function()
					return 0.20
				end,
				human_ammo_reserve_threshold = function()
					return 0.80
				end,
				human_grenade_reserve_threshold = function()
					return 1.0
				end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = {
				ammo_pickup_order_unit = function()
					return "explicit_pickup_order"
				end,
			},
			_pickup_component = {
				needs_ammo = false,
				ammo_pickup = "ordered_ammo_pickup",
				ammo_pickup_distance = 1,
				ammo_pickup_valid_until = 200,
			},
		}

		update_hook(self, "bot1")

		assert.equals("ordered_ammo_pickup", self._pickup_component.ammo_pickup)
		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("logs actual ammo pickup success after a successful interaction", function()
		local ammo_percentage = {
			bot1 = 0.10,
		}

		install_module({
			debug_enabled = true,
			bot_slot_for_unit = function(unit)
				return unit == "bot1" and 2 or nil
			end,
			ammo_module = {
				current_total_percentage = function(unit)
					return ammo_percentage[unit]
				end,
				uses_ammo = function()
					return true
				end,
			},
		})

		local AmmunitionInteraction = {
			stop = function(_self, _world, interactor_unit, _unit_data_component, _t, result, interactor_is_server)
				assert.equals("bot1", interactor_unit)
				assert.equals("success", result)
				assert.is_true(interactor_is_server)
				ammo_percentage[interactor_unit] = 0.55
			end,
		}
		_G.Unit = {
			get_data = function(unit, field)
				assert.equals("pickup_clip", unit)
				assert.equals("pickup_type", field)
				return "small_clip"
			end,
		}

		AmmoPolicy.install_interaction_hooks(AmmunitionInteraction)
		AmmunitionInteraction.stop({}, nil, "bot1", { target_unit = "pickup_clip" }, 100, "success", true)

		assert.is_truthy(find_debug_log("ammo pickup success: small_clip (bot=2, ammo=10%->55%)"))
	end)

	it("logs actual grenade pickup success after a successful interaction", function()
		local grenade_charges = {
			bot1 = 0,
		}

		install_module({
			debug_enabled = true,
			bot_slot_for_unit = function(unit)
				return unit == "bot1" and 4 or nil
			end,
			ammo_module = {
				current_total_percentage = function()
					return 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			ability_extension = function(unit)
				if unit ~= "bot1" then
					return nil
				end

				return {
					remaining_ability_charges = function(_, ability_type)
						assert.equals("grenade_ability", ability_type)
						return grenade_charges[unit]
					end,
					max_ability_charges = function(_, ability_type)
						assert.equals("grenade_ability", ability_type)
						return 1
					end,
				}
			end,
		})

		local AmmunitionInteraction = {
			stop = function(_self, _world, interactor_unit)
				grenade_charges[interactor_unit] = 1
			end,
		}
		_G.Unit = {
			get_data = function(unit, field)
				assert.equals("pickup_grenade", unit)
				assert.equals("pickup_type", field)
				return "small_grenade"
			end,
		}

		AmmoPolicy.install_interaction_hooks(AmmunitionInteraction)
		AmmunitionInteraction.stop({}, nil, "bot1", { target_unit = "pickup_grenade" }, 100, "success", true)

		assert.is_truthy(find_debug_log("grenade pickup success: small_grenade (bot=4, charges=0->1/1)"))
	end)
end)
