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
local _bot_slot_for_unit
local _is_enabled
local _is_host_singleplay
local _should_block_pickup_order
local _needs_ammo_pickup
local _record_health_station_tag
local _can_reserve_grenade_pickup
local _reserve_grenade_pickup
local _can_reserve_health_station
local _reserve_health_station

local SUPPORTED_SLOT_NAMES = {
	slot_pocketable = true,
	slot_pocketable_small = true,
}

local EXPLICIT_SLOT_PICKUPS = {
	tome = true,
	grimoire = true,
}
local SMART_TAG_SYSTEM_SENTINEL = "__bb_smart_tag_orders_installed"
local HEALTH_STATION_TAG_VALID_S = 20
local PICKUP_TAG_VALID_S = 20
local _health_station_tagged_until = setmetatable({}, { __mode = "k" })
local _pickup_tagged_until = setmetatable({}, { __mode = "k" })
local _set_tag_dispatch_suppression = 0

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _unit_data(unit, field_name)
	if not (unit and Unit and Unit.get_data) then
		return nil
	end

	local ok, value = pcall(Unit.get_data, unit, field_name)

	return ok and value or nil
end

local function _distance_squared(a, b)
	if Vector3 and Vector3.distance_squared then
		return Vector3.distance_squared(a, b)
	end

	local ax = a and a.x or 0
	local ay = a and a.y or 0
	local az = a and a.z or 0
	local bx = b and b.x or 0
	local by = b and b.y or 0
	local bz = b and b.z or 0
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz

	return dx * dx + dy * dy + dz * dz
end

local function _pickups_registry()
	return require("scripts/settings/pickup/pickups")
end

local function _ammo_module()
	return require("scripts/utilities/ammo")
end

local function _bot_order_module()
	return require("scripts/utilities/bot_order")
end

local function _solo_play_mod_active()
	local get_mod = rawget(_G, "get_mod")
	if not get_mod then
		return false
	end

	local ok, solo_play_mod = pcall(get_mod, "SoloPlay")
	if not (ok and solo_play_mod and solo_play_mod.is_soloplay) then
		return false
	end

	local active_ok, active = pcall(solo_play_mod.is_soloplay)

	return active_ok and active == true
end

local function _singleplay_host_type()
	local multiplayer_session = Managers and Managers.multiplayer_session
	if not (multiplayer_session and multiplayer_session.host_type) then
		return false
	end

	local ok, host_type = pcall(multiplayer_session.host_type, multiplayer_session)

	return ok and (host_type == "singleplay" or host_type == "singleplay_backend_session")
end

local function _host_singleplay()
	if _is_host_singleplay then
		local ok, result = pcall(_is_host_singleplay)

		if ok and result == true then
			return true
		end
	end

	if _solo_play_mod_active() or _singleplay_host_type() then
		return true
	end

	local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
	if not (game_mode_manager and game_mode_manager.settings) then
		return false
	end

	local ok, settings = pcall(game_mode_manager.settings, game_mode_manager)

	return ok and settings and settings.host_singleplay == true or false
end

local function _player_by_unit(unit)
	local player_manager = Managers and Managers.player
	local player = player_manager and player_manager.player_by_unit and player_manager:player_by_unit(unit)

	if player then
		return player
	end

	local player_unit_spawn = Managers and Managers.state and Managers.state.player_unit_spawn
	if player_unit_spawn and player_unit_spawn.owner then
		local ok, owner = pcall(player_unit_spawn.owner, player_unit_spawn, unit)
		if ok then
			return owner
		end
	end

	return nil
end

local function _human_player_by_unit(unit)
	local player = _player_by_unit(unit)

	if not (player and player.is_human_controlled and player:is_human_controlled()) then
		return nil
	end

	return player
end

local function _health_station_target(target_unit)
	return target_unit
		and ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(target_unit, "health_station_system") ~= nil
end

local function _record_pickup_tag(target_unit, pickup_name)
	if not (target_unit and pickup_name) then
		return
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	_pickup_tagged_until[target_unit] = fixed_t + PICKUP_TAG_VALID_S
	_log("pickup_tag:" .. tostring(target_unit), "pickup smart-tag recorded for bot use: " .. tostring(pickup_name))
