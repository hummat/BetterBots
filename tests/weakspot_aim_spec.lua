local test_helper = require("tests.test_helper")

local saved_script_unit = rawget(_G, "ScriptUnit")
local saved_unit = rawget(_G, "Unit")
local saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
local saved_vector3 = rawget(_G, "Vector3")
local saved_quaternion = rawget(_G, "Quaternion")

local WeakspotAim = dofile("scripts/mods/BetterBots/weakspot_aim.lua")

local vec_mt = {}

vec_mt.__sub = function(a, b)
	return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec_mt)
end

local function vec(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, vec_mt)
end

local function install_bulwark_math_globals()
	_G.Vector3 = {
		angle = function(a, b)
			local dot = a.x * b.x + a.y * b.y + a.z * b.z
			local length_a = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
			local length_b = math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z)

			if length_a == 0 or length_b == 0 then
				return 0
			end

			local cos_theta = dot / (length_a * length_b)
			cos_theta = math.max(-1, math.min(1, cos_theta))

			return math.acos(cos_theta)
		end,
		normalize = function(v)
			local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

			if length == 0 then
				return vec(0, 0, 0)
			end

			return vec(v.x / length, v.y / length, v.z / length)
		end,
	}
	_G.Quaternion = {
		forward = function(rotation)
			return rotation.forward
		end,
	}
end

