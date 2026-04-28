local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit
local _ammo
local _is_weakspot_aim_enabled

local NORMAL_RANGED_AMMO_THRESHOLD = 0.5
local BETTERBOTS_RANGED_AMMO_THRESHOLD = 0.2

local _weapon_logged_combos = {}
local _stream_action_logged_combos = {}
local _weakspot_aim_logged_scratchpads = setmetatable({}, { __mode = "k" })

local STREAM_CONFIRM_ACTIONS = {
	flamer_p1_m1 = {
		brace_pressed = "brace_start",
		shoot_braced = "stream_fire",
		shoot_braced_release = "fire_release",
		brace_release = "brace_end",
	},
	forcestaff_p2_m1 = {
		trigger_charge_flame = "stream_fire",
		charge_release = "charge_release",
	},
}

local function is_head_spine_aim_table(aim_at_node)
	if type(aim_at_node) ~= "table" then
		return false
	end

	local has_head = false
	local has_spine = false

	for i = 1, #aim_at_node do
		local node_name = aim_at_node[i]
		if node_name == "j_head" then
			has_head = true
		elseif node_name == "j_spine" then
			has_spine = true
		end
	end

	return has_head and has_spine
end

function M.weapon_log_context(unit)
	local bot_slot = _bot_slot_for_unit(unit) or "?"
	local wielded_slot = "none"
	local weapon_template_name = "none"
	local warp_charge_template_name = "none"
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	if unit_data_extension then
		local inventory_component = unit_data_extension:read_component("inventory")
		local weapon_action_component = unit_data_extension:read_component("weapon_action")
		local weapon_tweaks_component = unit_data_extension:read_component("weapon_tweak_templates")
		wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
		weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
		warp_charge_template_name = weapon_tweaks_component and weapon_tweaks_component.warp_charge_template_name
			or "none"
	end

	return bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name
end

local function target_alive_label(target_unit)
	if not target_unit then
		return "none"
	end

	if HEALTH_ALIVE ~= nil then
		local alive = HEALTH_ALIVE[target_unit]
		if alive ~= nil then
			return alive and "alive" or "dead"
		end
	end

	if ALIVE ~= nil then
		local alive = ALIVE[target_unit]
		if alive ~= nil then
			return alive and "alive" or "dead"
		end
	end

	if Unit and Unit.alive then
		return Unit.alive(target_unit) and "alive" or "dead"
	end

	return "unknown"
end

local function target_breed_name(target_unit)
	local unit_data_extension = target_unit and ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension.breed and unit_data_extension:breed()

	return breed and breed.name or "unknown"
end

local function first_perception_target(perception_component)
	if not perception_component then
		return nil, "none"
	end

	if perception_component.target_enemy then
		return perception_component.target_enemy, "target_enemy"
	end

	if perception_component.priority_target_enemy then
		return perception_component.priority_target_enemy, "priority_target_enemy"
	end

	if perception_component.opportunity_target_enemy then
		return perception_component.opportunity_target_enemy, "opportunity_target_enemy"
	end

	if perception_component.urgent_target_enemy then
		return perception_component.urgent_target_enemy, "urgent_target_enemy"
	end

	return nil, "none"
end

function M.weapon_target_log_context(unit)
	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local perception_component = blackboard and blackboard.perception
	local target_unit, target_slot = first_perception_target(perception_component)
	local target_alive = target_alive_label(target_unit)
	local breed_name = target_breed_name(target_unit)

	return target_slot, target_unit or "none", target_alive, breed_name
end

function M._stream_action_phase(template_name, action_input)
	local actions = STREAM_CONFIRM_ACTIONS[template_name]

	return actions and actions[action_input] or nil
end

function M.log_stream_action(bot_slot, template_name, action_input)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end

	local phase = M._stream_action_phase(template_name, action_input)
	if not phase then
		return false
	end

	local combo_key = tostring(bot_slot) .. ":" .. tostring(template_name) .. ":" .. tostring(action_input)
	if _stream_action_logged_combos[combo_key] then
		return true
	end

	_stream_action_logged_combos[combo_key] = true
	_debug_log(
		"stream_action:" .. combo_key,
		_fixed_time(),
		"stream action queued for "
			.. tostring(template_name)
			.. " via "
			.. tostring(action_input)
			.. " (phase="
			.. tostring(phase)
			.. ", bot="
			.. tostring(bot_slot)
			.. ")"
	)

	return true
end

function M.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
	if not unit or not weapon_template or not scratchpad or not scratchpad.aim_at_node then
		return nil
	end

	local attack_meta_data = weapon_template.attack_meta_data or {}
	if not is_head_spine_aim_table(attack_meta_data.aim_at_node) then
		return nil
	end

	if scratchpad.aim_at_node ~= "j_head" and scratchpad.aim_at_node ~= "j_spine" then
		return nil
	end

	local bot_slot, _, weapon_template_name = M.weapon_log_context(unit)

	return {
		bot_slot = bot_slot,
		weapon_template_name = weapon_template_name,
		selected_node = scratchpad.aim_at_node,
	}
