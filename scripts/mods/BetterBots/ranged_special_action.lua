-- Ranged weapon-special support for verified shotgun loader and rippergun bayonet families.
-- Keeps policy separate from weapon_action.lua so queue rewriting stays a seam.

local _mod
local _debug_log
local _debug_enabled
local _fixed_time = function()
	return 0
end
local _bot_slot_for_unit
local _armored_type
local _super_armor_type
local _is_enabled
local _rippergun_bayonet_distance
local _armor

local _armed_state_by_unit = setmetatable({}, { __mode = "k" })

local RIPPERGUN_BAYONET_MAX_DISTANCE = 3

local SUPPORTED_SHOTGUN_TEMPLATES = {
	shotgun_p1_m1 = true,
	shotgun_p1_m2 = true,
	shotgun_p1_m3 = true,
	shotgun_p4_m1 = true,
	shotgun_p4_m2 = true,
}

local SUPPORTED_RIPPERGUN_TEMPLATES = {
	ogryn_rippergun_p1_m1 = true,
	ogryn_rippergun_p1_m2 = true,
	ogryn_rippergun_p1_m3 = true,
}

local FIRE_ACTION_INPUTS = {
	shoot_pressed = true,
	zoom_shoot = true,
}

local CLEAR_ACTION_INPUTS = {
	reload = true,
	wield = true,
	vent = true,
	zoom = true,
	zoom_release = true,
}

local M = {}

local function _armor_api()
	if _armor then
		return _armor
	end

	local global_armor = rawget(_G, "Armor")
	if global_armor then
		_armor = global_armor
		return _armor
	end

	local ok, armor = pcall(require, "scripts/utilities/attack/armor")
	if ok then
		_armor = armor
	elseif _mod and _mod.warning then
		_mod:warning("BetterBots: ranged_special_action failed to load scripts/utilities/attack/armor")
	end

	return _armor
end

local function _unit_data_extension(unit)
	return unit and ScriptUnit.has_extension(unit, "unit_data_system") or nil
end

local function _current_weapon_template_name(unit)
	local unit_data_extension = _unit_data_extension(unit)
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil

	return weapon_action_component and weapon_action_component.template_name or nil
end

local function _current_wielded_slot_component(unit)
	local unit_data_extension = _unit_data_extension(unit)
	if not unit_data_extension then
		return nil
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or nil
	if not wielded_slot then
		return nil
	end

	return unit_data_extension:read_component(wielded_slot)
end

local function _current_target_enemy(unit)
	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local perception = blackboard and blackboard.perception

	return perception and perception.target_enemy or nil
end

local function _current_target_distance(unit)
	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local perception = blackboard and blackboard.perception
	local target_distance = perception and perception.target_enemy_distance or nil

	if type(target_distance) == "number" then
		return target_distance
	end

	return nil
end

local function _current_target_breed(unit)
	local target_unit = _current_target_enemy(unit)
	local unit_data_extension = target_unit and ScriptUnit.has_extension(target_unit, "unit_data_system")

	if not unit_data_extension or not unit_data_extension.breed then
		return nil
	end

	return unit_data_extension:breed()
end

local function _current_target_armor(unit, target_breed)
	local armor = _armor_api()
	local target_unit = _current_target_enemy(unit)

	if not armor or not target_unit or not target_breed then
		return nil
	end

	return armor.armor_type(target_unit, target_breed)
end

local function _is_armored_bucket(target_armor)
	return (_armored_type ~= nil and target_armor == _armored_type)
		or (_super_armor_type ~= nil and target_armor == _super_armor_type)
end

