local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _sprint_follow_distance
local _daemonhost_keepout_distance
local _is_daemonhost_avoidance_enabled
local _is_non_aggroed_daemonhost
local _hazard_avoidance
local _logged_sprint_disabled = false
local _logged_dh_avoidance_off = false

local DEFAULT_SPRINT_FOLLOW_DISTANCE = 12
local DEFAULT_DAEMONHOST_KEEPOUT_DISTANCE = 14
local DAEMONHOST_SAFE_RANGE_SQ = 20 * 20
local DAEMONHOST_COMBAT_RANGE_SQ = DEFAULT_DAEMONHOST_KEEPOUT_DISTANCE * DEFAULT_DAEMONHOST_KEEPOUT_DISTANCE
local DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

local _last_sprint_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_interesting_start_by_unit = setmetatable({}, { __mode = "k" })

-- Per-frame cache: nearest non-aggroed DH squared distance per unit.
-- Avoids repeated full enemy-table scans when multiple consumers
-- (sprint, _is_suppressed, BT condition wrappers) query in the same tick.
local _dh_nearest_dist_sq_by_unit = setmetatable({}, { __mode = "k" })
local _dh_nearest_unit_by_unit = setmetatable({}, { __mode = "k" })
local _dh_cache_t_by_unit = setmetatable({}, { __mode = "k" })
-- Cache key: (fixed_t, side). The side owns both ai_target_units and the
-- broader relation_units("enemy") list.
local _dh_units_cache_t = nil
local _dh_units_cache_side = nil
local _dh_units_cache = {}
local _side_system_warned = false

local function _unit_is_alive(unit)
	if ALIVE ~= nil then
		local alive = ALIVE[unit]
		if alive ~= nil then
			return alive == true
		end
	end

	if Unit and Unit.alive then
		return Unit.alive(unit)
	end

	return false
end

local function _vec_component(value, key, index)
	if value == nil then
		return 0
	end
	if type(value) == "table" then
		return value[key] or value[index] or 0
	end

	local ok, result = pcall(function()
		return value[key]
	end)
	if ok and result ~= nil then
		return result
	end

	ok, result = pcall(function()
		return value[index]
	end)
	if ok and result ~= nil then
		return result
	end

	return 0
end

local function _dot(a, b)
	return _vec_component(a, "x", 1) * _vec_component(b, "x", 1)
		+ _vec_component(a, "y", 2) * _vec_component(b, "y", 2)
		+ _vec_component(a, "z", 3) * _vec_component(b, "z", 3)
end

local function _normalized_flat(x, y)
	local length = math.sqrt(x * x + y * y)
	if length <= 0.001 then
		return nil, nil
	end

	return x / length, y / length
end

