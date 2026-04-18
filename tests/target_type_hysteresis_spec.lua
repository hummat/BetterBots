local test_helper = require("tests.test_helper")
local Hysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")

local function find_debug_log(logs, fragment)
	for i = 1, #logs do
		if logs[i].message:find(fragment, 1, true) then
			return logs[i]
		end
	end

	return nil
end

local function with_global_overrides(overrides, callback)
	local saved = {}
	local keys = {}

	for key, value in pairs(overrides) do
		saved[key] = rawget(_G, key)
		keys[#keys + 1] = key
		rawset(_G, key, value)
	end

	local ok, result_or_err = xpcall(callback, debug.traceback)

	for i = 1, #keys do
		local key = keys[i]
		rawset(_G, key, saved[key])
	end

	if not ok then
		error(result_or_err, 0)
	end

	return result_or_err
end

describe("target_type_hysteresis test helpers", function()
	it("restores globals after the callback throws", function()
		local original_require = require
		local original_script_unit = _G.ScriptUnit
		local original_vector3 = _G.Vector3
		local original_position_lookup = _G.POSITION_LOOKUP
		local original_health_alive = _G.HEALTH_ALIVE

		local ok, err = pcall(function()
			with_global_overrides({
				require = function()
					return nil
				end,
				ScriptUnit = { fake = true },
				Vector3 = { fake = true },
				POSITION_LOOKUP = { fake = true },
				HEALTH_ALIVE = { fake = true },
			}, function()
				error("boom")
			end)
		end)

		assert.is_false(ok)
		assert.matches("boom", tostring(err))
		assert.equals(original_require, require)
		assert.equals(original_script_unit, _G.ScriptUnit)
		assert.equals(original_vector3, _G.Vector3)
		assert.equals(original_position_lookup, _G.POSITION_LOOKUP)
		assert.equals(original_health_alive, _G.HEALTH_ALIVE)
	end)
end)

local function run_hooked_selection(opts)
	opts = opts or {}

	local RuntimeHysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")
	local saved_require = require
	local saved_script_unit = _G.ScriptUnit
	local saved_vector3 = _G.Vector3
	local saved_position_lookup = _G.POSITION_LOOKUP
	local saved_health_alive = _G.HEALTH_ALIVE
	local warnings = {}
	local debug_logs = {}
	local perf_tags = {}
	local perf_token = 0
	local bot_selection = opts.bot_selection or {}
	local enabled = opts.is_enabled
	local bot_perception_extension = {
		_threat_units = opts.threat_units or {},
		_update_target_enemy = function(
			_self,
			_self_unit,
			_self_position,
			perception_component,
			_behavior_component,
			_enemies_in_proximity,
			_side,
			_bot_group,
			_dt,
			t
		)
			perception_component.target_enemy = opts.vanilla_target_enemy or "target_1"
			perception_component.target_enemy_distance = opts.vanilla_target_enemy_distance or 2
			perception_component.target_enemy_type = opts.vanilla_target_type or "ranged"
			perception_component.target_enemy_reevaluation_t = opts.vanilla_reevaluation_t or t
		end,
	}

	rawset(_G, "require", function(path)
		if path == "scripts/utilities/bot_target_selection" then
			return {
				opportunity_weight = bot_selection.opportunity_weight or function()
					return 0
				end,
				priority_weight = bot_selection.priority_weight or function()
					return 0
				end,
				monster_weight = bot_selection.monster_weight or function()
					return 0
				end,
				current_target_weight = bot_selection.current_target_weight or function()
					return 0
				end,
				gestalt_weight = bot_selection.gestalt_weight or function()
					return 0
				end,
				slot_weight = bot_selection.slot_weight or function()
					return 0
				end,
				melee_distance_weight = bot_selection.melee_distance_weight or function()
					return 0
				end,
				ranged_distance_weight = bot_selection.ranged_distance_weight or function()
					return 0
				end,
				line_of_sight_weight = bot_selection.line_of_sight_weight or function()
					return 0
				end,
			}
		end

		if path == "scripts/utilities/breed" then
			return {
				is_player = function()
					return false
				end,
			}
		end

		if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
			return {
				weapon_template_from_slot = function(_visual_loadout_extension, slot_name)
					if slot_name == "slot_secondary" then
						return opts.bot_secondary_weapon_template
					end

					return nil
				end,
			}
		end

		return saved_require(path)
	end)

	_G.ScriptUnit = {
		has_extension = function(unit, system_name)
			if unit == "bot_1" and system_name == "unit_data_system" then
				return test_helper.make_player_unit_data_extension({
					inventory = { wielded_slot = opts.bot_wielded_slot or "slot_secondary" },
				})
			end

			if unit == "bot_1" and system_name == "visual_loadout_system" then
				return { unit = unit }
			end

			if unit == "target_1" and system_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension(opts.target_breed or {
					name = "renegade_gunner",
					not_bot_target = false,
				})
			end
		end,
	}
	_G.Vector3 = {
		distance_squared = function()
			return opts.target_distance_sq or 4
		end,
	}
	_G.POSITION_LOOKUP = {
		target_1 = { x = 1, y = 0, z = 0 },
	}
	_G.HEALTH_ALIVE = {
		target_1 = opts.target_alive ~= false,
	}

	RuntimeHysteresis.init({
		mod = {
			hook_require = function() end,
			hook = function(_, target, method_name, handler)
				local original = assert(target[method_name], "missing hook target method")
				target[method_name] = function(...)
					return handler(original, ...)
				end
			end,
			hook_safe = function() end,
			warning = function(_, message)
				warnings[#warnings + 1] = message
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
			return opts.debug_enabled == true
		end,
		fixed_time = function()
			return opts.fixed_t or opts.t or 0
		end,
		is_enabled = function()
			return enabled ~= false
		end,
		perf = {
			begin = function()
				perf_token = perf_token + 1
				return perf_token
			end,
			finish = function(tag, token)
				perf_tags[#perf_tags + 1] = { tag = tag, token = token }
			end,
		},
		close_range_ranged_policy = opts.close_range_ranged_policy or function(weapon_template)
			local keywords = weapon_template and weapon_template.keywords or {}
			for i = 1, #keywords do
				if keywords[i] == "flamer" then
					return {
						family = "flamer",
						hold_ranged_target_distance_sq = 100,
						hipfire_distance_sq = 100,
					}
				end
			end

			return nil
		end,
	})

	RuntimeHysteresis.install_bot_perception_hooks(bot_perception_extension)

	local perception_component = {
		target_enemy = opts.previous_target_enemy,
		target_enemy_type = opts.previous_target_type or "melee",
		target_enemy_reevaluation_t = opts.previous_reevaluation_t or 0,
		target_ally = nil,
	}
	local invoke_count = opts.repeat_calls or 1
	local side = {
		aggroed_minion_target_units = { target_1 = true },
		ai_target_units = { "target_1" },
	}

	for _ = 1, invoke_count do
		bot_perception_extension:_update_target_enemy("bot_1", { x = 0, y = 0, z = 0 }, perception_component, {
			melee_gestalt = "linesman",
			ranged_gestalt = "killshot",
		}, {}, side, {}, 0, opts.t or 1)
	end

	rawset(_G, "require", saved_require)
	_G.ScriptUnit = saved_script_unit
	_G.Vector3 = saved_vector3
	_G.POSITION_LOOKUP = saved_position_lookup
	_G.HEALTH_ALIVE = saved_health_alive

	return {
		perception_component = perception_component,
		warnings = warnings,
		debug_logs = debug_logs,
		perf_tags = perf_tags,
	}
end

local function run_inventory_switch_enter_hook(opts)
	opts = opts or {}

	local RuntimeHysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")
	local saved_script_unit = _G.ScriptUnit
	local debug_logs = {}
	local inventory_switch_action = {
		enter = function(_self, _unit, _breed, _blackboard, scratchpad)
			scratchpad.inventory_component = {
				wielded_slot = opts.wielded_slot or "slot_secondary",
			}
		end,
	}

	_G.ScriptUnit = {
		extension = function(unit, system_name)
			if unit == "bot_1" and system_name == "unit_data_system" then
				return test_helper.make_player_unit_data_extension({
					inventory = { wielded_slot = opts.wielded_slot or "slot_secondary" },
				})
			end
		end,
	}

	RuntimeHysteresis.init({
		mod = {
			hook_require = function(_, path, callback)
				if path == "scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_inventory_switch_action" then
					callback(inventory_switch_action)
				end
			end,
			hook_safe = function(_, target, method_name, handler)
				local original = target[method_name]
				target[method_name] = function(...)
					local result = original(...)
					handler(...)
					return result
				end
			end,
			warning = function() end,
		},
		debug_log = function(key, fixed_t, message)
			debug_logs[#debug_logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
			}
		end,
		debug_enabled = function()
			return opts.debug_enabled ~= false
		end,
		fixed_time = function()
			return opts.fixed_t or 0
		end,
		is_enabled = function()
			return true
		end,
		bot_slot_for_unit = function()
			return opts.bot_slot or 4
		end,
	})

	RuntimeHysteresis.register_hooks()
	inventory_switch_action.enter(
		{},
		"bot_1",
		nil,
		{ perception = { target_enemy_type = opts.target_type or "melee" } },
		{},
		{ wanted_slot = opts.wanted_slot or "slot_primary" },
		opts.t or 3
	)

	_G.ScriptUnit = saved_script_unit

	return debug_logs
end

describe("target_type_hysteresis", function()
	it("uses raw winner when current type is none", function()
		local chosen = Hysteresis.choose_target_type("none", 12, 8)
		assert.equals("melee", chosen)
	end)

	it("keeps current melee type on close scores", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.4)
		assert.equals("melee", chosen)
	end)

	it("keeps current ranged type on close scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 10.4, 10)
		assert.equals("ranged", chosen)
	end)

	it("flips when the opposite type wins by more than the margin", function()
		local chosen = Hysteresis.choose_target_type("ranged", 14, 10)
		assert.equals("melee", chosen)
	end)

	it("applies momentum bonus to the current type", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.49)
		assert.equals("melee", chosen)
	end)

	it("scales margin with larger scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 100, 108)
		assert.equals("ranged", chosen)
	end)

	it("reports when hysteresis suppresses a raw flip", function()
		local analysis = Hysteresis.analyze_target_type_choice("melee", 10, 10.4)

		assert.equals("ranged", analysis.raw_target_enemy_type)
		assert.equals("melee", analysis.chosen_type)
		assert.is_true(analysis.suppressed_raw_flip)
	end)

	it("does not report a suppressed raw flip when the winner clears the margin", function()
		local analysis = Hysteresis.analyze_target_type_choice("ranged", 14, 10)

		assert.equals("melee", analysis.raw_target_enemy_type)
		assert.equals("melee", analysis.chosen_type)
		assert.is_false(analysis.suppressed_raw_flip)
	end)

	it("records perf timing around post-process target-type stabilization", function()
		local result = run_hooked_selection({
			t = 1,
			bot_selection = {
				opportunity_weight = function()
					return 3
				end,
				priority_weight = function()
					return 2
				end,
				monster_weight = function()
					return 0
				end,
				current_target_weight = function()
					return 1
				end,
				gestalt_weight = function(_, _, breed)
					return breed.name == "renegade_gunner" and 10 or 0
				end,
				slot_weight = function()
					return 1
				end,
				melee_distance_weight = function()
					return 3
				end,
				ranged_distance_weight = function()
					return 9
				end,
				line_of_sight_weight = function()
					return 4
				end,
			},
		})

		assert.equals(1, #result.perf_tags)
		assert.equals("target_type_hysteresis.post_process", result.perf_tags[1].tag)
		assert.equals(1, result.perf_tags[1].token)
	end)

	it("handles near-zero and asymmetric score pairs", function()
		local cases = {
			{ current = "melee", melee = 0, ranged = 0, chosen = "melee" },
			{ current = "ranged", melee = 0, ranged = 0, chosen = "ranged" },
			{ current = "ranged", melee = 0.5, ranged = -0.5, chosen = "melee" },
			{ current = "ranged", melee = 50, ranged = 49, chosen = "ranged" },
			{ current = "melee", melee = 50, ranged = -50, chosen = "melee" },
		}

		for i = 1, #cases do
			local case = cases[i]
			assert.equals(case.chosen, Hysteresis.choose_target_type(case.current, case.melee, case.ranged))
		end
	end)

	it("holds the previous type and refreshes reevaluation when hysteresis suppresses a raw flip", function()
		local result = run_hooked_selection({
			t = 1,
			debug_enabled = true,
			previous_target_type = "melee",
			previous_reevaluation_t = 0,
			bot_selection = {
				slot_weight = function()
					return 10
				end,
				ranged_distance_weight = function()
					return 10.4
				end,
			},
		})

		assert.equals("target_1", result.perception_component.target_enemy)
		assert.equals("melee", result.perception_component.target_enemy_type)
		assert.equals(2, result.perception_component.target_enemy_distance)
		assert.equals(1.3, result.perception_component.target_enemy_reevaluation_t)
		assert.is_truthy(find_debug_log(result.debug_logs, "type hold melee over raw ranged"))
	end)

	it("preserves ranged targeting for close-range flamer families under melee pressure", function()
		local result = run_hooked_selection({
			t = 1,
			previous_target_type = "ranged",
			target_distance_sq = 25,
			bot_secondary_weapon_template = {
				name = "flamer_p1_m1",
				keywords = { "ranged", "flamer", "p1" },
			},
			bot_selection = {
				slot_weight = function()
					return 10
				end,
				melee_distance_weight = function()
					return 8
				end,
				ranged_distance_weight = function()
					return 0
				end,
				line_of_sight_weight = function()
					return 0
				end,
			},
		})

		assert.equals("ranged", result.perception_component.target_enemy_type)
	end)

	it("eagerly patches an already-loaded BotPerceptionExtension", function()
		local RuntimeHysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")
		local saved_require = require
		local bot_perception_extension = {
			_threat_units = {},
			_update_target_enemy = function(
				_self,
				_self_unit,
				_self_position,
				perception_component,
				_behavior_component,
				_enemies_in_proximity,
				_side,
				_bot_group,
				_dt,
				t
			)
				perception_component.target_enemy = "target_1"
				perception_component.target_enemy_distance = 2
				perception_component.target_enemy_type = "ranged"
				perception_component.target_enemy_reevaluation_t = t
			end,
		}

		with_global_overrides({
			require = function(path)
				if path == "scripts/extension_systems/perception/bot_perception_extension" then
					return bot_perception_extension
				end

				if path == "scripts/utilities/bot_target_selection" then
					return {
						opportunity_weight = function()
							return 0
						end,
						priority_weight = function()
							return 0
						end,
						monster_weight = function()
							return 0
						end,
						current_target_weight = function()
							return 0
						end,
						gestalt_weight = function()
							return 0
						end,
						slot_weight = function()
							return 10
						end,
						melee_distance_weight = function()
							return 0
						end,
						ranged_distance_weight = function()
							return 10.4
						end,
						line_of_sight_weight = function()
							return 0
						end,
					}
				end

				if path == "scripts/utilities/breed" then
					return {
						is_player = function()
							return false
						end,
					}
				end

				return saved_require(path)
			end,
			ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit == "target_1" and system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension({
							name = "renegade_gunner",
							not_bot_target = false,
						})
					end
				end,
			},
			Vector3 = {
				distance_squared = function()
					return 4
				end,
			},
			POSITION_LOOKUP = {
				target_1 = { x = 1, y = 0, z = 0 },
			},
			HEALTH_ALIVE = {
				target_1 = true,
			},
		}, function()
			RuntimeHysteresis.init({
				mod = {
					hook_require = function() end,
					hook = function(_, target, method_name, handler)
						local original = assert(target[method_name], "missing hook target method")
						target[method_name] = function(...)
							return handler(original, ...)
						end
					end,
					hook_safe = function() end,
					warning = function() end,
				},
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 1
				end,
				is_enabled = function()
					return true
				end,
			})

			RuntimeHysteresis.install_bot_perception_hooks(bot_perception_extension)

			local perception_component = {
				target_enemy = nil,
				target_enemy_type = "melee",
				target_enemy_reevaluation_t = 0,
				target_ally = nil,
			}

			bot_perception_extension:_update_target_enemy("bot_1", { x = 0, y = 0, z = 0 }, perception_component, {
				melee_gestalt = "linesman",
				ranged_gestalt = "killshot",
			}, {}, {
				aggroed_minion_target_units = { target_1 = true },
				ai_target_units = { "target_1" },
			}, {}, 0, 1)

			assert.equals("melee", perception_component.target_enemy_type)
		end)
	end)

	it("hooks BotPerceptionExtension._update_target_enemy for post-process stabilization", function()
		local RuntimeHysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")
		local saved_require = require
		local bot_perception_extension = {
			_update_target_enemy = function(
				_self,
				_self_unit,
				_self_position,
				perception_component,
				_behavior_component,
				_enemies_in_proximity,
				_side,
				_bot_group,
				_dt,
				t
			)
				perception_component.target_enemy = "target_1"
				perception_component.target_enemy_distance = 2
				perception_component.target_enemy_type = "ranged"
				perception_component.target_enemy_reevaluation_t = t
			end,
		}

		with_global_overrides({
			require = function(path)
				if path == "scripts/utilities/bot_target_selection" then
					return {
						opportunity_weight = function()
							return 0
						end,
						priority_weight = function()
							return 0
						end,
						monster_weight = function()
							return 0
						end,
						current_target_weight = function()
							return 0
						end,
						gestalt_weight = function()
							return 0
						end,
						slot_weight = function()
							return 10
						end,
						melee_distance_weight = function()
							return 0
						end,
						ranged_distance_weight = function()
							return 10.4
						end,
						line_of_sight_weight = function()
							return 0
						end,
					}
				end

				if path == "scripts/utilities/breed" then
					return {
						is_player = function()
							return false
						end,
					}
				end

				return saved_require(path)
			end,
			ScriptUnit = {
				has_extension = function(unit, system_name)
					if unit == "target_1" and system_name == "unit_data_system" then
						return test_helper.make_minion_unit_data_extension({
							name = "renegade_gunner",
							not_bot_target = false,
						})
					end
				end,
			},
			Vector3 = {
				distance_squared = function()
					return 4
				end,
			},
			POSITION_LOOKUP = {
				target_1 = { x = 1, y = 0, z = 0 },
			},
			HEALTH_ALIVE = {
				target_1 = true,
			},
		}, function()
			RuntimeHysteresis.init({
				mod = {
					hook_require = function() end,
					hook = function(_, target, method_name, handler)
						local original = assert(target[method_name], "missing hook target method")
						target[method_name] = function(...)
							return handler(original, ...)
						end
					end,
					hook_safe = function() end,
					warning = function() end,
				},
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 1
				end,
				is_enabled = function()
					return true
				end,
				perf = {
					begin = function()
						return 1
					end,
					finish = function() end,
				},
			})

			RuntimeHysteresis.install_bot_perception_hooks(bot_perception_extension)

			local perception_component = {
				target_enemy = nil,
				target_enemy_type = "melee",
				target_enemy_reevaluation_t = 0,
				target_ally = nil,
			}

			bot_perception_extension:_update_target_enemy("bot_1", { x = 0, y = 0, z = 0 }, perception_component, {
				melee_gestalt = "linesman",
				ranged_gestalt = "killshot",
			}, {}, {
				aggroed_minion_target_units = { target_1 = true },
				ai_target_units = { "target_1" },
			}, {}, 0, 1)

			assert.equals("melee", perception_component.target_enemy_type)
		end)
	end)

	it("warns once when post-process scoring fails and leaves the vanilla result intact", function()
		local result = run_hooked_selection({
			t = 2,
			previous_target_type = "melee",
			repeat_calls = 2,
			bot_selection = {
				gestalt_weight = function()
					error("boom")
				end,
			},
		})

		assert.equals(1, #result.warnings)
		assert.is_truthy(result.warnings[1]:find("boom", 1, true))
		assert.equals("target_1", result.perception_component.target_enemy)
		assert.equals("ranged", result.perception_component.target_enemy_type)
		assert.equals(2, result.perception_component.target_enemy_reevaluation_t)
	end)

	it("logs actual inventory switch entry for melee target-type correction", function()
		local debug_logs = run_inventory_switch_enter_hook({
			target_type = "melee",
			wanted_slot = "slot_primary",
			wielded_slot = "slot_secondary",
			bot_slot = 4,
			fixed_t = 7,
		})

		local log = find_debug_log(debug_logs, "switch_melee entered")
		assert.is_truthy(log)
		assert.equals("inventory_switch_enter:bot_1", log.key)
		assert.is_truthy(log.message:find("bot 4", 1, true))
		assert.is_truthy(log.message:find("wielded=slot_secondary", 1, true))
		assert.is_truthy(log.message:find("wanted=slot_primary", 1, true))
	end)
end)
