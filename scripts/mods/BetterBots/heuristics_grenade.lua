local _is_monster_signal_allowed
local _is_daemonhost_avoidance_enabled
local _warp_weapon_peril_threshold
local WHISTLE_MAX_COMPANION_DISTANCE_SQ = 10 * 10
local DEFAULT_ASSAIL_PERIL_THRESHOLD = 0.85

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

-- Bot policy, not a game-authored rule: reserve enough Assail shards for priority
-- use before spending them on horde softening. See docs/classes/psyker-tactics.md.
local ASSAIL_CROWD_MIN_CHARGES = {
	aggressive = 4,
	balanced = 5,
	conservative = 6,
}

-- Shared pacing window for non-explosive grenades so bots do not double-throw
-- defensive/disruption tools back-to-back. See docs/classes/psyker-tactics.md.
local NONEXPLOSIVE_GRENADE_REUSE_DELAY_S = {
	aggressive = 6,
	balanced = 8,
	conservative = 10,
}

local CHAIN_LIGHTNING_THRESHOLDS = {
	aggressive = { crowd = 3, mixed_nearby = 2 },
	balanced = { crowd = 4, mixed_nearby = 3 },
	conservative = { crowd = 5, mixed_nearby = 4 },
}

local SMITE_THRESHOLDS = {
	aggressive = { hard_min_distance = 4, priority_min_distance = 7, melee_pressure = 4 },
	balanced = { hard_min_distance = 5, priority_min_distance = 8, melee_pressure = 3 },
	conservative = { hard_min_distance = 6, priority_min_distance = 9, melee_pressure = 2 },
}

local function _has_talent(context, talent_name)
	local talents = context and context.talents or nil

	return type(talents) == "table" and talents[talent_name] ~= nil
end

local function _assail_peril_threshold()
	return _warp_weapon_peril_threshold and _warp_weapon_peril_threshold() or DEFAULT_ASSAIL_PERIL_THRESHOLD
end

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

local function _grenade_frag(context, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, "grenade_frag")
	if blocked then
		return false, blocked_rule
	end

	local horde_ok, horde_rule = _grenade_horde(context, 6, 2.5, "grenade_frag", preset)
	if horde_ok then
		return true, horde_rule
	end

	local elite_pressure = (context.elite_count or 0) + (context.special_count or 0)
	local pressure_challenge = _has_talent(context, "veteran_grenade_apply_bleed") and 4.0 or 4.5

	if
		elite_pressure >= 2
		and context.num_nearby >= 3
		and context.challenge_rating_sum >= pressure_challenge
		and (context.target_enemy_distance or 0) >= 6
	then
		return true, "grenade_frag_pressure"
	end

	return false, horde_rule
end

local function _grenade_ogryn_frag(context)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, "grenade_ogryn_frag")
	if blocked then
		return false, blocked_rule
	end

	local target_distance = context.target_enemy_distance or 0
	if _is_monster_signal_allowed(context) and target_distance >= 6 then
		return true, "grenade_ogryn_frag_monster"
	end

	local priority_pressure = (context.elite_count or 0) + (context.special_count or 0) + (context.monster_count or 0)
	if
		priority_pressure >= 3
		and context.num_nearby >= 4
		and context.challenge_rating_sum >= 5.0
		and target_distance >= 6
	then
		return true, "grenade_ogryn_frag_priority_pack"
	end

	return false, "grenade_ogryn_frag_hold"
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

local function _grenade_disruption(context, rule_prefix, opts, preset)
	opts = opts or {}

	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local interaction_offset = context.ally_interacting and 1 or 0
	local target_distance = context.target_enemy_distance or 0
	local priority_pressure = (context.elite_count or 0) + (context.special_count or 0)
	local pack_nearby = math.max(2, (opts.pack_nearby or 4) - interaction_offset)
	local pack_challenge = opts.pack_challenge or 3.5
	local min_distance = opts.min_distance or 6

	if
		priority_pressure >= (opts.pack_targets or 2)
		and context.num_nearby >= pack_nearby
		and context.challenge_rating_sum >= pack_challenge
		and target_distance >= min_distance
	then
		return true, rule_prefix .. "_interrupt_pack"
	end

	local target_nearby = math.max(2, (opts.target_nearby or 3) - interaction_offset)
	if context.target_is_elite_special and context.num_nearby >= target_nearby and target_distance >= min_distance then
		return true, rule_prefix .. "_interrupt_target"
	end

	local crowd_nearby = math.max(3, (opts.crowd_nearby or 6) - interaction_offset)
	if context.num_nearby >= crowd_nearby and context.challenge_rating_sum >= (opts.crowd_challenge or 2.5) then
		return true, rule_prefix .. "_crowd"
	end

	return _grenade_defensive(context, rule_prefix, preset)
end

