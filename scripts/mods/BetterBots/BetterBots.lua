local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local DEBUG_FORCE_ENABLED = false
local ITEM_WIELD_TIMEOUT_S = 1.5
local ITEM_SEQUENCE_RETRY_S = 1.0
local ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.2
local ITEM_DEFAULT_START_DELAY_S = 0.2
local ABILITY_STATE_FAIL_RETRY_S = 0.35
local META_PATCH_VERSION = "2026-03-04-tier2-v3"
local CONDITIONS_PATCH_VERSION = "2026-03-05-conditions-v4"
local _last_debug_log_t_by_key = {}
local _patched_ability_templates = setmetatable({}, { __mode = "k" })
local _patched_bt_bot_conditions = setmetatable({}, { __mode = "k" })
local _patched_bt_conditions = setmetatable({}, { __mode = "k" })
local _fallback_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_charge_event_by_unit = setmetatable({}, { __mode = "k" })
local _fallback_queue_dumped_by_key = {}
local _decision_context_cache_by_unit = setmetatable({}, { __mode = "k" })
local _super_armor_breed_flag_by_name = {}

local LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY = {
	zealot_relic = true,
}

local LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
	adamant_area_buff_drone = true,
}

local ARMOR_TYPES = ArmorSettings.types
local ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPES and ARMOR_TYPES.super_armor

local function _fixed_time()
	return FixedFrame.get_latest_fixed_time() or 0
end

local function _debug_enabled()
	if DEBUG_FORCE_ENABLED then
		return true
	end

	return mod:get(DEBUG_SETTING_ID) == true
end

local function _debug_log(key, fixed_t, message, min_interval_s)
	if not _debug_enabled() then
		return
	end

	local t = fixed_t or 0
	local interval_s = min_interval_s or DEBUG_LOG_INTERVAL_S
	local last_t = _last_debug_log_t_by_key[key]
	if last_t and t - last_t < interval_s then
		return
	end

	_last_debug_log_t_by_key[key] = t
	mod:echo("BetterBots DEBUG: " .. message)
end

-- Tier 2 templates exist but are missing ability_meta_data.
-- This metadata is consumed by BtBotActivateAbilityAction.
local TIER2_META_DATA = {
	zealot_invisibility = {
		activation = {
			action_input = "stance_pressed",
		},
	},
	zealot_dash = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_taunt_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	psyker_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
}

-- Veteran templates ship with stance_pressed metadata, but runtime validation
-- for bot input expects combat_ability_pressed/combat_ability_released.
local META_DATA_OVERRIDES = {
	veteran_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
	veteran_stealth_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
}

local function _inject_missing_ability_meta_data(AbilityTemplates)
	if _patched_ability_templates[AbilityTemplates] then
		return
	end

	local injected_count = 0
	local overridden_count = 0

	for template_name, meta_data in pairs(TIER2_META_DATA) do
		local template = rawget(AbilityTemplates, template_name)
		if template and not template.ability_meta_data then
			template.ability_meta_data = meta_data
			injected_count = injected_count + 1
			mod:echo("BetterBots: injected meta_data for " .. template_name)
		end
	end

	for template_name, meta_data in pairs(META_DATA_OVERRIDES) do
		local template = rawget(AbilityTemplates, template_name)
		local current_input = template
			and template.ability_meta_data
			and template.ability_meta_data.activation
			and template.ability_meta_data.activation.action_input
		local target_input = meta_data.activation.action_input

		if template and current_input ~= target_input then
			template.ability_meta_data = meta_data
			overridden_count = overridden_count + 1
			mod:echo(
				"BetterBots: patched meta_data for "
					.. template_name
					.. " (action_input="
					.. tostring(current_input)
					.. " -> "
					.. tostring(target_input)
					.. ")"
			)
		end
	end

	_patched_ability_templates[AbilityTemplates] = true
	_debug_log(
		"meta_injection:" .. tostring(AbilityTemplates),
		0,
		"ability template metadata patch installed (version="
			.. META_PATCH_VERSION
			.. ", injected="
			.. tostring(injected_count)
			.. ", overridden="
			.. tostring(overridden_count)
			.. ")"
	)
end

local function _is_tagged(tags, tag_name)
	return tags and tags[tag_name] == true
end

local function _enemy_breed(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	return unit_data_extension and unit_data_extension:breed() or nil
end

local function _breed_has_super_armor(breed)
	if not breed then
		return false
	end

	local breed_name = breed.name
	if breed_name ~= nil then
		local cached_value = _super_armor_breed_flag_by_name[breed_name]
		if cached_value ~= nil then
			return cached_value
		end
	end

	local has_super_armor = false
	if ARMOR_TYPE_SUPER_ARMOR and breed.armor_type == ARMOR_TYPE_SUPER_ARMOR then
		has_super_armor = true
	end

	local tags = breed.tags
	if not has_super_armor and tags and tags.super_armor == true then
		has_super_armor = true
	end

	local hit_zone_armor_override = breed.hit_zone_armor_override
	if not has_super_armor and hit_zone_armor_override and ARMOR_TYPE_SUPER_ARMOR then
		for _, armor_type in pairs(hit_zone_armor_override) do
			if armor_type == ARMOR_TYPE_SUPER_ARMOR then
				has_super_armor = true
				break
			end
		end
	end

	if breed_name ~= nil then
		_super_armor_breed_flag_by_name[breed_name] = has_super_armor
	end

	return has_super_armor
end

local function _build_ability_decision_context(unit, blackboard)
	local fixed_t = _fixed_time()
	local cached_entry = _decision_context_cache_by_unit[unit]
	if cached_entry and cached_entry.fixed_t == fixed_t then
		return cached_entry.context
	end

	local context = {
		num_nearby = 0,
		challenge_rating_sum = 0,
		elite_count = 0,
		special_count = 0,
		monster_count = 0,
		ranged_count = 0,
		melee_count = 0,
		health_pct = 1,
		toughness_pct = 1,
		peril_pct = nil,
		target_enemy = nil,
		target_enemy_distance = nil,
		target_enemy_type = nil,
		priority_target_enemy = nil,
		opportunity_target_enemy = nil,
		urgent_target_enemy = nil,
		target_ally_needs_aid = false,
		target_ally_distance = nil,
		target_is_elite_special = false,
		target_is_monster = false,
		target_is_super_armor = false,
	}

	local perception_component = blackboard and blackboard.perception
	if perception_component then
		context.target_enemy = perception_component.target_enemy
		context.target_enemy_distance = perception_component.target_enemy_distance
		context.target_enemy_type = perception_component.target_enemy_type
		context.priority_target_enemy = perception_component.priority_target_enemy
		context.opportunity_target_enemy = perception_component.opportunity_target_enemy
		context.urgent_target_enemy = perception_component.urgent_target_enemy
		context.target_ally_needs_aid = perception_component.target_ally_needs_aid == true
		context.target_ally_distance = perception_component.target_ally_distance
	end

	local health_extension = ScriptUnit.has_extension(unit, "health_system")
	if health_extension and health_extension.current_health_percent then
		context.health_pct = health_extension:current_health_percent() or context.health_pct
	end

	local toughness_extension = ScriptUnit.has_extension(unit, "toughness_system")
	if toughness_extension and toughness_extension.current_toughness_percent then
		context.toughness_pct = toughness_extension:current_toughness_percent() or context.toughness_pct
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if unit_data_extension then
		local warp_charge_component = unit_data_extension:read_component("warp_charge")
		if warp_charge_component and warp_charge_component.current_percentage ~= nil then
			context.peril_pct = warp_charge_component.current_percentage
		end
	end

	local perception_extension = ScriptUnit.has_extension(unit, "perception_system")
	if perception_extension then
		local enemies_in_proximity, num_enemies_in_proximity = perception_extension:enemies_in_proximity()
		context.num_nearby = num_enemies_in_proximity or 0

		for i = 1, context.num_nearby do
			local enemy_unit = enemies_in_proximity[i]
			local enemy_breed = _enemy_breed(enemy_unit)
			if enemy_breed then
				local tags = enemy_breed.tags
				context.challenge_rating_sum = context.challenge_rating_sum + (enemy_breed.challenge_rating or 0)
				if _is_tagged(tags, "elite") then
					context.elite_count = context.elite_count + 1
				end
				if _is_tagged(tags, "special") then
					context.special_count = context.special_count + 1
				end
				if _is_tagged(tags, "monster") then
					context.monster_count = context.monster_count + 1
				end
				if _is_tagged(tags, "ranged") then
					context.ranged_count = context.ranged_count + 1
				else
					context.melee_count = context.melee_count + 1
				end
			end
		end
	end

	if context.target_enemy then
		local target_breed = _enemy_breed(context.target_enemy)
		if target_breed then
			local tags = target_breed.tags
			context.target_is_elite_special = _is_tagged(tags, "elite") or _is_tagged(tags, "special")
			context.target_is_monster = _is_tagged(tags, "monster")
			context.target_is_super_armor = _breed_has_super_armor(target_breed)
		end
	end

	_decision_context_cache_by_unit[unit] = {
		fixed_t = fixed_t,
		context = context,
	}

	return context
end

local function _resolve_veteran_class_tag(ability_extension)
	local equipped_abilities = ability_extension and ability_extension._equipped_abilities
	local combat_ability = equipped_abilities and equipped_abilities.combat_ability
	local tweak_data = combat_ability and combat_ability.ability_template_tweak_data
	local class_tag = tweak_data and tweak_data.class_tag
	local ability_name = combat_ability and combat_ability.name or ""

	if class_tag then
		return class_tag, "class_tag"
	end

	if string.find(ability_name, "shout", 1, true) then
		return "squad_leader", "ability_name"
	end
	if string.find(ability_name, "stance", 1, true) then
		return "ranger", "ability_name"
	end

	return nil, "unknown"
end

local function _can_activate_veteran_combat_ability(
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension,
	context
)
	local class_tag, source = _resolve_veteran_class_tag(ability_extension)
	if class_tag == "squad_leader" then
		if context.num_nearby >= 4 then
			return true, "veteran_voc_surrounded"
		end
		if context.toughness_pct < 0.45 and context.num_nearby >= 2 then
			return true, "veteran_voc_low_toughness"
		end
		if context.toughness_pct < 0.25 and context.num_nearby >= 1 then
			return true, "veteran_voc_critical_toughness"
		end
		if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) <= 9 then
			return true, "veteran_voc_ally_aid"
		end
		if context.toughness_pct > 0.80 and context.num_nearby <= 2 then
			return false, "veteran_voc_block_safe_state"
		end

		return false, "veteran_voc_hold"
	end

	if class_tag == "base" or class_tag == "ranger" then
		if context.num_nearby > 5 and context.target_enemy_type == "melee" then
			return false, "veteran_stance_block_surrounded"
		end

		local can_activate_vanilla = conditions._can_activate_veteran_ranger_ability(
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running
		)
		if can_activate_vanilla then
			return true, "veteran_stance_target_elite_special"
		end

		if context.urgent_target_enemy and context.num_nearby <= 2 then
			return true, "veteran_stance_urgent_target"
		end

		return false, "veteran_stance_hold"
	end

	return nil, "veteran_variant_" .. source
