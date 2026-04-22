local M = {}

local _debug_log
local _debug_enabled
local _fixed_time
local _state_by_unit
local _build_context
local _pickups
local _is_enabled
local _human_units
local _allied_units
local _script_unit_has_extension
local _visual_loadout_api
local _health
local _ammo
local _unit_get_data
local _human_slot_scan_cache

local WIELD_TIMEOUT_S = 2
local USE_TIMEOUT_S = 3
local RETRY_DELAY_S = 1
local MEDICAL_HEALTH_THRESHOLD = 0.60
local MEDICAL_CORRUPTION_THRESHOLD = 0.15
local AMMO_THRESHOLD = 0.30
local SUPPORTED_PICKUPS = {
	ammo_cache_pocketable = {
		kind = "ammo_crate",
		slot_name = "slot_pocketable",
		wield_input = "wield_3",
		use_input = "place",
	},
	medical_crate_pocketable = {
		kind = "medical_crate",
		slot_name = "slot_pocketable",
		wield_input = "wield_3",
		use_input = "place",
	},
	syringe_ability_boost_pocketable = {
		kind = "stim",
		slot_name = "slot_pocketable_small",
		wield_input = "wield_4",
		use_input = "use_self",
	},
	syringe_power_boost_pocketable = {
		kind = "stim",
		slot_name = "slot_pocketable_small",
		wield_input = "wield_4",
		use_input = "use_self",
	},
	syringe_speed_boost_pocketable = {
		kind = "stim",
		slot_name = "slot_pocketable_small",
		wield_input = "wield_4",
		use_input = "use_self",
	},
	syringe_corruption_pocketable = {
		kind = "corruption_stim",
		slot_name = "slot_pocketable_small",
		wield_input = "wield_4",
		use_input = "use_self",
	},
}
local CARRIED_SLOT_ORDER = {
	"slot_pocketable_small",
	"slot_pocketable",
}

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _pickups_registry()
	if _pickups then
		return _pickups
	end

	return require("scripts/settings/pickup/pickups")
end

local function _pickup_entry(pickup_name)
	return pickup_name and SUPPORTED_PICKUPS[pickup_name] or nil
end

local function _pickup_name_from_unit(pickup_unit)
	return pickup_unit and _unit_get_data and _unit_get_data(pickup_unit, "pickup_type") or nil
end

local function _resolve_side(unit)
	local extension_manager = Managers and Managers.state and Managers.state.extension
	local side_system = extension_manager and extension_manager:system("side_system")

	return side_system and side_system.side_by_unit and side_system.side_by_unit[unit] or nil
end

local function _default_human_units(bot_group, unit)
	local side = bot_group and bot_group._side or _resolve_side(unit)
	return side and side.valid_human_units or {}
end

local function _default_allied_units(unit)
	local side = _resolve_side(unit)
	return side and side.valid_player_units or {}
end

local function _inventory_component(unit)
	if unit and unit.inventory then
		return unit.inventory
	end

	local unit_data_extension = _script_unit_has_extension and _script_unit_has_extension(unit, "unit_data_system")
	if unit_data_extension and unit_data_extension.read_component then
		return unit_data_extension:read_component("inventory")
	end

	return nil
end

local function _slot_is_empty(inventory_component, slot_name)
	return inventory_component and inventory_component[slot_name] == "not_equipped"
end

local function _any_human_slot_open(human_units, slot_name)
	local fixed_t = _fixed_time and _fixed_time() or 0
	local cached = _human_slot_scan_cache[slot_name]
	if cached and cached.fixed_t == fixed_t and cached.human_units == human_units then
		return cached.result
	end

	local result = false
	for i = 1, #human_units do
		local inventory_component = _inventory_component(human_units[i])
		if _slot_is_empty(inventory_component, slot_name) then
			result = true
			break
		end
	end

	_human_slot_scan_cache[slot_name] = {
		fixed_t = fixed_t,
		human_units = human_units,
		result = result,
	}

	return result
end

local function _reset_state(state, next_try_t)
	state.stage = nil
	state.pickup_name = nil
	state.slot_name = nil
	state.wield_input = nil
	state.use_input = nil
	state.deadline_t = nil
	state.wait_t = nil
	state.use_snapshot = nil
	state.next_try_t = next_try_t or nil
