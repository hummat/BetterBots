-- Healing deferral: lets human players take medicae stations and med-crates
-- first unless the bot is below the configured emergency threshold.
local M = {}

local _mod

local function _hook_require_now(path, callback)
	local hook_require_now = _mod and _mod.hook_require_now
	if hook_require_now then
		return hook_require_now(_mod, path, callback, 4)
	end

	if _mod and _mod.warning and _mod._raw_hook_require then
		_mod:warning("BetterBots: hook_require_now_missing for " .. tostring(path))
	end
	return _mod["hook_require"](_mod, path, callback)
end

local _debug_log
local _debug_enabled
local _fixed_time
local _health
local _perf
local _com_wheel
local _health_station_recently_tagged
local _bot_slot_for_unit
local _position_lookup
local _vector3
local _cached_settings
local _cached_settings_fixed_t
local _missing_health_warned
local _last_health_station_log_state_by_unit = setmetatable({}, { __mode = "k" })
local _reserved_health_station_by_unit = setmetatable({}, { __mode = "k" })
local _bot_group_units_scratch = {}
local BOT_GROUP_PATCH_SENTINEL = "__bb_healing_deferral_bot_group_installed"
local INTERACTION_PATCH_SENTINEL = "__bb_healing_deferral_health_station_interaction_installed"

local MODE_SETTING_ID = "healing_deferral_mode"
local HUMAN_THRESHOLD_SETTING_ID = "healing_deferral_human_threshold"
local EMERGENCY_THRESHOLD_SETTING_ID = "healing_deferral_emergency_threshold"
local REQUIRE_STATION_TAG_SETTING_ID = "healing_deferral_require_station_tag"
local DEFAULT_MODE = "stations_and_deployables"
local DEFERRAL_THRESHOLD = 0.9
local EMERGENCY_THRESHOLD = 0.25
local BOT_HEALTH_STATION_PRIORITY_MARGIN = 0.15
local DEFAULT_MAX_INTERACTION_DISTANCE = 2.5
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

local function _read_bool_setting(setting_id, default_value)
	if not _mod then
		return default_value
	end

	local raw_value = _mod:get(setting_id)
	if raw_value == true or raw_value == false then
		return raw_value
	end

	return default_value
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
		require_station_tag = _read_bool_setting(REQUIRE_STATION_TAG_SETTING_ID, false),
	}
	_cached_settings_fixed_t = fixed_t

	return _cached_settings
end

local function _format_percent(value)
	if value == nil then
		return "nil"
	end

	return string.format("%.0f%%", value * 100)
end

local function _debug_health_reserve_detail(bot_health_pct, human_units, threshold, health_pct_fn)
	if not (_debug_enabled and _debug_enabled()) then
		return ""
	end

	local read_health_pct = health_pct_fn or (_health and _health.current_health_percent)
	local lowest_human_health

	if human_units and read_health_pct then
		for i = 1, #human_units do
			local human_unit = human_units[i]
			local human_health_pct = human_unit and read_health_pct(human_unit)

			if human_health_pct and (not lowest_human_health or human_health_pct < lowest_human_health) then
				lowest_human_health = human_health_pct
			end
		end
	end

	return " (bot_health="
		.. _format_percent(bot_health_pct)
		.. ", lowest_human_health="
		.. _format_percent(lowest_human_health)
		.. ", threshold="
		.. _format_percent(threshold or DEFERRAL_THRESHOLD)
		.. ")"
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

local function _unit_preserves_wounded_state(unit)
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

local function _human_counts_for_healing_reserve(human_unit, health_pct, critical_threshold)
	if _unit_preserves_wounded_state(human_unit) and health_pct >= (critical_threshold or EMERGENCY_THRESHOLD) then
		return false
	end

	return true
end

local function _has_human_healing_request(human_units, request_fn)
	if not request_fn then
		return false
	end

	return request_fn(human_units) and true or false
end

local function _any_human_needs_healing(human_units, threshold, health_pct_fn, request_fn, critical_threshold)
	local limit = threshold or DEFERRAL_THRESHOLD
	local read_health_pct = health_pct_fn or (_health and _health.current_health_percent)

	if not (human_units and read_health_pct) then
		return _has_human_healing_request(human_units, request_fn)
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		local human_health_pct = human_unit and read_health_pct(human_unit)

		if
			human_health_pct
			and human_health_pct < limit
			and _human_counts_for_healing_reserve(human_unit, human_health_pct, critical_threshold)
		then
			return true
		end
	end

	return _has_human_healing_request(human_units, request_fn)
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

