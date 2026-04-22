local M = {}

local _mod
local _debug_log
local _debug_enabled
local _is_grimoire_pickup_enabled
local _is_tome_pickup_enabled
local _pickups
local _get_live_bot_groups
local _unit_get_data
local _unit_is_alive
local _write_blackboard_component
local _bot_slot_for_unit
local _should_allow_mule_pickup
local _should_block_pickup_order
local _last_tome_patch_enabled
local _last_grimoire_patch_enabled
local _blackboard_module
local _warned_group_system_lookup_failure
local _warned_blackboard_module_lookup_failure
local _pickups_registry
local BOT_GROUP_PATCH_SENTINEL = "__bb_mule_pickup_bot_group_installed"
local INTERACTION_PATCH_SENTINEL = "__bb_mule_pickup_interaction_installed"

local TOME_PICKUP_NAME = "tome"
local GRIMOIRE_PICKUP_NAME = "grimoire"
local POCKETABLE_SLOT_NAME = "slot_pocketable"
local MULE_PICKUP_MAX_DISTANCE_SQ = 400

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

local function _log_mule_pickup_success(interactor_unit, target_unit, pickup_name)
	local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(interactor_unit) or nil
	if not bot_slot then
		return
	end

	local pickup_settings = pickup_name and _pickups_registry().by_name[pickup_name] or nil
	local slot_name = pickup_settings and (pickup_settings.slot_name or pickup_settings.inventory_slot_name) or nil
	local is_supported_mule_pocketable = pickup_settings
		and pickup_settings.bots_mule_pickup
		and (slot_name == "slot_pocketable" or slot_name == "slot_pocketable_small")
	if pickup_name ~= TOME_PICKUP_NAME and pickup_name ~= GRIMOIRE_PICKUP_NAME and not is_supported_mule_pocketable then
		return
	end

	_log(
		"mule_pickup_success:" .. tostring(interactor_unit) .. ":" .. tostring(target_unit),
		"mule pickup success: " .. tostring(pickup_name) .. " (bot=" .. tostring(bot_slot) .. ")"
	)
end

function _pickups_registry()
	if _pickups then
		return _pickups
	end

	return require("scripts/settings/pickup/pickups")
end

local function _ensure_mule_pickup_slots(bot_group)
	if not bot_group then
		return false
	end

	local available_mule_pickups = bot_group._available_mule_pickups
	if not available_mule_pickups then
		available_mule_pickups = {}
		bot_group._available_mule_pickups = available_mule_pickups
	end

	local pickups = _pickups_registry()
	local pickups_by_name = pickups and pickups.by_name
	if not pickups_by_name then
		return false
	end

	local changed = false
	for _, pickup_data in pairs(pickups_by_name) do
		if pickup_data and pickup_data.bots_mule_pickup then
			local slot_name = pickup_data.slot_name or pickup_data.inventory_slot_name
			if slot_name and available_mule_pickups[slot_name] == nil then
				available_mule_pickups[slot_name] = {}
				changed = true
			end
		end
	end

	return changed
end

local function _default_get_live_bot_groups()
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager or type(extension_manager.system) ~= "function" then
		return nil
	end

	local ok, group_system = pcall(extension_manager.system, extension_manager, "group_system")
	if not ok or not group_system then
		if not _warned_group_system_lookup_failure and _mod and _mod.warning then
			_warned_group_system_lookup_failure = true
			_mod:warning("BetterBots: group_system unavailable; mule pickup live-sync skipped")
		end
		return nil
	end

	return group_system._bot_groups
end

local function _default_write_blackboard_component(blackboard, component_name)
	if _blackboard_module == nil then
		local ok, blackboard_module = pcall(require, "scripts/extension_systems/blackboard/utilities/blackboard")
		if ok then
			_blackboard_module = blackboard_module
		else
			if not _warned_blackboard_module_lookup_failure and _mod and _mod.warning then
				_warned_blackboard_module_lookup_failure = true
				_mod:warning("BetterBots: blackboard utility unavailable; mule pickup destination refresh skipped")
			end
			return nil
		end
	end

	if _blackboard_module and type(_blackboard_module.write_component) == "function" then
		return _blackboard_module.write_component(blackboard, component_name)
	end

	return nil
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

local function _tome_enabled()
	if not _is_tome_pickup_enabled then
		return true
	end
	return _is_tome_pickup_enabled() ~= false
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

