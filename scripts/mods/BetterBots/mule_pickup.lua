local M = {}

local _mod
local _debug_log
local _debug_enabled
local _is_grimoire_pickup_enabled
local _pickups
local _get_live_bot_groups
local _unit_get_data
local _unit_is_alive
local _write_blackboard_component
local _tome_patch_logged = false
local _last_grimoire_patch_enabled
local _blackboard_module

local TOME_PICKUP_NAME = "tome"
local GRIMOIRE_PICKUP_NAME = "grimoire"
local POCKETABLE_SLOT_NAME = "slot_pocketable"

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, 0, message)
end

local function _log_stale_clear(discriminator, source)
	_log(
		"mule_pickup_stale_clear:" .. tostring(discriminator),
		"cleared stale mule pickup ref (source=" .. tostring(source) .. ")"
	)
end

local function _pickups_registry()
	if _pickups then
		return _pickups
	end

	return require("scripts/settings/pickup/pickups")
end

local function _default_get_live_bot_groups()
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager or type(extension_manager.system) ~= "function" then
		return nil
	end

	local ok, group_system = pcall(extension_manager.system, extension_manager, "group_system")
	if not ok or not group_system then
		return nil
	end

	return group_system._bot_groups
end

local function _default_write_blackboard_component(blackboard, component_name)
	if _blackboard_module == nil then
		local ok, blackboard_module = pcall(require, "scripts/extension_systems/blackboard/utilities/blackboard")
		_blackboard_module = ok and blackboard_module or false
	end

	if _blackboard_module and type(_blackboard_module.write_component) == "function" then
		return _blackboard_module.write_component(blackboard, component_name)
	end

	return blackboard and blackboard[component_name] or nil
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

local function _pickup_unit_is_stale(pickup_unit)
	if not pickup_unit then
		return false
	end

	if not _unit_is_alive then
		return false
	end

	return not _unit_is_alive(pickup_unit)
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
	_get_live_bot_groups = deps.get_live_bot_groups or _default_get_live_bot_groups
	_unit_get_data = deps.unit_get_data or (Unit and Unit.get_data)
	_unit_is_alive = deps.unit_is_alive or (Unit and Unit.alive)
	_write_blackboard_component = deps.blackboard_write_component or _default_write_blackboard_component
	_tome_patch_logged = false
	_last_grimoire_patch_enabled = nil

	M.patch_pickups()
	M.sync_live_bot_groups()
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

	if _pickup_unit_is_stale(pickup_unit) then
		return false
	end

	return _unit_get_data(pickup_unit, "pickup_type") == GRIMOIRE_PICKUP_NAME
end

function M.sanitize_mule_pickup(pickup_component, unit)
	M.patch_pickups()

	if _grimoire_enabled() or not pickup_component or not pickup_component.mule_pickup then
		return false
	end

	local stale = _pickup_unit_is_stale(pickup_component.mule_pickup)
	local blocked_grimoire = not stale and M.is_grimoire_pickup_unit(pickup_component.mule_pickup)
	if not (stale or blocked_grimoire) then
		return false
	end

	pickup_component.mule_pickup = nil
	pickup_component.mule_pickup_distance = math.huge
	if stale then
		_log_stale_clear(unit, "pickup_component.mule_pickup")
	else
		_log("mule_pickup_block_grim:" .. tostring(unit), "blocked grimoire mule pickup")
	end

	return true
end

local function _mark_destination_refresh(unit)
	local blackboard = BLACKBOARDS and unit and BLACKBOARDS[unit]
	if not (blackboard and _write_blackboard_component) then
		return false
	end

	local follow_component = _write_blackboard_component(blackboard, "follow")
	if not follow_component then
		return false
	end

	follow_component.needs_destination_refresh = true

	return true
end