end

local function _queue_weapon_action_input(action_input_extension, input_name)
	if not (action_input_extension and input_name) then
		return
	end

	if string.find(input_name, "wield_", 1, true) == 1 then
		action_input_extension:bot_queue_action_input("weapon_action", "wield", input_name)
		return
	end

	action_input_extension:bot_queue_action_input("weapon_action", input_name, nil)
end

local function _capture_use_snapshot(slot_name, inventory_component)
	return {
		slot_name = slot_name,
		slot_item = inventory_component and inventory_component[slot_name] or nil,
		wielded_slot = inventory_component and inventory_component.wielded_slot or nil,
	}
end

local function _use_success_confirmed(snapshot, inventory_component)
	if not (snapshot and inventory_component) then
		return false
	end

	if inventory_component[snapshot.slot_name] == snapshot.slot_item then
		return false
	end

	return inventory_component.wielded_slot ~= snapshot.slot_name
end

local function _carried_template_for_slot(unit, slot_name)
	local visual_loadout_extension = _script_unit_has_extension
		and _script_unit_has_extension(unit, "visual_loadout_system")
	if not (visual_loadout_extension and _visual_loadout_api and _visual_loadout_api.weapon_template_from_slot) then
		return nil
	end

	return _visual_loadout_api.weapon_template_from_slot(visual_loadout_extension, slot_name)
end

local function _supported_carried_pickup(unit)
	local inventory_component = _inventory_component(unit)
	if not inventory_component then
		return nil, nil, nil, nil
	end

	for i = 1, #CARRIED_SLOT_ORDER do
		local slot_name = CARRIED_SLOT_ORDER[i]
		if not _slot_is_empty(inventory_component, slot_name) then
			local weapon_template = _carried_template_for_slot(unit, slot_name)
			local pickup_name = weapon_template and weapon_template.pickup_name or nil
			local entry = _pickup_entry(pickup_name)

			if entry then
				return entry, pickup_name, slot_name, inventory_component
			end
		end
	end

	return nil, nil, nil, inventory_component
end

local function _stim_threat_high(context)
	if not context then
		return false
	end

	if context.target_is_monster then
		return true
	end

	if context.target_is_elite_special and context.num_nearby >= 3 then
		return true
	end

	if context.challenge_rating_sum >= 8 and context.num_nearby >= 3 then
		return true
	end

	return false
end

-- Corruption stims only restore HP locked by permanent corruption damage; burning
-- one on a bot with clean corruption is pure waste regardless of current HP.
local function _corruption_healing_needed(unit)
	if not (_health and _health.permanent_damage_taken_percent) then
		return false
	end

	local corruption_pct = _health.permanent_damage_taken_percent(unit) or 0

	return corruption_pct > MEDICAL_CORRUPTION_THRESHOLD
end

local function _scan_team_resource_need(unit)
	local units = _allied_units and _allied_units(unit) or nil
	if not units or #units == 0 then
		units = (_human_units and _human_units(nil, unit)) or {}
	end
	local any_medical_need = false
	local any_low_ammo = false

	local function scan_target(target_unit)
		local health_pct = _health and _health.current_health_percent and _health.current_health_percent(target_unit)
			or 1
		local corruption_pct = _health
				and _health.permanent_damage_taken_percent
				and _health.permanent_damage_taken_percent(target_unit)
			or 0

		if health_pct < MEDICAL_HEALTH_THRESHOLD or corruption_pct > MEDICAL_CORRUPTION_THRESHOLD then
			any_medical_need = true
		end

		if _ammo and _ammo.uses_ammo and _ammo.uses_ammo(target_unit) then
			local ammo_pct = _ammo.current_total_percentage and _ammo.current_total_percentage(target_unit) or 1
			if ammo_pct <= AMMO_THRESHOLD then
				any_low_ammo = true
			end
		end
	end

	scan_target(unit)

	for i = 1, #units do
		local target_unit = units[i]
		if target_unit ~= unit then
			scan_target(target_unit)
		end
	end

	return any_medical_need, any_low_ammo
end

