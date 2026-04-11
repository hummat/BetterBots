local _fixed_time
local _decision_context_cache
local _super_armor_breed_cache
local _armor_type_super_armor
local _is_testing_profile
local _resolve_preset
local _debug_log
local _debug_enabled
local _combat_ability_identity
local _daemonhost_breed_names
local _is_daemonhost_avoidance_enabled
local _overlapping_liquids = {}
local WHISTLE_MAX_COMPANION_DISTANCE_SQ = 10 * 10
local SHIELD_INTERACTION_TYPES = {
	scanning = true,
	setup_decoding = true,
	setup_breach_charge = true,
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
	health_station = true,
	servo_skull = true,
	servo_skull_activator = true,
}

-- Per-frame shared cache of interacting allies on a given side. The
-- read_component walk over valid_player_units is identical for every bot
-- sharing a side within a fixed_t tick, so scan once and let each bot pick
-- its own "nearest" in build_context (distance depends on bot position).
-- Mirrors the sprint.lua shared daemonhost scan pattern — keyed on
-- (fixed_t, side) by reference identity.
local _interacting_units = {}
local _interacting_profiles = {}
local _interacting_types = {}
local _interacting_cache_t = nil
local _interacting_cache_side = nil

local function _scan_interacting_allies(side, fixed_t)
	if _interacting_cache_t == fixed_t and _interacting_cache_side == side then
		return _interacting_units, _interacting_profiles, _interacting_types
	end

	for i = #_interacting_units, 1, -1 do
		_interacting_units[i] = nil
		_interacting_profiles[i] = nil
		_interacting_types[i] = nil
	end

	local player_units = side and side.valid_player_units
	if not player_units then
		_interacting_cache_t = fixed_t
		_interacting_cache_side = side
		return _interacting_units, _interacting_profiles, _interacting_types
	end

	for i = 1, #player_units do
		local ally_unit = player_units[i]
		if (not ALIVE) or ALIVE[ally_unit] then
			local ally_data = ScriptUnit.has_extension(ally_unit, "unit_data_system")
			if ally_data then
				local profile = nil
				local interaction_type = nil

				local char_state = ally_data:read_component("character_state")
				local state_name = char_state and char_state.state_name

				if state_name == "minigame" then
					profile = "shield"
					interaction_type = "minigame"
				elseif state_name == "interacting" then
					local interacting_state = ally_data:read_component("interacting_character_state")
					local template = interacting_state and interacting_state.interaction_template
					if template and SHIELD_INTERACTION_TYPES[template] then
						profile = "shield"
						interaction_type = template
					end
				end

				if not profile then
					local inventory = ally_data:read_component("inventory")
					if inventory and inventory.wielded_slot == "slot_luggable" then
						profile = "escort"
						interaction_type = "luggable"
					end
				end

				if profile then
					local n = #_interacting_units + 1
					_interacting_units[n] = ally_unit
					_interacting_profiles[n] = profile
					_interacting_types[n] = interaction_type
				end
			end
		end
	end

	_interacting_cache_t = fixed_t
	_interacting_cache_side = side

	return _interacting_units, _interacting_profiles, _interacting_types
end
local HAZARD_TEMPLATE_TOKENS = {
	fire = true,
	gas = true,
	toxic = true,
	corrupt = true,
	slime = true,
}

local function _is_hazardous_liquid_area(liquid_area)
	if not liquid_area then
		return false
	end

	local source_side_name = liquid_area.source_side_name and liquid_area:source_side_name()
	if source_side_name == "heroes" then
		return false
	end

	local area_template_name = liquid_area.area_template_name and liquid_area:area_template_name()
	if not area_template_name then
		return source_side_name ~= nil
	end

	for token, _ in pairs(HAZARD_TEMPLATE_TOKENS) do
		if string.find(area_template_name, token, 1, true) then
			return true
		end
	end

	return false
end

local function _position_in_hostile_hazard(position)
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager or not position then
		return false
	end

	local liquid_area_system = extension_manager:system("liquid_area_system")
	if not liquid_area_system then
		return false
	end

	if liquid_area_system.find_liquid_areas_in_position then
		for i = #_overlapping_liquids, 1, -1 do
			_overlapping_liquids[i] = nil
		end
		liquid_area_system:find_liquid_areas_in_position(position, _overlapping_liquids)

		for i = 1, #_overlapping_liquids do
			if _is_hazardous_liquid_area(_overlapping_liquids[i]) then
				return true
			end
		end

		return false
	end

	return liquid_area_system.is_position_in_liquid and liquid_area_system:is_position_in_liquid(position) or false
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
		target_enemy_position = nil,
		target_enemy_distance = nil,
		target_enemy_type = nil,
		priority_target_enemy = nil,
		opportunity_target_enemy = nil,
		urgent_target_enemy = nil,
		companion_unit = nil,
		companion_position = nil,
		target_ally_needs_aid = false,
		target_ally_distance = nil,
		target_ally_unit = nil,
		target_is_elite_special = false,
		target_is_monster = false,
		target_is_dormant_daemonhost = false,
		target_is_super_armor = false,
		allies_in_coherency = 0,
		avg_ally_toughness_pct = 1,
		max_ally_corruption_pct = 0,
		in_hazard = false,
		ally_interacting = false,
		ally_interaction_type = nil,
		ally_interacting_unit = nil,
		ally_interacting_distance = nil,
		ally_interaction_profile = nil,
	}

	context.preset = _resolve_preset and _resolve_preset() or "balanced"

	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit]
	if unit_position then
		context.in_hazard = _position_in_hostile_hazard(unit_position)
	end

	local companion_spawner_extension = ScriptUnit.has_extension(unit, "companion_spawner_system")
	local companion_units = companion_spawner_extension and companion_spawner_extension:companion_units()
	if companion_units then
		for i = 1, #companion_units do
			local companion_unit = companion_units[i]
			if companion_unit and (not ALIVE or ALIVE[companion_unit]) then
				context.companion_unit = companion_unit
				context.companion_position = POSITION_LOOKUP and POSITION_LOOKUP[companion_unit] or nil
				break
			end
		end
	end

	local perception_component = blackboard and blackboard.perception
	if perception_component then
		context.target_enemy = perception_component.target_enemy
		context.target_enemy_position = POSITION_LOOKUP and POSITION_LOOKUP[context.target_enemy] or nil
		context.target_enemy_distance = perception_component.target_enemy_distance
		context.target_enemy_type = perception_component.target_enemy_type
		context.priority_target_enemy = perception_component.priority_target_enemy
		context.opportunity_target_enemy = perception_component.opportunity_target_enemy
		context.urgent_target_enemy = perception_component.urgent_target_enemy
		context.target_ally_needs_aid = perception_component.target_ally_needs_aid == true
		context.target_ally_distance = perception_component.target_ally_distance
		context.target_ally_unit = perception_component.target_ally
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
			if ally_unit ~= unit then
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
				if enemy_breed.ranged or enemy_breed.game_object_type == "minion_ranged" then
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
			-- #17: flag dormant daemonhosts so monster-aware heuristics refuse
			-- to blitz them. Once DH transitions to aggroed (on anyone — a
			-- triggered daemonhost commits the whole group), dormancy lifts
			-- and normal combat resumes. Pre-aggro: trash is targeted via
			-- vanilla target selection even though no combat action should
			-- ensue — we must refuse at the heuristic layer.
			if _daemonhost_breed_names and _daemonhost_breed_names[target_breed.name] then
				local target_bb = BLACKBOARDS and BLACKBOARDS[context.target_enemy]
				local target_perception = target_bb and target_bb.perception
				local is_aggroed = target_perception and target_perception.aggro_state == "aggroed"
				context.target_is_dormant_daemonhost = not is_aggroed
			end
		end
	end

	local side_system = Managers
		and Managers.state
		and Managers.state.extension
		and Managers.state.extension:system("side_system")
	if side_system then
		local side = side_system.side_by_unit[unit]
		if side then
			local interacting_units, interacting_profiles, interacting_types = _scan_interacting_allies(side, fixed_t)
			local best_distance_sq = math.huge
			for i = 1, #interacting_units do
				local ally_unit = interacting_units[i]
				if ally_unit ~= unit then
					local ally_position = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
					local dist_sq = math.huge
					if unit_position and ally_position and ally_position.x then
						local dx = ally_position.x - unit_position.x
						local dy = ally_position.y - unit_position.y
						local dz = ally_position.z - unit_position.z
						dist_sq = dx * dx + dy * dy + dz * dz
					end

					if not context.ally_interacting or dist_sq < best_distance_sq then
						best_distance_sq = dist_sq
						context.ally_interacting = true
						context.ally_interaction_type = interacting_types[i]
						context.ally_interacting_unit = ally_unit
						context.ally_interacting_distance = dist_sq < math.huge and math.sqrt(dist_sq) or nil
						context.ally_interaction_profile = interacting_profiles[i]
					end
				end
			end

			if context.ally_interacting and _debug_enabled and _debug_enabled() then
				_debug_log(
					"interaction_scan:" .. tostring(unit),
					fixed_t,
					context.ally_interaction_profile
						.. " ("
						.. tostring(context.ally_interaction_type)
						.. ") dist="
						.. string.format("%.1f", context.ally_interacting_distance or -1),
					5
				)
			end
		end
	end

	_decision_context_cache[unit] = {
		fixed_t = fixed_t,
		context = context,
	}

	return context
