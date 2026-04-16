local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _Ammo
local _Settings
local _ability_extension
local _bot_slot_for_unit
local _nearby_grenade_pickups
local _is_enabled
local _human_ammo_scan_cache = {}
local _human_grenade_scan_cache = {}
local _last_ammo_pickup_log_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_grenade_skip_log_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_grenade_pickup_log_state_by_unit = setmetatable({}, { __mode = "k" })
local INTERACTION_PATCH_SENTINEL = "__bb_ammo_policy_stop_installed"

local PICKUP_BROADPHASE_CATEGORY = {
	"pickups",
}
local PICKUP_QUERY_RESULTS = {}
local PICKUP_MAX_DISTANCE = 5
local PICKUP_MAX_FOLLOW_DISTANCE = 15
local NON_PICKUP_GRENADE_ABILITIES = {
	adamant_whistle = true,
	ogryn_grenade_friend_rock = true,
	psyker_throwing_knives = true,
	zealot_throwing_knives = true,
}
local AMMO_REFILL_GRENADE_ABILITIES = {
	zealot_throwing_knives = true,
}
local _grenade_ability_name
local _needs_ammo_pickup_for_grenade_refill

local function _cached_scan_result(cache, fixed_t, human_units, threshold)
	if cache.fixed_t == fixed_t and cache.human_units == human_units and cache.threshold == threshold then
		return cache.result
	end

	return nil
end

local function _store_scan_result(cache, fixed_t, human_units, threshold, result)
	cache.fixed_t = fixed_t
	cache.human_units = human_units
	cache.threshold = threshold
	cache.result = result

	return result
end

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _clear_grenade_skip_log_state(unit)
	_last_grenade_skip_log_state_by_unit[unit] = nil
end

local function _clear_ammo_pickup_log_state(unit)
	_last_ammo_pickup_log_state_by_unit[unit] = nil
end

local function _ammo_pickup_log_state_changed(unit, state)
	if _last_ammo_pickup_log_state_by_unit[unit] == state then
		return false
	end

	_last_ammo_pickup_log_state_by_unit[unit] = state

	return true
end

local function _log_grenade_skip_once(unit, reason, message, ability_extension)
	local ability_name = _grenade_ability_name(ability_extension) or "none"
	local state = tostring(reason) .. ":" .. tostring(ability_name)

	if _last_grenade_skip_log_state_by_unit[unit] == state then
		return
	end

	_last_grenade_skip_log_state_by_unit[unit] = state
	_log("grenade_pickup_skip_" .. tostring(reason) .. ":" .. tostring(unit), message)
end

local function _clear_grenade_pickup_log_state(unit)
	_last_grenade_pickup_log_state_by_unit[unit] = nil
end

local function _grenade_pickup_log_state_changed(unit, state)
	if _last_grenade_pickup_log_state_by_unit[unit] == state then
		return false
	end

	_last_grenade_pickup_log_state_by_unit[unit] = state

	return true
end

local function _bot_threshold()
	return (_Settings and _Settings.bot_ranged_ammo_threshold and _Settings.bot_ranged_ammo_threshold()) or 0.20
end

local function _human_threshold()
	return (_Settings and _Settings.human_ammo_reserve_threshold and _Settings.human_ammo_reserve_threshold()) or 0.80
end

local function _human_grenade_threshold()
	return (_Settings and _Settings.human_grenade_reserve_threshold and _Settings.human_grenade_reserve_threshold())
		or 1
end

local function _all_eligible_humans_above_threshold(human_units, threshold)
	if not (human_units and _Ammo) then
		return true
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	local cached = _cached_scan_result(_human_ammo_scan_cache, fixed_t, human_units, threshold)
	if cached ~= nil then
		return cached
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		if human_unit and _Ammo.uses_ammo(human_unit) then
			local ammo_percentage = _Ammo.current_total_percentage(human_unit)
			local needs_grenade_refill = ammo_percentage > threshold
				and _needs_ammo_pickup_for_grenade_refill(human_unit)
			if ammo_percentage <= threshold or needs_grenade_refill then
				return _store_scan_result(_human_ammo_scan_cache, fixed_t, human_units, threshold, false)
			end
		end
	end

	return _store_scan_result(_human_ammo_scan_cache, fixed_t, human_units, threshold, true)
end

function _grenade_ability_name(ability_extension)
	if not ability_extension then
		return nil
	end

	if ability_extension.get_current_grenade_ability_name then
		return ability_extension:get_current_grenade_ability_name()
	end

	if ability_extension.ability_name then
		return ability_extension:ability_name("grenade_ability")
	end

	return nil
