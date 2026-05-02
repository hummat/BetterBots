local M = {}

local HAZARD_PROP_SENTINEL = "__bb_hazard_avoidance_prop_installed"
local BOT_GROUP_SENTINEL = "__bb_hazard_avoidance_bot_group_installed"
local TRIGGER_DURATION_S = 3
local LEDGE_PROJECTION_DISTANCE = 1.75
local LEDGE_DROP_TOLERANCE = 0.75
local NAV_CHECK_ABOVE = 0.75
local NAV_CHECK_BELOW = 1.5

local _mod
local _debug_log
local _debug_enabled
local _is_hazard_movement_avoidance_enabled
local _hazard_avoidance_buffer
local _NavQueries
local _fixed_time = function()
	return 0
end
local _bot_slot_for_unit
local _last_consumed_key_by_input = setmetatable({}, { __mode = "k" })

local function _is_debug_enabled()
	return _debug_enabled and _debug_enabled()
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

local function _fmt_vec(value)
	return string.format(
		"(%.2f,%.2f,%.2f)",
		_vec_component(value, "x", 1),
		_vec_component(value, "y", 2),
		_vec_component(value, "z", 3)
	)
end

local function _flat_distance(a, b)
	local dx = _vec_component(a, "x", 1) - _vec_component(b, "x", 1)
	local dy = _vec_component(a, "y", 2) - _vec_component(b, "y", 2)

	return math.sqrt(dx * dx + dy * dy)
end

local function _make_vector(x, y, z)
	if Vector3 then
		return Vector3(x, y, z)
	end

	return { x = x, y = y, z = z }
end

local function _normalized_flat(x, y)
	local length = math.sqrt(x * x + y * y)
	if length <= 0.001 then
		return nil, nil
	end

	return x / length, y / length
end

local function _hazard_safety_enabled()
	return not _is_hazard_movement_avoidance_enabled or _is_hazard_movement_avoidance_enabled()
end

local function _resolve_nav_queries(deps)
	if deps and deps.nav_queries then
		return deps.nav_queries
	end

	local ok, nav_queries = pcall(require, "scripts/utilities/nav_queries")
	if ok then
		return nav_queries
	end

	return rawget(_G, "NavQueries")
end

local function _unit_name(unit)
	if _bot_slot_for_unit then
		local ok, slot = pcall(_bot_slot_for_unit, unit)
		if ok and slot then
			return tostring(slot)
		end
	end

	return tostring(unit)
end

local function _unbox(value)
	if value and type(value) == "table" and value.unbox then
		local ok, result = pcall(value.unbox, value)
		if ok then
			return result
		end
	end

	return value
end

local function _explosion_position(unit)
	if not (Unit and unit) then
		return nil
	end

	local ok_has_node, has_node = pcall(function()
		return not Unit.has_node or Unit.has_node(unit, "c_explosion")
	end)
	if not ok_has_node or not has_node then
		return nil
	end

	local ok_node, node = pcall(Unit.node, unit, "c_explosion")
	if not ok_node or node == nil then
		return nil
	end

	local ok_pos, pos = pcall(Unit.world_position, unit, node)
	if ok_pos then
		return pos
	end

	return nil
end

local function _content(self)
	if self and self.content then
		local ok, value = pcall(self.content, self)
		if ok then
			return value
		end
	end

	return self and self._content or nil
end

local function _radius_from_content(content)
	local explosion_template = content and content.explosion_template

	return explosion_template and explosion_template.radius or "unknown"
end

local function _numeric_radius_from_content(content)
	local explosion_template = content and content.explosion_template
	local radius = explosion_template and explosion_template.radius

	return type(radius) == "number" and radius or nil
end

local function _broadphase_position(self)
	if self and self.broadphase_position then
		local ok, value = pcall(self.broadphase_position, self)
		if ok then
			return value
		end
	end

	return self and self._broadphase_position or nil
end

local function _log_hazard_prop_trigger(self)
	if not _is_debug_enabled() then
		return
	end

	local unit = self and (self._unit or self.unit)
	local position = POSITION_LOOKUP and unit and POSITION_LOOKUP[unit] or nil
	local broadphase = _broadphase_position(self)
	local explosion = _explosion_position(unit)
	local content = _content(self)
	local radius = _radius_from_content(content)
	local broadphase_delta = position and broadphase and _flat_distance(position, broadphase) or nil
	local explosion_delta = position and explosion and _flat_distance(position, explosion) or nil

	_debug_log(
		"hazard_prop_triggered:" .. tostring(unit),
		_fixed_time(),
		string.format(
			"hazard_prop triggered unit=%s radius=%s duration=%.2f "
				.. "position=%s broadphase=%s explosion=%s delta_broadphase=%s delta_explosion=%s",
			tostring(unit),
			tostring(radius),
			TRIGGER_DURATION_S,
			_fmt_vec(position),
			_fmt_vec(broadphase),
			_fmt_vec(explosion),
			broadphase_delta and string.format("%.2f", broadphase_delta) or "unknown",
			explosion_delta and string.format("%.2f", explosion_delta) or "unknown"
		),
		nil,
		"info"
	)
