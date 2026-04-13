local mod = get_mod("BetterBots")
local Settings = mod:io_dofile("BetterBots/scripts/mods/BetterBots/settings")
local DEFAULTS = Settings.DEFAULTS

local BOT_PROFILE_OPTIONS = {
	{ text = "bot_profile_none", value = "none" },
	{ text = "bot_profile_veteran", value = "veteran" },
	{ text = "bot_profile_zealot", value = "zealot" },
	{ text = "bot_profile_psyker", value = "psyker" },
	{ text = "bot_profile_ogryn", value = "ogryn" },
}

-- DMF mutates option.text in place during localization. Sharing the options
-- array across multiple dropdowns causes compounding fallback wraps (the
-- already-localized string fails the second lookup and gets wrapped in <>).
-- Each dropdown needs its own option tables.
local function make_slot_dropdown(slot, default_value)
	local options = {}
	for i = 1, #BOT_PROFILE_OPTIONS do
		local src = BOT_PROFILE_OPTIONS[i]
		options[i] = { text = src.text, value = src.value }
	end
	return {
		setting_id = "bot_slot_" .. tostring(slot) .. "_profile",
		type = "dropdown",
		default_value = default_value,
		options = options,
	}
end

local function make_numeric(setting_id, range, step_size)
	return {
		setting_id = setting_id,
		type = "numeric",
		default_value = DEFAULTS[setting_id],
		range = range,
		step_size = step_size,
		tooltip = setting_id .. "_description",
	}