local function _desired_action(unit, blackboard)
	local entry, pickup_name, slot_name = _supported_carried_pickup(unit)
	if not entry then
		return nil
	end

	local context = _build_context and _build_context(unit, blackboard) or nil
	if entry.kind == "stim" then
		if _stim_threat_high(context) then
			return {
				pickup_name = pickup_name,
				slot_name = slot_name,
				wield_input = entry.wield_input,
				use_input = entry.use_input,
			}
		end

		return nil
	end

	if entry.kind == "corruption_stim" then
		local safe_to_use = context and context.num_nearby == 0 and not context.target_enemy

		if safe_to_use and _corruption_healing_needed(unit) then
			return {
				pickup_name = pickup_name,
				slot_name = slot_name,
				wield_input = entry.wield_input,
				use_input = entry.use_input,
			}
		end

		return nil
	end

	local any_medical_need, any_low_ammo = _scan_team_resource_need(unit)
	local safe_to_deploy = context
		and context.allies_in_coherency >= 2
		and context.num_nearby == 0
		and not context.target_enemy

	if not safe_to_deploy then
		return nil
	end

	if entry.kind == "medical_crate" and any_medical_need then
		return {
			pickup_name = pickup_name,
			slot_name = slot_name,
			wield_input = entry.wield_input,
			use_input = entry.use_input,
		}
	end

	if entry.kind == "ammo_crate" and any_low_ammo then
		return {
			pickup_name = pickup_name,
			slot_name = slot_name,
			wield_input = entry.wield_input,
			use_input = entry.use_input,
		}
	end

	return nil
end

function M.init(deps)
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_state_by_unit = deps.state_by_unit or setmetatable({}, { __mode = "k" })
	_build_context = deps.build_context
	_pickups = deps.pickups
	_is_enabled = deps.is_enabled
	_human_units = deps.human_units or _default_human_units
	_allied_units = deps.allied_units or _default_allied_units
	_script_unit_has_extension = deps.script_unit_has_extension or (ScriptUnit and ScriptUnit.has_extension)
	_visual_loadout_api = deps.visual_loadout_api
		or require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
	_health = deps.health_module or require("scripts/utilities/health")
	_ammo = deps.ammo_module or require("scripts/utilities/ammo")
	_unit_get_data = deps.unit_get_data or (Unit and Unit.get_data)
	_human_slot_scan_cache = {}

	M.patch_pickups()
end

function M.patch_pickups()
	local enabled = _is_enabled == nil or _is_enabled() ~= false
	local pickups = _pickups_registry()
	local pickups_by_name = pickups and pickups.by_name or nil

	if not pickups_by_name then
		return
	end

	for pickup_name in pairs(SUPPORTED_PICKUPS) do
		local pickup_data = pickups_by_name[pickup_name]
		if pickup_data then
			if pickup_data.inventory_slot_name and not pickup_data.slot_name then
				pickup_data.slot_name = pickup_data.inventory_slot_name
			end

			pickup_data.bots_mule_pickup = enabled
			_log(
				"pocketable_pickup_patch:" .. tostring(pickup_name),
				"patched pocketable pickup metadata for "
					.. tostring(pickup_name)
					.. " (enabled="
					.. tostring(enabled)
					.. ")"
			)
		end
	end
end

function M.should_allow_mule_pickup(unit, pickup_unit, bot_group, data)
	local pickup_name = _pickup_name_from_unit(pickup_unit)
	local entry = _pickup_entry(pickup_name)
	if not entry then
		return true, nil
	end

	if _is_enabled and not _is_enabled() then
		return false, "pocketable_disabled"
	end

	local inventory_component = _inventory_component(unit)
	if not _slot_is_empty(inventory_component, entry.slot_name) then
		return false, "bot_slot_full"
	end

	local pickup_orders = data and data.pickup_orders
	local order = pickup_orders and pickup_orders[entry.slot_name]
	if order and order.unit == pickup_unit then
		return true, nil
	end

	local human_units = (_human_units and _human_units(bot_group, unit)) or {}
	if _any_human_slot_open(human_units, entry.slot_name) then
		return false, "human_slot_open"
	end

	return true, nil
end

