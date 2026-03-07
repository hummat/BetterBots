local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local DEBUG_FORCE_ENABLED = false
local EVENT_LOG_SETTING_ID = "enable_event_log"
local ABILITY_STATE_FAIL_RETRY_S = 0.35
local META_PATCH_VERSION = "2026-03-04-tier2-v3"
local CONDITIONS_PATCH_VERSION = "2026-03-05-conditions-v4"
local _last_debug_log_t_by_key = {}
local _patched_bt_bot_conditions = setmetatable({}, { __mode = "k" })
local _patched_bt_conditions = setmetatable({}, { __mode = "k" })
local _patched_ability_templates = setmetatable({}, { __mode = "k" })
local _fallback_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_charge_event_by_unit = setmetatable({}, { __mode = "k" })
local _fallback_queue_dumped_by_key = {}
local _decision_context_cache_by_unit = setmetatable({}, { __mode = "k" })
local _session_start_emitted = false
local _SNAPSHOT_INTERVAL_S = 30
local _last_snapshot_t_by_unit = setmetatable({}, { __mode = "k" })
local _super_armor_breed_flag_by_name = {}

local ARMOR_TYPES = ArmorSettings.types
local ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPES and ARMOR_TYPES.super_armor

local function _fixed_time()
	return FixedFrame.get_latest_fixed_time() or 0
end

local function _debug_enabled()
	if DEBUG_FORCE_ENABLED then
		return true
	end

	return mod:get(DEBUG_SETTING_ID) == true
end

local function _debug_log(key, fixed_t, message, min_interval_s)
	if not _debug_enabled() then
		return
	end

	local t = fixed_t or 0
	local interval_s = min_interval_s or DEBUG_LOG_INTERVAL_S
	local last_t = _last_debug_log_t_by_key[key]
	if last_t and t - last_t < interval_s then
		return
	end

	_last_debug_log_t_by_key[key] = t
	mod:echo("BetterBots DEBUG: " .. message)
end

local function _equipped_combat_ability(unit)
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	local equipped_abilities = ability_extension and ability_extension._equipped_abilities
	local combat_ability = equipped_abilities and equipped_abilities.combat_ability

	return ability_extension, combat_ability
end

local function _equipped_combat_ability_name(unit)
	local _, combat_ability = _equipped_combat_ability(unit)

	return combat_ability and combat_ability.name or "unknown"
end

-- Sub-modules (loaded via io_dofile, no top-level game-system require or hook side effects)
local MetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/meta_data")
assert(MetaData, "BetterBots: failed to load meta_data module")

local Heuristics = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics")
assert(Heuristics, "BetterBots: failed to load heuristics module")

local ItemFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/item_fallback")
assert(ItemFallback, "BetterBots: failed to load item_fallback module")

local Debug = mod:io_dofile("BetterBots/scripts/mods/BetterBots/debug")
assert(Debug, "BetterBots: failed to load debug module")

local EventLog = mod:io_dofile("BetterBots/scripts/mods/BetterBots/event_log")
assert(EventLog, "BetterBots: failed to load event_log module")

-- Init each module with its dependencies
MetaData.init({
	mod = mod,
	patched_ability_templates = _patched_ability_templates,
	debug_log = _debug_log,
	META_PATCH_VERSION = META_PATCH_VERSION,
})

Heuristics.init({
	fixed_time = _fixed_time,
	decision_context_cache = _decision_context_cache_by_unit,
	super_armor_breed_cache = _super_armor_breed_flag_by_name,
	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
})

ItemFallback.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_charge_event_by_unit = _last_charge_event_by_unit,
	fallback_queue_dumped_by_key = _fallback_queue_dumped_by_key,
	ITEM_WIELD_TIMEOUT_S = 1.5,
	ITEM_SEQUENCE_RETRY_S = 1.0,
	ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.2,
	ITEM_DEFAULT_START_DELAY_S = 0.2,
	event_log = EventLog,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
})

Debug.init({
	mod = mod,
	debug_log = _debug_log,
	fixed_time = _fixed_time,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_charge_event_by_unit = _last_charge_event_by_unit,
})

EventLog.init({
	mod = mod,
	context_snapshot = Debug.context_snapshot,
})