end

local function _record_tag_permission(tagger_unit, target_unit)
	if not _host_singleplay() then
		return false, "not_host_singleplay"
	end

	local ordering_player = _human_player_by_unit(tagger_unit)
	if not ordering_player then
		return false, "interactor_not_human"
	end

	if _health_station_target(target_unit) then
		local fixed_t = _fixed_time and _fixed_time() or 0
		_health_station_tagged_until[target_unit] = fixed_t + HEALTH_STATION_TAG_VALID_S
		if _record_health_station_tag then
			_record_health_station_tag(target_unit)
		end
		_log("health_station_tag:" .. tostring(target_unit), "health station smart-tag recorded for bot use")
		return true, "health_station"
	end

	local pickup_name = _unit_data(target_unit, "pickup_type")
	_record_pickup_tag(target_unit, pickup_name)

	return pickup_name ~= nil, pickup_name
end

local function _side_player_units(unit)
	local extension_manager = Managers and Managers.state and Managers.state.extension
	local side_system = extension_manager and extension_manager:system("side_system")
	local side = side_system and side_system.side_by_unit and side_system.side_by_unit[unit]

	return side and side.valid_player_units or nil
end

local function _inventory_component(unit)
	local unit_data_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "unit_data_system")
	if unit_data_extension and unit_data_extension.read_component then
		return unit_data_extension:read_component("inventory")
	end

	return nil
end

local function _bot_inventory_slot_open(unit, slot_name)
	local inventory_component = _inventory_component(unit)

	return inventory_component and inventory_component[slot_name] == "not_equipped" or false
end

local function _classify_pickup_target(target_unit)
	local pickup_name = _unit_data(target_unit, "pickup_type")
	if not pickup_name then
		return nil, "no_pickup_type"
	end

	if pickup_name == "small_grenade" then
		return {
			family = "grenade",
			pickup_name = pickup_name,
		}
	end

	local pickup_settings = _pickups_registry().by_name[pickup_name]
	if not pickup_settings then
		return nil, "pickup_settings_missing"
	end

	local slot_name = pickup_settings.slot_name or pickup_settings.inventory_slot_name

	if pickup_settings.group == "ammo" then
		return {
			family = "ammo",
			pickup_name = pickup_name,
		}
	end

	if EXPLICIT_SLOT_PICKUPS[pickup_name] then
		return {
			family = "slot_order",
			pickup_name = pickup_name,
			slot_name = slot_name or "slot_pocketable",
		}
	end

	if slot_name and SUPPORTED_SLOT_NAMES[slot_name] then
		return {
			family = "slot_order",
			pickup_name = pickup_name,
			slot_name = slot_name,
		}
	end

	return nil, "unsupported_pickup_family"
end

local function _bot_is_alive(unit, player)
	if HEALTH_ALIVE ~= nil then
		local alive = HEALTH_ALIVE[unit]
		if alive ~= nil then
			return alive == true
		end
	end

	local saw_dead = false

	if player and player.unit_is_alive then
		local ok, alive = pcall(player.unit_is_alive, player)
		if ok then
			if alive == true then
				return true
			elseif alive == false then
				return false
			end
		end
	end

	if ALIVE ~= nil then
		local alive = ALIVE[unit]
		if alive == true then
			return true
		elseif alive == false then
			saw_dead = true
		end
	end

	if Unit and Unit.alive then
		local ok, alive = pcall(Unit.alive, unit)
		if ok then
			if alive == true then
				return true
			elseif alive == false then
				saw_dead = true
			end
		end
	end

	return unit ~= nil and not saw_dead
end

