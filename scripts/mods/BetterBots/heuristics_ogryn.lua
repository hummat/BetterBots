local _debug_log
local _debug_enabled
local _missing_talents_context_logged = false

local HARD_ALLY_AID_TYPES = {
	knocked_down = true,
	ledge = true,
	netted = true,
	hogtied = true,
}

local function _target_ally_needs_hard_aid(context)
	return context.target_ally_needs_aid == true and HARD_ALLY_AID_TYPES[context.target_ally_need_type] == true
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
	if _target_ally_needs_hard_aid(context) and (context.target_ally_distance or math.huge) > 6 then
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

local function _has_talent(context, talent_name)
	local talents = context and context.talents

	if talents == nil then
		if _debug_log and _debug_enabled and _debug_enabled() and not _missing_talents_context_logged then
			_missing_talents_context_logged = true
			_debug_log(
				"missing_talents_context:ogryn",
				0,
				"ogryn heuristic context missing talents table; build-aware checks falling back to untuned defaults",
				nil,
				"debug"
			)
		end

		return false
	end

	return talents[talent_name] ~= nil
end

local function _resolve_ogryn_gunlugger_tuning(context, thresholds)
	local tuning = {
		block_melee_nearby = thresholds.block_melee_nearby,
		block_low_threat_cr = thresholds.block_low_threat_cr,
		high_threat_cr = thresholds.high_threat_cr,
		high_threat_max_enemies = thresholds.high_threat_max_enemies,
		min_target_distance = 4,
		commit_target_distance = 5,
		fire_shots = _has_talent(context, "ogryn_special_ammo_fire_shots"),
		armor_pen = _has_talent(context, "ogryn_special_ammo_armor_pen"),
		movement = _has_talent(context, "ogryn_special_ammo_movement"),
		toughness_regen = _has_talent(context, "ogryn_ranged_stance_toughness_regen"),
	}

	if tuning.movement then
		tuning.block_melee_nearby = tuning.block_melee_nearby + 1
		tuning.min_target_distance = 3
		tuning.commit_target_distance = 3
	end

	return tuning
end

local function _current_target_is_priority(context)
	return context and context.target_enemy ~= nil and context.target_enemy == context.priority_target_enemy
end

local function _can_activate_ogryn_gunlugger(context, thresholds)
	local target_distance = context.target_enemy_distance
	local tuning = _resolve_ogryn_gunlugger_tuning(context, thresholds)
	if context.num_nearby >= tuning.block_melee_nearby then
		return false, "ogryn_gunlugger_block_melee_pressure"
	end
	if target_distance and target_distance < tuning.min_target_distance then
		return false, "ogryn_gunlugger_block_target_too_close"
	end
	if
		tuning.armor_pen
		and target_distance
		and target_distance > tuning.commit_target_distance
		and context.num_nearby <= tuning.high_threat_max_enemies
		and (context.target_is_super_armor or context.target_is_monster or _current_target_is_priority(context))
	then
		return true, "ogryn_gunlugger_armor_pen_target"
	end
	if
		tuning.fire_shots
		and target_distance
		and target_distance > tuning.commit_target_distance
		and context.num_nearby >= 2
		and context.challenge_rating_sum >= tuning.block_low_threat_cr
	then
		return true, "ogryn_gunlugger_fire_shots_pressure"
	end
	if
		tuning.toughness_regen
		and target_distance
		and target_distance > tuning.commit_target_distance
		and context.toughness_pct < 0.60
		and context.target_enemy_type == "ranged"
		and context.challenge_rating_sum >= tuning.block_low_threat_cr
	then
		return true, "ogryn_gunlugger_toughness_regen_sustain"
	end
	if context.challenge_rating_sum < tuning.block_low_threat_cr then
		return false, "ogryn_gunlugger_block_low_threat"
	end
	if
		context.urgent_target_enemy
		and context.num_nearby <= 1
		and target_distance
		and target_distance > tuning.commit_target_distance
	then
		return true, "ogryn_gunlugger_urgent_target"
	end
	if
		context.target_enemy_type == "ranged"
		and target_distance
		and target_distance > tuning.commit_target_distance
		and (context.elite_count + context.special_count) >= 1
	then
		return true, "ogryn_gunlugger_ranged_pack"
	end
	if
		context.challenge_rating_sum >= tuning.high_threat_cr
		and target_distance
		and target_distance > tuning.commit_target_distance
		and context.num_nearby <= tuning.high_threat_max_enemies
	then
		return true, "ogryn_gunlugger_high_threat"
	end

	return false, "ogryn_gunlugger_hold"
end

return {
	init = function(deps)
		_debug_log = deps and deps.debug_log or nil
		_debug_enabled = deps and deps.debug_enabled or nil
		_missing_talents_context_logged = false
	end,
	template_heuristics = {
		ogryn_charge = _can_activate_ogryn_charge,
		ogryn_charge_increased_distance = _can_activate_ogryn_charge,
		ogryn_taunt_shout = _can_activate_ogryn_taunt,
		ogryn_gunlugger_stance = _can_activate_ogryn_gunlugger,
	},
	heuristic_thresholds = {
		ogryn_charge = OGRYN_CHARGE_THRESHOLDS,
		ogryn_charge_increased_distance = OGRYN_CHARGE_THRESHOLDS,
		ogryn_taunt_shout = OGRYN_TAUNT_THRESHOLDS,
		ogryn_gunlugger_stance = OGRYN_GUNLUGGER_THRESHOLDS,
	},
}