-- Wire cross-module references (late-bound to avoid circular deps)
ItemFallback.wire({
	build_context = Heuristics.build_context,
	context_snapshot = Debug.context_snapshot,
	fallback_state_snapshot = Debug.fallback_state_snapshot,
	evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
})

Debug.wire({
	build_context = Heuristics.build_context,
	resolve_decision = Heuristics.resolve_decision,
	enemy_breed = Heuristics.enemy_breed,
	can_use_item_fallback = ItemFallback.can_use_item_fallback,
})

-- Condition hook: replaces bt_bot_conditions.can_activate_ability
local function _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	local ability_component_name = action_data.ability_component_name

	if ability_component_name == scratchpad.ability_component_name then
		return true
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
	MetaData.inject(AbilityTemplates)

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

	local can_activate, rule, context = Heuristics.resolve_decision(
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

	Debug.log_ability_decision(ability_template_name, fixed_t, can_activate, rule, context)

	if EventLog.is_enabled() then
		local bot_slot = Debug.bot_slot_for_unit(unit)
		EventLog.emit_decision(
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

-- Fallback queue: runs every BotBehaviorExtension.update tick
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

		local ability_extension, combat_ability = _equipped_combat_ability(unit)
		if ability_extension then
			ItemFallback.try_queue_item(
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

	if state.item_stage then
		state.item_stage = nil
		state.item_ability_name = nil
		state.item_wield_deadline_t = nil
		state.item_stage_deadline_t = nil
		state.item_attempt_t = nil
		state.item_charge_confirmed = nil
		state.item_profile_name = nil
		state.item_profile_key = nil
		state.item_profile_count = nil
		state.item_start_input = nil
		state.item_wait_t = nil
		state.item_followup_input = nil
		state.item_followup_delay = nil
		state.item_unwield_input = nil
		state.item_unwield_delay = nil
		state.item_charge_confirm_timeout = nil
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	if not ability_template then
		_debug_log(
			"fallback_missing_template:" .. ability_template_name,
			fixed_t,
			"fallback blocked missing template " .. ability_template_name
		)
		return
	end

	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data then
		_debug_log(
			"fallback_missing_meta:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (no ability_meta_data)"
		)
		return
	end

	local activation_data = ability_meta_data and ability_meta_data.activation
	if not activation_data then
		_debug_log(
			"fallback_missing_activation:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (no activation data)"
		)
		return
	end

	local action_input = activation_data and activation_data.action_input
	if not action_input then
		_debug_log(
			"fallback_missing_action_input:" .. ability_template_name,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (activation.action_input missing)"
		)
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

	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local used_input = activation_data.used_input
	local action_input_is_valid =
		ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)

	if not action_input_is_valid then
		_debug_log(
			"fallback_invalid_input:" .. ability_template_name .. ":" .. action_input,
			fixed_t,
			"fallback blocked " .. ability_template_name .. " (invalid action_input=" .. tostring(action_input) .. ")"
		)
		return
	end

	local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
	local can_activate, rule, context = Heuristics.resolve_decision(
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

	if EventLog.is_enabled() then
		local bot_slot = Debug.bot_slot_for_unit(unit)
		EventLog.emit_decision(
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
		if context.num_nearby > 0 then
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

	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)

	if EventLog.is_enabled() then
		local attempt_id = EventLog.next_attempt_id()
		state.attempt_id = attempt_id
		local bot_slot = Debug.bot_slot_for_unit(unit)
		EventLog.emit({
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

	local function _sanitize(value)
		local fragment = tostring(value or "unknown")
		return string.gsub(fragment, "[^%w_%-]", "_")
	end

	local dump_key = "template:" .. tostring(ability_template_name)
	if not _fallback_queue_dumped_by_key[dump_key] and _debug_enabled() then
		_fallback_queue_dumped_by_key[dump_key] = true
		mod:echo("BetterBots DEBUG: one-shot context dump for " .. dump_key)
		mod:dump({
			fixed_t = fixed_t,
			ability_template_name = ability_template_name,
			ability_name = _equipped_combat_ability_name(unit),
			activation_input = action_input,
			rule = rule,
			context = Debug.context_snapshot(context),
			fallback_state = Debug.fallback_state_snapshot(state, fixed_t),
		}, "betterbots_" .. _sanitize(dump_key), 3)
	end
end

-- Condition patch installer
local function _install_condition_patch(conditions, patched_set, patch_label)
	if not conditions or patched_set[conditions] then
		return
	end

	conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	end
	patched_set[conditions] = true

	_debug_log(
		"condition_patch:" .. patch_label .. ":" .. tostring(conditions),
		0,
		"patched " .. patch_label .. ".can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
	)
end

-- Hook registrations (all game-system hooks stay in main)
mod:hook_require("scripts/settings/ability/ability_templates/ability_templates", function(AbilityTemplates)
	MetaData.inject(AbilityTemplates)
end)

-- Guard: plasma guns (and similar) have overheat_configuration but nest thresholds
-- under a .thresholds subtable instead of flat top-level keys. The vanilla
-- Overheat.slot_percentage divides by overheat_configuration[threshold_type] without
-- a nil check, crashing the BT when bots wield these weapons.
mod:hook_require("scripts/utilities/overheat", function(Overheat)
	local _orig_slot_percentage = Overheat.slot_percentage
	Overheat.slot_percentage = function(unit, slot_name, threshold_type)
		local vis_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
		if vis_ext then
			local cfg = Overheat.configuration(vis_ext, slot_name)
			if cfg and not cfg[threshold_type] then
				return 0
			end
		end
		return _orig_slot_percentage(unit, slot_name, threshold_type)
	end
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions", function(conditions)
	_install_condition_patch(conditions, _patched_bt_bot_conditions, "bt_bot_conditions")
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/bt_conditions", function(conditions)
	_install_condition_patch(conditions, _patched_bt_conditions, "bt_conditions")
end)

local function _try_patch_conditions_now(module_path, patched_set, patch_label)
	local ok, conditions_or_err = pcall(require, module_path)
	if not ok then
		_debug_log(
			"condition_patch_require_failed:" .. patch_label,
			0,
			"require failed for " .. patch_label .. " (" .. tostring(conditions_or_err) .. ")",
			DEBUG_SKIP_RELIC_LOG_INTERVAL_S
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

mod:hook_require(
	"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
	function(BtBotActivateAbilityAction)
		mod:hook_safe(
			BtBotActivateAbilityAction,
			"enter",
			function(_self, unit, _breed, _blackboard, scratchpad, action_data, _t)
				local ability_component_name = action_data and action_data.ability_component_name or "?"
				local activation_data = scratchpad and scratchpad.activation_data
				local action_input = activation_data and activation_data.action_input or "?"
				local fixed_t = _fixed_time()

				_debug_log(
					"enter:" .. tostring(ability_component_name) .. ":" .. tostring(action_input),
					fixed_t,
					"enter ability node component="
						.. tostring(ability_component_name)
						.. " action_input="
						.. tostring(action_input)
				)

				if EventLog.is_enabled() and unit then
					local state = _fallback_state_by_unit[unit]
					if not state then
						state = {}
						_fallback_state_by_unit[unit] = state
					end
					local attempt_id = EventLog.next_attempt_id()
					state.attempt_id = attempt_id
					local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
					local ability_comp = unit_data_ext and unit_data_ext:read_component(ability_component_name)
					local template_name = ability_comp and ability_comp.template_name or "?"
					EventLog.emit({
						t = fixed_t,
						event = "queued",
						bot = Debug.bot_slot_for_unit(unit),
						ability = _equipped_combat_ability_name(unit),
						template = template_name,
						input = action_input,
						source = "bt",
						attempt_id = attempt_id,
					})
				end
			end
		)
	end
)

mod:hook_require("scripts/extension_systems/ability/player_unit_ability_extension", function(PlayerUnitAbilityExtension)
	mod:hook_safe(PlayerUnitAbilityExtension, "use_ability_charge", function(self, ability_type, optional_num_charges)
		if ability_type ~= "combat_ability" then
			return
		end

		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		local ability_name = "unknown"
		local equipped_abilities = self._equipped_abilities
		local combat_ability = equipped_abilities and equipped_abilities.combat_ability
		if combat_ability and combat_ability.name then
			ability_name = combat_ability.name
		end

		local fixed_t = _fixed_time()
		local unit = self._unit
		if unit then
			_last_charge_event_by_unit[unit] = {
				ability_name = ability_name,
				fixed_t = fixed_t,
			}

			if EventLog.is_enabled() then
				local bot_slot = Debug.bot_slot_for_unit(unit)
				local fb_state = _fallback_state_by_unit[unit]
				EventLog.emit({
					t = fixed_t,
					event = "consumed",
					bot = bot_slot,
					ability = ability_name,
					charges = optional_num_charges or 1,
					attempt_id = fb_state and fb_state.attempt_id or nil,
				})
			end
		end

		if not _debug_enabled() then
			return
		end

		_debug_log(
			"charge:" .. ability_name,
			fixed_t,
			"charge consumed for " .. ability_name .. " (charges=" .. tostring(optional_num_charges or 1) .. ")"
		)
	end)
end)

mod:hook_require(
	"scripts/extension_systems/ability/actions/action_character_state_change",
	function(ActionCharacterStateChange)
		mod:hook(ActionCharacterStateChange, "finish", function(func, self, reason, data, t, time_in_action)
			local action_settings = self._action_settings
			local ability_type = action_settings and action_settings.ability_type
			local use_ability_charge = action_settings and action_settings.use_ability_charge
			local player = self._player
			local unit = self._player_unit
			local wanted_state_name = self._wanted_state_name
			local character_state_component = self._character_sate_component
			local current_state_name = character_state_component and character_state_component.state_name or nil
			local failed_state_transition = wanted_state_name ~= nil and current_state_name ~= wanted_state_name
			local is_bot = player and not player:is_human_controlled()

			func(self, reason, data, t, time_in_action)

			if
				not is_bot
				or not unit
				or ability_type ~= "combat_ability"
				or not use_ability_charge
				or not failed_state_transition
			then
				return
			end

			local fixed_t = _fixed_time()
			local ability_name = _equipped_combat_ability_name(unit)
			ItemFallback.schedule_retry(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
			_debug_log(
				"state_fail_retry:" .. tostring(ability_name) .. ":" .. tostring(reason),
				fixed_t,
				"combat ability state transition failed for "
					.. tostring(ability_name)
					.. " (wanted="
					.. tostring(wanted_state_name)
					.. ", current="
					.. tostring(current_state_name)
					.. ", reason="
					.. tostring(reason)
					.. "); scheduled fast retry"
			)
		end)
	end
)

mod:hook_require(
	"scripts/extension_systems/action_input/player_unit_action_input_extension",
	function(PlayerUnitActionInputExtension)
		mod:hook_safe(PlayerUnitActionInputExtension, "extensions_ready", function(self, _world, unit)
			self._betterbots_player_unit = unit
		end)

		mod:hook(
			PlayerUnitActionInputExtension,
			"bot_queue_action_input",
			function(func, self, id, action_input, raw_input)
				local unit = self._betterbots_player_unit
				if unit and id == "weapon_action" and action_input == "wield" then
					local should_lock, ability_name, lock_reason = ItemFallback.should_lock_weapon_switch(unit)
					if should_lock then
						local fixed_t = _fixed_time()
						_debug_log(
							"lock_wield:" .. tostring(ability_name),
							fixed_t,
							"blocked weapon switch while keeping "
								.. tostring(ability_name)
								.. " "
								.. tostring(lock_reason)
								.. " (raw_input="
								.. tostring(raw_input)
								.. ")"
						)
						return nil
					end
				end

				return func(self, id, action_input, raw_input)
			end
		)
	end
)

mod:hook_require(
	"scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout",
	function(PlayerUnitVisualLoadout)
		mod:hook(PlayerUnitVisualLoadout, "wield_slot", function(func, slot_to_wield, player_unit, t, skip_wield_action)
			if slot_to_wield ~= "slot_combat_ability" then
				local should_lock, ability_name, lock_reason = ItemFallback.should_lock_weapon_switch(player_unit)
				if should_lock then
					local fixed_t = _fixed_time()
					_debug_log(
						"lock_wield_direct:" .. tostring(ability_name),
						fixed_t,
						"redirected wield_slot("
							.. tostring(slot_to_wield)
							.. ") -> slot_combat_ability while keeping "
							.. tostring(ability_name)
							.. " "
							.. tostring(lock_reason)
					)
					return func("slot_combat_ability", player_unit, t, skip_wield_action)
				end
			end

			return func(slot_to_wield, player_unit, t, skip_wield_action)
		end)
	end
)

mod:hook_require("scripts/extension_systems/weapon/weapon_system", function(WeaponSystem)
	mod:hook(
		WeaponSystem,
		"queue_perils_of_the_warp_elite_kills_achievement",
		function(func, self, player, explosion_queue_index)
			local account_id = nil
			if player and type(player.account_id) == "function" then
				account_id = player:account_id()
			end

			if account_id == nil then
				_debug_log(
					"skip_perils_nil_account",
					_fixed_time(),
					"skipped perils achievement queue with nil account_id"
				)
				return nil
			end

			return func(self, player, explosion_queue_index)
		end
	)
end)

mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
	mod:hook_safe(BotBehaviorExtension, "update", function(self, unit)
		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		local brain = self._brain
		local blackboard = brain and brain._blackboard or nil

		if EventLog.is_enabled() and not _session_start_emitted then
			local bots = Debug.collect_alive_bots()
			if bots and #bots > 0 then
				_session_start_emitted = true
				local bot_info = {}
				for i, bot_entry in ipairs(bots) do
					local p = bot_entry.player
					bot_info[i] = {
						slot = type(p.slot) == "function" and p:slot() or nil,
						archetype = type(p.archetype_name) == "function" and p:archetype_name() or nil,
						ability = _equipped_combat_ability_name(bot_entry.unit),
					}
				end
				EventLog.emit({
					t = _fixed_time(),
					event = "session_start",
					version = META_PATCH_VERSION,
					bots = bot_info,
				})
			end
		end

		_fallback_try_queue_combat_ability(unit, blackboard)
		EventLog.try_flush(_fixed_time())

		if EventLog.is_enabled() then
			local fixed_t = _fixed_time()
			local last_snap = _last_snapshot_t_by_unit[unit]
			if not last_snap or fixed_t - last_snap >= _SNAPSHOT_INTERVAL_S then
				_last_snapshot_t_by_unit[unit] = fixed_t
				local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
				local bot_slot = Debug.bot_slot_for_unit(unit)
				local fb_state = _fallback_state_by_unit[unit]
				EventLog.emit({
					t = fixed_t,
					event = "snapshot",
					bot = bot_slot,
					ability = _equipped_combat_ability_name(unit),
					cooldown_ready = ability_extension and ability_extension:can_use_ability("combat_ability") or false,
					charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability")
						or nil,
					ctx = Debug.context_snapshot(Heuristics.build_context(unit, blackboard)),
					item_stage = fb_state and fb_state.item_stage or nil,
				})
			end
		end
	end)
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		for key in pairs(_fallback_queue_dumped_by_key) do
			_fallback_queue_dumped_by_key[key] = nil
		end
		for unit in pairs(_decision_context_cache_by_unit) do
			_decision_context_cache_by_unit[unit] = nil
		end
		_debug_log("state:GameplayStateRun", _fixed_time(), "entered GameplayStateRun")
		EventLog.set_enabled(mod:get(EVENT_LOG_SETTING_ID) == true)
		EventLog.start_session(_fixed_time())
		_session_start_emitted = false
		for unit in pairs(_last_snapshot_t_by_unit) do
			_last_snapshot_t_by_unit[unit] = nil
		end
	end

	if status == "exit" and state == "GameplayStateRun" then
		EventLog.end_session()
	end
end

Debug.register_commands()

-- Re-enable EventLog after hot-reload if we're mid-session.
-- on_game_state_changed only fires on transitions, not on mod reload,
-- so a Ctrl+Shift+R during GameplayStateRun leaves EventLog dead.
if mod:get(EVENT_LOG_SETTING_ID) == true then
	local bots = Debug.collect_alive_bots()
	if bots and #bots > 0 then
		EventLog.set_enabled(true)
		EventLog.start_session(_fixed_time())
		_session_start_emitted = false
	end
end

mod:echo("BetterBots loaded")
if _debug_enabled() then
	mod:echo("BetterBots DEBUG: logging enabled (force=" .. tostring(DEBUG_FORCE_ENABLED) .. ")")
end