end

local function _snapshot_bot_threats(bot_data)
	local snapshot = {}

	for unit, data in pairs(bot_data or {}) do
		local threat = data and data.aoe_threat
		if threat then
			snapshot[unit] = {
				expires = threat.expires or -math.huge,
				escape_direction = _unbox(threat.escape_direction),
			}
		end
	end

	return snapshot
end

local function _log_bot_group_results(self, before, shape, size, duration)
	local bot_data = self and self._bot_data
	local t = self and self._t or _fixed_time()
	local expected_expires = t + (duration or 0)

	for unit, old in pairs(before) do
		local threat = bot_data and bot_data[unit] and bot_data[unit].aoe_threat
		local new_expires = threat and threat.expires or -math.huge
		local escape_direction = threat and _unbox(threat.escape_direction) or nil
		local status

		if old.expires >= expected_expires then
			status = "skipped"
		elseif math.abs(new_expires - expected_expires) < 0.001 and new_expires > old.expires then
			status = "accepted"
		else
			status = "missed"
			escape_direction = old.escape_direction
		end

		_debug_log(
			"aoe_threat:" .. status .. ":" .. tostring(unit) .. ":" .. tostring(expected_expires),
			t,
			string.format(
				"aoe_threat %s unit=%s shape=%s size=%s duration=%.2f old_expires=%.2f new_expires=%.2f escape=%s",
				status,
				_unit_name(unit),
				tostring(shape),
				tostring(size),
				duration or 0,
				old.expires,
				new_expires,
				_fmt_vec(escape_direction)
			),
			0,
			"info"
		)
	end
end

local function _emit_hazard_prop_threat(self)
	if not _hazard_safety_enabled() then
		return
	end

	local unit = self and (self._unit or self.unit)
	local content = _content(self)
	local radius = _numeric_radius_from_content(content)
	local position = _explosion_position(unit) or POSITION_LOOKUP and unit and POSITION_LOOKUP[unit] or nil
	if not (radius and position and Managers and Managers.state and Managers.state.extension and Quaternion) then
		return
	end

	local extension_manager = Managers.state.extension
	local ok_side, side_system = pcall(extension_manager.system, extension_manager, "side_system")
	local ok_group, group_system = pcall(extension_manager.system, extension_manager, "group_system")
	if not (ok_side and side_system and ok_group and group_system) then
		return
	end

	local sides = side_system.sides and side_system:sides() or nil
	local bot_groups = sides and group_system.bot_groups_from_sides and group_system:bot_groups_from_sides(sides) or nil
	if not bot_groups then
		return
	end

	local buffer = _hazard_avoidance_buffer and _hazard_avoidance_buffer() or 0
	local size = radius + math.max(buffer or 0, 0)
	for i = 1, #bot_groups do
		local bot_group = bot_groups[i]
		if bot_group and bot_group.aoe_threat_created then
			bot_group:aoe_threat_created(position, "sphere", size, Quaternion.identity(), TRIGGER_DURATION_S)
		end
	end

	if _is_debug_enabled() then
		_debug_log(
			"hazard_prop_buffered_threat:" .. tostring(unit),
			_fixed_time(),
			string.format(
				"hazard_prop buffered threat unit=%s radius=%.2f buffer=%.2f duration=%.2f position=%s",
				tostring(unit),
				radius,
				math.max(buffer or 0, 0),
				TRIGGER_DURATION_S,
				_fmt_vec(position)
			),
			nil,
			"info"
		)
	end
end

local function _movement_world_direction(self, unit)
	local move = self and self._move
	if not move then
		return nil
	end

	local move_x, move_y = move.x or 0, move.y or 0
	if math.abs(move_x) + math.abs(move_y) <= 0.001 then
		return nil
	end

	local rotation = self._first_person_component and self._first_person_component.rotation
	if not rotation and Unit and Unit.local_rotation and unit then
		local ok, unit_rotation = pcall(Unit.local_rotation, unit, 1)
		if ok then
			rotation = unit_rotation
		end
	end
	if not (rotation and Quaternion and Quaternion.right and Quaternion.forward) then
		return nil
	end

	local right = Quaternion.right(rotation)
	local forward = Quaternion.forward(rotation)
	local dir_x = _vec_component(right, "x", 1) * move_x + _vec_component(forward, "x", 1) * move_y
	local dir_y = _vec_component(right, "y", 2) * move_x + _vec_component(forward, "y", 2) * move_y
	local dir_z = _vec_component(right, "z", 3) * move_x + _vec_component(forward, "z", 3) * move_y
	local flat_x, flat_y = _normalized_flat(dir_x, dir_y)
	if not flat_x then
		return nil
	end

	return flat_x, flat_y, dir_z
end

