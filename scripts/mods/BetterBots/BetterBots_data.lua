local mod = get_mod("BetterBots")

return {
	name = "Better Bots",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
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
