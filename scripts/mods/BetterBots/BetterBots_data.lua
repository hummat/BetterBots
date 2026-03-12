local mod = get_mod("BetterBots")

return {
	name = "Better Bots",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "behavior_profile",
				type = "dropdown",
				default_value = "standard",
				options = {
					{ text = "behavior_profile_standard", value = "standard" },
					{ text = "behavior_profile_testing", value = "testing" },
				},
			},
			{
				setting_id = "healing_deferral_mode",
				type = "dropdown",
				default_value = "stations_and_deployables",
				options = {
					{ text = "healing_deferral_mode_off", value = "off" },
					{ text = "healing_deferral_mode_stations_only", value = "stations_only" },
					{
						text = "healing_deferral_mode_stations_and_deployables",
						value = "stations_and_deployables",
					},
				},
			},
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
			{
				setting_id = "enable_tier_1_abilities",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_tier_2_abilities",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_tier_3_abilities",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_grenade_blitz_abilities",
				type = "checkbox",
				default_value = true,
			},
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
			{
				setting_id = "enable_event_log",
				type = "checkbox",
				default_value = false,
			},
		},
	},
}