local function _unsafe_movement_endpoint(self, unit)
	if not (_hazard_safety_enabled() and _NavQueries and _NavQueries.ray_can_go) then
		return nil
	end

	local navigation_extension = self and self._navigation_extension
	local nav_world = navigation_extension and navigation_extension._nav_world
	local traverse_logic = navigation_extension and navigation_extension._traverse_logic
	local position = POSITION_LOOKUP and unit and POSITION_LOOKUP[unit] or nil
	if not (nav_world and traverse_logic and position) then
		return nil
	end

	local dir_x, dir_y = _movement_world_direction(self, unit)
	if not dir_x then
		return nil
	end

	local endpoint = _make_vector(
		_vec_component(position, "x", 1) + dir_x * LEDGE_PROJECTION_DISTANCE,
		_vec_component(position, "y", 2) + dir_y * LEDGE_PROJECTION_DISTANCE,
		_vec_component(position, "z", 3)
	)

	local ok, ray_can_go, projected_start, projected_end =
		pcall(_NavQueries.ray_can_go, nav_world, position, endpoint, traverse_logic, NAV_CHECK_ABOVE, NAV_CHECK_BELOW)
	if not ok or not projected_start or not projected_end then
		return "ledge_projection_failed"
	end
	if not ray_can_go then
		return "ledge_ray_blocked"
	end
	if _vec_component(projected_end, "z", 3) < _vec_component(projected_start, "z", 3) - LEDGE_DROP_TOLERANCE then
		return "ledge_drop"
	end

	return nil
end

local function _apply_endpoint_safety(self, unit)
	local reason = _unsafe_movement_endpoint(self, unit)
	if not reason then
		if self and self._bb_movement_safety_blocked and tostring(self._bb_movement_safety_blocked):find("^ledge_") then
			self._bb_movement_safety_blocked = nil
		end
		return
	end

	local move = self and self._move
	if move then
		move.x = 0
		move.y = 0
	end
	self._dodge = false
	self._bb_movement_safety_blocked = reason

	if _is_debug_enabled() then
		_debug_log(
			"movement_safety:" .. tostring(reason) .. ":" .. tostring(unit),
			_fixed_time(),
			"movement safety blocked unit=" .. _unit_name(unit) .. " reason=" .. tostring(reason),
			0,
			"info"
		)
	end
end

local function _group_threat(self)
	local group_extension = self and self._group_extension
	local bot_group_data = group_extension and group_extension.bot_group_data and group_extension:bot_group_data()

	return bot_group_data and bot_group_data.aoe_threat or nil
end

local function _log_consumed_threat(self, unit)
	if not _is_debug_enabled() or not (self and self._avoiding_aoe_threat) then
		return
	end

	local threat = _group_threat(self)
	if not threat or not threat.expires then
		return
	end

	unit = unit or self._betterbots_player_unit or self._unit
	local key = tostring(unit) .. ":" .. tostring(threat.expires)
	if _last_consumed_key_by_input[self] == key then
		return
	end

	_last_consumed_key_by_input[self] = key

	local now = _fixed_time()
	_debug_log(
		"aoe_threat_consumed:" .. tostring(unit) .. ":" .. tostring(threat.expires),
		now,
		string.format(
			"aoe_threat consumed unit=%s remaining=%.2f move=%s escape=%s",
			_unit_name(unit),
			(threat.expires or now) - now,
			_fmt_vec(self._move),
			_fmt_vec(_unbox(threat.escape_direction))
		),
		0,
		"info"
	)
end

function M.init(deps)
	deps = deps or {}
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_hazard_movement_avoidance_enabled = deps.is_hazard_movement_avoidance_enabled
	_hazard_avoidance_buffer = deps.hazard_avoidance_buffer
	_NavQueries = _resolve_nav_queries(deps)
	_fixed_time = deps.fixed_time or _fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_last_consumed_key_by_input = setmetatable({}, { __mode = "k" })
end

function M.install_hazard_prop_hooks(HazardPropExtension)
	if not HazardPropExtension or rawget(HazardPropExtension, HAZARD_PROP_SENTINEL) then
		return
	end

	HazardPropExtension[HAZARD_PROP_SENTINEL] = true

	_mod:hook(HazardPropExtension, "set_current_state", function(func, self, state)
		local previous_state = self and self.current_state and self:current_state() or self and self._state
		local result = func(self, state)

		if tostring(state) == "triggered" and tostring(previous_state) ~= "triggered" then
			_log_hazard_prop_trigger(self)
			_emit_hazard_prop_threat(self)
		end

		return result
	end)
end

function M.install_bot_group_hooks(BotGroup)
	if not BotGroup or rawget(BotGroup, BOT_GROUP_SENTINEL) then
		return
	end

	BotGroup[BOT_GROUP_SENTINEL] = true

	_mod:hook(BotGroup, "aoe_threat_created", function(func, self, position, shape, size, rotation, duration)
		if not _is_debug_enabled() then
			return func(self, position, shape, size, rotation, duration)
		end

		local before = _snapshot_bot_threats(self and self._bot_data)
		local result = func(self, position, shape, size, rotation, duration)
		_log_bot_group_results(self, before, shape, size, duration)

		return result
	end)
end

function M.on_bot_input_movement_updated(self, unit)
	_log_consumed_threat(self, unit)
	_apply_endpoint_safety(self, unit)
end

return M
