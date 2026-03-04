return {
	run = function()
		fassert(googlemain ~= nil, "BotAbilities must be lower than Darktide Mod Framework in your mod load order.")

		new_mod("BotAbilities", {
			mod_script       = "BotAbilities/scripts/mods/BotAbilities/BotAbilities",
			mod_data         = "BotAbilities/scripts/mods/BotAbilities/BotAbilities_data",
			mod_localization = "BotAbilities/scripts/mods/BotAbilities/BotAbilities_localization",
		})
	end,
	packages = {},
}
