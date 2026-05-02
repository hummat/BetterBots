local Debug = dofile("scripts/mods/BetterBots/debug.lua")

describe("debug", function()
	local debug_logs
	local saved_script_unit
	local saved_managers

	before_each(function()
		debug_logs = {}
		saved_script_unit = rawget(_G, "ScriptUnit")
		saved_managers = rawget(_G, "Managers")

		Debug.init({
			mod = { command = function() end, echo = function() end, dump = function() end },
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			equipped_combat_ability_name = function()
				return "unknown"
			end,
			fallback_state_by_unit = {},
			last_charge_event_by_unit = {},
		})
	end)

	after_each(function()
		_G.ScriptUnit = saved_script_unit
		_G.Managers = saved_managers
	end)

	it("includes hazard state in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			num_nearby = 2,
			health_pct = 0.8,
			toughness_pct = 0.5,
			in_hazard = true,
		})

		assert.is_true(snapshot.in_hazard)
		assert.equals(2, snapshot.num_nearby)
	end)

	it("drops positive infinity target_enemy_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = math.huge,
		})

		assert.is_nil(snapshot.target_enemy_distance)
	end)

	it("drops negative infinity target_ally_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_ally_distance = -math.huge,
		})

		assert.is_nil(snapshot.target_ally_distance)
	end)

	it("drops NaN target_enemy_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = 0 / 0,
		})

		assert.is_nil(snapshot.target_enemy_distance)
	end)

	it("keeps finite target_enemy_distance in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = 15.5,
		})

		assert.equals(15.5, snapshot.target_enemy_distance)
	end)

	it("includes daemonhost dormancy diagnostics in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_is_dormant_daemonhost = true,
			target_is_near_dormant_daemonhost = true,
			target_daemonhost_aggro_state = "passive",
		})

		assert.is_true(snapshot.target_is_dormant_daemonhost)
		assert.is_true(snapshot.target_is_near_dormant_daemonhost)
		assert.equals("passive", snapshot.target_daemonhost_aggro_state)
	end)

	it("logs the selected combat utility branch and leaf when diagnostics are enabled", function()
		local captured_hook
		Debug.init({
			mod = {
				command = function() end,
				echo = function() end,
				dump = function() end,
				hook = function(_, target, method, handler)
					captured_hook = handler
					target[method] = handler
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
				return 12
			end,
			equipped_combat_ability_name = function()
				return "unknown"
			end,
			fallback_state_by_unit = {},
			last_charge_event_by_unit = {},
		})
		Debug.wire({
			enemy_breed = function(unit)
				return unit == "target_1" and { name = "renegade_rifleman" } or nil
			end,
		})
		_G.Managers = {
			player = {
				players = function()
					return {
						{
							player_unit = "bot_1",
							is_human_controlled = function()
								return false
							end,
							slot = function()
								return 3
							end,
						},
					}
				end,
			},
		}
		_G.ScriptUnit = {
			has_extension = function(unit, extension_name)
				if unit ~= "bot_1" or extension_name ~= "unit_data_system" then
					return nil
				end

				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_secondary" }
						end
						if component_name == "weapon_action" then
							return { template_name = "plasmagun_p1_m1" }
						end

						return nil
					end,
				}
			end,
		}

		local BtRandomUtilityNode = {}
		Debug.install_combat_utility_diagnostics(BtRandomUtilityNode)
		assert.is_function(captured_hook)

		local self_node = {
			identifier = "in_combat_node",
			tree_node = { name = "in_combat" },
			_action_list = {
				{ name = "combat", utility_score = 0.75 },
				{ name = "follow", utility_score = 0.25 },
			},
		}
		local branch_node = { tree_node = { name = "combat" } }
		local leaf_node = { tree_node = { name = "shoot" } }
		local new_running_child_nodes = {}
		local function original(_, _, _, _, _, _, _, _, _, new_running)
			new_running.in_combat_node = branch_node
			return leaf_node
		end

		local returned = captured_hook(original, self_node, "bot_1", {
			perception = {
				target_enemy = "target_1",
				target_enemy_type = "ranged",
				target_enemy_distance = 9,
				target_ally_distance = 14,
			},
		}, nil, 0.03, 12, true, {}, {}, new_running_child_nodes, false)

		assert.equals(leaf_node, returned)
		assert.equals(1, #debug_logs)
		assert.matches("combat utility selected combat/shoot", debug_logs[1].message, 1, true)
		assert.matches("scores=combat=0.75,follow=0.25", debug_logs[1].message, 1, true)
		assert.matches("target=renegade_rifleman", debug_logs[1].message, 1, true)
		assert.matches("weapon=slot_secondary/plasmagun_p1_m1", debug_logs[1].message, 1, true)
	end)

	it("does not log idle follow utility selections without a combat target", function()
		local captured_hook
		Debug.init({
			mod = {
				command = function() end,
				echo = function() end,
				dump = function() end,
				hook = function(_, target, method, handler)
					captured_hook = handler
					target[method] = handler
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
				return 12
			end,
			equipped_combat_ability_name = function()
				return "unknown"
			end,
			fallback_state_by_unit = {},
			last_charge_event_by_unit = {},
		})

		local BtRandomUtilityNode = {}
		Debug.install_combat_utility_diagnostics(BtRandomUtilityNode)
		assert.is_function(captured_hook)
		_G.ScriptUnit = {
			has_extension = function()
				return nil
			end,
		}

		local self_node = {
			identifier = "in_combat_node",
			tree_node = { name = "in_combat" },
			_action_list = {
				{ name = "follow", utility_score = 0.12 },
				{ name = "combat", utility_score = 0 },
			},
		}
		local branch_node = { tree_node = { name = "follow" } }
		local leaf_node = { tree_node = { name = "successful_follow" } }
		local new_running_child_nodes = {}
		local function original(_, _, _, _, _, _, _, _, _, new_running)
			new_running.in_combat_node = branch_node
			return leaf_node
		end

		local returned = captured_hook(original, self_node, "bot_1", {
			perception = {
				target_enemy = nil,
				target_enemy_type = nil,
			},
		}, nil, 0.03, 12, true, {}, {}, new_running_child_nodes, false)

		assert.equals(leaf_node, returned)
		assert.equals(0, #debug_logs)
	end)

	it("installs combat utility diagnostics only once per engine class table", function()
		local hook_count = 0
		Debug.init({
			mod = {
				command = function() end,
				echo = function() end,
				dump = function() end,
				hook = function()
					hook_count = hook_count + 1
				end,
			},
			debug_log = function() end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 0
			end,
			equipped_combat_ability_name = function()
				return "unknown"
			end,
			fallback_state_by_unit = {},
			last_charge_event_by_unit = {},
		})

		local BtRandomUtilityNode = {}
		Debug.install_combat_utility_diagnostics(BtRandomUtilityNode)
		Debug.install_combat_utility_diagnostics(BtRandomUtilityNode)

		assert.equals(1, hook_count)
	end)
end)
