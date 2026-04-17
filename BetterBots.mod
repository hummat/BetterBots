return {
	run = function()
		if not rawget(_G, "new_mod") then
			error("BetterBots must be lower than Darktide Mod Framework in your mod load order.")
		end

		new_mod("BetterBots", {
			mod_script       = "BetterBots/scripts/mods/BetterBots/BetterBots",
			mod_data         = "BetterBots/scripts/mods/BetterBots/BetterBots_data",
			mod_localization = "BetterBots/scripts/mods/BetterBots/BetterBots_localization",
		})
	end,
	packages = {},
}
