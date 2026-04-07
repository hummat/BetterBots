local AmmoPolicy = dofile("scripts/mods/BetterBots/ammo_policy.lua")

describe("ammo_policy", function()
	local update_hook
	local debug_logs

	before_each(function()
		update_hook = nil
		debug_logs = {}
	end)

	local function install_module(overrides)
		AmmoPolicy.init({
			mod = {
				hook_safe = function(_, _, _, fn)
					update_hook = fn
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
			settings = overrides and overrides.settings,
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
end)
