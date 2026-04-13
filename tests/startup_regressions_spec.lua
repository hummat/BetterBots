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

local function read_file(path)
	local handle = assert(io.open(path, "r"))
	local source = assert(handle:read("*a"))
	handle:close()
	return source
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

	it("loads revive_ability through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/revive_ability"%)', 1))
	end)

	it("loads sustained_fire through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/sustained_fire"%)', 1))
	end)

	it("loads mule_pickup through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/mule_pickup"%)', 1))
	end)

	it("loads companion_tag through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/companion_tag"%)', 1))
	end)

	it("initializes and registers extracted runtime modules", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")

		assert.is_truthy(source:find("AnimationGuard%.init%(", 1))
		assert.is_truthy(source:find("AnimationGuard%.register_hooks%(", 1))
		assert.is_truthy(source:find("AirlockGuard%.init%(", 1))
		assert.is_truthy(source:find("AirlockGuard%.register_hooks%(", 1))
		assert.is_truthy(source:find("SmartTargeting%.init%(", 1))
		assert.is_truthy(source:find("SmartTargeting%.register_hooks%(", 1))
		assert.is_truthy(source:find("MeleeAttackChoice%.init%(", 1))
		assert.is_truthy(source:find("MeleeAttackChoice%.register_hooks%(", 1))
		assert.is_truthy(source:find("ReviveAbility%.init%(", 1))
		assert.is_truthy(source:find("ReviveAbility%.register_hooks%(", 1))
		assert.is_truthy(source:find("SustainedFire%.init%(", 1))
		assert.is_truthy(source:find('mod:hook_require%("scripts/extension_systems/input/bot_unit_input"', 1))
		assert.is_truthy(source:find("SustainedFire%.install_bot_unit_input_hooks%(", 1))
		assert.is_truthy(source:find("Sprint%.install_bot_unit_input_hooks%(", 1))
		assert.is_truthy(source:find('mod:hook_require%("scripts/extension_systems/group/bot_group"', 1))
		assert.is_truthy(source:find("HealingDeferral%.install_bot_group_hooks%(", 1))
		assert.is_truthy(source:find("MulePickup%.install_bot_group_hooks%(", 1))
		assert.is_truthy(source:find("MulePickup%.init%(", 1))
		assert.is_truthy(source:find("MulePickup%.register_hooks%(", 1))
		assert.is_truthy(source:find("CompanionTag%.init%(", 1))
		assert.is_truthy(source:find("CompanionTag%.update%(", 1))
	end)

	it("wires Perf into AbilityQueue initialization", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local init_block = assert(source:match("AbilityQueue%.init%(%{%s*(.-)%s*%}%)"))

		assert.is_truthy(init_block:find("perf%s*=%s*Perf", 1))
	end)

	it("suppresses auto perf dumps when no bot frames were sampled", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local auto_dump = assert(source:match("local function _auto_dump_perf_report%(%)%s*(.-)%s*end"))

		assert.is_truthy(auto_dump:find("report%.bot_frames%s*<=%s*0", 1))
	end)

	it("rejects duplicate hook_require targets across BetterBots source files", function()
		local owners_by_target = {}
		local duplicates = {}

		each_mod_source_file(function(path)
			local source = read_file(path)

			for target in source:gmatch('hook_require%(%s*"([^"]+)"') do
				local owners = owners_by_target[target]
				if not owners then
					owners = {}
					owners_by_target[target] = owners
				end

				local already_listed = false
				for i = 1, #owners do
					if owners[i] == path then
						already_listed = true
						break
					end
				end

				if not already_listed then
					owners[#owners + 1] = path
				end
			end
		end)

		for target, owners in pairs(owners_by_target) do
			if #owners > 1 then
				table.sort(owners)
				duplicates[#duplicates + 1] = target .. " => " .. table.concat(owners, ", ")
			end
		end

		table.sort(duplicates)
		assert.same({}, duplicates)
	end)

	it("guards hook_require registration against same-path clobbers at runtime", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")

		assert.is_truthy(source:find("local _original_hook_require = mod%.hook_require", 1))
		assert.is_truthy(source:find("local _hook_require_callsite_by_path = {}", 1, true))
		assert.is_truthy(source:find("BetterBots duplicate hook_require for %%s", 1))
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

	it("keeps the startup banner free of hardcoded module counts", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:echo%("BetterBots loaded"%)', 1))
		assert.is_nil(source:find('mod:echo%("BetterBots loaded %(', 1))
		assert.is_nil(source:find("local _MODULE_COUNT =", 1, true))
	end)

	it("emits an install log for the consolidated bt_bot_melee_action hook", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('"hook_require:bt_bot_melee_action"', 1))
	end)

	it("keeps BotBehaviorExtension hook_require consolidated in BetterBots.lua", function()
		local main_source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local revive_source = read_file("scripts/mods/BetterBots/revive_ability.lua")

		local hook_pattern = 'hook_require%("scripts/extension_systems/behavior/bot_behavior_extension"'
		local main_count = 0
		for _ in main_source:gmatch(hook_pattern) do
			main_count = main_count + 1
		end
		local revive_count = 0
		for _ in revive_source:gmatch(hook_pattern) do
			revive_count = revive_count + 1
		end

		assert.equals(1, main_count)
		assert.equals(0, revive_count)
		assert.is_truthy(main_source:find("ReviveAbility%.install_behavior_ext_hooks", 1))
		assert.is_truthy(main_source:find("MulePickup%.install_behavior_ext_hooks", 1))
	end)

	it("persists /bb_reset through DMF instead of the BetterBots mod object", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('rawget%(_G, "dmf"%)', 1))
		assert.is_truthy(source:find('type%(dmf_module%.save_unsaved_settings_to_file%) == "function"', 1))
		assert.is_truthy(source:find("dmf_module%.save_unsaved_settings_to_file%(", 1))
		assert.is_nil(source:find("mod%.save_unsaved_settings_to_file", 1))
		assert.is_nil(source:find("mod:save_unsaved_settings_to_file", 1))
	end)

	it("refreshes human-likeness BotSettings patch when setting changes", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find("function mod%.on_setting_changed%(setting_id%)", 1))
		assert.is_truthy(source:find("local TIMING_SETTING_IDS = {", 1, true))
		assert.is_truthy(source:find("human_timing_profile = true", 1, true))
		assert.is_truthy(source:find("human_timing_opportunistic_jitter_max_ms = true", 1, true))
		assert.is_truthy(source:find("if TIMING_SETTING_IDS%[setting_id%] then", 1))
		assert.is_truthy(source:find("HumanLikeness%.patch_bot_settings%(", 1))
		assert.is_nil(source:find('if setting_id == "enable_human_likeness" then', 1, true))
	end)

	it("eagerly patches BotSettings in case bot_settings was already required", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:hook_require%("scripts/settings/bot/bot_settings"', 1))
		assert.is_truthy(source:find('pcall%(require, "scripts/settings/bot/bot_settings"%)', 1))
	end)

	it("refreshes live mule pickup state when the grimoire setting changes", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('if setting_id == "enable_bot_grimoire_pickup" then', 1, true))
		assert.is_truthy(source:find("MulePickup%.patch_pickups%(", 1))
		assert.is_truthy(source:find("MulePickup%.sync_live_bot_groups%(", 1))
	end)

	it("exposes the full 0-100 bot ranged ammo slider in DMF settings", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots_data.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('make_numeric("bot_ranged_ammo_threshold", { 0, 100 }, 5)', 1, true))
	end)

	it("keeps settings UI organized through widget factories and a flat bot team setup group", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots_data.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find("local DEFAULTS = Settings.DEFAULTS", 1, true))
		assert.is_truthy(source:find("local function make_slot_dropdown", 1, true))
		assert.is_truthy(source:find('setting_id = "bot_feature_toggles_group"', 1, true))
		assert.is_truthy(source:find('setting_id = "bot_tuning_group"', 1, true))
		assert.is_truthy(source:find('setting_id = "healing_deferral_group"', 1, true))
		assert.is_truthy(source:find('setting_id = "bot_profiles_group"', 1, true))
		assert.is_truthy(source:find("make_slot_dropdown%(1, DEFAULTS%.bot_slot_1_profile%)"))
		assert.is_truthy(source:find("make_slot_dropdown%(5, DEFAULTS%.bot_slot_5_profile%)"))
		assert.is_truthy(source:find('setting_id = "bot_weapon_quality"', 1, true))
		assert.is_nil(source:find('setting_id = "bot_slots_core_group"', 1, true))
		assert.is_nil(source:find('setting_id = "bot_slots_tertium_group"', 1, true))
		assert.is_truthy(source:find('text = "behavior_profile_testing", value = "testing"', 1, true))
		local loc_handle = assert(io.open("scripts/mods/BetterBots/BetterBots_localization.lua", "r"))
		local localization = assert(loc_handle:read("*a"))
		loc_handle:close()
		assert.is_truthy(localization:find('bot_weapon_quality = {%s*en = "Bot weapon quality"', 1))
		assert.is_nil(localization:find("bot_slots_core_group = {", 1, true))
		assert.is_nil(localization:find("bot_slots_tertium_group = {", 1, true))
		assert.is_truthy(localization:find('bot_weapon_quality_max = {%s*en = "Max %(fully upgraded%)"', 1))
	end)

	it("centralizes combat ability identity instead of duplicating veteran sniffers", function()
		local function read(path)
			local handle = assert(io.open(path, "r"))
			local source = assert(handle:read("*a"))
			handle:close()
			return source
		end

		local settings = read("scripts/mods/BetterBots/settings.lua")
		local heuristics = read("scripts/mods/BetterBots/heuristics.lua")
		local revive = read("scripts/mods/BetterBots/revive_ability.lua")

		assert.is_nil(settings:find("local function _veteran_class_tag", 1, true))
		assert.is_nil(heuristics:find("local function _resolve_veteran_class_tag", 1, true))
		assert.is_nil(revive:find("local function _combat_ability_name", 1, true))
	end)

	it("heuristics.lua uses breed.ranged for ranged_count (not tags.ranged)", function()
		local handle = assert(io.open("scripts/mods/BetterBots/heuristics.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_nil(
			source:find('_is_tagged%(tags, "ranged"%)'),
			"ranged_count must use enemy_breed.ranged, not _is_tagged(tags, 'ranged')"
		)
		assert.is_not_nil(
			source:find("enemy_breed%.ranged"),
			"ranged_count classification must check enemy_breed.ranged"
		)
	end)

	describe("cross-module category drift guard", function()
		local function extract_table_keys(source, table_name)
			local block = source:match("local%s+" .. table_name .. "%s*=%s*(%b{})")
			assert.is_not_nil(block, "could not find '" .. table_name .. "' in source")
			local keys = {}
			-- Match bare identifiers on the LHS of '=' (not inside ["string"] form)
			for key in block:gmatch("([%w_]+)%s*=") do
				keys[key] = true
			end
			return keys
		end

		it("TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY keys all exist in team_cooldown CATEGORY_MAP", function()
			local identity_source = read_file("scripts/mods/BetterBots/combat_ability_identity.lua")
			local team_source = read_file("scripts/mods/BetterBots/team_cooldown.lua")

			local identity_keys = extract_table_keys(identity_source, "TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY")
			local team_keys = extract_table_keys(team_source, "CATEGORY_MAP")

			assert.is_true(next(identity_keys) ~= nil, "identity TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY is empty")
			assert.is_true(next(team_keys) ~= nil, "team_cooldown CATEGORY_MAP is empty")

			for key in pairs(identity_keys) do
				assert.is_true(
					team_keys[key] == true,
					"combat_ability_identity.TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY key '"
						.. key
						.. "' is missing from team_cooldown.CATEGORY_MAP — drift detected"
				)
			end

			-- Inverse: team_cooldown CATEGORY_MAP entries that look like semantic keys
			-- (not raw engine templates) should be known to the identity module.
			for key in pairs(team_keys) do
				assert.is_true(
					identity_keys[key] == true,
					"team_cooldown.CATEGORY_MAP key '"
						.. key
						.. "' is missing from combat_ability_identity.TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY — drift detected"
				)
			end
		end)

		it("CATEGORY_SETTING_BY_SEMANTIC_KEY entries match settings.lua CATEGORY_* tables", function()
			local Settings = dofile("scripts/mods/BetterBots/settings.lua")
			local identity_source = read_file("scripts/mods/BetterBots/combat_ability_identity.lua")

			local identity_keys = extract_table_keys(identity_source, "CATEGORY_SETTING_BY_SEMANTIC_KEY")
			assert.is_true(next(identity_keys) ~= nil, "CATEGORY_SETTING_BY_SEMANTIC_KEY is empty")

			local settings_union = {}
			assert.is_not_nil(Settings._CATEGORY_TABLES, "settings._CATEGORY_TABLES not exposed")
			for _, tbl in pairs(Settings._CATEGORY_TABLES) do
				for template_name in pairs(tbl) do
					settings_union[template_name] = true
				end
			end

			-- Forward: every non-veteran semantic key in the identity module must appear
			-- in at least one of settings.lua's CATEGORY_* tables. Veteran shared templates
			-- (veteran_combat_ability_stance/shout) are resolved by the identity module
			-- itself and intentionally absent from the settings tables.
			for key in pairs(identity_keys) do
				if not key:match("^veteran_") then
					assert.is_true(
						settings_union[key] == true,
						"combat_ability_identity semantic key '"
							.. key
							.. "' is missing from settings.lua CATEGORY_* tables — drift detected"
					)
				end
			end

			-- Inverse: every template in the settings CATEGORY_* tables must have a
			-- category_setting_id entry in the identity module.
			for template_name in pairs(settings_union) do
				assert.is_true(
					identity_keys[template_name] == true,
					"settings.lua CATEGORY_* template '"
						.. template_name
						.. "' is missing from combat_ability_identity.CATEGORY_SETTING_BY_SEMANTIC_KEY — drift detected"
				)
			end
		end)
	end)

	describe("widget parity guard", function()
		it("surfaces the new human-likeness profile widgets and localization keys", function()
			local data_source = read_file("scripts/mods/BetterBots/BetterBots_data.lua")
			local localization_source = read_file("scripts/mods/BetterBots/BetterBots_localization.lua")

			assert.is_truthy(data_source:find('setting_id = "human_timing_profile"', 1, true))
			assert.is_truthy(data_source:find('setting_id = "pressure_leash_profile"', 1, true))
			assert.is_truthy(data_source:find('text = "human_timing_profile_auto", value = "auto"', 1, true))
			assert.is_truthy(data_source:find('text = "pressure_leash_profile_auto", value = "auto"', 1, true))
			assert.is_nil(data_source:find('setting_id = "enable_human_likeness"', 1, true))
			assert.is_truthy(data_source:find("show_widgets = { 1, 2, 3, 4, 5, 6 }", 1, true))
			assert.is_truthy(data_source:find("show_widgets = { 1, 2, 3, 4 }", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_description = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_auto = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_off = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_fast = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_medium = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_slow = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_profile_custom = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_reaction_min_description = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_reaction_max_description = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_defensive_jitter_min_ms_description = {", 1, true))
			assert.is_truthy(localization_source:find("human_timing_defensive_jitter_max_ms_description = {", 1, true))
			assert.is_truthy(
				localization_source:find("human_timing_opportunistic_jitter_min_ms_description = {", 1, true)
			)
			assert.is_truthy(
				localization_source:find("human_timing_opportunistic_jitter_max_ms_description = {", 1, true)
			)
			assert.is_truthy(localization_source:find("pressure_leash_profile = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_description = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_auto = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_off = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_light = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_medium = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_strong = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_profile_custom = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_start_rating_description = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_full_rating_description = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_scale_percent_description = {", 1, true))
			assert.is_truthy(localization_source:find("pressure_leash_floor_m_description = {", 1, true))
		end)

		it("every widget setting_id has a matching Settings.DEFAULTS entry and vice versa", function()
			local Settings = dofile("scripts/mods/BetterBots/settings.lua")
			local data_source = read_file("scripts/mods/BetterBots/BetterBots_data.lua")

			-- Extract all setting_id string literals from the widget definitions.
			-- Skip fragment strings that are part of Lua concatenations (..) used by
			-- factory functions like make_slot_dropdown — those are synthesized below.
			local widget_ids = {}
			for prefix, setting_id, suffix in data_source:gmatch('([%.]?)setting_id%s*=%s*"([^"]+)"([^,}]*)') do
				local is_concat_fragment = suffix:find("%.%.") ~= nil
				if not is_concat_fragment and not setting_id:match("_group$") and prefix ~= "." then
					widget_ids[setting_id] = true
				end
			end

			-- Synthesized slot dropdowns are generated by make_slot_dropdown(1..5) and
			-- only appear in the source as 'bot_slot_" .. tostring(slot) .. "_profile'.
			-- Detect the factory call and inject the expected ids.
			if data_source:find("make_slot_dropdown%(%s*1%s*,") then
				for slot = 1, 5 do
					widget_ids["bot_slot_" .. slot .. "_profile"] = true
				end
			end
			-- make_numeric("foo", ...) is already covered by the setting_id regex pattern
			-- because make_numeric passes the id through as a string literal at call site.
			for setting_id in data_source:gmatch('make_numeric%(%s*"([^"]+)"') do
				widget_ids[setting_id] = true
			end

			assert.is_true(next(widget_ids) ~= nil, "no widget setting_ids discovered in BetterBots_data.lua")

			-- Forward: every widget id must map to a DEFAULTS entry
			for id in pairs(widget_ids) do
				assert.is_not_nil(
					Settings.DEFAULTS[id],
					"widget setting_id '" .. id .. "' has no matching entry in Settings.DEFAULTS"
				)
			end

			-- Inverse: every DEFAULTS key must have a matching widget
			for id in pairs(Settings.DEFAULTS) do
				assert.is_true(
					widget_ids[id] == true,
					"Settings.DEFAULTS['" .. id .. "'] has no matching widget in BetterBots_data.lua"
				)
			end
		end)
	end)

	it("engagement_leash module loads without error", function()
		local ok, result = pcall(dofile, "scripts/mods/BetterBots/engagement_leash.lua")
		assert.is_true(ok, "engagement_leash.lua failed to load: " .. tostring(result))
		assert.is_not_nil(result)
		assert.is_not_nil(result.init)
		assert.is_not_nil(result.register_hooks)
		assert.is_not_nil(result.compute_effective_leash)
		assert.is_not_nil(result.record_charge)
		assert.is_not_nil(result.is_movement_ability)
	end)
end)
