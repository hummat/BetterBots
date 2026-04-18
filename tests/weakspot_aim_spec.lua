local saved_script_unit = rawget(_G, "ScriptUnit")
local saved_unit = rawget(_G, "Unit")

local WeakspotAim = dofile("scripts/mods/BetterBots/weakspot_aim.lua")

describe("weakspot_aim", function()
	after_each(function()
		_G.ScriptUnit = saved_script_unit
		_G.Unit = saved_unit
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
			WeakspotAim.apply_override("target_unit_a", scratchpad)

			assert.equals(1, #log_entries)
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
	end)

	describe("install_on_shoot_action", function()
		local function make_hook_recorder()
			local hooks = {}
			local mock_mod = {
				hook_safe = function(_self, target, method, handler)
					hooks[#hooks + 1] = { target = target, method = method, handler = handler }
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

			assert.equals(1, #hooks) -- one _set_new_aim_target hook, not two
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
end)
