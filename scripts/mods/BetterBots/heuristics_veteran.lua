local _combat_ability_identity

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

return {
	init = function(deps)
		assert(deps.combat_ability_identity, "heuristics_veteran: combat_ability_identity dep required")
		_combat_ability_identity = deps.combat_ability_identity
	end,
	template_heuristics = {
		veteran_stealth_combat_ability = _can_activate_veteran_stealth,
	},
	heuristic_thresholds = {
		veteran_stealth_combat_ability = VETERAN_STEALTH_THRESHOLDS,
	},
	evaluate_veteran_combat_ability = function(
		conditions,
		unit,
		blackboard,
		scratchpad,
		condition_args,
		action_data,
		is_running,
		ability_extension,
		context,
		preset
	)
		local identity = _resolve_combat_identity("veteran_combat_ability", ability_extension)
		local threshold_table = (identity.semantic_key == "veteran_combat_ability_shout") and VETERAN_VOC_THRESHOLDS
			or VETERAN_STANCE_THRESHOLDS
		local thresholds = threshold_table[preset] or threshold_table.balanced

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
			thresholds
		)
	end,
}
