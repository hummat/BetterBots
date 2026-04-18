local M = {}

local _fixed_time
local _debug_log
local _debug_enabled
local _NavQueries

local NAV_CHECK_ABOVE = 0.75
local NAV_CHECK_BELOW = 0.5
local NEGATIVE_CACHE_COOLDOWN_S = 0.5
local MIN_DESTINATION_DIST_SQ = 0.0625

local CHARGE_DASH_TEMPLATES = {
	zealot_dash = true,
	zealot_targeted_dash = true,
	zealot_targeted_dash_improved = true,
	zealot_targeted_dash_improved_double = true,
	ogryn_charge = true,
	ogryn_charge_increased_distance = true,
	adamant_charge = true,
}

local _blocked_state_by_unit = setmetatable({}, { __mode = "k" })

local function _distance_squared(a, b)
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	local dz = (a.z or 0) - (b.z or 0)
	return dx * dx + dy * dy + dz * dz
end

local function _destination_key(position)
	if not position then
		return "nil"
	end

	return string.format("%.3f:%.3f:%.3f", position.x or 0, position.y or 0, position.z or 0)
end

local function _log_block(unit, source, template_name, fixed_t, reason)
	if not _debug_enabled() then
		return
	end

	_debug_log(
		"charge_nav:"
			.. tostring(source)
			.. ":"
			.. tostring(template_name)
			.. ":"
			.. tostring(reason)
			.. ":"
			.. tostring(unit),
		fixed_t,
		tostring(source) .. " blocked " .. tostring(template_name) .. " (charge_nav=" .. tostring(reason) .. ")"
	)
end

local function _remember_block(unit, template_name, source, fixed_t, reason, destination_key)
	_blocked_state_by_unit[unit] = {
		template_name = template_name,
		reason = reason,
		destination_key = destination_key,
		until_t = fixed_t + NEGATIVE_CACHE_COOLDOWN_S,
	}
	_log_block(unit, source, template_name, fixed_t, reason)
	return false, reason
end

function M.should_validate(template_name)
	return CHARGE_DASH_TEMPLATES[template_name] == true
end

function M.validate(unit, template_name, source)
	if not M.should_validate(template_name) then
		return true
	end

	local fixed_t = _fixed_time()
	local position = POSITION_LOOKUP and POSITION_LOOKUP[unit] or nil
	local navigation_extension = ScriptUnit.has_extension(unit, "navigation_system")

	if not navigation_extension then
		return _remember_block(
			unit,
			template_name,
			source,
			fixed_t,
			"missing_navigation_extension",
			"missing_navigation"
		)
	end

	local destination = navigation_extension.destination and navigation_extension:destination() or nil
	if not position then
		return _remember_block(unit, template_name, source, fixed_t, "missing_position", "missing_position")
	end
	if not destination then
		return _remember_block(unit, template_name, source, fixed_t, "missing_destination", "missing_destination")
	end

	local destination_key = _destination_key(destination)
	local blocked_state = _blocked_state_by_unit[unit]
	if
		blocked_state
		and blocked_state.template_name == template_name
		and blocked_state.destination_key == destination_key
		and fixed_t < blocked_state.until_t
	then
		local cached_reason = "cached_" .. tostring(blocked_state.reason)
		_log_block(unit, source, template_name, fixed_t, cached_reason)
		return false, cached_reason
	end

	if navigation_extension.destination_reached and navigation_extension:destination_reached() then
		return _remember_block(unit, template_name, source, fixed_t, "destination_reached", destination_key)
	end

	if _distance_squared(position, destination) <= MIN_DESTINATION_DIST_SQ then
		return _remember_block(unit, template_name, source, fixed_t, "destination_too_close", destination_key)
	end

	local nav_world = navigation_extension._nav_world
	if not nav_world then
		return _remember_block(unit, template_name, source, fixed_t, "missing_nav_world", destination_key)
	end

	local traverse_logic = navigation_extension._traverse_logic
	local ray_can_go, projected_start_position, projected_end_position =
		_NavQueries.ray_can_go(nav_world, position, destination, traverse_logic, NAV_CHECK_ABOVE, NAV_CHECK_BELOW)

	if not projected_start_position or not projected_end_position then
		return _remember_block(unit, template_name, source, fixed_t, "projection_failed", destination_key)
	end

	if not ray_can_go then
		return _remember_block(unit, template_name, source, fixed_t, "ray_blocked", destination_key)
	end

	_blocked_state_by_unit[unit] = nil
	return true
end

function M.init(deps)
	_fixed_time = deps.fixed_time
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_NavQueries = deps.nav_queries or require("scripts/utilities/nav_queries")
end

return M
