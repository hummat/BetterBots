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
