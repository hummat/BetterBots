local mod = get_mod("BetterBots")

return {
	name = "Better Bots",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "enable_debug_logs",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "enable_event_log",
				type = "checkbox",
				default_value = false,
			},
		},
	},
}
