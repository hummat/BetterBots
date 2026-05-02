local M = {}

local _fixed_time
local _debug_log
local _debug_enabled
local _is_enabled
local _NavQueries
local _resolve_bot_target_unit_fn
local _is_position_near_daemonhost

local NAV_CHECK_ABOVE = 0.75
local NAV_CHECK_BELOW = 0.5
-- Negative results are cheap to repeat but still cost a GwNav ray query. A
-- short cooldown collapses repeated same-endpoint failures inside one burst
-- without leaving the bot blind for a meaningful amount of time.
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

local TARGETED_DASH_TEMPLATES = {
	zealot_dash = true,
	zealot_targeted_dash = true,
	zealot_targeted_dash_improved = true,
	zealot_targeted_dash_improved_double = true,
}

-- Cache shape: unit -> { template_name, destination_key, reason, until_t }.
-- The destination key stays in the cache key so a bot immediately re-checks
-- when the launch endpoint changes, even inside the cooldown window.
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

local function _resolve_bot_target_unit(perception_component)
	if _resolve_bot_target_unit_fn then
		return _resolve_bot_target_unit_fn(perception_component)
	end

	if not perception_component then
		return nil
	end

	return perception_component.target_enemy
		or perception_component.priority_target_enemy
		or perception_component.opportunity_target_enemy
		or perception_component.urgent_target_enemy
end

local function _resolve_target_position(template_name, options, navigation_extension)
	options = options or {}

	if options.target_position then
		return options.target_position, _destination_key(options.target_position), false
	end

	if TARGETED_DASH_TEMPLATES[template_name] then
		local blackboard = options.blackboard
		local perception = blackboard and blackboard.perception
		local target_unit = _resolve_bot_target_unit(perception)
		local target_position = target_unit and POSITION_LOOKUP and POSITION_LOOKUP[target_unit] or nil
		if target_position then
			return target_position, _destination_key(target_position), false
		end
	end

	local destination = navigation_extension.destination and navigation_extension:destination() or nil
	if destination then
		return destination, _destination_key(destination), true
	end

	return nil, "missing_destination", true
end

local function _log_block(unit, source, template_name, fixed_t, reason)
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
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

local function _log_validated(unit, source, template_name, fixed_t)
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(
		"charge_nav:validated:" .. tostring(template_name) .. ":" .. tostring(unit),
		fixed_t,
		tostring(source) .. " validated " .. tostring(template_name) .. " (charge_nav=clear)"
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
	if _is_enabled and not _is_enabled() then
		return false
	end

	return CHARGE_DASH_TEMPLATES[template_name] == true
end

function M.validate(unit, template_name, source, options)
	if not M.should_validate(template_name) then
		return true
	end
	if not _fixed_time or not _NavQueries or not ScriptUnit or not ScriptUnit.has_extension then
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

	if not position then
		return _remember_block(unit, template_name, source, fixed_t, "missing_position", "missing_position")
	end

	local target_position, target_key, is_navigation_destination =
		_resolve_target_position(template_name, options, navigation_extension)
	if not target_position then
		return _remember_block(unit, template_name, source, fixed_t, "missing_destination", target_key)
	end

	local blocked_state = _blocked_state_by_unit[unit]
	if
		blocked_state
		and blocked_state.template_name == template_name
		and blocked_state.destination_key == target_key
		and fixed_t < blocked_state.until_t
	then
		local cached_reason = "cached_" .. tostring(blocked_state.reason)
		_log_block(unit, source, template_name, fixed_t, cached_reason)
		return false, cached_reason
	end

	if
		is_navigation_destination
		and navigation_extension.destination_reached
		and navigation_extension:destination_reached()
	then
		return _remember_block(unit, template_name, source, fixed_t, "destination_reached", target_key)
	end

	if _distance_squared(position, target_position) <= MIN_DESTINATION_DIST_SQ then
		local too_close_reason = is_navigation_destination and "destination_too_close" or "target_too_close"
		return _remember_block(unit, template_name, source, fixed_t, too_close_reason, target_key)
	end

	if _is_position_near_daemonhost and _is_position_near_daemonhost(unit, target_position) then
		return _remember_block(unit, template_name, source, fixed_t, "daemonhost_target_near", target_key)
	end

	local nav_world = navigation_extension._nav_world
	if not nav_world then
		return _remember_block(unit, template_name, source, fixed_t, "missing_nav_world", target_key)
	end

	local traverse_logic = navigation_extension._traverse_logic
	if not traverse_logic then
		return _remember_block(unit, template_name, source, fixed_t, "missing_traverse_logic", target_key)
	end
	local ray_can_go, projected_start_position, projected_end_position =
		_NavQueries.ray_can_go(nav_world, position, target_position, traverse_logic, NAV_CHECK_ABOVE, NAV_CHECK_BELOW)

	if not projected_start_position or not projected_end_position then
		return _remember_block(unit, template_name, source, fixed_t, "projection_failed", target_key)
	end

	if not ray_can_go then
		return _remember_block(unit, template_name, source, fixed_t, "ray_blocked", target_key)
	end

	_blocked_state_by_unit[unit] = nil
	_log_validated(unit, source, template_name, fixed_t)
	return true
end

function M.init(deps)
	_fixed_time = deps.fixed_time
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_enabled = deps.is_enabled
	_NavQueries = deps.nav_queries or require("scripts/utilities/nav_queries")
	local bot_targeting = deps.bot_targeting
	_resolve_bot_target_unit_fn = bot_targeting and bot_targeting.resolve_bot_target_unit or nil
	_is_position_near_daemonhost = deps.is_position_near_daemonhost
end

return M
