-- Healing deferral: lets human players take medicae stations and med-crates
-- first unless the bot is below the configured emergency threshold.
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _health
local _perf
local _com_wheel
local _cached_settings
local _cached_settings_fixed_t
local _missing_health_warned
local _last_health_station_log_state_by_unit = setmetatable({}, { __mode = "k" })
local BOT_GROUP_PATCH_SENTINEL = "__bb_healing_deferral_bot_group_installed"

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
local function _read_percent_setting(setting_id, default_value, min_value, max_value)
	if not _mod then
		return default_value
	end

	local raw_value = _mod:get(setting_id)
	local numeric_value = tonumber(raw_value)
	if not numeric_value then
		return default_value
	end

	if numeric_value < min_value or numeric_value > max_value then
		return default_value
	end

	return numeric_value / 100
end

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _health_station_log_state_changed(unit, state)
	if _last_health_station_log_state_by_unit[unit] == state then
		return false
	end

	_last_health_station_log_state_by_unit[unit] = state

	return true
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
	return _read_percent_setting(HUMAN_THRESHOLD_SETTING_ID, DEFERRAL_THRESHOLD, 50, 100)
end

local function _read_emergency_threshold_setting()
	return _read_percent_setting(EMERGENCY_THRESHOLD_SETTING_ID, EMERGENCY_THRESHOLD, 0, 50)
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

local function _any_human_needs_healing(human_units, threshold, health_pct_fn, request_fn)
	local limit = threshold or DEFERRAL_THRESHOLD
	local read_health_pct = health_pct_fn or (_health and _health.current_health_percent)

	if request_fn and request_fn(human_units) then
		return true
	end

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

local function _bot_preserves_wounded_state(unit)
	if not (unit and ScriptUnit and ScriptUnit.has_extension) then
		return false
	end

	local talent_extension = ScriptUnit.has_extension(unit, "talent_system")
	if not (talent_extension and talent_extension.talents) then
		return false
	end

	local talents = talent_extension:talents()
	return talents and talents.zealot_martyrdom ~= nil or false
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

local function _should_defer_resource(
	resource_kind,
	bot_health_pct,
	human_needs_healing,
	settings,
	preserve_wounded_state
)
	if not (settings and _mode_allows_resource(settings.mode, resource_kind)) then
		return false
	end
	if preserve_wounded_state then
		return true
	end

	return _should_defer_healing(bot_health_pct, human_needs_healing, settings.emergency_threshold)
end

local function _should_skip_health_station_use(
	bot_health_pct,
	total_damage_pct,
	permanent_damage_pct,
	charge_amount,
	has_humans
)
	local total_damage = total_damage_pct or (1 - (bot_health_pct or 1))
	local _ = permanent_damage_pct
	_ = charge_amount
	_ = has_humans

	if total_damage <= 0.001 then
		return true, "full_health"
	end

	return false, nil
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
	_last_health_station_log_state_by_unit = setmetatable({}, { __mode = "k" })
	if deps.health_module then
		_health = deps.health_module
	else
		local ok, health_module = pcall(require, "scripts/utilities/health")
		_health = ok and health_module or nil
	end
	_perf = deps.perf
	_com_wheel = deps.com_wheel
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