end

local function _resolve_combat_identity(ability_template_name, ability_extension)
	return _combat_ability_identity.resolve(nil, ability_extension, { template_name = ability_template_name })
end

-- Per-preset threshold tables: aggressive fires abilities at first sign of pressure
-- (accepts resource waste), balanced is the default, conservative holds for genuine
-- emergencies (risks missed opportunities). The "testing" preset has no threshold
-- entries — it intentionally falls back to "balanced" thresholds via the
-- `or table.balanced` pattern, then the testing profile override in
-- _apply_behavior_profile loosens decisions post-heuristic.
-- Templates without preset-varying thresholds (broker_focus, broker_punk_rage)
-- take only (context) — the extra thresholds arg is silently ignored by Lua.
-- Item heuristics (broker_ability_stimm_field, etc.) are dispatched separately.
local VETERAN_VOC_THRESHOLDS = {
	aggressive = {
		surrounded = 2,
		low_toughness = 0.65,
		low_toughness_nearby = 1,
		critical_toughness = 0.40,
		ally_aid_dist = 14,
		block_safe_toughness = 0.70,
		block_safe_max_enemies = 2,
	},
	balanced = {
		surrounded = 3,
		low_toughness = 0.50,
		low_toughness_nearby = 2,
		critical_toughness = 0.25,
		ally_aid_dist = 9,
		block_safe_toughness = 0.85,
		block_safe_max_enemies = 1,
	},
	conservative = {
		surrounded = 4,
		low_toughness = 0.35,
		low_toughness_nearby = 3,
		critical_toughness = 0.15,
		ally_aid_dist = 6,
		block_safe_toughness = 0.95,
		block_safe_max_enemies = 0,
	},
}

local VETERAN_STANCE_THRESHOLDS = {
	aggressive = { block_surrounded = 7, urgent_max_enemies = 3 },
	balanced = { block_surrounded = 5, urgent_max_enemies = 2 },
	conservative = { block_surrounded = 4, urgent_max_enemies = 1 },
}

local function _can_activate_veteran_combat_ability(
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension,
	context,
	thresholds
)
	local identity = _resolve_combat_identity("veteran_combat_ability", ability_extension)
	local class_tag = identity.class_tag
	local source = identity.class_tag_source
	if class_tag == "squad_leader" then
		local thresholds_voc = thresholds
		if context.in_hazard and context.num_nearby >= 1 then
			return true, "veteran_voc_hazard"
		end
		if context.ally_interacting and context.num_nearby >= 1 then
			return true, "veteran_voc_protect_interactor"
		end
		if context.num_nearby >= thresholds_voc.surrounded then
			return true, "veteran_voc_surrounded"
		end
		if
			context.toughness_pct < thresholds_voc.low_toughness
			and context.num_nearby >= thresholds_voc.low_toughness_nearby
		then
			return true, "veteran_voc_low_toughness"
		end
		if context.toughness_pct < thresholds_voc.critical_toughness and context.num_nearby >= 1 then
			return true, "veteran_voc_critical_toughness"
		end
		if
			context.target_ally_needs_aid
			and (context.target_ally_distance or math.huge) <= thresholds_voc.ally_aid_dist
		then
			return true, "veteran_voc_ally_aid"
		end
		if
			context.toughness_pct > thresholds_voc.block_safe_toughness
			and context.num_nearby <= thresholds_voc.block_safe_max_enemies
		then
			return false, "veteran_voc_block_safe_state"
		end

		return false, "veteran_voc_hold"
	end

	if class_tag == "base" or class_tag == "ranger" then
		if context.num_nearby > thresholds.block_surrounded and context.target_enemy_type == "melee" then
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

		if context.urgent_target_enemy and context.num_nearby <= thresholds.urgent_max_enemies then
			return true, "veteran_stance_urgent_target"
		end

		return false, "veteran_stance_hold"
	end

	return nil, "veteran_variant_" .. source
end

local VETERAN_STEALTH_THRESHOLDS = {
	aggressive = {
		critical_toughness = 0.35,
		low_health = 0.55,
		overwhelmed_nearby = 4,
		overwhelmed_toughness = 0.65,
	},
	balanced = {
		critical_toughness = 0.25,
		low_health = 0.40,
		overwhelmed_nearby = 5,
		overwhelmed_toughness = 0.50,
	},
	conservative = {
		critical_toughness = 0.15,
		low_health = 0.25,
		overwhelmed_nearby = 6,
		overwhelmed_toughness = 0.35,
	},
}

local function _can_activate_veteran_stealth(context, thresholds)
	if context.num_nearby == 0 then
		return false, "veteran_stealth_block_no_enemies"
	end
	if context.toughness_pct < thresholds.critical_toughness and context.num_nearby >= 2 then
		return true, "veteran_stealth_critical_toughness"
	end
	if context.health_pct < thresholds.low_health and context.num_nearby >= 1 then
		return true, "veteran_stealth_low_health"
	end
	if
		context.target_ally_needs_aid
		and (context.target_ally_distance or math.huge) <= 20
		and context.num_nearby >= 2
	then
		return true, "veteran_stealth_ally_aid"
	end
	if
		context.num_nearby >= thresholds.overwhelmed_nearby
		and context.toughness_pct < thresholds.overwhelmed_toughness
	then
		return true, "veteran_stealth_overwhelmed"
	end

	return false, "veteran_stealth_hold"
