local _is_testing_profile
local _context_module
local _veteran_module
local _is_monster_signal_allowed
local _fixed_time
local _debug_log
local _debug_enabled
local _resolve_decision_cache
local _resolve_decision_cache_hits_logged
local _template_heuristics = {}
local _heuristic_thresholds = {}
local _item_heuristics = {}
local _item_thresholds = {}
local _grenade_heuristics = {}

local function _merge_into(dst, src)
	for key, value in pairs(src or {}) do
		dst[key] = value
	end
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

	if _is_monster_signal_allowed and _is_monster_signal_allowed(context) then
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

local function _log_resolve_decision_cache_hit(unit, ability_template_name, fixed_t)
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
		return
	end

	local logged_for_unit = _resolve_decision_cache_hits_logged and _resolve_decision_cache_hits_logged[unit]
	if not logged_for_unit then
		logged_for_unit = {}
		_resolve_decision_cache_hits_logged[unit] = logged_for_unit
	end

	if logged_for_unit[ability_template_name] then
		return
	end

	logged_for_unit[ability_template_name] = true
	_debug_log(
		"resolve_decision_cache_hit:" .. ability_template_name .. ":" .. tostring(unit),
		fixed_t or 0,
		"resolve_decision cache hit " .. tostring(ability_template_name) .. " (unit=" .. tostring(unit) .. ")",
		nil,
		"debug"
	)
