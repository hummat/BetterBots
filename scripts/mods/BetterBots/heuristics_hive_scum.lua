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

-- Hive Scum exports direct template/item heuristics only.
-- No per-preset threshold tables yet.

return {
	template_heuristics = {
		broker_focus = _can_activate_broker_focus,
		broker_punk_rage = _can_activate_broker_rage,
	},
	item_heuristics = {
		broker_ability_stimm_field = _can_activate_stimm_field,
	},
}
