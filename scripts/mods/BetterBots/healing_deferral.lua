-- Healing deferral: lets human players take medicae stations and med-crates
-- first unless the bot is below the configured emergency threshold.
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _health
local _perf
local _cached_settings
local _cached_settings_fixed_t
local _missing_health_warned

local MODE_SETTING_ID = "healing_deferral_mode"
local HUMAN_THRESHOLD_SETTING_ID = "healing_deferral_human_threshold"
local EMERGENCY_THRESHOLD_SETTING_ID = "healing_deferral_emergency_threshold"
local DEFAULT_MODE = "stations_and_deployables"
local DEFERRAL_THRESHOLD = 0.9
local EMERGENCY_THRESHOLD = 0.25
local VALID_MODES = {
	off = true,
	stations_only = true,
	stations_and_deployables = true,
}
local HUMAN_THRESHOLD_BY_SETTING = {
	["50"] = 0.50,
	["75"] = 0.75,
	["90"] = 0.90,
	["100"] = 1.00,
}
local EMERGENCY_THRESHOLD_BY_SETTING = {
	never = 0,
	["10"] = 0.10,
	["25"] = 0.25,
	["40"] = 0.40,
}

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _read_mode_setting()
	if not _mod then
		return DEFAULT_MODE
	end

	local mode = _mod:get(MODE_SETTING_ID)
	if VALID_MODES[mode] then
		return mode
	end

	return DEFAULT_MODE
end

local function _read_human_threshold_setting()
	if not _mod then
		return DEFERRAL_THRESHOLD
	end

	local value = _mod:get(HUMAN_THRESHOLD_SETTING_ID)
	return HUMAN_THRESHOLD_BY_SETTING[value] or DEFERRAL_THRESHOLD
end

local function _read_emergency_threshold_setting()
	if not _mod then
		return EMERGENCY_THRESHOLD
	end

	local value = _mod:get(EMERGENCY_THRESHOLD_SETTING_ID)
	return EMERGENCY_THRESHOLD_BY_SETTING[value] or EMERGENCY_THRESHOLD
end

local function _resolve_settings()
	local fixed_t = _fixed_time and _fixed_time() or nil
	if _cached_settings and _cached_settings_fixed_t == fixed_t then
		return _cached_settings
	end

	_cached_settings = {
		mode = _read_mode_setting(),
		human_threshold = _read_human_threshold_setting(),
		emergency_threshold = _read_emergency_threshold_setting(),
	}
	_cached_settings_fixed_t = fixed_t

	return _cached_settings
end

local function _any_human_needs_healing(human_units, threshold, health_pct_fn)
	local limit = threshold or DEFERRAL_THRESHOLD
	local read_health_pct = health_pct_fn or (_health and _health.current_health_percent)

	if not (human_units and read_health_pct) then
		return false
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]

		if human_unit and read_health_pct(human_unit) < limit then
			return true
		end
	end

	return false
end

local function _should_defer_healing(bot_health_pct, human_needs_healing, emergency_threshold)
	if not human_needs_healing then
		return false
	end

	if bot_health_pct < (emergency_threshold or EMERGENCY_THRESHOLD) then
		return false
	end

	return true
end

local function _mode_allows_resource(mode, resource_kind)
	if mode == "stations_and_deployables" then
		return true
	end

	if mode == "stations_only" then
		return resource_kind == "health_station"
	end

	return false
end

local function _should_defer_resource(resource_kind, bot_health_pct, human_needs_healing, settings)
	if not (settings and _mode_allows_resource(settings.mode, resource_kind)) then
		return false
	end

	return _should_defer_healing(bot_health_pct, human_needs_healing, settings.emergency_threshold)
end

local function _apply_health_station_deferral(health_station_component)
	health_station_component.needs_health = false
	health_station_component.needs_health_queue_number = 0
end