end

local function _grenade_ability_uses_pickups(ability_extension)
	local ability_name = _grenade_ability_name(ability_extension)
	if ability_name and NON_PICKUP_GRENADE_ABILITIES[ability_name] then
		return false
	end

	return true
end

local function _grenade_ability_refills_from_ammo(ability_extension)
	local ability_name = _grenade_ability_name(ability_extension)

	return ability_name and AMMO_REFILL_GRENADE_ABILITIES[ability_name] or false
end

local function _grenade_charge_state(unit, ability_extension)
	ability_extension = ability_extension or (_ability_extension and _ability_extension(unit, "ability_system"))
	if not ability_extension then
		_log_grenade_skip_once(unit, "no_ability", "grenade pickup skipped: no ability extension")
		return nil, nil
	end

	local max_charges = ability_extension:max_ability_charges("grenade_ability")
	if max_charges <= 0 then
		return 0, 0
	end

	return ability_extension:remaining_ability_charges("grenade_ability"), max_charges
end

_needs_ammo_pickup_for_grenade_refill = function(unit, ability_extension)
	ability_extension = ability_extension or (_ability_extension and _ability_extension(unit, "ability_system"))
	if not (ability_extension and _grenade_ability_refills_from_ammo(ability_extension)) then
		return false
	end

	local current, max = _grenade_charge_state(unit, ability_extension)

	return current ~= nil and max ~= nil and current < max
end

local function _eligible_for_grenade_pickup(unit)
	local ability_extension = _ability_extension and _ability_extension(unit, "ability_system")
	if not ability_extension then
		return false, nil, nil, "no_ability"
	end

	local uses_pickups = _grenade_ability_uses_pickups(ability_extension)
	if not uses_pickups then
		return false, 0, 0, "pickup_disabled"
	end

	local current, max = _grenade_charge_state(unit, ability_extension)
	if max ~= nil and max <= 0 then
		return false, current, max, "cooldown_only"
	end

	return max ~= nil and max > 0, current, max, "pickup_based"
end

local function _bot_group_data(bot_group, unit)
	return bot_group and bot_group._bot_data and bot_group._bot_data[unit] or nil
end

local function _reserved_grenade_pickup(bot_group, unit)
	local bot_data = _bot_group_data(bot_group, unit)
	if not bot_data then
		return nil
	end

	local reserved_pickup = bot_data and bot_data._bb_reserved_grenade_pickup or nil

	if reserved_pickup and bot_data.ammo_pickup_order_unit ~= reserved_pickup then
		bot_data._bb_reserved_grenade_pickup = nil
		return nil
	end

	return reserved_pickup
end

local function _reserve_grenade_pickup(bot_group, unit, pickup_component, grenade_pickup, grenade_distance)
	if not (pickup_component and grenade_pickup) then
		return
	end

	pickup_component.ammo_pickup = grenade_pickup
	pickup_component.ammo_pickup_distance = grenade_distance or 0
	pickup_component.ammo_pickup_valid_until = math.huge

	local bot_data = _bot_group_data(bot_group, unit)
	if bot_data then
		bot_data.ammo_pickup_order_unit = grenade_pickup
		bot_data._bb_reserved_grenade_pickup = grenade_pickup
	end
end

local function _clear_reserved_grenade_pickup(bot_group, unit, pickup_component, grenade_pickup)
	local bot_data = _bot_group_data(bot_group, unit)
	local reserved_pickup = bot_data and bot_data._bb_reserved_grenade_pickup or nil
	local target_pickup = grenade_pickup or reserved_pickup
	local cleared = false

	if pickup_component and pickup_component.ammo_pickup == target_pickup then
		pickup_component.ammo_pickup = nil
		pickup_component.ammo_pickup_distance = math.huge
		pickup_component.ammo_pickup_valid_until = -math.huge
		cleared = true
	end

	if bot_data and reserved_pickup and reserved_pickup == target_pickup then
		if bot_data.ammo_pickup_order_unit == reserved_pickup then
			bot_data.ammo_pickup_order_unit = nil
		end
		bot_data._bb_reserved_grenade_pickup = nil
		cleared = true
	end

	return cleared
end

local function _clear_reserved_grenade_pickup_if_present(bot_group, unit, pickup_component)
	local grenade_pickup = _reserved_grenade_pickup(bot_group, unit)
	if not grenade_pickup then
		local current_pickup = pickup_component and pickup_component.ammo_pickup
		if
			current_pickup
			and Unit
			and Unit.get_data
			and Unit.get_data(current_pickup, "pickup_type") == "small_grenade"
		then
			grenade_pickup = current_pickup
		end
	end

	if not grenade_pickup then
		return false
	end

	return _clear_reserved_grenade_pickup(bot_group, unit, pickup_component, grenade_pickup)