end

local ZEALOT_DASH_THRESHOLDS = {
	aggressive = {
		low_toughness = 0.45,
		elite_min_dist = 3,
		elite_max_dist = 28,
		combat_gap_nearby = 1,
		combat_gap_min_dist = 3,
		combat_gap_max_dist = 22,
	},
	balanced = {
		low_toughness = 0.30,
		elite_min_dist = 5,
		elite_max_dist = 20,
		combat_gap_nearby = 2,
		combat_gap_min_dist = 4,
		combat_gap_max_dist = 15,
	},
	conservative = {
		low_toughness = 0.20,
		elite_min_dist = 6,
		elite_max_dist = 15,
		combat_gap_nearby = 3,
		combat_gap_min_dist = 5,
		combat_gap_max_dist = 10,
	},
}

local function _can_activate_zealot_dash(context, thresholds)
	local target_distance = context.target_enemy_distance
	if not context.target_enemy then
		return false, "zealot_dash_block_no_target"
	end
	if target_distance and target_distance < 3 then
		return false, "zealot_dash_block_target_too_close"
	end
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "zealot_dash_block_protecting_interactor"
	end
	if context.target_is_super_armor then
		return false, "zealot_dash_block_super_armor"
	end
	if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 3 then
		return true, "zealot_dash_ally_aid"
	end
	if context.priority_target_enemy and target_distance and target_distance > 4 then
		return true, "zealot_dash_priority_target"
	end
	if
		context.toughness_pct < thresholds.low_toughness
		and context.num_nearby > 0
		and target_distance
		and target_distance > 3
		and target_distance < 20
	then
		return true, "zealot_dash_low_toughness"
	end
	if
		context.target_is_elite_special
		and target_distance
		and target_distance > thresholds.elite_min_dist
		and target_distance < thresholds.elite_max_dist
	then
		return true, "zealot_dash_elite_special_gap"
	end
	if
		context.num_nearby >= thresholds.combat_gap_nearby
		and target_distance
		and target_distance > thresholds.combat_gap_min_dist
		and target_distance < thresholds.combat_gap_max_dist
	then
		return true, "zealot_dash_combat_gap_close"
	end

	return false, "zealot_dash_hold"
end

local ZEALOT_INVISIBILITY_THRESHOLDS = {
	aggressive = {
		emergency_toughness = 0.45,
		emergency_health = 0.45,
		overwhelmed_nearby = 3,
		overwhelmed_toughness = 0.75,
		ally_dist = 18,
		ally_nearby = 1,
	},
	balanced = {
		emergency_toughness = 0.30,
		emergency_health = 0.30,
		overwhelmed_nearby = 4,
		overwhelmed_toughness = 0.60,
		ally_dist = 12,
		ally_nearby = 2,
	},
	conservative = {
		emergency_toughness = 0.20,
		emergency_health = 0.20,
		overwhelmed_nearby = 5,
		overwhelmed_toughness = 0.45,
		ally_dist = 8,
		ally_nearby = 3,
	},
}

local function _can_activate_zealot_invisibility(context, thresholds)
	if context.num_nearby == 0 then
		return false, "zealot_stealth_block_no_enemies"
	end
	if
		(context.toughness_pct < thresholds.emergency_toughness and context.num_nearby >= 2)
		or context.health_pct < thresholds.emergency_health
	then
		return true, "zealot_stealth_emergency"
	end
	if
		context.num_nearby >= thresholds.overwhelmed_nearby
		and context.toughness_pct < thresholds.overwhelmed_toughness
	then
		return true, "zealot_stealth_overwhelmed"
	end
	if
		context.target_ally_needs_aid
		and (context.target_ally_distance or math.huge) <= thresholds.ally_dist
		and context.num_nearby >= thresholds.ally_nearby
	then
		return true, "zealot_stealth_ally_reposition"
	end

	return false, "zealot_stealth_hold"
end

local PSYKER_SHOUT_THRESHOLDS = {
	aggressive = {
		high_peril = 0.60,
		surrounded = 2,
		low_toughness = 0.30,
		priority_dist = 30,
		block_low_value_toughness = 0.35,
	},
	balanced = {
		high_peril = 0.75,
		surrounded = 3,
		low_toughness = 0.20,
		priority_dist = 20,
		block_low_value_toughness = 0.50,
	},
	conservative = {
		high_peril = 0.85,
		surrounded = 4,
		low_toughness = 0.12,
		priority_dist = 15,
		block_low_value_toughness = 0.65,
	},
}

local function _can_activate_psyker_shout(context, thresholds)
	if context.num_nearby == 0 then
		return false, "psyker_shout_block_no_enemies"
	end
	if context.peril_pct and context.peril_pct >= thresholds.high_peril then
		return true, "psyker_shout_high_peril"
	end
	if context.num_nearby >= thresholds.surrounded then
		return true, "psyker_shout_surrounded"
	end
	if context.toughness_pct < thresholds.low_toughness and context.num_nearby >= 1 then
		return true, "psyker_shout_low_toughness"
	end
	if
		context.priority_target_enemy
		and context.target_enemy_distance
		and context.target_enemy_distance <= thresholds.priority_dist
	then
		return true, "psyker_shout_priority_target"
	end
	if
		context.peril_pct
		and context.peril_pct < 0.30
		and context.num_nearby < thresholds.surrounded
		and context.toughness_pct > thresholds.block_low_value_toughness
	then
		return false, "psyker_shout_block_low_value"
	end

	return false, "psyker_shout_hold"
end

local PSYKER_STANCE_THRESHOLDS = {
	aggressive = { threat_cr = 3.0, combat_density = 2 },
	balanced = { threat_cr = 4.0, combat_density = 3 },
	conservative = { threat_cr = 5.0, combat_density = 4 },
}

local function _can_activate_psyker_stance(context, thresholds)
	if context.peril_pct == nil then
		return nil, "psyker_stance_missing_peril"
	end
	if context.num_nearby == 0 then
		return false, "psyker_stance_block_no_enemies"
	end
	if context.health_pct < 0.25 then
		return false, "psyker_stance_block_low_health"
	end

	-- Some bot loadouts still report 0 peril in live combat, so keep a
	-- threat-only fallback instead of hard-blocking on the human peril window.
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
		context.challenge_rating_sum >= thresholds.threat_cr
		and (bot_no_peril or (context.peril_pct >= 0.35 and context.peril_pct <= 0.85))
	then
		return true, "psyker_stance_threat_window"
	end
	if bot_no_peril and context.num_nearby >= thresholds.combat_density then
		return true, "psyker_stance_combat_density"
	end

	return false, "psyker_stance_hold"
end

local OGRYN_CHARGE_THRESHOLDS = {
	aggressive = {
		opportunity_min_dist = 4,
		opportunity_max_dist = 28,
		escape_nearby = 2,
		escape_toughness = 0.45,
	},
	balanced = {
		opportunity_min_dist = 6,
		opportunity_max_dist = 20,
		escape_nearby = 3,
		escape_toughness = 0.30,
	},
	conservative = {
		opportunity_min_dist = 8,
		opportunity_max_dist = 15,
		escape_nearby = 4,
		escape_toughness = 0.20,
	},
}

