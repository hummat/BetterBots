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

	describe("logging", function()
		local saved_script_unit
		local saved_position_lookup
		local saved_vector3
		local captured_hook_require
		local captured_hook_safe
		local debug_logs

		before_each(function()
			saved_script_unit = rawget(_G, "ScriptUnit")
			saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
			saved_vector3 = rawget(_G, "Vector3")
			debug_logs = {}
			captured_hook_require = {}
			captured_hook_safe = nil

			_G.Vector3 = {
				distance = distance,
			}

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if system_name ~= "unit_data_system" then
						return nil
					end

					if unit == "poxburster" then
						return {
							breed = function()
								return { name = "chaos_poxwalker_bomber" }
							end,
						}
					end

					return nil
				end,
			}

			_G.POSITION_LOOKUP = {
				["poxburster"] = { x = 20, y = 0, z = 0 },
				["human"] = { x = 18, y = 0, z = 0 },
			}

			Poxburster.init({
				mod = {
					hook_require = function(_self, path, callback)
						captured_hook_require[path] = callback
					end,
					hook_safe = function(_self, _target, method_name, callback)
						assert.equals("_update_target_enemy", method_name)
						captured_hook_safe = callback
					end,
					hook = function() end,
				},
				debug_log = function(key, fixed_t, message, _interval, level)
					debug_logs[#debug_logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
						level = level,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 42
				end,
			})
		end)

		after_each(function()
			_G.ScriptUnit = saved_script_unit
			_G.POSITION_LOOKUP = saved_position_lookup
			_G.Vector3 = saved_vector3
		end)

		local function run_hook_with_target(slot_name)
			Poxburster.register_hooks()
			assert.is_not_nil(captured_hook_require["scripts/extension_systems/perception/bot_perception_extension"])

			captured_hook_require["scripts/extension_systems/perception/bot_perception_extension"]({})
			assert.is_not_nil(captured_hook_safe)

			local perception_component = {
				target_enemy_distance = 3,
				target_enemy_type = "special",
			}
			perception_component[slot_name] = "poxburster"

			captured_hook_safe(
				nil,
				"bot_unit",
				{ x = 0, y = 0, z = 0 },
				perception_component,
				nil,
				nil,
				{ valid_human_units = { "human" } }
			)

			return perception_component
		end

		it("logs suppression at debug level so it is visible in normal validation runs", function()
			local perception_component = run_hook_with_target("target_enemy")

			assert.is_nil(perception_component.target_enemy)
			assert.equals(math.huge, perception_component.target_enemy_distance)
			assert.equals("none", perception_component.target_enemy_type)
			assert.equals(1, #debug_logs)
			assert.equals("debug", debug_logs[1].level)
			assert.matches("suppressed poxburster target_enemy %(near_human_player%)", debug_logs[1].message)
		end)

		it("includes the acting bot in the poxburster push log key", function()
			local captured_hook
			local logged = {}

			Poxburster.init({
				mod = {
					hook_require = function(_self, path, callback)
						if path == "scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action" then
							callback({})
						end
					end,
					hook_safe = function() end,
					hook = function(_self, _target, method_name, handler)
						if method_name == "_should_push" then
							captured_hook = handler
						end
					end,
				},
				debug_log = function(key, fixed_t, message, _interval, level)
					logged[#logged + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
						level = level,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 42
				end,
			})
			Poxburster.register_hooks()

			local scratchpad = {
				unit = "bot_unit",
				weapon_extension = {
					action_input_is_currently_valid = function()
						return true
					end,
				},
			}
			local defense_meta_data = {
				push_action_input = "push",
			}
			local target_breed = {
				name = "chaos_poxwalker_bomber",
			}

			local pushed, action_input = captured_hook(function()
				return false, nil, false
			end, nil, defense_meta_data, scratchpad, true, "poxburster", target_breed, 12.5)

			assert.is_true(pushed)
			assert.equals("push", action_input)
			assert.equals(1, #logged)
			assert.equals("poxburster_push:poxburster:" .. tostring(scratchpad.unit), logged[1].key)
		end)

		it("suppresses poxbursters from all secondary perception slots", function()
			local opportunity = run_hook_with_target("opportunity_target_enemy")
			local urgent = run_hook_with_target("urgent_target_enemy")
			local priority = run_hook_with_target("priority_target_enemy")

			assert.is_nil(opportunity.opportunity_target_enemy)
			assert.is_nil(urgent.urgent_target_enemy)
			assert.is_nil(priority.priority_target_enemy)
		end)
	end)

	describe("push range (#54)", function()
		local saved_script_unit
		local saved_position_lookup
		local saved_vector3

		before_each(function()
			saved_script_unit = rawget(_G, "ScriptUnit")
			saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
			saved_vector3 = rawget(_G, "Vector3")

			_G.Vector3 = { distance = distance }

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if system_name ~= "unit_data_system" then
						return nil
					end
					if unit == "poxburster" then
						return {
							breed = function()
								return { name = "chaos_poxwalker_bomber" }
							end,
						}
					end
					if unit == "horde_enemy" then
						return {
							breed = function()
								return { name = "chaos_poxwalker" }
							end,
						}
					end
					return nil
				end,
			}
		end)

		after_each(function()
			_G.ScriptUnit = saved_script_unit
			_G.POSITION_LOOKUP = saved_position_lookup
			_G.Vector3 = saved_vector3
		end)

		it("returns true when poxburster is within push distance", function()
			_G.POSITION_LOOKUP = { ["poxburster"] = { x = 2, y = 0, z = 0 } }
			assert.is_true(Poxburster.is_poxburster_in_push_range("poxburster", { x = 0, y = 0, z = 0 }))
		end)

		it("returns false when poxburster is outside push distance", function()
			_G.POSITION_LOOKUP = { ["poxburster"] = { x = 4, y = 0, z = 0 } }
			assert.is_false(Poxburster.is_poxburster_in_push_range("poxburster", { x = 0, y = 0, z = 0 }))
		end)

		it("returns false for non-poxburster enemies", function()
			_G.POSITION_LOOKUP = { ["horde_enemy"] = { x = 1, y = 0, z = 0 } }
			assert.is_false(Poxburster.is_poxburster_in_push_range("horde_enemy", { x = 0, y = 0, z = 0 }))
		end)

		it("returns false for nil unit", function()
			assert.is_false(Poxburster.is_poxburster_in_push_range(nil, { x = 0, y = 0, z = 0 }))
		end)

		it("returns false at exactly PUSH_DIST boundary", function()
			_G.POSITION_LOOKUP = {
				["poxburster"] = { x = Poxburster.POXBURSTER_PUSH_DIST, y = 0, z = 0 },
			}
			assert.is_false(Poxburster.is_poxburster_in_push_range("poxburster", { x = 0, y = 0, z = 0 }))
		end)

		describe("perception hook", function()
			local captured_hook_require
			local captured_hook_safe
			local debug_logs

			before_each(function()
				debug_logs = {}
				captured_hook_require = {}
				captured_hook_safe = nil

				Poxburster.init({
					mod = {
						hook_require = function(_self, path, callback)
							captured_hook_require[path] = callback
						end,
						hook_safe = function(_self, _target, _method_name, callback)
							captured_hook_safe = callback
						end,
						hook = function() end,
					},
					debug_log = function(key, _fixed_t, message, _interval, level)
						debug_logs[#debug_logs + 1] = { key = key, message = message, level = level }
					end,
					debug_enabled = function()
						return true
					end,
					fixed_time = function()
						return 42
					end,
				})

				Poxburster.register_hooks()
				captured_hook_require["scripts/extension_systems/perception/bot_perception_extension"]({})
			end)

			it("does not suppress target_enemy when poxburster is in push range", function()
				_G.POSITION_LOOKUP = {
					["poxburster"] = { x = 2, y = 0, z = 0 },
					["human"] = { x = 50, y = 0, z = 0 },
				}

				local perception =
					{ target_enemy = "poxburster", target_enemy_distance = 2, target_enemy_type = "special" }
				captured_hook_safe(
					nil,
					"bot_unit",
					{ x = 0, y = 0, z = 0 },
					perception,
					nil,
					nil,
					{ valid_human_units = { "human" } }
				)

				assert.equals("poxburster", perception.target_enemy)
				assert.equals(2, perception.target_enemy_distance)
			end)

			it("still suppresses target_enemy when poxburster is in suppress range but outside push range", function()
				_G.POSITION_LOOKUP = {
					["poxburster"] = { x = 4, y = 0, z = 0 },
					["human"] = { x = 50, y = 0, z = 0 },
				}

				local perception =
					{ target_enemy = "poxburster", target_enemy_distance = 4, target_enemy_type = "special" }
				captured_hook_safe(
					nil,
					"bot_unit",
					{ x = 0, y = 0, z = 0 },
					perception,
					nil,
					nil,
					{ valid_human_units = { "human" } }
				)

				assert.is_nil(perception.target_enemy)
				assert.equals(math.huge, perception.target_enemy_distance)
			end)

			it("still suppresses secondary slots even when poxburster is in push range", function()
				_G.POSITION_LOOKUP = {
					["poxburster"] = { x = 2, y = 0, z = 0 },
					["human"] = { x = 50, y = 0, z = 0 },
				}

				local perception = {
					target_enemy = "poxburster",
					target_enemy_distance = 2,
					target_enemy_type = "special",
					opportunity_target_enemy = "poxburster",
					urgent_target_enemy = "poxburster",
					priority_target_enemy = "poxburster",
				}
				captured_hook_safe(
					nil,
					"bot_unit",
					{ x = 0, y = 0, z = 0 },
					perception,
					nil,
					nil,
					{ valid_human_units = { "human" } }
				)

				assert.equals("poxburster", perception.target_enemy)
				assert.is_nil(perception.opportunity_target_enemy)
				assert.is_nil(perception.urgent_target_enemy)
				assert.is_nil(perception.priority_target_enemy)
			end)
		end)
	end)
end)
