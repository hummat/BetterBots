-- Ability queue: fallback combat ability activation that runs every
-- BotBehaviorExtension.update tick. Handles Tier 1/2 template-based
-- abilities and delegates to ItemFallback for Tier 3 item-based abilities.
local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _equipped_combat_ability
local _equipped_combat_ability_name
local _is_suppressed
local _fallback_state_by_unit
local _fallback_queue_dumped_by_key

local _Heuristics
local _MetaData
local _ItemFallback
local _Debug
local _EventLog
local _is_combat_template_enabled

local DEBUG_SKIP_RELIC_LOG_INTERVAL_S

local RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

local function _fallback_try_queue_combat_ability(unit, blackboard)
	local ability_component_name = "combat_ability_action"
	local fixed_t = _fixed_time()
	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component and ability_component.template_name
	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end

	if not ability_template_name or ability_template_name == "none" then
		if _debug_enabled() then
			_debug_log(
				"fallback_none:" .. tostring(unit),
				fixed_t,
				"fallback skipped "
					.. ability_component_name
					.. " (template_name=none, equipped="
					.. _equipped_combat_ability_name(unit)
					.. ")",
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S
			)
		end

		local ability_extension, combat_ability = _equipped_combat_ability(unit)
		if ability_extension then
			_ItemFallback.try_queue_item(
				unit,
				unit_data_extension,
				ability_extension,
				state,
				fixed_t,
				combat_ability,
				blackboard
			)
		end

		return
	end

	local ability_extension_for_gate = ScriptUnit.has_extension(unit, "ability_system")
	if
		_is_combat_template_enabled
		and not _is_combat_template_enabled(ability_template_name, ability_extension_for_gate)
	then
		if _debug_enabled() then
			_debug_log(
				"fallback_disabled_template:" .. ability_template_name,
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (disabled by mod setting)"
			)
		end
		return
	end

	if state.item_stage then
		_ItemFallback.reset_item_sequence_state(state)
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_template:" .. ability_template_name,
				fixed_t,
				"fallback blocked missing template " .. ability_template_name
			)
		end
		return
	end

	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data then
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_meta:" .. ability_template_name,
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (no ability_meta_data)"
			)
		end
		return
	end

	local activation_data = ability_meta_data and ability_meta_data.activation
	if not activation_data then
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_activation:" .. ability_template_name,
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (no activation data)"
			)
		end
		return
	end

	local action_input = activation_data and activation_data.action_input
	if not action_input then
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_action_input:" .. ability_template_name,
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (activation.action_input missing)"
			)
		end
		return
	end

	if state.active then
		if fixed_t >= state.hold_until then
			if state.wait_action_input and not state.wait_sent then
				local action_input_extension = state.action_input_extension
					or ScriptUnit.extension(unit, "action_input_system")
				action_input_extension:bot_queue_action_input(ability_component_name, state.wait_action_input, nil)
				state.wait_sent = true
			end

			state.active = nil
			state.hold_until = nil
			state.wait_action_input = nil
			state.wait_sent = nil
			state.next_try_t = fixed_t + 1.5
		end

		return
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	-- Guards: only block NEW activations (after state machine cleanup above)
	local behavior = blackboard and blackboard.behavior
	if behavior and behavior.current_interaction_unit ~= nil then
		return
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"fallback_suppress:" .. tostring(suppress_reason),
				fixed_t,
				"fallback ability suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return
	end

	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local used_input = activation_data.used_input
	local action_input_is_valid =
		ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)

	if not action_input_is_valid then
		if _debug_enabled() then
			_debug_log(
				"fallback_invalid_input:" .. ability_template_name .. ":" .. action_input,
				fixed_t,
				"fallback blocked "
					.. ability_template_name
					.. " (invalid action_input="
					.. tostring(action_input)
					.. ")"
			)
		end
		return
	end

	local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
	local can_activate, rule, context = _Heuristics.resolve_decision(
		ability_template_name,
		conditions,
		unit,
		blackboard,
		nil,
		nil,
		nil,
		false,
		ability_extension
	)

	if _EventLog.is_enabled() then
		local bot_slot = _Debug.bot_slot_for_unit(unit)
		_EventLog.emit_decision(
			fixed_t,
			bot_slot,
			_equipped_combat_ability_name(unit),
			ability_template_name,
			can_activate,
			rule,
			"fallback",
			context
		)
	end

	if not can_activate then
		if context.num_nearby > 0 and _debug_enabled() then
			_debug_log(
				"fallback_decision_block:" .. ability_template_name,
				fixed_t,
				"fallback held "
					.. ability_template_name
					.. " (rule="
					.. tostring(rule)
					.. ", nearby="
					.. tostring(context.num_nearby)
					.. ")"
			)
		end
		return
	end

	-- Rescue aim (#10): for fallback-queued charges, apply aim correction
	-- here since the BtBotActivateAbilityAction.enter hook won't fire.
	if rule and RESCUE_CHARGE_RULES[rule] then
		local perception = blackboard and blackboard.perception
		local ally_unit = perception and perception.target_ally
		if ally_unit then
			local ally_pos = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
			if ally_pos then
				local input_ext = ScriptUnit.has_extension(unit, "input_system")
				local bot_input = input_ext and input_ext.bot_unit_input and input_ext:bot_unit_input()
				if bot_input then
					bot_input:set_aiming(true)
					bot_input:set_aim_position(ally_pos)
					if _debug_enabled() then
						_debug_log(
							"rescue_aim:" .. tostring(unit),
							fixed_t,
							"rescue aim (fallback): directed charge toward disabled ally"
						)
					end
				end
			end
		end
	end

	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)

	if _EventLog.is_enabled() then
		local attempt_id = _EventLog.next_attempt_id()
		state.attempt_id = attempt_id
		local bot_slot = _Debug.bot_slot_for_unit(unit)
		_EventLog.emit({
			t = fixed_t,
			event = "queued",
			bot = bot_slot,
			ability = _equipped_combat_ability_name(unit),
			template = ability_template_name,
			input = action_input,
			source = "fallback",
			rule = rule,
			attempt_id = attempt_id,
		})
	end

	state.action_input_extension = action_input_extension
	state.active = true
	state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
	state.wait_action_input = ability_meta_data.wait_action and ability_meta_data.wait_action.action_input or nil
	state.wait_sent = false

	if _debug_enabled() then
		_debug_log(
			"fallback_queue:" .. tostring(unit),
			fixed_t,
			"fallback queued "
				.. ability_template_name
				.. " input="
				.. tostring(action_input)
				.. " (rule="
				.. tostring(rule)
				.. ", nearby="
				.. tostring(context.num_nearby)
				.. ")"
		)
	end

	local function _sanitize(value)
		local fragment = tostring(value or "unknown")
		return string.gsub(fragment, "[^%w_%-]", "_")
	end

	local dump_key = "template:" .. tostring(ability_template_name)
	if not _fallback_queue_dumped_by_key[dump_key] and _debug_enabled() then
		_fallback_queue_dumped_by_key[dump_key] = true
		_mod:echo("BetterBots DEBUG: one-shot context dump for " .. dump_key)
		_mod:dump({
			fixed_t = fixed_t,
			ability_template_name = ability_template_name,
			ability_name = _equipped_combat_ability_name(unit),
			activation_input = action_input,
			rule = rule,
			context = _Debug.context_snapshot(context),
			fallback_state = _Debug.fallback_state_snapshot(state, fixed_t),
		}, "betterbots_" .. _sanitize(dump_key), 3)
	end
end

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_equipped_combat_ability = deps.equipped_combat_ability
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_is_suppressed = deps.is_suppressed
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_fallback_queue_dumped_by_key = deps.fallback_queue_dumped_by_key
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = deps.DEBUG_SKIP_RELIC_LOG_INTERVAL_S
	local shared_rules = deps.shared_rules or {}
	RESCUE_CHARGE_RULES = shared_rules.RESCUE_CHARGE_RULES or RESCUE_CHARGE_RULES
end

function M.wire(deps)
	_Heuristics = deps.Heuristics
	_MetaData = deps.MetaData
	_ItemFallback = deps.ItemFallback
	_Debug = deps.Debug
	_EventLog = deps.EventLog
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

function M.try_queue(unit, blackboard)
	_fallback_try_queue_combat_ability(unit, blackboard)
end

return M
