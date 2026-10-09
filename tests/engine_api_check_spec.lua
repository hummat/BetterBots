local EngineApiCheck = dofile("scripts/engine_api_check.lua")

local ENGINE_ABILITY_FILE = "scripts/extension_systems/ability/player_unit_ability_extension.lua"
local ENGINE_ABILITY_BASE_FILE = "scripts/extension_systems/ability/ability_extension_base.lua"
local BASE_TEMPLATE_FILE = "scripts/settings/equipment/weapon_templates/base_template_settings.lua"
local GENERATOR_FILE = "scripts/settings/equipment/weapon_templates/weapon_template_generators/drone_generator.lua"
local CONSTANTS_FILE = "scripts/settings/player_character/player_character_constants.lua"

local function write_tree(root, files)
	for relative, content in pairs(files) do
		local path = root .. "/" .. relative
		assert(os.execute("mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'"))
		local handle = assert(io.open(path, "w"))
		handle:write(content)
		handle:close()
	end
end

local function make_root()
	local root = os.tmpname()
	os.remove(root)
	assert(os.execute("mkdir -p '" .. root .. "'"))
	return root
end

local function engine_tree()
	return {
		[ENGINE_ABILITY_BASE_FILE] = table.concat({
			"-- chunkname: base",
			'local AbilityExtensionBase = class("AbilityExtensionBase")',
			"AbilityExtensionBase.init = function (self)",
			"\tself._equipped_abilities = {}",
			"end",
			"AbilityExtensionBase.can_use_ability = function (self, ability_type)",
			"end",
		}, "\n"),
		[ENGINE_ABILITY_FILE] = table.concat({
			"-- chunkname: player",
			'local PlayerUnitAbilityExtension = class("PlayerUnitAbilityExtension", "AbilityExtensionBase")',
			"PlayerUnitAbilityExtension.remaining_ability_charges = function (self, ability_type)",
			"end",
		}, "\n"),
		[BASE_TEMPLATE_FILE] = table.concat({
			"local base_template_settings = {}",
			"base_template_settings.action_inputs = {",
			"\twield = {",
			"\t\tbuffer_time = 0.4,",
			"\t\tinput_sequence = {",
			"\t\t\t{ inputs = wield_inputs },",
			"\t\t},",
			"\t},",
			"}",
		}, "\n"),
		[GENERATOR_FILE] = table.concat({
			"base_template.action_inputs = {",
			"\t\taim_drone = { buffer_time = 0 },",
			"\t}",
			"weapon_template.action_inputs.channel = { buffer_time = 0.2 }",
		}, "\n"),
		[CONSTANTS_FILE] = table.concat({
			"slot_combat_ability = {",
			"\twield_inputs = {",
			'\t\tpressed = { "combat_ability_pressed" },',
			"\t},",
			"}",
		}, "\n"),
	}
end

local function run(mod_files, test_helper_source, engine_files)
	local repo_root = make_root()
	local decompile_root = make_root()
	local files = {
		["scripts/mods/BetterBots/BetterBots.lua"] = "",
		["tests/test_helper.lua"] = test_helper_source or "",
	}
	for name, source in pairs(mod_files) do
		files["scripts/mods/BetterBots/" .. name] = source
	end
	write_tree(repo_root, files)
	write_tree(decompile_root, engine_files or engine_tree())

	local errors = EngineApiCheck.run(repo_root, decompile_root)
	os.execute("rm -rf '" .. repo_root .. "' '" .. decompile_root .. "'")
	return errors
end

