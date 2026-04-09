-- scripts/mods/BetterBots/revive_ability.lua
-- Revive-with-ability (#7): fire a defensive ability before rescue interactions.
-- Hooks BtBotInteractAction.enter; delegates hold+release to ability_queue's
-- state machine via _fallback_state_by_unit.
local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _is_suppressed
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _perf

local _MetaData
local _EventLog
local _Debug
local _is_combat_template_enabled
local _action_input_is_bot_queueable

local REVIVE_DEFENSIVE_ABILITIES = {
	ogryn_taunt_shout = true,
	psyker_shout = true,
	adamant_shout = true,
	zealot_invisibility = true,
	veteran_stealth_combat_ability = true,
}

local RESCUE_INTERACTION_TYPES = {
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
}

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_suppressed = deps.is_suppressed
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_perf = deps.perf
	local shared_rules = deps.shared_rules or {}
	_action_input_is_bot_queueable = shared_rules.action_input_is_bot_queueable
end

function M.wire(deps)
	_MetaData = deps.MetaData
	_EventLog = deps.EventLog
	_Debug = deps.Debug
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

function M.try_pre_revive(unit, blackboard, action_data)
	local interaction_type = action_data and action_data.interaction_type
	if not RESCUE_INTERACTION_TYPES[interaction_type] then
		return false
	end

	local perception = blackboard and blackboard.perception
	local enemies_nearby = perception and perception.enemies_in_proximity or 0
	if enemies_nearby < 1 then
		return false
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_suppressed:" .. tostring(suppress_reason) .. ":" .. tostring(unit),
				_fixed_time(),
				"revive ability suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	if not ability_template_name or not REVIVE_DEFENSIVE_ABILITIES[ability_template_name] then
		return false
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_extension then
		return false
	end

	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		return false
	end

	if not ability_extension:can_use_ability("combat_ability") then
		return false
	end

	local charges = ability_extension:remaining_ability_charges("combat_ability")
	if not charges or charges < 1 then
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data or not ability_meta_data.activation then
		return false
	end

	local activation_data = ability_meta_data.activation
	local action_input = activation_data.action_input
	if not action_input then
		return false
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		return false
	end

	if _action_input_is_bot_queueable then
		local is_valid = _action_input_is_bot_queueable(
			action_input_extension,
			ability_extension,
			"combat_ability_action",
			ability_template_name,
			action_input,
			activation_data.used_input,
			_fixed_time()
		)
		if not is_valid then
			return false
		end
	end

	local fixed_t = _fixed_time()
	action_input_extension:bot_queue_action_input("combat_ability_action", action_input, nil)

	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end
	state.active = true
	state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
	state.wait_action_input = ability_meta_data.wait_action and ability_meta_data.wait_action.action_input or nil
	state.wait_sent = false
	state.action_input_extension = action_input_extension

	if _debug_enabled() then
		_debug_log(
			"revive_ability:" .. ability_template_name .. ":" .. tostring(unit),
			fixed_t,
			"revive ability queued: "
				.. ability_template_name
				.. " (interaction="
				.. tostring(interaction_type)
				.. ", enemies="
				.. tostring(enemies_nearby)
				.. ")"
		)
	end

	if _EventLog and _EventLog.is_enabled() then
		local bot_slot = _Debug and _Debug.bot_slot_for_unit(unit) or nil
		_EventLog.emit({
			t = fixed_t,
			event = "revive_ability",
			bot = bot_slot,
			ability = _equipped_combat_ability_name(unit),
			template = ability_template_name,
			interaction = interaction_type,
			enemies = enemies_nearby,
		})
	end

	return true
end

function M.register_hooks()
	-- Hook registration in Task 3
end

-- Exposed for testing
M.REVIVE_DEFENSIVE_ABILITIES = REVIVE_DEFENSIVE_ABILITIES
M.RESCUE_INTERACTION_TYPES = RESCUE_INTERACTION_TYPES

return M