local function _can_activate_ogryn_charge(context, thresholds)
	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 4 then
		return false, "ogryn_charge_block_target_too_close"
	end
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "ogryn_charge_block_protecting_interactor"
	end
	if context.priority_target_enemy and target_distance and target_distance > 4 then
		return true, "ogryn_charge_priority_target"
	end
	if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 6 then
		return true, "ogryn_charge_ally_aid"
	end
	if
		context.opportunity_target_enemy
		and target_distance
		and target_distance >= thresholds.opportunity_min_dist
		and target_distance <= thresholds.opportunity_max_dist
	then
		return true, "ogryn_charge_opportunity_target"
	end
	if context.num_nearby >= thresholds.escape_nearby and context.toughness_pct < thresholds.escape_toughness then
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

local OGRYN_TAUNT_THRESHOLDS = {
	aggressive = {
		horde_nearby = 2,
		horde_toughness = 0.20,
		horde_health = 0.15,
		high_threat_cr = 3.0,
		block_low_value_enemies = 3,
		block_low_value_cr = 2.5,
	},
	balanced = {
		horde_nearby = 3,
		horde_toughness = 0.35,
		horde_health = 0.25,
		high_threat_cr = 4.0,
		block_low_value_enemies = 2,
		block_low_value_cr = 1.5,
	},
	conservative = {
		horde_nearby = 4,
		horde_toughness = 0.50,
		horde_health = 0.35,
		high_threat_cr = 5.0,
		block_low_value_enemies = 1,
		block_low_value_cr = 1.0,
	},
}

local function _can_activate_ogryn_taunt(context, thresholds)
	if context.toughness_pct < 0.20 and context.health_pct < 0.30 then
		return false, "ogryn_taunt_block_too_fragile"
	end
	if context.ally_interacting and context.num_nearby >= 1 and context.toughness_pct > 0.30 then
		return true, "ogryn_taunt_protect_interactor"
	end
	if context.target_ally_needs_aid and context.num_nearby >= 2 and context.toughness_pct > 0.30 then
		return true, "ogryn_taunt_ally_aid"
	end
	if
		context.num_nearby >= thresholds.horde_nearby
		and context.toughness_pct > thresholds.horde_toughness
		and context.health_pct > thresholds.horde_health
	then
		return true, "ogryn_taunt_horde_control"
	end
	if
		context.challenge_rating_sum >= thresholds.high_threat_cr
		and context.num_nearby >= 2
		and context.toughness_pct > 0.30
	then
		return true, "ogryn_taunt_high_threat"
	end
	if
		context.num_nearby <= thresholds.block_low_value_enemies
		and context.challenge_rating_sum < thresholds.block_low_value_cr
	then
		return false, "ogryn_taunt_block_low_value"
	end

	return false, "ogryn_taunt_hold"
end

local OGRYN_GUNLUGGER_THRESHOLDS = {
	aggressive = {
		block_melee_nearby = 5,
		block_low_threat_cr = 1.0,
		high_threat_cr = 3.0,
		high_threat_max_enemies = 3,
	},
	balanced = {
		block_melee_nearby = 4,
		block_low_threat_cr = 1.5,
		high_threat_cr = 4.0,
		high_threat_max_enemies = 2,
	},
	conservative = {
		block_melee_nearby = 3,
		block_low_threat_cr = 2.0,
		high_threat_cr = 5.5,
		high_threat_max_enemies = 1,
	},
}

local function _can_activate_ogryn_gunlugger(context, thresholds)
	local target_distance = context.target_enemy_distance
	if context.num_nearby >= thresholds.block_melee_nearby then
		return false, "ogryn_gunlugger_block_melee_pressure"
	end
	if target_distance and target_distance < 4 then
		return false, "ogryn_gunlugger_block_target_too_close"
	end
	if context.challenge_rating_sum < thresholds.block_low_threat_cr then
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
	if
		context.challenge_rating_sum >= thresholds.high_threat_cr
		and target_distance
		and target_distance > 5
		and context.num_nearby <= thresholds.high_threat_max_enemies
	then
		return true, "ogryn_gunlugger_high_threat"
	end

	return false, "ogryn_gunlugger_hold"
end

local ADAMANT_STANCE_THRESHOLDS = {
	aggressive = {
		low_toughness = 0.45,
		surrounded_nearby = 1,
		surrounded_toughness = 0.85,
		elite_count = 1,
		elite_toughness = 0.65,
		block_safe_toughness = 0.55,
		block_safe_max_enemies = 2,
	},
	balanced = {
		low_toughness = 0.30,
		surrounded_nearby = 2,
		surrounded_toughness = 0.70,
		elite_count = 2,
		elite_toughness = 0.50,
		block_safe_toughness = 0.70,
		block_safe_max_enemies = 1,
	},
	conservative = {
		low_toughness = 0.20,
		surrounded_nearby = 3,
		surrounded_toughness = 0.55,
		elite_count = 3,
		elite_toughness = 0.35,
		block_safe_toughness = 0.80,
		block_safe_max_enemies = 0,
	},
}

-- #17: once a heuristic would key off target_is_monster, the decision must
-- first confirm the monster is not a dormant daemonhost. Centralized so every
-- call site gets the same gate (and respects the avoidance setting toggle).
local function _is_monster_signal_allowed(context)
	if not context.target_is_monster then
		return false
	end
	if
		context.target_is_dormant_daemonhost
		and _is_daemonhost_avoidance_enabled
		and _is_daemonhost_avoidance_enabled()
	then
		return false
	end
	return true
end

local function _can_activate_adamant_stance(context, thresholds)
	local target_distance = context.target_enemy_distance
	if context.toughness_pct < thresholds.low_toughness then
		return true, "adamant_stance_low_toughness"
	end
	if
		context.num_nearby >= thresholds.surrounded_nearby
		and context.toughness_pct < thresholds.surrounded_toughness
	then
		return true, "adamant_stance_surrounded"
	end
	if _is_monster_signal_allowed(context) and target_distance and target_distance < 8 then
		return true, "adamant_stance_monster_pressure"
	end
	if context.elite_count >= thresholds.elite_count and context.toughness_pct < thresholds.elite_toughness then
		return true, "adamant_stance_elite_pressure"
	end
	if
		context.toughness_pct > thresholds.block_safe_toughness
		and context.num_nearby <= thresholds.block_safe_max_enemies
	then
		return false, "adamant_stance_block_safe_state"
	end

	return false, "adamant_stance_hold"
end

local ADAMANT_CHARGE_THRESHOLDS = {
	aggressive = { density_nearby = 1, density_max_dist = 14 },
	balanced = { density_nearby = 2, density_max_dist = 10 },
	conservative = { density_nearby = 3, density_max_dist = 7 },
}

