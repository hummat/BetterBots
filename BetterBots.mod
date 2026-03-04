return {
	run = function()
		fassert(googlemain ~= nil, "BetterBots must be lower than Darktide Mod Framework in your mod load order.")

		new_mod("BetterBots", {
			mod_script       = "BetterBots/scripts/mods/BetterBots/BetterBots",
			mod_data         = "BetterBots/scripts/mods/BetterBots/BetterBots_data",
			mod_localization = "BetterBots/scripts/mods/BetterBots/BetterBots_localization",
		})
	end,
	packages = {},
}
