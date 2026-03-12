local M = {}

local _mod

local BEHAVIOR_PROFILE_SETTING_ID = "behavior_profile"
local ENABLE_TIER_1_ABILITIES_SETTING_ID = "enable_tier_1_abilities"
local ENABLE_TIER_2_ABILITIES_SETTING_ID = "enable_tier_2_abilities"
local ENABLE_TIER_3_ABILITIES_SETTING_ID = "enable_tier_3_abilities"
local ENABLE_GRENADE_BLITZ_ABILITIES_SETTING_ID = "enable_grenade_blitz_abilities"

local DEFAULT_BEHAVIOR_PROFILE = "standard"
local VALID_BEHAVIOR_PROFILES = {
	standard = true,
	testing = true,
}

local TIER_1_COMBAT_TEMPLATES = {
	veteran_combat_ability = true,
	veteran_stealth_combat_ability = true,
	psyker_overcharge_stance = true,
	ogryn_gunlugger_stance = true,
	adamant_stance = true,
	broker_focus = true,
	broker_punk_rage = true,
}

local TIER_2_COMBAT_TEMPLATES = {
	zealot_dash = true,
	zealot_targeted_dash = true,
	zealot_targeted_dash_improved = true,
	zealot_targeted_dash_improved_double = true,
	zealot_invisibility = true,
	psyker_shout = true,
	ogryn_charge = true,
	ogryn_charge_increased_distance = true,
	ogryn_taunt_shout = true,
	adamant_charge = true,
	adamant_shout = true,
}

local TIER_3_ITEM_ABILITIES = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
	adamant_area_buff_drone = true,
	broker_ability_stimm_field = true,
}

local function _setting_enabled(setting_id)
	if not _mod then
		return true
	end

	local value = _mod:get(setting_id)
	if value == nil then
		return true
	end

	return value == true
end

function M.init(deps)
	_mod = deps.mod
end

function M.resolve_behavior_profile()
	if not _mod then
		return DEFAULT_BEHAVIOR_PROFILE
	end

	local value = _mod:get(BEHAVIOR_PROFILE_SETTING_ID)
	if VALID_BEHAVIOR_PROFILES[value] then
		return value
	end

	return DEFAULT_BEHAVIOR_PROFILE
end

function M.is_testing_profile()
	return M.resolve_behavior_profile() == "testing"
end

function M.is_combat_template_enabled(template_name)
	if TIER_1_COMBAT_TEMPLATES[template_name] then
		return _setting_enabled(ENABLE_TIER_1_ABILITIES_SETTING_ID)
	end

	if TIER_2_COMBAT_TEMPLATES[template_name] then
		return _setting_enabled(ENABLE_TIER_2_ABILITIES_SETTING_ID)
	end

	return true
end

function M.is_item_ability_enabled(ability_name)
	if TIER_3_ITEM_ABILITIES[ability_name] then
		return _setting_enabled(ENABLE_TIER_3_ABILITIES_SETTING_ID)
	end

	return true
end

function M.is_grenade_enabled(_grenade_name)
	return _setting_enabled(ENABLE_GRENADE_BLITZ_ABILITIES_SETTING_ID)
end

return M