local function _clear_behavior_targets(behavior_component, unit)
	if not behavior_component then
		return false
	end

	local changed = false
	local stale_interaction = _pickup_unit_is_stale(behavior_component.interaction_unit)
	if stale_interaction or M.is_grimoire_pickup_unit(behavior_component.interaction_unit) then
		behavior_component.interaction_unit = nil
		changed = true
		if stale_interaction then
			_log_stale_clear(tostring(unit) .. ":interaction_unit", "behavior_component.interaction_unit")
		end
	end
	local stale_forced = _pickup_unit_is_stale(behavior_component.forced_pickup_unit)
	if stale_forced or M.is_grimoire_pickup_unit(behavior_component.forced_pickup_unit) then
		behavior_component.forced_pickup_unit = nil
		changed = true
		if stale_forced then
			_log_stale_clear(tostring(unit) .. ":forced_pickup_unit", "behavior_component.forced_pickup_unit")
		end
	end

	return changed
end

local function _clear_grimoire_pickup_order(pickup_orders, unit)
	local order = pickup_orders and pickup_orders[POCKETABLE_SLOT_NAME]
	local stale = order and _pickup_unit_is_stale(order.unit)
	if not (order and (stale or M.is_grimoire_pickup_unit(order.unit))) then
		return nil
	end

	pickup_orders[POCKETABLE_SLOT_NAME] = nil
	if stale then
		_log_stale_clear(tostring(unit) .. ":pickup_order", "pickup_orders.slot_pocketable")
	end

	return stale and "stale" or "grimoire"
end

local function _clear_cached_grimoire_pickups(bot_group)
	local available_mule_pickups = bot_group and bot_group._available_mule_pickups
	local available_pickups = available_mule_pickups and available_mule_pickups[POCKETABLE_SLOT_NAME]
	if not available_pickups then
		return false
	end

	local changed = false
	for pickup_unit in pairs(available_pickups) do
		local stale = _pickup_unit_is_stale(pickup_unit)
		if stale or M.is_grimoire_pickup_unit(pickup_unit) then
			available_pickups[pickup_unit] = nil
			changed = true
			if stale then
				_log_stale_clear(pickup_unit, "_available_mule_pickups.slot_pocketable")
			end
		end
	end

	return changed
end

function M.sync_live_bot_group(bot_group)
	M.patch_pickups()

	if _grimoire_enabled() or not bot_group then
		return false
	end

	local changed = _clear_cached_grimoire_pickups(bot_group)
	local bot_data = (bot_group.data and bot_group:data()) or bot_group._bot_data
	if not bot_data then
		return changed
	end

	for unit, data in pairs(bot_data) do
		local unit_changed = false
		local pickup_order_clear_reason = _clear_grimoire_pickup_order(data.pickup_orders, unit)
		if pickup_order_clear_reason then
			unit_changed = true
			changed = true
			if pickup_order_clear_reason == "grimoire" then
				_log("mule_pickup_order_clear:" .. tostring(unit), "cleared grimoire mule pickup order")
			end
		end

		if M.sanitize_mule_pickup(data.pickup_component, unit) then
			unit_changed = true
			changed = true
		end

		if _clear_behavior_targets(data.behavior_component, unit) then
			unit_changed = true
			changed = true
		end

		if unit_changed and _mark_destination_refresh(unit) then
			_log("mule_pickup_refresh:" .. tostring(unit), "refreshed destination after clearing grimoire mule state")
		end
	end

	return changed
end

function M.sync_live_bot_groups()
	M.patch_pickups()

	if _grimoire_enabled() or not _get_live_bot_groups then
		return false
	end

	local bot_groups = _get_live_bot_groups()
	if not bot_groups then
		return false
	end

	local changed = false
	for _, bot_group in pairs(bot_groups) do
		if M.sync_live_bot_group(bot_group) then
			changed = true
		end
	end

	return changed
end

function M.should_block_pickup_order(pickup_unit)
	M.patch_pickups()

	return not _grimoire_enabled() and M.is_grimoire_pickup_unit(pickup_unit)
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_refresh_destination", function(self)
		local changed = M.sanitize_mule_pickup(self._pickup_component, self._unit)
		if changed then
			_clear_behavior_targets(self._behavior_component, self._unit)
		end
	end)
end

function M.register_hooks()
	M.patch_pickups()
	M.sync_live_bot_groups()

	_mod:hook_require("scripts/extension_systems/group/bot_group", function(BotGroup)
		_mod:hook_safe(BotGroup, "_update_mule_pickups", function(self)
			M.sync_live_bot_group(self)
		end)
	end)

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