function M.should_block_pickup_order(pickup_unit)
	local pickup_name = _pickup_name_from_unit(pickup_unit)
	local entry = _pickup_entry(pickup_name)
	if entry then
		if _is_enabled and not _is_enabled() then
			return true, "pocketable_disabled"
		end

		return false, nil
	end

	if pickup_name and string.find(pickup_name, "_pocketable", 1, true) then
		return true, "unsupported_pocketable"
	end

	return false, nil
end

function M.try_queue(unit, blackboard)
	if _is_enabled and not _is_enabled() then
		return
	end

	local state = _state_by_unit[unit]
	if not state then
		state = {}
		_state_by_unit[unit] = state
	end

	local fixed_t = _fixed_time and _fixed_time() or 0
	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	local action_input_extension = _script_unit_has_extension
		and _script_unit_has_extension(unit, "action_input_system")
	local inventory_component = _inventory_component(unit)
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"

	if not (action_input_extension and inventory_component) then
		return
	end

	if state.stage == "waiting_consume" then
		if _slot_is_empty(inventory_component, state.slot_name) then
			if _use_success_confirmed(state.use_snapshot, inventory_component) then
				_log(
					"pocketable_pickup_success:" .. tostring(unit),
					"pocketable use completed for " .. tostring(state.pickup_name)
				)
			else
				_log(
					"pocketable_pickup_uncertain:" .. tostring(unit),
					"pocketable ended without confirmation for " .. tostring(state.pickup_name)
				)
			end
			_reset_state(state, fixed_t + RETRY_DELAY_S)
			return
		end

		if fixed_t >= (state.deadline_t or 0) then
			_log(
				"pocketable_pickup_timeout:" .. tostring(unit),
				"pocketable use timed out for " .. tostring(state.pickup_name)
			)
			_reset_state(state, fixed_t + RETRY_DELAY_S)
		end

		return
	end

	local desired
	if state.stage == "waiting_wield" then
		if wielded_slot ~= state.slot_name then
			if fixed_t >= (state.deadline_t or 0) then
				_log(
					"pocketable_pickup_wield_timeout:" .. tostring(unit),
					"pocketable wield timed out for " .. tostring(state.pickup_name)
				)
				_reset_state(state, fixed_t + RETRY_DELAY_S)
			end

			return
		end

		state.stage = nil
		desired = {
			pickup_name = state.pickup_name,
			slot_name = state.slot_name,
			wield_input = state.wield_input,
			use_input = state.use_input,
		}
	else
		desired = _desired_action(unit, blackboard)
		if not desired then
			if state.stage then
				_reset_state(state)
			end
			return
		end

		if state.pickup_name and state.pickup_name ~= desired.pickup_name then
			_reset_state(state, fixed_t + RETRY_DELAY_S)
			return
		end
	end

	local carried_template = _carried_template_for_slot(unit, desired.slot_name)
	if not carried_template then
		return
	end

	if _slot_is_empty(inventory_component, desired.slot_name) then
		_reset_state(state, fixed_t + RETRY_DELAY_S)
		return
	end

	state.pickup_name = desired.pickup_name
	state.slot_name = desired.slot_name
	state.wield_input = desired.wield_input
	state.use_input = desired.use_input

	if wielded_slot ~= desired.slot_name then
		_queue_weapon_action_input(action_input_extension, desired.wield_input)
		state.stage = "waiting_wield"
		state.deadline_t = fixed_t + WIELD_TIMEOUT_S
		_log(
			"pocketable_pickup_wield:" .. tostring(unit),
			"queued pocketable wield " .. tostring(desired.wield_input) .. " for " .. tostring(desired.pickup_name)
		)
		return
	end

	if not (carried_template.action_inputs and carried_template.action_inputs[desired.use_input]) then
		_reset_state(state, fixed_t + RETRY_DELAY_S)
		return
	end

	_queue_weapon_action_input(action_input_extension, desired.use_input)
	state.stage = "waiting_consume"
	state.deadline_t = fixed_t + USE_TIMEOUT_S
	state.use_snapshot = _capture_use_snapshot(desired.slot_name, inventory_component)
	_log(
		"pocketable_pickup_use:" .. tostring(unit),
		"queued pocketable input " .. tostring(desired.use_input) .. " for " .. tostring(desired.pickup_name)
	)
end

return M
