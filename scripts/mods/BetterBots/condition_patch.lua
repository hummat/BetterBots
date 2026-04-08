-- Condition patch: replaces bt_bot_conditions.can_activate_ability with
-- BetterBots' version that checks heuristics, guards, and rescue intent.
-- Also fixes should_vent_overheat hysteresis (#30).
local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _is_suppressed
local _equipped_combat_ability_name

local _Heuristics
local _MetaData
local _Debug
local _EventLog
local _is_combat_template_enabled
local _perf
local _TeamCooldown

local _patched_bt_bot_conditions
local _patched_bt_conditions
local _rescue_intent

local DEBUG_SKIP_RELIC_LOG_INTERVAL_S
local CONDITIONS_PATCH_VERSION
local NORMAL_RANGED_AMMO_THRESHOLD = 0.5
local _bot_ranged_ammo_threshold

local DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

-- Returns true when the bot's current target_enemy is a non-aggroed
-- daemonhost. O(1) — no proximity scan needed since we only check
-- the single target the bot is already committed to attacking.
local function _is_dormant_daemonhost_target(_unit, blackboard) -- luacheck: ignore 212/_unit
	local perception = blackboard and blackboard.perception
	local target_enemy = perception and perception.target_enemy
	if not target_enemy or not ALIVE[target_enemy] then
		return false
	end

	local target_data_ext = ScriptUnit.has_extension(target_enemy, "unit_data_system")
	local breed = target_data_ext and target_data_ext:breed()
	if not (breed and DAEMONHOST_BREED_NAMES[breed.name]) then
		return false
	end

	local target_bb = BLACKBOARDS and BLACKBOARDS[target_enemy]
	local target_perception = target_bb and target_bb.perception
	if target_perception and target_perception.aggro_state == "aggroed" then
		return false
	end

	return true
end

local RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

local _action_input_is_bot_queueable

local function _return_with_perf(perf_t0, ...)
	if perf_t0 and _perf then
		_perf.finish("condition_patch.can_activate_ability", perf_t0)
	end

	return ...
end

local function _override_ranged_ammo_condition_args(unit, condition_args)
	if not condition_args or condition_args.ammo_percentage ~= NORMAL_RANGED_AMMO_THRESHOLD then
		return condition_args
	end

	local threshold = _bot_ranged_ammo_threshold and _bot_ranged_ammo_threshold() or 0.20
	local adjusted_args = {}
	for key, value in pairs(condition_args) do
		adjusted_args[key] = value
	end
	adjusted_args.ammo_percentage = threshold

	if _debug_enabled() then
		_debug_log(
			"ranged_ammo_threshold_override:" .. tostring(unit),
			_fixed_time(),
			"ranged ammo gate lowered from "
				.. string.format("%.0f%%", NORMAL_RANGED_AMMO_THRESHOLD * 100)
				.. " to "
				.. string.format("%.0f%%", threshold * 100),
			10
		)
	end

	return adjusted_args
end

local function _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	local perf_t0 = _perf and _perf.begin()
	local ability_component_name = action_data.ability_component_name

	-- Fast path: keep running ability nodes alive (e.g. charge mid-lunge)
	if ability_component_name == scratchpad.ability_component_name then
		return _return_with_perf(perf_t0, true)
	end

	-- Guards below only apply to NEW activations
	local behavior = blackboard and blackboard.behavior
	if behavior and behavior.current_interaction_unit ~= nil then
		return _return_with_perf(perf_t0, false)
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"suppress:" .. tostring(suppress_reason) .. ":" .. tostring(unit),
				_fixed_time(),
				"ability suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		if _debug_enabled() then
			_debug_log(
				"missing_ext:unit_data:" .. tostring(unit),
				_fixed_time(),
				"unit_data_system extension absent (stale unit?)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component.template_name
	local fixed_t = _fixed_time()

	if ability_template_name == "none" then
		if _debug_enabled() then
			_debug_log(
				"none:" .. ability_component_name,
				fixed_t,
				"blocked " .. ability_component_name .. " (template_name=none)",
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_extension then
		return _return_with_perf(perf_t0, false)
	end

	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		if _debug_enabled() then
			_debug_log(
				"disabled_template:" .. ability_template_name,
				fixed_t,
				"blocked " .. ability_template_name .. " (disabled by mod setting)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		if _debug_enabled() then
			_debug_log(
				"missing_template:" .. ability_template_name,
				fixed_t,
				"blocked missing template " .. ability_template_name
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local ability_meta_data = ability_template.ability_meta_data
	if not ability_meta_data then
		if _debug_enabled() then
			_debug_log(
				"missing_meta:" .. ability_template_name,
				fixed_t,
				"blocked " .. ability_template_name .. " (no ability_meta_data)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local activation_data = ability_meta_data.activation
	if not activation_data then
		if _debug_enabled() then
			_debug_log(
				"missing_activation:" .. ability_template_name,
				fixed_t,
				"blocked " .. ability_template_name .. " (no activation data)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local action_input = activation_data.action_input
	if not action_input then
		if _debug_enabled() then
			_debug_log(
				"missing_action_input:" .. ability_template_name,
				fixed_t,
				"blocked " .. ability_template_name .. " (activation.action_input missing)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local used_input = activation_data.used_input
	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		if _debug_enabled() then
			_debug_log(
				"missing_ext:action_input:" .. tostring(unit),
				_fixed_time(),
				"action_input_system extension absent (stale unit?)"
			)
		end
		return _return_with_perf(perf_t0, false)
	end
	local action_input_is_valid = _action_input_is_bot_queueable(
		action_input_extension,
		ability_extension,
		ability_component_name,
		ability_template_name,
		action_input,
		used_input,
		fixed_t
	)

	if not action_input_is_valid then
		if _debug_enabled() then
			_debug_log(
				"invalid_input:" .. ability_template_name .. ":" .. action_input,
				fixed_t,
				"blocked " .. ability_template_name .. " (invalid action_input=" .. tostring(action_input) .. ")"
			)
		end
		return _return_with_perf(perf_t0, false)
	end

	local can_activate, rule, context = _Heuristics.resolve_decision(
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

	if can_activate and rule and RESCUE_CHARGE_RULES[rule] then
		local perception = blackboard and blackboard.perception
		local ally_unit = perception and perception.target_ally
		if ally_unit then
			_rescue_intent[unit] = ally_unit
		end
	end

	if can_activate and _TeamCooldown then
		local team_suppressed, team_reason = _TeamCooldown.is_suppressed(unit, ability_template_name, fixed_t, rule)
		if team_suppressed then
			if _debug_enabled() then
				_debug_log(
					"team_cd:" .. ability_template_name .. ":" .. tostring(unit),
					fixed_t,
					"suppressed " .. ability_template_name .. " (" .. tostring(team_reason) .. ")"
				)
			end
			can_activate = false
			rule = "team_cooldown_suppressed"
		end
	end

	_Debug.log_ability_decision(ability_template_name, fixed_t, can_activate, rule, context)

	if _EventLog.is_enabled() then
		local bot_slot = _Debug.bot_slot_for_unit(unit)
		_EventLog.emit_decision(
			fixed_t,
			bot_slot,
			_equipped_combat_ability_name(unit),
			ability_template_name,
			can_activate,
			rule,
			"bt",
			context
		)
	end

	return _return_with_perf(perf_t0, can_activate)
end

local function _install_condition_patch(conditions, patched_set, patch_label)
	if not conditions or patched_set[conditions] then
		return
	end

	conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	end

	-- #30: fix should_vent_overheat hysteresis. Vanilla checks
	-- scratchpad.reloading which is never set (BtBotReloadAction sets
	-- scratchpad.is_reloading — key mismatch). Use is_running instead.
	if conditions.should_vent_overheat then
		local Overheat = require("scripts/utilities/overheat")
		conditions.should_vent_overheat = function(
			unit,
			blackboard,
			_scratchpad, -- luacheck: ignore 212
			condition_args,
			_action_data, -- luacheck: ignore 212
			is_running
		)
			local perception_component = blackboard.perception
			if perception_component.target_enemy_type == "melee" then
				return false
			end
			local overheat_percentage =
				Overheat.slot_percentage(unit, "slot_secondary", condition_args.overheat_limit_type)
			if is_running then
				return overheat_percentage >= condition_args.stop_percentage
			else
				return overheat_percentage >= condition_args.start_min_percentage
					and overheat_percentage <= condition_args.start_max_percentage
			end
		end
	end

	-- #17: suppress melee/ranged combat when the bot's current target IS a
	-- non-aggroed daemonhost. Target-specific (not proximity-based) so bots
	-- can still fight hordes/specials in mixed encounters near a sleeping DH.
	local orig_bot_in_melee_range = conditions.bot_in_melee_range
	if orig_bot_in_melee_range then
		conditions.bot_in_melee_range = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
			if _is_dormant_daemonhost_target(unit, blackboard) then
				if _debug_enabled() then
					_debug_log(
						"dh_suppress_melee:" .. tostring(unit),
						_fixed_time(),
						"melee suppressed (target is dormant daemonhost)"
					)
				end
				return false
			end
			return orig_bot_in_melee_range(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		end
	end

	local orig_has_target_and_ammo = conditions.has_target_and_ammo_greater_than
	if orig_has_target_and_ammo then
		conditions.has_target_and_ammo_greater_than = function(
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running
		)
			if _is_dormant_daemonhost_target(unit, blackboard) then
				if _debug_enabled() then
					_debug_log(
						"dh_suppress_ranged:" .. tostring(unit),
						_fixed_time(),
						"ranged suppressed (target is dormant daemonhost)"
					)
				end
				return false
			end
			local adjusted_args = _override_ranged_ammo_condition_args(unit, condition_args)
			local result =
				orig_has_target_and_ammo(unit, blackboard, scratchpad, adjusted_args, action_data, is_running)
			if result and adjusted_args ~= condition_args and _debug_enabled() then
				_debug_log(
					"ranged_ammo_override_active:" .. tostring(unit),
					_fixed_time(),
					"ranged permitted with lowered ammo gate (threshold="
						.. string.format("%.0f%%", adjusted_args.ammo_percentage * 100)
						.. ")",
					10
				)
			end
			return result
		end
	end

	patched_set[conditions] = true

	if _debug_enabled() then
		_debug_log(
			"condition_patch:" .. patch_label .. ":" .. tostring(conditions),
			0,
			"patched " .. patch_label .. ".can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
		)
	end
end

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_suppressed = deps.is_suppressed
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_patched_bt_bot_conditions = deps.patched_bt_bot_conditions
	_patched_bt_conditions = deps.patched_bt_conditions
	_rescue_intent = deps.rescue_intent
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = deps.DEBUG_SKIP_RELIC_LOG_INTERVAL_S
	CONDITIONS_PATCH_VERSION = deps.CONDITIONS_PATCH_VERSION
	_perf = deps.perf
	local shared_rules = deps.shared_rules or {}
	DAEMONHOST_BREED_NAMES = shared_rules.DAEMONHOST_BREED_NAMES or DAEMONHOST_BREED_NAMES
	RESCUE_CHARGE_RULES = shared_rules.RESCUE_CHARGE_RULES or RESCUE_CHARGE_RULES
	_action_input_is_bot_queueable = shared_rules.action_input_is_bot_queueable
end

function M.wire(deps)
	_Heuristics = deps.Heuristics
	_MetaData = deps.MetaData
	_Debug = deps.Debug
	_EventLog = deps.EventLog
	_is_combat_template_enabled = deps.is_combat_template_enabled
	_bot_ranged_ammo_threshold = deps.bot_ranged_ammo_threshold
	_TeamCooldown = deps.TeamCooldown
end

function M.can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
end

function M.rescue_intent()
	return _rescue_intent
end

-- Exposed for testing; not part of the public API.
M._install_condition_patch = _install_condition_patch
M._is_dormant_daemonhost_target = _is_dormant_daemonhost_target
function M._action_input_is_bot_queueable(...)
	return _action_input_is_bot_queueable(...)
end

function M.register_hooks()
	_mod:hook_require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions", function(conditions)
		_install_condition_patch(conditions, _patched_bt_bot_conditions, "bt_bot_conditions")
	end)

	_mod:hook_require("scripts/extension_systems/behavior/utilities/bt_conditions", function(conditions)
		_install_condition_patch(conditions, _patched_bt_conditions, "bt_conditions")
	end)

	-- Eagerly patch if conditions were already loaded.
	local function _try_patch_conditions_now(module_path, patched_set, patch_label)
		local ok, conditions_or_err = pcall(require, module_path)
		if not ok then
			_mod:echo(
				"BetterBots WARNING: condition patch failed for "
					.. patch_label
					.. " ("
					.. tostring(conditions_or_err)
					.. ")"
			)
			return
		end

		_install_condition_patch(conditions_or_err, patched_set, patch_label)
	end

	_try_patch_conditions_now(
		"scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions",
		_patched_bt_bot_conditions,
		"bt_bot_conditions"
	)
	_try_patch_conditions_now(
		"scripts/extension_systems/behavior/utilities/bt_conditions",
		_patched_bt_conditions,
		"bt_conditions"
	)
end

return M
