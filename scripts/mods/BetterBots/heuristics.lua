local _fixed_time
local _decision_context_cache
local _super_armor_breed_cache
local _armor_type_super_armor

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
		local cached_value = _super_armor_breed_cache[breed_name]
		if cached_value ~= nil then
			return cached_value
		end
	end

	local has_super_armor = false
	if _armor_type_super_armor and breed.armor_type == _armor_type_super_armor then
		has_super_armor = true
	end

	local tags = breed.tags
	if not has_super_armor and tags and tags.super_armor == true then
		has_super_armor = true
	end

	local hit_zone_armor_override = breed.hit_zone_armor_override
	if not has_super_armor and hit_zone_armor_override and _armor_type_super_armor then
		for _, armor_type in pairs(hit_zone_armor_override) do
			if armor_type == _armor_type_super_armor then
				has_super_armor = true
				break
			end
		end
	end

	if breed_name ~= nil then
		_super_armor_breed_cache[breed_name] = has_super_armor
	end

	return has_super_armor
end

local function build_context(unit, blackboard)
	local fixed_t = _fixed_time()
	local cached_entry = _decision_context_cache[unit]
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
		allies_in_coherency = 0,
		avg_ally_toughness_pct = 1,
		max_ally_corruption_pct = 0,
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

	local coherency_extension = ScriptUnit.has_extension(unit, "coherency_system")
	if coherency_extension and coherency_extension.in_coherence_units then
		local in_coherence_units = coherency_extension:in_coherence_units()
		local ally_count = 0
		local ally_toughness_sum = 0
		local max_corruption = 0
		for ally_unit, _ in pairs(in_coherence_units) do
			local ally_breed_data = ScriptUnit.has_extension(ally_unit, "unit_data_system")
			local ally_breed = ally_breed_data and ally_breed_data:breed()
			local is_dog = ally_breed and ally_breed.name and string.find(ally_breed.name, "companion", 1, true)
			if not is_dog then
				ally_count = ally_count + 1
				local ally_toughness_ext = ScriptUnit.has_extension(ally_unit, "toughness_system")
				if ally_toughness_ext and ally_toughness_ext.current_toughness_percent then
					ally_toughness_sum = ally_toughness_sum + (ally_toughness_ext:current_toughness_percent() or 1)
				else
					ally_toughness_sum = ally_toughness_sum + 1
				end
				local ally_health_ext = ScriptUnit.has_extension(ally_unit, "health_system")
				if ally_health_ext and ally_health_ext.permanent_damage_taken_percent then
					local corruption = ally_health_ext:permanent_damage_taken_percent() or 0
					if corruption > max_corruption then
						max_corruption = corruption
					end
				end
			end
		end
		context.allies_in_coherency = ally_count
		context.avg_ally_toughness_pct = ally_count > 0 and (ally_toughness_sum / ally_count) or 1
		context.max_ally_corruption_pct = max_corruption
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

	_decision_context_cache[unit] = {
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
		if context.num_nearby >= 3 then
			return true, "veteran_voc_surrounded"
		end
		if context.toughness_pct < 0.50 and context.num_nearby >= 2 then
			return true, "veteran_voc_low_toughness"
		end
		if context.toughness_pct < 0.25 and context.num_nearby >= 1 then
			return true, "veteran_voc_critical_toughness"
		end
		if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) <= 9 then
			return true, "veteran_voc_ally_aid"
		end
		if context.toughness_pct > 0.85 and context.num_nearby <= 1 then
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
	if context.toughness_pct < 0.25 and context.num_nearby >= 2 then
		return true, "veteran_stealth_critical_toughness"
	end
	if context.health_pct < 0.40 and context.num_nearby >= 1 then
		return true, "veteran_stealth_low_health"
	end
	if
		context.target_ally_needs_aid
		and (context.target_ally_distance or math.huge) <= 20
		and context.num_nearby >= 2
	then
		return true, "veteran_stealth_ally_aid"
	end
	if context.num_nearby >= 5 and context.toughness_pct < 0.50 then
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
	if context.num_nearby >= 2 and target_distance and target_distance > 4 and target_distance < 15 then
		return true, "zealot_dash_combat_gap_close"
	end

	return false, "zealot_dash_hold"
end

