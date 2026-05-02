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
local _EngagementLeash
local _ChargeNavValidation
local _TeamCooldown
local _CombatAbilityIdentity
local _HumanLikeness
local _perf
local _is_team_cooldown_enabled
local _is_combat_template_enabled
local _ability_templates
local _ability_templates_injected

local DEBUG_SKIP_RELIC_LOG_INTERVAL_S

local RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

local _action_input_is_bot_queueable

local function _clear_pending_jitter(state)
	state.pending_rule = nil
	state.pending_template_name = nil
	state.pending_action_input = nil
	state.pending_ready_t = nil
end

local function _ability_templates_once()
	if not _ability_templates then
		_ability_templates = require("scripts/settings/ability/ability_templates/ability_templates")
	end

	if not _ability_templates_injected then
		_MetaData.inject(_ability_templates)
		_ability_templates_injected = true
	end

	return _ability_templates
end

local function _finish_child_perf(tag, start_clock)
	if start_clock and _perf then
		_perf.finish(tag, start_clock, nil, { include_total = false })
	end
end

local function _fallback_try_queue_combat_ability(unit, blackboard)
	local ability_component_name = "combat_ability_action"
	local fixed_t = _fixed_time()
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_ext:" .. tostring(unit),
				fixed_t,
				"unit_data_system extension absent (stale unit?)"
			)
		end
		return
	end
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
			local item_t0 = _perf and _perf.begin() or nil
			_ItemFallback.try_queue_item(
				unit,
				unit_data_extension,
				ability_extension,
				state,
				fixed_t,
				combat_ability,
				blackboard
			)
			_finish_child_perf("ability_queue.item_fallback", item_t0)
		end

		return
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		if _debug_enabled() then
			_debug_log(
				"fallback_disabled_template:" .. ability_template_name .. ":" .. tostring(unit),
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (disabled by mod setting)"
			)
		end
		return
	end

	if state.item_stage then
		_ItemFallback.reset_item_sequence_state(state)
	end

	local setup_t0 = _perf and _perf.begin() or nil
	local AbilityTemplates = _ability_templates_once()

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		_finish_child_perf("ability_queue.template_setup", setup_t0)
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_template:" .. ability_template_name .. ":" .. tostring(unit),
				fixed_t,
				"fallback blocked missing template " .. ability_template_name
			)
		end
		return
	end

	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data then
		_finish_child_perf("ability_queue.template_setup", setup_t0)
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_meta:" .. ability_template_name .. ":" .. tostring(unit),
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (no ability_meta_data)"
			)
		end
		return
	end

	local activation_data = ability_meta_data and ability_meta_data.activation
	if not activation_data then
		_finish_child_perf("ability_queue.template_setup", setup_t0)
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_activation:" .. ability_template_name .. ":" .. tostring(unit),
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (no activation data)"
			)
		end
		return
	end

	local action_input = activation_data and activation_data.action_input
	if not action_input then
		_finish_child_perf("ability_queue.template_setup", setup_t0)
		if _debug_enabled() then
			_debug_log(
				"fallback_missing_action_input:" .. ability_template_name .. ":" .. tostring(unit),
				fixed_t,
				"fallback blocked " .. ability_template_name .. " (activation.action_input missing)"
			)
		end
		return
	end
	_finish_child_perf("ability_queue.template_setup", setup_t0)

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

	if not ability_extension or not ability_extension:can_use_ability("combat_ability") then
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
				"fallback_suppress:" .. tostring(suppress_reason) .. ":" .. tostring(unit),
				fixed_t,
				"fallback ability suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return
	end

	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")
	local used_input = activation_data.used_input
	local validation_t0 = _perf and _perf.begin() or nil
	local action_input_is_valid = _action_input_is_bot_queueable(
		action_input_extension,
		ability_extension,
		ability_component_name,
		ability_template_name,
		action_input,
		used_input,
		fixed_t
	)
	_finish_child_perf("ability_queue.input_validation", validation_t0)

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

	local decision_t0 = _perf and _perf.begin() or nil
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
	_finish_child_perf("ability_queue.decision", decision_t0)

	if not can_activate then
		_clear_pending_jitter(state)
		if context.num_nearby > 0 and _debug_enabled() then
			_debug_log(
				"fallback_decision_block:" .. ability_template_name .. ":" .. tostring(unit),
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

	local queue_t0 = _perf and _perf.begin() or nil
	-- Team cooldown staggering (#14): suppress this fallback queue if another
	-- bot in the same ability category fired recently. The BT condition path
	-- (condition_patch.lua) does the same check, but virtually all solo-play
	-- activations come through this fallback path, so without this guard the
	-- staggering never fires in real gameplay.
	if _TeamCooldown and (not _is_team_cooldown_enabled or _is_team_cooldown_enabled()) then
		local identity = _CombatAbilityIdentity
				and _CombatAbilityIdentity.resolve(unit, ability_extension, ability_component)
			or nil
		local team_key = (identity and identity.semantic_key) or ability_template_name
		local team_suppressed, team_reason = _TeamCooldown.is_suppressed(unit, team_key, fixed_t, rule)
		if team_suppressed then
			_clear_pending_jitter(state)
			if _debug_enabled() then
				_debug_log(
					"team_cd:" .. ability_template_name .. ":" .. tostring(unit),
					fixed_t,
					"fallback suppressed " .. ability_template_name .. " (" .. tostring(team_reason) .. ")"
				)
			end
			_finish_child_perf("ability_queue.queue", queue_t0)
			return
		end
	end

	local bypass_jitter = _HumanLikeness and _HumanLikeness.should_bypass_ability_jitter(rule)
	if _HumanLikeness and not bypass_jitter then
		local pending_matches = state.pending_rule == rule
			and state.pending_template_name == ability_template_name
			and state.pending_action_input == action_input

		if not pending_matches then
			state.pending_rule = rule
			state.pending_template_name = ability_template_name
			state.pending_action_input = action_input
			state.pending_ready_t = fixed_t + _HumanLikeness.random_ability_jitter_delay(rule)
			_finish_child_perf("ability_queue.queue", queue_t0)
			return
		end

		if fixed_t < state.pending_ready_t then
			_finish_child_perf("ability_queue.queue", queue_t0)
			return
		end
	end

	-- Rescue aim (#10): for fallback-queued charges, apply aim correction
	-- here since the BtBotActivateAbilityAction.enter hook won't fire.
	local rescue_ally_position
	if rule and RESCUE_CHARGE_RULES[rule] then
		local perception = blackboard and blackboard.perception
		local ally_unit = perception and perception.target_ally
		if ally_unit then
			local ally_pos = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
			if ally_pos then
				rescue_ally_position = ally_pos
			end
		end
	end

	if _ChargeNavValidation and _ChargeNavValidation.should_validate(ability_template_name) then
		local nav_ok, nav_reason = _ChargeNavValidation.validate(unit, ability_template_name, "fallback", {
			blackboard = blackboard,
			target_position = rescue_ally_position,
		})
		if not nav_ok then
			local should_emit_block_event = not _ChargeNavValidation.should_emit_block_event
				or _ChargeNavValidation.should_emit_block_event(nav_reason)
			if should_emit_block_event and _EventLog.is_enabled() then
				_EventLog.emit({
					t = fixed_t,
					event = "blocked",
					bot = _Debug.bot_slot_for_unit(unit),
					ability = _equipped_combat_ability_name(unit),
					template = ability_template_name,
					source = "fallback",
					rule = rule,
					reason = nav_reason,
				})
			end
			_finish_child_perf("ability_queue.queue", queue_t0)
			return
		end
	end

	if rescue_ally_position then
		local input_ext = ScriptUnit.has_extension(unit, "input_system")
		local bot_input = input_ext and input_ext.bot_unit_input and input_ext:bot_unit_input()
		if bot_input then
			bot_input:set_aiming(true)
			bot_input:set_aim_position(rescue_ally_position)
			if _debug_enabled() then
				_debug_log(
					"rescue_aim:" .. tostring(unit),
					fixed_t,
					"rescue aim (fallback): directed charge toward disabled ally"
				)
			end
		end
	end

	_clear_pending_jitter(state)
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)

	if _EngagementLeash and _EngagementLeash.is_movement_ability(ability_template_name) then
		_EngagementLeash.record_charge(unit, fixed_t)
	end

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
	_finish_child_perf("ability_queue.queue", queue_t0)
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
	_perf = deps.perf
	_ability_templates = nil
	_ability_templates_injected = false
	local shared_rules = deps.shared_rules or {}
	RESCUE_CHARGE_RULES = shared_rules.RESCUE_CHARGE_RULES or RESCUE_CHARGE_RULES
	_action_input_is_bot_queueable = shared_rules.action_input_is_bot_queueable
end

function M.wire(deps)
	_Heuristics = deps.Heuristics
	_MetaData = deps.MetaData
	_ItemFallback = deps.ItemFallback
	_Debug = deps.Debug
	_EventLog = deps.EventLog
	_EngagementLeash = deps.EngagementLeash
	_ChargeNavValidation = deps.ChargeNavValidation
	_TeamCooldown = deps.TeamCooldown
	_CombatAbilityIdentity = deps.CombatAbilityIdentity
	_HumanLikeness = deps.HumanLikeness
	_is_team_cooldown_enabled = deps.is_team_cooldown_enabled
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

function M.try_queue(unit, blackboard)
	_fallback_try_queue_combat_ability(unit, blackboard)
end

function M._action_input_is_bot_queueable(...)
	return _action_input_is_bot_queueable(...)
end

return M