local function _grenade_denial(context, rule_prefix, min_nearby, min_challenge, opts, preset)
	opts = opts or {}

	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local target_distance = context.target_enemy_distance or 0
	local min_distance = opts.min_distance or 6
	if opts.use_monster and _is_monster_signal_allowed(context) and target_distance >= min_distance then
		return true, rule_prefix .. "_monster"
	end

	local interaction_offset = context.ally_interacting and 1 or 0
	local priority_pressure = (context.elite_count or 0) + (context.special_count or 0) + (context.monster_count or 0)
	local pack_nearby = math.max(3, (opts.pack_nearby or 4) - interaction_offset)
	if
		priority_pressure >= (opts.pack_targets or 2)
		and context.num_nearby >= pack_nearby
		and context.challenge_rating_sum >= (opts.pack_challenge or 4.0)
		and target_distance >= min_distance
	then
		return true, rule_prefix .. "_priority_pack"
	end

	local horde_ok, horde_rule = _grenade_horde(context, min_nearby, min_challenge, rule_prefix, preset)
	if horde_ok then
		return true, horde_rule
	end

	return false, horde_rule
end

local function _grenade_ogryn_box(context, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, "grenade_box")
	if blocked then
		return false, blocked_rule
	end

	local target_distance = context.target_enemy_distance or 0
	local priority_pressure = (context.elite_count or 0) + (context.special_count or 0)
	if
		priority_pressure >= 2
		and context.num_nearby >= 4
		and context.challenge_rating_sum >= 4.5
		and target_distance >= 8
	then
		return true, "grenade_box_priority_pack"
	end

	local horde_ok, horde_rule = _grenade_horde(context, 5, 3.0, "grenade_box", preset)
	if horde_ok then
		return true, horde_rule
	end

	return false, horde_rule
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
	-- Brain Burst is a long stationary charge. Treat it as a selective
	-- hard-target delete, not a generic "some priority target exists" blitz.
	if
		context.target_is_dormant_daemonhost
		and _is_daemonhost_avoidance_enabled
		and _is_daemonhost_avoidance_enabled()
	then
		return false, "grenade_smite_block_dormant_daemonhost"
	end

	if context.peril_pct and context.peril_pct >= 0.85 then
		return false, "grenade_smite_block_peril"
	end

	if not context.target_enemy then
		return false, "grenade_smite_hold"
	end

	local t = SMITE_THRESHOLDS[context.preset] or SMITE_THRESHOLDS.balanced
	local target_distance = context.target_enemy_distance or 0
	local is_hard_target = context.target_is_super_armor or _is_monster_signal_allowed(context)
	local is_explicit_priority_target = context.target_enemy == context.priority_target_enemy
		or context.target_enemy == context.opportunity_target_enemy
		or context.target_enemy == context.urgent_target_enemy
	local has_smite_on_hit = _has_talent(context, "psyker_smite_on_hit")

	if target_distance < t.hard_min_distance then
		return false, "grenade_smite_block_melee_range"
	end

	if context.num_nearby >= t.melee_pressure and not is_hard_target then
		return false, "grenade_smite_block_melee_pressure"
	end

	if context.target_is_super_armor and target_distance >= t.hard_min_distance then
		return true, "grenade_smite_super_armor"
	end

	if _is_monster_signal_allowed(context) and target_distance >= t.priority_min_distance then
		return true, "grenade_smite_monster"
	end

	if
		has_smite_on_hit
		and context.target_is_elite_special
		and not context.target_is_bomber
		and not context.target_is_super_armor
		and not _is_monster_signal_allowed(context)
		and not is_explicit_priority_target
	then
		return false, "grenade_smite_block_proc_cover"
	end

	if
		(context.target_is_elite_special or is_explicit_priority_target)
		and target_distance >= t.priority_min_distance
	then
		return true, "grenade_smite_priority_target"
	end

	return false, "grenade_smite_hold"
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

	if context.peril_pct and context.peril_pct >= _assail_peril_threshold() then
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
		local min_crowd_charges = ASSAIL_CROWD_MIN_CHARGES[context.preset] or ASSAIL_CROWD_MIN_CHARGES.balanced
		local charges_remaining = context.grenade_charges_remaining
		if charges_remaining == nil then
			return false, "grenade_assail_block_unknown_charges"
		end
		if charges_remaining < min_crowd_charges then
			return false, "grenade_assail_block_low_charges"
		end

		return true, "grenade_assail_crowd_soften"
	end

	return false, "grenade_assail_hold"
end

local function _block_recent_nonexplosive_grenade_use(context, rule_prefix, preset)
	local min_reuse_delay = NONEXPLOSIVE_GRENADE_REUSE_DELAY_S[preset] or NONEXPLOSIVE_GRENADE_REUSE_DELAY_S.balanced
	local since_last_charge = context.seconds_since_last_grenade_charge
	if since_last_charge ~= nil and since_last_charge < min_reuse_delay then
		return false, rule_prefix .. "_block_recent_use"
	end

	return true, nil
