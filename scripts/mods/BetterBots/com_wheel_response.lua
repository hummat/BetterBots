local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _is_enabled
local _battle_cry_until_t
local _request_state_by_unit = setmetatable({}, { __mode = "k" })

local COM_WHEEL_CONCEPT = "on_demand_com_wheel"
local TRIGGER_BATTLE_CRY = "com_cheer"
local TRIGGER_NEED_AMMO = "com_need_ammo"
local TRIGGER_NEED_HEALTH = "com_need_health"
local BATTLE_CRY_DURATION_S = 5
local RESOURCE_REQUEST_DURATION_S = 10
local VO_PATCH_SENTINEL = "__bb_com_wheel_response_installed"

local function _now()
	return _fixed_time and _fixed_time() or 0
end

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _now(), message)
end

local function _feature_enabled()
	if not _is_enabled then
		return true
	end

	return _is_enabled() ~= false
end

local function _human_player_by_unit(unit)
	local player_manager = Managers and Managers.player
	local player = player_manager and player_manager.player_by_unit and player_manager:player_by_unit(unit)

	if not (player and player.is_human_controlled and player:is_human_controlled()) then
		return nil
	end

	return player
end

local function _request_state(unit)
	local state = _request_state_by_unit[unit]
	if state then
		return state
	end

	state = {}
	_request_state_by_unit[unit] = state

	return state
end

local function _has_live_request(human_units, field_name)
	if not (_feature_enabled() and human_units) then
		return false
	end

	local t = _now()
	for i = 1, #human_units do
		local state = _request_state_by_unit[human_units[i]]
		local until_t = state and state[field_name] or nil
		if until_t and until_t > t then
			return true
		end
	end

	return false
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_enabled = deps.is_enabled
	_battle_cry_until_t = nil
	_request_state_by_unit = setmetatable({}, { __mode = "k" })
end

function M.reset()
	_battle_cry_until_t = nil
	_request_state_by_unit = setmetatable({}, { __mode = "k" })
end

function M.record_trigger(unit, trigger_id)
	if not (_feature_enabled() and _human_player_by_unit(unit)) then
		return false, "not_human"
	end

	local t = _now()
	if trigger_id == TRIGGER_BATTLE_CRY then
		_battle_cry_until_t = t + BATTLE_CRY_DURATION_S
		_log(
			"com_wheel_battle_cry:" .. tostring(unit),
			"battle cry request noted: aggressive preset override for " .. tostring(BATTLE_CRY_DURATION_S) .. "s"
		)
		return true, "battle_cry"
	end

	local state = _request_state(unit)
	if trigger_id == TRIGGER_NEED_AMMO then
		state.ammo_until_t = t + RESOURCE_REQUEST_DURATION_S
		_log(
			"com_wheel_need_ammo:" .. tostring(unit),
			"need ammo request noted for " .. tostring(RESOURCE_REQUEST_DURATION_S) .. "s"
		)
		return true, "need_ammo"
	end

	if trigger_id == TRIGGER_NEED_HEALTH then
		state.health_until_t = t + RESOURCE_REQUEST_DURATION_S
		_log(
			"com_wheel_need_health:" .. tostring(unit),
			"need health request noted for " .. tostring(RESOURCE_REQUEST_DURATION_S) .. "s"
		)
		return true, "need_health"
	end

	return false, "unsupported_trigger"
end

function M.override_behavior_profile(base_preset)
	if not _feature_enabled() then
		return nil
	end

	local t = _now()
	if not (_battle_cry_until_t and _battle_cry_until_t > t) then
		return nil
	end

	if base_preset == "testing" or base_preset == "aggressive" then
		return nil
	end

	return "aggressive"
end

function M.has_recent_ammo_request(human_units)
	return _has_live_request(human_units, "ammo_until_t")
end

function M.has_recent_health_request(human_units)
	return _has_live_request(human_units, "health_until_t")
end

function M.install_hooks(Vo)
	if not Vo or rawget(Vo, VO_PATCH_SENTINEL) then
		return
	end

	Vo[VO_PATCH_SENTINEL] = true

	_mod:hook(Vo, "on_demand_vo_event", function(func, unit, concept, trigger_id, target_unit)
		local result = func(unit, concept, trigger_id, target_unit)

		if concept == COM_WHEEL_CONCEPT then
			M.record_trigger(unit, trigger_id)
		end

		return result
	end)
end

function M.register_hooks()
	_mod:hook_require("scripts/utilities/vo", function(Vo)
		M.install_hooks(Vo)
	end)
end

return M