local function _can_activate_adamant_charge(context, thresholds)
	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 3 then
		return false, "adamant_charge_block_target_too_close"
	end
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "adamant_charge_block_protecting_interactor"
	end
	if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 3 then
		return true, "adamant_charge_ally_aid"
	end
	if context.num_nearby == 0 and not context.priority_target_enemy and not context.target_is_elite_special then
		return false, "adamant_charge_block_no_pressure"
	end
	if
		context.num_nearby >= thresholds.density_nearby
		and target_distance
		and target_distance > 3
		and target_distance < thresholds.density_max_dist
	then
		return true, "adamant_charge_density"
	end
	if
		context.target_is_elite_special
		and target_distance
		and target_distance > 3
		and target_distance < thresholds.density_max_dist
	then
		return true, "adamant_charge_elite_special"
	end
	if context.priority_target_enemy and target_distance and target_distance > 3 then
		return true, "adamant_charge_priority_target"
	end

	return false, "adamant_charge_hold"
end

local ADAMANT_SHOUT_THRESHOLDS = {
	aggressive = {
		low_toughness = 0.40,
		low_toughness_nearby = 1,
		density_nearby = 3,
		density_toughness = 0.75,
		elite_toughness = 0.65,
	},
	balanced = {
		low_toughness = 0.25,
		low_toughness_nearby = 2,
		density_nearby = 4,
		density_toughness = 0.60,
		elite_toughness = 0.50,
	},
	conservative = {
		low_toughness = 0.15,
		low_toughness_nearby = 3,
		density_nearby = 5,
		density_toughness = 0.45,
		elite_toughness = 0.35,
	},
}

local function _can_activate_adamant_shout(context, thresholds)
	if context.ally_interacting and context.num_nearby >= 1 then
		return true, "adamant_shout_protect_interactor"
	end
	if context.toughness_pct < thresholds.low_toughness and context.num_nearby >= thresholds.low_toughness_nearby then
		return true, "adamant_shout_low_toughness"
	end
	if context.num_nearby >= thresholds.density_nearby and context.toughness_pct < thresholds.density_toughness then
		return true, "adamant_shout_density"
	end
	if
		(context.elite_count + context.special_count) >= 1
		and context.num_nearby >= 2
		and context.toughness_pct < thresholds.elite_toughness
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

local ZEALOT_RELIC_THRESHOLDS = {
	aggressive = {
		team_toughness = 0.55,
		team_max_enemies = 3,
		self_critical_toughness = 0.35,
		self_max_enemies = 4,
	},
	balanced = {
		team_toughness = 0.40,
		team_max_enemies = 2,
		self_critical_toughness = 0.25,
		self_max_enemies = 3,
	},
	conservative = {
		team_toughness = 0.30,
		team_max_enemies = 1,
		self_critical_toughness = 0.15,
		self_max_enemies = 2,
	},
}

local function _can_activate_zealot_relic(context, thresholds)
	if context.in_hazard and context.num_nearby >= 1 then
		return true, "zealot_relic_hazard"
	end
	if context.num_nearby >= 5 and context.toughness_pct < 0.30 then
		return false, "zealot_relic_block_overwhelmed"
	end
	if context.ally_interacting and context.allies_in_coherency >= 1 then
		return true, "zealot_relic_protect_interactor"
	end
	if
		context.avg_ally_toughness_pct < thresholds.team_toughness
		and context.allies_in_coherency >= 2
		and context.num_nearby < thresholds.team_max_enemies
	then
		return true, "zealot_relic_team_low_toughness"
	end
	if
		context.toughness_pct < thresholds.self_critical_toughness
		and context.num_nearby < thresholds.self_max_enemies
	then
		return true, "zealot_relic_self_critical"
	end
	if context.allies_in_coherency == 0 then
		return false, "zealot_relic_block_no_allies"
	end
	return false, "zealot_relic_hold"
end

local FORCE_FIELD_THRESHOLDS = {
	aggressive = {
		block_safe_toughness = 0.65,
		pressure_nearby = 2,
		pressure_toughness = 0.55,
		ranged_toughness = 0.75,
	},
	balanced = {
		block_safe_toughness = 0.80,
		pressure_nearby = 3,
		pressure_toughness = 0.40,
		ranged_toughness = 0.60,
	},
	conservative = {
		block_safe_toughness = 0.90,
		pressure_nearby = 4,
		pressure_toughness = 0.25,
		ranged_toughness = 0.45,
	},
}

local function _can_activate_force_field(context, thresholds)
	if context.num_nearby == 0 and not context.target_enemy then
		return false, "force_field_block_no_threats"
	end
	if context.ally_interacting and (context.ranged_count >= 1 or context.num_nearby >= 2) then
		return true, "force_field_protect_interactor"
	end
	if context.target_ally_needs_aid then
		return true, "force_field_ally_aid"
	end
	if context.toughness_pct > thresholds.block_safe_toughness then
		return false, "force_field_block_safe"
	end
	if context.num_nearby >= thresholds.pressure_nearby and context.toughness_pct < thresholds.pressure_toughness then
		return true, "force_field_pressure"
	end
	if context.target_enemy_type == "ranged" and context.toughness_pct < thresholds.ranged_toughness then
		return true, "force_field_ranged_pressure"
	end
	return false, "force_field_hold"
end

local DRONE_THRESHOLDS = {
	aggressive = {
		block_low_value_enemies = 1,
		team_horde_nearby = 3,
		overwhelmed_nearby = 4,
		overwhelmed_toughness = 0.65,
	},
	balanced = {
		block_low_value_enemies = 2,
		team_horde_nearby = 4,
		overwhelmed_nearby = 5,
		overwhelmed_toughness = 0.50,
	},
	conservative = {
		block_low_value_enemies = 3,
		team_horde_nearby = 5,
		overwhelmed_nearby = 6,
		overwhelmed_toughness = 0.35,
	},
}

local function _can_activate_drone(context, thresholds)
	if context.allies_in_coherency == 0 then
		return false, "drone_block_no_allies"
	end
	if _is_monster_signal_allowed(context) and context.allies_in_coherency >= 1 then
		return true, "drone_monster_fight"
	end
	if context.num_nearby <= thresholds.block_low_value_enemies then
		return false, "drone_block_low_value"
	end
	local team_horde_threshold = thresholds.team_horde_nearby
	if context.ally_interacting then
		team_horde_threshold = team_horde_threshold - 1
	end
	if context.allies_in_coherency >= 2 and context.num_nearby >= team_horde_threshold then
		return true, "drone_team_horde"
	end
	if
		context.num_nearby >= thresholds.overwhelmed_nearby
		and context.toughness_pct < thresholds.overwhelmed_toughness
	then
		return true, "drone_overwhelmed"
	end
	return false, "drone_hold"
end

local function _can_activate_stimm_field(context)
	if context.allies_in_coherency == 0 then
		return false, "stimm_block_no_allies"
	end
	if context.ally_interacting then
		return true, "stimm_protect_interactor"
	end
	if context.max_ally_corruption_pct > 0.30 then
		return true, "stimm_corruption_heal"
	end
	if context.target_ally_needs_aid and context.num_nearby >= 2 then
		return true, "stimm_ally_aid"
	end
	return false, "stimm_hold"
end

