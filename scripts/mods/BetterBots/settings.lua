local M = {}

local _mod

-- Category → setting ID mapping
local CATEGORY_STANCES = {
	-- veteran_combat_ability is NOT here — uses dual-category gate
	psyker_overcharge_stance = true,
	ogryn_gunlugger_stance = true,
	adamant_stance = true,
	broker_focus = true,
	broker_punk_rage = true,
}

local CATEGORY_CHARGES = {
	zealot_dash = true,
	zealot_targeted_dash = true,
	zealot_targeted_dash_improved = true,
	zealot_targeted_dash_improved_double = true,
	ogryn_charge = true,
	ogryn_charge_increased_distance = true,
	adamant_charge = true,
}

local CATEGORY_SHOUTS = {
	psyker_shout = true,
	ogryn_taunt_shout = true,
	adamant_shout = true,
}

local CATEGORY_STEALTH = {
	veteran_stealth_combat_ability = true,
	zealot_invisibility = true,
}

-- Reverse lookup: template_name → setting_id
-- Built once at load time. veteran_combat_ability excluded (dual-category).
local TEMPLATE_TO_CATEGORY_SETTING = {}

local CATEGORY_TO_SETTING = {
	{ table = CATEGORY_STANCES, setting = "enable_stances" },
	{ table = CATEGORY_CHARGES, setting = "enable_charges" },
	{ table = CATEGORY_SHOUTS, setting = "enable_shouts" },
	{ table = CATEGORY_STEALTH, setting = "enable_stealth" },
}

for _, entry in ipairs(CATEGORY_TO_SETTING) do
	for template_name in pairs(entry.table) do
		TEMPLATE_TO_CATEGORY_SETTING[template_name] = entry.setting
	end
end

-- Deployable item abilities (all map to enable_deployables)
local DEPLOYABLE_ITEMS = {
	zealot_relic = true,
	psyker_force_field = true,
	psyker_force_field_improved = true,
	psyker_force_field_dome = true,
	adamant_area_buff_drone = true,
	broker_ability_stimm_field = true,
}

-- Feature gates: feature_name → setting_id
local FEATURE_GATES = {
	sprint = "enable_sprint",
	pinging = "enable_pinging",
	special_penalty = "enable_special_penalty",
	poxburster = "enable_poxburster",
	melee_improvements = "enable_melee_improvements",
	ranged_improvements = "enable_ranged_improvements",
	engagement_leash = "enable_engagement_leash",
}

-- Preset system
local _warned_unknown_features = {}

local VALID_PRESETS = {
	testing = true,
	aggressive = true,
	balanced = true,
	conservative = true,
}
local DEFAULT_BOT_RANGED_AMMO_THRESHOLD = 0.20
local DEFAULT_HUMAN_AMMO_RESERVE_THRESHOLD = 0.80
local BOT_RANGED_AMMO_THRESHOLD_SETTING_ID = "bot_ranged_ammo_threshold"
local HUMAN_AMMO_RESERVE_THRESHOLD_SETTING_ID = "bot_human_ammo_reserve_threshold"

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

local function _read_percent_setting(setting_id, default_value, min_value, max_value)
	if not _mod then
		return default_value
	end

	local raw_value = _mod:get(setting_id)
	local numeric_value = tonumber(raw_value)
	if not numeric_value then
		return default_value
	end

	if numeric_value < min_value or numeric_value > max_value then
		return default_value
	end

	return numeric_value / 100
end

-- Minimal veteran class_tag resolution for the dual-category gate.
-- Duplicates _resolve_veteran_class_tag from heuristics.lua because settings.lua
-- is loaded before heuristics.lua and cannot import from it (heuristics.lua
-- receives resolve_preset from settings.lua via init(), creating a mutual dependency).
local function _veteran_class_tag(ability_extension)
	local equipped = ability_extension and ability_extension._equipped_abilities
	local combat = equipped and equipped.combat_ability
	local tweak = combat and combat.ability_template_tweak_data
	local class_tag = tweak and tweak.class_tag

	if class_tag then
		return class_tag
	end

	local name = combat and combat.name or ""
	if string.find(name, "shout", 1, true) then
		return "squad_leader"
	end
	if string.find(name, "stance", 1, true) then
		return "ranger"
	end

	return nil
end

function M.init(deps)
	_mod = deps.mod
end

function M.resolve_preset()
	if not _mod then
		return "balanced"
	end

	local value = _mod:get("behavior_profile")

	-- Silent migration: "standard" → "balanced"
	if value == "standard" then
		return "balanced"
	end

	if VALID_PRESETS[value] then
		return value
	end

	return "balanced"
end

function M.is_testing_profile()
	return M.resolve_preset() == "testing"
end

function M.bot_ranged_ammo_threshold()
	return _read_percent_setting(BOT_RANGED_AMMO_THRESHOLD_SETTING_ID, DEFAULT_BOT_RANGED_AMMO_THRESHOLD, 5, 30)
end

function M.human_ammo_reserve_threshold()
	return _read_percent_setting(HUMAN_AMMO_RESERVE_THRESHOLD_SETTING_ID, DEFAULT_HUMAN_AMMO_RESERVE_THRESHOLD, 50, 100)
end

function M.is_combat_template_enabled(template_name, ability_extension)
	-- Dual-category gate for veteran_combat_ability
	if template_name == "veteran_combat_ability" then
		local tag = _veteran_class_tag(ability_extension)
		if tag == "squad_leader" then
			return _setting_enabled("enable_shouts")
		end
		-- ranger, base, or unknown → stances
		return _setting_enabled("enable_stances")
	end

	local setting_id = TEMPLATE_TO_CATEGORY_SETTING[template_name]
	if not setting_id then
		return true
	end

	return _setting_enabled(setting_id)
end

function M.is_item_ability_enabled(ability_name)
	if DEPLOYABLE_ITEMS[ability_name] then
		return _setting_enabled("enable_deployables")
	end

	return true
end

function M.is_grenade_enabled(_grenade_name)
	return _setting_enabled("enable_grenades")
end

-- Feature gates are mod-internal constants (unlike template names, which come from
-- game data). An unknown feature_name is always a bug — but we fail open to avoid
-- crashing in production. The test suite validates all wired feature names.
function M.is_feature_enabled(feature_name)
	local setting_id = FEATURE_GATES[feature_name]
	if not setting_id then
		if not _warned_unknown_features[feature_name] and _mod and _mod.warning then
			_warned_unknown_features[feature_name] = true
			_mod:warning("BetterBots: unknown feature gate '" .. tostring(feature_name) .. "' (defaulting to enabled)")
		end
		return true
	end

	return _setting_enabled(setting_id)
end

return M