local function _add_non_aggroed_daemonhost_units(units, seen)
	if not units then
		return
	end

	for i = 1, #units do
		local enemy_unit = units[i]
		if enemy_unit and not seen[enemy_unit] and _unit_is_alive(enemy_unit) then
			seen[enemy_unit] = true
			local unit_data_ext = ScriptUnit.has_extension(enemy_unit, "unit_data_system")
			if unit_data_ext then
				local breed = unit_data_ext:breed()
				if breed and DAEMONHOST_BREED_NAMES[breed.name] then
					local is_non_aggroed = _is_non_aggroed_daemonhost and _is_non_aggroed_daemonhost(enemy_unit)
					if is_non_aggroed == nil then
						local dh_bb = BLACKBOARDS and BLACKBOARDS[enemy_unit]
						local dh_perception = dh_bb and dh_bb.perception
						is_non_aggroed = not (dh_perception and dh_perception.aggro_state == "aggroed")
					end
					if is_non_aggroed then
						_dh_units_cache[#_dh_units_cache + 1] = enemy_unit
					end
				end
			end
		end
	end
end

local function _non_aggroed_daemonhost_units(side, fixed_t)
	if _dh_units_cache_t == fixed_t and _dh_units_cache_side == side then
		return _dh_units_cache
	end

	for i = #_dh_units_cache, 1, -1 do
		_dh_units_cache[i] = nil
	end

	local seen = {}
	_add_non_aggroed_daemonhost_units(side and side.ai_target_units, seen)
	local relation_units = side and side.relation_units and side:relation_units("enemy") or nil
	if relation_units ~= side.ai_target_units then
		_add_non_aggroed_daemonhost_units(relation_units, seen)
	end

	_dh_units_cache_t = fixed_t
	_dh_units_cache_side = side

	return _dh_units_cache
end

-- Returns the squared distance to the nearest non-aggroed daemonhost,
-- or math.huge if none exist. Cached per unit per frame.
-- Uses side.ai_target_units (all enemy units on the opposing side).
-- enemies_in_proximity() is unsuitable: it only returns aggroed enemies
-- within a 5m radius — non-aggroed daemonhosts are invisible to that API.
-- Skips aggroed daemonhosts (#17) — once fighting, suppression is
-- pointless and bots should defend themselves.
local function _nearest_daemonhost_from_position(unit, unit_position)
	local fixed_t = _fixed_time()
	local nearest = math.huge
	local nearest_unit = nil

	if not unit_position then
		return nil, nearest
	end

	local side_system = Managers and Managers.state and Managers.state.extension
	if not side_system then
		return nil, nearest
	end

	local ok, ss = pcall(side_system.system, side_system, "side_system")
	if not ok or not ss then
		if not _side_system_warned then
			_side_system_warned = true
			_debug_log("dh_side_system_fail", 0, "daemonhost scan unavailable, sprint safety disabled", nil, "info")
		end
		return nil, nearest
	end

	local side = ss.side_by_unit and ss.side_by_unit[unit]
	if not side then
		return nil, nearest
	end

	local daemonhost_units = _non_aggroed_daemonhost_units(side, fixed_t)
	for i = 1, #daemonhost_units do
		local enemy_unit = daemonhost_units[i]
		local enemy_pos = POSITION_LOOKUP[enemy_unit]
		if enemy_pos then
			local dist_sq = Vector3.distance_squared(unit_position, enemy_pos)
			if dist_sq < nearest then
				nearest = dist_sq
				nearest_unit = enemy_unit
			end
		end
	end

	return nearest_unit, nearest
end

local function _nearest_daemonhost(unit)
	local fixed_t = _fixed_time()
	if _dh_cache_t_by_unit[unit] == fixed_t then
		return _dh_nearest_unit_by_unit[unit], _dh_nearest_dist_sq_by_unit[unit]
	end

	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit] or nil
	local nearest_unit, nearest = _nearest_daemonhost_from_position(unit, unit_position)

	_dh_cache_t_by_unit[unit] = fixed_t
	_dh_nearest_dist_sq_by_unit[unit] = nearest
	_dh_nearest_unit_by_unit[unit] = nearest_unit
	return nearest_unit, nearest
end

local function _nearest_dh_dist_sq(unit)
	local _, dist_sq = _nearest_daemonhost(unit)
	return dist_sq
end

local function _daemonhost_keepout_range_sq()
	local distance = _daemonhost_keepout_distance and _daemonhost_keepout_distance()
		or DEFAULT_DAEMONHOST_KEEPOUT_DISTANCE
	distance = math.max(distance or DEFAULT_DAEMONHOST_KEEPOUT_DISTANCE, 0)

	return distance * distance
end

-- Check if a non-aggroed daemonhost is within range. Accepts optional
-- range_sq (default: 20m radius for sprint/abilities, pass DAEMONHOST_COMBAT_RANGE_SQ
-- for the tighter 10m combat suppression radius).
local function _is_near_daemonhost(unit, range_sq)
	return _nearest_dh_dist_sq(unit) < (range_sq or DAEMONHOST_SAFE_RANGE_SQ)
end

local function _is_position_near_daemonhost(reference_unit, position, range_sq)
	local _, dist_sq = _nearest_daemonhost_from_position(reference_unit, position)
	return dist_sq < (range_sq or DAEMONHOST_SAFE_RANGE_SQ)
end

local function _daemonhost_avoidance_enabled()
	return not _is_daemonhost_avoidance_enabled or _is_daemonhost_avoidance_enabled()
end

local function _steer_away_from_daemonhost(self, unit)
	if not _daemonhost_avoidance_enabled() then
		return false
	end

	local daemonhost_unit, dist_sq = _nearest_daemonhost(unit)
	if not daemonhost_unit or dist_sq >= _daemonhost_keepout_range_sq() then
		if self and self._bb_movement_safety_blocked == "daemonhost_keepout" then
			self._bb_movement_safety_blocked = nil
		end
		return false
	end

	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit] or nil
	local daemonhost_position = POSITION_LOOKUP and POSITION_LOOKUP[daemonhost_unit] or nil
	local move = self and self._move
	if not (unit_position and daemonhost_position and move) then
		return false
	end

	local away_x = _vec_component(unit_position, "x", 1) - _vec_component(daemonhost_position, "x", 1)
	local away_y = _vec_component(unit_position, "y", 2) - _vec_component(daemonhost_position, "y", 2)
	local normalized_x, normalized_y = _normalized_flat(away_x, away_y)
	if normalized_x then
		away_x = normalized_x
		away_y = normalized_y or 0
	else
		away_x, away_y = 0, -1
	end

	local rotation = self._first_person_component and self._first_person_component.rotation
	if not rotation and Unit and Unit.local_rotation then
		local ok, unit_rotation = pcall(Unit.local_rotation, unit, 1)
		if ok then
			rotation = unit_rotation
		end
	end

	if rotation and Quaternion and Quaternion.right and Quaternion.forward then
		local away = { x = away_x, y = away_y, z = 0 }
		move.x = _dot(Quaternion.right(rotation), away)
		move.y = _dot(Quaternion.forward(rotation), away)
	else
		move.x = 0
		move.y = -1
	end

	self._dodge = false
	self._bb_movement_safety_blocked = "daemonhost_keepout"

	if _debug_enabled() then
		_debug_log(
			"dh_keepout_move:" .. tostring(unit),
			_fixed_time(),
			string.format(
				"movement safety steered away from daemonhost dist=%.2f keepout=%.2f",
				math.sqrt(dist_sq),
				math.sqrt(_daemonhost_keepout_range_sq())
			),
			1,
			"debug"
		)
	end

	return true
