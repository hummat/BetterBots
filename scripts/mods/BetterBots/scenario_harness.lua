-- scenario_harness.lua -- scripted in-mission validation scenarios (#100)
local M = {}

local _mod
local _event_log
local _fixed_time
local _debug
local _spawned_units = {}

local ENEMY_SIDE_ID = 2

local SCENARIOS = {
	poxburster_push = {
		description = "spawn one aggroed poxburster near a bot",
		spawns = {
			{ breed = "chaos_poxwalker_bomber", forward = 3, anchor = "bot" },
		},
		expect = {
			"pushing poxburster",
			"suppressed poxburster",
		},
	},
	crusher_pack = {
		description = "spawn three crushers 15m ahead",
		spawns = {
			{ breed = "chaos_ogryn_executor", forward = 15, right = -2 },
			{ breed = "chaos_ogryn_executor", forward = 16, right = 0 },
			{ breed = "chaos_ogryn_executor", forward = 15, right = 2 },
		},
		expect = {
			"fallback queued",
			"grenade queued",
			"melee special prelude queued",
		},
	},
	mauler_weakspot = {
		description = "spawn one scab mauler 12m ahead",
		spawns = {
			{ breed = "renegade_executor", forward = 12 },
		},
		expect = {
			"weakspot aim selected",
			"weakspot override applied",
		},
	},
	mixed_horde_pressure = {
		description = "spawn mixed trash, melee, elite, ranged, and special pressure",
		max_repeat = 2,
		spawns = {
			{ breed = "chaos_poxwalker", count = 10, forward = 11, right = -3 },
			{ breed = "renegade_melee", count = 6, forward = 13, right = 3 },
			{ breed = "renegade_executor", count = 2, forward = 16, right = 0 },
			{ breed = "renegade_gunner", forward = 20, right = -4 },
			{ breed = "renegade_grenadier", forward = 22, right = 4 },
		},
		expect = {
			"fallback queued",
			"grenade releasing toward",
			"melee special prelude queued",
			"type hold",
		},
	},
	daemonhost_passive_near = {
		description = "spawn one passive daemonhost without a forced target",
		spawns = {
			{ breed = "chaos_daemonhost", forward = 12, aggro_state = false, target = false },
		},
		expect = {
			"skipped ping for chaos_daemonhost (reason: dormant_daemonhost)",
			"melee suppressed (target is dormant daemonhost",
			"ranged suppressed (target is dormant daemonhost",
		},
	},
	daemonhost_aggroed_control = {
		description = "spawn one aggroed daemonhost targeting the player",
		spawns = {
			{ breed = "chaos_daemonhost", forward = 18, aggro_state = "aggroed", target = "player" },
		},
		expect = {
			"ability allowed against daemonhost",
			"target=chaos_daemonhost",
			"dormant=false",
		},
	},
}

local SCENARIO_ORDER = {
	"poxburster_push",
	"crusher_pack",
	"mauler_weakspot",
	"mixed_horde_pressure",
	"daemonhost_passive_near",
	"daemonhost_aggroed_control",
}

local function _echo(message)
	if _mod and _mod.echo then
		_mod:echo(message)
	end
end

local function _emit(event)
	if _event_log and _event_log.emit then
		_event_log.emit(event)
	end
end

local function _now()
	return _fixed_time and _fixed_time() or 0
end

local function _parse_command_args(...)
	local count = select("#", ...)
	if count == 0 then
		return nil, {}
	end

	local raw = select(1, ...)
	if raw == nil then
		return nil, {}
	end

	local tokens = {}
	for i = 1, count do
		raw = select(i, ...)
		if raw ~= nil then
			for token in tostring(raw):gmatch("%S+") do
				tokens[#tokens + 1] = token
			end
		end
	end

	return tokens[1], {
		distance = tonumber(tokens[2]),
		count = tonumber(tokens[3]),
	}
end

local function _clamp_number(value, default, min_value, max_value)
	local number = tonumber(value)
	if not number then
		return default
	end
	if number < min_value then
		return min_value
	end
	if number > max_value then
		return max_value
	end

	return number
end

local function _spawn_repeat_count(options, scenario)
	local max_repeat = scenario and scenario.max_repeat or 12
	return math.floor(_clamp_number(options and options.count, 1, 1, max_repeat))
end

local function _spawn_forward(spawn, options)
	return _clamp_number(options and options.distance, spawn.forward, 2, 80)
end

local function _spawn_right(spawn, repeat_index, repeat_count)
	local base_right = spawn.right or 0
	if repeat_count <= 1 then
		return base_right
	end

	return base_right + (repeat_index - (repeat_count + 1) / 2) * 2
end

local function _alive_bot_unit()
	local bots = _debug and _debug.collect_alive_bots and _debug.collect_alive_bots() or nil
	if not bots then
		return nil
	end

	for i = 1, #bots do
		local unit = bots[i] and bots[i].unit
		if unit and Unit and Unit.alive and Unit.alive(unit) then
			return unit
		end
	end

	return nil
end

local function _is_server()
	local game_session = Managers and Managers.state and Managers.state.game_session
	return game_session and game_session.is_server and game_session:is_server() == true
end

local function _local_player_unit()
	local player_manager = Managers and Managers.player
	local player = player_manager and player_manager.local_player and player_manager:local_player(1)
	if not player then
		return nil
	end

	if player.unit_is_alive and not player:unit_is_alive() then
		return nil
	end

	return player.player_unit
end

local function _component(value, field)
	return value and (value[field] or 0) or 0
end

local function _vector(x, y, z)
	if Vector3 then
		return Vector3(x, y, z)
	end

	return { x = x, y = y, z = z }
end

local function _relative_position(origin, rotation, forward_distance, right_distance)
	local forward = Quaternion.forward and Quaternion.forward(rotation) or _vector(1, 0, 0)
	local right = Quaternion.right and Quaternion.right(rotation) or _vector(0, 1, 0)
	local fx, fy, fz = _component(forward, "x"), _component(forward, "y"), _component(forward, "z")
	local rx, ry, rz = _component(right, "x"), _component(right, "y"), _component(right, "z")
	local ox, oy, oz = _component(origin, "x"), _component(origin, "y"), _component(origin, "z")
	local forward_scale = forward_distance or 0
	local right_scale = right_distance or 0

	return _vector(
		ox + fx * forward_scale + rx * right_scale,
		oy + fy * forward_scale + ry * right_scale,
		oz + fz * forward_scale + rz * right_scale
	)
end

local function _spawn_params(target_unit, spawn)
	local params = {
		optional_health_modifier = spawn.health_modifier,
	}
	if spawn.aggro_state ~= false then
		params.optional_aggro_state = spawn.aggro_state or "aggroed"
	end
	if spawn.target ~= false then
		params.optional_target_unit = target_unit
	end

	return params
end

local function _spawn_count(spawn, repeat_count)
	return math.floor(_clamp_number(spawn and spawn.count, 1, 1, 24)) * repeat_count
end

local function _spawn_anchor_unit(spawn, player_unit)
	if spawn.target == false then
		return nil
	end
	if spawn.anchor == "bot" then
		return _alive_bot_unit() or player_unit
	end

	return player_unit
end

local function _clear_spawned(reason)
	local minion_spawner = Managers and Managers.state and Managers.state.minion_spawn
	if not (minion_spawner and minion_spawner.despawn_minion) then
		_echo("BetterBots: scenario cleanup unavailable (minion despawn not ready)")
		return false
	end

	local fixed_t = _now()
	local despawned = 0
	for i = #_spawned_units, 1, -1 do
		local unit = _spawned_units[i]
		if not Unit or not Unit.alive or Unit.alive(unit) then
			minion_spawner:despawn_minion(unit)
			despawned = despawned + 1
		end
		_spawned_units[i] = nil
	end

	_emit({
		t = fixed_t,
		event = "scenario_clear",
		reason = reason or "manual",
		despawned = despawned,
	})
	_echo("BetterBots: scenario cleanup despawned " .. tostring(despawned) .. " unit(s)")

	return true
end

local function _run_scenario(name, options)
	local scenario = SCENARIOS[name]
	if not scenario then
		_echo("BetterBots: unknown scenario '" .. tostring(name) .. "'")
		return false
	end

	if not _is_server() then
		_echo("BetterBots: /bb_scenario unavailable (not server)")
		return false
	end

	local minion_spawner = Managers and Managers.state and Managers.state.minion_spawn
	if not minion_spawner then
		_echo("BetterBots: /bb_scenario unavailable (minion_spawn not ready)")
		return false
	end

	local player_unit = _local_player_unit()
	if not (player_unit and Unit and Unit.alive and Unit.alive(player_unit)) then
		_echo("BetterBots: /bb_scenario unavailable (local player unit not alive)")
		return false
	end

	local origin = Unit.local_position(player_unit, 1)
	local player_rotation = Unit.local_rotation(player_unit, 1)
	local fixed_t = _now()
	local run_id = name .. ":" .. tostring(math.floor(fixed_t * 1000))
	local spawned_count = 0
	local repeat_count = _spawn_repeat_count(options, scenario)

	_emit({
		t = fixed_t,
		event = "scenario_start",
		scenario = name,
		run_id = run_id,
		expect = scenario.expect,
		requested_distance = options and options.distance,
		requested_count = options and options.count,
		repeat_count = repeat_count,
	})

	for i = 1, #scenario.spawns do
		local spawn = scenario.spawns[i]
		local breed_name = spawn.breed
		local anchor_unit = _spawn_anchor_unit(spawn, player_unit)
		local target_unit = anchor_unit
		local placement_unit = anchor_unit or player_unit
		local spawn_origin = placement_unit ~= player_unit and Unit.local_position(placement_unit, 1) or origin
		local spawn_rotation = placement_unit ~= player_unit and Unit.local_rotation(placement_unit, 1)
			or player_rotation
		local forward_distance = _spawn_forward(spawn, options)
		local per_spawn_count = _spawn_count(spawn, repeat_count)
		for repeat_i = 1, per_spawn_count do
			local right_distance = _spawn_right(spawn, repeat_i, per_spawn_count)
			local position = _relative_position(spawn_origin, spawn_rotation, forward_distance, right_distance)
			local rotation = Quaternion.identity and Quaternion.identity() or spawn_rotation
			local unit = minion_spawner:spawn_minion(
				breed_name,
				position,
				rotation,
				spawn.side_id or ENEMY_SIDE_ID,
				_spawn_params(target_unit, spawn)
			)
			if unit then
				spawned_count = spawned_count + 1
				_spawned_units[#_spawned_units + 1] = unit
				_emit({
					t = fixed_t,
					event = "scenario_spawn",
					scenario = name,
					run_id = run_id,
					breed = breed_name,
					unit = tostring(unit),
					side_id = spawn.side_id or ENEMY_SIDE_ID,
					index = i,
					repeat_index = repeat_i,
					repeat_count = per_spawn_count,
					forward_distance = forward_distance,
					right_distance = right_distance,
					anchor = spawn.anchor,
					target_unit = tostring(target_unit),
				})
			else
				_emit({
					t = fixed_t,
					event = "scenario_spawn_failed",
					scenario = name,
					run_id = run_id,
					breed = breed_name,
					reason = "spawn_returned_nil",
				})
			end
		end
	end

	_emit({
		t = fixed_t,
		event = "scenario_result",
		scenario = name,
		run_id = run_id,
		status = spawned_count > 0 and "spawned" or "failed",
		spawned = spawned_count,
		repeat_count = repeat_count,
	})
	_echo("BetterBots: scenario " .. name .. " spawned " .. tostring(spawned_count) .. " unit(s)")

	return spawned_count > 0
end

local function _list_scenarios()
	local parts = {}
	for i = 1, #SCENARIO_ORDER do
		local name = SCENARIO_ORDER[i]
		parts[#parts + 1] = name .. " (" .. SCENARIOS[name].description .. ")"
	end

	_echo("BetterBots scenarios: " .. table.concat(parts, ", "))
end

function M.init(deps)
	_mod = deps.mod
	_event_log = deps.event_log
	_fixed_time = deps.fixed_time
	_debug = deps.debug
	_spawned_units = {}
end

function M.register_commands()
	_mod:command("bb_scenarios", "List BetterBots validation scenarios", function()
		_list_scenarios()
	end)
	_mod:command("bb_scenario_clear", "Despawn units spawned by BetterBots validation scenarios", function()
		_clear_spawned("manual")
	end)
	_mod:command(
		"bb_scenario",
		"Run a BetterBots validation scenario: /bb_scenario <name> [distance] [count]",
		function(...)
			local name, options = _parse_command_args(...)
			if not name then
				_echo(
					"BetterBots: usage: /bb_scenario <" .. table.concat(SCENARIO_ORDER, "|") .. "> [distance] [count]"
				)
				return
			end

			_run_scenario(name, options)
		end
	)
end

function M.run(name, options)
	return _run_scenario(name, options)
end

function M.clear()
	return _clear_spawned("manual")
end

function M.scenarios()
	return SCENARIOS
end

return M
