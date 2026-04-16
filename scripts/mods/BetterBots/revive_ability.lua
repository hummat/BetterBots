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
local _combat_ability_identity

local INTERACT_ACTION_PATCH_SENTINEL = "__bb_revive_ability_installed"

local RESCUE_INTERACTION_TYPES = {
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
}

local RESCUE_NEED_TYPES = {
	knocked_down = true,
	netted = true,
	ledge = true,
	hogtied = true,
}

local M = {}

function M.init(deps)
	assert(deps.combat_ability_identity, "revive_ability: combat_ability_identity dep required")
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
	_combat_ability_identity = deps.combat_ability_identity
end

function M.wire(deps)
	_MetaData = deps.MetaData
	_EventLog = deps.EventLog
	_Debug = deps.Debug
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

local function _resolve_revive_template(unit, ability_template_name, ability_extension)
	local identity =
		_combat_ability_identity.resolve(unit, ability_extension, { template_name = ability_template_name })
	local effective_name = _combat_ability_identity.effective_name(identity)

	if _combat_ability_identity.is_revive_defensive(identity) then
		return true, effective_name
	end

	return false, effective_name
end

-- Formats a human-readable bot identifier for log correlation. Prefers the
-- slot number (1-5) from Debug.bot_slot_for_unit so observers can match
-- candidate/skip/queue log lines against the in-game party roster; falls
-- back to the unit reference if the slot lookup isn't available.
local function _format_bot_id(unit)
	local slot = _Debug and _Debug.bot_slot_for_unit and _Debug.bot_slot_for_unit(unit)
	if slot then
		return "bot=" .. tostring(slot)
	end
	return "unit=" .. tostring(unit)
end

function M.log_revive_candidate(unit, behavior_component, perception_component)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end

	local target_ally = perception_component and perception_component.target_ally
	local need_type = perception_component and perception_component.target_ally_need_type
	if not target_ally or behavior_component.interaction_unit ~= target_ally or not RESCUE_NEED_TYPES[need_type] then
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not unit_data_extension or not ability_extension then
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	local is_defensive, effective_ability_name =
		_resolve_revive_template(unit, ability_template_name, ability_extension)
	if not is_defensive then
		return false
	end

	local log_name = effective_ability_name or ability_template_name or "unknown"
	_debug_log(
		"revive_candidate:" .. log_name .. ":" .. tostring(unit),
		_fixed_time(),
		"["
			.. _format_bot_id(unit)
			.. "] revive candidate observed: "
			.. tostring(log_name)
			.. " (template="
			.. tostring(ability_template_name)
			.. ", need_type="
			.. tostring(need_type)
			.. ")",
		5
	)

	return true
end