end

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = false,
	options = {
		widgets = {
			{
				setting_id = "abilities_group",
				type = "group",
				sub_widgets = {
					{ setting_id = "enable_stances", type = "checkbox", default_value = DEFAULTS.enable_stances },
					{ setting_id = "enable_charges", type = "checkbox", default_value = DEFAULTS.enable_charges },
					{ setting_id = "enable_shouts", type = "checkbox", default_value = DEFAULTS.enable_shouts },
					{ setting_id = "enable_stealth", type = "checkbox", default_value = DEFAULTS.enable_stealth },
					{
						setting_id = "enable_deployables",
						type = "checkbox",
						default_value = DEFAULTS.enable_deployables,
					},
					{ setting_id = "enable_grenades", type = "checkbox", default_value = DEFAULTS.enable_grenades },
				},
			},
			{
				setting_id = "bot_feature_toggles_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "behavior_profile",
						type = "dropdown",
						default_value = DEFAULTS.behavior_profile,
						options = {
							{ text = "behavior_profile_aggressive", value = "aggressive" },
							{ text = "behavior_profile_balanced", value = "balanced" },
							{ text = "behavior_profile_conservative", value = "conservative" },
							{ text = "behavior_profile_testing", value = "testing" },
						},
					},
					{ setting_id = "enable_pinging", type = "checkbox", default_value = DEFAULTS.enable_pinging },
					{ setting_id = "enable_poxburster", type = "checkbox", default_value = DEFAULTS.enable_poxburster },
					{
						setting_id = "enable_melee_improvements",
						type = "checkbox",
						default_value = DEFAULTS.enable_melee_improvements,
					},
					{
						setting_id = "enable_ranged_improvements",
						type = "checkbox",
						default_value = DEFAULTS.enable_ranged_improvements,
					},
					{
						setting_id = "enable_team_cooldown",
						type = "checkbox",
						default_value = DEFAULTS.enable_team_cooldown,
					},
					{
						setting_id = "enable_engagement_leash",
						type = "checkbox",
						default_value = DEFAULTS.enable_engagement_leash,
					},
					{
						setting_id = "enable_smart_targeting",
						type = "checkbox",
						default_value = DEFAULTS.enable_smart_targeting,
					},
					{
						setting_id = "enable_daemonhost_avoidance",
						type = "checkbox",
						default_value = DEFAULTS.enable_daemonhost_avoidance,
					},
					{
						setting_id = "enable_target_type_hysteresis",
						type = "checkbox",
						default_value = DEFAULTS.enable_target_type_hysteresis,
					},
					{
						setting_id = "human_timing_profile",
						type = "dropdown",
						default_value = DEFAULTS.human_timing_profile,
						tooltip = "human_timing_profile_description",
						options = {
							{ text = "human_timing_profile_off", value = "off" },
							{ text = "human_timing_profile_fast", value = "fast" },
							{ text = "human_timing_profile_medium", value = "medium" },
							{ text = "human_timing_profile_slow", value = "slow" },
							{
								text = "human_timing_profile_custom",
								value = "custom",
								show_widgets = { 1, 2, 3, 4, 5, 6 },
							},
						},
						sub_widgets = {
							make_numeric("human_timing_reaction_min", { 0, 20 }, 1),
							make_numeric("human_timing_reaction_max", { 0, 20 }, 1),
							make_numeric("human_timing_defensive_jitter_min_ms", { 0, 1000 }, 25),
							make_numeric("human_timing_defensive_jitter_max_ms", { 0, 1000 }, 25),
							make_numeric("human_timing_opportunistic_jitter_min_ms", { 0, 1500 }, 25),
							make_numeric("human_timing_opportunistic_jitter_max_ms", { 0, 1500 }, 25),
						},
					},
					{
						setting_id = "pressure_leash_profile",
						type = "dropdown",
						default_value = DEFAULTS.pressure_leash_profile,
						tooltip = "pressure_leash_profile_description",
						options = {
							{ text = "pressure_leash_profile_off", value = "off" },
							{ text = "pressure_leash_profile_light", value = "light" },
							{ text = "pressure_leash_profile_medium", value = "medium" },
							{ text = "pressure_leash_profile_strong", value = "strong" },
							{
								text = "pressure_leash_profile_custom",
								value = "custom",
								show_widgets = { 1, 2, 3, 4 },
							},
						},
						sub_widgets = {
							make_numeric("pressure_leash_start_rating", { 0, 40 }, 1),
							make_numeric("pressure_leash_full_rating", { 1, 50 }, 1),
							make_numeric("pressure_leash_scale_percent", { 25, 100 }, 5),
							make_numeric("pressure_leash_floor_m", { 4, 12 }, 1),
						},
					},
					{
						setting_id = "enable_bot_grimoire_pickup",
						type = "checkbox",
						default_value = DEFAULTS.enable_bot_grimoire_pickup,
					},
				},
			},
			{
				setting_id = "bot_tuning_group",
				type = "group",
				sub_widgets = {
					make_numeric("sprint_follow_distance", { 0, 30 }, 2),
					make_numeric("special_chase_penalty_range", { 0, 30 }, 2),
					make_numeric("player_tag_bonus", { 0, 10 }, 1),
					make_numeric("melee_horde_light_bias", { 0, 10 }, 1),
					make_numeric("bot_ranged_ammo_threshold", { 0, 100 }, 5),
					make_numeric("bot_human_ammo_reserve_threshold", { 50, 100 }, 5),
					make_numeric("bot_grenade_charges_threshold", { 0, 12 }, 1),
					make_numeric("bot_human_grenade_reserve_threshold", { 0, 100 }, 5),
				},
			},
			{
				setting_id = "healing_deferral_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "healing_deferral_mode",
						type = "dropdown",
						default_value = DEFAULTS.healing_deferral_mode,
						options = {
							{ text = "healing_deferral_mode_off", value = "off", show_widgets = {} },
							{
								text = "healing_deferral_mode_stations_only",
								value = "stations_only",
								show_widgets = { 1, 2 },
							},
							{
								text = "healing_deferral_mode_stations_and_deployables",
								value = "stations_and_deployables",
								show_widgets = { 1, 2 },
							},
						},
						sub_widgets = {
							make_numeric("healing_deferral_human_threshold", { 50, 100 }, 5),
							make_numeric("healing_deferral_emergency_threshold", { 0, 50 }, 5),
						},
					},
				},
			},
			{
				setting_id = "bot_profiles_group",
				type = "group",
				sub_widgets = {
					make_slot_dropdown(1, DEFAULTS.bot_slot_1_profile),
					make_slot_dropdown(2, DEFAULTS.bot_slot_2_profile),
					make_slot_dropdown(3, DEFAULTS.bot_slot_3_profile),
					make_slot_dropdown(4, DEFAULTS.bot_slot_4_profile),
					make_slot_dropdown(5, DEFAULTS.bot_slot_5_profile),
					{
						setting_id = "bot_weapon_quality",
						type = "dropdown",
						default_value = DEFAULTS.bot_weapon_quality,
						options = {
							{ text = "bot_weapon_quality_auto", value = "auto" },
							{ text = "bot_weapon_quality_low", value = "low" },
							{ text = "bot_weapon_quality_medium", value = "medium" },
							{ text = "bot_weapon_quality_high", value = "high" },
							{ text = "bot_weapon_quality_max", value = "max" },
						},
					},
				},
			},
			{
				setting_id = "diagnostics_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "enable_debug_logs",
						type = "dropdown",
						default_value = DEFAULTS.enable_debug_logs,
						options = {
							{ text = "debug_log_level_off", value = "off", show_widgets = {} },
							{ text = "debug_log_level_info", value = "info", show_widgets = { 1, 2 } },
							{ text = "debug_log_level_debug", value = "debug", show_widgets = { 1, 2 } },
							{ text = "debug_log_level_trace", value = "trace", show_widgets = { 1, 2 } },
						},
						sub_widgets = {
							{
								setting_id = "enable_event_log",
								type = "checkbox",
								default_value = DEFAULTS.enable_event_log,
							},
							{
								setting_id = "enable_perf_timing",
								type = "checkbox",
								default_value = DEFAULTS.enable_perf_timing,
							},
						},
					},
				},
			},
		},
	},
}
