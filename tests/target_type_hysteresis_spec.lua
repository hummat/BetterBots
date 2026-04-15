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

local function run_hooked_selection(opts)
	opts = opts or {}

	local RuntimeHysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")
	local saved_require = require
	local saved_script_unit = _G.ScriptUnit
	local saved_vector3 = _G.Vector3
	local saved_position_lookup = _G.POSITION_LOOKUP
	local saved_health_alive = _G.HEALTH_ALIVE
	local target_selection_template
	local warnings = {}
	local debug_logs = {}
	local perf_tags = {}
	local perf_token = 0
	local bot_selection = opts.bot_selection or {}
	local enabled = opts.is_enabled

	target_selection_template = {
		bot_default = function(
			_unit,
			_unit_position,
			_side,
			perception_component,
			_behavior_component,
			_breed,
			_target_units,
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

		return saved_require(path)
	end)

	_G.ScriptUnit = {
		has_extension = function(unit, system_name)
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
			hook_require = function(_, path, callback)
				if
					path
					== "scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template"
				then
					callback(target_selection_template)
				end
			end,
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
	})

	RuntimeHysteresis.register_hooks()

	local perception_component = {
		target_enemy = opts.previous_target_enemy,
		target_enemy_type = opts.previous_target_type or "melee",
		target_enemy_reevaluation_t = opts.previous_reevaluation_t or 0,
		target_ally = nil,
	}
	local invoke_count = opts.repeat_calls or 1

	for _ = 1, invoke_count do
		target_selection_template.bot_default(
			"bot_1",
			{ x = 0, y = 0, z = 0 },
			{ aggroed_minion_target_units = { target_1 = true } },
			perception_component,
			{
				melee_gestalt = "linesman",
				ranged_gestalt = "killshot",
			},
			nil,
			{ "target_1" },
			opts.t or 1,
			{},
			{},
			nil
		)
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
		local saved_require = require
		local saved_script_unit = _G.ScriptUnit
		local saved_vector3 = _G.Vector3
		local saved_position_lookup = _G.POSITION_LOOKUP
		local saved_health_alive = _G.HEALTH_ALIVE
		local target_selection_template
		local perf_tags = {}
		local perf_token = 0

		target_selection_template = {
			bot_default = function(
				_unit,
				_unit_position,
				_side,
				perception_component,
				_behavior_component,
				_breed,
				_target_units,
				t
			)
				perception_component.target_enemy = "target_1"
				perception_component.target_enemy_distance = 2
				perception_component.target_enemy_type = "ranged"
				perception_component.target_enemy_reevaluation_t = t
			end,
		}

		rawset(_G, "require", function(path)
			if path == "scripts/utilities/bot_target_selection" then
				return {
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
		end)

		_G.ScriptUnit = {
			has_extension = function(unit, system_name)
				if unit == "target_1" and system_name == "unit_data_system" then
					return test_helper.make_minion_unit_data_extension({
						name = "renegade_gunner",
						not_bot_target = false,
					})
				end
			end,
		}
		_G.Vector3 = {
			distance_squared = function()
				return 4
			end,
		}
		_G.POSITION_LOOKUP = {
			target_1 = { x = 1, y = 0, z = 0 },
		}
		_G.HEALTH_ALIVE = {
			target_1 = true,
		}

		Hysteresis.init({
			mod = {
				hook_require = function(_, path, callback)
					if
						path
						== "scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template"
					then
						callback(target_selection_template)
					end
				end,
				warning = function() end,
			},
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 5
			end,
			is_enabled = function()
				return true
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
		})

		Hysteresis.register_hooks()
		target_selection_template.bot_default(
			"bot_1",
			{ x = 0, y = 0, z = 0 },
			{ aggroed_minion_target_units = { target_1 = true } },
			{
				target_enemy = nil,
				target_enemy_type = "melee",
				target_enemy_reevaluation_t = 0,
				target_ally = nil,
			},
			{
				melee_gestalt = "linesman",
				ranged_gestalt = "killshot",
			},
			nil,
			{ "target_1" },
			1,
			{},
			{},
			nil
		)

		rawset(_G, "require", saved_require)
		_G.ScriptUnit = saved_script_unit
		_G.Vector3 = saved_vector3
		_G.POSITION_LOOKUP = saved_position_lookup
		_G.HEALTH_ALIVE = saved_health_alive

		assert.equals(1, #perf_tags)
		assert.equals("target_type_hysteresis.post_process", perf_tags[1].tag)
		assert.equals(1, perf_tags[1].token)
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
end)