end

local function _reserved_grenade_pickup_still_in_range(pickup_component)
	local pickup_distance = pickup_component and pickup_component.ammo_pickup_distance or math.huge

	return pickup_distance < PICKUP_MAX_FOLLOW_DISTANCE
end

local function _all_eligible_humans_above_grenade_threshold(human_units, threshold)
	if not human_units then
		return true
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	local cached = _cached_scan_result(_human_grenade_scan_cache, fixed_t, human_units, threshold)
	if cached ~= nil then
		return cached
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		local eligible, current, max = _eligible_for_grenade_pickup(human_unit)
		if eligible then
			local charge_fraction = current / max
			if charge_fraction < threshold then
				return _store_scan_result(_human_grenade_scan_cache, fixed_t, human_units, threshold, false)
			end
		end
	end

	return _store_scan_result(_human_grenade_scan_cache, fixed_t, human_units, threshold, true)
end

local function _best_nearby_grenade_pickup(bot_group, unit)
	if _nearby_grenade_pickups then
		return _nearby_grenade_pickups(bot_group, unit)
	end

	local bot_data = bot_group and bot_group._bot_data and bot_group._bot_data[unit]
	local broadphase_system = bot_group and bot_group._broadphase_system
	local player_position = POSITION_LOOKUP and POSITION_LOOKUP[unit]
	if not (bot_data and broadphase_system and player_position) then
		return nil
	end

	local broadphase = broadphase_system.broadphase
	local num_units = Broadphase.query(
		broadphase,
		player_position,
		PICKUP_MAX_FOLLOW_DISTANCE,
		PICKUP_QUERY_RESULTS,
		PICKUP_BROADPHASE_CATEGORY
	)
	local follow_position = bot_data.follow_position
	local current_pickup = bot_data.pickup_component and bot_data.pickup_component.ammo_pickup
	local best_pickup
	local best_distance

	for i = 1, num_units do
		local pickup_unit = PICKUP_QUERY_RESULTS[i]
		if Unit.get_data(pickup_unit, "pickup_type") == "small_grenade" then
			local pickup_position = POSITION_LOOKUP[pickup_unit]
			if pickup_position then
				local distance = Vector3.distance(player_position, pickup_position)
				local follow_distance = follow_position and Vector3.distance(follow_position, pickup_position)
					or math.huge
				local in_range = distance < PICKUP_MAX_DISTANCE or follow_distance < PICKUP_MAX_FOLLOW_DISTANCE

				if in_range then
					local sticky_distance = current_pickup == pickup_unit and 2.5 or 0
					local candidate_distance = distance - sticky_distance
					if not best_distance or candidate_distance < best_distance then
						best_pickup = pickup_unit
						best_distance = candidate_distance
					end
				end
			end
		end
	end

	return best_pickup, best_distance
end

local function _current_ammo_percentage(unit)
	if not (_Ammo and _Ammo.current_total_percentage and _Ammo.uses_ammo and _Ammo.uses_ammo(unit)) then
		return nil
	end

	return _Ammo.current_total_percentage(unit)
end

local function _pickup_snapshot(unit)
	local grenade_current, grenade_max = _grenade_charge_state(unit)

	return {
		ammo_pct = _current_ammo_percentage(unit),
		grenade_current = grenade_current,
		grenade_max = grenade_max,
	}
end

