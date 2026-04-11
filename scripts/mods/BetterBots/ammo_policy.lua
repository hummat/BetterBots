local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _Ammo
local _Settings
local _human_ammo_scan_cache = {}

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _bot_threshold()
	return (_Settings and _Settings.bot_ranged_ammo_threshold and _Settings.bot_ranged_ammo_threshold()) or 0.20
end

local function _human_threshold()
	return (_Settings and _Settings.human_ammo_reserve_threshold and _Settings.human_ammo_reserve_threshold()) or 0.80
end

local function _all_eligible_humans_above_threshold(human_units, threshold)
	if not (human_units and _Ammo) then
		return true
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	if
		_human_ammo_scan_cache.fixed_t == fixed_t
		and _human_ammo_scan_cache.human_units == human_units
		and _human_ammo_scan_cache.threshold == threshold
	then
		return _human_ammo_scan_cache.result
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		if human_unit and _Ammo.uses_ammo(human_unit) then
			local ammo_percentage = _Ammo.current_total_percentage(human_unit)
			if ammo_percentage <= threshold then
				_human_ammo_scan_cache = {
					fixed_t = fixed_t,
					human_units = human_units,
					threshold = threshold,
					result = false,
				}
				return false
			end
		end
	end

	_human_ammo_scan_cache = {
		fixed_t = fixed_t,
		human_units = human_units,
		threshold = threshold,
		result = true,
	}
	return true
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_Ammo = deps.ammo_module or require("scripts/utilities/ammo")
	_Settings = deps.settings
	_human_ammo_scan_cache = {}
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_update_ammo", function(self, unit)
		local perf_t0 = _perf and _perf.begin()
		local pickup_component = self._pickup_component
		if not pickup_component then
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local bot_group = self._bot_group
		if bot_group and bot_group:ammo_pickup_order_unit(unit) ~= nil then
			pickup_component.needs_ammo = true
			_log("ammo_pickup_order:" .. tostring(unit), "ammo pickup preserved due to explicit order")
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local humans_ok =
			_all_eligible_humans_above_threshold(self._side and self._side.valid_human_units, _human_threshold())

		if humans_ok then
			-- All humans are stocked — bot picks up freely to top off.
			pickup_component.needs_ammo = true
			_log("ammo_pickup_allow:" .. tostring(unit), "ammo pickup permitted: all eligible humans above reserve")
		else
			-- A human is low — bot only picks up when desperate (below bot threshold).
			local bot_ammo_percentage = _Ammo.current_total_percentage(unit)
			local bot_threshold = _bot_threshold()
			local bot_desperate = bot_ammo_percentage <= bot_threshold
			pickup_component.needs_ammo = bot_desperate
			if bot_desperate then
				_log(
					"ammo_pickup_desperate:" .. tostring(unit),
					"ammo pickup permitted: bot desperate ("
						.. string.format("%.0f%% <= %.0f%%", bot_ammo_percentage * 100, bot_threshold * 100)
						.. ") despite human reserve low"
				)
			else
				_log(
					"ammo_pickup_defer:" .. tostring(unit),
					"ammo pickup deferred to human ("
						.. string.format("bot %.0f%% > %.0f%%", bot_ammo_percentage * 100, bot_threshold * 100)
						.. ")"
				)
			end
		end

		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
	end)
end

M.all_eligible_humans_above_threshold = _all_eligible_humans_above_threshold

return M