-- Called from the consolidated bot_behavior_extension hook_require in BetterBots.lua.
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
		if not health_station_component then
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local perception_component = self._perception_component
		local target_level_unit = perception_component and perception_component.target_level_unit or nil
		local health_station_extension = target_level_unit
			and ScriptUnit.has_extension(target_level_unit, "health_station_system")
		if not health_station_extension then
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end
		local human_units = self._side and self._side.valid_human_units or nil
		local bot_health_pct = _health.current_health_percent(unit)
		local total_damage_pct = math.max(1 - bot_health_pct, 0)
		local permanent_damage_pct = _health.permanent_damage_taken_percent
				and _health.permanent_damage_taken_percent(unit)
			or 0
		local charge_amount = health_station_extension.charge_amount and health_station_extension:charge_amount() or 0
		local skip_station_use, skip_reason = _should_skip_health_station_use(
			bot_health_pct,
			total_damage_pct,
			permanent_damage_pct,
			charge_amount,
			human_units and #human_units > 0
		)

		if skip_station_use then
			_apply_health_station_deferral(health_station_component)
			if skip_reason == "full_health" and _health_station_log_state_changed(unit, "full_health") then
				_log("healing_station:" .. tostring(unit), "deferred health station because bot is already full")
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local human_request_active = _com_wheel
				and _com_wheel.has_recent_health_request
				and _com_wheel.has_recent_health_request(human_units)
			or false
		local human_needs_healing = _any_human_needs_healing(
			human_units,
			settings.human_threshold,
			nil,
			_com_wheel and _com_wheel.has_recent_health_request
		)
		local preserve_wounded_state = _bot_preserves_wounded_state(unit)

		if
			_should_defer_resource(
				"health_station",
				bot_health_pct,
				human_needs_healing,
				settings,
				preserve_wounded_state
			)
		then
			_apply_health_station_deferral(health_station_component)
			if preserve_wounded_state then
				_log(
					"healing_station:" .. tostring(unit),
					"deferred health station to preserve Martyrdom wounded state"
				)
			elseif human_request_active then
				_log("healing_station:" .. tostring(unit), "deferred health station to human request")
			else
				_log("healing_station:" .. tostring(unit), "deferred health station to human player")
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		health_station_component.needs_health = true
		health_station_component.needs_health_queue_number = 1
		if _health_station_log_state_changed(unit, "allow") then
			_log(
				"healing_station_allow:" .. tostring(unit),
				"health station permitted: humans above reserve and bot not full"
			)
		end
		if perf_t0 then
			_perf.finish("healing_deferral.health_stations", perf_t0)
		end
	end)
end

function M.register_hooks() end

function M.install_bot_group_hooks(BotGroup)
	if not BotGroup or rawget(BotGroup, BOT_GROUP_PATCH_SENTINEL) then
		return
	end

	BotGroup[BOT_GROUP_PATCH_SENTINEL] = true

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
		local human_units = side and side.valid_human_units
		local human_request_active = _com_wheel
				and _com_wheel.has_recent_health_request
				and _com_wheel.has_recent_health_request(human_units)
			or false
		local human_needs_healing = _any_human_needs_healing(
			human_units,
			settings.human_threshold,
			nil,
			_com_wheel and _com_wheel.has_recent_health_request
		)

		for unit, data in pairs(bot_data) do
			local pickup_component = data and data.pickup_component
			if pickup_component and pickup_component.health_deployable then
				local bot_health_pct = _health.current_health_percent(unit)
				local preserve_wounded_state = _bot_preserves_wounded_state(unit)
				if
					_should_defer_resource(
						"health_deployable",
						bot_health_pct,
						human_needs_healing,
						settings,
						preserve_wounded_state
					)
				then
					_apply_health_deployable_deferral(pickup_component)
					if preserve_wounded_state then
						_log(
							"healing_deployable:" .. tostring(unit),
							"deferred medical crate to preserve Martyrdom wounded state"
						)
					elseif human_request_active then
						_log("healing_deployable:" .. tostring(unit), "deferred medical crate to human request")
					else
						_log("healing_deployable:" .. tostring(unit), "deferred medical crate to human player")
					end
				end
			end
		end

		if perf_t0 then
			_perf.finish("healing_deferral.health_deployables", perf_t0)
		end
	end)
end

M.any_human_needs_healing = _any_human_needs_healing
M.should_defer_healing = _should_defer_healing
M.should_defer_resource = _should_defer_resource
M.should_skip_health_station_use = _should_skip_health_station_use
M.bot_preserves_wounded_state = _bot_preserves_wounded_state
M.apply_health_station_deferral = _apply_health_station_deferral
M.apply_health_deployable_deferral = _apply_health_deployable_deferral
M.resolve_settings = _resolve_settings

return M
