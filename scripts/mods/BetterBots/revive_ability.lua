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
	-- Implementation in Task 2
	return false
end

function M.register_hooks()
	-- Hook registration in Task 3
end

-- Exposed for testing
M.REVIVE_DEFENSIVE_ABILITIES = REVIVE_DEFENSIVE_ABILITIES
M.RESCUE_INTERACTION_TYPES = RESCUE_INTERACTION_TYPES

return M
