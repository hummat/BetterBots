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

local _is_monster_signal_allowed

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

return {
	init = function(deps)
		assert(deps.is_monster_signal_allowed, "heuristics_arbites: is_monster_signal_allowed dep required")
		_is_monster_signal_allowed = deps.is_monster_signal_allowed
	end,
	template_heuristics = {
		adamant_stance = _can_activate_adamant_stance,
		adamant_charge = _can_activate_adamant_charge,
		adamant_shout = _can_activate_adamant_shout,
	},
	heuristic_thresholds = {
		adamant_stance = ADAMANT_STANCE_THRESHOLDS,
		adamant_charge = ADAMANT_CHARGE_THRESHOLDS,
		adamant_shout = ADAMANT_SHOUT_THRESHOLDS,
	},
	item_heuristics = {
		adamant_area_buff_drone = _can_activate_drone,
	},
	item_thresholds = {
		adamant_area_buff_drone = DRONE_THRESHOLDS,
	},
}
