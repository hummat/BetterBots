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
								type = "dropdown",
								default_value = "90",
								options = {
									{ text = "healing_deferral_threshold_50", value = "50" },
									{ text = "healing_deferral_threshold_75", value = "75" },
									{ text = "healing_deferral_threshold_90", value = "90" },
									{ text = "healing_deferral_threshold_100", value = "100" },
								},
							},
							{
								setting_id = "healing_deferral_emergency_threshold",
								type = "dropdown",
								default_value = "25",
								options = {
									{ text = "healing_deferral_emergency_never", value = "never" },
									{ text = "healing_deferral_threshold_10", value = "10" },
									{ text = "healing_deferral_threshold_25", value = "25" },
									{ text = "healing_deferral_threshold_40", value = "40" },
								},
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