end

local function _should_sprint(self, unit, _input)
	-- Must be moving forward (Sprint.check requires move.y >= 0.7)
	local move = self._move
	if not move or move.y < 0.7 then
		return false, "not_moving_forward"
	end

	if self._bb_movement_safety_blocked then
		return false, tostring(self._bb_movement_safety_blocked)
	end

	-- Never sprint near daemonhosts — triggers aggro via sprint_flat_bonus
	local dh_avoidance = _daemonhost_avoidance_enabled()
	if not dh_avoidance then
		if _debug_enabled() and not _logged_dh_avoidance_off then
			_logged_dh_avoidance_off = true
			_debug_log(
				"dh_avoidance_off:sprint",
				_fixed_time(),
				"daemonhost sprint avoidance disabled by setting",
				nil,
				"info"
			)
		end
	elseif _is_near_daemonhost(unit) then
		return false, "daemonhost_nearby"
	end

	-- Get follow distance from group extension
	local follow_dist = _sprint_follow_distance and _sprint_follow_distance() or DEFAULT_SPRINT_FOLLOW_DISTANCE
	if follow_dist > 0 then
		local group_extension = self._group_extension
		if group_extension then
			local bot_group_data = group_extension:bot_group_data()
			local follow_unit = bot_group_data and bot_group_data.follow_unit
			if follow_unit and _unit_is_alive(follow_unit) then
				local unit_position = POSITION_LOOKUP[unit]
				local follow_position = POSITION_LOOKUP[follow_unit]
				if unit_position and follow_position then
					local dist_sq = Vector3.distance_squared(unit_position, follow_position)
					if dist_sq > follow_dist * follow_dist then
						return true, "catch_up"
					end
				end
			end
		end
	end

	-- Get perception for enemy count and ally needs
	local behavior_extension = ScriptUnit.has_extension(unit, "behavior_system")
	local brain = behavior_extension and behavior_extension._brain
	local blackboard = brain and brain._blackboard
	local perception = blackboard and blackboard.perception

	-- Sprint to rescue allies
	if perception then
		local needs_aid = perception.target_ally_needs_aid
		local need_type = perception.target_ally_need_type
		if needs_aid and need_type ~= "in_need_of_attention_look" and need_type ~= "in_need_of_attention_stop" then
			return true, "ally_rescue"
		end
	end

	-- Sprint during pure traversal (no enemies)
	local perception_extension = ScriptUnit.has_extension(unit, "perception_system")
	if perception_extension then
		local _, num_enemies = perception_extension:enemies_in_proximity()
		if num_enemies == 0 then
			return true, "traversal"
		end
	end

	return false, "enemies_nearby"