local function _eligible_bot_for_family(bot_unit, descriptor)
	local player = _player_by_unit(bot_unit)
	if not player or (player.is_human_controlled and player:is_human_controlled()) then
		return false, "not_bot"
	end

	if not _bot_is_alive(bot_unit, player) then
		return false, "bot_dead"
	end

	if descriptor.family == "ammo" then
		if _needs_ammo_pickup then
			if not _needs_ammo_pickup(bot_unit) then
				return false, "ammo_full"
			end
		else
			local Ammo = _ammo_module()
			if Ammo.reserve_ammo_is_full(bot_unit) then
				return false, "ammo_full"
			end
		end

		return true, nil
	end

	if descriptor.family == "slot_order" then
		if not _bot_inventory_slot_open(bot_unit, descriptor.slot_name) then
			return false, "slot_full"
		end

		return true, nil
	end

	if descriptor.family == "grenade" then
		if not _can_reserve_grenade_pickup then
			return false, "grenade_reservation_unavailable"
		end

		return _can_reserve_grenade_pickup(bot_unit, descriptor.pickup_unit)
	end

	if descriptor.family == "health_station" then
		if not _can_reserve_health_station then
			return false, "health_station_reservation_unavailable"
		end

		return _can_reserve_health_station(bot_unit, descriptor.pickup_unit)
	end

	return false, "unsupported_family"
end

local function _eligible_bot_detail(bot_unit, reason)
	if reason == "not_bot" then
		return nil
	end

	local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(bot_unit) or nil
	local bot_label = bot_slot and ("bot=" .. tostring(bot_slot)) or tostring(bot_unit)

	return bot_label .. ":" .. tostring(reason)
end

