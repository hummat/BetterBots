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
	team_cooldown = "enable_team_cooldown",
	engagement_leash = "enable_engagement_leash",
	smart_targeting = "enable_smart_targeting",
	daemonhost_avoidance = "enable_daemonhost_avoidance",
	target_type_hysteresis = "enable_target_type_hysteresis",
	ammo_policy = "enable_ammo_policy",
	bot_tome_pickup = "enable_bot_tome_pickup",
	weakspot_aim = "enable_weakspot_aim",
	charge_nav_validation = "enable_charge_nav_validation",
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
local DEFAULT_HUMAN_GRENADE_RESERVE_THRESHOLD = 1.00
local HUMAN_GRENADE_RESERVE_THRESHOLD_SETTING_ID = "bot_human_grenade_reserve_threshold"
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
	enable_team_cooldown = true,
	enable_engagement_leash = true,
	enable_smart_targeting = true,
	enable_daemonhost_avoidance = true,
	enable_target_type_hysteresis = true,
	enable_ammo_policy = true,
	enable_bot_tome_pickup = true,
	enable_weakspot_aim = true,
	enable_charge_nav_validation = true,
	human_timing_profile = "auto",
	pressure_leash_profile = "auto",
	human_timing_reaction_min = 2,
	human_timing_reaction_max = 4,
	human_timing_defensive_jitter_min_ms = 100,
	human_timing_defensive_jitter_max_ms = 250,
	human_timing_opportunistic_jitter_min_ms = 250,
	human_timing_opportunistic_jitter_max_ms = 700,
	pressure_leash_start_rating = 12,
	pressure_leash_full_rating = 30,
	pressure_leash_scale_percent = 65,
	pressure_leash_floor_m = 7,
	enable_bot_grimoire_pickup = false,
	sprint_follow_distance = 12,
	special_chase_penalty_range = 18,
	player_tag_bonus = 3,
	melee_horde_light_bias = 4,
	bot_ranged_ammo_threshold = 20,
	bot_human_ammo_reserve_threshold = 80,
	bot_human_grenade_reserve_threshold = 100,
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

local HUMAN_TIMING_PROFILES = {
	off = {
		enabled = false,
		reaction_min = 10,
		reaction_max = 20,
		defensive_jitter_min_s = 0,
		defensive_jitter_max_s = 0,
		opportunistic_jitter_min_s = 0,
		opportunistic_jitter_max_s = 0,
	},
	fast = {
		enabled = true,
		reaction_min = 1,
		reaction_max = 3,
		defensive_jitter_min_s = 0.05,
		defensive_jitter_max_s = 0.15,
		opportunistic_jitter_min_s = 0.15,
		opportunistic_jitter_max_s = 0.45,
	},
	medium = {
		enabled = true,
		reaction_min = 2,
		reaction_max = 4,
		defensive_jitter_min_s = 0.10,
		defensive_jitter_max_s = 0.25,
		opportunistic_jitter_min_s = 0.25,
		opportunistic_jitter_max_s = 0.70,
	},
	slow = {
		enabled = true,
		reaction_min = 3,
		reaction_max = 6,
		defensive_jitter_min_s = 0.15,
		defensive_jitter_max_s = 0.35,
		opportunistic_jitter_min_s = 0.40,
		opportunistic_jitter_max_s = 1.00,
	},
}

local PRESSURE_LEASH_PROFILES = {
	off = {
		enabled = false,
		start_rating = 10,
		full_rating = 30,
		scale_multiplier = 1.0,
		floor_m = 6,
	},
	light = {
		enabled = true,
		start_rating = 16,
		full_rating = 36,
		scale_multiplier = 0.80,
		floor_m = 8,
	},
	medium = {
		enabled = true,
		start_rating = 12,
		full_rating = 30,
		scale_multiplier = 0.65,
		floor_m = 7,
	},
	strong = {
		enabled = true,
		start_rating = 8,
		full_rating = 24,
		scale_multiplier = 0.50,
		floor_m = 6,
	},
}

local AUTO_HUMAN_TIMING_PROFILE_BY_CHALLENGE = {
	[1] = "slow",
	[2] = "slow",
	[3] = "medium",
	[4] = "fast",
	[5] = "fast",
}

local AUTO_PRESSURE_LEASH_PROFILE_BY_CHALLENGE = {
	[1] = "light",
	[2] = "light",
	[3] = "medium",
	[4] = "medium",
	[5] = "strong",
}

local HUMAN_TIMING_PROFILE_OPTIONS = {
	auto = true,
	off = true,
	fast = true,
	medium = true,
	slow = true,
	custom = true,
}

local PRESSURE_LEASH_PROFILE_OPTIONS = {
	auto = true,
	off = true,
	light = true,
	medium = true,
	strong = true,
	custom = true,
}

local function _copy_config(config)
	local copy = {}
	for key, value in pairs(config) do
		copy[key] = value
	end
	return copy
end

local function _resolve_profile(setting_id, sibling_setting_id, legacy_id, valid_values, default_value)
	if not _mod then
		return default_value
	end

	local explicit_value = _mod:get(setting_id)
	if explicit_value ~= nil then
		if valid_values[explicit_value] then
			return explicit_value
		end
		return default_value
	end

	if _mod:get(sibling_setting_id) == nil and _mod:get(legacy_id) == false then
		return "off"
	end

	return default_value
