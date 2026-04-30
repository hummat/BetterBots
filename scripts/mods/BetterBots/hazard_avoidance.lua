local M = {}

local HAZARD_PROP_SENTINEL = "__bb_hazard_avoidance_prop_installed"
local BOT_GROUP_SENTINEL = "__bb_hazard_avoidance_bot_group_installed"
local TRIGGER_DURATION_S = 3

local _mod
local _debug_log
local _debug_enabled
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
end

return M
