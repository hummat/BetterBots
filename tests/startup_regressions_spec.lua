local Localization = dofile("scripts/mods/BetterBots/BetterBots_localization.lua")

local function has_bare_percent(str)
	local i = 1

	while i <= #str do
		local char = str:sub(i, i)

		if char == "%" then
			local next_char = str:sub(i + 1, i + 1)

			if next_char ~= "%" then
				return true
			end

			i = i + 2
		else
			i = i + 1
		end
	end

	return false
end

describe("startup regressions", function()
	it("escapes percent signs in localized setting labels", function()
		for key, entry in pairs(Localization) do
			local english = entry and entry.en

			if type(english) == "string" then
				assert.is_false(
					has_bare_percent(english),
					string.format("localization key %s contains bare %% in %q", key, english)
				)
			end
		end
	end)

	it("loads log_levels through mod io without a double .lua suffix", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/log_levels"%)', 1))
	end)

	it("loads animation_guard through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/animation_guard"%)', 1))
	end)

	it("routes startup debug chatter through the log-level gate instead of unconditional echo", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_nil(source:find('mod:echo%("BetterBots DEBUG: logging enabled %(level=', 1))
		assert.is_truthy(source:find('_debug_log%(%s*"startup:logging"', 1))
	end)
end)