local function _is_tome_pickup_unit(pickup_unit)
	if not (pickup_unit and _unit_get_data) then
		return false
	end

	if _pickup_unit_is_stale(pickup_unit) then
		return false
	end

	return _unit_get_data(pickup_unit, "pickup_type") == TOME_PICKUP_NAME
end

-- Returns (should_clear, reason). Stale cleanup runs regardless of grimoire/tome settings;
-- grimoire/tome blocking only runs when that pickup type is opted out, so dead unit
-- references still get flushed when the user enables pickup for either type.
local function _should_clear_mule_unit(pickup_unit)
	if not pickup_unit then
		return false, nil
	end
	if _pickup_unit_is_stale(pickup_unit) then
		return true, "stale"
	end
	if not _grimoire_enabled() and M.is_grimoire_pickup_unit(pickup_unit) then
		return true, "grimoire"
	end
	if not _tome_enabled() and _is_tome_pickup_unit(pickup_unit) then
		return true, "tome"
	end
	return false, nil
end

local function _pickup_allowed_for_bot(unit, pickup_unit, bot_group, data)
	if not pickup_unit then
		return true, nil
	end

	local should_clear, reason = _should_clear_mule_unit(pickup_unit)
	if should_clear then
		return false, reason
	end

	if _should_allow_mule_pickup then
		local allowed, policy_reason = _should_allow_mule_pickup(unit, pickup_unit, bot_group, data)
		if allowed == false then
			return false, policy_reason
		end
	end

	return true, nil
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
	_is_tome_pickup_enabled = deps.is_tome_pickup_enabled
	_pickups = deps.pickups
	_get_live_bot_groups = deps.get_live_bot_groups or _default_get_live_bot_groups
	_unit_get_data = deps.unit_get_data or (Unit and Unit.get_data)
	_unit_is_alive = deps.unit_is_alive or (Unit and Unit.alive)
	_write_blackboard_component = deps.blackboard_write_component or _default_write_blackboard_component
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_should_allow_mule_pickup = deps.should_allow_mule_pickup
	_should_block_pickup_order = deps.should_block_pickup_order
	_last_tome_patch_enabled = nil
	_last_grimoire_patch_enabled = nil
	_warned_group_system_lookup_failure = false
	_warned_blackboard_module_lookup_failure = false

	M.patch_pickups()
	M.sync_live_bot_groups()
end

function M.patch_pickups()
	local tome_enabled = _tome_enabled()
	local grimoire_enabled = _grimoire_enabled()

	_patch_pickup(TOME_PICKUP_NAME, tome_enabled)
	_patch_pickup(GRIMOIRE_PICKUP_NAME, grimoire_enabled)

	if _last_tome_patch_enabled ~= tome_enabled then
		_last_tome_patch_enabled = tome_enabled
		_log(
			"mule_pickup_patch:" .. TOME_PICKUP_NAME,
			"patched mule pickup metadata for tome (enabled=" .. tostring(tome_enabled) .. ")"
		)
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

function M.sanitize_mule_pickup(pickup_component, unit, bot_group, data)
	M.patch_pickups()

	if not pickup_component or not pickup_component.mule_pickup then
		return false
	end

	local allowed, reason = _pickup_allowed_for_bot(unit, pickup_component.mule_pickup, bot_group, data)
	if allowed then
		return false
	end

	pickup_component.mule_pickup = nil
	pickup_component.mule_pickup_distance = math.huge
	if reason == "stale" then
		_log_stale_clear(unit, "pickup_component.mule_pickup")
	elseif reason == "grimoire" then
		_log("mule_pickup_block_grim:" .. tostring(unit), "blocked grimoire mule pickup")
	elseif reason == "tome" then
		_log("mule_pickup_block_tome:" .. tostring(unit), "blocked tome mule pickup")
	elseif reason == "human_slot_open" then
		_log(
			"mule_pickup_block_policy:" .. tostring(unit),
			"blocked pocketable mule pickup to leave the slot open for humans"
		)
	elseif reason == "pocketable_disabled" then
		_log(
			"mule_pickup_block_policy:" .. tostring(unit),
			"blocked pocketable mule pickup because pocketable support is disabled"
		)
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

local function _distance_squared(a, b)
	if not (a and b and Vector3 and Vector3.distance_squared) then
		return math.huge
	end

	return Vector3.distance_squared(a, b)
end

local function _has_any_pickup_order(pickup_orders, available_mule_pickups)
	if not (pickup_orders and available_mule_pickups) then
		return false
	end

	for slot_name in pairs(available_mule_pickups) do
		if pickup_orders[slot_name] then
			return true
		end
	end

	return false
