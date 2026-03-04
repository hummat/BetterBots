local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local DEBUG_FORCE_ENABLED = true
local ITEM_WIELD_TIMEOUT_S = 1.5
local ITEM_SEQUENCE_RETRY_S = 1.0
local ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.2
local ITEM_DEFAULT_START_DELAY_S = 0.2
local ABILITY_STATE_FAIL_RETRY_S = 0.35
local META_PATCH_VERSION = "2026-03-04-tier2-v3"
local CONDITIONS_PATCH_VERSION = "2026-03-04-conditions-v3"
local _last_debug_log_t_by_key = {}
local _patched_ability_templates = setmetatable({}, { __mode = "k" })
local _patched_bt_bot_conditions = setmetatable({}, { __mode = "k" })
local _patched_bt_conditions = setmetatable({}, { __mode = "k" })
local _fallback_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_charge_event_by_unit = setmetatable({}, { __mode = "k" })

local LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY = {
	zealot_relic = true,
}

local LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
}

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

-- Tier 2 templates exist but are missing ability_meta_data.
-- This metadata is consumed by BtBotActivateAbilityAction.
local TIER2_META_DATA = {
	zealot_invisibility = {
		activation = {
			action_input = "stance_pressed",
		},
	},
	zealot_dash = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_taunt_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	psyker_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
}

-- Veteran templates ship with stance_pressed metadata, but runtime validation
-- for bot input expects combat_ability_pressed/combat_ability_released.
local META_DATA_OVERRIDES = {
	veteran_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
	veteran_stealth_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
}

local function _inject_missing_ability_meta_data(AbilityTemplates)
	if _patched_ability_templates[AbilityTemplates] then
		return
	end

	local injected_count = 0
	local overridden_count = 0

	for template_name, meta_data in pairs(TIER2_META_DATA) do
		local template = rawget(AbilityTemplates, template_name)
		if template and not template.ability_meta_data then
			template.ability_meta_data = meta_data
			injected_count = injected_count + 1
			mod:echo("BetterBots: injected meta_data for " .. template_name)
		end
	end

	for template_name, meta_data in pairs(META_DATA_OVERRIDES) do
		local template = rawget(AbilityTemplates, template_name)
		local current_input = template
			and template.ability_meta_data
			and template.ability_meta_data.activation
			and template.ability_meta_data.activation.action_input
		local target_input = meta_data.activation.action_input

		if template and current_input ~= target_input then
			template.ability_meta_data = meta_data
			overridden_count = overridden_count + 1
			mod:echo(
				"BetterBots: patched meta_data for "
					.. template_name
					.. " (action_input="
					.. tostring(current_input)
					.. " -> "
					.. tostring(target_input)
					.. ")"
			)
		end
	end

	_patched_ability_templates[AbilityTemplates] = true
	_debug_log(
		"meta_injection:" .. tostring(AbilityTemplates),
		0,
		"ability template metadata patch installed (version="
			.. META_PATCH_VERSION
			.. ", injected="
			.. tostring(injected_count)
			.. ", overridden="
			.. tostring(overridden_count)
			.. ")"
	)
