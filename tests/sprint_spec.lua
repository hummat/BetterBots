-- Mock engine globals before loading the sprint module
local test_helper = require("tests.test_helper")

local _extensions = {}
local _positions = {}
local _alive = {}
local _unit_alive = {}
local _saved_globals = {}
local Sprint
local _spawned_minions = {}

-- Mock BLACKBOARDS for daemonhost aggro state detection (#17)
local _blackboards = {}

-- Mock Managers.state.extension:system("side_system") for daemonhost detection
local _mock_side_system = nil

-- Mock time for per-frame caching — increment between tests to bust cache
local _mock_time = 0
local _debug_logs = {}

-- Helper: build a mock BotUnitInput self with _move and _group_extension
local function make_self(opts)
	opts = opts or {}
	return {
		_move = opts.move or { x = 0, y = 1 },
		_group_extension = opts.group_extension or nil,
	}
end

-- Helper: build a position vector
local function pos(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

-- Helper: set up perception extension with enemies
local function setup_perception(unit, enemies)
	local enemy_list = enemies or {}
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].perception_system = test_helper.make_bot_perception_extension({
		enemies = enemy_list,
	})
end

-- Helper: set up behavior extension with blackboard
local function setup_behavior(unit, perception_data)
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].behavior_system = test_helper.make_bot_behavior_extension({
		brain = {
			_blackboard = {
				perception = perception_data or {},
			},
		},
	})
end

-- Helper: set up unit_data extension for a breed
local function setup_breed(unit, breed_name)
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].unit_data_system = test_helper.make_minion_unit_data_extension({ name = breed_name })
end

-- Helper: set up group extension with follow unit
local function make_group_extension(follow_unit)
	return {
		bot_group_data = function()
			return { follow_unit = follow_unit }
		end,
	}
end

-- Helper: set up a mock side system with enemy units for daemonhost detection
local function setup_side_system(bot_unit, enemy_units)
	local bot_side = {
		ai_target_units = enemy_units or {},
		relation_side_names = function()
			return { "enemy" }
		end,
		relation_units = function()
			return enemy_units or {}
		end,
	}
	local enemy_side = {
		ai_target_units = {},
	}
	_mock_side_system = test_helper.make_side_system_double({
		side_by_unit = {
			[bot_unit] = bot_side,
		},
		get_side_from_name = function(_self, _name)
			return enemy_side
		end,
	})
end

local function setup_side_system_with_relation_only_daemonhost(bot_unit, enemy_units)
	local bot_side = {
		ai_target_units = {},
		relation_side_names = function()
			return { "enemy" }
		end,
		relation_units = function()
			return enemy_units or {}
		end,
	}
	_mock_side_system = test_helper.make_side_system_double({
		side_by_unit = {
			[bot_unit] = bot_side,
		},
		get_side_from_name = function()
			return {
				ai_target_units = {},
			}
		end,
	})
end

-- Reset all mocks between tests
local function reset()
	for k in pairs(_extensions) do
		_extensions[k] = nil
	end
	for k in pairs(_positions) do
		_positions[k] = nil
	end
	for k in pairs(_alive) do
		_alive[k] = nil
	end
	for k in pairs(_unit_alive) do
		_unit_alive[k] = nil
	end
	for k in pairs(_blackboards) do
		_blackboards[k] = nil
	end
	for k in pairs(_spawned_minions) do
		_spawned_minions[k] = nil
	end
	_mock_side_system = nil
	_mock_time = _mock_time + 1 -- bust per-frame DH distance cache
	for i = #_debug_logs, 1, -1 do
		_debug_logs[i] = nil
	end
end