end

local function _can_activate_veteran_stealth(context)
	if context.num_nearby == 0 then
		return false, "veteran_stealth_block_no_enemies"
	end
	if context.toughness_pct < 0.15 and context.num_nearby >= 3 then
		return true, "veteran_stealth_critical_toughness"
	end
	if context.health_pct < 0.35 and context.num_nearby >= 2 then
		return true, "veteran_stealth_low_health"
	end
	if
		context.target_ally_needs_aid
		and (context.target_ally_distance or math.huge) <= 20
		and context.num_nearby >= 2
	then
		return true, "veteran_stealth_ally_aid"
	end
	if context.num_nearby >= 7 and context.toughness_pct < 0.40 then
		return true, "veteran_stealth_overwhelmed"
	end

	return false, "veteran_stealth_hold"
end

local function _can_activate_zealot_dash(context)
	local target_distance = context.target_enemy_distance
	if not context.target_enemy then
		return false, "zealot_dash_block_no_target"
	end
	if target_distance and target_distance < 3 then
		return false, "zealot_dash_block_target_too_close"
	end
	if context.target_is_super_armor then
		return false, "zealot_dash_block_super_armor"
	end
	if context.priority_target_enemy and target_distance and target_distance > 4 then
		return true, "zealot_dash_priority_target"
	end
	if
		context.toughness_pct < 0.30
		and context.num_nearby > 0
		and target_distance
		and target_distance > 3
		and target_distance < 20
	then
		return true, "zealot_dash_low_toughness"
	end
	if context.target_is_elite_special and target_distance and target_distance > 5 and target_distance < 20 then
		return true, "zealot_dash_elite_special_gap"
	end

	return false, "zealot_dash_hold"
end

local function _can_activate_zealot_invisibility(context)
	if context.num_nearby == 0 then
		return false, "zealot_stealth_block_no_enemies"
	end
	if (context.toughness_pct < 0.20 and context.num_nearby >= 3) or context.health_pct < 0.25 then
		return true, "zealot_stealth_emergency"
	end
	if context.num_nearby >= 5 and context.toughness_pct < 0.50 then
		return true, "zealot_stealth_overwhelmed"
	end
	if
		context.target_ally_needs_aid
		and (context.target_ally_distance or math.huge) <= 12
		and context.num_nearby >= 2
	then
		return true, "zealot_stealth_ally_reposition"
	end

	return false, "zealot_stealth_hold"
end

local function _can_activate_psyker_shout(context)
	if context.num_nearby == 0 then
		return false, "psyker_shout_block_no_enemies"
	end
	if context.peril_pct and context.peril_pct >= 0.75 then
		return true, "psyker_shout_high_peril"
	end
	if context.num_nearby >= 3 then
		return true, "psyker_shout_surrounded"
	end
	if context.toughness_pct < 0.20 and context.num_nearby >= 1 then
		return true, "psyker_shout_low_toughness"
	end
	if context.priority_target_enemy and context.target_enemy_distance and context.target_enemy_distance <= 15 then
		return true, "psyker_shout_priority_target"
	end
	if context.peril_pct and context.peril_pct < 0.30 and context.num_nearby < 3 and context.toughness_pct > 0.50 then
		return false, "psyker_shout_block_low_value"
	end

	return false, "psyker_shout_hold"
end

local function _can_activate_psyker_stance(context)
	if context.peril_pct == nil then
		return nil, "psyker_stance_missing_peril"
	end
	if context.num_nearby == 0 then
		return false, "psyker_stance_block_no_enemies"
	end
	if context.health_pct < 0.25 then
		return false, "psyker_stance_block_low_health"
	end
	if context.peril_pct < 0.20 or context.peril_pct > 0.90 then
		return false, "psyker_stance_block_peril_window"
	end
	if
		(context.opportunity_target_enemy or context.urgent_target_enemy)
		and context.peril_pct >= 0.35
		and context.peril_pct <= 0.85
	then
		return true, "psyker_stance_target_window"
	end
	if context.challenge_rating_sum >= 5.0 and context.peril_pct >= 0.35 and context.peril_pct <= 0.85 then
		return true, "psyker_stance_threat_window"
	end

	return false, "psyker_stance_hold"
end

local function _can_activate_ogryn_charge(context)
	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 4 then
		return false, "ogryn_charge_block_target_too_close"
	end
	if context.priority_target_enemy and target_distance and target_distance > 4 then
		return true, "ogryn_charge_priority_target"
	end
	if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 6 then
		return true, "ogryn_charge_ally_aid"
	end
	if context.opportunity_target_enemy and target_distance and target_distance >= 8 and target_distance <= 18 then
		return true, "ogryn_charge_opportunity_target"
	end
	if context.num_nearby >= 4 and context.toughness_pct < 0.20 then
		return true, "ogryn_charge_escape"
	end
	if context.num_nearby == 0 and not context.priority_target_enemy and not context.target_ally_needs_aid then
		return false, "ogryn_charge_block_no_pressure"
	end
	if not context.target_enemy and not context.priority_target_enemy then
		return false, "ogryn_charge_block_no_target"
	end

	return false, "ogryn_charge_hold"
end

local function _can_activate_ogryn_taunt(context)
	if context.toughness_pct < 0.20 and context.health_pct < 0.30 then
		return false, "ogryn_taunt_block_too_fragile"
	end
	if context.target_ally_needs_aid and context.num_nearby >= 2 and context.toughness_pct > 0.30 then
		return true, "ogryn_taunt_ally_aid"
	end
	if context.num_nearby >= 4 and context.toughness_pct > 0.40 and context.health_pct > 0.30 then
		return true, "ogryn_taunt_horde_control"
	end
	if context.challenge_rating_sum >= 5.0 and context.num_nearby >= 3 and context.toughness_pct > 0.35 then
		return true, "ogryn_taunt_high_threat"
	end
	if context.num_nearby <= 2 and context.challenge_rating_sum < 1.5 then
		return false, "ogryn_taunt_block_low_value"
	end

	return false, "ogryn_taunt_hold"