describe("engine API usage check", function()
	it("flags a removed method called through a binding wrapped across lines", function()
		local errors = run({
			["debug.lua"] = table.concat({
				"local function state(unit)",
				"\tlocal ability_extension = ScriptUnit.has_extension",
				'\t\tand ScriptUnit.has_extension(unit, "ability_system")',
				'\treturn ability_extension:remaining_ability_cooldown("combat_ability")',
				"end",
			}, "\n"),
		})

		assert.same({
			"scripts/mods/BetterBots/debug.lua:4: ability_extension.remaining_ability_cooldown"
				.. " not found on any ability_system engine class",
		}, errors)
	end)

	it("flags removed methods when the call is wrapped before the colon or the parenthesis", function()
		local errors = run({
			["debug.lua"] = table.concat({
				'local ability_extension = ScriptUnit.extension(unit, "ability_system")',
				"local cooldown = ability_extension",
				'\t:remaining_ability_cooldown("combat_ability")',
				"local max = ability_extension:max_ability_cooldown",
				'\t("combat_ability")',
			}, "\n"),
		})

		assert.same({
			"scripts/mods/BetterBots/debug.lua:3: ability_extension.remaining_ability_cooldown"
				.. " not found on any ability_system engine class",
			"scripts/mods/BetterBots/debug.lua:4: ability_extension.max_ability_cooldown"
				.. " not found on any ability_system engine class",
		}, errors)
	end)

	it("resolves parameters by a name bound elsewhere and accepts inherited methods and fields", function()
		local errors = run({
			["binder.lua"] = 'local ability_extension = ScriptUnit.extension(unit, "ability_system")\n',
			["user.lua"] = table.concat({
				"local function ready(ability_extension)",
				'\tlocal charges = ability_extension:remaining_ability_charges("combat_ability")',
				"\tlocal equipped = ability_extension._equipped_abilities",
				'\treturn ability_extension:can_use_ability("combat_ability") and ability_extension:gone()',
				"end",
			}, "\n"),
		})

		assert.same({
			"scripts/mods/BetterBots/user.lua:4: ability_extension.gone not found on any ability_system engine class",
		}, errors)
	end)

	it("ignores field receivers, writes, mod-owned markers, comments, and strings", function()
		local errors = run({
			["binder.lua"] = 'local extension = ScriptUnit.has_extension(unit, "ability_system")\n',
			["user.lua"] = table.concat({
				'local side_system = Managers.state.extension:system("side_system")',
				"extension.cached_by_mod = true",
				"local marker = extension._betterbots_player_unit or extension.__bb_installed",
				"-- extension:removed_in_comment()",
				'local text = "extension:removed_in_string()"',
			}, "\n"),
		})

		assert.same({}, errors)
	end)

	it("fails a system whose extension directory cannot be found", function()
		local errors = run({
			["user.lua"] = table.concat({
				'local renamed = ScriptUnit.has_extension(unit, "renamed_system")',
				"return renamed:anything()",
			}, "\n"),
		})

		assert.equals(1, #errors)
		assert.matches("renamed_system used by BetterBots has no engine classes", errors[1], 1, true)
	end)

	it("checks mock builder allowlists against the doubled class, including inherited members", function()
		local errors = run(
			{},
			table.concat({
				'_apply_audited_overrides("make_player_ability_extension", ext, opts.overrides, {',
				"\tcan_use_ability = true,",
				"\t_equipped_abilities = true,",
				"\tremaining_ability_cooldown = true,",
				"})",
				'_apply_audited_overrides("make_invented_extension", ext, opts.overrides, {',
				"\tanything = true,",
				"})",
			}, "\n")
		)

		assert.same({
			"tests/test_helper.lua: builder make_invented_extension has no engine class mapping"
				.. " (add it to BUILDER_CLASSES in scripts/engine_api_check.lua)",
			"tests/test_helper.lua: make_player_ability_extension allows remaining_ability_cooldown,"
				.. " which PlayerUnitAbilityExtension does not define",
		}, errors)
	end)

	it("flags queued action inputs no template defines and raw inputs no slot wields", function()
		local errors = run({
			["queue.lua"] = table.concat({
				'action_input_extension:bot_queue_action_input("weapon_action", "combat_ability", nil)',
				"_queue_weapon_action_input(",
				"\tstate,",
				'\t"grenade_ability"',
				")",
				'local PROFILE = { required_inputs = { "channel", "removed_input" }, aim_input = "buffer_time" }',
				'ext:bot_queue_action_input("weapon_action", "wield", "wield_9")',
				'M.SLOT_WIELD_RAW_INPUT = "wield_8"',
			}, "\n"),
		})

		local prefix = "scripts/mods/BetterBots/queue.lua:"
		assert.same({
			prefix .. '1: action input "combat_ability" is not defined by any weapon or ability template',
			prefix .. '2: action input "grenade_ability" is not defined by any weapon or ability template',
			prefix .. '6: action input "buffer_time" is not defined by any weapon or ability template',
			prefix .. '6: action input "removed_input" is not defined by any weapon or ability template',
			prefix .. '7: raw input "wield_9" is not a slot wield input in player_character_constants.lua',
			prefix .. '8: raw input "wield_8" is not a slot wield input in player_character_constants.lua',
		}, errors)
	end)

	it("flags single-quoted queued inputs the same as double-quoted ones", function()
		local errors = run({
			["queue.lua"] = table.concat({
				"ext:bot_queue_action_input('weapon_action', 'combat_ability', nil)",
				"ext:bot_queue_action_input('weapon_action', 'wield', 'wield_9')",
				"local PROFILE = { required_inputs = { 'removed_input' }, aim_input = 'buffer_time' }",
			}, "\n"),
		})

		local prefix = "scripts/mods/BetterBots/queue.lua:"
		assert.same({
			prefix .. '1: action input "combat_ability" is not defined by any weapon or ability template',
			prefix .. '2: raw input "wield_9" is not a slot wield input in player_character_constants.lua',
			prefix .. '3: action input "buffer_time" is not defined by any weapon or ability template',
			prefix .. '3: action input "removed_input" is not defined by any weapon or ability template',
		}, errors)
	end)

	it("accepts generator and appended template inputs and ignores comparisons, components, and log text", function()
		local errors = run({
			["queue.lua"] = table.concat({
				'ext:bot_queue_action_input("weapon_action", "wield", "combat_ability_pressed")',
				'_queue_weapon_action_input(state, "aim_drone")',
				'local PROFILE = { start_input = "channel", wield_input = "combat_ability_pressed" }',
				'local ITEM = { unwield_input = "aim_drone" }',
				'queue_weapon_input(unit, "aim_drone", "grenade_ability_action")',
				'if action_input == "removed_input" then end',
				'local text = ", fire_input=" .. tostring(fire_input)',
				'local COMBAT_ABILITY_WIELD_RAW_INPUT = "combat_ability_pressed"',
			}, "\n"),
		})

		assert.same({}, errors)
	end)

	it("fails closed when the decompiled tree has no input tables to check against", function()
		local engine_files = engine_tree()
		engine_files[BASE_TEMPLATE_FILE] = nil
		engine_files[GENERATOR_FILE] = nil
		engine_files[CONSTANTS_FILE] = nil

		local errors = run({}, nil, engine_files)

		assert.same({
			"found no action_inputs tables under scripts/settings/ (parser drift)",
			"found no wield_inputs in scripts/settings/player_character/player_character_constants.lua",
		}, errors)
	end)
end)
