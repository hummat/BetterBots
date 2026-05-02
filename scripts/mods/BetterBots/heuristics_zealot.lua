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

local HARD_ALLY_AID_TYPES = {
	knocked_down = true,
	ledge = true,
	netted = true,
	hogtied = true,
}

local function _has_talent(context, talent_name)
	local talents = context and context.talents
	return talents and talents[talent_name] ~= nil or false
end

local function _target_ally_needs_hard_aid(context)
	return context.target_ally_needs_aid == true and HARD_ALLY_AID_TYPES[context.target_ally_need_type] == true
end

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
	if _target_ally_needs_hard_aid(context) and (context.target_ally_distance or math.huge) > 3 then
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
	local martyrdom = _has_talent(context, "zealot_martyrdom")
	if context.num_nearby == 0 then
		return false, "zealot_stealth_block_no_enemies"
	end
	if
		(context.toughness_pct < thresholds.emergency_toughness and context.num_nearby >= 2)
		or (context.health_pct < thresholds.emergency_health and not martyrdom)
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
	if martyrdom and context.health_pct < thresholds.emergency_health then
		return false, "zealot_stealth_hold_martyrdom_low_health"
	end

	return false, "zealot_stealth_hold"
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

return {
	template_heuristics = {
		zealot_dash = _can_activate_zealot_dash,
		zealot_targeted_dash = _can_activate_zealot_dash,
		zealot_targeted_dash_improved = _can_activate_zealot_dash,
		zealot_targeted_dash_improved_double = _can_activate_zealot_dash,
		zealot_invisibility = _can_activate_zealot_invisibility,
	},
	heuristic_thresholds = {
		zealot_dash = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash_improved = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash_improved_double = ZEALOT_DASH_THRESHOLDS,
		zealot_invisibility = ZEALOT_INVISIBILITY_THRESHOLDS,
	},
	item_heuristics = {
		zealot_relic = _can_activate_zealot_relic,
	},
	item_thresholds = {
		zealot_relic = ZEALOT_RELIC_THRESHOLDS,
	},
}