end

local function _current_challenge()
	local difficulty_manager = Managers and Managers.state and Managers.state.difficulty
	return difficulty_manager and difficulty_manager:get_challenge() or 3
end

local function _resolve_auto_profile(auto_profiles_by_challenge, fallback_profile)
	local challenge = _current_challenge()
	local profile = auto_profiles_by_challenge[challenge]

	if profile then
		return profile
	end

	return auto_profiles_by_challenge[3] or fallback_profile
end

local function _read_custom_numeric_setting(setting_id, min_value, max_value)
	if not _mod then
		return nil
	end

	local raw_value = _mod:get(setting_id)
	local numeric_value = tonumber(raw_value)
	if not numeric_value then
		return nil
	end

	if numeric_value < min_value or numeric_value > max_value then
		return nil
	end

	return numeric_value
end

function M.human_grenade_reserve_threshold()
	return _read_percent_setting(
		HUMAN_GRENADE_RESERVE_THRESHOLD_SETTING_ID,
		DEFAULT_HUMAN_GRENADE_RESERVE_THRESHOLD,
		0,
		100
	)
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

function M.human_timing_profile()
	return _resolve_profile(
		"human_timing_profile",
		"pressure_leash_profile",
		"enable_human_likeness",
		HUMAN_TIMING_PROFILE_OPTIONS,
		"auto"
	)
end

function M.pressure_leash_profile()
	return _resolve_profile(
		"pressure_leash_profile",
		"human_timing_profile",
		"enable_human_likeness",
		PRESSURE_LEASH_PROFILE_OPTIONS,
		"auto"
	)
end

function M.resolve_human_timing_config()
	local profile = M.human_timing_profile()
	if profile == "auto" then
		profile = _resolve_auto_profile(AUTO_HUMAN_TIMING_PROFILE_BY_CHALLENGE, "medium")
	end
	if profile ~= "custom" then
		return _copy_config(HUMAN_TIMING_PROFILES[profile] or HUMAN_TIMING_PROFILES.medium)
	end

	local fallback = HUMAN_TIMING_PROFILES.medium
	local reaction_min = _read_custom_numeric_setting("human_timing_reaction_min", 0, 20)
	local reaction_max = _read_custom_numeric_setting("human_timing_reaction_max", 0, 20)
	local defensive_min_ms = _read_custom_numeric_setting("human_timing_defensive_jitter_min_ms", 0, 1000)
	local defensive_max_ms = _read_custom_numeric_setting("human_timing_defensive_jitter_max_ms", 0, 1000)
	local opportunistic_min_ms = _read_custom_numeric_setting("human_timing_opportunistic_jitter_min_ms", 0, 1500)
	local opportunistic_max_ms = _read_custom_numeric_setting("human_timing_opportunistic_jitter_max_ms", 0, 1500)

	if
		not reaction_min
		or not reaction_max
		or not defensive_min_ms
		or not defensive_max_ms
		or not opportunistic_min_ms
		or not opportunistic_max_ms
		or reaction_min > reaction_max
		or defensive_min_ms > defensive_max_ms
		or opportunistic_min_ms > opportunistic_max_ms
	then
		return _copy_config(fallback)
	end

	return {
		enabled = true,
		reaction_min = reaction_min,
		reaction_max = reaction_max,
		defensive_jitter_min_s = defensive_min_ms / 1000,
		defensive_jitter_max_s = defensive_max_ms / 1000,
		opportunistic_jitter_min_s = opportunistic_min_ms / 1000,
		opportunistic_jitter_max_s = opportunistic_max_ms / 1000,
	}
end

function M.resolve_pressure_leash_config()
	local profile = M.pressure_leash_profile()
	if profile == "auto" then
		profile = _resolve_auto_profile(AUTO_PRESSURE_LEASH_PROFILE_BY_CHALLENGE, "medium")
	end
	if profile ~= "custom" then
		return _copy_config(PRESSURE_LEASH_PROFILES[profile] or PRESSURE_LEASH_PROFILES.medium)
	end

	local fallback = PRESSURE_LEASH_PROFILES.medium
	local start_rating = _read_custom_numeric_setting("pressure_leash_start_rating", 0, 40)
	local full_rating = _read_custom_numeric_setting("pressure_leash_full_rating", 1, 50)
	local scale_percent = _read_custom_numeric_setting("pressure_leash_scale_percent", 25, 100)
	local floor_m = _read_custom_numeric_setting("pressure_leash_floor_m", 4, 12)

	if not start_rating or not full_rating or not scale_percent or not floor_m or full_rating <= start_rating then
		return _copy_config(fallback)
	end

	return {
		enabled = true,
		start_rating = start_rating,
		full_rating = full_rating,
		scale_multiplier = scale_percent / 100,
		floor_m = floor_m,
	}
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

function M.is_bot_grimoire_pickup_enabled()
	if not _mod then
		return M.DEFAULTS.enable_bot_grimoire_pickup
	end

	local value = _mod:get("enable_bot_grimoire_pickup")
	if value == nil then
		return M.DEFAULTS.enable_bot_grimoire_pickup
	end

	return value == true
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