end

local function _assign_proactive_mule_pickups(bot_group, bot_data)
	local available_mule_pickups = bot_group and bot_group._available_mule_pickups
	if not available_mule_pickups then
		return false
	end

	local assigned_pickups = {}
	for _, data in pairs(bot_data) do
		local pickup_component = data.pickup_component
		local current_pickup = pickup_component and pickup_component.mule_pickup
		if current_pickup then
			assigned_pickups[current_pickup] = true
		end

		if data.pickup_orders then
			for _, order in pairs(data.pickup_orders) do
				if order and order.unit then
					assigned_pickups[order.unit] = true
				end
			end
		end
	end

	local changed = false
	local position_lookup = POSITION_LOOKUP
	for unit, data in pairs(bot_data) do
		local pickup_component = data.pickup_component
		if pickup_component and not pickup_component.mule_pickup then
			local has_pickup_order = _has_any_pickup_order(data.pickup_orders, available_mule_pickups)
			local bot_position = position_lookup and position_lookup[unit]
			local follow_position = data.follow_position or bot_position

			if not has_pickup_order and bot_position and follow_position then
				local best_pickup, best_pickup_distance_sq = nil, math.huge

				for _, available_pickups in pairs(available_mule_pickups) do
					for pickup_unit in pairs(available_pickups) do
						local pickup_allowed = not assigned_pickups[pickup_unit]
							and _pickup_allowed_for_bot(unit, pickup_unit, bot_group, data)
						if pickup_allowed then
							local pickup_position = position_lookup[pickup_unit]
							local follow_distance_sq = _distance_squared(follow_position, pickup_position)
							local bot_distance_sq = _distance_squared(bot_position, pickup_position)

							if
								follow_distance_sq < MULE_PICKUP_MAX_DISTANCE_SQ
								and bot_distance_sq < best_pickup_distance_sq
							then
								best_pickup = pickup_unit
								best_pickup_distance_sq = bot_distance_sq
							end
						end
					end
				end

				if best_pickup then
					pickup_component.mule_pickup = best_pickup
					pickup_component.mule_pickup_distance = math.sqrt(best_pickup_distance_sq)
					assigned_pickups[best_pickup] = true
					changed = true
					_log(
						"mule_pickup_assign:" .. tostring(unit),
						"assigned proactive mule pickup for " .. tostring(_unit_get_data(best_pickup, "pickup_type"))
					)
					_mark_destination_refresh(unit)
				end
			end
		end
	end

	return changed
end

local function _clear_behavior_targets(behavior_component, unit, bot_group, data)
	if not behavior_component then
		return false
	end

	local changed = false
	local allow_interaction, reason_interaction =
		_pickup_allowed_for_bot(unit, behavior_component.interaction_unit, bot_group, data)
	if not allow_interaction then
		behavior_component.interaction_unit = nil
		changed = true
		if reason_interaction == "stale" then
			_log_stale_clear(tostring(unit) .. ":interaction_unit", "behavior_component.interaction_unit")
		end
	end
	local allow_forced, reason_forced =
		_pickup_allowed_for_bot(unit, behavior_component.forced_pickup_unit, bot_group, data)
	if not allow_forced then
		behavior_component.forced_pickup_unit = nil
		changed = true
		if reason_forced == "stale" then
			_log_stale_clear(tostring(unit) .. ":forced_pickup_unit", "behavior_component.forced_pickup_unit")
		end
	end

	return changed
end

local function _clear_grimoire_pickup_order(pickup_orders, unit)
	local order = pickup_orders and pickup_orders[POCKETABLE_SLOT_NAME]
	if not order then
		return nil
	end

	local blocked, reason = M.should_block_pickup_order(order.unit)
	if not blocked then
		return nil
	end

	pickup_orders[POCKETABLE_SLOT_NAME] = nil
	if reason == "stale" then
		_log_stale_clear(tostring(unit) .. ":pickup_order", "pickup_orders.slot_pocketable")
	end

	return reason
end

local function _clear_cached_grimoire_pickups(bot_group)
	local available_mule_pickups = bot_group and bot_group._available_mule_pickups
	local available_pickups = available_mule_pickups and available_mule_pickups[POCKETABLE_SLOT_NAME]
	if not available_pickups then
		return false
	end

	local changed = false
	for pickup_unit in pairs(available_pickups) do
		local should_clear, reason = _should_clear_mule_unit(pickup_unit)
		if should_clear then
			available_pickups[pickup_unit] = nil
			changed = true
			if reason == "stale" then
				_log_stale_clear(pickup_unit, "_available_mule_pickups.slot_pocketable")
			end
		end
	end

	return changed
