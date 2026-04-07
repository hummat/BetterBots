local mod = get_mod("BetterBots")

return {
	name = "Better Bots",
	description = mod:localize("mod_description"),
	is_togglable = false,
	options = {
		widgets = {
			-- Group: Abilities
			{
				setting_id = "abilities_group",
				type = "group",
				sub_widgets = {
					{ setting_id = "enable_stances", type = "checkbox", default_value = true },
					{ setting_id = "enable_charges", type = "checkbox", default_value = true },
					{ setting_id = "enable_shouts", type = "checkbox", default_value = true },
					{ setting_id = "enable_stealth", type = "checkbox", default_value = true },
					{ setting_id = "enable_deployables", type = "checkbox", default_value = true },
					{ setting_id = "enable_grenades", type = "checkbox", default_value = true },
				},
			},
			-- Group: Bot Behavior
			{
				setting_id = "bot_behavior_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "behavior_profile",
						type = "dropdown",
						default_value = "balanced",
						options = {
							{ text = "behavior_profile_testing", value = "testing" },
							{ text = "behavior_profile_aggressive", value = "aggressive" },
							{ text = "behavior_profile_balanced", value = "balanced" },
							{ text = "behavior_profile_conservative", value = "conservative" },
						},
					},
					{ setting_id = "enable_sprint", type = "checkbox", default_value = true },
					{ setting_id = "enable_pinging", type = "checkbox", default_value = true },
					{ setting_id = "enable_special_penalty", type = "checkbox", default_value = true },
					{ setting_id = "enable_poxburster", type = "checkbox", default_value = true },
					{ setting_id = "enable_melee_improvements", type = "checkbox", default_value = true },
					{ setting_id = "enable_ranged_improvements", type = "checkbox", default_value = true },
					{ setting_id = "enable_engagement_leash", type = "checkbox", default_value = true },
					{
						setting_id = "bot_ranged_ammo_threshold",
						type = "numeric",
						default_value = 20,
						range = { 0, 100 },
						step_size = 5,
					},
					{
						setting_id = "bot_human_ammo_reserve_threshold",
						type = "numeric",
						default_value = 80,
						range = { 50, 100 },
						step_size = 5,
					},
					{
						setting_id = "healing_deferral_mode",
						type = "dropdown",
						default_value = "stations_and_deployables",
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
							{
								setting_id = "healing_deferral_human_threshold",
								type = "numeric",
								default_value = 90,
								range = { 50, 100 },
								step_size = 5,
							},
							{
								setting_id = "healing_deferral_emergency_threshold",
								type = "numeric",
								default_value = 25,
								range = { 0, 50 },
								step_size = 5,
							},
						},
					},
				},
			},
			-- Group: Bot Profiles
			{
				setting_id = "bot_profiles_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "bot_slot_1_profile",
						type = "dropdown",
						default_value = "zealot",
						options = {
							{ text = "bot_profile_none", value = "none" },
							{ text = "bot_profile_veteran", value = "veteran" },
							{ text = "bot_profile_zealot", value = "zealot" },
							{ text = "bot_profile_psyker", value = "psyker" },
							{ text = "bot_profile_ogryn", value = "ogryn" },
						},
					},
					{
						setting_id = "bot_slot_2_profile",
						type = "dropdown",
						default_value = "psyker",
						options = {
							{ text = "bot_profile_none", value = "none" },
							{ text = "bot_profile_veteran", value = "veteran" },
							{ text = "bot_profile_zealot", value = "zealot" },
							{ text = "bot_profile_psyker", value = "psyker" },
							{ text = "bot_profile_ogryn", value = "ogryn" },
						},
					},
					{
						setting_id = "bot_slot_3_profile",
						type = "dropdown",
						default_value = "ogryn",
						options = {
							{ text = "bot_profile_none", value = "none" },
							{ text = "bot_profile_veteran", value = "veteran" },
							{ text = "bot_profile_zealot", value = "zealot" },
							{ text = "bot_profile_psyker", value = "psyker" },
							{ text = "bot_profile_ogryn", value = "ogryn" },
						},
					},
					{
						setting_id = "bot_slot_4_profile",
						type = "dropdown",
						default_value = "none",
						options = {
							{ text = "bot_profile_none", value = "none" },
							{ text = "bot_profile_veteran", value = "veteran" },
							{ text = "bot_profile_zealot", value = "zealot" },
							{ text = "bot_profile_psyker", value = "psyker" },
							{ text = "bot_profile_ogryn", value = "ogryn" },
						},
					},
					{
						setting_id = "bot_slot_5_profile",
						type = "dropdown",
						default_value = "none",
						options = {
							{ text = "bot_profile_none", value = "none" },
							{ text = "bot_profile_veteran", value = "veteran" },
							{ text = "bot_profile_zealot", value = "zealot" },
							{ text = "bot_profile_psyker", value = "psyker" },
							{ text = "bot_profile_ogryn", value = "ogryn" },
						},
					},
					{
						setting_id = "bot_weapon_quality",
						type = "dropdown",
						default_value = "auto",
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
			-- Group: Diagnostics
			{
				setting_id = "diagnostics_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "enable_debug_logs",
						type = "dropdown",
						default_value = "off",
						options = {
							{ text = "debug_log_level_off", value = "off" },
							{ text = "debug_log_level_info", value = "info" },
							{ text = "debug_log_level_debug", value = "debug" },
							{ text = "debug_log_level_trace", value = "trace" },
						},
					},
					{ setting_id = "enable_event_log", type = "checkbox", default_value = false },
					{ setting_id = "enable_perf_timing", type = "checkbox", default_value = false },
				},
			},
		},
	},
}