end

local function _can_activate_ogryn_gunlugger(context)
	local target_distance = context.target_enemy_distance
	if context.num_nearby >= 3 then
		return false, "ogryn_gunlugger_block_melee_pressure"
	end
	if target_distance and target_distance < 4 then
		return false, "ogryn_gunlugger_block_target_too_close"
	end
	if context.challenge_rating_sum < 2.0 then
		return false, "ogryn_gunlugger_block_low_threat"
	end
	if context.urgent_target_enemy and context.num_nearby <= 1 and target_distance and target_distance > 5 then
		return true, "ogryn_gunlugger_urgent_target"
	end
	if
		context.target_enemy_type == "ranged"
		and target_distance
		and target_distance > 5
		and (context.elite_count + context.special_count) >= 2
	then
		return true, "ogryn_gunlugger_ranged_pack"
	end
	if context.challenge_rating_sum >= 6.0 and target_distance and target_distance > 5 and context.num_nearby <= 2 then
		return true, "ogryn_gunlugger_high_threat"
	end

	return false, "ogryn_gunlugger_hold"
end

local function _can_activate_adamant_stance(context)
	local target_distance = context.target_enemy_distance
	if context.toughness_pct < 0.30 then
		return true, "adamant_stance_low_toughness"
	end
	if context.num_nearby >= 3 and context.toughness_pct < 0.60 then
		return true, "adamant_stance_surrounded"
	end
	if context.target_is_monster and target_distance and target_distance < 8 then
		return true, "adamant_stance_monster_pressure"
	end
	if context.elite_count >= 2 and context.toughness_pct < 0.50 then
		return true, "adamant_stance_elite_pressure"
	end
	if context.toughness_pct > 0.70 and context.num_nearby <= 1 then
		return false, "adamant_stance_block_safe_state"
	end

	return false, "adamant_stance_hold"
end

local function _can_activate_adamant_charge(context)
	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 3 then
		return false, "adamant_charge_block_target_too_close"
	end
	if context.num_nearby == 0 and not context.priority_target_enemy and not context.target_is_elite_special then
		return false, "adamant_charge_block_no_pressure"
	end
	if context.num_nearby >= 2 and target_distance and target_distance > 3 and target_distance < 10 then
		return true, "adamant_charge_density"
	end
	if context.target_is_elite_special and target_distance and target_distance > 3 and target_distance < 10 then
		return true, "adamant_charge_elite_special"
	end
	if context.priority_target_enemy and target_distance and target_distance > 3 then
		return true, "adamant_charge_priority_target"
	end

	return false, "adamant_charge_hold"
end

local function _can_activate_adamant_shout(context)
	if context.toughness_pct < 0.25 and context.num_nearby >= 2 then
		return true, "adamant_shout_low_toughness"
	end
	if context.num_nearby >= 5 and context.toughness_pct < 0.50 then
		return true, "adamant_shout_density"
	end

	return false, "adamant_shout_hold"
end

local function _can_activate_broker_focus(context)
	if context.num_nearby == 0 then
		return false, "broker_focus_block_no_enemies"
	end
	if context.toughness_pct < 0.40 then
		return true, "broker_focus_low_toughness"
	end
	if context.target_enemy_type == "ranged" and context.num_nearby >= 2 then
		return true, "broker_focus_ranged_pressure"
	end
	if context.num_nearby >= 5 then
		return true, "broker_focus_density"
	end

	return false, "broker_focus_hold"
end

local function _can_activate_broker_rage(context)
	if context.num_nearby == 0 then
		return false, "broker_rage_block_no_enemies"
	end
	if context.toughness_pct < 0.40 then
		return true, "broker_rage_low_toughness"
	end
	if context.num_nearby >= 3 and context.melee_count >= 2 then
		return true, "broker_rage_melee_pressure"
	end
	if (context.elite_count + context.monster_count) >= 1 and context.num_nearby >= 1 then
		return true, "broker_rage_elite_pressure"
	end
	if context.num_nearby >= 6 then
		return true, "broker_rage_density"
	end
	if context.target_enemy_type == "ranged" and context.num_nearby <= 2 then
		return false, "broker_rage_block_ranged_only"
	end

	return false, "broker_rage_hold"
end

local TEMPLATE_HEURISTICS = {
	veteran_stealth_combat_ability = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_veteran_stealth(context)
	end,
	zealot_dash = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_dash(context)
	end,
	-- Runtime normally resolves these to template `zealot_dash`, but we keep aliases
	-- for safety and debug clarity.
	zealot_targeted_dash = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_dash(context)
	end,
	zealot_targeted_dash_improved = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_dash(context)
	end,
	zealot_targeted_dash_improved_double = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_dash(context)
	end,
	zealot_invisibility = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_invisibility(context)
	end,
	psyker_shout = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_psyker_shout(context)
	end,
	psyker_overcharge_stance = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_psyker_stance(context)
	end,
	ogryn_charge = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_ogryn_charge(context)
	end,
	-- Runtime normally resolves these to template `ogryn_charge`.
	ogryn_charge_increased_distance = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_ogryn_charge(context)
	end,
	ogryn_taunt_shout = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_ogryn_taunt(context)
	end,
	ogryn_gunlugger_stance = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_ogryn_gunlugger(context)
	end,
	adamant_stance = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_adamant_stance(context)
	end,
	adamant_charge = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_adamant_charge(context)
	end,
	adamant_shout = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_adamant_shout(context)
	end,
	broker_focus = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_broker_focus(context)
	end,
	broker_punk_rage = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_broker_rage(context)
	end,
}

local function _evaluate_template_heuristic(
	ability_template_name,
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension,
	context
)
	if ability_template_name == "veteran_combat_ability" then
		return _can_activate_veteran_combat_ability(
			conditions,
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running,
			ability_extension,
			context
		)
	end

	local fn = TEMPLATE_HEURISTICS[ability_template_name]
	if not fn then
		return nil, "fallback_unhandled_template"
	end

	return fn(
		conditions,
		unit,
		blackboard,
		scratchpad,
		condition_args,
		action_data,
		is_running,
		ability_extension,
		context
	)
end

local function _fmt_percent(value)
	if value == nil then
		return "n/a"
	end

	return string.format("%.2f", value)
end

local function _fmt_seconds(value)
	if value == nil then
		return "n/a"
	end

	if value == math.huge then
		return "inf"
	end

	return string.format("%.2f", value)
end

local function _sanitize_dump_name_fragment(value)
	local fragment = tostring(value or "unknown")
	fragment = string.gsub(fragment, "[^%w_%-]", "_")

	return fragment
end

local function _enemy_unit_label(enemy_unit)
	if not enemy_unit then
		return "none"
	end

	local breed = _enemy_breed(enemy_unit)

	return (breed and breed.name) or tostring(enemy_unit)
end

local function _context_snapshot(context)
	if not context then
		return nil
	end

	return {
		num_nearby = context.num_nearby,
		challenge_rating_sum = context.challenge_rating_sum,
		elite_count = context.elite_count,
		special_count = context.special_count,
		monster_count = context.monster_count,
		ranged_count = context.ranged_count,
		melee_count = context.melee_count,
		health_pct = context.health_pct,
		toughness_pct = context.toughness_pct,
		peril_pct = context.peril_pct,
		target_enemy_distance = context.target_enemy_distance,
		target_enemy_type = context.target_enemy_type,
		target_enemy = _enemy_unit_label(context.target_enemy),
		priority_target_enemy = _enemy_unit_label(context.priority_target_enemy),
		opportunity_target_enemy = _enemy_unit_label(context.opportunity_target_enemy),
		urgent_target_enemy = _enemy_unit_label(context.urgent_target_enemy),
		target_ally_needs_aid = context.target_ally_needs_aid,
		target_ally_distance = context.target_ally_distance,
		target_is_elite_special = context.target_is_elite_special,
		target_is_monster = context.target_is_monster,
		target_is_super_armor = context.target_is_super_armor,
	}
end

local function _fallback_state_snapshot(state, fixed_t)
	if not state then
		return {
			active = false,
			item_stage = "none",
		}
	end

	local snapshot = {
		active = state.active == true,
		hold_until = state.hold_until,
		hold_remaining_s = state.hold_until and math.max(state.hold_until - fixed_t, 0) or nil,
		wait_action_input = state.wait_action_input,
		wait_sent = state.wait_sent == true,
		next_try_t = state.next_try_t,
		next_try_in_s = state.next_try_t and (state.next_try_t - fixed_t) or nil,
		item_stage = state.item_stage or "none",
		item_profile_name = state.item_profile_name,
		item_wait_t = state.item_wait_t,
		item_wait_in_s = state.item_wait_t and (state.item_wait_t - fixed_t) or nil,
		item_charge_confirmed = state.item_charge_confirmed == true,
		item_start_input = state.item_start_input,
		item_followup_input = state.item_followup_input,
		item_unwield_input = state.item_unwield_input,
	}

	return snapshot
