-- Engagement leash: coherency-anchored combat engagement range (#47)
--
-- _allow_engage hook: extends vanilla engagement distances based on combat
-- context (already engaged, post-charge grace, target within 3m, ranged foray).
-- Hard cap: 25m (30m with always-in-coherency talent).
--
-- _is_in_engage_range hook: unconditionally normalizes the engage range to
-- the near-follow-position distance. Does not extend distances.

local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled
local _HumanLikeness
local _Heuristics

-- Coherency-derived constants
local BASE_LEASH = 12
local COHERENCY_STICKINESS_LIMIT = 20
local HARD_CAP = 25
local HARD_CAP_ALWAYS_COHERENCY = 30
local POST_CHARGE_GRACE_S = 4
local UNDER_ATTACK_RANGE_SQ = 9
local COHERENCY_RADIUS_MARGIN = 4
local DEFAULT_COHERENCY_RADIUS = 8
local COHERENCY_CACHE_REFRESH_S = 1

-- Per-bot state (weak-keyed on unit)
local _bot_state = setmetatable({}, { __mode = "k" })

-- Movement ability templates that trigger post-charge grace.
-- Only base template names — ability_component.template_name always reflects the
-- base ability_template, not talent variant names (e.g. zealot_targeted_dash → zealot_dash).
local MOVEMENT_ABILITIES = {
	zealot_dash = true,
	ogryn_charge = true,
	adamant_charge = true,
}

-- Special rules for Zealot coherency talents
local ALWAYS_COHERENCY_RULES = {
	"zealot_always_at_least_one_coherency",
	"zealot_always_at_least_two_coherency",
}

local function _get_or_create_state(unit)
	local state = _bot_state[unit]
	if not state then
		state = {
			charge_timestamp = -math.huge,
			coherency_radius = DEFAULT_COHERENCY_RADIUS,
			always_in_coherency = false,
			last_cache_t = 0,
		}
		_bot_state[unit] = state
	end
	return state
end

local function _refresh_coherency_cache(unit, state, t)
	if t - state.last_cache_t < COHERENCY_CACHE_REFRESH_S then
		return
	end
	state.last_cache_t = t

	local coherency_ext = ScriptUnit.has_extension(unit, "coherency_system")
	if coherency_ext and coherency_ext.current_radius then
		state.coherency_radius = coherency_ext:current_radius() or DEFAULT_COHERENCY_RADIUS
	else
		state.coherency_radius = DEFAULT_COHERENCY_RADIUS
	end

	local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
	if talent_ext and talent_ext.has_special_rule then
		state.always_in_coherency = false
		for _, rule_name in ipairs(ALWAYS_COHERENCY_RULES) do
			if talent_ext:has_special_rule(rule_name) then
				state.always_in_coherency = true
				break
			end
		end
	else
		state.always_in_coherency = false
	end
end

function M.compute_effective_leash(unit, target_unit, target_breed, already_engaged, t)
	local state = _get_or_create_state(unit)
	_refresh_coherency_cache(unit, state, t)

	local cap = state.always_in_coherency and HARD_CAP_ALWAYS_COHERENCY or HARD_CAP
	local base = math.max(BASE_LEASH, state.coherency_radius + COHERENCY_RADIUS_MARGIN)

	if t - state.charge_timestamp < POST_CHARGE_GRACE_S then
		return math.min(COHERENCY_STICKINESS_LIMIT, cap), "post_charge_grace"
	end

	if target_unit then
		local bot_pos = POSITION_LOOKUP and POSITION_LOOKUP[unit]
		local target_pos = POSITION_LOOKUP and POSITION_LOOKUP[target_unit]
		if bot_pos and target_pos and Vector3.distance_squared(bot_pos, target_pos) < UNDER_ATTACK_RANGE_SQ then
			return math.min(COHERENCY_STICKINESS_LIMIT, cap), "under_attack"
		end
	end

	if already_engaged then
		return math.min(COHERENCY_STICKINESS_LIMIT, cap), "already_engaged"
	end

	if target_unit and target_breed and target_breed.ranged then
		local enemy_bb = BLACKBOARDS and BLACKBOARDS[target_unit]
		local enemy_perception = enemy_bb and enemy_bb.perception
		if enemy_perception and enemy_perception.target_unit == unit then
			return math.min(COHERENCY_STICKINESS_LIMIT, cap), "ranged_foray"
		end
	end

	local effective = math.min(base, cap)
	if _HumanLikeness and _Heuristics then
		local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
		local context = blackboard and _Heuristics.build_context(unit, blackboard)
		local pressure = context and context.challenge_rating_sum or 0
		effective = _HumanLikeness.scale_engage_leash(effective, pressure)
	end

	local reason = (effective < math.min(base, cap)) and "pressure_scaled" or "base"
	return effective, reason
end

function M.should_extend_approach(unit, target_unit, target_breed, already_engaged, t)
	local _, reason = M.compute_effective_leash(unit, target_unit, target_breed, already_engaged, t)
	return reason ~= "base"
end

function M.record_charge(unit, t)
	local state = _get_or_create_state(unit)
	state.charge_timestamp = t

	if _debug_enabled() then
		_debug_log(
			"leash:charge_recorded:" .. tostring(unit),
			t,
			"post-charge grace started (" .. tostring(POST_CHARGE_GRACE_S) .. "s)",
			nil,
			"debug"
		)
	end
end

function M.is_movement_ability(template_name)
	return MOVEMENT_ABILITIES[template_name] == true
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_is_enabled = deps.is_enabled
	_HumanLikeness = deps.HumanLikeness
	_Heuristics = deps.Heuristics
end

-- Called from the consolidated bt_bot_melee_action hook_require in BetterBots.lua (#67).
function M.install_melee_hooks(BtBotMeleeAction)
	_mod:hook(
		BtBotMeleeAction,
		"_allow_engage",
		function(
			func,
			self,
			self_unit,
			target_unit,
			target_position,
			target_breed,
			scratchpad,
			action_data,
			already_engaged,
			aim_position,
			follow_position
		)
			if _is_enabled and not _is_enabled() then
				return func(
					self,
					self_unit,
					target_unit,
					target_position,
					target_breed,
					scratchpad,
					action_data,
					already_engaged,
					aim_position,
					follow_position
				)
			end

			if action_data.override_engage_range_to_follow_position == math.huge then
				return func(
					self,
					self_unit,
					target_unit,
					target_position,
					target_breed,
					scratchpad,
					action_data,
					already_engaged,
					aim_position,
					follow_position
				)
			end

			local perf_t0 = _perf and _perf.begin()
			local t = _fixed_time()
			local effective_leash, reason =
				M.compute_effective_leash(self_unit, target_unit, target_breed, already_engaged, t)

			local orig_override = action_data.override_engage_range_to_follow_position
			local orig_challenge = action_data.override_engage_range_to_follow_position_challenge
			action_data.override_engage_range_to_follow_position = effective_leash
			action_data.override_engage_range_to_follow_position_challenge = effective_leash

			local ok, result = pcall(
				func,
				self,
				self_unit,
				target_unit,
				target_position,
				target_breed,
				scratchpad,
				action_data,
				already_engaged,
				aim_position,
				follow_position
			)

			action_data.override_engage_range_to_follow_position = orig_override
			action_data.override_engage_range_to_follow_position_challenge = orig_challenge
			if perf_t0 then
				_perf.finish("engagement_leash._allow_engage", perf_t0)
			end

			if not ok then
				if _debug_enabled() then
					_debug_log(
						"leash_restore_error:" .. tostring(self_unit),
						t,
						"restored engagement leash overrides after vanilla error",
						nil,
						"info"
					)
				end
				error(result, 0)
			end

			if _debug_enabled() and reason ~= "base" then
				_debug_log(
					"leash:" .. reason .. ":" .. tostring(self_unit),
					t,
					"engagement leash "
						.. reason
						.. " → "
						.. effective_leash
						.. "m (was "
						.. orig_override
						.. "m) result="
						.. tostring(result)
				)
			end
			return result
		end
	)

	_mod:hook(
		BtBotMeleeAction,
		"_is_in_engage_range",
		function(func, self, self_position, target_position, action_data, follow_position)
			if _is_enabled and not _is_enabled() then
				return func(self, self_position, target_position, action_data, follow_position)
			end

			if action_data.engage_range == math.huge then
				return func(self, self_position, target_position, action_data, follow_position)
			end

			local orig_engage_range = action_data.engage_range
			local t = _fixed_time()
			action_data.engage_range = action_data.engage_range_near_follow_position

			local ok, result = pcall(func, self, self_position, target_position, action_data, follow_position)

			action_data.engage_range = orig_engage_range
			if not ok then
				if _debug_enabled() then
					_debug_log(
						"leash_range_restore_error:" .. tostring(action_data),
						t,
						"restored engagement range after vanilla error",
						nil,
						"info"
					)
				end
				error(result, 0)
			end
			return result
		end
	)
end

function M.register_hooks() end

M._CONSTANTS = {
	BASE_LEASH = BASE_LEASH,
	COHERENCY_STICKINESS_LIMIT = COHERENCY_STICKINESS_LIMIT,
	HARD_CAP = HARD_CAP,
	HARD_CAP_ALWAYS_COHERENCY = HARD_CAP_ALWAYS_COHERENCY,
	POST_CHARGE_GRACE_S = POST_CHARGE_GRACE_S,
	UNDER_ATTACK_RANGE_SQ = UNDER_ATTACK_RANGE_SQ,
	COHERENCY_RADIUS_MARGIN = COHERENCY_RADIUS_MARGIN,
	DEFAULT_COHERENCY_RADIUS = DEFAULT_COHERENCY_RADIUS,
}

M.MOVEMENT_ABILITIES = MOVEMENT_ABILITIES

return M