local function _health_station_extension(station_unit)
	return station_unit
		and ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(station_unit, "health_station_system")
end

local function _health_station_charge_amount(health_station_extension)
	return health_station_extension
			and health_station_extension.charge_amount
			and health_station_extension:charge_amount()
		or 0
end

local function _unit_position(unit)
	local position_lookup = _position_lookup or POSITION_LOOKUP
	return position_lookup and position_lookup[unit] or nil
end

local function _distance_squared_between_units(unit_a, unit_b)
	local position_lookup = _position_lookup or POSITION_LOOKUP
	local vector3 = _vector3 or Vector3
	local position_a = position_lookup and position_lookup[unit_a]
	local position_b = position_lookup and position_lookup[unit_b]
	if not (position_a and position_b and vector3 and vector3.distance_squared) then
		return nil
	end

	return vector3.distance_squared(position_a, position_b)
end

local function _reserved_health_station(unit)
	return unit and _reserved_health_station_by_unit[unit] or nil
end

local function _clear_reserved_health_station(unit, station_unit)
	local reserved_station = _reserved_health_station(unit)
	if not reserved_station then
		return false
	end

	if station_unit and station_unit ~= reserved_station then
		return false
	end

	_reserved_health_station_by_unit[unit] = nil

	return true
end

local function _clear_reserved_health_station_for_all(station_unit)
	if not station_unit then
		return false
	end

	local cleared = false
	for unit, reserved_station in pairs(_reserved_health_station_by_unit) do
		if reserved_station == station_unit then
			_reserved_health_station_by_unit[unit] = nil
			cleared = true
		end
	end

	return cleared
end

local function _format_precise_percent(value)
	if type(value) ~= "number" then
		return "unknown"
	end

	return string.format("%.1f%%", value * 100)
end

local function _format_number(value)
	if type(value) ~= "number" then
		return "unknown"
	end

	return string.format("%.1f", value)
end

local function _format_delta(before, after, formatter)
	return formatter(before) .. "->" .. formatter(after)
end

local function _health_snapshot(unit)
	if not _health then
		return {}
	end

	return {
		health_pct = _health.current_health_percent and _health.current_health_percent(unit) or nil,
		permanent_damage_pct = _health.permanent_damage_taken_percent and _health.permanent_damage_taken_percent(unit)
			or nil,
		damage = _health.damage_taken and _health.damage_taken(unit) or nil,
		permanent_damage = _health.permanent_damage_taken and _health.permanent_damage_taken(unit) or nil,
	}
end

local function _logged_health_station_charge_amount(station_unit)
	local extension = ScriptUnit
		and ScriptUnit.has_extension
		and station_unit
		and ScriptUnit.has_extension(station_unit, "health_station_system")
	if not (extension and extension.charge_amount) then
		return nil
	end

	local ok, charge_amount = pcall(extension.charge_amount, extension)
	if ok then
		return charge_amount
	end

	return nil
end

local function _format_charge_amount(charge_amount)
	if charge_amount == nil then
		return "unknown"
	end

	return tostring(charge_amount)
end

local function _interaction_duration(unit_data_component)
	if not unit_data_component then
		return nil
	end

	local duration = unit_data_component.duration
	if type(duration) == "number" then
		return duration
	end

	local start_time = unit_data_component.start_time
	local done_time = unit_data_component.done_time
	if type(start_time) == "number" and type(done_time) == "number" then
		return done_time - start_time
	end

	return nil
end

local function _format_duration(duration)
	if type(duration) ~= "number" then
		return "unknown"
	end

	return string.format("%.2fs", duration)
end

