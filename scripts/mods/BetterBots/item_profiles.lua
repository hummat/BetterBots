-- Item ability sequence profiles and selector logic.
-- item_fallback.lua owns queueing; this module only chooses the sequence shape.
local M = {}

local LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY = {
	zealot_relic = true,
}

local LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
	adamant_area_buff_drone = true,
}

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
		followup_delay = 0.6,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.7,
	},
	force_field_regular = {
		required_inputs = { "aim_force_field", "place_force_field", "unwield_to_previous" },
		start_input = "aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "place_force_field",
		followup_delay = 0.35,
		unwield_input = "unwield_to_previous",
		unwield_delay = 1.6,
		charge_confirm_timeout = 2.2,
	},
	force_field_instant = {
		required_inputs = { "instant_aim_force_field", "instant_place_force_field", "unwield_to_previous" },
		start_input = "instant_aim_force_field",
		start_delay_after_wield = 0.05,
		followup_input = "instant_place_force_field",
		followup_delay = 0.12,
		unwield_input = "unwield_to_previous",
		unwield_delay = 0.5,
		charge_confirm_timeout = 2.0,
	},
	drone_regular = {
		required_inputs = { "aim_drone", "release_drone", "unwield_to_previous" },
		start_input = "aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "release_drone",
		followup_delay = 0.35,
		unwield_input = "unwield_to_previous",
		unwield_delay = 2.3,
		charge_confirm_timeout = 2.2,
	},
	drone_instant = {
		required_inputs = { "instant_aim_drone", "instant_release_drone", "unwield_to_previous" },
		start_input = "instant_aim_drone",
		start_delay_after_wield = 0.05,
		followup_input = "instant_release_drone",
		followup_delay = 0.1,
		unwield_input = "unwield_to_previous",
		unwield_delay = 1.1,
		charge_confirm_timeout = 2.0,
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

local function ordered_profile_ids(ability_name)
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

local function action_inputs_include_all(action_inputs, required_inputs)
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

local function item_cast_sequences_for_weapon(ability_name, weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs
	if not action_inputs then
		return {}
	end

	local ordered_ids = ordered_profile_ids(ability_name)
	local sequence_candidates = {}

	for i = 1, #ordered_ids do
		local profile_name = ordered_ids[i]
		local profile = ITEM_SEQUENCE_PROFILES[profile_name]

		if profile and action_inputs_include_all(action_inputs, profile.required_inputs) then
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

function M.select_sequence(state, ability_name, weapon_template_name, weapon_template)
	local sequence_candidates = item_cast_sequences_for_weapon(ability_name, weapon_template)

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

function M.rotate_profile(state)
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

function M.should_lock_active_ability(ability_name)
	return LOCK_WEAPON_SWITCH_WHILE_ACTIVE_ABILITY[ability_name] == true
end

function M.should_lock_sequence(ability_name)
	return LOCK_WEAPON_SWITCH_DURING_ITEM_SEQUENCE[ability_name] == true
end

return M