end

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
			"blocked " .. ability_component_name .. " (template_name=none)"
		)
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_inject_missing_ability_meta_data(AbilityTemplates)

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

	if ability_template_name == "veteran_combat_ability" then
		local can_activate = conditions._can_activate_veteran_ranger_ability(
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running
		)
		_debug_log(
			"decision:" .. ability_template_name,
			fixed_t,
			"decision " .. ability_template_name .. " -> " .. tostring(can_activate)
		)
		return can_activate
	end

	if ability_template_name == "zealot_relic" then
		local can_activate =
			conditions._can_activate_zealot_relic(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		_debug_log(
			"decision:" .. ability_template_name,
			fixed_t,
			"decision " .. ability_template_name .. " -> " .. tostring(can_activate)
		)
		return can_activate
	end

	local perception_extension = ScriptUnit.extension(unit, "perception_system")
	local _, num_nearby = perception_extension:enemies_in_proximity()
	local can_activate = num_nearby > 0

	_debug_log(
		"decision:" .. ability_template_name,
		fixed_t,
		"decision "
			.. ability_template_name
			.. " -> "
			.. tostring(can_activate)
			.. " (nearby="
			.. tostring(num_nearby)
			.. ")"
	)

	return can_activate
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

local function _reset_item_sequence_state(state, next_try_t)
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

	if next_try_t then
		state.next_try_t = next_try_t
	end
end

local ITEM_SEQUENCE_PROFILES = {
	channel = {
		required_inputs = { "channel", "wield_previous" },
		start_input = "channel",
		start_delay_after_wield = 0,
		unwield_input = nil,
		unwield_delay = 5.6,
		charge_confirm_timeout = 1.5,
	},
	press_release = {
		required_inputs = { "ability_pressed", "ability_released", "unwield_to_previous" },
		start_input = "ability_pressed",
		start_delay_after_wield = 0,
		followup_input = "ability_released",
		followup_delay = 0.08,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.35,
	},
	force_field_regular = {
		required_inputs = { "aim_force_field", "place_force_field", "unwield_to_previous" },
		start_input = "aim_force_field",
		start_delay_after_wield = 0,
		followup_input = "place_force_field",
		followup_delay = 0.08,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.45,
	},
	force_field_instant = {
		required_inputs = { "instant_aim_force_field", "instant_place_force_field", "unwield_to_previous" },
		start_input = "instant_aim_force_field",
		start_delay_after_wield = 0,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.25,
	},
	drone_regular = {
		required_inputs = { "aim_drone", "release_drone", "unwield_to_previous" },
		start_input = "aim_drone",
		start_delay_after_wield = 0,
		followup_input = "release_drone",
		followup_delay = 0.2,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.5,
	},
	drone_instant = {
		required_inputs = { "instant_aim_drone", "instant_release_drone", "unwield_to_previous" },
		start_input = "instant_aim_drone",
		start_delay_after_wield = 0,
		followup_input = "instant_release_drone",
		followup_delay = 0.05,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.4,
	},
}

local ITEM_DEFAULT_PROFILE_ORDER = {
	"channel",
	"press_release",
	"force_field_regular",
	"force_field_instant",
	"drone_regular",
	"drone_instant",
}

local ITEM_PROFILE_ORDER_BY_ABILITY = {
	zealot_relic = { "channel" },
	psyker_force_field = { "force_field_regular", "force_field_instant" },
	psyker_force_field_improved = { "force_field_regular", "force_field_instant" },
	psyker_force_field_dome = { "force_field_regular", "force_field_instant" },
	adamant_area_buff_drone = { "drone_regular", "drone_instant" },
	broker_ability_stimm_field = { "press_release" },
}

local function _ordered_item_profile_ids(ability_name)
	local ordered_ids = {}
	local seen = {}
	local preferred_ids = ITEM_PROFILE_ORDER_BY_ABILITY[ability_name]

	if preferred_ids then
		for i = 1, #preferred_ids do
			local profile_name = preferred_ids[i]

			if not seen[profile_name] then
				ordered_ids[#ordered_ids + 1] = profile_name
				seen[profile_name] = true
			end
		end
	end

	for i = 1, #ITEM_DEFAULT_PROFILE_ORDER do
		local profile_name = ITEM_DEFAULT_PROFILE_ORDER[i]

		if not seen[profile_name] then
			ordered_ids[#ordered_ids + 1] = profile_name
		end
	end

	return ordered_ids
end

local function _action_inputs_include_all(action_inputs, required_inputs)
	if not action_inputs then
		return false
	end

	for i = 1, #required_inputs do
		if action_inputs[required_inputs[i]] == nil then
			return false
		end
	end

	return true
end

local function _item_cast_sequences_for_weapon(ability_name, weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs
	if not action_inputs then
		return {}
	end

	local ordered_ids = _ordered_item_profile_ids(ability_name)
	local sequence_candidates = {}

	for i = 1, #ordered_ids do
		local profile_name = ordered_ids[i]
		local profile = ITEM_SEQUENCE_PROFILES[profile_name]

		if profile and _action_inputs_include_all(action_inputs, profile.required_inputs) then
			sequence_candidates[#sequence_candidates + 1] = {
				profile_name = profile_name,
				start_input = profile.start_input,
				start_delay_after_wield = profile.start_delay_after_wield,
				followup_input = profile.followup_input,
				followup_delay = profile.followup_delay,
				unwield_input = profile.unwield_input,
				unwield_delay = profile.unwield_delay,
				charge_confirm_timeout = profile.charge_confirm_timeout,
			}
		end
	end

	return sequence_candidates
end

local function _select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
	local sequence_candidates = _item_cast_sequences_for_weapon(ability_name, weapon_template)

	if #sequence_candidates == 0 then
		return nil
	end

	if not state.item_profile_index_by_key then
		state.item_profile_index_by_key = {}
	end

	local profile_key = ability_name .. ":" .. tostring(weapon_template_name)
	local selected_index = state.item_profile_index_by_key[profile_key] or 1
	local candidate_count = #sequence_candidates

	if selected_index > candidate_count then
		selected_index = 1
	end

	state.item_profile_index_by_key[profile_key] = selected_index

	return sequence_candidates[selected_index], profile_key, selected_index, candidate_count
end

local function _rotate_item_cast_profile(state)
	local profile_key = state.item_profile_key
	local profile_count = state.item_profile_count or 0
	local index_by_key = state.item_profile_index_by_key

	if not profile_key or not index_by_key or profile_count <= 1 then
		return false
	end

	local current_index = index_by_key[profile_key] or 1
	local next_index = current_index + 1
	if next_index > profile_count then
		next_index = 1
	end

	index_by_key[profile_key] = next_index
	return next_index ~= current_index
end

local function _schedule_item_sequence_retry(state, fixed_t, rotate_profile)
	if rotate_profile then
		_rotate_item_cast_profile(state)
	end

	_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
end

local function _schedule_ability_retry_for_unit(unit, fixed_t, retry_delay_s)
	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	local retry_t = fixed_t + (retry_delay_s or ITEM_SEQUENCE_RETRY_S)
	local next_try_t = state.next_try_t
	if not next_try_t or retry_t < next_try_t then
		state.next_try_t = retry_t
	end
end

local function _should_lock_weapon_switch_for_item_ability(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	if not inventory_component or inventory_component.wielded_slot ~= "slot_combat_ability" then
		return false
	end

	local ability_name = _equipped_combat_ability_name(unit)
	local combat_ability_component = unit_data_extension:read_component("combat_ability")
	local combat_ability_active = combat_ability_component and combat_ability_component.active == true

	if combat_ability_active and LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY[ability_name] then
		return true, ability_name, "active"
	end

	local state = _fallback_state_by_unit[unit]
	local staged_ability_name = state and state.item_ability_name
	if
		state
		and state.item_stage
		and staged_ability_name
		and LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE[staged_ability_name]
	then
		return true, staged_ability_name, "sequence"
	end

	return false
end

local function _item_attempt_charge_confirmed(unit, state, ability_name)
	local attempt_t = state.item_attempt_t
	if not attempt_t then
		return false
	end

	local charge_event = _last_charge_event_by_unit[unit]
	if not charge_event then
		return false
	end

	if charge_event.fixed_t < attempt_t then
		return false
	end

	return charge_event.ability_name == ability_name
end

local function _queue_weapon_action_input(state, input_name)
	local action_input_extension = state.action_input_extension
	if not action_input_extension then
		return
	end

	action_input_extension:bot_queue_action_input("weapon_action", input_name, nil)
end

local function _queue_item_start_input(ability_name, state, fixed_t)
	_queue_weapon_action_input(state, state.item_start_input)
	_debug_log(
		"fallback_item_start:" .. ability_name,
		fixed_t,
		"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_start_input)
	)

	state.item_attempt_t = fixed_t
	state.item_charge_confirmed = false

	if state.item_followup_input then
		state.item_stage = "waiting_followup"
		state.item_wait_t = fixed_t + (state.item_followup_delay or 0.2)
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
	else
		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + state.item_unwield_delay
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
	end
end

local function _transition_to_charge_confirmation(state, fixed_t)
	state.item_stage = "waiting_charge_confirmation"
	state.item_wait_t = fixed_t + (state.item_charge_confirm_timeout or ITEM_CHARGE_CONFIRM_TIMEOUT_S)
	state.item_stage_deadline_t = state.item_wait_t
end

local function _current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, action_input)
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"

	if not action_input then
		return true, weapon_template_name
	end

	local weapon_template = rawget(WeaponTemplates, weapon_template_name)
	local supports_input = weapon_template
		and weapon_template.action_inputs
		and weapon_template.action_inputs[action_input] ~= nil

	return supports_input and true or false, weapon_template_name
end

local function _can_use_item_fallback(unit, ability_extension, ability_name)
	if not ability_extension:can_use_ability("combat_ability") then
		return false
	end

	local perception_extension = ScriptUnit.extension(unit, "perception_system")
	local _, num_nearby = perception_extension:enemies_in_proximity()
	if num_nearby <= 0 then
		return false
	end

	if ability_name == "zealot_relic" then
		local conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
		local can_activate = conditions
			and conditions._can_activate_zealot_relic
			and conditions._can_activate_zealot_relic(unit)

		if not can_activate then
			return false
		end
	end

	return true
end

local function _fallback_try_queue_item_combat_ability(
	unit,
	unit_data_extension,
	ability_extension,
	state,
	fixed_t,
	combat_ability
)
	local ability_name = combat_ability and combat_ability.name or "unknown"
	local has_item_flow = combat_ability and not combat_ability.ability_template and combat_ability.inventory_item_name
	if not has_item_flow then
		_reset_item_sequence_state(state)
		return
	end

	if state.item_ability_name and state.item_ability_name ~= ability_name then
		_reset_item_sequence_state(state, fixed_t + 0.5)
	end

	if state.next_try_t and fixed_t < state.next_try_t then
		return
	end

	if not _can_use_item_fallback(unit, ability_extension, ability_name) then
		return
	end

	local inventory_component = unit_data_extension:read_component("inventory")
	local weapon_action_component = unit_data_extension:read_component("weapon_action")
	local wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
	local weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
	local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")
	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")

	state.action_input_extension = action_input_extension
	state.item_ability_name = ability_name

	if not state.item_charge_confirmed and _item_attempt_charge_confirmed(unit, state, ability_name) then
		state.item_charge_confirmed = true
		_debug_log(
			"fallback_item_charge_confirmed:" .. ability_name,
			fixed_t,
			"fallback item confirmed charge consume for "
				.. ability_name
				.. " (profile="
				.. tostring(state.item_profile_name)
				.. ")"
		)
	end

	if state.item_stage == "waiting_wield" then
		if wielded_slot ~= "slot_combat_ability" then
			if fixed_t >= (state.item_wield_deadline_t or 0) then
				_debug_log(
					"fallback_item_wield_timeout:" .. ability_name,
					fixed_t,
					"fallback item blocked " .. ability_name .. " (wield timeout)"
				)
				_schedule_item_sequence_retry(state, fixed_t, false)
			end

			return
		end

		if not state.item_start_input then
			local weapon_template = rawget(WeaponTemplates, weapon_template_name)
			local sequence, profile_key, selected_index, candidate_count =
				_select_item_cast_sequence(state, ability_name, weapon_template_name, weapon_template)
			if not sequence then
				_debug_log(
					"fallback_item_unsupported:" .. ability_name .. ":" .. weapon_template_name,
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (unsupported weapon template="
						.. tostring(weapon_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, false)
				return
			end

			state.item_profile_name = sequence.profile_name
			state.item_profile_key = profile_key
			state.item_profile_count = candidate_count
			state.item_start_input = sequence.start_input
			state.item_followup_input = sequence.followup_input
			state.item_followup_delay = sequence.followup_delay
			state.item_unwield_input = sequence.unwield_input
			state.item_unwield_delay = sequence.unwield_delay or 0.3
			state.item_charge_confirm_timeout = sequence.charge_confirm_timeout or ITEM_CHARGE_CONFIRM_TIMEOUT_S
			state.item_stage = "waiting_start"
			state.item_wait_t = fixed_t + (sequence.start_delay_after_wield or ITEM_DEFAULT_START_DELAY_S)
			state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S

			_debug_log(
				"fallback_item_profile:" .. ability_name .. ":" .. weapon_template_name,
				fixed_t,
				"fallback item selected profile "
					.. tostring(state.item_profile_name)
					.. " ("
					.. tostring(selected_index)
					.. "/"
					.. tostring(candidate_count)
					.. ") for "
					.. ability_name
			)
		end

		if fixed_t >= (state.item_wait_t or 0) then
			_queue_item_start_input(ability_name, state, fixed_t)
		end

		return
	end

	if state.item_stage == "waiting_start" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_start_lost_wield:" .. ability_name,
				fixed_t,
				"fallback item blocked "
					.. ability_name
					.. " (lost combat-ability wield before start; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_start_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_start_input)

		if not supports_start_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_start_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_start_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (start input drift; input="
						.. tostring(state.item_start_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		_queue_item_start_input(ability_name, state, fixed_t)

		return
	end

	if state.item_stage == "waiting_followup" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_followup_lost_wield:" .. ability_name,
				fixed_t,
				"fallback item blocked "
					.. ability_name
					.. " (lost combat-ability wield before followup; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_schedule_item_sequence_retry(state, fixed_t, true)
			return
		end

		local supports_followup_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_followup_input)

		if not supports_followup_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_followup_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_followup_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (followup input drift; input="
						.. tostring(state.item_followup_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_followup_input then
			_queue_weapon_action_input(state, state.item_followup_input)
			_debug_log(
				"fallback_item_followup:" .. ability_name,
				fixed_t,
				"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_followup_input)
			)
		end

		state.item_stage = "waiting_unwield"
		state.item_wait_t = fixed_t + (state.item_unwield_delay or 0.3)
		state.item_stage_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
		return
	end

	if state.item_stage == "waiting_unwield" then
		if wielded_slot ~= "slot_combat_ability" then
			_debug_log(
				"fallback_item_unwield_lost_slot:" .. ability_name,
				fixed_t,
				"fallback item continuing charge confirmation for "
					.. ability_name
					.. " (lost combat-ability wield during unwield stage; slot="
					.. tostring(wielded_slot)
					.. ")"
			)
			_transition_to_charge_confirmation(state, fixed_t)
			return
		end

		local supports_unwield_input, current_template_name =
			_current_weapon_supports_action_input(unit_data_extension, WeaponTemplates, state.item_unwield_input)

		if not supports_unwield_input then
			if fixed_t >= (state.item_stage_deadline_t or 0) then
				_debug_log(
					"fallback_item_unwield_input_drift:"
						.. ability_name
						.. ":"
						.. tostring(state.item_unwield_input)
						.. ":"
						.. tostring(current_template_name),
					fixed_t,
					"fallback item blocked "
						.. ability_name
						.. " (unwield input drift; input="
						.. tostring(state.item_unwield_input)
						.. ", template="
						.. tostring(current_template_name)
						.. ")"
				)
				_schedule_item_sequence_retry(state, fixed_t, true)
			end

			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		if state.item_unwield_input then
			_queue_weapon_action_input(state, state.item_unwield_input)
			_debug_log(
				"fallback_item_unwield:" .. ability_name,
				fixed_t,
				"fallback item queued " .. ability_name .. " input=" .. tostring(state.item_unwield_input)
			)
		end

		_transition_to_charge_confirmation(state, fixed_t)
		return
	end

	if state.item_stage == "waiting_charge_confirmation" then
		if state.item_charge_confirmed then
			_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
			return
		end

		if fixed_t < (state.item_wait_t or 0) then
			return
		end

		local rotated = _rotate_item_cast_profile(state)
		_debug_log(
			"fallback_item_no_charge:" .. ability_name,
			fixed_t,
			"fallback item finished without charge consume for "
				.. ability_name
				.. " (profile="
				.. tostring(state.item_profile_name)
				.. ", rotated="
				.. tostring(rotated)
				.. ")"
		)
		_reset_item_sequence_state(state, fixed_t + ITEM_SEQUENCE_RETRY_S)
		return
	end

	if wielded_slot == "slot_combat_ability" then
		state.item_stage = "waiting_wield"
		state.item_wield_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S
		return
	end

	local current_weapon_template = rawget(WeaponTemplates, weapon_template_name)
	if
		not (
			current_weapon_template
			and current_weapon_template.action_inputs
			and current_weapon_template.action_inputs.combat_ability
		)
	then
		_debug_log(
			"fallback_item_no_wield_input:" .. ability_name .. ":" .. weapon_template_name,
			fixed_t,
			"fallback item blocked "
				.. ability_name
				.. " (weapon template lacks combat_ability input: "
				.. tostring(weapon_template_name)
				.. ")"
		)
		state.next_try_t = fixed_t + ITEM_SEQUENCE_RETRY_S
		return
	end

	_queue_weapon_action_input(state, "combat_ability")
	state.item_stage = "waiting_wield"
	state.item_wield_deadline_t = fixed_t + ITEM_WIELD_TIMEOUT_S

	_debug_log(
		"fallback_item_wield:" .. ability_name,
		fixed_t,
		"fallback item queued " .. ability_name .. " input=combat_ability (wield slot_combat_ability)"
	)
end

local function _fallback_try_queue_combat_ability(unit)
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
			_fallback_try_queue_item_combat_ability(
				unit,
				unit_data_extension,
				ability_extension,
				state,
				fixed_t,
				combat_ability
			)
		end

		return
	end

	if state.item_stage then
		_reset_item_sequence_state(state)
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_inject_missing_ability_meta_data(AbilityTemplates)

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

	local perception_extension = ScriptUnit.extension(unit, "perception_system")
	local _, num_nearby = perception_extension:enemies_in_proximity()
	if num_nearby <= 0 then
		return
	end

	local action_input_extension = state.action_input_extension or ScriptUnit.extension(unit, "action_input_system")
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)

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
			.. " (nearby="
			.. tostring(num_nearby)
			.. ")"
	)
end

mod:hook_require("scripts/settings/ability/ability_templates/ability_templates", function(AbilityTemplates)
	_inject_missing_ability_meta_data(AbilityTemplates)
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions", function(conditions)
	if _patched_bt_bot_conditions[conditions] then
		return
	end

	conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	end
	_patched_bt_bot_conditions[conditions] = true

	_debug_log(
		"condition_patch:bot_conditions:" .. tostring(conditions),
		0,
		"patched bt_bot_conditions.can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
	)
end)

mod:hook_require("scripts/extension_systems/behavior/utilities/bt_conditions", function(conditions)
	if _patched_bt_conditions[conditions] then
		return
	end

	conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		return _can_activate_ability(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running)
	end
	_patched_bt_conditions[conditions] = true

	_debug_log(
		"condition_patch:bt_conditions:" .. tostring(conditions),
		0,
		"patched bt_conditions.can_activate_ability (version=" .. CONDITIONS_PATCH_VERSION .. ")"
	)
end)

mod:hook_require(
	"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
	function(BtBotActivateAbilityAction)
		mod:hook_safe(
			BtBotActivateAbilityAction,
			"enter",
			function(_self, _unit, _breed, _blackboard, scratchpad, action_data, _t)
				if not _debug_enabled() then
					return
				end

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
			_schedule_ability_retry_for_unit(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
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
					local should_lock, ability_name, lock_reason = _should_lock_weapon_switch_for_item_ability(unit)
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

mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
	mod:hook_safe(BotBehaviorExtension, "update", function(self, unit)
		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		_fallback_try_queue_combat_ability(unit)
	end)
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		_debug_log("state:GameplayStateRun", _fixed_time(), "entered GameplayStateRun")
	end
end

mod:echo("BetterBots loaded")
if _debug_enabled() then
	mod:echo("BetterBots DEBUG: logging enabled (force=" .. tostring(DEBUG_FORCE_ENABLED) .. ")")
end
