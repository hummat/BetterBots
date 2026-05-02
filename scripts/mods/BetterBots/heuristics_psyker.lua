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

local function _force_field_should_help_ally(context)
	if not context.target_ally_needs_aid then
		return false
	end
	if _target_ally_needs_hard_aid(context) then
		return true
	end
	return context.num_nearby >= 2
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

local function _has_talent(context, talent_name)
	local talents = context and context.talents

	if talents == nil then
		if _debug_log and _debug_enabled and _debug_enabled() and not _missing_talents_context_logged then
			_missing_talents_context_logged = true
			_debug_log(
				"missing_talents_context:psyker",
				0,
				"psyker heuristic context missing talents table; build-aware checks falling back to untuned defaults",
				nil,
				"debug"
			)
		end

		return false
	end

	return talents[talent_name] ~= nil
end

local function _resolve_shout_high_peril_threshold(context, thresholds)
	local high_peril = thresholds.high_peril
	local preserve_peril = false

	if
		_has_talent(context, "psyker_damage_based_on_warp_charge") or _has_talent(context, "psyker_warp_glass_cannon")
	then
		high_peril = high_peril + 0.10
		preserve_peril = true
	end

	if _has_talent(context, "psyker_shout_vent_warp_charge") then
		high_peril = high_peril + 0.05
		preserve_peril = true
	end

	return math.min(high_peril, 0.95), preserve_peril
end

local function _can_activate_psyker_shout(context, thresholds)
	if context.num_nearby == 0 then
		return false, "psyker_shout_block_no_enemies"
	end
	local high_peril_threshold, preserve_peril = _resolve_shout_high_peril_threshold(context, thresholds)
	if context.peril_pct and context.peril_pct >= high_peril_threshold then
		if preserve_peril then
			return true, "psyker_shout_high_peril_talent_aware"
		end
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
	if preserve_peril and context.peril_pct and context.peril_pct >= thresholds.high_peril then
		return false, "psyker_shout_hold_preserve_peril"
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

local function _resolve_psyker_stance_tuning(context, thresholds)
	local tuning = {
		threat_cr = thresholds.threat_cr,
		combat_density = thresholds.combat_density,
		bot_no_peril_combat_density = math.max(2, thresholds.combat_density),
		target_peril_floor = 0.35,
		target_peril_ceiling = 0.85,
		block_peril_floor = 0.20,
		block_peril_ceiling = 0.90,
		build_aggressive = false,
	}

	if
		_has_talent(context, "psyker_new_mark_passive")
		or _has_talent(context, "psyker_overcharge_weakspot_kill_bonuses")
	then
		tuning.threat_cr = math.max(2.0, tuning.threat_cr - 1.0)
		tuning.combat_density = math.max(1, tuning.combat_density - 1)
		tuning.build_aggressive = true
	end

	if _has_talent(context, "psyker_overcharge_reduced_warp_charge") then
		tuning.target_peril_ceiling = 0.90
		tuning.block_peril_ceiling = 0.95
	end

	if _has_talent(context, "psyker_overcharge_stance_infinite_casting") then
		tuning.target_peril_ceiling = 0.95
		tuning.block_peril_ceiling = 0.97
	end

	return tuning
end

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
	local tuning = _resolve_psyker_stance_tuning(context, thresholds)

	if
		not bot_no_peril
		and (context.peril_pct < tuning.block_peril_floor or context.peril_pct > tuning.block_peril_ceiling)
	then
		return false, "psyker_stance_block_peril_window"
	end
	if
		(context.opportunity_target_enemy or context.urgent_target_enemy)
		and (
			bot_no_peril
			or (context.peril_pct >= tuning.target_peril_floor and context.peril_pct <= tuning.target_peril_ceiling)
		)
	then
		if tuning.build_aggressive then
			return true, "psyker_stance_target_window_build"
		end
		return true, "psyker_stance_target_window"
	end
	if
		context.challenge_rating_sum >= tuning.threat_cr
		and (
			bot_no_peril
			or (context.peril_pct >= tuning.target_peril_floor and context.peril_pct <= tuning.target_peril_ceiling)
		)
	then
		if tuning.build_aggressive then
			return true, "psyker_stance_threat_window_build"
		end
		return true, "psyker_stance_threat_window"
	end
	if bot_no_peril and context.num_nearby >= tuning.bot_no_peril_combat_density then
		if tuning.build_aggressive then
			return true, "psyker_stance_combat_density_build"
		end
		return true, "psyker_stance_combat_density"
	end

	return false, "psyker_stance_hold"
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
	if _force_field_should_help_ally(context) then
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

return {
	init = function(deps)
		_debug_log = deps and deps.debug_log or nil
		_debug_enabled = deps and deps.debug_enabled or nil
		_missing_talents_context_logged = false
	end,
	template_heuristics = {
		psyker_shout = _can_activate_psyker_shout,
		psyker_overcharge_stance = _can_activate_psyker_stance,
	},
	heuristic_thresholds = {
		psyker_shout = PSYKER_SHOUT_THRESHOLDS,
		psyker_overcharge_stance = PSYKER_STANCE_THRESHOLDS,
	},
	item_heuristics = {
		psyker_force_field = _can_activate_force_field,
		psyker_force_field_improved = _can_activate_force_field,
		psyker_force_field_dome = _can_activate_force_field,
	},
	item_thresholds = {
		psyker_force_field = FORCE_FIELD_THRESHOLDS,
		psyker_force_field_improved = FORCE_FIELD_THRESHOLDS,
		psyker_force_field_dome = FORCE_FIELD_THRESHOLDS,
	},
}