end

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
		return _veteran_module.evaluate_veteran_combat_ability(
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
	end

	local fn = _template_heuristics[ability_template_name]
	if not fn then
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = _heuristic_thresholds[ability_template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil

	return fn(context, thresholds)
end

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
	local fixed_t = _fixed_time and _fixed_time() or nil
	if fixed_t ~= nil and _resolve_decision_cache then
		local cache_entry = _resolve_decision_cache[unit]
		if not cache_entry or cache_entry.fixed_t ~= fixed_t then
			cache_entry = {
				fixed_t = fixed_t,
				results = {},
			}
			_resolve_decision_cache[unit] = cache_entry
		end

		-- Cache at template granularity only. That is sufficient for the current
		-- BT/fallback duplication because the heuristic dispatch is driven by the
		-- template plus the per-frame build_context result. If future heuristics
		-- start depending on scratchpad/condition_args/action_data/is_running in a
		-- material way, this key must be widened or removed.
		local cached = cache_entry.results[ability_template_name]
		if cached then
			_log_resolve_decision_cache_hit(unit, ability_template_name, fixed_t)
			return cached.can_activate, cached.rule, cached.context
		end
	end

	local context = _context_module.build_context(unit, blackboard)
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

	if fixed_t ~= nil and _resolve_decision_cache then
		local cache_entry = _resolve_decision_cache[unit]
		cache_entry.results[ability_template_name] = {
			can_activate = profiled_can_activate,
			rule = profiled_rule,
			context = context,
		}
	end

	return profiled_can_activate, profiled_rule, context
end

local function evaluate_heuristic(template_name, context, opts)
	opts = opts or {}
	local preset = opts.preset or context.preset or "balanced"
	local saved_preset = context.preset
	context.preset = preset

	if template_name == "veteran_combat_ability" then
		local can_activate, rule = _veteran_module.evaluate_veteran_combat_ability(
			opts.conditions or {},
			opts.unit,
			nil,
			nil,
			nil,
			nil,
			false,
			opts.ability_extension,
			context,
			preset
		)

		context.preset = saved_preset
		return _apply_behavior_profile(can_activate, rule, context, opts)
	end

	local fn = _template_heuristics[template_name]
	if not fn then
		context.preset = saved_preset
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = _heuristic_thresholds[template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
	local can_activate, rule = fn(context, thresholds)
	context.preset = saved_preset
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

local function evaluate_item_heuristic(ability_name, context, opts)
	local fn = _item_heuristics[ability_name]
	if not fn then
		return false, "unknown_item_ability"
	end

	local preset = (opts and opts.preset) or context.preset or "balanced"
	local threshold_table = _item_thresholds[ability_name]
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

	local relaxed_num_nearby = opts and opts.revalidation and type(context.num_nearby) == "number"
	local saved_num_nearby
	if relaxed_num_nearby then
		saved_num_nearby = context.num_nearby
		context.num_nearby = saved_num_nearby + 1
	end

	local fn = _grenade_heuristics[grenade_template_name]
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
		assert(deps.context_module, "heuristics: context_module dep required")
		assert(deps.veteran_module, "heuristics: veteran_module dep required")
		assert(deps.zealot_module, "heuristics: zealot_module dep required")
		assert(deps.psyker_module, "heuristics: psyker_module dep required")
		assert(deps.ogryn_module, "heuristics: ogryn_module dep required")
		assert(deps.arbites_module, "heuristics: arbites_module dep required")
		assert(deps.hive_scum_module, "heuristics: hive_scum_module dep required")
		assert(deps.grenade_module, "heuristics: grenade_module dep required")

		_is_testing_profile = deps.is_testing_profile
		_context_module = deps.context_module
		_veteran_module = deps.veteran_module
		_fixed_time = deps.fixed_time
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_resolve_decision_cache = deps.resolve_decision_cache or {}
		_resolve_decision_cache_hits_logged = deps.resolve_decision_cache_hits_logged or {}

		_context_module.init({
			fixed_time = deps.fixed_time,
			decision_context_cache = deps.decision_context_cache,
			super_armor_breed_cache = deps.super_armor_breed_cache,
			ARMOR_TYPE_SUPER_ARMOR = deps.ARMOR_TYPE_SUPER_ARMOR,
			resolve_preset = deps.resolve_preset,
			debug_log = deps.debug_log,
			debug_enabled = deps.debug_enabled,
			shared_rules = deps.shared_rules,
			is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled,
		})

		if deps.psyker_module.init then
			deps.psyker_module.init({
				debug_log = deps.debug_log,
				debug_enabled = deps.debug_enabled,
			})
		end

		if deps.ogryn_module.init then
			deps.ogryn_module.init({
				debug_log = deps.debug_log,
				debug_enabled = deps.debug_enabled,
			})
		end

		_veteran_module.init({
			combat_ability_identity = deps.combat_ability_identity,
		})

		deps.arbites_module.init({
			is_monster_signal_allowed = _context_module.is_monster_signal_allowed,
		})

		deps.grenade_module.init({
			is_monster_signal_allowed = _context_module.is_monster_signal_allowed,
			is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled,
			warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold,
		})

		_template_heuristics = {}
		_heuristic_thresholds = {}
		_item_heuristics = {}
		_item_thresholds = {}
		_grenade_heuristics = {}

		_merge_into(_template_heuristics, _veteran_module.template_heuristics)
		_merge_into(_template_heuristics, deps.zealot_module.template_heuristics)
		_merge_into(_template_heuristics, deps.psyker_module.template_heuristics)
		_merge_into(_template_heuristics, deps.ogryn_module.template_heuristics)
		_merge_into(_template_heuristics, deps.arbites_module.template_heuristics)
		_merge_into(_template_heuristics, deps.hive_scum_module.template_heuristics)

		_merge_into(_heuristic_thresholds, _veteran_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.zealot_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.psyker_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.ogryn_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.arbites_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.hive_scum_module.heuristic_thresholds)

		_merge_into(_item_heuristics, deps.zealot_module.item_heuristics)
		_merge_into(_item_heuristics, deps.psyker_module.item_heuristics)
		_merge_into(_item_heuristics, deps.arbites_module.item_heuristics)
		_merge_into(_item_heuristics, deps.hive_scum_module.item_heuristics)

		_merge_into(_item_thresholds, deps.zealot_module.item_thresholds)
		_merge_into(_item_thresholds, deps.psyker_module.item_thresholds)
		_merge_into(_item_thresholds, deps.arbites_module.item_thresholds)
		_merge_into(_item_thresholds, deps.hive_scum_module.item_thresholds)

		_merge_into(_grenade_heuristics, deps.grenade_module.grenade_heuristics)

		_is_monster_signal_allowed = _context_module.is_monster_signal_allowed
	end,
	build_context = function(...)
		return _context_module.build_context(...)
	end,
	normalize_grenade_context = function(...)
		return _context_module.normalize_grenade_context(...)
	end,
	resolve_decision = resolve_decision,
	evaluate_heuristic = evaluate_heuristic,
	evaluate_item_heuristic = evaluate_item_heuristic,
	evaluate_grenade_heuristic = evaluate_grenade_heuristic,
	enemy_breed = function(...)
		return _context_module.enemy_breed(...)
	end,
}