local function _open_reachable_health_station_interaction(unit, behavior_component, station_unit)
	if not (unit and behavior_component and station_unit) then
		return false
	end

	local health_station_extension = _health_station_extension(station_unit)
	if not health_station_extension or _health_station_charge_amount(health_station_extension) <= 0 then
		return false
	end

	local interactor_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "interactor_system")
	if not (interactor_extension and interactor_extension.can_interact) then
		return false
	end

	local can_interact_ok, can_interact =
		pcall(interactor_extension.can_interact, interactor_extension, station_unit, "health_station")
	if not can_interact_ok or not can_interact then
		return false
	end

	local distance_squared = _distance_squared_between_units(unit, station_unit)
	if not distance_squared then
		return false
	end

	local max_interaction_distance = DEFAULT_MAX_INTERACTION_DISTANCE
	if interactor_extension._max_interaction_distance then
		local distance_ok, resolved_distance =
			pcall(interactor_extension._max_interaction_distance, interactor_extension)
		if distance_ok and type(resolved_distance) == "number" and resolved_distance > 0 then
			max_interaction_distance = resolved_distance
		end
	end

	if distance_squared > max_interaction_distance * max_interaction_distance then
		return false
	end

	local target_level_unit_destination = behavior_component.target_level_unit_destination
	local self_position = _unit_position(unit)
	if not (target_level_unit_destination and target_level_unit_destination.store and self_position) then
		return false
	end

	behavior_component.interaction_unit = station_unit
	-- Vanilla can_use_health_station also checks the stored level-unit destination.
	-- Once the station is in bot interaction range, snap that destination to the bot
	-- so the BT can enter the interaction instead of waiting on path epsilon.
	target_level_unit_destination:store(self_position)

	_log(
		"healing_station_interact_ready:" .. tostring(unit) .. ":" .. tostring(station_unit),
		"health station interaction opened for bot"
	)

	return true
end

local function _apply_reserved_health_station_target(unit, perception_component, station_unit)
	if not (perception_component and station_unit) then
		return
	end

	perception_component.target_level_unit = station_unit
	local distance_squared = _distance_squared_between_units(unit, station_unit)
	if distance_squared then
		perception_component.target_level_unit_distance = distance_squared
	end
end

local function _more_injured_bot_count(unit, bot_units, bot_health_pct, health_pct_fn, priority_margin)
	if not (unit and bot_units and bot_health_pct and health_pct_fn) then
		return 0
	end

	local margin = priority_margin or BOT_HEALTH_STATION_PRIORITY_MARGIN
	local more_injured_count = 0

	for i = 1, #bot_units do
		local other_unit = bot_units[i]

		if other_unit and other_unit ~= unit then
			local other_health_pct = health_pct_fn(other_unit)

			if other_health_pct and other_health_pct + margin < bot_health_pct then
				more_injured_count = more_injured_count + 1
			end
		end
	end

	return more_injured_count
end

