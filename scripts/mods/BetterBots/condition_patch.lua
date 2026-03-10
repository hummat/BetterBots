-- Condition patch: replaces bt_bot_conditions.can_activate_ability with
-- BetterBots' version that checks heuristics, guards, and rescue intent.
-- Also fixes should_vent_overheat hysteresis (#30).
local _mod
local _debug_log
local _fixed_time
local _is_suppressed
local _equipped_combat_ability_name

local _Heuristics
local _MetaData
local _Debug
local _EventLog

local _patched_bt_bot_conditions
local _patched_bt_conditions
local _rescue_intent
local _is_near_daemonhost

local DEBUG_SKIP_RELIC_LOG_INTERVAL_S
local CONDITIONS_PATCH_VERSION

local RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

local function _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	local ability_component_name = action_data.ability_component_name

	-- Fast path: keep running ability nodes alive (e.g. charge mid-lunge)
	if ability_component_name == scratchpad.ability_component_name then
		return true
	end

	-- Guards below only apply to NEW activations
	local behavior = blackboard and blackboard.behavior
	if behavior and behavior.current_interaction_unit ~= nil then
		return false
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		_debug_log(
			"suppress:" .. tostring(suppress_reason),
			_fixed_time(),
			"ability suppressed (" .. tostring(suppress_reason) .. ")"
		)
		return false
	end

	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component.template_name
	local fixed_t = _fixed_time()

	if ability_template_name == "none" then
		_debug_log(
			"none:" .. ability_component_name,
			fixed_t,
			"blocked " .. ability_component_name .. " (template_name=none)",
			DEBUG_SKIP_RELIC_LOG_INTERVAL_S
		)
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		_debug_log(
			"missing_template:" .. ability_template_name,
			fixed_t,
			"blocked missing template " .. ability_template_name
		)
		return false
	end

	local ability_meta_data = ability_template.ability_meta_data
	if not ability_meta_data then
		_debug_log(
			"missing_meta:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (no ability_meta_data)"
		)
		return false
	end

	local activation_data = ability_meta_data.activation
	if not activation_data then
		_debug_log(
			"missing_activation:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (no activation data)"
		)
		return false
	end

	local action_input = activation_data.action_input
	if not action_input then
		_debug_log(
			"missing_action_input:" .. ability_template_name,
			fixed_t,
			"blocked " .. ability_template_name .. " (activation.action_input missing)"
		)
		return false
	end

	local used_input = activation_data.used_input
	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local action_input_is_valid =
		ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)

	if not action_input_is_valid then
		_debug_log(
			"invalid_input:" .. ability_template_name .. ":" .. action_input,
			fixed_t,
			"blocked " .. ability_template_name .. " (invalid action_input=" .. tostring(action_input) .. ")"
		)
		return false
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

	return can_activate
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

	-- #17: suppress melee/ranged combat near non-aggroed daemonhosts.
	-- Wraps the original conditions so bots won't initiate attacks that
	-- could provoke a nearby daemonhost.
	if _is_near_daemonhost then
		local orig_bot_in_melee_range = conditions.bot_in_melee_range
		if orig_bot_in_melee_range then
			conditions.bot_in_melee_range = function(unit, ...)
				if _is_near_daemonhost(unit) then
					_debug_log(
						"dh_suppress_melee:" .. tostring(unit),
						_fixed_time(),
						"melee suppressed (daemonhost_nearby)"
					)
					return false
				end
				return orig_bot_in_melee_range(unit, ...)
			end
		end

		local orig_has_target_and_ammo = conditions.has_target_and_ammo_greater_than
		if orig_has_target_and_ammo then
			conditions.has_target_and_ammo_greater_than = function(unit, ...)
				if _is_near_daemonhost(unit) then
					_debug_log(
						"dh_suppress_ranged:" .. tostring(unit),
						_fixed_time(),
						"ranged suppressed (daemonhost_nearby)"
					)
					return false
				end
				return orig_has_target_and_ammo(unit, ...)
			end
		end
	end

	patched_set[conditions] = true

	_debug_log(
		"condition_patch:" .. patch_label .. ":" .. tostring(conditions),
		0,
		"patched " .. patch_label .. ".can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
	)
end

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_fixed_time = deps.fixed_time
	_is_suppressed = deps.is_suppressed
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_patched_bt_bot_conditions = deps.patched_bt_bot_conditions
	_patched_bt_conditions = deps.patched_bt_conditions
	_rescue_intent = deps.rescue_intent
	_is_near_daemonhost = deps.is_near_daemonhost
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = deps.DEBUG_SKIP_RELIC_LOG_INTERVAL_S
	CONDITIONS_PATCH_VERSION = deps.CONDITIONS_PATCH_VERSION
end

function M.wire(deps)
	_Heuristics = deps.Heuristics
	_MetaData = deps.MetaData
	_Debug = deps.Debug
	_EventLog = deps.EventLog
end

function M.can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
end

function M.rescue_intent()
	return _rescue_intent
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