local function _should_arm_special(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil

	if not target_breed then
		return false
	end

	if target_breed.is_boss then
		return true
	end

	if tags and (tags.monster or tags.captain or tags.special or tags.elite) then
		return true
	end

	return _is_armored_bucket(target_armor)
end

local function _should_use_rippergun_bayonet(target_breed, target_armor, target_distance)
	local max_distance = _rippergun_bayonet_distance and _rippergun_bayonet_distance() or RIPPERGUN_BAYONET_MAX_DISTANCE
	if type(max_distance) ~= "number" or max_distance <= 0 then
		return false
	end

	if type(target_distance) ~= "number" or target_distance > max_distance then
		return false
	end

	return _should_arm_special(target_breed, target_armor)
end

local function _bot_slot(unit)
	return _bot_slot_for_unit and _bot_slot_for_unit(unit) or "?"
end

local function _log_arm(unit, template_name, target_breed_name, fire_input)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(
		"shotgun_special_arm:" .. tostring(unit) .. ":" .. tostring(template_name),
		_fixed_time(),
		"armed shotgun special for "
			.. tostring(template_name)
			.. " target="
			.. tostring(target_breed_name)
			.. " (bot="
			.. tostring(_bot_slot(unit))
			.. ", fire_input="
			.. tostring(fire_input)
			.. ")"
	)
end

local function _log_spend(unit, template_name, target_breed_name, fire_input)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(
		"shotgun_special_spend:" .. tostring(unit) .. ":" .. tostring(template_name),
		_fixed_time(),
		"spent shotgun special for "
			.. tostring(template_name)
			.. " target="
			.. tostring(target_breed_name)
			.. " (bot="
			.. tostring(_bot_slot(unit))
			.. ", fire_input="
			.. tostring(fire_input)
			.. ")"
	)
end

local function _log_bayonet(unit, template_name, target_breed_name, fire_input)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(
		"rippergun_bayonet:" .. tostring(unit) .. ":" .. tostring(template_name),
		_fixed_time(),
		"queued rippergun bayonet for "
			.. tostring(template_name)
			.. " target="
			.. tostring(target_breed_name)
			.. " (bot="
			.. tostring(_bot_slot(unit))
			.. ", fire_input="
			.. tostring(fire_input)
			.. ")"
	)
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time or function()
		return 0
	end
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_armored_type = deps.ARMOR_TYPE_ARMORED
	_super_armor_type = deps.ARMOR_TYPE_SUPER_ARMOR
	_is_enabled = deps.is_enabled
	_rippergun_bayonet_distance = deps.rippergun_bayonet_distance
	_armor = nil
	_armed_state_by_unit = setmetatable({}, { __mode = "k" })
end

function M.rewrite_weapon_action_input(unit, action_input, raw_input)
	if (_is_enabled and not _is_enabled()) or not FIRE_ACTION_INPUTS[action_input] then
		return action_input, raw_input
	end

	local template_name = _current_weapon_template_name(unit)
	if SUPPORTED_SHOTGUN_TEMPLATES[template_name] then
		local existing_state = _armed_state_by_unit[unit]
		if existing_state and existing_state.template_name == template_name then
			return action_input, raw_input
		end

		local inventory_slot_component = _current_wielded_slot_component(unit)
		if inventory_slot_component and inventory_slot_component.special_active then
			return action_input, raw_input
		end

		local target_breed = _current_target_breed(unit)
		local target_armor = _current_target_armor(unit, target_breed)
		if not _should_arm_special(target_breed, target_armor) then
			return action_input, raw_input
		end

		return "special_action", raw_input
	end

	if SUPPORTED_RIPPERGUN_TEMPLATES[template_name] then
		local target_breed = _current_target_breed(unit)
		local target_armor = _current_target_armor(unit, target_breed)
		local target_distance = _current_target_distance(unit)
		if _should_use_rippergun_bayonet(target_breed, target_armor, target_distance) then
			return "stab", raw_input
		end
	end

	return action_input, raw_input
end

function M.observe_queued_weapon_action(unit, action_input, original_action_input)
	if (_is_enabled and not _is_enabled()) or not unit then
		return
	end

	local template_name = _current_weapon_template_name(unit)
	local active_state = _armed_state_by_unit[unit]

	if active_state and active_state.template_name ~= template_name then
		_armed_state_by_unit[unit] = nil
		active_state = nil
	end

	if SUPPORTED_SHOTGUN_TEMPLATES[template_name] then
		if action_input == "special_action" and FIRE_ACTION_INPUTS[original_action_input] then
			local target_breed = _current_target_breed(unit)
			local target_breed_name = target_breed and target_breed.name or "unknown"

			_armed_state_by_unit[unit] = {
				template_name = template_name,
				target_breed_name = target_breed_name,
				fire_input = original_action_input,
			}
			_log_arm(unit, template_name, target_breed_name, original_action_input)
			return
		end

		if active_state and FIRE_ACTION_INPUTS[action_input] then
			local target_breed = _current_target_breed(unit)
			local target_breed_name = target_breed and target_breed.name or active_state.target_breed_name or "unknown"
			local fire_input = action_input

			_armed_state_by_unit[unit] = nil
			_log_spend(unit, template_name, target_breed_name, fire_input)
			return
		end

		if CLEAR_ACTION_INPUTS[action_input] then
			_armed_state_by_unit[unit] = nil
		end
		return
	end

	if
		SUPPORTED_RIPPERGUN_TEMPLATES[template_name]
		and action_input == "stab"
		and FIRE_ACTION_INPUTS[original_action_input]
	then
		local target_breed = _current_target_breed(unit)
		local target_breed_name = target_breed and target_breed.name or "unknown"

		_log_bayonet(unit, template_name, target_breed_name, original_action_input)
	end
end

return M