describe("weakspot_aim", function()
	after_each(function()
		_G.ScriptUnit = saved_script_unit
		_G.Unit = saved_unit
		_G.POSITION_LOOKUP = saved_position_lookup
		_G.Vector3 = saved_vector3
		_G.Quaternion = saved_quaternion
	end)

	describe("_breed_override_for", function()
		it("returns j_spine for Scab Mauler (renegade_executor)", function()
			assert.equals("j_spine", WeakspotAim._breed_override_for("renegade_executor"))
		end)

		it("returns nil for a breed with no override", function()
			assert.is_nil(WeakspotAim._breed_override_for("chaos_ogryn_gunner"))
		end)
	end)

	describe("apply_override", function()
		it("overrides aim_at_node and aim_at_node_charged for Mauler", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.equals("j_spine", node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)

		it("leaves scratchpad untouched for unknown breed", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "chaos_ogryn_gunner" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("is a no-op when the feature gate is disabled", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return false
				end,
			})

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)

			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})
		end)

		it("logs the override decision when debug is enabled", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local log_entries = {}
			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function(key, _t, msg)
					log_entries[#log_entries + 1] = { key = key, msg = msg }
				end,
				debug_enabled = function()
					return true
				end,
				is_enabled = function()
					return true
				end,
			})

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			WeakspotAim.apply_override("target_unit_a", scratchpad, "bot_unit_a")

			assert.equals(1, #log_entries)
			assert.matches("target_unit_a", log_entries[1].key)
			assert.matches("bot_unit_a", log_entries[1].key)
			assert.matches("j_spine", log_entries[1].msg)
			assert.matches("renegade_executor", log_entries[1].msg)

			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})
		end)

		it("logs once when a configured weakspot node is missing at runtime", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return false
				end,
			}

			local log_entries = {}
			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function(key, _t, msg)
					log_entries[#log_entries + 1] = { key = key, msg = msg }
				end,
				debug_enabled = function()
					return true
				end,
				is_enabled = function()
					return true
				end,
			})

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			assert.is_nil(WeakspotAim.apply_override("target_unit", scratchpad, "bot_unit"))
			assert.is_nil(WeakspotAim.apply_override("target_unit", scratchpad, "bot_unit"))

			assert.equals(1, #log_entries)
			assert.matches("missing_node", log_entries[1].key)
			assert.matches("renegade_executor", log_entries[1].key)
			assert.matches("j_spine", log_entries[1].msg)
		end)

		it("restores the vanilla baseline when the action starts on a Mauler (in-game enter order)", function()
			-- In-game, `BtBotShootAction.enter` sets scratchpad.aim_at_node to
			-- the vanilla pick and then calls `_set_new_aim_target` BEFORE
			-- returning. Our hook_safe on _set_new_aim_target fires first (inside
			-- enter), so the override stomps the vanilla pick before any enter
			-- post-hook could run. Baseline must therefore be captured lazily on
			-- the first apply_override call, before any mutation.
			local breed_name = "renegade_executor"
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = breed_name }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			WeakspotAim.apply_override("mauler_unit_a", scratchpad)
			assert.equals("j_spine", scratchpad.aim_at_node)

			breed_name = "chaos_ogryn_gunner"
			local node = WeakspotAim.apply_override("gunner_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_head", scratchpad.aim_at_node, "must restore vanilla baseline, not overridden j_spine")
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("keeps override state isolated across bots with different targets", function()
			local breeds_by_unit = {
				mauler_unit = { name = "renegade_executor" },
				gunner_unit = { name = "chaos_ogryn_gunner" },
			}

			_G.ScriptUnit = {
				has_extension = function(unit)
					return {
						breed = function()
							return breeds_by_unit[unit]
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local scratchpad_a = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			local scratchpad_b = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }

			WeakspotAim.apply_override("mauler_unit", scratchpad_a)
			WeakspotAim.apply_override("gunner_unit", scratchpad_b)

			assert.equals("j_spine", scratchpad_a.aim_at_node)
			assert.equals("j_head", scratchpad_b.aim_at_node)

			WeakspotAim.apply_override("gunner_unit", scratchpad_a)

			assert.equals("j_head", scratchpad_a.aim_at_node)
			assert.equals("j_head", scratchpad_b.aim_at_node)
		end)

		it("skips override when the target rig is missing the node", function()
			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function(_unit, node)
					return node == "j_head"
				end,
			}

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("provisionally overrides to j_head for Crusher when the bot is behind the target", function()
			install_bulwark_math_globals()

			local crusher_breed = { name = "chaos_ogryn_executor" }

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(crusher_breed)
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, -10, 0) },
			}
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.equals("j_head", node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("does not override Crusher when the bot is in front of the target", function()
			install_bulwark_math_globals()

			local crusher_breed = { name = "chaos_ogryn_executor" }

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(crusher_breed)
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, 10, 0) },
			}
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)

		it("restores the baseline when Crusher rear exposure disappears", function()
			install_bulwark_math_globals()

			local crusher_breed = { name = "chaos_ogryn_executor" }

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(crusher_breed)
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, -10, 0) },
			}

			WeakspotAim.apply_override("target_unit", scratchpad)
			assert.equals("j_head", scratchpad.aim_at_node)

			scratchpad.first_person_component.position = vec(0, 10, 0)
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)

		it("overrides to j_head for Bulwark when the bot is outside the shield blocking angle", function()
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local shield_extension = {
				is_blocking = function()
					return true
				end,
			}

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return shield_extension
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(-10, 0, 0) },
			}
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.equals("j_head", node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("overrides to j_head for Bulwark when the shield is open", function()
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local shield_extension = {
				is_blocking = function()
					return false
				end,
			}

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return shield_extension
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, 10, 0) },
			}
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.equals("j_head", node)
			assert.equals("j_head", scratchpad.aim_at_node)
			assert.equals("j_head", scratchpad.aim_at_node_charged)
		end)

		it("logs once when the Bulwark shield API is missing", function()
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local log_entries = {}

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return {}
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}
			WeakspotAim.init({
				mod = { echo = function() end },
				debug_log = function(key, _t, msg)
					log_entries[#log_entries + 1] = { key = key, msg = msg }
				end,
				debug_enabled = function()
					return true
				end,
				is_enabled = function()
					return true
				end,
			})

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, 10, 0) },
			}

			assert.is_nil(WeakspotAim.apply_override("target_unit", scratchpad, "bot_unit"))
			assert.is_nil(WeakspotAim.apply_override("target_unit", scratchpad, "bot_unit"))
			assert.equals(1, #log_entries)
			assert.matches("shield_api_missing", log_entries[1].key)
			assert.matches("target_unit", log_entries[1].key)
		end)

		it("restores the vanilla baseline when a Bulwark turns to block the bot from the front again", function()
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local shield_blocking = true

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return {
							is_blocking = function()
								return shield_blocking
							end,
						}
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(-10, 0, 0) },
			}

			WeakspotAim.apply_override("target_unit", scratchpad)
			assert.equals("j_head", scratchpad.aim_at_node)

			scratchpad.first_person_component.position = vec(0, 10, 0)
			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)
	end)

	describe("install_on_shoot_action", function()
		local function make_hook_recorder()
			local hooks = {}
			local mock_mod = {
				hook = function(_self, target, method, handler)
					hooks[#hooks + 1] = { type = "hook", target = target, method = method, handler = handler }
				end,
				hook_safe = function(_self, target, method, handler)
					hooks[#hooks + 1] = { type = "hook_safe", target = target, method = method, handler = handler }
				end,
			}
			return hooks, mock_mod
		end

		it("attaches a _set_new_aim_target post-hook that applies the override", function()
			local hooks, mock_mod = make_hook_recorder()
			WeakspotAim.init({
				mod = mock_mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})

			_G.ScriptUnit = {
				has_extension = function()
					return {
						breed = function()
							return { name = "renegade_executor" }
						end,
					}
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
			}

			local BtBotShootAction = {}
			WeakspotAim.install_on_shoot_action(BtBotShootAction)

			local aim_hook
			for _, h in ipairs(hooks) do
				if h.method == "_set_new_aim_target" then
					aim_hook = h
				end
			end
			assert.is_not_nil(aim_hook, "_set_new_aim_target hook not installed")

			local scratchpad = { aim_at_node = "j_head", aim_at_node_charged = "j_head" }
			aim_hook.handler({}, 0.5, "target_unit", scratchpad, {})
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)

		it("re-evaluates Bulwark exposure while the target stays locked", function()
			local hooks, mock_mod = make_hook_recorder()
			WeakspotAim.init({
				mod = mock_mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local shield_blocking = true

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return {
							is_blocking = function()
								return shield_blocking
							end,
						}
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local BtBotShootAction = {}
			WeakspotAim.install_on_shoot_action(BtBotShootAction)

			local set_new_target_hook
			local reevaluate_hook
			for _, h in ipairs(hooks) do
				if h.method == "_set_new_aim_target" then
					set_new_target_hook = h
				elseif h.method == "_aim_position" then
					reevaluate_hook = h
				end
			end

			assert.is_not_nil(set_new_target_hook)
			assert.is_not_nil(reevaluate_hook, "expected a per-frame reevaluation hook")

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(-10, 0, 0) },
				target_breed = bulwark_breed,
			}

			set_new_target_hook.handler({}, 0.5, "target_unit", scratchpad, {})
			assert.equals("j_head", scratchpad.aim_at_node)

			scratchpad.first_person_component.position = vec(0, 10, 0)
			local seen_node
			reevaluate_hook.handler(function(_self, _unit, live_scratchpad)
				seen_node = live_scratchpad.aim_at_node
				return 0, 0, nil, nil, nil
			end, {}, "bot_unit", scratchpad, {}, 0.016, vec(0, 0, 0), nil, "target_unit")

			assert.equals("j_spine", seen_node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)

		it("is idempotent against double-install (hot reload)", function()
			local hooks, mock_mod = make_hook_recorder()
			WeakspotAim.init({
				mod = mock_mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})

			local BtBotShootAction = {}
			WeakspotAim.install_on_shoot_action(BtBotShootAction)
			WeakspotAim.install_on_shoot_action(BtBotShootAction)

			assert.equals(3, #hooks) -- enter + _set_new_aim_target + _aim_position
		end)

		it("does not own a mod:hook_require registration (weapon_action consolidates)", function()
			-- `bt_bot_shoot_action` is already `hook_require`-owned by weapon_action.lua,
			-- and `BetterBots.lua` raises on duplicate paths. weakspot_aim must not
			-- call mod:hook_require; it should only patch the class it is handed.
			local required_paths = {}
			local mock_mod = {
				hook_require = function(_self, path)
					required_paths[#required_paths + 1] = path
				end,
				hook = function() end,
				hook_safe = function() end,
			}

			WeakspotAim.init({
				mod = mock_mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				is_enabled = function()
					return true
				end,
			})

			WeakspotAim.install_on_shoot_action({})

			assert.equals(0, #required_paths)
		end)
	end)

	describe("bulwark angle handling", function()
		it("returns nil when the bot only differs in vertical position", function()
			install_bulwark_math_globals()

			_G.Unit = {
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local angle = WeakspotAim._target_forward_angle_to_bot("target_unit", {
				first_person_component = { position = vec(0, 0, 5) },
			})

			assert.is_nil(angle)
		end)

		it("does not treat elevated frontal positions as exposed", function()
			install_bulwark_math_globals()

			local bulwark_breed = { name = "chaos_ogryn_bulwark" }
			local shield_extension = {
				is_blocking = function()
					return true
				end,
			}

			_G.ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit ~= "target_unit" then
						return nil
					end
					if system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension(bulwark_breed)
					end
					if system_name == "shield_system" then
						return shield_extension
					end
					return nil
				end,
			}
			_G.Unit = {
				has_node = function()
					return true
				end,
				local_rotation = function()
					return { forward = vec(0, 1, 0) }
				end,
			}
			_G.POSITION_LOOKUP = {
				target_unit = vec(0, 0, 0),
			}

			local scratchpad = {
				aim_at_node = "j_spine",
				aim_at_node_charged = "j_spine",
				first_person_component = { position = vec(0, 1, 10) },
			}

			local node = WeakspotAim.apply_override("target_unit", scratchpad)

			assert.is_nil(node)
			assert.equals("j_spine", scratchpad.aim_at_node)
			assert.equals("j_spine", scratchpad.aim_at_node_charged)
		end)
	end)
end)
