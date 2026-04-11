local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _sprint_follow_distance
local _is_daemonhost_avoidance_enabled
local _logged_sprint_disabled = false
local _logged_dh_avoidance_off = false

local DEFAULT_SPRINT_FOLLOW_DISTANCE = 12
local DAEMONHOST_SAFE_RANGE_SQ = 20 * 20
local DAEMONHOST_COMBAT_RANGE_SQ = 10 * 10
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
local _dh_cache_t_by_unit = setmetatable({}, { __mode = "k" })
-- Cache key: (fixed_t, side_system, enemy_side_names). enemy_side_names is
-- compared by reference identity — vanilla Side:relation_side_names returns a
-- stable table from Side._relation_side_names, so same side ⇒ same reference
-- per frame. Including it prevents silent staleness if a future caller passes
-- a different relation list in the same tick (latent correctness hole).
local _dh_units_cache_t = nil
local _dh_units_cache_side_system = nil
local _dh_units_cache_enemy_sides = nil
local _dh_units_cache = {}
local _side_system_warned = false

local function _non_aggroed_daemonhost_units(side_system, enemy_side_names, fixed_t)
	if
		_dh_units_cache_t == fixed_t
		and _dh_units_cache_side_system == side_system
		and _dh_units_cache_enemy_sides == enemy_side_names
	then
		return _dh_units_cache
	end

	for i = #_dh_units_cache, 1, -1 do
		_dh_units_cache[i] = nil
	end

	for _, enemy_side_name in ipairs(enemy_side_names) do
		local enemy_side = side_system:get_side_from_name(enemy_side_name)
		local ai_units = enemy_side and enemy_side.ai_target_units
		if ai_units then
			for i = 1, #ai_units do
				local enemy_unit = ai_units[i]
				if enemy_unit and ALIVE[enemy_unit] then
					local unit_data_ext = ScriptUnit.has_extension(enemy_unit, "unit_data_system")
					if unit_data_ext then
						local breed = unit_data_ext:breed()
						if breed and DAEMONHOST_BREED_NAMES[breed.name] then
							local dh_bb = BLACKBOARDS and BLACKBOARDS[enemy_unit]
							local dh_perception = dh_bb and dh_bb.perception
							local is_aggroed = dh_perception and dh_perception.aggro_state == "aggroed"
							if not is_aggroed then
								_dh_units_cache[#_dh_units_cache + 1] = enemy_unit
							end
						end
					end
				end
			end
		end
	end

	_dh_units_cache_t = fixed_t
	_dh_units_cache_side_system = side_system
	_dh_units_cache_enemy_sides = enemy_side_names

	return _dh_units_cache
end

-- Returns the squared distance to the nearest non-aggroed daemonhost,
-- or math.huge if none exist. Cached per unit per frame.
-- Uses side.ai_target_units (all enemy units on the opposing side).
-- enemies_in_proximity() is unsuitable: it only returns aggroed enemies
-- within a 5m radius — non-aggroed daemonhosts are invisible to that API.
-- Skips aggroed daemonhosts (#17) — once fighting, suppression is
-- pointless and bots should defend themselves.
local function _nearest_dh_dist_sq(unit)
	local fixed_t = _fixed_time()
	if _dh_cache_t_by_unit[unit] == fixed_t then
		return _dh_nearest_dist_sq_by_unit[unit]
	end

	local nearest = math.huge

	local unit_position = POSITION_LOOKUP[unit]
	if not unit_position then
		_dh_cache_t_by_unit[unit] = fixed_t
		_dh_nearest_dist_sq_by_unit[unit] = nearest
		return nearest
	end

	local side_system = Managers and Managers.state and Managers.state.extension
	if not side_system then
		_dh_cache_t_by_unit[unit] = fixed_t
		_dh_nearest_dist_sq_by_unit[unit] = nearest
		return nearest
	end

	local ok, ss = pcall(side_system.system, side_system, "side_system")
	if not ok or not ss then
		if not _side_system_warned then
			_side_system_warned = true
			_debug_log("dh_side_system_fail", 0, "daemonhost scan unavailable, sprint safety disabled", nil, "info")
		end
		_dh_cache_t_by_unit[unit] = fixed_t
		_dh_nearest_dist_sq_by_unit[unit] = nearest
		return nearest
	end

	local side = ss.side_by_unit and ss.side_by_unit[unit]
	if not side then
		_dh_cache_t_by_unit[unit] = fixed_t
		_dh_nearest_dist_sq_by_unit[unit] = nearest
		return nearest
	end

	local enemy_side_names = side:relation_side_names("enemy")
	if not enemy_side_names then
		_dh_cache_t_by_unit[unit] = fixed_t
		_dh_nearest_dist_sq_by_unit[unit] = nearest
		return nearest
	end

	local daemonhost_units = _non_aggroed_daemonhost_units(ss, enemy_side_names, fixed_t)
	for i = 1, #daemonhost_units do
		local enemy_unit = daemonhost_units[i]
		local enemy_pos = POSITION_LOOKUP[enemy_unit]
		if enemy_pos then
			local dist_sq = Vector3.distance_squared(unit_position, enemy_pos)
			if dist_sq < nearest then
				nearest = dist_sq
			end
		end
	end

	_dh_cache_t_by_unit[unit] = fixed_t
	_dh_nearest_dist_sq_by_unit[unit] = nearest
	return nearest
end

-- Check if a non-aggroed daemonhost is within range. Accepts optional
-- range_sq (default: 20m radius for sprint/abilities, pass DAEMONHOST_COMBAT_RANGE_SQ
-- for the tighter 10m combat suppression radius).
local function _is_near_daemonhost(unit, range_sq)
	return _nearest_dh_dist_sq(unit) < (range_sq or DAEMONHOST_SAFE_RANGE_SQ)
end

local function _should_sprint(self, unit, _input)
	-- Must be moving forward (Sprint.check requires move.y >= 0.7)
	local move = self._move
	if not move or move.y < 0.7 then
		return false, "not_moving_forward"
	end

	-- Never sprint near daemonhosts — triggers aggro via sprint_flat_bonus
	local dh_avoidance = not _is_daemonhost_avoidance_enabled or _is_daemonhost_avoidance_enabled()
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
			if follow_unit and ALIVE[follow_unit] then
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

local function on_update_movement(func, self, unit, input, dt, t)
	local perf_t0 = _perf and _perf.begin()
	func(self, unit, input, dt, t)

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
	_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled
	local shared_rules = deps.shared_rules or {}
	DAEMONHOST_BREED_NAMES = shared_rules.DAEMONHOST_BREED_NAMES or DAEMONHOST_BREED_NAMES
	_dh_units_cache_t = nil
	_dh_units_cache_side_system = nil
	_dh_units_cache_enemy_sides = nil
	for i = #_dh_units_cache, 1, -1 do
		_dh_units_cache[i] = nil
	end
end

Sprint.register_hook = function()
	_mod:hook_require("scripts/extension_systems/input/bot_unit_input", function(BotUnitInput)
		_mod:hook(BotUnitInput, "_update_movement", on_update_movement)
	end)
end

Sprint.should_sprint = _should_sprint
Sprint.is_near_daemonhost = _is_near_daemonhost
Sprint.DAEMONHOST_COMBAT_RANGE_SQ = DAEMONHOST_COMBAT_RANGE_SQ

return Sprint