describe("sprint", function()
	setup(function()
		_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")
		_saved_globals.POSITION_LOOKUP = rawget(_G, "POSITION_LOOKUP")
		_saved_globals.ALIVE = rawget(_G, "ALIVE")
		_saved_globals.Unit = rawget(_G, "Unit")
		_saved_globals.Vector3 = rawget(_G, "Vector3")
		_saved_globals.Quaternion = rawget(_G, "Quaternion")
		_saved_globals.BLACKBOARDS = rawget(_G, "BLACKBOARDS")
		_saved_globals.Managers = rawget(_G, "Managers")

		_G.ScriptUnit = {
			has_extension = function(unit, system_name)
				local unit_exts = _extensions[unit]
				return unit_exts and unit_exts[system_name] or nil
			end,
		}

		_G.POSITION_LOOKUP = setmetatable({}, {
			__index = function(_, unit)
				return _positions[unit]
			end,
		})

		_G.ALIVE = setmetatable({}, {
			__index = function(_, unit)
				return _alive[unit]
			end,
		})

		_G.Unit = {
			alive = function(unit)
				return _unit_alive[unit] == true
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

		_G.Quaternion = {
			right = function()
				return pos(1, 0, 0)
			end,
			forward = function()
				return pos(0, 1, 0)
			end,
		}

		_G.BLACKBOARDS = setmetatable({}, {
			__index = function(_, unit)
				return _blackboards[unit]
			end,
		})

		_G.Managers = {
			state = {
				extension = {
					system = function(_self, name)
						if name == "side_system" and _mock_side_system then
							return _mock_side_system
						end
						return nil
					end,
				},
				minion_spawn = {
					spawned_minions = function()
						return _spawned_minions
					end,
				},
			},
		}

		Sprint = dofile("scripts/mods/BetterBots/sprint.lua")
		Sprint.init({
			mod = { echo = function() end },
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return _mock_time
			end,
		})
	end)

	teardown(function()
		for k, v in pairs(_saved_globals) do
			rawset(_G, k, v)
		end
	end)

	before_each(function()
		reset()
	end)

	describe("should_sprint", function()
		it("blocks when not moving forward", function()
			local self_obj = make_self({ move = { x = 0, y = 0.3 } })
			local ok, reason = Sprint.should_sprint(self_obj, "bot1", {})
			assert.is_false(ok)
			assert.equals("not_moving_forward", reason)
		end)

		it("blocks when move is nil", function()
			local self_obj = { _move = nil }
			local ok, reason = Sprint.should_sprint(self_obj, "bot1", {})
			assert.is_false(ok)
			assert.equals("not_moving_forward", reason)
		end)

		it("sprints during traversal with no enemies", function()
			local unit = "bot1"
			setup_perception(unit, {})
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)

		it("blocks sprint when enemies nearby", function()
			local unit = "bot1"
			local enemy = "enemy1"
			setup_perception(unit, { enemy })
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("shares daemonhost scan results across bots in the same frame", function()
			local bot1 = "bot1"
			local bot2 = "bot2"
			local daemonhost = "daemonhost"
			local breed_calls = 0

			_positions[bot1] = pos(0, 0, 0)
			_positions[bot2] = pos(10, 0, 0)
			_positions[daemonhost] = pos(30, 0, 0)
			_alive[daemonhost] = true
			setup_breed(daemonhost, "chaos_daemonhost")
			_extensions[daemonhost].unit_data_system = test_helper.make_minion_unit_data_extension(
				{ name = "chaos_daemonhost" },
				{
					breed = function()
						breed_calls = breed_calls + 1
						return { name = "chaos_daemonhost" }
					end,
				}
			)
			local shared_side = {
				ai_target_units = { daemonhost },
				relation_units = function()
					return { daemonhost }
				end,
			}
			_mock_side_system = test_helper.make_side_system_double({
				side_by_unit = {
					[bot1] = shared_side,
					[bot2] = shared_side,
				},
			})

			assert.is_false(Sprint.is_near_daemonhost(bot1))
			assert.is_false(Sprint.is_near_daemonhost(bot2))
			assert.equals(1, breed_calls)
		end)

		it("rescans when bot side changes in the same frame", function()
			-- Pins the shared cache key: two bots on different sides must not
			-- share one cached daemonhost list.
			local bot1 = "bot1"
			local bot2 = "bot2"
			local dh_a = "dh_side_a"
			local dh_b = "dh_side_b"

			_positions[bot1] = pos(0, 0, 0)
			_positions[bot2] = pos(0, 0, 0)
			_positions[dh_a] = pos(5, 0, 0) -- within 20m of both bots
			_positions[dh_b] = pos(30, 0, 0) -- outside 20m of both bots
			_alive[dh_a] = true
			_alive[dh_b] = true
			setup_breed(dh_a, "chaos_daemonhost")
			setup_breed(dh_b, "chaos_daemonhost")

			local side_a = {
				ai_target_units = { dh_a },
				relation_units = function()
					return { dh_a }
				end,
			}
			local side_b = {
				ai_target_units = { dh_b },
				relation_units = function()
					return { dh_b }
				end,
			}
			_mock_side_system = test_helper.make_side_system_double({
				side_by_unit = {
					[bot1] = side_a,
					[bot2] = side_b,
				},
			})

			assert.is_true(Sprint.is_near_daemonhost(bot1))
			assert.is_false(Sprint.is_near_daemonhost(bot2))
		end)

		it("sprints to catch up when far from follow unit", function()
			local unit = "bot1"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(20, 0, 0)
			_alive[follow] = true
			setup_perception(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("catch_up", reason)
		end)

		it("sprints to catch up when ALIVE is missing for a live follow unit", function()
			local unit = "bot1"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(20, 0, 0)
			_unit_alive[follow] = true
			setup_perception(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("catch_up", reason)
		end)

		it("does not catch-up sprint when close to follow unit", function()
			local unit = "bot1"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(5, 0, 0)
			_alive[follow] = true
			setup_perception(unit, {})
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- Close to follow, no enemies -> traversal
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)

		it("sprints to rescue allies", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "knocked_down",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("ally_rescue", reason)
		end)

		it("does not sprint for attention_look ally aid", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "in_need_of_attention_look",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("does not sprint for attention_stop ally aid", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "in_need_of_attention_stop",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("blocks sprint near daemonhost", function()
			local unit = "bot1"
			local dh = "daemonhost1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("daemonhost_nearby", reason)
		end)

		it("scans daemonhost liveness without throwing when ALIVE is missing", function()
			-- Guards the daemonhost scan's `ALIVE[enemy_unit]` dereference:
			-- under a nil ALIVE global (e.g. early-spawn window or a future
			-- engine rename) the path must fall back to Unit.alive instead of
			-- raising through the sprint hook.
			local unit = "bot1"
			local dh = "daemonhost_no_alive"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0)
			-- No _alive[dh]; rely on Unit.alive fallback via _unit_alive.
			_unit_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_behavior(unit, {})

			local saved_alive = rawget(_G, "ALIVE")
			_G.ALIVE = nil
			local self_obj = make_self()
			local ok_call, ok, reason = pcall(Sprint.should_sprint, self_obj, unit, {})
			_G.ALIVE = saved_alive

			assert.is_true(ok_call, "daemonhost scan must not throw when ALIVE is nil")
			assert.is_false(ok)
			assert.equals("daemonhost_nearby", reason)
		end)

		it("blocks sprint near mutator daemonhost", function()
			local unit = "bot1"
			local dh = "mdh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(15, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_mutator_daemonhost")
			setup_side_system(unit, { dh })
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("daemonhost_nearby", reason)
		end)

		it("allows sprint when daemonhost is beyond safe range", function()
			local unit = "bot1"
			local dh = "daemonhost_far"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(25, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_perception(unit, {})
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- Daemonhost at 25m > 20m safe range, no aggroed enemies -> traversal
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)
	end)

	describe("settings wiring (#81)", function()
		before_each(function()
			reset()
		end)

		it("skips catch-up sprint when sprint_follow_distance=0", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 0
				end,
			})

			local unit = "bot_disabled"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(50, 0, 0)
			_alive[follow] = true
			setup_perception(unit, {})
			setup_side_system(unit, {})
			setup_behavior(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})

			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- Catch-up is gated by follow_dist > 0, so falls through to traversal
			assert.is_true(ok)
			assert.equals("traversal", reason)

			-- Restore default
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
			})
		end)

		it("uses configurable sprint follow distance", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 25
				end,
			})

			local unit = "bot_custom"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(20, 0, 0) -- 20m < 25m threshold
			_alive[follow] = true
			setup_perception(unit, {})
			setup_side_system(unit, {})
			setup_behavior(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})

			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- 20m < 25m, so no catch-up; falls through to traversal (no enemies)
			assert.is_true(ok)
			assert.equals("traversal", reason)

			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
			})
		end)

		it("allows sprint near daemonhost when avoidance is disabled", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				is_daemonhost_avoidance_enabled = function()
					return false
				end,
			})

			local unit = "bot_dh_off"
			local dh = "daemonhost_close"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0) -- inside 20m safe range
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_perception(unit, {})
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- DH avoidance disabled, so not blocked; traversal (no enemies)
			assert.is_true(ok)
			assert.equals("traversal", reason)

			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
			})
		end)
	end)

	describe("is_near_daemonhost", function()
		it("returns false with no side system", function()
			_positions["bot1"] = pos(0, 0, 0)
			assert.is_false(Sprint.is_near_daemonhost("bot1"))
		end)

		it("returns false with no enemies on side", function()
			local unit = "bot1"
			_positions[unit] = pos(0, 0, 0)
			setup_side_system(unit, {})
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true for close daemonhost", function()
			local unit = "bot1"
			local dh = "dh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for far daemonhost", function()
			local unit = "bot1"
			local dh = "dh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(25, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for non-daemonhost enemy", function()
			local unit = "bot1"
			local enemy = "poxwalker1"
			_positions[unit] = pos(0, 0, 0)
			_positions[enemy] = pos(3, 0, 0)
			_alive[enemy] = true
			setup_breed(enemy, "chaos_poxwalker")
			setup_side_system(unit, { enemy })
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("detects mutator daemonhost", function()
			local unit = "bot1"
			local dh = "mdh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_mutator_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for aggroed daemonhost", function()
			local unit = "bot1"
			local dh = "dh_aggro"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			_blackboards[dh] = { perception = { aggro_state = "aggroed" } }
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true for alerted (non-aggroed) daemonhost", function()
			local unit = "bot1"
			local dh = "dh_alerted"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			_blackboards[dh] = { perception = { aggro_state = "alerted" } }
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true when daemonhost has no blackboard", function()
			local unit = "bot1"
			local dh = "dh_no_bb"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			-- No BLACKBOARDS entry — treat as non-aggroed (conservative)
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("detects passive daemonhosts from relation units when they are not AI targets", function()
			local unit = "bot1"
			local dh = "dh_relation_only"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system_with_relation_only_daemonhost(unit, { dh })

			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("detects passive daemonhosts from the minion spawn manager when side lists omit them", function()
			local unit = "bot1"
			local dh = "dh_spawned_only"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system_with_relation_only_daemonhost(unit, {})
			_spawned_minions[1] = dh

			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("uses the minion spawn daemonhost scan even when side lookup is unavailable", function()
			local unit = "bot1"
			local dh = "dh_no_side"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			_mock_side_system = test_helper.make_side_system_double({
				side_by_unit = {},
			})
			_spawned_minions[1] = dh

			assert.is_true(Sprint.is_near_daemonhost(unit))
			assert.is_true(Sprint.is_position_near_daemonhost(unit, pos(6, 0, 0), Sprint.daemonhost_keepout_range_sq()))
		end)

		it("logs daemonhost candidate classification details in debug mode", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function(key, _fixed_t, message)
					_debug_logs[#_debug_logs + 1] = {
						key = key,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return _mock_time
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})

			local unit = "bot_debug"
			local dh = "dh_debug"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			_blackboards[dh] = { perception = { aggro_state = "aggroed" } }

			assert.is_false(Sprint.is_near_daemonhost(unit))

			local joined = ""
			for i = 1, #_debug_logs do
				joined = joined .. "\n" .. _debug_logs[i].message
			end
			assert.is_truthy(joined:find("daemonhost scan candidate", 1, true))
			assert.is_truthy(joined:find("source=ai_target_units", 1, true))
			assert.is_truthy(joined:find("breed=chaos_daemonhost", 1, true))
			assert.is_truthy(joined:find("aggro_state=aggroed", 1, true))
			assert.is_truthy(joined:find("accepted=false", 1, true))
			assert.is_truthy(joined:find("reason=aggroed", 1, true))
		end)

		it("logs each daemonhost scan source once even when enemy counts change", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function(key, _fixed_t, message)
					_debug_logs[#_debug_logs + 1] = {
						key = key,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return _mock_time
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})

			local unit = "bot_source_log"
			local enemy1 = "enemy1"
			local enemy2 = "enemy2"
			local side = {
				ai_target_units = { enemy1 },
				relation_units = function(self)
					return self.ai_target_units
				end,
			}
			_positions[unit] = pos(0, 0, 0)
			_mock_side_system = test_helper.make_side_system_double({
				side_by_unit = {
					[unit] = side,
				},
			})

			assert.is_false(Sprint.is_near_daemonhost(unit))
			_mock_time = _mock_time + 1
			side.ai_target_units = { enemy1, enemy2 }
			assert.is_false(Sprint.is_near_daemonhost(unit))

			local source_logs = 0
			for i = 1, #_debug_logs do
				if _debug_logs[i].message:find("daemonhost scan source source=ai_target_units", 1, true) then
					source_logs = source_logs + 1
				end
			end

			assert.equals(1, source_logs)
		end)

		it("checks arbitrary positions against daemonhost danger range from the bot side", function()
			local unit = "bot1"
			local dh = "dh_near_target"
			_positions[unit] = pos(30, 0, 0)
			_positions[dh] = pos(0, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })

			assert.is_false(Sprint.is_near_daemonhost(unit, Sprint.daemonhost_keepout_range_sq()))
			assert.is_true(Sprint.is_position_near_daemonhost(unit, pos(5, 0, 0), Sprint.daemonhost_keepout_range_sq()))
		end)

		it("returns true when one DH aggroed and another non-aggroed nearby", function()
			local unit = "bot1"
			local dh_aggro = "dh_fighting"
			local dh_passive = "dh_sleeping"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh_aggro] = pos(5, 0, 0)
			_positions[dh_passive] = pos(10, 0, 0)
			_alive[dh_aggro] = true
			_alive[dh_passive] = true
			setup_breed(dh_aggro, "chaos_daemonhost")
			setup_breed(dh_passive, "chaos_daemonhost")
			setup_side_system(unit, { dh_aggro, dh_passive })
			_blackboards[dh_aggro] = { perception = { aggro_state = "aggroed" } }
			_blackboards[dh_passive] = { perception = { aggro_state = "passive" } }
			-- Skips the aggroed one, catches the passive one
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("respects tighter combat range parameter", function()
			local unit = "bot1"
			local dh = "dh_mid"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(15, 0, 0) -- 15m: inside 20m but outside 10m
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			-- Default 20m range: true
			assert.is_true(Sprint.is_near_daemonhost(unit))
			-- Bust cache for next call with different range
			_mock_time = _mock_time + 1
			-- Tighter 10m combat range: false (15m > 10m)
			assert.is_false(Sprint.is_near_daemonhost(unit, Sprint.DAEMONHOST_COMBAT_RANGE_SQ))
		end)
	end)

	describe("on_update_movement hook", function()
		local input
		local next_should
		local next_reason

		before_each(function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 5
				end,
				daemonhost_keepout_distance = function()
					return 14
				end,
				is_daemonhost_avoidance_enabled = function()
					return true
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})
			Sprint._set_should_sprint_for_test(function()
				return next_should, next_reason
			end)
			input = {}
			next_should = false
			next_reason = "enemies_nearby"
		end)

		local function call(func, input_arg)
			Sprint._on_update_movement(func or function() end, make_self(), "unit_stub", input_arg or input, 0.016, 1.0)
		end

		it("always sets hold_to_sprint = true when enabled", function()
			call()
			assert.is_true(input.hold_to_sprint)
		end)

		it("sets input.sprinting to _should_sprint result", function()
			next_should = true
			call()
			assert.is_true(input.sprinting)

			next_should = false
			call()
			assert.is_false(input.sprinting)
		end)

		it("soft-steers away from non-aggroed daemonhosts inside the movement radius", function()
			local bot = "bot_keepout"
			local daemonhost = "daemonhost_keepout"
			local self_obj = make_self({
				move = { x = 0, y = 1 },
			})
			self_obj._first_person_component = {
				rotation = "rotation",
			}

			_positions[bot] = pos(0, 0, 0)
			_positions[daemonhost] = pos(0, 8, 0)
			_alive[daemonhost] = true
			setup_breed(daemonhost, "chaos_daemonhost")
			setup_side_system(bot, { daemonhost })

			Sprint._on_update_movement(function()
				self_obj._move.x = 0
				self_obj._move.y = 1
			end, self_obj, bot, input, 0.016, _mock_time)

			assert.equals(0, self_obj._move.x)
			assert.is_true(self_obj._move.y <= 0)
			assert.equals("daemonhost_keepout", self_obj._bb_movement_safety_blocked)
			assert.is_false(input.sprinting)
		end)

		it("logs daemonhost movement steering once per unit and strength bucket", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function(key, _fixed_t, message)
					_debug_logs[#_debug_logs + 1] = {
						key = key,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 5
				end,
				daemonhost_keepout_distance = function()
					return 14
				end,
				is_daemonhost_avoidance_enabled = function()
					return true
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})

			local bot = "bot_keepout_log"
			local daemonhost = "daemonhost_keepout_log"
			local self_obj = make_self({
				move = { x = 0, y = 1 },
			})
			self_obj._first_person_component = {
				rotation = "rotation",
			}

			_positions[bot] = pos(0, 0, 0)
			_positions[daemonhost] = pos(0, 8, 0)
			_alive[daemonhost] = true
			setup_breed(daemonhost, "chaos_daemonhost")
			setup_side_system(bot, { daemonhost })

			Sprint._on_update_movement(function()
				self_obj._move.x = 0
				self_obj._move.y = 1
			end, self_obj, bot, input, 0.016, _mock_time)
			self_obj._move.x = 0
			self_obj._move.y = 1
			Sprint._on_update_movement(function()
				self_obj._move.x = 0
				self_obj._move.y = 1
			end, self_obj, bot, input, 0.016, _mock_time)

			local movement_logs = 0
			for i = 1, #_debug_logs do
				if _debug_logs[i].message:find("movement safety steered away from daemonhost", 1, true) then
					movement_logs = movement_logs + 1
					assert.is_truthy(_debug_logs[i].message:find("bucket=firm", 1, true))
				end
			end

			assert.equals(1, movement_logs)
		end)

		it("keeps passage movement positive at the edge of daemonhost movement radius", function()
			local bot = "bot_soft_keepout"
			local daemonhost = "daemonhost_soft_keepout"
			local self_obj = make_self({
				move = { x = 0, y = 1 },
			})
			self_obj._first_person_component = {
				rotation = "rotation",
			}

			_positions[bot] = pos(0, 0, 0)
			_positions[daemonhost] = pos(0, 9.9, 0)
			_alive[daemonhost] = true
			setup_breed(daemonhost, "chaos_daemonhost")
			setup_side_system(bot, { daemonhost })

			Sprint._on_update_movement(function()
				self_obj._move.x = 0
				self_obj._move.y = 1
			end, self_obj, bot, input, 0.016, _mock_time)

			assert.equals(0, self_obj._move.x)
			assert.is_true(self_obj._move.y > 0)
			assert.is_true(self_obj._move.y < 1)
			assert.equals("daemonhost_keepout", self_obj._bb_movement_safety_blocked)
			assert.is_false(input.sprinting)
		end)

		it("soft-steers across the full configured daemonhost action keepout", function()
			local bot = "bot_outer_keepout"
			local daemonhost = "daemonhost_outer_keepout"
			local self_obj = make_self({
				move = { x = 0, y = 1 },
			})
			self_obj._bb_movement_safety_blocked = "daemonhost_keepout"
			self_obj._first_person_component = {
				rotation = "rotation",
			}

			_positions[bot] = pos(0, 0, 0)
			_positions[daemonhost] = pos(0, 12, 0)
			_alive[daemonhost] = true
			setup_breed(daemonhost, "chaos_daemonhost")
			setup_side_system(bot, { daemonhost })

			Sprint._on_update_movement(function()
				self_obj._move.x = 0
				self_obj._move.y = 1
			end, self_obj, bot, input, 0.016, _mock_time)

			assert.equals(0, self_obj._move.x)
			assert.is_true(self_obj._move.y < 1)
			assert.equals("daemonhost_keepout", self_obj._bb_movement_safety_blocked)
		end)

		it("short-circuits and does not mutate input when follow_distance = 0", function()
			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 0
				end,
				is_daemonhost_avoidance_enabled = function()
					return true
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})

			call()
			assert.is_nil(input.hold_to_sprint)
			assert.is_nil(input.sprinting)
		end)

		it("chains original func on both normal and short-circuit paths", function()
			local func_calls = 0
			local wrapped = function()
				func_calls = func_calls + 1
			end

			call(wrapped)
			assert.equals(1, func_calls)

			Sprint.init({
				mod = { echo = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return _mock_time
				end,
				sprint_follow_distance = function()
					return 0
				end,
				is_daemonhost_avoidance_enabled = function()
					return true
				end,
				shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
			})

			call(wrapped, {})
			assert.equals(2, func_calls)
		end)
	end)
end)
