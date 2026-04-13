local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _Ammo
local _Settings
local _ability_extension
local _nearby_grenade_pickups
local _human_ammo_scan_cache = {}
local _human_grenade_scan_cache = {}
local PICKUP_BROADPHASE_CATEGORY = {
	"pickups",
}
local PICKUP_QUERY_RESULTS = {}
local PICKUP_VALID_DURATION = 5
local PICKUP_MAX_DISTANCE = 5
local PICKUP_MAX_FOLLOW_DISTANCE = 15

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

local function _bot_grenade_threshold()
	return (_Settings and _Settings.bot_grenade_charges_threshold and _Settings.bot_grenade_charges_threshold()) or 0
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

local function _grenade_charge_state(unit)
	local ability_extension = _ability_extension and _ability_extension(unit, "ability_system")
	if not ability_extension then
		return nil, nil
	end

	local max_charges = ability_extension:max_ability_charges("grenade_ability")
	if max_charges <= 0 then
		return 0, 0
	end

	return ability_extension:remaining_ability_charges("grenade_ability"), max_charges
end

local function _eligible_for_grenade_pickup(unit)
	local current, max = _grenade_charge_state(unit)

	return max ~= nil and max > 0, current, max
end

local function _clear_reserved_grenade_pickup(pickup_component, grenade_pickup)
	if not pickup_component or pickup_component.ammo_pickup ~= grenade_pickup then
		return false
	end

	pickup_component.ammo_pickup = nil
	pickup_component.ammo_pickup_distance = math.huge
	pickup_component.ammo_pickup_valid_until = -math.huge

	return true
end

local function _all_eligible_humans_above_grenade_threshold(human_units, threshold)
	if not human_units then
		return true
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	if
		_human_grenade_scan_cache.fixed_t == fixed_t
		and _human_grenade_scan_cache.human_units == human_units
		and _human_grenade_scan_cache.threshold == threshold
	then
		return _human_grenade_scan_cache.result
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		local eligible, current, max = _eligible_for_grenade_pickup(human_unit)
		if eligible then
			local charge_fraction = current / max
			if charge_fraction < threshold then
				_human_grenade_scan_cache = {
					fixed_t = fixed_t,
					human_units = human_units,
					threshold = threshold,
					result = false,
				}
				return false
			end
		end
	end

	_human_grenade_scan_cache = {
		fixed_t = fixed_t,
		human_units = human_units,
		threshold = threshold,
		result = true,
	}
	return true
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

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_Ammo = deps.ammo_module or require("scripts/utilities/ammo")
	_Settings = deps.settings
	_ability_extension = deps.ability_extension or (ScriptUnit and ScriptUnit.has_extension)
	_nearby_grenade_pickups = deps.nearby_grenade_pickups
	_human_ammo_scan_cache = {}
	_human_grenade_scan_cache = {}
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

		local grenade_eligible, grenade_current, grenade_max = _eligible_for_grenade_pickup(unit)
		if grenade_eligible and grenade_current <= _bot_grenade_threshold() then
			local grenade_pickup, grenade_distance = _best_nearby_grenade_pickup(bot_group, unit)
			if grenade_pickup then
				local humans_ok_for_grenade = _all_eligible_humans_above_grenade_threshold(
					self._side and self._side.valid_human_units,
					_human_grenade_threshold()
				)
				if humans_ok_for_grenade then
					pickup_component.ammo_pickup = grenade_pickup
					pickup_component.ammo_pickup_distance = grenade_distance or 0
					pickup_component.ammo_pickup_valid_until = (_fixed_time and _fixed_time() or 0)
						+ PICKUP_VALID_DURATION
					pickup_component.needs_ammo = true
					_log(
						"grenade_pickup_allow:" .. tostring(unit),
						"grenade pickup permitted: all eligible humans above reserve"
					)
					_log("grenade_pickup_bind:" .. tostring(unit), "grenade pickup bound into ammo slot")
				else
					if _clear_reserved_grenade_pickup(pickup_component, grenade_pickup) then
						_log(
							"grenade_pickup_release:" .. tostring(unit),
							"released reserved grenade pickup to human reserve"
						)
					end
					_log("grenade_pickup_defer:" .. tostring(unit), "grenade pickup deferred to human reserve")
				end
			end
		elseif grenade_max ~= nil and grenade_max <= 0 then
			_log("grenade_pickup_skip_ineligible:" .. tostring(unit), "grenade pickup skipped: cooldown-based blitz")
		end

		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
	end)
end

M.all_eligible_humans_above_threshold = _all_eligible_humans_above_threshold

return M