local function _log_pickup_success(interactor_unit, target_unit, pickup_name, before, after)
	local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(interactor_unit) or nil
	if not bot_slot then
		return
	end

	if before.ammo_pct ~= nil and after.ammo_pct ~= nil and after.ammo_pct > before.ammo_pct then
		_log(
			"ammo_pickup_success:" .. tostring(interactor_unit) .. ":" .. tostring(target_unit),
			"ammo pickup success: "
				.. tostring(pickup_name)
				.. " (bot="
				.. tostring(bot_slot)
				.. ", ammo="
				.. string.format("%.0f%%->%.0f%%", before.ammo_pct * 100, after.ammo_pct * 100)
				.. ")"
		)
	end

	if
		before.grenade_current ~= nil
		and after.grenade_current ~= nil
		and after.grenade_current > before.grenade_current
	then
		_log(
			"grenade_pickup_success:" .. tostring(interactor_unit) .. ":" .. tostring(target_unit),
			"grenade pickup success: "
				.. tostring(pickup_name)
				.. " (bot="
				.. tostring(bot_slot)
				.. ", charges="
				.. tostring(before.grenade_current)
				.. "->"
				.. tostring(after.grenade_current)
				.. "/"
				.. tostring(after.grenade_max or before.grenade_max or "?")
				.. ")"
		)
	end
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_Ammo = deps.ammo_module or require("scripts/utilities/ammo")
	_Settings = deps.settings
	_ability_extension = deps.ability_extension or (ScriptUnit and ScriptUnit.has_extension)
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_nearby_grenade_pickups = deps.nearby_grenade_pickups
	_is_enabled = deps.is_enabled
	_human_ammo_scan_cache = {}
	_human_grenade_scan_cache = {}
	_last_ammo_pickup_log_state_by_unit = setmetatable({}, { __mode = "k" })
	_last_grenade_skip_log_state_by_unit = setmetatable({}, { __mode = "k" })
	_last_grenade_pickup_log_state_by_unit = setmetatable({}, { __mode = "k" })
end

