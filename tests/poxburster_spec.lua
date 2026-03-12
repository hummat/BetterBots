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
					hook_safe = function(_self, target, method_name, callback)
						assert.equals("_update_target_enemy", method_name)
						captured_hook_safe = callback
					end,
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

		it("logs suppression at debug level so it is visible in normal validation runs", function()
			Poxburster.register_hooks()
			assert.is_not_nil(
				captured_hook_require["scripts/extension_systems/perception/bot_perception_extension"]
			)

			captured_hook_require["scripts/extension_systems/perception/bot_perception_extension"]({})
			assert.is_not_nil(captured_hook_safe)

			local perception_component = {
				target_enemy = "poxburster",
				target_enemy_distance = 3,
				target_enemy_type = "special",
			}

			captured_hook_safe(
				nil,
				"bot_unit",
				{ x = 0, y = 0, z = 0 },
				perception_component,
				nil,
				nil,
				{ valid_human_units = { "human" } }
			)

			assert.is_nil(perception_component.target_enemy)
			assert.equals(math.huge, perception_component.target_enemy_distance)
			assert.equals("none", perception_component.target_enemy_type)
			assert.equals(1, #debug_logs)
			assert.equals("debug", debug_logs[1].level)
			assert.matches("suppressed poxburster target %(near_human_player%)", debug_logs[1].message)
		end)
	end)
end)
