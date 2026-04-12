local M = {}

local _mod
local _debug_log
local _debug_enabled
local _is_grimoire_pickup_enabled
local _pickups
local _unit_get_data
local _tome_patch_logged = false
local _last_grimoire_patch_enabled

local TOME_PICKUP_NAME = "tome"
local GRIMOIRE_PICKUP_NAME = "grimoire"

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, 0, message)
end

local function _pickups_registry()
	if _pickups then
		return _pickups
	end

	return require("scripts/settings/pickup/pickups")
end

local function _get_pickup_data(pickup_name)
	local pickups = _pickups_registry()

	return pickups and pickups.by_name and pickups.by_name[pickup_name] or nil
end

local function _grimoire_enabled()
	if not _is_grimoire_pickup_enabled then
		return false
	end
	return _is_grimoire_pickup_enabled() == true
end

local function _patch_pickup(pickup_name, mule_enabled)
	local pickup_data = _get_pickup_data(pickup_name)
	if not pickup_data then
		return
	end

	if pickup_data.inventory_slot_name and not pickup_data.slot_name then
		pickup_data.slot_name = pickup_data.inventory_slot_name
	end

	pickup_data.bots_mule_pickup = mule_enabled
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_grimoire_pickup_enabled = deps.is_grimoire_pickup_enabled
	_pickups = deps.pickups
	_unit_get_data = deps.unit_get_data or (Unit and Unit.get_data)
	_tome_patch_logged = false
	_last_grimoire_patch_enabled = nil

	M.patch_pickups()
end

function M.patch_pickups()
	local grimoire_enabled = _grimoire_enabled()

	_patch_pickup(TOME_PICKUP_NAME, true)
	_patch_pickup(GRIMOIRE_PICKUP_NAME, grimoire_enabled)

	if not _tome_patch_logged then
		_tome_patch_logged = true
		_log("mule_pickup_patch:" .. TOME_PICKUP_NAME, "patched mule pickup metadata for tome")
	end

	if _last_grimoire_patch_enabled ~= grimoire_enabled then
		_last_grimoire_patch_enabled = grimoire_enabled
		_log(
			"mule_pickup_patch:" .. GRIMOIRE_PICKUP_NAME,
			"patched mule pickup metadata for grimoire (enabled=" .. tostring(grimoire_enabled) .. ")"
		)
	end
end

function M.is_grimoire_pickup_unit(pickup_unit)
	if not (pickup_unit and _unit_get_data) then
		return false
	end

	return _unit_get_data(pickup_unit, "pickup_type") == GRIMOIRE_PICKUP_NAME
end

function M.sanitize_mule_pickup(pickup_component, unit)
	M.patch_pickups()

	if _grimoire_enabled() or not pickup_component or not pickup_component.mule_pickup then
		return false
	end

	if not M.is_grimoire_pickup_unit(pickup_component.mule_pickup) then
		return false
	end

	pickup_component.mule_pickup = nil
	pickup_component.mule_pickup_distance = math.huge
	_log("mule_pickup_block_grim:" .. tostring(unit), "blocked grimoire mule pickup")

	return true
end

function M.should_block_pickup_order(pickup_unit)
	M.patch_pickups()

	return not _grimoire_enabled() and M.is_grimoire_pickup_unit(pickup_unit)
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_refresh_destination", function(self)
		M.sanitize_mule_pickup(self._pickup_component, self._unit)
	end)
end

function M.register_hooks()
	M.patch_pickups()

	_mod:hook_require("scripts/utilities/bot_order", function(BotOrder)
		_mod:hook(BotOrder, "pickup", function(func, bot_unit, pickup_unit, ordering_player)
			if M.should_block_pickup_order(pickup_unit) then
				_log("mule_pickup_order_block:" .. tostring(bot_unit), "blocked grimoire pickup order")
				return nil
			end

			return func(bot_unit, pickup_unit, ordering_player)
		end)
	end)
end

return M