local function _can_activate_zealot_invisibility(context)
	if context.num_nearby == 0 then
		return false, "zealot_stealth_block_no_enemies"
	end
	if (context.toughness_pct < 0.30 and context.num_nearby >= 2) or context.health_pct < 0.30 then
		return true, "zealot_stealth_emergency"
	end
	if context.num_nearby >= 4 and context.toughness_pct < 0.60 then
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
	if context.priority_target_enemy and context.target_enemy_distance and context.target_enemy_distance <= 20 then
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

	-- Bots don't use warp attacks, so peril stays at 0. Bypass peril gate
	-- and use threat-only conditions. Revisit when blitz support (#4) lands.
	local bot_no_peril = context.peril_pct == 0

	if not bot_no_peril and (context.peril_pct < 0.20 or context.peril_pct > 0.90) then
		return false, "psyker_stance_block_peril_window"
	end
	if
		(context.opportunity_target_enemy or context.urgent_target_enemy)
		and (bot_no_peril or (context.peril_pct >= 0.35 and context.peril_pct <= 0.85))
	then
		return true, "psyker_stance_target_window"
	end
	if
		context.challenge_rating_sum >= 4.0
		and (bot_no_peril or (context.peril_pct >= 0.35 and context.peril_pct <= 0.85))
	then
		return true, "psyker_stance_threat_window"
	end
	if bot_no_peril and context.num_nearby >= 3 then
		return true, "psyker_stance_combat_density"
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
	if context.opportunity_target_enemy and target_distance and target_distance >= 6 and target_distance <= 20 then
		return true, "ogryn_charge_opportunity_target"
	end
	if context.num_nearby >= 3 and context.toughness_pct < 0.30 then
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
	if context.num_nearby >= 3 and context.toughness_pct > 0.35 and context.health_pct > 0.25 then
		return true, "ogryn_taunt_horde_control"
	end
	if context.challenge_rating_sum >= 4.0 and context.num_nearby >= 2 and context.toughness_pct > 0.30 then
		return true, "ogryn_taunt_high_threat"
	end
	if context.num_nearby <= 2 and context.challenge_rating_sum < 1.5 then
		return false, "ogryn_taunt_block_low_value"
	end

	return false, "ogryn_taunt_hold"
end

local function _can_activate_ogryn_gunlugger(context)
	local target_distance = context.target_enemy_distance
	if context.num_nearby >= 4 then
		return false, "ogryn_gunlugger_block_melee_pressure"
	end
	if target_distance and target_distance < 4 then
		return false, "ogryn_gunlugger_block_target_too_close"
	end
	if context.challenge_rating_sum < 1.5 then
		return false, "ogryn_gunlugger_block_low_threat"
	end
	if context.urgent_target_enemy and context.num_nearby <= 1 and target_distance and target_distance > 5 then
		return true, "ogryn_gunlugger_urgent_target"
	end
	if
		context.target_enemy_type == "ranged"
		and target_distance
		and target_distance > 5
		and (context.elite_count + context.special_count) >= 1
	then
		return true, "ogryn_gunlugger_ranged_pack"
	end
	if context.challenge_rating_sum >= 4.0 and target_distance and target_distance > 5 and context.num_nearby <= 2 then
		return true, "ogryn_gunlugger_high_threat"
	end

	return false, "ogryn_gunlugger_hold"
end

local function _can_activate_adamant_stance(context)
	local target_distance = context.target_enemy_distance
	if context.toughness_pct < 0.30 then
		return true, "adamant_stance_low_toughness"
	end
	if context.num_nearby >= 2 and context.toughness_pct < 0.70 then
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
	if context.num_nearby >= 4 and context.toughness_pct < 0.60 then
		return true, "adamant_shout_density"
	end
	if
		(context.elite_count + context.special_count) >= 1
		and context.num_nearby >= 2
		and context.toughness_pct < 0.50
	then
		return true, "adamant_shout_elite_pressure"
	end

	return false, "adamant_shout_hold"
end

local function _can_activate_broker_focus(context)
	if context.num_nearby == 0 then
		return false, "broker_focus_block_no_enemies"
	end
	if context.toughness_pct < 0.50 then
		return true, "broker_focus_low_toughness"
	end
	if context.target_enemy_type == "ranged" and context.num_nearby >= 2 then
		return true, "broker_focus_ranged_pressure"
	end
	if context.num_nearby >= 4 then
		return true, "broker_focus_density"
	end

	return false, "broker_focus_hold"
end

local function _can_activate_broker_rage(context)
	if context.num_nearby == 0 then
		return false, "broker_rage_block_no_enemies"
	end
	if context.toughness_pct < 0.50 then
		return true, "broker_rage_low_toughness"
	end
	if context.num_nearby >= 3 and context.melee_count >= 2 then
		return true, "broker_rage_melee_pressure"
	end
	if (context.elite_count + context.monster_count) >= 1 and context.num_nearby >= 1 then
		return true, "broker_rage_elite_pressure"
	end
	if context.num_nearby >= 5 then
		return true, "broker_rage_density"
	end
	if context.target_enemy_type == "ranged" and context.num_nearby <= 2 then
		return false, "broker_rage_block_ranged_only"
	end

	return false, "broker_rage_hold"
end

local function _can_activate_zealot_relic(context)
	if context.num_nearby >= 5 and context.toughness_pct < 0.30 then
		return false, "zealot_relic_block_overwhelmed"
	end
	if context.avg_ally_toughness_pct < 0.40 and context.allies_in_coherency >= 2 and context.num_nearby < 2 then
		return true, "zealot_relic_team_low_toughness"
	end
	if context.toughness_pct < 0.25 and context.num_nearby < 3 then
		return true, "zealot_relic_self_critical"
	end
	if context.allies_in_coherency == 0 then
		return false, "zealot_relic_block_no_allies"
	end
	return false, "zealot_relic_hold"
end

local function _can_activate_force_field(context)
	if context.num_nearby == 0 and not context.target_enemy then
		return false, "force_field_block_no_threats"
	end
	if context.target_ally_needs_aid then
		return true, "force_field_ally_aid"
	end
	if context.toughness_pct > 0.80 then
		return false, "force_field_block_safe"
	end
	if context.num_nearby >= 3 and context.toughness_pct < 0.40 then
		return true, "force_field_pressure"
	end
	if context.target_enemy_type == "ranged" and context.toughness_pct < 0.60 then
		return true, "force_field_ranged_pressure"
	end
	return false, "force_field_hold"
end

local function _can_activate_drone(context)
	if context.allies_in_coherency == 0 then
		return false, "drone_block_no_allies"
	end
	if context.num_nearby <= 2 then
		return false, "drone_block_low_value"
	end
	if context.allies_in_coherency >= 2 and context.num_nearby >= 4 then
		return true, "drone_team_horde"
	end
	if context.target_is_monster and context.allies_in_coherency >= 1 then
		return true, "drone_monster_fight"
	end
	if context.num_nearby >= 5 and context.toughness_pct < 0.50 then
		return true, "drone_overwhelmed"
	end
	return false, "drone_hold"
end

local function _can_activate_stimm_field(context)
	if context.num_nearby == 0 then
		return false, "stimm_block_no_enemies"
	end
	if context.allies_in_coherency == 0 then
		return false, "stimm_block_no_allies"
	end
	if context.max_ally_corruption_pct > 0.30 and context.allies_in_coherency >= 1 then
		return true, "stimm_corruption_heal"
	end
	if context.target_ally_needs_aid and context.num_nearby >= 2 then
		return true, "stimm_ally_aid"
	end
	return false, "stimm_hold"
end

local TEMPLATE_HEURISTICS = {
	veteran_stealth_combat_ability = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_veteran_stealth(context)
	end,
	zealot_dash = function(_, _, _, _, _, _, _, _, context)
		return _can_activate_zealot_dash(context)
	end,
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

local ITEM_HEURISTICS = {
	zealot_relic = _can_activate_zealot_relic,
	psyker_force_field = _can_activate_force_field,
	psyker_force_field_improved = _can_activate_force_field,
	psyker_force_field_dome = _can_activate_force_field,
	adamant_area_buff_drone = _can_activate_drone,
	broker_ability_stimm_field = _can_activate_stimm_field,
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

-- Centralized decision evaluation with nil→fallback resolution.
-- Replaces the pattern previously duplicated in _can_activate_ability,
-- _fallback_try_queue_combat_ability, and _resolve_current_heuristic_decision.
local function resolve_decision(
	ability_template_name,
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension
)
	local context = build_context(unit, blackboard)
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
			rule = rule and (tostring(rule) .. "->fallback_nearby") or "fallback_nearby"
		end
	end

	return can_activate, rule, context
end

-- Test-friendly entry point: evaluates a template heuristic against a pre-built
-- context table without touching engine state. For veteran_combat_ability, pass
-- opts.conditions and opts.ability_extension.
local function evaluate_heuristic(template_name, context, opts)
	if template_name == "veteran_combat_ability" then
		opts = opts or {}
		return _can_activate_veteran_combat_ability(
			opts.conditions or {},
			opts.unit,
			nil,
			nil,
			nil,
			nil,
			false,
			opts.ability_extension,
			context
		)
	end

	local fn = TEMPLATE_HEURISTICS[template_name]
	if not fn then
		return nil, "fallback_unhandled_template"
	end

	return fn(nil, nil, nil, nil, nil, nil, nil, nil, context)
end

local function evaluate_item_heuristic(ability_name, context)
	local fn = ITEM_HEURISTICS[ability_name]
	if not fn then
		return false, "unknown_item_ability"
	end
	return fn(context)
end

return {
	init = function(deps)
		_fixed_time = deps.fixed_time
		_decision_context_cache = deps.decision_context_cache
		_super_armor_breed_cache = deps.super_armor_breed_cache
		_armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
	end,
	build_context = build_context,
	resolve_decision = resolve_decision,
	evaluate_heuristic = evaluate_heuristic,
	evaluate_item_heuristic = evaluate_item_heuristic,
	enemy_breed = _enemy_breed,
}
