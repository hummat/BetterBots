-- scenario_harness_spec.lua -- tests for scripted validation scenarios (#100)

local ScenarioHarness = dofile("scripts/mods/BetterBots/scenario_harness.lua")

local _saved_globals = {}
local _commands
local _echoes
local _events
local _spawns
local _despawns
local _mock_time
local _bot_unit
local _bot_alive

local function vec(x, y, z)
	return { x = x, y = y, z = z }
end

local function assert_vec(expected, actual)
	assert.equals(expected.x, actual.x)
	assert.equals(expected.y, actual.y)
	assert.equals(expected.z, actual.z)
end

local function reset()
	_commands = {}
	_echoes = {}
	_events = {}
	_spawns = {}
	_despawns = {}
	_mock_time = 12.5
	_bot_unit = "bot_unit"
	_bot_alive = true

	_G.Breeds = {
		chaos_poxwalker_bomber = true,
		chaos_ogryn_executor = true,
		chaos_daemonhost = true,
		chaos_poxwalker = true,
		renegade_executor = true,
		renegade_melee = true,
		renegade_gunner = true,
		renegade_grenadier = true,
	}
	_G.Managers = {
		player = {
			local_player = function()
				return {
					player_unit = "player_unit",
					unit_is_alive = function()
						return true
					end,
				}
			end,
		},
		state = {
			game_session = {
				is_server = function()
					return true
				end,
			},
			minion_spawn = {
				spawn_minion = function(_self, breed_name, position, rotation, side_id, spawn_params)
					local unit = "spawned_" .. tostring(#_spawns + 1)
					_spawns[#_spawns + 1] = {
						unit = unit,
						breed_name = breed_name,
						position = position,
						rotation = rotation,
						side_id = side_id,
						spawn_params = spawn_params,
					}
					return unit
				end,
				despawn_minion = function(_self, unit)
					_despawns[#_despawns + 1] = unit
				end,
			},
		},
	}
	_G.Unit = {
		local_position = function(unit, node)
			assert.equals(1, node)
			if unit == _bot_unit then
				return vec(14, 20, 3)
			end
			assert.equals("player_unit", unit)
			return vec(10, 20, 3)
		end,
		local_rotation = function(unit, node)
			assert.equals(1, node)
			assert.is_true(unit == "player_unit" or unit == _bot_unit)
			return "player_rotation"
		end,
		alive = function(unit)
			return unit == "player_unit" or (unit == _bot_unit and _bot_alive) or unit:find("^spawned_") ~= nil
		end,
	}
	_G.Quaternion = {
		forward = function(rotation)
			assert.equals("player_rotation", rotation)
			return vec(1, 0, 0)
		end,
		right = function(rotation)
			assert.equals("player_rotation", rotation)
			return vec(0, 1, 0)
		end,
		identity = function()
			return "identity_rotation"
		end,
	}
	_G.Vector3 = function(x, y, z)
		return vec(x, y, z)
	end

	ScenarioHarness.init({
		mod = {
			command = function(_self, name, description, callback)
				_commands[name] = { description = description, callback = callback }
			end,
			echo = function(_self, message)
				_echoes[#_echoes + 1] = message
			end,
		},
		event_log = {
			emit = function(event)
				_events[#_events + 1] = event
			end,
		},
		fixed_time = function()
			return _mock_time
		end,
		debug = {
			collect_alive_bots = function()
				return {
					{ unit = _bot_unit },
				}
			end,
		},
	})
end

setup(function()
	_saved_globals.Managers = rawget(_G, "Managers")
	_saved_globals.Unit = rawget(_G, "Unit")
	_saved_globals.Quaternion = rawget(_G, "Quaternion")
	_saved_globals.Vector3 = rawget(_G, "Vector3")
	_saved_globals.Breeds = rawget(_G, "Breeds")
end)

teardown(function()
	rawset(_G, "Managers", _saved_globals.Managers)
	rawset(_G, "Unit", _saved_globals.Unit)
	rawset(_G, "Quaternion", _saved_globals.Quaternion)
	rawset(_G, "Vector3", _saved_globals.Vector3)
	rawset(_G, "Breeds", _saved_globals.Breeds)
end)

describe("scenario_harness", function()
	before_each(function()
		reset()
	end)

	it("registers bb_scenario commands and lists built-in scenarios", function()
		ScenarioHarness.register_commands()

		assert.is_truthy(_commands.bb_scenario)
		assert.is_truthy(_commands.bb_scenarios)
		assert.is_truthy(_commands.bb_scenario_clear)

		_commands.bb_scenarios.callback()

		assert.is_truthy(_echoes[1]:find("poxburster_push", 1, true))
		assert.is_truthy(_echoes[1]:find("crusher_pack", 1, true))
		assert.is_truthy(_echoes[1]:find("mauler_weakspot", 1, true))
		assert.is_truthy(_echoes[1]:find("mixed_horde_pressure", 1, true))
		assert.is_truthy(_echoes[1]:find("daemonhost_passive_near", 1, true))
		assert.is_truthy(_echoes[1]:find("daemonhost_aggroed_control", 1, true))
	end)

	it("spawns the named scenario ahead of the local player and emits scenario events", function()
		ScenarioHarness.run("poxburster_push")

		assert.equals(1, #_spawns)
		assert.equals("chaos_poxwalker_bomber", _spawns[1].breed_name)
		assert.equals(2, _spawns[1].side_id)
		assert.equals("aggroed", _spawns[1].spawn_params.optional_aggro_state)
		assert.equals(_bot_unit, _spawns[1].spawn_params.optional_target_unit)
		assert_vec(vec(17, 20, 3), _spawns[1].position)

		assert.equals("scenario_start", _events[1].event)
		assert.equals("poxburster_push", _events[1].scenario)
		assert.equals("scenario_spawn", _events[2].event)
		assert.equals("spawned_1", _events[2].unit)
		assert.equals("chaos_poxwalker_bomber", _events[2].breed)
		assert.equals("BetterBots: scenario poxburster_push spawned 1 unit(s)", _echoes[#_echoes])
	end)

	it("falls back to the local player for poxburster spawns when no live bot is available", function()
		_bot_alive = false

		ScenarioHarness.run("poxburster_push")

		assert.equals("player_unit", _spawns[1].spawn_params.optional_target_unit)
		assert_vec(vec(13, 20, 3), _spawns[1].position)
	end)

	it("can repeat mauler weakspot spawns at a caller-selected distance", function()
		ScenarioHarness.run("mauler_weakspot", { distance = 24, count = 3 })

		assert.equals(3, #_spawns)
		for i = 1, 3 do
			assert.equals("renegade_executor", _spawns[i].breed_name)
			assert.equals(34, _spawns[i].position.x)
			assert.equals(3, _spawns[i].position.z)
		end
		assert.equals(18, _spawns[1].position.y)
		assert.equals(20, _spawns[2].position.y)
		assert.equals(22, _spawns[3].position.y)
		assert.equals(3, _events[#_events].spawned)
		assert.equals(3, _events[#_events].repeat_count)
		assert.equals("BetterBots: scenario mauler_weakspot spawned 3 unit(s)", _echoes[#_echoes])
	end)

	it("spawns passive daemonhost without forcing a target or aggro state", function()
		ScenarioHarness.run("daemonhost_passive_near")

		assert.equals(1, #_spawns)
		assert.equals("chaos_daemonhost", _spawns[1].breed_name)
		assert.is_nil(_spawns[1].spawn_params.optional_aggro_state)
		assert.is_nil(_spawns[1].spawn_params.optional_target_unit)
		assert_vec(vec(22, 20, 3), _spawns[1].position)
		assert.equals("daemonhost_passive_near", _events[1].scenario)
		assert.equals("spawned_1", _events[2].unit)
	end)

	it("spawns aggroed daemonhost control against the local player", function()
		ScenarioHarness.run("daemonhost_aggroed_control")

		assert.equals(1, #_spawns)
		assert.equals("chaos_daemonhost", _spawns[1].breed_name)
		assert.equals("aggroed", _spawns[1].spawn_params.optional_aggro_state)
		assert.equals("player_unit", _spawns[1].spawn_params.optional_target_unit)
	end)

	it("spawns mixed horde composition using per-spawn counts", function()
		ScenarioHarness.run("mixed_horde_pressure")

		assert.equals(20, #_spawns)

		local counts = {}
		for i = 1, #_spawns do
			local breed = _spawns[i].breed_name
			counts[breed] = (counts[breed] or 0) + 1
		end

		assert.equals(10, counts.chaos_poxwalker)
		assert.equals(6, counts.renegade_melee)
		assert.equals(2, counts.renegade_executor)
		assert.equals(1, counts.renegade_gunner)
		assert.equals(1, counts.renegade_grenadier)
		assert.equals(20, _events[#_events].spawned)
	end)

	it("caps mixed horde repeat count to avoid accidental stress spawns", function()
		ScenarioHarness.run("mixed_horde_pressure", { count = 12 })

		assert.equals(40, #_spawns)
		assert.equals(2, _events[1].repeat_count)
		assert.equals(40, _events[#_events].spawned)
	end)

	it("parses bb_scenario distance and count arguments", function()
		ScenarioHarness.register_commands()

		_commands.bb_scenario.callback("mauler_weakspot 18 2")

		assert.equals(2, #_spawns)
		assert.equals(28, _spawns[1].position.x)
		assert.equals(19, _spawns[1].position.y)
		assert.equals(21, _spawns[2].position.y)
	end)

	it("parses bb_scenario distance and count when DMF passes arguments separately", function()
		ScenarioHarness.register_commands()

		_commands.bb_scenario.callback("mauler_weakspot", "30", "4")

		assert.equals(4, #_spawns)
		assert.equals(40, _spawns[1].position.x)
		assert.equals(17, _spawns[1].position.y)
		assert.equals(23, _spawns[4].position.y)
		assert.equals(30, _events[1].requested_distance)
		assert.equals(4, _events[1].requested_count)
		assert.equals(4, _events[1].repeat_count)
		assert.equals(30, _events[2].forward_distance)
		assert.equals(4, _events[2].repeat_count)
	end)

	for _, case in ipairs({
		{
			name = "poxburster_push",
			spawn_count = 2,
			first_breed = "chaos_poxwalker_bomber",
			first_x = 22,
		},
		{
			name = "crusher_pack",
			spawn_count = 6,
			first_breed = "chaos_ogryn_executor",
			first_x = 18,
		},
		{
			name = "mauler_weakspot",
			spawn_count = 2,
			first_breed = "renegade_executor",
			first_x = 18,
		},
	}) do
		it("applies split distance and count arguments to " .. case.name, function()
			ScenarioHarness.register_commands()

			_commands.bb_scenario.callback(case.name, "8", "2")

			assert.equals(case.spawn_count, #_spawns)
			assert.equals(case.first_breed, _spawns[1].breed_name)
			assert.equals(case.first_x, _spawns[1].position.x)
			assert.equals(8, _events[1].requested_distance)
			assert.equals(2, _events[1].requested_count)
			assert.equals(2, _events[1].repeat_count)
			assert.equals("scenario_spawn", _events[2].event)
			assert.equals(8, _events[2].forward_distance)
			assert.equals(2, _events[2].repeat_count)
			assert.equals(case.spawn_count, _events[#_events].spawned)
			assert.equals(2, _events[#_events].repeat_count)
		end)
	end

	it("clears spawned scenario units and records teardown", function()
		ScenarioHarness.run("poxburster_push")
		ScenarioHarness.clear()

		assert.same({ "spawned_1" }, _despawns)
		assert.equals("scenario_clear", _events[#_events].event)
		assert.equals(1, _events[#_events].despawned)
		assert.equals("manual", _events[#_events].reason)
		assert.equals("BetterBots: scenario cleanup despawned 1 unit(s)", _echoes[#_echoes])
	end)

	it("rejects unknown scenarios before spawning", function()
		ScenarioHarness.run("missing")

		assert.equals(0, #_spawns)
		assert.equals(0, #_events)
		assert.equals("BetterBots: unknown scenario 'missing'", _echoes[1])
	end)

	it("fails closed when the minion spawner is unavailable", function()
		_G.Managers.state.minion_spawn = nil

		ScenarioHarness.run("poxburster_push")

		assert.equals(0, #_spawns)
		assert.equals(0, #_events)
		assert.equals("BetterBots: /bb_scenario unavailable (minion_spawn not ready)", _echoes[1])
	end)
end)
