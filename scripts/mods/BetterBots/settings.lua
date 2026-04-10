local M = {}

local _mod
local _combat_ability_identity

-- Category → setting ID mapping
-- These tables are the authoritative list of templates covered by each gate.
-- They are parsed by settings_spec.lua (source scan) to enforce heuristic coverage
-- and referenced by M._CATEGORY_TABLES below so introspection stays possible.
-- Runtime gating happens through combat_ability_identity.category_setting_id,
-- not a reverse lookup on these tables.
local CATEGORY_STANCES = {
	-- veteran_combat_ability is NOT here — semantic resolver maps it to stance or shout
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

M._CATEGORY_TABLES = {
	enable_stances = CATEGORY_STANCES,
	enable_charges = CATEGORY_CHARGES,
	enable_shouts = CATEGORY_SHOUTS,
	enable_stealth = CATEGORY_STEALTH,
}

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
-- sprint and special_penalty replaced by slider-with-zero (#81).
local FEATURE_GATES = {
	pinging = "enable_pinging",
	poxburster = "enable_poxburster",
	melee_improvements = "enable_melee_improvements",
	ranged_improvements = "enable_ranged_improvements",
	engagement_leash = "enable_engagement_leash",
	smart_targeting = "enable_smart_targeting",
	daemonhost_avoidance = "enable_daemonhost_avoidance",
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

M.DEFAULTS = {
	enable_stances = true,
	enable_charges = true,
	enable_shouts = true,
	enable_stealth = true,
	enable_deployables = true,
	enable_grenades = true,
	behavior_profile = "balanced",
	enable_pinging = true,
	enable_poxburster = true,
	enable_melee_improvements = true,
	enable_ranged_improvements = true,
	enable_engagement_leash = true,
	enable_smart_targeting = true,
	enable_daemonhost_avoidance = true,
	sprint_follow_distance = 12,
	special_chase_penalty_range = 18,
	player_tag_bonus = 3,
	melee_horde_light_bias = 4,
	bot_ranged_ammo_threshold = 20,
	bot_human_ammo_reserve_threshold = 80,
	healing_deferral_mode = "stations_and_deployables",
	healing_deferral_human_threshold = 90,
	healing_deferral_emergency_threshold = 25,
	bot_slot_1_profile = "zealot",
	bot_slot_2_profile = "psyker",
	bot_slot_3_profile = "ogryn",
	bot_slot_4_profile = "none",
	bot_slot_5_profile = "none",
	bot_weapon_quality = "auto",
	enable_debug_logs = "off",
	enable_event_log = false,
	enable_perf_timing = false,
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

function M.init(deps)
	assert(deps.combat_ability_identity, "settings: combat_ability_identity dep required")
	_mod = deps.mod
	_combat_ability_identity = deps.combat_ability_identity
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
	return _read_percent_setting(BOT_RANGED_AMMO_THRESHOLD_SETTING_ID, DEFAULT_BOT_RANGED_AMMO_THRESHOLD, 0, 100)
end

function M.human_ammo_reserve_threshold()
	return _read_percent_setting(HUMAN_AMMO_RESERVE_THRESHOLD_SETTING_ID, DEFAULT_HUMAN_AMMO_RESERVE_THRESHOLD, 50, 100)
end

-- Read a raw numeric setting (no percentage conversion).
-- Returns default_value when nil, non-numeric, or out of [min_value, max_value].
local function _read_numeric_setting(setting_id, default_value, min_value, max_value)
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

	return numeric_value
end

-- Slider-with-zero migration helper: read the slider setting, but if it's nil
-- (user hasn't touched it) AND a legacy checkbox was explicitly false, return 0.
local function _read_slider_with_legacy(slider_id, legacy_id, default_value, min_value, max_value)
	if not _mod then
		return default_value
	end

	local slider_raw = _mod:get(slider_id)
	if slider_raw ~= nil then
		return _read_numeric_setting(slider_id, default_value, min_value, max_value)
	end

	-- Slider not set — check legacy checkbox migration
	local legacy_value = _mod:get(legacy_id)
	if legacy_value == false then
		return 0
	end

	return default_value
end

function M.player_tag_bonus()
	return _read_numeric_setting("player_tag_bonus", 3, 0, 10)
end

function M.melee_horde_light_bias()
	return _read_numeric_setting("melee_horde_light_bias", 4, 0, 10)
end

function M.sprint_follow_distance()
	return _read_slider_with_legacy("sprint_follow_distance", "enable_sprint", 12, 0, 30)
end

function M.special_chase_penalty_range()
	return _read_slider_with_legacy("special_chase_penalty_range", "enable_special_penalty", 18, 0, 30)
end

function M.is_combat_template_enabled(template_name, ability_extension)
	local identity = _combat_ability_identity.resolve(nil, ability_extension, { template_name = template_name })
	local semantic_setting_id = _combat_ability_identity.category_setting_id(identity)
	if not semantic_setting_id then
		return true
	end

	return _setting_enabled(semantic_setting_id)
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