local function _collect_bot_group_units(bot_group, out)
	for i = #out, 1, -1 do
		out[i] = nil
	end

	if not bot_group then
		return nil
	end

	local bot_data = bot_group.data and bot_group:data() or bot_group._bot_data

	if not bot_data then
		return nil
	end

	for bot_unit in pairs(bot_data) do
		out[#out + 1] = bot_unit
	end

	return out
end

local function _should_defer_to_more_injured_bot(unit, bot_units, bot_health_pct, charge_amount, health_pct_fn)
	local charges = tonumber(charge_amount) or 0

	if charges < 1 then
		return false
	end

	return _more_injured_bot_count(unit, bot_units, bot_health_pct, health_pct_fn) >= charges
end

local function _apply_health_station_deferral(health_station_component)
	health_station_component.needs_health = false
	health_station_component.needs_health_queue_number = 0
end

local function _mark_destination_refresh(self)
	local follow_component = self and self._follow_component
	if not follow_component then
		return false
	end

	follow_component.needs_destination_refresh = true

	return true
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
	_reserved_health_station_by_unit = setmetatable({}, { __mode = "k" })
	if deps.health_module then
		_health = deps.health_module
	else
		local ok, health_module = pcall(require, "scripts/utilities/health")
		_health = ok and health_module or nil
	end
	_perf = deps.perf
	_com_wheel = deps.com_wheel
	_health_station_recently_tagged = deps.health_station_recently_tagged
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_position_lookup = deps.position_lookup
	_vector3 = deps.vector3
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

function M.can_reserve_health_station(unit, station_unit)
	local settings = _resolve_settings()
	if not settings.require_station_tag then
		return false, "station_tag_not_required"
	end

	if not _mode_allows_resource(settings.mode, "health_station") then
		return false, "mode_disabled"
	end

	if not (_health and _health.current_health_percent) then
		return false, "missing_health"
	end

	local health_station_extension = _health_station_extension(station_unit)
	if not health_station_extension then
		return false, "not_health_station"
	end

	local charge_amount = _health_station_charge_amount(health_station_extension)
	if charge_amount <= 0 then
		return false, "no_charges"
	end

	if _unit_preserves_wounded_state(unit) then
		return false, "preserve_wounded_state"
	end

	local bot_health_pct = _health.current_health_percent(unit)
	local total_damage_pct = math.max(1 - bot_health_pct, 0)
	local permanent_damage_pct = _health.permanent_damage_taken_percent and _health.permanent_damage_taken_percent(unit)
		or 0
	local skip_station_use, skip_reason =
		_should_skip_health_station_use(bot_health_pct, total_damage_pct, permanent_damage_pct, charge_amount, true)

	if skip_station_use then
		return false, skip_reason
	end

	return true, nil
end

function M.reserve_tagged_health_station(unit, station_unit)
	local can_reserve, reason = M.can_reserve_health_station(unit, station_unit)
	if not can_reserve then
		return false, reason
	end

	_reserved_health_station_by_unit[unit] = station_unit
	_log("health_station_reserve:" .. tostring(unit), "reserved tagged health station for bot")

	return true, nil
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
		local reserved_station = _reserved_health_station(unit)
		local target_level_unit = perception_component and perception_component.target_level_unit or nil
		local health_station_extension
		if reserved_station then
			health_station_extension = _health_station_extension(reserved_station)
			if health_station_extension then
				target_level_unit = reserved_station
				_apply_reserved_health_station_target(unit, perception_component, reserved_station)
			else
				_clear_reserved_health_station(unit, reserved_station)
				reserved_station = nil
			end
		end
		if not health_station_extension then
			health_station_extension = _health_station_extension(target_level_unit)
		end
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
		local charge_amount = _health_station_charge_amount(health_station_extension)
		if charge_amount <= 0 then
			if reserved_station then
				_clear_reserved_health_station(unit, reserved_station)
			end
			_apply_health_station_deferral(health_station_component)
			if _health_station_log_state_changed(unit, "reserved_station_empty") then
				_log(
					"healing_station:" .. tostring(unit),
					reserved_station
							and "released explicit health station smart-tag order because the station has no charges"
						or "deferred health station because the station has no charges"
				)
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end
		local skip_station_use, skip_reason = _should_skip_health_station_use(
			bot_health_pct,
			total_damage_pct,
			permanent_damage_pct,
			charge_amount,
			human_units and #human_units > 0
		)

		if skip_station_use then
			if reserved_station then
				_clear_reserved_health_station(unit, reserved_station)
			end
			_apply_health_station_deferral(health_station_component)
			if skip_reason == "full_health" and _health_station_log_state_changed(unit, "full_health") then
				_log("healing_station:" .. tostring(unit), "deferred health station because bot is already full")
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local station_was_tagged = settings.require_station_tag
			and _health_station_recently_tagged
			and _health_station_recently_tagged(target_level_unit)
		local explicit_station_order = reserved_station == target_level_unit
		if settings.require_station_tag and not (station_was_tagged or explicit_station_order) then
			_apply_health_station_deferral(health_station_component)
			if _health_station_log_state_changed(unit, "station_tag_required") then
				_log("healing_station:" .. tostring(unit), "deferred health station until a human smart-tags it")
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
			_com_wheel and _com_wheel.has_recent_health_request,
			settings.emergency_threshold
		)
		local preserve_wounded_state = _unit_preserves_wounded_state(unit)

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
			if preserve_wounded_state and reserved_station then
				_clear_reserved_health_station(unit, reserved_station)
			end
			if preserve_wounded_state then
				_log(
					"healing_station:" .. tostring(unit),
					"deferred health station to preserve Martyrdom wounded state"
				)
			elseif human_request_active then
				_log("healing_station:" .. tostring(unit), "deferred health station to human request")
			else
				_log(
					"healing_station:" .. tostring(unit),
					"deferred health station to human player"
						.. _debug_health_reserve_detail(
							bot_health_pct,
							human_units,
							settings.human_threshold,
							_health.current_health_percent
						)
				)
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		local bot_units = _collect_bot_group_units(self._bot_group, _bot_group_units_scratch)

		if
			_should_defer_to_more_injured_bot(
				unit,
				bot_units,
				bot_health_pct,
				charge_amount,
				_health.current_health_percent
			)
		then
			_apply_health_station_deferral(health_station_component)
			if _health_station_log_state_changed(unit, "bot_priority") then
				_log("healing_station:" .. tostring(unit), "deferred health station to more injured bot")
			end
			if perf_t0 then
				_perf.finish("healing_deferral.health_stations", perf_t0)
			end
			return
		end

		health_station_component.needs_health = true
		health_station_component.needs_health_queue_number = 1
		local interaction_opened =
			_open_reachable_health_station_interaction(unit, self._behavior_component, target_level_unit)
		if
			(station_was_tagged or explicit_station_order)
			and not interaction_opened
			and _mark_destination_refresh(self)
		then
			_log(
				"healing_station_tag_refresh:" .. tostring(unit),
				"health station destination refresh requested from human smart-tag"
			)
		end
		local allow_state = explicit_station_order and "allow_explicit:" .. tostring(target_level_unit) or "allow"
		if _health_station_log_state_changed(unit, allow_state) then
			local allow_message = explicit_station_order and "health station permitted: explicit human smart-tag order"
				or "health station permitted: humans above reserve and bot not full"
			_log(
				"healing_station_allow:" .. tostring(unit),
				allow_message
					.. _debug_health_reserve_detail(
						bot_health_pct,
						human_units,
						settings.human_threshold,
						_health.current_health_percent
					)
			)
		end
		if perf_t0 then
			_perf.finish("healing_deferral.health_stations", perf_t0)
		end
	end)