function M.try_pre_revive(unit, _blackboard, action_data) -- luacheck: ignore 212/_blackboard
	local interaction_type = action_data and action_data.interaction_type
	if not RESCUE_INTERACTION_TYPES[interaction_type] then
		return false
	end

	-- From here on, this IS a rescue interaction — log skip reasons.
	-- Throttle keys still use the stringified unit for uniqueness; the
	-- visible log message uses the slot-aware identifier so operators can
	-- correlate candidate/skip/queue lines against the party roster.
	local bot_id = tostring(unit)
	local bot_tag = "[" .. _format_bot_id(unit) .. "] "

	local perception_extension = ScriptUnit.has_extension(unit, "perception_system")
	local enemies_nearby = 0
	if perception_extension then
		local _, num = perception_extension:enemies_in_proximity()
		enemies_nearby = num or 0
	end
	if enemies_nearby < 1 then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_enemies:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no enemies nearby)"
			)
		end
		return false
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:suppressed:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (suppressed: " .. tostring(suppress_reason) .. ")"
			)
		end
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_unit_data:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no unit_data_system extension)"
			)
		end
		return false
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_ability_ext:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no ability_system extension)"
			)
		end
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	local is_defensive, effective_ability_name =
		_resolve_revive_template(unit, ability_template_name, ability_extension)
	if not ability_template_name or not is_defensive then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:not_whitelisted:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped (ability "
					.. tostring(ability_template_name)
					.. ", equipped="
					.. tostring(effective_ability_name)
					.. " not in defensive whitelist)"
			)
		end
		return false
	end

	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:disabled:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " disabled by setting)"
			)
		end
		return false
	end

	if not ability_extension:can_use_ability("combat_ability") then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:cant_use:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " can_use_ability=false)"
			)
		end
		return false
	end

	local charges = ability_extension:remaining_ability_charges("combat_ability")
	if not charges or charges < 1 then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_charges:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " charges=0)"
			)
		end
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data or not ability_meta_data.activation then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_meta:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped ("
					.. tostring(ability_template_name)
					.. " missing ability_meta_data.activation)"
			)
		end
		return false
	end

	local activation_data = ability_meta_data.activation
	local action_input = activation_data.action_input
	if not action_input then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_input:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped ("
					.. tostring(ability_template_name)
					.. " activation has no action_input)"
			)
		end
		return false
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_input_ext:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no action_input_system extension)"
			)
		end
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
			if _debug_enabled() then
				_debug_log(
					"revive_ability_skip:not_queueable:" .. bot_id,
					_fixed_time(),
					bot_tag
						.. "revive ability skipped ("
						.. tostring(ability_template_name)
						.. " action_input "
						.. tostring(action_input)
						.. " not bot-queueable)"
				)
			end
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
			"revive_ability:" .. tostring(effective_ability_name or ability_template_name) .. ":" .. tostring(unit),
			fixed_t,
			bot_tag
				.. "revive ability queued: "
				.. tostring(effective_ability_name or ability_template_name)
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
			ability = effective_ability_name or _equipped_combat_ability_name(unit),
			template = ability_template_name,
			equipped_ability_name = effective_ability_name,
			interaction = interaction_type,
			enemies = enemies_nearby,
		})
	end

	return true
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action",
		function(BtBotInteractAction)
			if not BtBotInteractAction or rawget(BtBotInteractAction, INTERACT_ACTION_PATCH_SENTINEL) then
				return
			end
			BtBotInteractAction[INTERACT_ACTION_PATCH_SENTINEL] = true

			local orig_enter = BtBotInteractAction.enter
			BtBotInteractAction.enter = function(self, unit, breed, blackboard, scratchpad, action_data, t)
				local perf_t0 = _perf and _perf.begin()
				local ok, err = pcall(M.try_pre_revive, unit, blackboard, action_data)
				if not ok and _debug_enabled and _debug_enabled() then
					_debug_log(
						"revive_ability_error:" .. tostring(unit),
						_fixed_time(),
						"try_pre_revive error: " .. tostring(err)
					)
				end
				if perf_t0 and _perf then
					_perf.finish("revive_ability", perf_t0)
				end
				return orig_enter(self, unit, breed, blackboard, scratchpad, action_data, t)
			end

			if _debug_enabled and _debug_enabled() then
				_debug_log("revive_ability:hook_installed", 0, "installed BtBotInteractAction.enter hook")
			end
		end
	)
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(
		BotBehaviorExtension,
		"_refresh_destination",
		function(
			self,
			_t,
			_self_position,
			_previous_destination,
			_hold_position,
			_hold_position_max_distance_sq,
			_bot_group_data,
			_navigation_extension,
			_follow_component,
			perception_component
		)
			if not (_debug_enabled and _debug_enabled()) then
				return
			end

			local unit = self and self._unit
			local behavior_component = self and self._behavior_component
			if not unit or not behavior_component or not perception_component then
				return
			end

			M.log_revive_candidate(unit, behavior_component, perception_component)
		end
	)
end

M.RESCUE_INTERACTION_TYPES = RESCUE_INTERACTION_TYPES

return M