end

function M.sync_live_bot_group(bot_group)
	M.patch_pickups()

	if not bot_group then
		return false
	end

	local changed = _ensure_mule_pickup_slots(bot_group)
	if _clear_cached_grimoire_pickups(bot_group) then
		changed = true
	end
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
			elseif pickup_order_clear_reason == "tome" then
				_log("mule_pickup_order_clear:" .. tostring(unit), "cleared tome mule pickup order")
			end
		end

		if M.sanitize_mule_pickup(data.pickup_component, unit, bot_group, data) then
			unit_changed = true
			changed = true
		end

		if _clear_behavior_targets(data.behavior_component, unit, bot_group, data) then
			unit_changed = true
			changed = true
		end

		if unit_changed and _mark_destination_refresh(unit) then
			_log("mule_pickup_refresh:" .. tostring(unit), "refreshed destination after clearing mule state")
		end
	end

	if _assign_proactive_mule_pickups(bot_group, bot_data) then
		changed = true
	end

	return changed
end

function M.sync_live_bot_groups()
	M.patch_pickups()

	if not _get_live_bot_groups then
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

	local should_clear, reason = _should_clear_mule_unit(pickup_unit)
	if should_clear then
		return true, reason
	end

	if _should_block_pickup_order then
		local blocked, policy_reason = _should_block_pickup_order(pickup_unit)
		if blocked == true then
			return true, policy_reason
		end
	end

	return false, nil
end

-- Called from the consolidated _refresh_destination hook_safe in BetterBots.lua.
-- DMF dedupes hook registrations by (mod, obj, method); registering one hook
-- per feature on the same method silently drops all but the first (#_refresh_destination).
function M.on_refresh_destination(self)
	local changed = M.sanitize_mule_pickup(self._pickup_component, self._unit)
	if changed then
		_clear_behavior_targets(self._behavior_component, self._unit)
	end
end

function M.install_bot_group_hooks(BotGroup)
	if not BotGroup or rawget(BotGroup, BOT_GROUP_PATCH_SENTINEL) then
		return
	end

	BotGroup[BOT_GROUP_PATCH_SENTINEL] = true

	_mod:hook_safe(BotGroup, "init", function(self)
		M.patch_pickups()
		_ensure_mule_pickup_slots(self)
	end)

	_mod:hook_safe(BotGroup, "_update_mule_pickups", function(self)
		M.sync_live_bot_group(self)
	end)
end

function M.register_hooks()
	M.patch_pickups()
	M.sync_live_bot_groups()

	_mod:hook_require(
		"scripts/extension_systems/interaction/interactions/pocketable_interaction",
		function(PocketableInteraction)
			M.install_interaction_hooks(PocketableInteraction)
		end
	)

	_mod:hook_require("scripts/utilities/bot_order", function(BotOrder)
		_mod:hook(BotOrder, "pickup", function(func, bot_unit, pickup_unit, ordering_player)
			local blocked, reason = M.should_block_pickup_order(pickup_unit)
			if blocked then
				_log(
					"mule_pickup_order_block:" .. tostring(bot_unit),
					"blocked " .. tostring(reason) .. " pickup order"
				)
				return nil
			end

			return func(bot_unit, pickup_unit, ordering_player)
		end)
	end)
end

function M.install_interaction_hooks(PocketableInteraction)
	if not PocketableInteraction or rawget(PocketableInteraction, INTERACTION_PATCH_SENTINEL) then
		return
	end

	PocketableInteraction[INTERACTION_PATCH_SENTINEL] = true

	_mod:hook(
		PocketableInteraction,
		"stop",
		function(func, self, world, interactor_unit, interaction_context, t, result, interactor_is_server)
			if not (_debug_enabled and _debug_enabled() and interactor_is_server and result == "success") then
				return func(self, world, interactor_unit, interaction_context, t, result, interactor_is_server)
			end

			local target_unit = interaction_context and interaction_context.target_unit or nil
			local pickup_name = target_unit and _unit_get_data and _unit_get_data(target_unit, "pickup_type") or nil
			local stop_result = func(self, world, interactor_unit, interaction_context, t, result, interactor_is_server)

			_log_mule_pickup_success(interactor_unit, target_unit, pickup_name)

			return stop_result
		end
	)
end

return M