end

function M.install_interaction_hooks(HealthStationInteraction)
	if not HealthStationInteraction or rawget(HealthStationInteraction, INTERACTION_PATCH_SENTINEL) then
		return
	end

	HealthStationInteraction[INTERACTION_PATCH_SENTINEL] = true

	_mod:hook(
		HealthStationInteraction,
		"stop",
		function(func, self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			-- Reservation cleanup below is functional, not diagnostic — it must
			-- run regardless of the debug setting. Only the _log call is gated.
			if not (interactor_is_server and result == "success") then
				return func(self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			end

			local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(interactor_unit) or nil

			local station_unit = unit_data_component and unit_data_component.target_unit or nil
			local before_health = _health_snapshot(interactor_unit)
			local before_charges = _logged_health_station_charge_amount(station_unit)
			local duration = _interaction_duration(unit_data_component)
			local stop_result = func(self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			local after_health = _health_snapshot(interactor_unit)
			local after_charges = _logged_health_station_charge_amount(station_unit)
			if after_charges ~= nil and after_charges <= 0 then
				_clear_reserved_health_station_for_all(station_unit)
			end
			local charge_consumed = before_charges ~= nil and after_charges ~= nil and after_charges < before_charges
			local health_changed = before_health.health_pct ~= after_health.health_pct
				or before_health.permanent_damage_pct ~= after_health.permanent_damage_pct
				or before_health.damage ~= after_health.damage
				or before_health.permanent_damage ~= after_health.permanent_damage
			local outcome = charge_consumed or health_changed

			-- A successful station interaction satisfies this bot's claim even
			-- when snapshots show no heal/charge delta; keeping it would block
			-- other bots.
			_clear_reserved_health_station(interactor_unit, station_unit)

			if not bot_slot then
				return stop_result
			end

			_log(
				"healing_station_stop:" .. tostring(interactor_unit) .. ":" .. tostring(station_unit),
				(outcome and "health station heal applied: bot=" or "health station no-op: bot=")
					.. tostring(bot_slot)
					.. " result="
					.. tostring(result)
					.. " health="
					.. _format_delta(before_health.health_pct, after_health.health_pct, _format_precise_percent)
					.. " perm="
					.. _format_delta(
						before_health.permanent_damage_pct,
						after_health.permanent_damage_pct,
						_format_precise_percent
					)
					.. " damage="
					.. _format_delta(before_health.damage, after_health.damage, _format_number)
					.. " permanent_damage="
					.. _format_delta(before_health.permanent_damage, after_health.permanent_damage, _format_number)
					.. " charges="
					.. _format_delta(before_charges, after_charges, _format_charge_amount)
					.. " duration="
					.. _format_duration(duration)
			)

			return stop_result
		end
	)
end

function M.register_hooks()
	_hook_require_now(
		"scripts/extension_systems/interaction/interactions/health_station_interaction",
		function(HealthStationInteraction)
			M.install_interaction_hooks(HealthStationInteraction)
		end
	)
end

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
			_com_wheel and _com_wheel.has_recent_health_request,
			settings.emergency_threshold
		)

		for unit, data in pairs(bot_data) do
			local pickup_component = data and data.pickup_component
			if pickup_component and pickup_component.health_deployable then
				local bot_health_pct = _health.current_health_percent(unit)
				local preserve_wounded_state = _unit_preserves_wounded_state(unit)
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
M.should_defer_to_more_injured_bot = _should_defer_to_more_injured_bot
M.bot_preserves_wounded_state = _unit_preserves_wounded_state
M.reserved_health_station = _reserved_health_station
M.apply_health_station_deferral = _apply_health_station_deferral
M.apply_health_deployable_deferral = _apply_health_deployable_deferral
M.resolve_settings = _resolve_settings

return M