end

local function _dump_fallback_queue_context_once(kind, ability_name, payload)
	if not _debug_enabled() then
		return
	end

	local key = tostring(kind) .. ":" .. tostring(ability_name)
	if _fallback_queue_dumped_by_key[key] then
		return
	end

	_fallback_queue_dumped_by_key[key] = true

	mod:echo("BetterBots DEBUG: one-shot context dump for " .. key)
	mod:dump(payload, "betterbots_" .. _sanitize_dump_name_fragment(key), 3)
end

local function _player_debug_label(player)
	local name = type(player.name) == "function" and player:name() or "unknown"
	local slot = type(player.slot) == "function" and player:slot() or "?"
	local archetype = type(player.archetype_name) == "function" and player:archetype_name() or "?"

	return tostring(name) .. " [slot=" .. tostring(slot) .. ", archetype=" .. tostring(archetype) .. "]"
end

local function _collect_alive_bots()
	local manager_table = rawget(_G, "Managers")
	local alive_lookup = rawget(_G, "ALIVE")
	local player_manager = manager_table and manager_table.player
	if not player_manager then
		return nil, "Managers.player unavailable"
	end

	local players = player_manager:players()
	local bots = {}
	if not players then
		return bots
	end

	for _, player in pairs(players) do
		if player and not player:is_human_controlled() then
			local unit = player.player_unit
			if unit and alive_lookup and alive_lookup[unit] then
				bots[#bots + 1] = {
					player = player,
					unit = unit,
				}
			end
		end
	end

	table.sort(bots, function(a, b)
		local a_slot = type(a.player.slot) == "function" and a.player:slot() or math.huge
		local b_slot = type(b.player.slot) == "function" and b.player:slot() or math.huge
		return a_slot < b_slot
	end)

	return bots
end

local function _bot_blackboard(unit)
	local behavior_extension = ScriptUnit.has_extension(unit, "behavior_system")
	local brain = behavior_extension and behavior_extension._brain

	return brain and brain._blackboard or nil
end

local function _log_ability_decision(ability_template_name, fixed_t, can_activate, rule, context)
	_debug_log(
		"decision:" .. ability_template_name,
		fixed_t,
		"decision "
			.. ability_template_name
			.. " -> "
			.. tostring(can_activate)
			.. " (rule="
			.. tostring(rule)
			.. ", nearby="
			.. tostring(context.num_nearby)
			.. ", challenge="
			.. string.format("%.2f", context.challenge_rating_sum or 0)
			.. ", hp="
			.. _fmt_percent(context.health_pct)
			.. ", tough="
			.. _fmt_percent(context.toughness_pct)
			.. ", peril="
			.. _fmt_percent(context.peril_pct)
			.. ", target_dist="
			.. _fmt_percent(context.target_enemy_distance)
			.. ")"
	)
end

