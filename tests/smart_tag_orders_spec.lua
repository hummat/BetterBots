local test_helper = require("tests.test_helper")
local SmartTagOrders = dofile("scripts/mods/BetterBots/smart_tag_orders.lua")

describe("smart_tag_orders", function()
	local saved_script_unit = rawget(_G, "ScriptUnit")
	local saved_unit = rawget(_G, "Unit")
	local saved_managers = rawget(_G, "Managers")
	local saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
	local saved_alive = rawget(_G, "ALIVE")
	local saved_vector3 = rawget(_G, "Vector3")
	local debug_logs
	local pickup_orders
	local pickup_defs
	local ammo_full_by_unit
	local grenade_refill_by_unit
	local players_by_unit
	local inventories_by_unit
	local side_units
	local human_unit
	local bot_one
	local bot_two
	local target_unit
	local hook_require_callbacks
	local hook_registrations

	local function reset()
		debug_logs = {}
		pickup_orders = {}
		pickup_defs = {}
		ammo_full_by_unit = {}
		grenade_refill_by_unit = {}
		players_by_unit = {}
		inventories_by_unit = {}
		side_units = {}
		human_unit = { name = "human" }
		bot_one = { name = "bot_one" }
		bot_two = { name = "bot_two" }
		target_unit = { name = "target" }
		hook_require_callbacks = {}
		hook_registrations = {}

		package.loaded["scripts/settings/pickup/pickups"] = {
			by_name = pickup_defs,
		}
		package.loaded["scripts/utilities/ammo"] = {
			reserve_ammo_is_full = function(unit)
				return ammo_full_by_unit[unit] == true
			end,
		}
		package.loaded["scripts/utilities/bot_order"] = {
			pickup = function(bot_unit, pickup_unit, ordering_player)
				pickup_orders[#pickup_orders + 1] = {
					bot_unit = bot_unit,
					pickup_unit = pickup_unit,
					ordering_player = ordering_player,
				}
			end,
		}

		_G.ScriptUnit = {
			has_extension = function(unit, system_name)
				if system_name ~= "unit_data_system" then
					return nil
				end

				local inventory = inventories_by_unit[unit]
				if not inventory then
					return nil
				end

				return test_helper.make_player_unit_data_extension({
					inventory = inventory,
				})
			end,
		}

		_G.Unit = {
			get_data = function(unit, field_name)
				if field_name == "pickup_type" then
					return unit.pickup_type
				end

				return nil
			end,
		}

		_G.Vector3 = {
			distance_squared = function(a, b)
				local dx = a.x - b.x
				local dy = a.y - b.y
				local dz = a.z - b.z
				return dx * dx + dy * dy + dz * dz
			end,
		}

		_G.POSITION_LOOKUP = {}
		_G.ALIVE = {}
		_G.Managers = {
			player = {
				player_by_unit = function(_, unit)
					return players_by_unit[unit]
				end,
			},
			state = {
				extension = {
					system = function(_, system_name)
						if system_name ~= "side_system" then
							return nil
						end

						return {
							side_by_unit = {
								[human_unit] = {
									valid_player_units = side_units,
								},
							},
						}
					end,
				},
			},
		}

		SmartTagOrders.init({
			mod = {
				hook_require = function(_, path, callback)
					hook_require_callbacks[path] = callback
				end,
				hook = function(_, target, method_name, handler)
					hook_registrations[#hook_registrations + 1] = {
						target = target,
						method = method_name,
						handler = handler,
					}
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
				return true
			end,
			fixed_time = function()
				return 10
			end,
			bot_slot_for_unit = function(unit)
				if unit == bot_one then
					return 1
				end

				if unit == bot_two then
					return 2
				end

				return 0
			end,
			is_enabled = function()
				return true
			end,
		})

		SmartTagOrders.wire({
			should_block_pickup_order = function()
				return false
			end,
			needs_ammo_pickup = function(unit)
				return ammo_full_by_unit[unit] ~= true or grenade_refill_by_unit[unit] == true
			end,
		})
	end

	before_each(function()
		reset()
	end)

	after_each(function()
		package.loaded["scripts/settings/pickup/pickups"] = nil
		package.loaded["scripts/utilities/ammo"] = nil
		package.loaded["scripts/utilities/bot_order"] = nil
		_G.ScriptUnit = saved_script_unit
		_G.Unit = saved_unit
		_G.Managers = saved_managers
		_G.POSITION_LOOKUP = saved_position_lookup
		_G.ALIVE = saved_alive
		_G.Vector3 = saved_vector3
	end)

	it("routes explicit tome interactions to the nearest eligible bot", function()
		target_unit.pickup_type = "tome"
		pickup_defs.tome = {
			slot_name = "slot_pocketable",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		players_by_unit[bot_two] = {
			is_human_controlled = function()
				return false
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable = "not_equipped" }
		inventories_by_unit[bot_two] = { slot_pocketable = "occupied" }
		side_units = { human_unit, bot_one, bot_two }
		_G.ALIVE[bot_one] = true
		_G.ALIVE[bot_two] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_two] = { x = 9, y = 0, z = 0 }

		local handled, selected_bot = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_true(handled)
		assert.equals(bot_one, selected_bot)
		assert.same({
			bot_unit = bot_one,
			pickup_unit = target_unit,
			ordering_player = players_by_unit[human_unit],
		}, pickup_orders[1])
	end)

	it("routes explicit ammo interactions to the nearest bot missing reserve ammo", function()
		target_unit.pickup_type = "large_clip"
		pickup_defs.large_clip = {
			group = "ammo",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		players_by_unit[bot_two] = {
			is_human_controlled = function()
				return false
			end,
		}
		ammo_full_by_unit[bot_one] = true
		ammo_full_by_unit[bot_two] = false
		side_units = { human_unit, bot_one, bot_two }
		_G.ALIVE[bot_one] = true
		_G.ALIVE[bot_two] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 7, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_two] = { x = 12, y = 0, z = 0 }

		local handled, selected_bot = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_true(handled)
		assert.equals(bot_two, selected_bot)
		assert.equals(bot_two, pickup_orders[1].bot_unit)
	end)

	it("keeps ammo smart-tags eligible for grenade refill bots with full reserve ammo", function()
		target_unit.pickup_type = "large_clip"
		pickup_defs.large_clip = {
			group = "ammo",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		players_by_unit[bot_two] = {
			is_human_controlled = function()
				return false
			end,
		}
		ammo_full_by_unit[bot_one] = true
		grenade_refill_by_unit[bot_one] = true
		ammo_full_by_unit[bot_two] = true
		side_units = { human_unit, bot_one, bot_two }
		_G.ALIVE[bot_one] = true
		_G.ALIVE[bot_two] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_two] = { x = 12, y = 0, z = 0 }

		local handled, selected_bot = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_true(handled)
		assert.equals(bot_one, selected_bot)
		assert.equals(bot_one, pickup_orders[1].bot_unit)
	end)

	it("ignores unsupported grenade pickup families safely", function()
		target_unit.pickup_type = "small_grenade"
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}

		local handled, reason = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_false(handled)
		assert.equals("unsupported_grenade_pickup", reason)
		assert.equals(0, #pickup_orders)
	end)

	it("rejects slot pickups blocked by pickup policy", function()
		target_unit.pickup_type = "motion_detection_mine_shock_pocketable"
		pickup_defs.motion_detection_mine_shock_pocketable = {
			inventory_slot_name = "slot_pocketable_small",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}

		SmartTagOrders.wire({
			should_block_pickup_order = function()
				return true, "unsupported_pocketable"
			end,
		})

		local handled, reason = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_false(handled)
		assert.equals("unsupported_pocketable", reason)
		assert.equals(0, #pickup_orders)
		assert.is_truthy(debug_logs[1].message:find("unsupported_pocketable", 1, true))
	end)

	it("logs per-bot reasons when no bot is eligible for a slot pickup", function()
		target_unit.pickup_type = "syringe_power_boost_pocketable"
		pickup_defs.syringe_power_boost_pocketable = {
			inventory_slot_name = "slot_pocketable_small",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable_small = "occupied" }
		side_units = { human_unit, bot_one }
		_G.ALIVE[bot_one] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }

		local handled, reason = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_false(handled)
		assert.equals("no_eligible_bot", reason)
		assert.equals(0, #pickup_orders)
		assert.is_truthy(debug_logs[1].message:find("slot_full", 1, true))
	end)

	it("falls back to player liveness when ALIVE is missing for a live bot", function()
		target_unit.pickup_type = "syringe_power_boost_pocketable"
		pickup_defs.syringe_power_boost_pocketable = {
			inventory_slot_name = "slot_pocketable_small",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
			unit_is_alive = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
			unit_is_alive = function()
				return true
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable_small = "not_equipped" }
		side_units = { human_unit, bot_one }
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }

		local handled, selected_bot = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_true(handled)
		assert.equals(bot_one, selected_bot)
		assert.equals(bot_one, pickup_orders[1].bot_unit)
	end)

	it("does not report the human tagger as a dead bot candidate", function()
		target_unit.pickup_type = "syringe_power_boost_pocketable"
		pickup_defs.syringe_power_boost_pocketable = {
			inventory_slot_name = "slot_pocketable_small",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
			unit_is_alive = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
			unit_is_alive = function()
				return true
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable_small = "occupied" }
		side_units = { human_unit, bot_one }
		_G.ALIVE[bot_one] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }

		local handled, reason = SmartTagOrders.try_dispatch(human_unit, target_unit, nil)

		assert.is_false(handled)
		assert.equals("no_eligible_bot", reason)
		assert.is_truthy(debug_logs[1].message:find("bot=1:slot_full", 1, true))
		assert.is_nil(debug_logs[1].message:find("bot=0", 1, true))
		assert.is_nil(debug_logs[1].message:find("bot_dead", 1, true))
	end)

	it("ignores companion-order interactions", function()
		target_unit.pickup_type = "tome"
		pickup_defs.tome = {
			slot_name = "slot_pocketable",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}

		local handled, reason = SmartTagOrders.try_dispatch(human_unit, target_unit, "companion_order")

		assert.is_false(handled)
		assert.equals("companion_order", reason)
		assert.equals(0, #pickup_orders)
	end)

	it("routes first-time pickup tags through the set_contextual_unit_tag hook", function()
		target_unit.pickup_type = "tome"
		pickup_defs.tome = {
			slot_name = "slot_pocketable",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable = "not_equipped" }
		side_units = { human_unit, bot_one }
		_G.ALIVE[bot_one] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }

		SmartTagOrders.register_hooks()

		local callback = hook_require_callbacks["scripts/extension_systems/smart_tag/smart_tag_system"]
		local smart_tag_class = {}
		smart_tag_class.set_contextual_unit_tag = function(_self, tagger_unit, tagged_unit, alternate)
			return {
				tagger_unit = tagger_unit,
				tagged_unit = tagged_unit,
				alternate = alternate,
			}
		end

		callback(smart_tag_class)

		assert.equals(1, #hook_registrations)
		assert.equals("set_contextual_unit_tag", hook_registrations[1].method)

		local result = hook_registrations[1].handler(
			smart_tag_class.set_contextual_unit_tag,
			smart_tag_class,
			human_unit,
			target_unit,
			nil
		)

		assert.same({
			tagger_unit = human_unit,
			tagged_unit = target_unit,
			alternate = nil,
		}, result)
		assert.equals(bot_one, pickup_orders[1].bot_unit)
	end)

	it("routes already-tagged pickup interactions through trigger_tag_interaction", function()
		target_unit.pickup_type = "syringe_corruption_pocketable"
		pickup_defs.syringe_corruption_pocketable = {
			slot_name = "slot_pocketable_small",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable_small = "not_equipped" }
		side_units = { human_unit, bot_one }
		_G.ALIVE[bot_one] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }

		SmartTagOrders.register_hooks()

		local callback = hook_require_callbacks["scripts/extension_systems/smart_tag/smart_tag_system"]
		local smart_tag_class = {
			set_contextual_unit_tag = function() end,
			trigger_tag_interaction = function(_self, tag_id, interactor_unit, tagged_unit, alternate)
				return {
					tag_id = tag_id,
					interactor_unit = interactor_unit,
					tagged_unit = tagged_unit,
					alternate = alternate,
				}
			end,
		}

		callback(smart_tag_class)

		local result = hook_registrations[2].handler(
			smart_tag_class.trigger_tag_interaction,
			smart_tag_class,
			77,
			human_unit,
			target_unit,
			nil
		)

		assert.same({
			tag_id = 77,
			interactor_unit = human_unit,
			tagged_unit = target_unit,
			alternate = nil,
		}, result)
		assert.equals(bot_one, pickup_orders[1].bot_unit)
	end)

	it("pcall-wraps pickup routing errors inside the contextual pickup hook", function()
		target_unit.pickup_type = "tome"
		pickup_defs.tome = {
			slot_name = "slot_pocketable",
		}
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_one] = {
			is_human_controlled = function()
				return false
			end,
		}
		inventories_by_unit[bot_one] = { slot_pocketable = "not_equipped" }
		side_units = { human_unit, bot_one }
		_G.ALIVE[bot_one] = true
		_G.POSITION_LOOKUP[target_unit] = { x = 10, y = 0, z = 0 }
		_G.POSITION_LOOKUP[bot_one] = { x = 8, y = 0, z = 0 }
		package.loaded["scripts/utilities/bot_order"] = {
			pickup = function()
				error("pickup failed")
			end,
		}

		SmartTagOrders.register_hooks()

		local callback = hook_require_callbacks["scripts/extension_systems/smart_tag/smart_tag_system"]
		local smart_tag_class = {}
		smart_tag_class.set_contextual_unit_tag = function()
			return "original_result"
		end

		callback(smart_tag_class)

		local ok, result = pcall(
			hook_registrations[1].handler,
			smart_tag_class.set_contextual_unit_tag,
			smart_tag_class,
			human_unit,
			target_unit,
			nil
		)

		assert.is_true(ok)
		assert.equals("original_result", result)
	end)

	it("registers the smart-tag hook once per shared SmartTagSystem table", function()
		SmartTagOrders.register_hooks()

		local callback = hook_require_callbacks["scripts/extension_systems/smart_tag/smart_tag_system"]
		assert.is_function(callback)

		local target = {
			set_contextual_unit_tag = function() end,
			trigger_tag_interaction = function() end,
		}

		callback(target)
		callback(target)

		assert.equals(2, #hook_registrations)
		assert.equals(target, hook_registrations[1].target)
		assert.equals("set_contextual_unit_tag", hook_registrations[1].method)
		assert.equals(target, hook_registrations[2].target)
		assert.equals("trigger_tag_interaction", hook_registrations[2].method)
	end)
end)