-- Template heuristic dispatch: fn(context, thresholds) -> can_activate, rule
-- veteran_combat_ability is dispatched separately in _evaluate_template_heuristic
-- because it needs the full condition_patch args.
local TEMPLATE_HEURISTICS = {
	veteran_stealth_combat_ability = _can_activate_veteran_stealth,
	zealot_dash = _can_activate_zealot_dash,
	zealot_targeted_dash = _can_activate_zealot_dash,
	zealot_targeted_dash_improved = _can_activate_zealot_dash,
	zealot_targeted_dash_improved_double = _can_activate_zealot_dash,
	zealot_invisibility = _can_activate_zealot_invisibility,
	psyker_shout = _can_activate_psyker_shout,
	psyker_overcharge_stance = _can_activate_psyker_stance,
	ogryn_charge = _can_activate_ogryn_charge,
	ogryn_charge_increased_distance = _can_activate_ogryn_charge,
	ogryn_taunt_shout = _can_activate_ogryn_taunt,
	ogryn_gunlugger_stance = _can_activate_ogryn_gunlugger,
	adamant_stance = _can_activate_adamant_stance,
	adamant_charge = _can_activate_adamant_charge,
	adamant_shout = _can_activate_adamant_shout,
	broker_focus = _can_activate_broker_focus,
	broker_punk_rage = _can_activate_broker_rage,
}

local HEURISTIC_THRESHOLDS = {
	veteran_stealth_combat_ability = VETERAN_STEALTH_THRESHOLDS,
	zealot_dash = ZEALOT_DASH_THRESHOLDS,
	zealot_targeted_dash = ZEALOT_DASH_THRESHOLDS,
	zealot_targeted_dash_improved = ZEALOT_DASH_THRESHOLDS,
	zealot_targeted_dash_improved_double = ZEALOT_DASH_THRESHOLDS,
	zealot_invisibility = ZEALOT_INVISIBILITY_THRESHOLDS,
	psyker_shout = PSYKER_SHOUT_THRESHOLDS,
	psyker_overcharge_stance = PSYKER_STANCE_THRESHOLDS,
	ogryn_charge = OGRYN_CHARGE_THRESHOLDS,
	ogryn_charge_increased_distance = OGRYN_CHARGE_THRESHOLDS,
	ogryn_taunt_shout = OGRYN_TAUNT_THRESHOLDS,
	ogryn_gunlugger_stance = OGRYN_GUNLUGGER_THRESHOLDS,
	adamant_stance = ADAMANT_STANCE_THRESHOLDS,
	adamant_charge = ADAMANT_CHARGE_THRESHOLDS,
	adamant_shout = ADAMANT_SHOUT_THRESHOLDS,
}

local ITEM_THRESHOLDS = {
	zealot_relic = ZEALOT_RELIC_THRESHOLDS,
	psyker_force_field = FORCE_FIELD_THRESHOLDS,
	psyker_force_field_improved = FORCE_FIELD_THRESHOLDS,
	psyker_force_field_dome = FORCE_FIELD_THRESHOLDS,
	adamant_area_buff_drone = DRONE_THRESHOLDS,
}

local ITEM_HEURISTICS = {
	zealot_relic = _can_activate_zealot_relic,
	psyker_force_field = _can_activate_force_field,
	psyker_force_field_improved = _can_activate_force_field,
	psyker_force_field_dome = _can_activate_force_field,
	adamant_area_buff_drone = _can_activate_drone,
	broker_ability_stimm_field = _can_activate_stimm_field,
}

local GRENADE_HORDE_PRESETS = {
	aggressive = { nearby_offset = -1, challenge_offset = -0.5 },
	balanced = { nearby_offset = 0, challenge_offset = 0 },
	conservative = { nearby_offset = 1, challenge_offset = 0.5 },
}

local GRENADE_PRIORITY_PRESETS = {
	aggressive = { distance_offset = -1 },
	balanced = { distance_offset = 0 },
	conservative = { distance_offset = 1 },
}

local GRENADE_DEFENSIVE_PRESETS = {
	aggressive = { toughness_offset = 0.10, count_offset = -1 },
	balanced = { toughness_offset = 0, count_offset = 0 },
	conservative = { toughness_offset = -0.10, count_offset = 1 },
}

local GRENADE_MINE_PRESETS = {
	aggressive = { elite_offset = -1, density_offset = -1 },
	balanced = { elite_offset = 0, density_offset = 0 },
	conservative = { elite_offset = 1, density_offset = 1 },
}

local CHAIN_LIGHTNING_THRESHOLDS = {
	aggressive = { crowd = 3, mixed_nearby = 2 },
	balanced = { crowd = 4, mixed_nearby = 3 },
	conservative = { crowd = 5, mixed_nearby = 4 },
}

local function _grenade_blocked_by_melee_engagement(context, rule_prefix, opts)
	opts = opts or {}

	if opts.skip_melee_engagement_block then
		return false, nil
	end

	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 4 then
		return true, rule_prefix .. "_block_melee_range"
	end

	return false, nil
end