end

function M.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end
	if _is_weakspot_aim_enabled and not _is_weakspot_aim_enabled() then
		return false
	end

	if _weakspot_aim_logged_scratchpads[scratchpad] then
		return true
	end

	local context = M.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
	if not context then
		return false
	end

	_weakspot_aim_logged_scratchpads[scratchpad] = true
	_debug_log(
		"weakspot_aim:" .. tostring(unit),
		_fixed_time(),
		"weakspot aim selected "
			.. tostring(context.selected_node)
			.. " (weapon="
			.. tostring(context.weapon_template_name)
			.. ", bot="
			.. tostring(context.bot_slot)
			.. ")"
	)

	return true
end

local function ammo_api()
	if _ammo ~= nil then
		return _ammo or nil
	end

	local ok, ammo = pcall(require, "scripts/utilities/ammo")
	if ok then
		_ammo = ammo
	elseif _mod and _mod.warning then
		_ammo = false
		_mod:warning("BetterBots: ammo utility unavailable; dead-zone ranged fire detection disabled")
	end

	return _ammo or nil
end

local function dead_zone_target_breed(unit)
	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local perception = blackboard and blackboard.perception
	local target_unit = perception and perception.target_enemy
	if not target_unit then
		return nil
	end

	local target_unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if not target_unit_data_extension or not target_unit_data_extension.breed then
		return nil
	end

	return target_unit_data_extension:breed()
end

function M.dead_zone_ranged_fire_context(unit, action_input)
	if action_input ~= "shoot_pressed" and action_input ~= "shoot_charge" then
		return nil
	end

	local bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name = M.weapon_log_context(unit)
	if wielded_slot ~= "slot_secondary" or warp_charge_template_name ~= "none" then
		return nil
	end

	local ammo = ammo_api()
	local ammo_pct = ammo and ammo.current_slot_percentage and ammo.current_slot_percentage(unit, "slot_secondary")
		or nil
	if not ammo_pct or ammo_pct <= BETTERBOTS_RANGED_AMMO_THRESHOLD or ammo_pct > NORMAL_RANGED_AMMO_THRESHOLD then
		return nil
	end

	local breed = dead_zone_target_breed(unit)
	local tags = breed and breed.tags or nil
	if tags and (tags.elite or tags.special or tags.monster) then
		return nil
	end

	return {
		action_input = action_input,
		ammo_pct = ammo_pct,
		bot_slot = bot_slot,
		target_breed_name = breed and breed.name or "unknown",
		weapon_template_name = weapon_template_name,
	}
end

function M.log_dead_zone_ranged_fire(unit, action_input)
	local context = M.dead_zone_ranged_fire_context(unit, action_input)
	if not context then
		return false
	end

	_debug_log(
		"ranged_dead_zone_fire:" .. tostring(context.bot_slot) .. ":" .. tostring(context.weapon_template_name),
		_fixed_time(),
		"ranged dead-zone override kept normal shot (ammo="
			.. string.format("%.2f", context.ammo_pct)
			.. ", target="
			.. tostring(context.target_breed_name)
			.. ", weapon="
			.. tostring(context.weapon_template_name)
			.. ", action="
			.. tostring(context.action_input)
			.. ")",
		10
	)

	return true
end

function M.log_bot_weapon_action(unit, action_input, raw_input)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end

	local bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name = M.weapon_log_context(unit)
	local target_slot, target_unit, target_alive, breed_name = M.weapon_target_log_context(unit)
	local combo_key = tostring(bot_slot)
		.. ":"
		.. tostring(weapon_template_name)
		.. ":"
		.. tostring(action_input)
		.. ":"
		.. tostring(raw_input)
		.. ":"
		.. tostring(target_slot)
		.. ":"
		.. tostring(target_unit)
		.. ":"
		.. tostring(target_alive)
	if not _weapon_logged_combos[combo_key] then
		_weapon_logged_combos[combo_key] = true
		_debug_log(
			"bot_weapon:" .. combo_key,
			_fixed_time(),
			"bot weapon: bot="
				.. tostring(bot_slot)
				.. " slot="
				.. tostring(wielded_slot)
				.. " weapon_template="
				.. tostring(weapon_template_name)
				.. " warp_template="
				.. tostring(warp_charge_template_name)
				.. " action="
				.. tostring(action_input)
				.. " raw_input="
				.. tostring(raw_input)
				.. " target_slot="
				.. tostring(target_slot)
				.. " target="
				.. tostring(target_unit)
				.. " target_alive="
				.. tostring(target_alive)
				.. " target_breed="
				.. tostring(breed_name)
		)
	end

	M.log_dead_zone_ranged_fire(unit, action_input)
	return true
end

function M.init(deps)
	deps = deps or {}
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_ammo = deps.ammo
	_is_weakspot_aim_enabled = deps.is_weakspot_aim_enabled or function()
		return true
	end
	_weapon_logged_combos = {}
	_stream_action_logged_combos = {}
	_weakspot_aim_logged_scratchpads = setmetatable({}, { __mode = "k" })
end

return M