local function _select_nearest_eligible_bot(interactor_unit, target_unit, descriptor)
	local side_units = _side_player_units(interactor_unit)
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[target_unit]
	local best_bot
	local best_distance_sq = math.huge
	local rejection_details

	if not (side_units and target_position) then
		return nil, "missing_side_or_position", nil
	end

	for i = 1, #side_units do
		local bot_unit = side_units[i]
		local eligible, ineligible_reason = _eligible_bot_for_family(bot_unit, descriptor)

		if eligible then
			local bot_position = POSITION_LOOKUP and POSITION_LOOKUP[bot_unit]
			if bot_position then
				local distance_sq = _distance_squared(bot_position, target_position)
				if distance_sq < best_distance_sq then
					best_bot = bot_unit
					best_distance_sq = distance_sq
				end
			end
		else
			local detail = _eligible_bot_detail(bot_unit, ineligible_reason)
			if detail then
				rejection_details = rejection_details or {}
				rejection_details[#rejection_details + 1] = detail
			end
		end
	end

	if not best_bot then
		return nil, "no_eligible_bot", rejection_details and table.concat(rejection_details, ", ") or nil
	end

	return best_bot, nil, nil
end

function M.try_dispatch(interactor_unit, target_unit, optional_alternate)
	if optional_alternate == "companion_order" then
		return false, "companion_order"
	end

	local recorded, record_reason = _record_tag_permission(interactor_unit, target_unit)
	local ordering_player = _human_player_by_unit(interactor_unit)
	if not ordering_player then
		return false, "interactor_not_human"
	end

	if record_reason == "not_host_singleplay" then
		return false, record_reason
	end

	if recorded and record_reason == "health_station" then
		if (_is_enabled and not _is_enabled()) or not _reserve_health_station then
			return false, "health_station_tag_recorded"
		end

		local descriptor = {
			family = "health_station",
			pickup_name = "health_station",
			pickup_unit = target_unit,
		}
		local bot_unit, select_reason, select_detail =
			_select_nearest_eligible_bot(interactor_unit, target_unit, descriptor)
		if not bot_unit then
			local detail_suffix = select_detail and ", detail=" .. tostring(select_detail) or ""
			_log(
				"smart_tag_order_reject:" .. tostring(target_unit),
				"smart-tag pickup ignored for health_station (reason="
					.. tostring(select_reason)
					.. detail_suffix
					.. ")"
			)
			return false, "health_station_tag_recorded"
		end

		local reserved, reserve_reason = _reserve_health_station(bot_unit, target_unit)
		if not reserved then
			_log(
				"smart_tag_order_reject:" .. tostring(target_unit),
				"smart-tag pickup ignored for health_station (reason="
					.. tostring(reserve_reason or "health_station_reservation_failed")
					.. ")"
			)
			return false, "health_station_tag_recorded"
		end

		_log(
			"smart_tag_order_accept:" .. tostring(target_unit),
			"smart-tag pickup routed health_station to bot "
				.. tostring(_bot_slot_for_unit and _bot_slot_for_unit(bot_unit) or bot_unit)
				.. " (family=health_station)"
		)

		return true, bot_unit
	end

	if _is_enabled and not _is_enabled() then
		return false, "feature_disabled"
	end

	local descriptor, classify_reason = _classify_pickup_target(target_unit)
	if not descriptor then
		return false, classify_reason
	end
	descriptor.pickup_unit = target_unit

	if descriptor.family == "slot_order" and _should_block_pickup_order then
		local blocked, block_reason = _should_block_pickup_order(target_unit)
		if blocked then
			_log(
				"smart_tag_order_reject:" .. tostring(target_unit),
				"smart-tag pickup ignored for "
					.. tostring(descriptor.pickup_name)
					.. " (reason="
					.. tostring(block_reason)
					.. ")"
			)
			return false, block_reason
		end
	end

	local bot_unit, select_reason, select_detail =
		_select_nearest_eligible_bot(interactor_unit, target_unit, descriptor)
	if not bot_unit then
		local detail_suffix = select_detail and ", detail=" .. tostring(select_detail) or ""
		_log(
			"smart_tag_order_reject:" .. tostring(target_unit),
			"smart-tag pickup ignored for "
				.. tostring(descriptor.pickup_name)
				.. " (reason="
				.. tostring(select_reason)
				.. detail_suffix
				.. ")"
		)
		return false, select_reason
	end

	if descriptor.family == "grenade" then
		local reserved, reserve_reason
		if _reserve_grenade_pickup then
			reserved, reserve_reason = _reserve_grenade_pickup(bot_unit, target_unit)
		end
		if not reserved then
			_log(
				"smart_tag_order_reject:" .. tostring(target_unit),
				"smart-tag pickup ignored for "
					.. tostring(descriptor.pickup_name)
					.. " (reason="
					.. tostring(reserve_reason or "grenade_reservation_failed")
					.. ")"
			)
			return false, reserve_reason or "grenade_reservation_failed"
		end
	else
		_bot_order_module().pickup(bot_unit, target_unit, ordering_player)
	end

	_log(
		"smart_tag_order_accept:" .. tostring(target_unit),
		"smart-tag pickup routed "
			.. tostring(descriptor.pickup_name)
			.. " to bot "
			.. tostring(_bot_slot_for_unit and _bot_slot_for_unit(bot_unit) or bot_unit)
			.. " (family="
			.. tostring(descriptor.family)
			.. ")"
	)

	return true, bot_unit
end

local function _target_unit_by_tag_id(smart_tag_system, tag_id)
	if not (smart_tag_system and tag_id and smart_tag_system.tag_by_id) then
		return nil
	end

	local ok, tag = pcall(smart_tag_system.tag_by_id, smart_tag_system, tag_id)
	if not ok or not tag or not tag.target_unit then
		return nil
	end

	local target_ok, target_unit = pcall(tag.target_unit, tag)

	return target_ok and target_unit or nil
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_is_enabled = deps.is_enabled
	_is_host_singleplay = deps.is_host_singleplay
	_health_station_tagged_until = setmetatable({}, { __mode = "k" })
	_pickup_tagged_until = setmetatable({}, { __mode = "k" })
	_set_tag_dispatch_suppression = 0
end

function M.wire(refs)
	_should_block_pickup_order = refs.should_block_pickup_order
	_needs_ammo_pickup = refs.needs_ammo_pickup
	_record_health_station_tag = refs.record_health_station_tag
	_can_reserve_grenade_pickup = refs.can_reserve_grenade_pickup
	_reserve_grenade_pickup = refs.reserve_grenade_pickup
	_can_reserve_health_station = refs.can_reserve_health_station
	_reserve_health_station = refs.reserve_health_station
end

function M.health_station_recently_tagged(target_unit)
	local tagged_until = target_unit and _health_station_tagged_until[target_unit] or nil
	if not tagged_until then
		return false
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	if fixed_t <= tagged_until then
		return true
	end

	_health_station_tagged_until[target_unit] = nil

	return false
end

function M.pickup_recently_tagged(target_unit)
	local tagged_until = target_unit and _pickup_tagged_until[target_unit] or nil
	if not tagged_until then
		return false
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	if fixed_t <= tagged_until then
		return true
	end

	_pickup_tagged_until[target_unit] = nil

	return false
end

local function _log_hook_skip(hook_source, interactor_unit, target_unit, optional_alternate, reason, template_name)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	local pickup_name = _unit_data(target_unit, "pickup_type")
	local smart_tag_target_type = _unit_data(target_unit, "smart_tag_target_type")
	local human_resolved = _human_player_by_unit(interactor_unit) ~= nil
	local key = "smart_tag_order_skip:"
		.. tostring(hook_source)
		.. ":"
		.. tostring(reason)
		.. ":"
		.. tostring(target_unit)

	_log(
		key,
		"smart-tag pickup hook skipped"
			.. " (source="
			.. tostring(hook_source)
			.. ", reason="
			.. tostring(reason)
			.. ", template="
			.. tostring(template_name)
			.. ", target="
			.. tostring(target_unit)
			.. ", pickup="
			.. tostring(pickup_name)
			.. ", smart_tag_target="
			.. tostring(smart_tag_target_type)
			.. ", human="
			.. tostring(human_resolved)
			.. ", alternate="
			.. tostring(optional_alternate)
			.. ")"
	)
end

local function _dispatch_from_hook(interactor_unit, target_unit, optional_alternate, hook_source, template_name)
	local ok, handled, detail = pcall(M.try_dispatch, interactor_unit, target_unit, optional_alternate)
	if not ok and _mod and _mod.warning then
		_mod:warning("BetterBots: smart-tag pickup routing failed: " .. tostring(handled))
	elseif not handled then
		_log_hook_skip(hook_source, interactor_unit, target_unit, optional_alternate, detail, template_name)
	end
end

local function _call_with_set_tag_dispatch_suppressed(callback)
	_set_tag_dispatch_suppression = _set_tag_dispatch_suppression + 1

	local ok, result_a, result_b, result_c, result_d, result_e = pcall(callback)

	_set_tag_dispatch_suppression = math.max(0, _set_tag_dispatch_suppression - 1)

	if not ok then
		error(result_a, 0)
	end

	return result_a, result_b, result_c, result_d, result_e
end

function M.register_hooks()
	_hook_require_now("scripts/extension_systems/smart_tag/smart_tag_system", function(SmartTagSystem)
		if not SmartTagSystem or rawget(SmartTagSystem, SMART_TAG_SYSTEM_SENTINEL) then
			return
		end

		SmartTagSystem[SMART_TAG_SYSTEM_SENTINEL] = true

		if type(SmartTagSystem.set_tag) == "function" then
			_mod:hook(
				SmartTagSystem,
				"set_tag",
				function(func, self, template_name, tagger_unit, target_unit, target_location)
					local result = func(self, template_name, tagger_unit, target_unit, target_location)

					if _set_tag_dispatch_suppression > 0 then
						_record_tag_permission(tagger_unit, target_unit)
					else
						_dispatch_from_hook(tagger_unit, target_unit, nil, "set_tag", template_name)
					end

					return result
				end
			)
		end

		if type(SmartTagSystem.set_contextual_unit_tag) == "function" then
			_mod:hook(
				SmartTagSystem,
				"set_contextual_unit_tag",
				function(func, self, tagger_unit, target_unit, alternate)
					local result = _call_with_set_tag_dispatch_suppressed(function()
						return func(self, tagger_unit, target_unit, alternate)
					end)

					_dispatch_from_hook(tagger_unit, target_unit, alternate, "set_contextual_unit_tag", nil)

					return result
				end
			)
		end

		if type(SmartTagSystem.trigger_tag_interaction) == "function" then
			_mod:hook(
				SmartTagSystem,
				"trigger_tag_interaction",
				function(func, self, tag_id, interactor_unit, target_unit, optional_alternate)
					local dispatch_target_unit = target_unit or _target_unit_by_tag_id(self, tag_id)
					local result = _call_with_set_tag_dispatch_suppressed(function()
						return func(self, tag_id, interactor_unit, target_unit, optional_alternate)
					end)

					_dispatch_from_hook(
						interactor_unit,
						dispatch_target_unit,
						optional_alternate,
						"trigger_tag_interaction",
						nil
					)

					return result
				end
			)
		end
	end)
end

return M