local function _grenade_horde(context, min_nearby, min_challenge, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_HORDE_PRESETS[preset] or GRENADE_HORDE_PRESETS.balanced
	local interaction_offset = context.ally_interacting and 1 or 0
	local adj_nearby = min_nearby + t.nearby_offset - interaction_offset
	local adj_challenge = min_challenge + t.challenge_offset
	if context.num_nearby >= adj_nearby and context.challenge_rating_sum >= adj_challenge then
		return true, rule_prefix .. "_horde"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_priority_target(context, rule_prefix, opts, preset)
	opts = opts or {}

	-- #17: refuse any priority-target grenade/blitz against a dormant
	-- daemonhost. target_is_dormant_daemonhost is only true when avoidance
	-- is enabled AND the DH has not yet aggroed (aggro lifts globally).
	if
		context.target_is_dormant_daemonhost
		and _is_daemonhost_avoidance_enabled
		and _is_daemonhost_avoidance_enabled()
	then
		return false, rule_prefix .. "_block_dormant_daemonhost"
	end

	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix, opts)
	if blocked then
		return false, blocked_rule
	end

	if opts.max_peril and context.peril_pct and context.peril_pct >= opts.max_peril then
		return false, rule_prefix .. "_block_peril"
	end

	if opts.block_super_armor and context.target_is_super_armor then
		return false, rule_prefix .. "_block_super_armor"
	end

	local target_distance = context.target_enemy_distance or 0
	local t = GRENADE_PRIORITY_PRESETS[preset] or GRENADE_PRIORITY_PRESETS.balanced
	local min_distance = (opts.min_distance or 0) + t.distance_offset
	local has_priority_target = _is_monster_signal_allowed(context)
		or context.target_is_elite_special
		or context.priority_target_enemy ~= nil
		or context.opportunity_target_enemy ~= nil
		or context.urgent_target_enemy ~= nil

	if has_priority_target and not opts.skip_priority_melee_pressure_block and context.num_nearby >= 4 then
		return false, rule_prefix .. "_block_priority_melee_pressure"
	end

	if has_priority_target and target_distance >= min_distance then
		return true, rule_prefix .. "_priority_target"
	end

	if (context.elite_count + context.special_count + context.monster_count) >= 1 then
		return true, rule_prefix .. "_priority_pack"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_defensive(context, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_DEFENSIVE_PRESETS[preset] or GRENADE_DEFENSIVE_PRESETS.balanced
	local interaction_offset = context.ally_interacting and 1 or 0
	if context.target_ally_needs_aid and context.num_nearby >= 2 then
		return true, rule_prefix .. "_ally_aid"
	end

	local ranged_threshold = math.max(1, 2 + t.count_offset - interaction_offset)
	if context.ranged_count >= ranged_threshold and context.toughness_pct < (0.50 + t.toughness_offset) then
		return true, rule_prefix .. "_pressure"
	end

	local melee_threshold = math.max(2, 4 + t.count_offset - interaction_offset)
	if context.num_nearby >= melee_threshold and context.toughness_pct < (0.35 + t.toughness_offset) then
		return true, rule_prefix .. "_pressure"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_mine(context, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_MINE_PRESETS[preset] or GRENADE_MINE_PRESETS.balanced
	local interaction_offset = context.ally_interacting and 1 or 0
	if context.elite_count >= (3 + t.elite_offset) then
		return true, rule_prefix .. "_elite_pack"
	end

	if context.num_nearby >= (5 + t.density_offset - interaction_offset) and context.challenge_rating_sum >= 3.0 then
		return true, rule_prefix .. "_hold_point"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_whistle(context)
	if not context.companion_unit or not context.companion_position then
		return false, "grenade_whistle_block_no_companion"
	end

	if not context.target_enemy or not context.target_enemy_position then
		return false, "grenade_whistle_block_no_target"
	end

	if
		Vector3.distance_squared(context.companion_position, context.target_enemy_position)
		> WHISTLE_MAX_COMPANION_DISTANCE_SQ
	then
		return false, "grenade_whistle_block_companion_far"
	end

	if context.target_is_elite_special or context.priority_target_enemy or context.urgent_target_enemy then
		return true, "grenade_whistle_priority_target"
	end

	if (context.elite_count + context.special_count) >= 1 then
		return true, "grenade_whistle_priority_pack"
	end

	return false, "grenade_whistle_hold"
end

local function _grenade_smite(context)
	return _grenade_priority_target(context, "grenade_smite", {
		max_peril = 0.85,
		min_distance = 5,
		skip_melee_engagement_block = true,
		skip_priority_melee_pressure_block = true,
	}, context.preset)
end

local function _grenade_assail(context)
	-- #17: refuse assail against dormant daemonhost — the projectile is
	-- ballistic, so "aim" is enough to consume a charge on a DH.
	if
		context.target_is_dormant_daemonhost
		and _is_daemonhost_avoidance_enabled
		and _is_daemonhost_avoidance_enabled()
	then
		return false, "grenade_assail_block_dormant_daemonhost"
	end

	if context.peril_pct and context.peril_pct >= 0.85 then
		return false, "grenade_assail_block_peril"
	end

	if context.target_is_super_armor then
		return false, "grenade_assail_block_super_armor"
	end

	local target_distance = context.target_enemy_distance or 0
	local has_priority_target = _is_monster_signal_allowed(context)
		or context.target_is_elite_special
		or context.priority_target_enemy ~= nil
		or context.opportunity_target_enemy ~= nil
		or context.urgent_target_enemy ~= nil

	if has_priority_target then
		return true, "grenade_assail_priority_target"
	end

	if context.target_enemy_type == "ranged" or context.ranged_count >= 2 then
		return true, "grenade_assail_ranged_pressure"
	end

	if context.ranged_count >= 1 and target_distance >= 8 then
		return true, "grenade_assail_ranged_pressure"
	end

	if (context.elite_count + context.special_count + context.monster_count) >= 1 then
		return true, "grenade_assail_priority_pack"
	end

	if context.num_nearby >= 4 and context.challenge_rating_sum >= 2.0 then
		return true, "grenade_assail_crowd_soften"
	end

	return false, "grenade_assail_hold"
end

local function _grenade_chain_lightning(context)
	if context.peril_pct and context.peril_pct >= 0.85 then
		return false, "grenade_chain_lightning_block_peril"
	end

	local t = CHAIN_LIGHTNING_THRESHOLDS[context.preset] or CHAIN_LIGHTNING_THRESHOLDS.balanced
	local interaction_offset = context.ally_interacting and 1 or 0
	if context.num_nearby >= t.crowd - interaction_offset then
		return true, "grenade_chain_lightning_crowd"
	end

	if
		context.num_nearby >= t.mixed_nearby - interaction_offset
		and (context.elite_count + context.special_count) >= 1
	then
		return true, "grenade_chain_lightning_crowd"
	end

	return false, "grenade_chain_lightning_hold"
end

local GRENADE_HEURISTICS = {
	veteran_frag_grenade = function(context)
		return _grenade_horde(context, 6, 2.5, "grenade_frag", context.preset)
	end,
	veteran_krak_grenade = function(context)
		return _grenade_priority_target(context, "grenade_krak", { min_distance = 4 }, context.preset)
	end,
	veteran_smoke_grenade = function(context)
		return _grenade_defensive(context, "grenade_smoke", context.preset)
	end,
	zealot_fire_grenade = function(context)
		return _grenade_horde(context, 5, 2.5, "grenade_fire", context.preset)
	end,
	zealot_shock_grenade = function(context)
		return _grenade_defensive(context, "grenade_shock", context.preset)
	end,
	zealot_throwing_knives = function(context)
		return _grenade_priority_target(context, "grenade_knives", {
			min_distance = 5,
			skip_melee_engagement_block = true,
			skip_priority_melee_pressure_block = true,
		}, context.preset)
	end,
	ogryn_grenade_box = function(context)
		return _grenade_horde(context, 5, 3.0, "grenade_box", context.preset)
	end,
	ogryn_grenade_box_cluster = function(context)
		return _grenade_horde(context, 5, 3.0, "grenade_box_cluster", context.preset)
	end,
	ogryn_grenade_frag = function(context)
		return _grenade_horde(context, 5, 3.0, "grenade_ogryn_frag", context.preset)
	end,
	ogryn_grenade_friend_rock = function(context)
		return _grenade_priority_target(context, "grenade_rock", { min_distance = 6 }, context.preset)
	end,
	adamant_grenade = function(context)
		return _grenade_horde(context, 4, 2.0, "grenade_adamant", context.preset)
	end,
	adamant_grenade_improved = function(context)
		return _grenade_horde(context, 4, 2.0, "grenade_adamant", context.preset)
	end,
	adamant_shock_mine = function(context)
		return _grenade_mine(context, "grenade_shock_mine", context.preset)
	end,
	adamant_whistle = _grenade_whistle,
	broker_flash_grenade = function(context)
		return _grenade_defensive(context, "grenade_flash", context.preset)
	end,
	broker_flash_grenade_improved = function(context)
		return _grenade_defensive(context, "grenade_flash", context.preset)
	end,
	broker_tox_grenade = function(context)
		return _grenade_horde(context, 6, 3.0, "grenade_tox", context.preset)
	end,
	broker_missile_launcher = function(context)
		return _grenade_priority_target(context, "grenade_missile", { min_distance = 8 }, context.preset)
	end,
	psyker_throwing_knives = _grenade_assail,
	psyker_smite = _grenade_smite,
	psyker_chain_lightning = _grenade_chain_lightning,
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
	local preset = context.preset or "balanced"

	if ability_template_name == "veteran_combat_ability" then
		local identity = _resolve_combat_identity(ability_template_name, ability_extension)
		local vet_thresholds = VETERAN_STANCE_THRESHOLDS[preset] or VETERAN_STANCE_THRESHOLDS.balanced
		if identity.semantic_key == "veteran_combat_ability_shout" then
			vet_thresholds = VETERAN_VOC_THRESHOLDS[preset] or VETERAN_VOC_THRESHOLDS.balanced
		end
		return _can_activate_veteran_combat_ability(
			conditions,
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running,
			ability_extension,
			context,
			vet_thresholds
		)
	end

	local fn = TEMPLATE_HEURISTICS[ability_template_name]
	if not fn then
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = HEURISTIC_THRESHOLDS[ability_template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil

	return fn(context, thresholds)
end

local function _testing_profile_active(opts)
	if opts and opts.preset then
		return opts.preset == "testing"
	end
	if opts and opts.behavior_profile then
		return opts.behavior_profile == "testing"
	end

	return _is_testing_profile and _is_testing_profile() or false
end

local function _testing_profile_override(context)
	if not context then
		return false
	end

	if context.target_ally_needs_aid then
		return true, "testing_profile_ally_aid"
	end

	if _is_monster_signal_allowed(context) then
		return true, "testing_profile_monster"
	end

	if context.target_is_elite_special or context.special_count > 0 or context.elite_count > 0 then
		return true, "testing_profile_priority"
	end

	if context.num_nearby >= 2 then
		return true, "testing_profile_crowd"
	end

	if context.num_nearby >= 1 and (context.toughness_pct < 0.80 or context.health_pct < 0.80) then
		return true, "testing_profile_pressure"
	end

	return false
end

local function _testing_profile_can_override_rule(rule)
	if rule == nil then
		return true
	end

	rule = tostring(rule)

	if string.find(rule, "_hold", 1, true) then
		return true
	end

	if string.find(rule, "_block_safe", 1, true) then
		return true
	end

	if string.find(rule, "_block_low_value", 1, true) then
		return true
	end

	return false
end

local function _apply_behavior_profile(can_activate, rule, context, opts)
	if can_activate ~= false or not _testing_profile_active(opts) then
		return can_activate, rule
	end

	if not _testing_profile_can_override_rule(rule) then
		return can_activate, rule
	end

	local should_override, override_rule = _testing_profile_override(context)
	if not should_override then
		return can_activate, rule
	end

	if rule then
		return true, tostring(rule) .. "->" .. override_rule
	end

	return true, override_rule
end

-- Centralized decision evaluation with nil→fallback resolution.
-- Replaces the pattern previously duplicated in condition_patch._can_activate_ability
-- and ability_queue._fallback_try_queue_combat_ability.
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

	local profiled_can_activate, profiled_rule = _apply_behavior_profile(can_activate, rule, context)

	return profiled_can_activate, profiled_rule, context
end

-- Test-friendly entry point: evaluates a template heuristic against a pre-built
-- context table without touching engine state. For veteran_combat_ability, pass
-- opts.conditions and opts.ability_extension.
local function evaluate_heuristic(template_name, context, opts)
	opts = opts or {}
	local preset = opts.preset or context.preset or "balanced"
	local saved_preset = context.preset
	context.preset = preset

	if template_name == "veteran_combat_ability" then
		local identity = _resolve_combat_identity(template_name, opts.ability_extension)
		local tag = identity.class_tag
		local threshold_table = (tag == "squad_leader") and VETERAN_VOC_THRESHOLDS or VETERAN_STANCE_THRESHOLDS
		local thresholds = threshold_table[preset] or threshold_table.balanced

		local can_activate, rule = _can_activate_veteran_combat_ability(
			opts.conditions or {},
			opts.unit,
			nil,
			nil,
			nil,
			nil,
			false,
			opts.ability_extension,
			context,
			thresholds
		)

		context.preset = saved_preset
		return _apply_behavior_profile(can_activate, rule, context, opts)
	end

	local fn = TEMPLATE_HEURISTICS[template_name]
	if not fn then
		context.preset = saved_preset
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = HEURISTIC_THRESHOLDS[template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
	local can_activate, rule = fn(context, thresholds)
	context.preset = saved_preset
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

local function evaluate_item_heuristic(ability_name, context, opts)
	local fn = ITEM_HEURISTICS[ability_name]
	if not fn then
		return false, "unknown_item_ability"
	end

	local preset = (opts and opts.preset) or context.preset or "balanced"
	local threshold_table = ITEM_THRESHOLDS[ability_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
	local can_activate, rule = fn(context, thresholds)
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

local function evaluate_grenade_heuristic(grenade_template_name, context, opts)
	if not context then
		return false, "grenade_no_context"
	end

	local preset = (opts and opts.preset) or context.preset or "balanced"
	local saved_preset = context.preset
	context.preset = preset

	-- Revalidation hysteresis: after the initial "throw" decision passed
	-- and the bot has already committed to the aim window, allow a single
	-- enemy's worth of slack on the density-based throw gates so brief
	-- dips in proximity count don't abort frags/bombs mid-arm. Veteran
	-- frag is the worst offender in the wild (JSONL shows every queued
	-- attempt landing on `blocked reason=revalidation`) because
	-- `_grenade_horde` hard-gates at `num_nearby >= 6` and the proximity
	-- count fluctuates across the ~0.5-1 s aim window. _grenade_priority_
	-- target templates (smite/knives/krak) don't gate on density so the
	-- relaxation is effectively a no-op for them.
	local relaxed_num_nearby = opts and opts.revalidation and type(context.num_nearby) == "number"
	local saved_num_nearby
	if relaxed_num_nearby then
		saved_num_nearby = context.num_nearby
		context.num_nearby = saved_num_nearby + 1
	end

	local fn = GRENADE_HEURISTICS[grenade_template_name]
	local can_activate, rule
	if fn then
		can_activate, rule = fn(context)
	elseif context.num_nearby > 0 then
		can_activate, rule = true, "grenade_generic"
	else
		can_activate, rule = false, "grenade_no_enemies"
	end

	if relaxed_num_nearby then
		context.num_nearby = saved_num_nearby
	end

	context.preset = saved_preset
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

return {
	init = function(deps)
		assert(deps.combat_ability_identity, "heuristics: combat_ability_identity dep required")
		_fixed_time = deps.fixed_time
		_decision_context_cache = deps.decision_context_cache
		_super_armor_breed_cache = deps.super_armor_breed_cache
		_armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
		_is_testing_profile = deps.is_testing_profile
		_resolve_preset = deps.resolve_preset
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_combat_ability_identity = deps.combat_ability_identity
		-- #17: daemonhost carve-out deps. Optional so unit tests that set
		-- context.target_is_dormant_daemonhost directly still work without
		-- wiring shared_rules or the setting lookup.
		_daemonhost_breed_names = deps.shared_rules and deps.shared_rules.DAEMONHOST_BREED_NAMES
		_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled or function()
			return true
		end

		_interacting_cache_t = nil
		_interacting_cache_side = nil
		for i = #_interacting_units, 1, -1 do
			_interacting_units[i] = nil
			_interacting_profiles[i] = nil
			_interacting_types[i] = nil
		end
	end,
	build_context = build_context,
	resolve_decision = resolve_decision,
	evaluate_heuristic = evaluate_heuristic,
	evaluate_item_heuristic = evaluate_item_heuristic,
	evaluate_grenade_heuristic = evaluate_grenade_heuristic,
	enemy_breed = _enemy_breed,
}
