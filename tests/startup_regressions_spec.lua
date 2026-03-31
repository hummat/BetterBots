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

local function each_mod_source_file(callback)
	local handle = assert(io.popen("find scripts/mods/BetterBots -maxdepth 1 -name '*.lua' | sort"))
	for path in handle:lines() do
		callback(path)
	end
	handle:close()
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

	it("loads shared helper modules through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/shared_rules"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/bot_targeting"%)', 1))
	end)

	it("loads smart_targeting through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/smart_targeting"%)', 1))
	end)

	it("loads animation_guard through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/animation_guard"%)', 1))
	end)

	it("loads airlock_guard through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/airlock_guard"%)', 1))
	end)

	it("loads melee_attack_choice through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/melee_attack_choice"%)', 1))
	end)

	it("initializes and registers extracted runtime modules", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find("AnimationGuard%.init%(", 1))
		assert.is_truthy(source:find("AnimationGuard%.register_hooks%(", 1))
		assert.is_truthy(source:find("AirlockGuard%.init%(", 1))
		assert.is_truthy(source:find("AirlockGuard%.register_hooks%(", 1))
		assert.is_truthy(source:find("SmartTargeting%.init%(", 1))
		assert.is_truthy(source:find("SmartTargeting%.register_hooks%(", 1))
		assert.is_truthy(source:find("MeleeAttackChoice%.init%(", 1))
		assert.is_truthy(source:find("MeleeAttackChoice%.register_hooks%(", 1))
	end)

	it("keeps mod-local helper loading in BetterBots.lua instead of leaf modules", function()
		each_mod_source_file(function(path)
			if path ~= "scripts/mods/BetterBots/BetterBots.lua" then
				local handle = assert(io.open(path, "r"))
				local source = assert(handle:read("*a"))
				handle:close()

				assert.is_nil(
					source:find('require%("scripts/mods/BetterBots/', 1),
					path .. " must not require BetterBots local modules directly"
				)
				assert.is_nil(
					source:find('dofile%("scripts/mods/BetterBots/', 1),
					path .. " must not dofile BetterBots local modules directly"
				)
			end
		end)
	end)

	it("routes startup debug chatter through the log-level gate instead of unconditional echo", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_nil(source:find('mod:echo%("BetterBots DEBUG: logging enabled %(level=', 1))
		assert.is_truthy(source:find('_debug_log%(%s*"startup:logging"', 1))
	end)

	it("heuristics.lua uses breed.ranged for ranged_count (not tags.ranged)", function()
		local handle = assert(io.open("scripts/mods/BetterBots/heuristics.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_nil(
			source:find('_is_tagged%(tags, "ranged"%)' ),
			"ranged_count must use enemy_breed.ranged, not _is_tagged(tags, 'ranged')"
		)
		assert.is_not_nil(
			source:find("enemy_breed%.ranged"),
			"ranged_count classification must check enemy_breed.ranged"
		)
	end)
end)
