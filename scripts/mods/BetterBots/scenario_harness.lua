-- scenario_harness.lua -- scripted in-mission validation scenarios (#100)
local M = {}

local _mod
local _event_log
local _fixed_time
local _spawned_units = {}

local ENEMY_SIDE_ID = 2

local SCENARIOS = {
	poxburster_push = {
		description = "spawn one aggroed poxburster 8m ahead",
		spawns = {
			{ breed = "chaos_poxwalker_bomber", forward = 8 },
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
}

local SCENARIO_ORDER = {
	"poxburster_push",
	"crusher_pack",
	"mauler_weakspot",
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

local function _first_arg(...)
	local count = select("#", ...)
	if count == 0 then
		return nil
	end

	local raw = select(1, ...)
	if raw == nil then
		return nil
	end

	local text = tostring(raw)
	return text:match("^%s*(%S+)")
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

local function _spawn_params(player_unit, spawn)
	return {
		optional_aggro_state = spawn.aggro_state or "aggroed",
		optional_target_unit = player_unit,
		optional_health_modifier = spawn.health_modifier,
	}
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

local function _run_scenario(name)
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

	_emit({
		t = fixed_t,
		event = "scenario_start",
		scenario = name,
		run_id = run_id,
		expect = scenario.expect,
	})

	for i = 1, #scenario.spawns do
		local spawn = scenario.spawns[i]
		local breed_name = spawn.breed
		do
			local position = _relative_position(origin, player_rotation, spawn.forward, spawn.right)
			local rotation = Quaternion.identity and Quaternion.identity() or player_rotation
			local unit = minion_spawner:spawn_minion(
				breed_name,
				position,
				rotation,
				spawn.side_id or ENEMY_SIDE_ID,
				_spawn_params(player_unit, spawn)
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
	_spawned_units = {}
end

function M.register_commands()
	_mod:command("bb_scenarios", "List BetterBots validation scenarios", function()
		_list_scenarios()
	end)
	_mod:command("bb_scenario_clear", "Despawn units spawned by BetterBots validation scenarios", function()
		_clear_spawned("manual")
	end)
	_mod:command("bb_scenario", "Run a BetterBots validation scenario: /bb_scenario <name>", function(...)
		local name = _first_arg(...)
		if not name then
			_echo("BetterBots: usage: /bb_scenario <" .. table.concat(SCENARIO_ORDER, "|") .. ">")
			return
		end

		_run_scenario(name)
	end)
end

function M.run(name)
	return _run_scenario(name)
end

function M.clear()
	return _clear_spawned("manual")
end

function M.scenarios()
	return SCENARIOS
end

return M