end

local _default_should_sprint = _should_sprint

local function on_update_movement(func, self, unit, input, dt, t)
	local perf_t0 = _perf and _perf.begin()
	func(self, unit, input, dt, t)

	if _hazard_avoidance and _hazard_avoidance.on_bot_input_movement_updated then
		_hazard_avoidance.on_bot_input_movement_updated(self, unit)
	end

	_steer_away_from_daemonhost(self, unit)

	local follow_dist = _sprint_follow_distance and _sprint_follow_distance() or DEFAULT_SPRINT_FOLLOW_DISTANCE
	if follow_dist <= 0 then
		if _debug_enabled() and not _logged_sprint_disabled then
			_logged_sprint_disabled = true
			_debug_log("sprint_disabled", _fixed_time(), "sprint disabled (follow_distance=0)", nil, "info")
		end
		if perf_t0 then
			_perf.finish("sprint.update_movement", perf_t0)
		end
		return
	end

	local should, reason = _should_sprint(self, unit, input)

	-- Always set hold_to_sprint so Sprint.sprint_input uses the hold path.
	-- Without this, the else branch sets wants_sprint = is_sprinting,
	-- which keeps an active sprint running even after conditions change.
	input.hold_to_sprint = true
	input.sprinting = should

	-- Debug log for interesting sprint transitions (catch_up, ally_rescue, daemonhost).
	-- Also log the STOP that follows an interesting START so traces are paired.
	local prev = _last_sprint_state_by_unit[unit]
	if should ~= prev then
		_last_sprint_state_by_unit[unit] = should
		local dominated_start = not should and _last_interesting_start_by_unit[unit]
		local dominated_reason = dominated_start or reason
		if reason == "catch_up" or reason == "ally_rescue" or reason == "daemonhost_nearby" or dominated_start then
			if _debug_enabled() then
				local fixed_t = _fixed_time and _fixed_time() or 0
				_debug_log(
					"sprint:" .. tostring(unit),
					fixed_t,
					"sprint " .. (should and "START" or "STOP") .. " (" .. tostring(dominated_reason) .. ")",
					nil,
					"trace"
				)
			end
		end
		_last_interesting_start_by_unit[unit] = should
				and (reason == "catch_up" or reason == "ally_rescue" or reason == "daemonhost_nearby")
				and reason
			or nil
	end

	if perf_t0 then
		_perf.finish("sprint.update_movement", perf_t0)
	end
end

local Sprint = {}

Sprint.init = function(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_sprint_follow_distance = deps.sprint_follow_distance
	_daemonhost_keepout_distance = deps.daemonhost_keepout_distance
	_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled
	_hazard_avoidance = deps.hazard_avoidance
	local shared_rules = deps.shared_rules or {}
	DAEMONHOST_BREED_NAMES = shared_rules.DAEMONHOST_BREED_NAMES or DAEMONHOST_BREED_NAMES
	_is_non_aggroed_daemonhost = shared_rules.is_non_aggroed_daemonhost
	_dh_units_cache_t = nil
	_dh_units_cache_side = nil
	_dh_nearest_unit_by_unit = setmetatable({}, { __mode = "k" })
	_dh_nearest_dist_sq_by_unit = setmetatable({}, { __mode = "k" })
	_dh_cache_t_by_unit = setmetatable({}, { __mode = "k" })
	for i = #_dh_units_cache, 1, -1 do
		_dh_units_cache[i] = nil
	end
end

Sprint.install_bot_unit_input_hooks = function(BotUnitInput)
	_mod:hook(BotUnitInput, "_update_movement", on_update_movement)
end

Sprint.register_hook = function()
	error("BetterBots: Sprint.register_hook is obsolete; install through BetterBots.lua")
end

Sprint.should_sprint = _should_sprint
Sprint._on_update_movement = on_update_movement
Sprint._set_should_sprint_for_test = function(fn)
	_should_sprint = fn or _default_should_sprint
	Sprint.should_sprint = _should_sprint
end
Sprint.is_near_daemonhost = _is_near_daemonhost
Sprint.is_position_near_daemonhost = _is_position_near_daemonhost
Sprint.DAEMONHOST_COMBAT_RANGE_SQ = DAEMONHOST_COMBAT_RANGE_SQ
Sprint.daemonhost_keepout_range_sq = _daemonhost_keepout_range_sq

return Sprint