local function _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	local ability_component_name = action_data.ability_component_name

	if ability_component_name == scratchpad.ability_component_name then
		return true
	end

	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component.template_name
	local fixed_t = _fixed_time()

	if ability_template_name == "none" then
		_debug_log(
			"none:" .. ability_component_name,
			fixed_t,
			"blocked " .. ability_component_name .. " (template_name=none)"
		)
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_inject_missing_ability_meta_data(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		_debug_log(
			"missing_template:" .. ability_template_name,
			fixed_t,
			"blocked missing template " .. ability_template_name
		)
		return false
	end

	local ability_meta_data = ability_template.ability_meta_data
	if not ability_meta_data then
		_debug_log(
			"missing_meta:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (no ability_meta_data)"
		)
		return false
	end

	local activation_data = ability_meta_data.activation
	if not activation_data then
		_debug_log(
			"missing_activation:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (no activation data)"
		)
		return false
	end

	local action_input = activation_data.action_input
	if not action_input then
		_debug_log(
			"missing_action_input:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (activation.action_input missing)"
		)
		return false
	end

	local used_input = activation_data.used_input
	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local action_input_is_valid =
		ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)

	if not action_input_is_valid then
		_debug_log(
			"invalid_input:" .. ability_template_name .. ":" .. action_input,
			fixed_t,
			"blocked " .. ability_template_name .. " (invalid action_input=" .. tostring(action_input) .. ")"
		)
		return false
	end

	_debug_log(
		"bt_gate:" .. ability_template_name,
		fixed_t,
		"bt gate evaluated " .. ability_template_name .. " (component=" .. tostring(ability_component_name) .. ")",
		0.75
	)

	if ability_template_name == "zealot_relic" then
		local can_activate =
			conditions._can_activate_zealot_relic(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		_log_ability_decision(
			ability_template_name,
			fixed_t,
			can_activate,
			"zealot_relic_vanilla",
			_build_ability_decision_context(unit, blackboard)
		)
		return can_activate
	end

	local context = _build_ability_decision_context(unit, blackboard)
	local can_activate, rule = _evaluate_template_heuristic(
		ability_template_name,
		conditions,
		unit,
		blackboard,
		scratchpad,
		condition_args,
		action_data,
		is_running,
		ability_extension,
		context
	)

	if can_activate == nil then
		if ability_template_name == "veteran_combat_ability" then
			can_activate = conditions._can_activate_veteran_ranger_ability(
				unit,
				blackboard,
				scratchpad,
				condition_args,
				action_data,
				is_running
			)
			rule = rule and (tostring(rule) .. "->fallback_veteran_vanilla") or "fallback_veteran_vanilla"
		else
			can_activate = context.num_nearby > 0
			rule = rule or "fallback_nearby"
		end
	end

	_log_ability_decision(ability_template_name, fixed_t, can_activate, rule, context)

	return can_activate
end

local function _equipped_combat_ability(unit)
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	local equipped_abilities = ability_extension and ability_extension._equipped_abilities
	local combat_ability = equipped_abilities and equipped_abilities.combat_ability

	return ability_extension, combat_ability
end

local function _equipped_combat_ability_name(unit)
	local _, combat_ability = _equipped_combat_ability(unit)

	return combat_ability and combat_ability.name or "unknown"
end

local function _reset_item_sequence_state(state, next_try_t)
	state.item_stage = nil
	state.item_ability_name = nil
	state.item_wield_deadline_t = nil
	state.item_stage_deadline_t = nil
	state.item_attempt_t = nil
	state.item_charge_confirmed = nil
	state.item_profile_name = nil
	state.item_profile_key = nil
	state.item_profile_count = nil
	state.item_start_input = nil
	state.item_wait_t = nil
	state.item_followup_input = nil
	state.item_followup_delay = nil
	state.item_unwield_input = nil
	state.item_unwield_delay = nil
	state.item_charge_confirm_timeout = nil

	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local ITEM_SEQUENCE_PROFILES = {
	channel = {
		required_inputs = { "channel", "wield_previous" },
		start_input = "channel",
		start_delay_after_wield = 0,
		unwield_input = nil,
		unwield_delay = 5.6,
		charge_confirm_timeout = 1.5,
	},
	press_release = {
		required_inputs = { "ability_pressed", "ability_released", "unwield_to_previous" },
		start_input = "ability_pressed",
		start_delay_after_wield = 0,
		followup_input = "ability_released",
		followup_delay = 0.08,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.35,
	},
	force_field_regular = {
		required_inputs = { "aim_force_field", "place_force_field", "unwield_to_previous" },
		start_input = "aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "place_force_field",
		followup_delay = 0.12,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.9,
		charge_confirm_timeout = 2.2,
	},
	force_field_instant = {
		required_inputs = { "instant_aim_force_field", "instant_place_force_field", "unwield_to_previous" },
		start_input = "instant_aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "instant_place_force_field",
		followup_delay = 0.12,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.8,
		charge_confirm_timeout = 2.0,
	},
	drone_regular = {
		required_inputs = { "aim_drone", "release_drone", "unwield_to_previous" },
		start_input = "aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "release_drone",
		followup_delay = 0.24,
		unwield_input = "unwield_to_previous",
		unwield_delay = 1.0,
		charge_confirm_timeout = 2.2,
	},
	drone_instant = {
		required_inputs = { "instant_aim_drone", "instant_release_drone", "unwield_to_previous" },
		start_input = "instant_aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "instant_release_drone",
		followup_delay = 0.1,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.9,
		charge_confirm_timeout = 2.0,
	},
}

local ITEM_DEFAULT_PROFILE_ORDER = {
	"channel",
	"press_release",
	"force_field_regular",
	"force_field_instant",
	"drone_regular",
	"drone_instant",
}

local ITEM_PROFILE_ORDER_BY_ABILITY = {
	zealot_relic = { "channel" },
	psyker_force_field = { "force_field_regular", "force_field_instant" },
	psyker_force_field_improved = { "force_field_regular", "force_field_instant" },
	psyker_force_field_dome = { "force_field_regular", "force_field_instant" },
	adamant_area_buff_drone = { "drone_regular", "drone_instant" },
	broker_ability_stimm_field = { "press_release" },
}

local function _ordered_item_profile_ids(ability_name)
	local ordered_ids = {}
	local seen = {}
	local preferred_ids = ITEM_PROFILE_ORDER_BY_ABILITY[ability_name]

	if preferred_ids then
		for i = 1, #preferred_ids do
			local profile_name = preferred_ids[i]

			if not seen[profile_name] then
				ordered_ids[#ordered_ids + 1] = profile_name
				seen[profile_name] = true
			end
		end
	end

	for i = 1, #ITEM_DEFAULT_PROFILE_ORDER do
		local profile_name = ITEM_DEFAULT_PROFILE_ORDER[i]

		if not seen[profile_name] then
			ordered_ids[#ordered_ids + 1] = profile_name
		end
	end

	return ordered_ids
end

local function _action_inputs_include_all(action_inputs, required_inputs)
	if not action_inputs then
		return false
	end

	for i = 1, #required_inputs do
		if action_inputs[required_inputs[i]] == nil then
			return false
		end
	end

	return true
end

local function _item_cast_sequences_for_weapon(ability_name, weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs
	if not action_inputs then
		return {}
	end

	local ordered_ids = _ordered_item_profile_ids(ability_name)
	local sequence_candidates = {}

	for i = 1, #ordered_ids do
		local profile_name = ordered_ids[i]
		local profile = ITEM_SEQUENCE_PROFILES[profile_name]

		if profile and _action_inputs_include_all(action_inputs, profile.required_inputs) then
			sequence_candidates[#sequence_candidates + 1] = {
				profile_name = profile_name,
				start_input = profile.start_input,
				start_delay_after_wield = profile.start_delay_after_wield,
				followup_input = profile.followup_input,
				followup_delay = profile.followup_delay,
				unwield_input = profile.unwield_input,
				unwield_delay = profile.unwield_delay,
				charge_confirm_timeout = profile.charge_confirm_timeout,
			}
		end
	end

	return sequence_candidates
end

local function _select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
	local sequence_candidates = _item_cast_sequences_for_weapon(ability_name, weapon_template)

	if #sequence_candidates == 0 then
		return nil
	end

	if not state.item_profile_index_by_key then
		state.item_profile_index_by_key = {}
	end

	local profile_key = ability_name .. ":" .. tostring(weapon_template_name)
	local selected_index = state.item_profile_index_by_key[profile_key] or 1
	local candidate_count = #sequence_candidates

	if selected_index > candidate_count then
		selected_index = 1
	end

	state.item_profile_index_by_key[profile_key] = selected_index

	return sequence_candidates[selected_index], profile_key, selected_index, candidate_count
end

local function _rotate_item_cast_profile(state)
	local profile_key = state.item_profile_key
	local profile_count = state.item_profile_count or 0
	local index_by_key = state.item_profile_index_by_key

	if not profile_key or not index_by_key or profile_count <= 1 then
		return false
	end

	local current_index = index_by_key[profile_key] or 1
	local next_index = current_index + 1
	if next_index > profile_count then
		next_index = 1
	end

	index_by_key[profile_key] = next_index
	return next_index ~= current_index
end

local function _schedule_item_sequence_retry(state, fixed_t, rotate_profile)
	if rotate_profile then
		_rotate_item_cast_profile(state)
	end

	_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
end

local function _schedule_ability_retry_for_unit(unit, fixed_t, retry_delay_s)
	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	local retry_t = fixed_t + (retry_delay_s or ITEM_SEQUENCE_RETRY_S)
	local next_try_t = state.next_try_t
	if not next_try_t or retry_t < next_try_t then
		state.next_try_t = retry_t
	end
end

local function _should_lock_weapon_switch_for_item_ability(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	if not inventory_component or inventory_component.wielded_slot ~= "slot_combat_ability" then
		return false
	end

	local ability_name = _equipped_combat_ability_name(unit)
	local combat_ability_component = unit_data_extension:read_component("combat_ability")
	local combat_ability_active = combat_ability_component and combat_ability_component.active == true

	if combat_ability_active and LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY[ability_name] then
		return true, ability_name, "active"
	end

	local state = _fallback_state_by_unit[unit]
	local staged_ability_name = state and state.item_ability_name
	if
		state
		and state.item_stage
		and staged_ability_name
		and LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE[staged_ability_name]
	then
		return true, staged_ability_name, "sequence"
	end

	return false
end

local function _item_attempt_charge_confirmed(unit, state, ability_name)
	local attempt_t = state.item_attempt_t
	if not attempt_t then
		return false
	end

	local charge_event = _last_charge_event_by_unit[unit]
	if not charge_event then
		return false
	end

	if charge_event.fixed_t < attempt_t then
		return false
	end

	return charge_event.ability_name == ability_name
end

local function _queue_weapon_action_input(state, input_name)
	local action_input_extension = state.action_input_extension
	if not action_input_extension then
		return
	end

	action_input_extension:bot_queue_action_input("weapon_action", input_name, nil)
end

local function _queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)
	_queue_weapon_action_input(state, state.item_start_input)
	_debug_log(
		"fallback_item_start:" .. ability_name,
		fixed_t,
		"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_start_input)
	)

	state.item_attempt_t = fixed_t
	state.item_charge_confirmed = false

	if state.item_followup_input then
		state.item_stage = "waiting_followup"
		state.item_wait_t = fixed_t + (state.item_followup_delay or 0.2)
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
	else
		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + state.item_unwield_delay
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
	end

	local context = _build_ability_decision_context(unit, blackboard)
	_dump_fallback_queue_context_once("item", ability_name, {
		fixed_t = fixed_t,
		ability_name = ability_name,
		item_profile_name = state.item_profile_name,
		item_start_input = state.item_start_input,
		item_followup_input = state.item_followup_input,
		item_unwield_input = state.item_unwield_input,
		context = _context_snapshot(context),
		fallback_state = _fallback_state_snapshot(state, fixed_t),
	})
end

local function _transition_to_charge_confirmation(state, fixed_t)
	state.item_stage = "waiting_charge_confirmation"
	state.item_wait_t = fixed_t + (state.item_charge_confirm_timeout or ITEM_CHARGE_CONFIRM_TIMEOUT_S)
	state.item_stage_deadline_t = state.item_wait_t
end

local function _current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, action_input)
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"

	if not action_input then
		return true, weapon_template_name
	end

	local weapon_template = rawget(WeaponTemplates, weapon_template_name)
	local supports_input = weapon_template
		and weapon_template.action_inputs
		and weapon_template.action_inputs[action_input] ~= nil

	return supports_input and true or false, weapon_template_name
end

local function _can_use_item_fallback(unit, ability_extension, ability_name)
	if not ability_extension:can_use_ability("combat_ability") then
		return false
	end

	local perception_extension = ScriptUnit.extension(unit, "perception_system")
	local _, num_nearby = perception_extension:enemies_in_proximity()
	if num_nearby <= 0 then
		return false
	end

	if ability_name == "zealot_relic" then
		local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
		local can_activate = conditions
			and conditions._can_activate_zealot_relic
			and conditions._can_activate_zealot_relic(unit)

		if not can_activate then
			return false
		end
	end

	return true
end

local function _fallback_try_queue_item_combat_ability(
	unit,
	unit_data_extension,
	ability_extension,
	state,
	fixed_t,
	combat_ability,
	blackboard
)
	local ability_name = combat_ability and combat_ability.name or "unknown"
	local has_item_flow = combat_ability and not combat_ability.ability_template and combat_ability.inventory_item_name
	if not has_item_flow then
		_reset_item_sequence_state(state)
		return
	end

	if state.item_ability_name and state.item_ability_name ~= ability_name then
		_reset_item_sequence_state(state, fixed_t + 0.5)
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	if not _can_use_item_fallback(unit, ability_extension, ability_name) then
		return
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
	local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")
	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")

	state.action_input_extension = action_input_extension
	state.item_ability_name = ability_name

	if not state.item_charge_confirmed and _item_attempt_charge_confirmed(unit, state, ability_name) then
		state.item_charge_confirmed = true
		_debug_log(
			"fallback_item_charge_confirmed:" .. ability_name,
			fixed_t,
			"fallback item confirmed charge consume for "
				.. ability_name
				.. " (profile="
				.. tostring(state.item_profile_name)
				.. ")"
		)
	end

	if state.item_stage == "waiting_wield" then
		if wielded_slot ~= "slot_combat_ability" then
			if fixed_t >= (state.item_wield_deadline_t or 0) then
				_debug_log(
					"fallback_item_wield_timeout:" .. ability_name,
					fixed_t,
					"fallback item blocked " .. ability_name .. " (wield timeout)"
				)
				_schedule_item_sequence_retry(state, fixed_t, false)
			end

			return
		end

		if not state.item_start_input then
			local weapon_template = rawget(WeaponTemplates, weapon_template_name)
			local sequence, profile_key, selected_index, candidate_count =
				_select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
			if not sequence then
				_debug_log(
					"fallback_item_unsupported:" .. ability_name .. ":" .. weapon_template_name,
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (unsupported weapon template="
						.. tostring(weapon_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, false)
				return
			end

			state.item_profile_name = sequence.profile_name
			state.item_profile_key = profile_key
			state.item_profile_count = candidate_count
			state.item_start_input = sequence.start_input
			state.item_followup_input = sequence.followup_input
			state.item_followup_delay = sequence.followup_delay
			state.item_unwield_input = sequence.unwield_input
			state.item_unwield_delay = sequence.unwield_delay or 0.3
			state.item_charge_confirm_timeout = sequence.charge_confirm_timeout or ITEM_CHARGE_CONFIRM_TIMEOUT_S
			state.item_stage = "waiting_start"
			state.item_wait_t = fixed_t + (sequence.start_delay_after_wield or ITEM_DEFAULT_START_DELAY_S)
			state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S

			_debug_log(
				"fallback_item_profile:" .. ability_name .. ":" .. weapon_template_name,
				fixed_t,
				"fallback item selected profile "
					.. tostring(state.item_profile_name)
					.. " ("
					.. tostring(selected_index)
					.. "/"
					.. tostring(candidate_count)
					.. ") for "
					.. ability_name
			)
		end

		if fixed_t >= (state.item_wait_t or 0) then
			_queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)
		end

		return
	end

	if state.item_stage == "waiting_start" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_start_lost_wield:" .. ability_name,
				fixed_t,
				"fallback item blocked "
					.. ability_name
					.. " (lost combat-ability wield before start; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_start_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_start_input)

		if not supports_start_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_start_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_start_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (start input drift; input="
						.. tostring(state.item_start_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		_queue_item_start_input(unit, ability_name, state, fixed_t, blackboard)

		return
	end

	if state.item_stage == "waiting_followup" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_followup_lost_wield:" .. ability_name,
				fixed_t,
				"fallback item blocked "
					.. ability_name
					.. " (lost combat-ability wield before followup; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_followup_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_followup_input)

		if not supports_followup_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_followup_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_followup_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (followup input drift; input="
						.. tostring(state.item_followup_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_followup_input then
			_queue_weapon_action_input(state, state.item_followup_input)
			_debug_log(
				"fallback_item_followup:" .. ability_name,
				fixed_t,
				"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_followup_input)
			)
		end

		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + (state.item_unwield_delay or 0.3)
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
		return
	end

	if state.item_stage == "waiting_unwield" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_unwield_lost_slot:" .. ability_name,
				fixed_t,
				"fallback item continuing charge confirmation for "
					.. ability_name
					.. " (lost combat-ability wield during unwield stage; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_transition_to_charge_confirmation(state, fixed_t)
			return
		end

		local supports_unwield_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_unwield_input)

		if not supports_unwield_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_unwield_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_unwield_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (unwield input drift; input="
						.. tostring(state.item_unwield_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_unwield_input then
			_queue_weapon_action_input(state, state.item_unwield_input)
			_debug_log(
				"fallback_item_unwield:" .. ability_name,
				fixed_t,
				"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_unwield_input)
			)
		end

		_transition_to_charge_confirmation(state, fixed_t)
		return
	end

	if state.item_stage == "waiting_charge_confirmation" then
		if state.item_charge_confirmed then
			_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		local rotated = _rotate_item_cast_profile(state)
		_debug_log(
			"fallback_item_no_charge:" .. ability_name,
			fixed_t,
			"fallback item finished without charge consume for "
				.. ability_name
				.. " (profile="
				.. tostring(state.item_profile_name)
				.. ", rotated="
				.. tostring(rotated)
				.. ")"
		)
		_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
		return
	end

	if wielded_slot == "slot_combat_ability" then
		state.item_stage = "waiting_wield"
		state.item_wield_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
		return
	end

	local current_weapon_template = rawget(WeaponTemplates, weapon_template_name)
	if
		not (
			current_weapon_template
			and current_weapon_template.action_inputs
			and current_weapon_template.action_inputs.combat_ability
		)
	then
		_debug_log(
			"fallback_item_no_wield_input:" .. ability_name .. ":" .. weapon_template_name,
			fixed_t,
			"fallback item blocked "
				.. ability_name
				.. " (weapon template lacks combat_ability input: "
				.. tostring(weapon_template_name)
				.. ")"
		)
		state.next_try_t = fixed_t + ITEM_SEQUENCE_RETRY_S
		return
	end

	_queue_weapon_action_input(state, "combat_ability")
	state.item_stage = "waiting_wield"
	state.item_wield_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S

	_debug_log(
		"fallback_item_wield:" .. ability_name,
		fixed_t,
		"fallback item queued " .. ability_name .. " input=combat_ability (wield slot_combat_ability)"
	)
end

local function _fallback_try_queue_combat_ability(unit, blackboard)
	local ability_component_name = "combat_ability_action"
	local fixed_t = _fixed_time()
	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component and ability_component.template_name
	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end

	if not ability_template_name or ability_template_name == "none" then
		_debug_log(
			"fallback_none:" .. tostring(unit),
			fixed_t,
			"fallback skipped "
				.. ability_component_name
				.. " (template_name=none, equipped="
				.. _equipped_combat_ability_name(unit)
				.. ")",
			DEBUG_SKIP_RELIC_LOG_INTERVAL_S
		)

		local ability_extension, combat_ability = _equipped_combat_ability(unit)
		if ability_extension then
			_fallback_try_queue_item_combat_ability(
				unit,
				unit_data_extension,
				ability_extension,
				state,
				fixed_t,
				combat_ability,
				blackboard
			)
		end

		return
	end

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_inject_missing_ability_meta_data(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		_debug_log(
			"fallback_missing_template:" .. ability_template_name,
			fixed_t,
			"fallback blocked missing template " .. ability_template_name
		)
		return
	end

	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data then
		_debug_log(
			"fallback_missing_meta:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (no ability_meta_data)"
		)
		return
	end

	local activation_data = ability_meta_data and ability_meta_data.activation
	if not activation_data then
		_debug_log(
			"fallback_missing_activation:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (no activation data)"
		)
		return
	end

	local action_input = activation_data and activation_data.action_input
	if not action_input then
		_debug_log(
			"fallback_missing_action_input:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (activation.action_input missing)"
		)
		return
	end

	if state.active then
		if fixed_t >= state.hold_until then
			if state.wait_action_input and not state.wait_sent then
				local action_input_extension = state.action_input_extension
					or ScriptUnit.extension(unit, "action_input_system")
				action_input_extension:bot_queue_action_input(ability_component_name, state.wait_action_input, nil)
				state.wait_sent = true
			end

			state.active = nil
			state.hold_until = nil
			state.wait_action_input = nil
			state.wait_sent = nil
			state.next_try_t = fixed_t + 1.5
		end

		return
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local used_input = activation_data.used_input
	local action_input_is_valid =
		ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)

	if not action_input_is_valid then
		_debug_log(
			"fallback_invalid_input:" .. ability_template_name .. ":" .. action_input,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (invalid action_input=" .. tostring(action_input) .. ")"
		)
		return
	end

	local context = _build_ability_decision_context(unit, blackboard)
	local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
	local can_activate, rule = _evaluate_template_heuristic(
		ability_template_name,
		conditions,
		unit,
		blackboard,
		nil,
		nil,
		nil,
		false,
		ability_extension,
		context
	)

	if can_activate == nil then
		if ability_template_name == "veteran_combat_ability" then
			can_activate = conditions._can_activate_veteran_ranger_ability(unit, blackboard, nil, nil, nil, false)
			rule = rule and (tostring(rule) .. "->fallback_veteran_vanilla") or "fallback_veteran_vanilla"
		else
			can_activate = context.num_nearby > 0
			rule = rule or "fallback_nearby"
		end
	end

	if not can_activate then
		_debug_log(
			"fallback_decision_block:" .. ability_template_name,
			fixed_t,
			"fallback held "
				.. ability_template_name
				.. " (rule="
				.. tostring(rule)
				.. ", nearby="
				.. tostring(context.num_nearby)
				.. ")"
		)
		return
	end

	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)

	state.action_input_extension = action_input_extension
	state.active = true
	state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
	state.wait_action_input = ability_meta_data.wait_action and ability_meta_data.wait_action.action_input or nil
	state.wait_sent = false

	_debug_log(
		"fallback_queue:" .. tostring(unit),
		fixed_t,
		"fallback queued "
			.. ability_template_name
			.. " input="
			.. tostring(action_input)
			.. " (rule="
			.. tostring(rule)
			.. ", nearby="
			.. tostring(context.num_nearby)
			.. ")"
	)

	_dump_fallback_queue_context_once("template", ability_template_name, {
		fixed_t = fixed_t,
		ability_template_name = ability_template_name,
		ability_name = _equipped_combat_ability_name(unit),
		activation_input = action_input,
		rule = rule,
		context = _context_snapshot(context),
		fallback_state = _fallback_state_snapshot(state, fixed_t),
	})
end

local function _resolve_current_heuristic_decision(unit, blackboard)
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not ability_extension or not unit_data_extension then
		return nil, "missing_extensions", "none", "unknown", nil
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name or "none"
	local ability_name = _equipped_combat_ability_name(unit)
	local context = _build_ability_decision_context(unit, blackboard)

	if ability_template_name == "none" then
		local can_activate = _can_use_item_fallback(unit, ability_extension, ability_name)
		local rule = can_activate and "item_fallback_ready" or "item_fallback_blocked"

		return can_activate, rule, ability_template_name, ability_name, context
	end

	local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
	local can_activate, rule = _evaluate_template_heuristic(
		ability_template_name,
		conditions,
		unit,
		blackboard,
		nil,
		nil,
		nil,
		false,
		ability_extension,
		context
	)

	if can_activate == nil then
		if ability_template_name == "veteran_combat_ability" then
			can_activate = conditions._can_activate_veteran_ranger_ability(unit, blackboard, nil, nil, nil, false)
			rule = rule and (tostring(rule) .. "->fallback_veteran_vanilla") or "fallback_veteran_vanilla"
		else
			can_activate = context.num_nearby > 0
			rule = rule or "fallback_nearby"
		end
	end

	return can_activate, rule, ability_template_name, ability_name, context
end

local function _install_condition_patch(conditions, patched_set, patch_label)
	if not conditions or patched_set[conditions] then
		return
	end

	conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	end
	patched_set[conditions] = true

	_debug_log(
		"condition_patch:" .. patch_label .. ":" .. tostring(conditions),
		0,
		"patched " .. patch_label .. ".can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
	)
end

mod:hook_require("scripts/settings/ability/ability_templates/ability_templates", function(AbilityTemplates)
	_inject_missing_ability_meta_data(AbilityTemplates)
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions", function(conditions)
	_install_condition_patch(conditions, _patched_bt_bot_conditions, "bt_bot_conditions")
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/bt_conditions", function(conditions)
	_install_condition_patch(conditions, _patched_bt_conditions, "bt_conditions")
end)

local function _try_patch_conditions_now(module_path, patched_set, patch_label)
	local ok, conditions_or_err = pcall(require, module_path)
	if not ok then
		_debug_log(
			"condition_patch_require_failed:" .. patch_label,
			0,
			"require failed for " .. patch_label .. " (" .. tostring(conditions_or_err) .. ")",
			DEBUG_SKIP_RELIC_LOG_INTERVAL_S
		)
		return
	end

	_install_condition_patch(conditions_or_err, patched_set, patch_label)
end

_try_patch_conditions_now(
	"scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions",
	_patched_bt_bot_conditions,
	"bt_bot_conditions"
)
_try_patch_conditions_now(
	"scripts/extension_systems/behavior/utilities/bt_conditions",
	_patched_bt_conditions,
	"bt_conditions"
)

mod:hook_require(
	"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
	function(BtBotActivateAbilityAction)
		mod:hook_safe(
			BtBotActivateAbilityAction,
			"enter",
			function(_self, _unit, _breed, _blackboard, scratchpad, action_data, _t)
				if not _debug_enabled() then
					return
				end

				local ability_component_name = action_data and action_data.ability_component_name or "?"
				local activation_data = scratchpad and scratchpad.activation_data
				local action_input = activation_data and activation_data.action_input or "?"
				local fixed_t = _fixed_time()

				_debug_log(
					"enter:" .. tostring(ability_component_name) .. ":" .. tostring(action_input),
					fixed_t,
					"enter ability node component="
						.. tostring(ability_component_name)
						.. " action_input="
						.. tostring(action_input)
				)
			end
		)
	end
)

mod:hook_require("scripts/extension_systems/ability/player_unit_ability_extension", function(PlayerUnitAbilityExtension)
	mod:hook_safe(PlayerUnitAbilityExtension, "use_ability_charge", function(self, ability_type, optional_num_charges)
		if ability_type ~= "combat_ability" then
			return
		end

		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		local ability_name = "unknown"
		local equipped_abilities = self._equipped_abilities
		local combat_ability = equipped_abilities and equipped_abilities.combat_ability
		if combat_ability and combat_ability.name then
			ability_name = combat_ability.name
		end

		local fixed_t = _fixed_time()
		local unit = self._unit
		if unit then
			_last_charge_event_by_unit[unit] = {
				ability_name = ability_name,
				fixed_t = fixed_t,
			}
		end

		if not _debug_enabled() then
			return
		end

		_debug_log(
			"charge:" .. ability_name,
			fixed_t,
			"charge consumed for " .. ability_name .. " (charges=" .. tostring(optional_num_charges or 1) .. ")"
		)
	end)
end)

mod:hook_require(
	"scripts/extension_systems/ability/actions/action_character_state_change",
	function(ActionCharacterStateChange)
		mod:hook(ActionCharacterStateChange, "finish", function(func, self, reason, data, t, time_in_action)
			local action_settings = self._action_settings
			local ability_type = action_settings and action_settings.ability_type
			local use_ability_charge = action_settings and action_settings.use_ability_charge
			local player = self._player
			local unit = self._player_unit
			local wanted_state_name = self._wanted_state_name
			local character_state_component = self._character_sate_component
			local current_state_name = character_state_component and character_state_component.state_name or nil
			local failed_state_transition = wanted_state_name ~= nil and current_state_name ~= wanted_state_name
			local is_bot = player and not player:is_human_controlled()

			func(self, reason, data, t, time_in_action)

			if
				not is_bot
				or not unit
				or ability_type ~= "combat_ability"
				or not use_ability_charge
				or not failed_state_transition
			then
				return
			end

			local fixed_t = _fixed_time()
			local ability_name = _equipped_combat_ability_name(unit)
			_schedule_ability_retry_for_unit(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
			_debug_log(
				"state_fail_retry:" .. tostring(ability_name) .. ":" .. tostring(reason),
				fixed_t,
				"combat ability state transition failed for "
					.. tostring(ability_name)
					.. " (wanted="
					.. tostring(wanted_state_name)
					.. ", current="
					.. tostring(current_state_name)
					.. ", reason="
					.. tostring(reason)
					.. "); scheduled fast retry"
			)
		end)
	end
)

mod:hook_require(
	"scripts/extension_systems/action_input/player_unit_action_input_extension",
	function(PlayerUnitActionInputExtension)
		mod:hook_safe(PlayerUnitActionInputExtension, "extensions_ready", function(self, _world, unit)
			self._betterbots_player_unit = unit
		end)

		mod:hook(
			PlayerUnitActionInputExtension,
			"bot_queue_action_input",
			function(func, self, id, action_input, raw_input)
				local unit = self._betterbots_player_unit
				if unit and id == "weapon_action" and action_input == "wield" then
					local should_lock, ability_name, lock_reason = _should_lock_weapon_switch_for_item_ability(unit)
					if should_lock then
						local fixed_t = _fixed_time()
						_debug_log(
							"lock_wield:" .. tostring(ability_name),
							fixed_t,
							"blocked weapon switch while keeping "
								.. tostring(ability_name)
								.. " "
								.. tostring(lock_reason)
								.. " (raw_input="
								.. tostring(raw_input)
								.. ")"
						)
						return nil
					end
				end

				return func(self, id, action_input, raw_input)
			end
		)
	end
)

mod:hook_require("scripts/extension_systems/weapon/weapon_system", function(WeaponSystem)
	mod:hook(
		WeaponSystem,
		"queue_perils_of_the_warp_elite_kills_achievement",
		function(func, self, player, explosion_queue_index)
			local account_id = nil
			if player and type(player.account_id) == "function" then
				account_id = player:account_id()
			end

			if account_id == nil then
				_debug_log(
					"skip_perils_nil_account",
					_fixed_time(),
					"skipped perils achievement queue with nil account_id"
				)
				return nil
			end

			return func(self, player, explosion_queue_index)
		end
	)
end)

mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
	mod:hook_safe(BotBehaviorExtension, "update", function(self, unit)
		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		local brain = self._brain
		local blackboard = brain and brain._blackboard or nil
		_fallback_try_queue_combat_ability(unit, blackboard)
	end)
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		for key in pairs(_fallback_queue_dumped_by_key) do
			_fallback_queue_dumped_by_key[key] = nil
		end
		for unit in pairs(_decision_context_cache_by_unit) do
			_decision_context_cache_by_unit[unit] = nil
		end
		_debug_log("state:GameplayStateRun", _fixed_time(), "entered GameplayStateRun")
	end
end

mod:command("bb_state", "Dump BetterBots bot ability + fallback state", function()
	local bots, error_message = _collect_alive_bots()
	if error_message then
		mod:echo("BetterBots: /bb_state unavailable (" .. error_message .. ")")
		return
	end
	bots = bots or {}
	if #bots == 0 then
		mod:echo("BetterBots: /bb_state found no alive bots")
		return
	end

	local fixed_t = _fixed_time()
	mod:echo("BetterBots: /bb_state bots=" .. tostring(#bots) .. " fixed_t=" .. _fmt_seconds(fixed_t))

	for i, bot_entry in ipairs(bots) do
		local player = bot_entry.player
		local unit = bot_entry.unit
		local label = _player_debug_label(player)
		local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
		local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
		local ability_action_component = unit_data_extension
			and unit_data_extension:read_component("combat_ability_action")
		local combat_ability_component = unit_data_extension and unit_data_extension:read_component("combat_ability")
		local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
		local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action")
		local template_name = ability_action_component and ability_action_component.template_name or "none"
		local ability_name = _equipped_combat_ability_name(unit)
		local charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability") or nil
		local max_charges = ability_extension and ability_extension:max_ability_charges("combat_ability") or nil
		local cooldown = ability_extension and ability_extension:remaining_ability_cooldown("combat_ability") or nil
		local max_cooldown = ability_extension and ability_extension:max_ability_cooldown("combat_ability") or nil
		local can_use = ability_extension and ability_extension:can_use_ability("combat_ability") or false
		local fallback_state = _fallback_state_snapshot(_fallback_state_by_unit[unit], fixed_t)
		local last_charge = _last_charge_event_by_unit[unit]
		local last_charge_age_s = last_charge and (fixed_t - last_charge.fixed_t) or nil

		mod:echo(
			"BetterBots: ["
				.. tostring(i)
				.. "] "
				.. label
				.. " ability="
				.. tostring(ability_name)
				.. " template="
				.. tostring(template_name)
				.. " charges="
				.. tostring(charges)
				.. "/"
				.. tostring(max_charges)
				.. " cd="
				.. _fmt_seconds(cooldown)
				.. "/"
				.. _fmt_seconds(max_cooldown)
				.. " can_use="
				.. tostring(can_use)
				.. " active="
				.. tostring(combat_ability_component and combat_ability_component.active == true)
				.. " slot="
				.. tostring(inventory_component and inventory_component.wielded_slot or "none")
				.. " weapon_template="
				.. tostring(weapon_action_component and weapon_action_component.template_name or "none")
				.. " stage="
				.. tostring(fallback_state.item_stage)
				.. " next_try_in_s="
				.. _fmt_seconds(fallback_state.next_try_in_s)
				.. " last_charge_age_s="
				.. _fmt_seconds(last_charge_age_s)
		)
	end
end)

mod:command("bb_brain", "Dump BetterBots bot brain/blackboard snapshots", function()
	local bots, error_message = _collect_alive_bots()
	if error_message then
		mod:echo("BetterBots: /bb_brain unavailable (" .. error_message .. ")")
		return
	end
	bots = bots or {}
	if #bots == 0 then
		mod:echo("BetterBots: /bb_brain found no alive bots")
		return
	end

	local fixed_t = _fixed_time()
	for i, bot_entry in ipairs(bots) do
		local player = bot_entry.player
		local unit = bot_entry.unit
		local blackboard = _bot_blackboard(unit)
		local context = _build_ability_decision_context(unit, blackboard)
		local player_slot = type(player.slot) == "function" and player:slot() or "?"
		local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
		local ability_action_component = unit_data_extension
			and unit_data_extension:read_component("combat_ability_action")
		local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
		local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action")
		local ability_name = _equipped_combat_ability_name(unit)
		local perception = blackboard and blackboard.perception or nil
		local dump_name = "bb_brain_"
			.. tostring(i)
			.. "_"
			.. _sanitize_dump_name_fragment(ability_name)
			.. "_"
			.. _sanitize_dump_name_fragment(player_slot)
		local dump_payload = {
			fixed_t = fixed_t,
			bot = _player_debug_label(player),
			unit = tostring(unit),
			ability = {
				name = ability_name,
				template_name = ability_action_component and ability_action_component.template_name or "none",
				wielded_slot = inventory_component and inventory_component.wielded_slot or "none",
				weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none",
			},
			fallback_state = _fallback_state_snapshot(_fallback_state_by_unit[unit], fixed_t),
			context = _context_snapshot(context),
			perception = {
				target_enemy = _enemy_unit_label(perception and perception.target_enemy),
				target_enemy_distance = perception and perception.target_enemy_distance or nil,
				target_enemy_type = perception and perception.target_enemy_type or nil,
				priority_target_enemy = _enemy_unit_label(perception and perception.priority_target_enemy),
				opportunity_target_enemy = _enemy_unit_label(perception and perception.opportunity_target_enemy),
				urgent_target_enemy = _enemy_unit_label(perception and perception.urgent_target_enemy),
				target_ally_needs_aid = perception and perception.target_ally_needs_aid == true or false,
				target_ally_distance = perception and perception.target_ally_distance or nil,
			},
		}

		mod:echo("BetterBots: /bb_brain dump " .. tostring(i) .. " -> " .. dump_name)
		mod:dump(dump_payload, dump_name, 3)
	end
end)

mod:command("bb_decide", "Evaluate BetterBots heuristics without queuing input", function()
	local bots, error_message = _collect_alive_bots()
	if error_message then
		mod:echo("BetterBots: /bb_decide unavailable (" .. error_message .. ")")
		return
	end
	bots = bots or {}
	if #bots == 0 then
		mod:echo("BetterBots: /bb_decide found no alive bots")
		return
	end

	local fixed_t = _fixed_time()
	mod:echo("BetterBots: /bb_decide bots=" .. tostring(#bots) .. " fixed_t=" .. _fmt_seconds(fixed_t))

	for i, bot_entry in ipairs(bots) do
		local player = bot_entry.player
		local unit = bot_entry.unit
		local blackboard = _bot_blackboard(unit)
		local can_activate, rule, template_name, ability_name, context =
			_resolve_current_heuristic_decision(unit, blackboard)

		mod:echo(
			"BetterBots: ["
				.. tostring(i)
				.. "] "
				.. _player_debug_label(player)
				.. " ability="
				.. tostring(ability_name)
				.. " template="
				.. tostring(template_name)
				.. " decide="
				.. tostring(can_activate)
				.. " rule="
				.. tostring(rule)
				.. " nearby="
				.. tostring(context and context.num_nearby or "n/a")
				.. " tough="
				.. _fmt_percent(context and context.toughness_pct or nil)
				.. " peril="
				.. _fmt_percent(context and context.peril_pct or nil)
				.. " dist="
				.. _fmt_percent(context and context.target_enemy_distance or nil)
		)
	end
end)

mod:echo("BetterBots loaded")
if _debug_enabled() then
	mod:echo("BetterBots DEBUG: logging enabled (force=" .. tostring(DEBUG_FORCE_ENABLED) .. ")")
end