function M.install_interaction_hooks(AmmunitionInteraction)
	if not AmmunitionInteraction or rawget(AmmunitionInteraction, INTERACTION_PATCH_SENTINEL) then
		return
	end
	AmmunitionInteraction[INTERACTION_PATCH_SENTINEL] = true

	_mod:hook(
		AmmunitionInteraction,
		"stop",
		function(func, self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			if not (interactor_is_server and result == "success" and _debug_enabled and _debug_enabled()) then
				return func(self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			end

			local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(interactor_unit) or nil
			if not bot_slot then
				return func(self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			end

			local target_unit = unit_data_component and unit_data_component.target_unit or nil
			local pickup_name = target_unit and Unit and Unit.get_data and Unit.get_data(target_unit, "pickup_type")
				or "unknown"
			local before = _pickup_snapshot(interactor_unit)
			local stop_result = func(self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)
			local after = _pickup_snapshot(interactor_unit)

			_log_pickup_success(interactor_unit, target_unit, pickup_name, before, after)

			return stop_result
		end
	)
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/interaction/interactions/ammunition_interaction",
		function(AmmunitionInteraction)
			M.install_interaction_hooks(AmmunitionInteraction)
		end
	)
	_mod:hook_require(
		"scripts/extension_systems/interaction/interactions/grenade_interaction",
		function(GrenadeInteraction)
			M.install_interaction_hooks(GrenadeInteraction)
		end
	)
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_update_ammo", function(self, unit)
		local pickup_component = self._pickup_component
		local bot_group = self._bot_group
		if _is_enabled and not _is_enabled() then
			_clear_ammo_pickup_log_state(unit)
			_clear_grenade_skip_log_state(unit)
			if _clear_reserved_grenade_pickup_if_present(bot_group, unit, pickup_component) then
				_clear_grenade_pickup_log_state(unit)
				_log(
					"grenade_pickup_release_disabled:" .. tostring(unit),
					"released reserved grenade pickup because ammo policy was disabled"
				)
			end
			return
		end

		local perf_t0 = _perf and _perf.begin()
		if not pickup_component then
			_clear_ammo_pickup_log_state(unit)
			_clear_grenade_skip_log_state(unit)
			_clear_grenade_pickup_log_state(unit)
			_log("ammo_pickup_skip_no_component:" .. tostring(unit), "ammo policy skipped: no pickup_component")
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local reserved_grenade_pickup = _reserved_grenade_pickup(bot_group, unit)
		local pickup_order_unit = bot_group and bot_group:ammo_pickup_order_unit(unit) or nil
		local has_external_ammo_pickup_order = pickup_order_unit ~= nil and pickup_order_unit ~= reserved_grenade_pickup

		if has_external_ammo_pickup_order then
			_clear_ammo_pickup_log_state(unit)
			_clear_grenade_skip_log_state(unit)
			_clear_grenade_pickup_log_state(unit)
			pickup_component.needs_ammo = true
			_log("ammo_pickup_order:" .. tostring(unit), "ammo pickup preserved due to explicit order")
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local bot_ammo_percentage = _current_ammo_percentage(unit)
		local bot_needs_grenade_refill = _needs_ammo_pickup_for_grenade_refill(unit)
		local bot_needs_ammo = (bot_ammo_percentage ~= nil and bot_ammo_percentage < 1) or bot_needs_grenade_refill
		local humans_ok =
			_all_eligible_humans_above_threshold(self._side and self._side.valid_human_units, _human_threshold())

		if not bot_needs_ammo then
			pickup_component.needs_ammo = false
			_clear_ammo_pickup_log_state(unit)
		elseif humans_ok then
			pickup_component.needs_ammo = true
			if _ammo_pickup_log_state_changed(unit, "allow") then
				_log("ammo_pickup_allow:" .. tostring(unit), "ammo pickup permitted: all eligible humans above reserve")
			end
		else
			local bot_threshold = _bot_threshold()
			local bot_desperate = bot_ammo_percentage ~= nil and bot_ammo_percentage <= bot_threshold
			pickup_component.needs_ammo = bot_desperate
			if bot_desperate and _ammo_pickup_log_state_changed(unit, "desperate") then
				_log(
					"ammo_pickup_desperate:" .. tostring(unit),
					"ammo pickup permitted: bot desperate ("
						.. string.format("%.0f%% <= %.0f%%", bot_ammo_percentage * 100, bot_threshold * 100)
						.. ") despite human reserve low"
				)
			elseif not bot_desperate and _ammo_pickup_log_state_changed(unit, "defer") then
				_log(
					"ammo_pickup_defer:" .. tostring(unit),
					"ammo pickup deferred to human ("
						.. string.format("bot %.0f%% > %.0f%%", bot_ammo_percentage * 100, bot_threshold * 100)
						.. ")"
				)
			end
		end

		local grenade_eligible, grenade_current, grenade_max, grenade_reason = _eligible_for_grenade_pickup(unit)
		if grenade_eligible and grenade_current < grenade_max then
			local grenade_pickup, grenade_distance = _best_nearby_grenade_pickup(bot_group, unit)
			if not grenade_pickup and reserved_grenade_pickup then
				if _reserved_grenade_pickup_still_in_range(pickup_component) then
					grenade_pickup = reserved_grenade_pickup
					grenade_distance = pickup_component.ammo_pickup_distance
				elseif _clear_reserved_grenade_pickup(bot_group, unit, pickup_component, reserved_grenade_pickup) then
					_clear_grenade_pickup_log_state(unit)
					_log(
						"grenade_pickup_release_range:" .. tostring(unit),
						"released reserved grenade pickup after leaving range"
					)
				end
			end

			if grenade_pickup then
				local human_units = self._side and self._side.valid_human_units
				local humans_ok_for_grenade =
					_all_eligible_humans_above_grenade_threshold(human_units, _human_grenade_threshold())
				if humans_ok_for_grenade then
					_reserve_grenade_pickup(bot_group, unit, pickup_component, grenade_pickup, grenade_distance)
					pickup_component.needs_ammo = true
					local pickup_state = "reserved:" .. tostring(grenade_pickup)
					if _grenade_pickup_log_state_changed(unit, pickup_state) then
						_log(
							"grenade_pickup_allow:" .. tostring(unit),
							"grenade pickup permitted: all eligible humans above reserve"
						)
						_log("grenade_pickup_bind:" .. tostring(unit), "grenade pickup bound into ammo slot")
					end
				else
					if _clear_reserved_grenade_pickup(bot_group, unit, pickup_component, grenade_pickup) then
						_clear_grenade_pickup_log_state(unit)
						_log(
							"grenade_pickup_release:" .. tostring(unit),
							"released reserved grenade pickup to human reserve"
						)
					end
					local pickup_state = "deferred:" .. tostring(grenade_pickup)
					if _grenade_pickup_log_state_changed(unit, pickup_state) then
						_log("grenade_pickup_defer:" .. tostring(unit), "grenade pickup deferred to human reserve")
					end
				end
			end
		else
			if reserved_grenade_pickup then
				_clear_reserved_grenade_pickup(bot_group, unit, pickup_component, reserved_grenade_pickup)
			end
			_clear_grenade_pickup_log_state(unit)
		end

		if grenade_reason == "no_ability" then
			_log_grenade_skip_once(unit, "no_ability", "grenade pickup skipped: no ability extension")
		elseif grenade_reason == "pickup_disabled" then
			_log_grenade_skip_once(
				unit,
				"pickup_disabled",
				"grenade pickup skipped: ability does not use grenade pickups"
			)
		elseif grenade_reason == "cooldown_only" then
			_log_grenade_skip_once(unit, "cooldown_only", "grenade pickup skipped: cooldown-based blitz")
		else
			_clear_grenade_skip_log_state(unit)
		end

		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
	end)
end

M.all_eligible_humans_above_threshold = _all_eligible_humans_above_threshold

return M