end

local function _grenade_fire(context, preset)
	local should_throw, rule = _grenade_horde(context, 5, 2.5, "grenade_fire", preset)
	if not should_throw then
		return false, rule
	end

	local allowed, blocked_rule = _block_recent_nonexplosive_grenade_use(context, "grenade_fire", preset)
	if not allowed then
		return false, blocked_rule
	end

	return true, rule
end

local function _grenade_defensive_nonexplosive(context, rule_prefix, preset)
	local should_throw, rule = _grenade_defensive(context, rule_prefix, preset)
	if not should_throw then
		return false, rule
	end

	local allowed, blocked_rule = _block_recent_nonexplosive_grenade_use(context, rule_prefix, preset)
	if not allowed then
		return false, blocked_rule
	end

	return true, rule
end

local function _grenade_disruption_nonexplosive(context, rule_prefix, opts, preset)
	local should_throw, rule = _grenade_disruption(context, rule_prefix, opts, preset)
	if not should_throw then
		return false, rule
	end

	local allowed, blocked_rule = _block_recent_nonexplosive_grenade_use(context, rule_prefix, preset)
	if not allowed then
		return false, blocked_rule
	end

	return true, rule
end

local function _grenade_mine_nonexplosive(context, rule_prefix, preset)
	local should_throw, rule = _grenade_mine(context, rule_prefix, preset)
	if not should_throw then
		return false, rule
	end

	local allowed, blocked_rule = _block_recent_nonexplosive_grenade_use(context, rule_prefix, preset)
	if not allowed then
		return false, blocked_rule
	end

	return true, rule
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

local BROKER_FLASH_DISRUPTION_OPTS = {
	pack_nearby = 4,
	pack_challenge = 3.5,
	crowd_nearby = 5,
	crowd_challenge = 2.5,
	min_distance = 6,
}

local GRENADE_HEURISTICS = {
	veteran_frag_grenade = function(context)
		return _grenade_frag(context, context.preset)
	end,
	veteran_krak_grenade = function(context)
		return _grenade_priority_target(context, "grenade_krak", { min_distance = 4 }, context.preset)
	end,
	veteran_smoke_grenade = function(context)
		return _grenade_defensive_nonexplosive(context, "grenade_smoke", context.preset)
	end,
	zealot_fire_grenade = function(context)
		return _grenade_fire(context, context.preset)
	end,
	zealot_shock_grenade = function(context)
		return _grenade_disruption_nonexplosive(context, "grenade_shock", {
			pack_nearby = 4,
			pack_challenge = 3.5,
			crowd_nearby = 5,
			crowd_challenge = 2.5,
			min_distance = 6,
		}, context.preset)
	end,
	zealot_throwing_knives = function(context)
		return _grenade_priority_target(context, "grenade_knives", {
			min_distance = 5,
			skip_melee_engagement_block = true,
			skip_priority_melee_pressure_block = true,
		}, context.preset)
	end,
	ogryn_grenade_box = function(context)
		return _grenade_ogryn_box(context, context.preset)
	end,
	ogryn_grenade_box_cluster = function(context)
		return _grenade_horde(context, 5, 3.0, "grenade_box_cluster", context.preset)
	end,
	ogryn_grenade_frag = _grenade_ogryn_frag,
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
		return _grenade_mine_nonexplosive(context, "grenade_shock_mine", context.preset)
	end,
	adamant_whistle = _grenade_whistle,
	broker_flash_grenade = function(context)
		return _grenade_disruption_nonexplosive(context, "grenade_flash", BROKER_FLASH_DISRUPTION_OPTS, context.preset)
	end,
	broker_flash_grenade_improved = function(context)
		return _grenade_disruption_nonexplosive(context, "grenade_flash", BROKER_FLASH_DISRUPTION_OPTS, context.preset)
	end,
	broker_tox_grenade = function(context)
		return _grenade_denial(context, "grenade_tox", 6, 3.0, {
			use_monster = true,
			pack_targets = 2,
			pack_nearby = 4,
			pack_challenge = 4.0,
			min_distance = 6,
		}, context.preset)
	end,
	broker_missile_launcher = function(context)
		return _grenade_priority_target(context, "grenade_missile", { min_distance = 8 }, context.preset)
	end,
	psyker_throwing_knives = _grenade_assail,
	psyker_smite = _grenade_smite,
	psyker_chain_lightning = _grenade_chain_lightning,
}

return {
	init = function(deps)
		assert(deps.is_monster_signal_allowed, "heuristics_grenade: is_monster_signal_allowed dep required")
		_is_monster_signal_allowed = deps.is_monster_signal_allowed
		_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled or function()
			return true
		end
		_warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold
	end,
	grenade_heuristics = GRENADE_HEURISTICS,
}