local function _apply_health_deployable_deferral(pickup_component)
	pickup_component.health_deployable = nil
	pickup_component.health_deployable_distance = math.huge
	pickup_component.health_deployable_valid_until = -math.huge
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_cached_settings = nil
	_cached_settings_fixed_t = nil
	_missing_health_warned = false
	if deps.health_module then
		_health = deps.health_module
	else
		local ok, health_module = pcall(require, "scripts/utilities/health")
		_health = ok and health_module or nil
	end
	_perf = deps.perf
end

local function _warn_missing_health_once()
	if _missing_health_warned then
		return
	end

	_missing_health_warned = true

	if _mod and _mod.warning then
		_mod:warning("BetterBots: healing deferral disabled; failed to load scripts/utilities/health")
	end

	_log("healing_deferral_missing_health", "healing deferral disabled: health utility unavailable")
end

-- Called from the consolidated bot_behavior_extension hook_require in BetterBots.lua (#67).
function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_update_health_stations", function(self, unit)
		local perf_t0 = _perf and _perf.begin()
		if not (_health and _health.current_health_percent) then
			_warn_missing_health_once()
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local settings = _resolve_settings()
		if not _mode_allows_resource(settings.mode, "health_station") then
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local health_station_component = self._health_station_component
		if not (health_station_component and health_station_component.needs_health) then
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local side = self._side
		local human_needs_healing = _any_human_needs_healing(side and side.valid_human_units, settings.human_threshold)
		local bot_health_pct = _health.current_health_percent(unit)

		if not _should_defer_resource("health_station", bot_health_pct, human_needs_healing, settings) then
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		_apply_health_station_deferral(health_station_component)
		_log("healing_station:" .. tostring(unit), "deferred health station to human player")
		if perf_t0 then
			_perf.finish("healing_deferral.health_stations", perf_t0)
		end
	end)
end

function M.register_hooks()
	_mod:hook_require("scripts/extension_systems/group/bot_group", function(BotGroup)
		_mod:hook_safe(BotGroup, "_update_pickups_and_deployables_near_player", function(self, bot_data)
			local perf_t0 = _perf and _perf.begin()
			if not (_health and _health.current_health_percent) then
				_warn_missing_health_once()
				if perf_t0 then
					_perf.finish("healing_deferral.health_deployables", perf_t0)
				end
				return
			end

			local settings = _resolve_settings()
			if not _mode_allows_resource(settings.mode, "health_deployable") then
				if perf_t0 then
					_perf.finish("healing_deferral.health_deployables", perf_t0)
				end
				return
			end

			local side = self._side
			local human_needs_healing =
				_any_human_needs_healing(side and side.valid_human_units, settings.human_threshold)
			if not human_needs_healing then
				if perf_t0 then
					_perf.finish("healing_deferral.health_deployables", perf_t0)
				end
				return
			end

			for unit, data in pairs(bot_data) do
				local pickup_component = data and data.pickup_component
				if pickup_component and pickup_component.health_deployable then
					local bot_health_pct = _health.current_health_percent(unit)
					if _should_defer_resource("health_deployable", bot_health_pct, human_needs_healing, settings) then
						_apply_health_deployable_deferral(pickup_component)
						_log("healing_deployable:" .. tostring(unit), "deferred medical crate to human player")
					end
				end
			end

			if perf_t0 then
				_perf.finish("healing_deferral.health_deployables", perf_t0)
			end
		end)
	end)

	-- The issue body also mentioned pocketable health pickups, but the decompiled
	-- Lua path is currently dead for bots (`bots_mule_pickup` is not set on the
	-- relevant templates). Don't hook a dead path and claim behavior we can't prove.
end

M.any_human_needs_healing = _any_human_needs_healing
M.should_defer_healing = _should_defer_healing
M.should_defer_resource = _should_defer_resource
M.apply_health_station_deferral = _apply_health_station_deferral
M.apply_health_deployable_deferral = _apply_health_deployable_deferral
M.resolve_settings = _resolve_settings

return M
