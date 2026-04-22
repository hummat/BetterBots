local _fixed_time
local _decision_context_cache
local _super_armor_breed_cache
local _armor_type_super_armor
local _resolve_preset
local _debug_log
local _debug_enabled
local _daemonhost_breed_names
local _is_daemonhost_avoidance_enabled
local _daemonhost_state
local _overlapping_liquids = {}
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

local EMPTY_TALENTS = {}
local function _zero_stacks()
	return 0
end

local function _unit_is_alive(unit)
	if ALIVE ~= nil then
		local alive = ALIVE[unit]
		if alive ~= nil then
			return alive == true
		end
	end

	if Unit and Unit.alive then
		return Unit.alive(unit)
	end

	return false
end

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
		if _unit_is_alive(ally_unit) then
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

local function _copy_context(context)
	local copy = {}
	for key, value in pairs(context) do
		copy[key] = value
	end
	return copy
end

local function normalize_grenade_context(unit, context, target_unit)
	if not context or not target_unit or context.target_enemy == target_unit then
		return context
	end

	local normalized = _copy_context(context)
	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit] or nil
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[target_unit] or nil

	normalized.target_enemy = target_unit
	normalized.target_enemy_position = target_position
	normalized.target_enemy_distance = nil
	normalized.target_enemy_type = nil
	normalized.target_is_elite_special = false
	normalized.target_is_bomber = false
	normalized.target_is_monster = false
	normalized.target_is_dormant_daemonhost = false
	normalized.target_daemonhost_aggro_state = nil
	normalized.target_is_super_armor = false

	if unit_position and target_position and unit_position.x and target_position.x then
		local dx = target_position.x - unit_position.x
		local dy = target_position.y - unit_position.y
		local dz = target_position.z - unit_position.z
		normalized.target_enemy_distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local target_breed = _enemy_breed(target_unit)
	if not target_breed then
		return normalized
	end

	local tags = target_breed.tags
	normalized.target_is_elite_special = _is_tagged(tags, "elite") or _is_tagged(tags, "special")
	normalized.target_is_bomber = _is_tagged(tags, "bomber")
	normalized.target_is_monster = _is_tagged(tags, "monster")
	normalized.target_is_super_armor = _breed_has_super_armor(target_breed)

	if target_breed.ranged or target_breed.game_object_type == "minion_ranged" then
		normalized.target_enemy_type = "ranged"
	else
		normalized.target_enemy_type = "melee"
	end

	if _daemonhost_breed_names and _daemonhost_breed_names[target_breed.name] then
		local aggro_state, stage
		if _daemonhost_state then
			aggro_state, stage = _daemonhost_state(target_unit)
		else
			local target_bb = BLACKBOARDS and BLACKBOARDS[target_unit]
			local target_perception = target_bb and target_bb.perception
			aggro_state = target_perception and target_perception.aggro_state or nil
		end
		aggro_state = aggro_state or "missing"
		local is_aggroed = stage ~= nil and stage == 6 or aggro_state == "aggroed"
		normalized.target_is_dormant_daemonhost = not is_aggroed
		normalized.target_daemonhost_aggro_state = aggro_state
		normalized.target_daemonhost_stage = stage
	end

	return normalized
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
		target_is_bomber = false,
		target_is_monster = false,
		target_is_dormant_daemonhost = false,
		target_daemonhost_aggro_state = nil,
		target_daemonhost_stage = nil,
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
		talents = EMPTY_TALENTS,
		current_stacks = _zero_stacks,
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
			if companion_unit and _unit_is_alive(companion_unit) then
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

	-- F1: expose talent + buff state for heuristics. Vanilla bot stubs lack
	-- both extensions, so fall back to an empty talents table and a
	-- zero-returning current_stacks closure. Callers check context.talents[name]
	-- for presence (value is the talent tier) and context.current_stacks(name)
	-- for stacking buff counts.
	local talent_extension = ScriptUnit.has_extension(unit, "talent_system")
	if talent_extension and talent_extension.talents then
		context.talents = talent_extension:talents() or EMPTY_TALENTS
	end

	local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
	if buff_extension and buff_extension.current_stacks then
		context.current_stacks = function(buff_name)
			return buff_extension:current_stacks(buff_name) or 0
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
			context.target_is_bomber = _is_tagged(tags, "bomber")
			context.target_is_monster = _is_tagged(tags, "monster")
			context.target_is_super_armor = _breed_has_super_armor(target_breed)
			-- #17: flag dormant daemonhosts so monster-aware heuristics refuse
			-- to blitz them. Once DH transitions to aggroed (on anyone — a
			-- triggered daemonhost commits the whole group), dormancy lifts
			-- and normal combat resumes. Pre-aggro: trash is targeted via
			-- vanilla target selection even though no combat action should
			-- ensue — we must refuse at the heuristic layer.
			if _daemonhost_breed_names and _daemonhost_breed_names[target_breed.name] then
				local aggro_state, stage
				if _daemonhost_state then
					aggro_state, stage = _daemonhost_state(context.target_enemy)
				else
					local target_bb = BLACKBOARDS and BLACKBOARDS[context.target_enemy]
					local target_perception = target_bb and target_bb.perception
					aggro_state = target_perception and target_perception.aggro_state or nil
				end
				aggro_state = aggro_state or "missing"
				local is_aggroed = stage ~= nil and stage == 6 or aggro_state == "aggroed"
				context.target_is_dormant_daemonhost = not is_aggroed
				context.target_daemonhost_aggro_state = aggro_state
				context.target_daemonhost_stage = stage
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

return {
	init = function(deps)
		assert(deps.fixed_time, "heuristics_context: fixed_time dep required")
		assert(deps.decision_context_cache, "heuristics_context: decision_context_cache dep required")
		assert(deps.super_armor_breed_cache, "heuristics_context: super_armor_breed_cache dep required")
		assert(deps.ARMOR_TYPE_SUPER_ARMOR, "heuristics_context: ARMOR_TYPE_SUPER_ARMOR dep required")
		assert(deps.resolve_preset, "heuristics_context: resolve_preset dep required")
		assert(deps.debug_log, "heuristics_context: debug_log dep required")
		assert(deps.debug_enabled, "heuristics_context: debug_enabled dep required")
		assert(deps.shared_rules, "heuristics_context: shared_rules dep required")

		_fixed_time = deps.fixed_time
		_decision_context_cache = deps.decision_context_cache
		_super_armor_breed_cache = deps.super_armor_breed_cache
		_armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
		_resolve_preset = deps.resolve_preset
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_daemonhost_breed_names = deps.shared_rules and deps.shared_rules.DAEMONHOST_BREED_NAMES
		_daemonhost_state = deps.shared_rules and deps.shared_rules.daemonhost_state
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
	normalize_grenade_context = normalize_grenade_context,
	enemy_breed = _enemy_breed,
	is_monster_signal_allowed = _is_monster_signal_allowed,
}
