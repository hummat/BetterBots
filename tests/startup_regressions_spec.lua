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

local function find_named_call(calls, module_name)
	for i = 1, #calls do
		if calls[i].module == module_name then
			return calls[i]
		end
	end

	return nil
end

local function find_install_call(calls, module_name, method_name)
	for i = 1, #calls do
		local entry = calls[i]
		if entry.module == module_name and entry.method == method_name then
			return entry
		end
	end

	return nil
end

local function find_echo(echoes, pattern)
	for i = 1, #echoes do
		if string.find(echoes[i], pattern, 1, true) then
			return echoes[i]
		end
	end

	return nil
end

local function sorted_keys(map)
	local keys = {}

	for key in pairs(map) do
		keys[#keys + 1] = key
	end

	table.sort(keys)

	return keys
end

local function make_runtime_module(module_name, install_calls, extra)
	local module = extra or {}

	if module.init == nil then
		module.init = function(deps)
			install_calls.init_calls[#install_calls.init_calls + 1] = {
				module = module_name,
				deps = deps,
			}
		end
	end

	if module.wire == nil then
		module.wire = function(refs)
			install_calls.wire_calls[#install_calls.wire_calls + 1] = {
				module = module_name,
				refs = refs,
			}
		end
	end

	if module.register_hooks == nil then
		module.register_hooks = function(...)
			install_calls.register_calls[#install_calls.register_calls + 1] = {
				module = module_name,
				args = { ... },
			}
		end
	end

	return module
end

local function make_bootstrap_harness(module_overrides)
	local saved_get_mod = rawget(_G, "get_mod")
	local saved_require = require
	local saved_script_unit = rawget(_G, "ScriptUnit")
	local saved_blackboards = rawget(_G, "BLACKBOARDS")
	local hook_require_callbacks = {}
	local install_calls = {
		init_calls = {},
		wire_calls = {},
		register_calls = {},
		install_calls = {},
	}
	local echoes = {}
	local warnings = {}
	local commands = {}
	local hook_registrations = {}
	local settings = {
		enable_debug_logs = 0,
		enable_event_log = false,
		enable_perf_timing = false,
	}
	module_overrides = module_overrides or {}

	local function record_install(module_name, method_name, ...)
		install_calls.install_calls[#install_calls.install_calls + 1] = {
			module = module_name,
			method = method_name,
			args = { ... },
		}
	end

	local modules = {}

	modules.LogLevels = make_runtime_module("LogLevels", install_calls, {
		resolve_setting = function()
			return 0
		end,
		should_log = function()
			return false
		end,
		level_name = function()
			return "off"
		end,
	})

	modules.SharedRules = {}
	modules.BotTargeting = {}
	modules.CombatAbilityIdentity = make_runtime_module("CombatAbilityIdentity", install_calls, {
		resolve = function()
			return nil
		end,
	})
	modules.TeamCooldown = make_runtime_module("TeamCooldown", install_calls, {
		record = function() end,
		reset = function() end,
	})
	modules.MetaData = make_runtime_module("MetaData", install_calls, {
		inject = function() end,
	})
	modules.Settings = make_runtime_module("Settings", install_calls, {
		resolve_human_timing_config = function()
			return {}
		end,
		resolve_pressure_leash_config = function()
			return {}
		end,
		is_testing_profile = function()
			return false
		end,
		resolve_preset = function()
			return "default"
		end,
		is_feature_enabled = function()
			return false
		end,
		sprint_follow_distance = function()
			return 12
		end,
		player_tag_bonus = function()
			return 1
		end,
		special_chase_penalty_range = function()
			return 8
		end,
		bot_ranged_ammo_threshold = function()
			return 20
		end,
		melee_horde_light_bias = function()
			return 0.5
		end,
		is_item_ability_enabled = function()
			return true
		end,
		is_combat_template_enabled = function()
			return true
		end,
		is_grenade_enabled = function()
			return true
		end,
		is_bot_grimoire_pickup_enabled = function()
			return false
		end,
		DEFAULTS = {},
	})
	modules.Heuristics = make_runtime_module("Heuristics", install_calls, {
		build_context = function()
			return {}
		end,
		resolve_decision = function()
			return false, "noop", {}
		end,
		evaluate_item_heuristic = function()
			return false, "noop"
		end,
		evaluate_grenade_heuristic = function()
			return false, "noop"
		end,
		normalize_grenade_context = function(_unit, context)
			return context
		end,
		enemy_breed = function()
			return nil
		end,
	})
	modules.HeuristicsContext = make_runtime_module("HeuristicsContext", install_calls)
	modules.HeuristicsVeteran = make_runtime_module("HeuristicsVeteran", install_calls)
	modules.HeuristicsZealot = make_runtime_module("HeuristicsZealot", install_calls)
	modules.HeuristicsPsyker = make_runtime_module("HeuristicsPsyker", install_calls)
	modules.HeuristicsOgryn = make_runtime_module("HeuristicsOgryn", install_calls)
	modules.HeuristicsArbites = make_runtime_module("HeuristicsArbites", install_calls)
	modules.HeuristicsHiveScum = make_runtime_module("HeuristicsHiveScum", install_calls)
	modules.HeuristicsGrenade = make_runtime_module("HeuristicsGrenade", install_calls)
	modules.ItemFallback = make_runtime_module("ItemFallback", install_calls, {
		should_lock_weapon_switch = function()
			return false
		end,
		can_use_item_fallback = function()
			return false
		end,
		schedule_retry = function() end,
		reset_item_sequence_state = function() end,
	})
	modules.Debug = make_runtime_module("Debug", install_calls, {
		context_snapshot = function(context)
			return context
		end,
		fallback_state_snapshot = function(state)
			return state
		end,
		bot_slot_for_unit = function()
			return 1
		end,
		register_commands = function() end,
		collect_alive_bots = function()
			return {}
		end,
	})
	modules.EventLog = make_runtime_module("EventLog", install_calls, {
		is_enabled = function()
			return false
		end,
		set_enabled = function() end,
		start_session = function() end,
		end_session = function() end,
		try_flush = function() end,
		next_attempt_id = function()
			return 1
		end,
		emit = function() end,
	})
	modules.Perf = make_runtime_module("Perf", install_calls, {
		begin = function()
			return 0
		end,
		finish = function() end,
		sync_setting = function() end,
		enter_run = function() end,
		mark_bot_frame = function() end,
		report_and_reset = function()
			return nil
		end,
		format_report_lines = function()
			return {}
		end,
		is_enabled = function()
			return false
		end,
	})
	modules.Sprint = make_runtime_module("Sprint", install_calls, {
		DAEMONHOST_COMBAT_RANGE_SQ = 9,
		is_near_daemonhost = function()
			return false
		end,
		install_bot_unit_input_hooks = function(target)
			record_install("Sprint", "install_bot_unit_input_hooks", target)
		end,
	})
	modules.MeleeMetaData = make_runtime_module("MeleeMetaData", install_calls, {
		inject = function() end,
		sync_all = function() end,
	})
	modules.MeleeAttackChoice = make_runtime_module("MeleeAttackChoice", install_calls, {
		install_melee_hooks = function(target)
			record_install("MeleeAttackChoice", "install_melee_hooks", target)
		end,
	})
	modules.RangedMetaData = make_runtime_module("RangedMetaData", install_calls, {
		inject = function() end,
		sync_all = function() end,
	})
	modules.TargetSelection = make_runtime_module("TargetSelection", install_calls)
	modules.Poxburster = make_runtime_module("Poxburster", install_calls, {
		install_bot_perception_hooks = function(target)
			record_install("Poxburster", "install_bot_perception_hooks", target)
		end,
		install_melee_hooks = function(target)
			record_install("Poxburster", "install_melee_hooks", target)
		end,
	})
	modules.SmartTargeting = make_runtime_module("SmartTargeting", install_calls)
	modules.AnimationGuard = make_runtime_module("AnimationGuard", install_calls)
	modules.AirlockGuard = make_runtime_module("AirlockGuard", install_calls)
	modules.VfxSuppression = make_runtime_module("VfxSuppression", install_calls, {
		install_ability_ext_hooks = function(target)
			record_install("VfxSuppression", "install_ability_ext_hooks", target)
		end,
	})
	modules.WeaponAction = make_runtime_module("WeaponAction", install_calls)
	modules.SustainedFire = make_runtime_module("SustainedFire", install_calls, {
		install_bot_unit_input_hooks = function(target)
			record_install("SustainedFire", "install_bot_unit_input_hooks", target)
		end,
		observe_queued_weapon_action = function() end,
	})
	modules.ConditionPatch = make_runtime_module("ConditionPatch", install_calls)
	modules.AbilityQueue = make_runtime_module("AbilityQueue", install_calls, {
		try_queue = function() end,
	})
	modules.GrenadeFallback = make_runtime_module("GrenadeFallback", install_calls, {
		prime_weapon_templates = function(target)
			record_install("GrenadeFallback", "prime_weapon_templates", target)
		end,
		should_lock_weapon_switch = function()
			return false
		end,
		should_block_wield_input = function()
			return false
		end,
		should_block_weapon_action_input = function()
			return false
		end,
		record_charge_event = function() end,
		try_queue = function() end,
	})
	modules.PingSystem = make_runtime_module("PingSystem", install_calls, {
		update = function() end,
	})
	modules.CompanionTag = make_runtime_module("CompanionTag", install_calls, {
		update = function() end,
		is_recent_command_target = function()
			return false
		end,
	})
	modules.HealingDeferral = make_runtime_module("HealingDeferral", install_calls, {
		install_bot_group_hooks = function(target)
			record_install("HealingDeferral", "install_bot_group_hooks", target)
		end,
		install_behavior_ext_hooks = function(target)
			record_install("HealingDeferral", "install_behavior_ext_hooks", target)
		end,
	})
	modules.AmmoPolicy = make_runtime_module("AmmoPolicy", install_calls, {
		install_behavior_ext_hooks = function(target)
			record_install("AmmoPolicy", "install_behavior_ext_hooks", target)
		end,
	})
	modules.MulePickup = make_runtime_module("MulePickup", install_calls, {
		install_bot_group_hooks = function(target)
			record_install("MulePickup", "install_bot_group_hooks", target)
		end,
		install_behavior_ext_hooks = function(target)
			record_install("MulePickup", "install_behavior_ext_hooks", target)
		end,
		patch_pickups = function() end,
		sync_live_bot_groups = function() end,
	})
	modules.BotProfiles = make_runtime_module("BotProfiles", install_calls, {
		reset = function() end,
		register_hooks = function()
			install_calls.register_calls[#install_calls.register_calls + 1] = {
				module = "BotProfiles",
				args = {},
			}
		end,
	})
	modules.HumanLikeness = make_runtime_module("HumanLikeness", install_calls, {
		patch_bot_settings = function(target)
			record_install("HumanLikeness", "patch_bot_settings", target)
		end,
	})
	modules.TargetTypeHysteresis = make_runtime_module("TargetTypeHysteresis", install_calls, {
		install_bot_perception_hooks = function(target)
			record_install("TargetTypeHysteresis", "install_bot_perception_hooks", target)
		end,
	})
	modules.EngagementLeash = make_runtime_module("EngagementLeash", install_calls, {
		install_melee_hooks = function(target)
			record_install("EngagementLeash", "install_melee_hooks", target)
		end,
		is_movement_ability = function()
			return false
		end,
		record_charge = function() end,
	})
	modules.ReviveAbility = make_runtime_module("ReviveAbility", install_calls, {
		install_behavior_ext_hooks = function(target)
			record_install("ReviveAbility", "install_behavior_ext_hooks", target)
		end,
	})

	for module_name, override in pairs(module_overrides) do
		if override.__strict then
			modules[module_name] = override
		else
			local module = assert(modules[module_name], "unknown fake module override: " .. tostring(module_name))
			for key, value in pairs(override) do
				module[key] = value
			end
		end
	end

	local module_path_map = {
		["BetterBots/scripts/mods/BetterBots/log_levels"] = modules.LogLevels,
		["BetterBots/scripts/mods/BetterBots/shared_rules"] = modules.SharedRules,
		["BetterBots/scripts/mods/BetterBots/combat_ability_identity"] = modules.CombatAbilityIdentity,
		["BetterBots/scripts/mods/BetterBots/bot_targeting"] = modules.BotTargeting,
		["BetterBots/scripts/mods/BetterBots/team_cooldown"] = modules.TeamCooldown,
		["BetterBots/scripts/mods/BetterBots/meta_data"] = modules.MetaData,
		["BetterBots/scripts/mods/BetterBots/settings"] = modules.Settings,
		["BetterBots/scripts/mods/BetterBots/heuristics_context"] = modules.HeuristicsContext,
		["BetterBots/scripts/mods/BetterBots/heuristics_veteran"] = modules.HeuristicsVeteran,
		["BetterBots/scripts/mods/BetterBots/heuristics_zealot"] = modules.HeuristicsZealot,
		["BetterBots/scripts/mods/BetterBots/heuristics_psyker"] = modules.HeuristicsPsyker,
		["BetterBots/scripts/mods/BetterBots/heuristics_ogryn"] = modules.HeuristicsOgryn,
		["BetterBots/scripts/mods/BetterBots/heuristics_arbites"] = modules.HeuristicsArbites,
		["BetterBots/scripts/mods/BetterBots/heuristics_hive_scum"] = modules.HeuristicsHiveScum,
		["BetterBots/scripts/mods/BetterBots/heuristics_grenade"] = modules.HeuristicsGrenade,
		["BetterBots/scripts/mods/BetterBots/heuristics"] = modules.Heuristics,
		["BetterBots/scripts/mods/BetterBots/item_fallback"] = modules.ItemFallback,
		["BetterBots/scripts/mods/BetterBots/debug"] = modules.Debug,
		["BetterBots/scripts/mods/BetterBots/event_log"] = modules.EventLog,
		["BetterBots/scripts/mods/BetterBots/perf"] = modules.Perf,
		["BetterBots/scripts/mods/BetterBots/sprint"] = modules.Sprint,
		["BetterBots/scripts/mods/BetterBots/melee_meta_data"] = modules.MeleeMetaData,
		["BetterBots/scripts/mods/BetterBots/melee_attack_choice"] = modules.MeleeAttackChoice,
		["BetterBots/scripts/mods/BetterBots/ranged_meta_data"] = modules.RangedMetaData,
		["BetterBots/scripts/mods/BetterBots/target_selection"] = modules.TargetSelection,
		["BetterBots/scripts/mods/BetterBots/poxburster"] = modules.Poxburster,
		["BetterBots/scripts/mods/BetterBots/smart_targeting"] = modules.SmartTargeting,
		["BetterBots/scripts/mods/BetterBots/animation_guard"] = modules.AnimationGuard,
		["BetterBots/scripts/mods/BetterBots/airlock_guard"] = modules.AirlockGuard,
		["BetterBots/scripts/mods/BetterBots/vfx_suppression"] = modules.VfxSuppression,
		["BetterBots/scripts/mods/BetterBots/weapon_action"] = modules.WeaponAction,
		["BetterBots/scripts/mods/BetterBots/sustained_fire"] = modules.SustainedFire,
		["BetterBots/scripts/mods/BetterBots/condition_patch"] = modules.ConditionPatch,
		["BetterBots/scripts/mods/BetterBots/ability_queue"] = modules.AbilityQueue,
		["BetterBots/scripts/mods/BetterBots/grenade_fallback"] = modules.GrenadeFallback,
		["BetterBots/scripts/mods/BetterBots/ping_system"] = modules.PingSystem,
		["BetterBots/scripts/mods/BetterBots/companion_tag"] = modules.CompanionTag,
		["BetterBots/scripts/mods/BetterBots/healing_deferral"] = modules.HealingDeferral,
		["BetterBots/scripts/mods/BetterBots/ammo_policy"] = modules.AmmoPolicy,
		["BetterBots/scripts/mods/BetterBots/mule_pickup"] = modules.MulePickup,
		["BetterBots/scripts/mods/BetterBots/bot_profiles"] = modules.BotProfiles,
		["BetterBots/scripts/mods/BetterBots/human_likeness"] = modules.HumanLikeness,
		["BetterBots/scripts/mods/BetterBots/target_type_hysteresis"] = modules.TargetTypeHysteresis,
		["BetterBots/scripts/mods/BetterBots/engagement_leash"] = modules.EngagementLeash,
		["BetterBots/scripts/mods/BetterBots/revive_ability"] = modules.ReviveAbility,
	}

	local fake_mod = {
		get = function(_, setting_id)
			return settings[setting_id]
		end,
		set = function(_, setting_id, value)
			settings[setting_id] = value
		end,
		io_dofile = function(_, path)
			return assert(module_path_map[path], "missing fake io_dofile module: " .. path)
		end,
		hook_require = function(_, path, callback)
			hook_require_callbacks[path] = callback
		end,
		hook = function(_, target, method_name, handler)
			local original = assert(target[method_name], "missing hook target method: " .. tostring(method_name))
			assert.equals("function", type(original), "hook target must be callable: " .. tostring(method_name))
			hook_registrations[#hook_registrations + 1] = { target = target, method = method_name, hook_type = "hook" }
			target[method_name] = function(...)
				return handler(original, ...)
			end
		end,
		hook_safe = function(_, target, method_name, handler)
			local original = assert(target[method_name], "missing hook target method: " .. tostring(method_name))
			assert.equals("function", type(original), "hook target must be callable: " .. tostring(method_name))
			hook_registrations[#hook_registrations + 1] =
				{ target = target, method = method_name, hook_type = "hook_safe" }
			target[method_name] = function(...)
				local results = { original(...) }
				handler(...)
				return unpack(results)
			end
		end,
		command = function(_, name, _description, callback)
			commands[name] = callback
		end,
		echo = function(_, message)
			echoes[#echoes + 1] = message
		end,
		warning = function(_, message)
			warnings[#warnings + 1] = message
		end,
	}

	local harness = {
		mod = fake_mod,
		modules = modules,
		echoes = echoes,
		warnings = warnings,
		commands = commands,
		hook_require_callbacks = hook_require_callbacks,
		hook_registrations = hook_registrations,
		init_calls = install_calls.init_calls,
		wire_calls = install_calls.wire_calls,
		register_calls = install_calls.register_calls,
		install_calls = install_calls.install_calls,
		load = function()
			rawset(_G, "get_mod", function(mod_name)
				assert.equals("BetterBots", mod_name)
				return fake_mod
			end)
			rawset(_G, "ScriptUnit", {
				has_extension = function()
					return nil
				end,
				extension = function()
					return nil
				end,
			})
			rawset(_G, "BLACKBOARDS", {})
			rawset(_G, "require", function(path)
				if path == "scripts/utilities/fixed_frame" then
					return {
						get_latest_fixed_time = function()
							return 0
						end,
					}
				end
				if path == "scripts/settings/damage/armor_settings" then
					return {
						types = {
							super_armor = 4,
							armored = 2,
						},
					}
				end
				if path == "scripts/settings/bot/bot_settings" then
					return {}
				end
				return saved_require(path)
			end)

			local ok, loaded = pcall(dofile, "scripts/mods/BetterBots/BetterBots.lua")
			rawset(_G, "require", saved_require)
			rawset(_G, "get_mod", saved_get_mod)
			rawset(_G, "ScriptUnit", saved_script_unit)
			rawset(_G, "BLACKBOARDS", saved_blackboards)

			assert.is_true(ok, tostring(loaded))
			return fake_mod
		end,
		invoke_hook_require = function(_, path, target)
			local callback = assert(hook_require_callbacks[path], "missing hook_require callback for " .. path)
			callback(target)
		end,
	}

	return harness
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

	it("loads split heuristics modules through mod io", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_context"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_veteran"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_zealot"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_psyker"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_ogryn"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_arbites"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_hive_scum"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_grenade"%)', 1))
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

	it("boots BetterBots.lua against fake mod and asserts runtime wiring", function()
		local harness = make_bootstrap_harness()
		local mod = harness:load()

		assert.is_truthy(mod)
		assert.is_truthy(find_named_call(harness.init_calls, "Settings"))
		assert.is_truthy(find_named_call(harness.init_calls, "AbilityQueue"))
		assert.is_truthy(find_named_call(harness.wire_calls, "ItemFallback"))
		assert.is_truthy(find_named_call(harness.register_calls, "WeaponAction"))

		local item_wire = find_named_call(harness.wire_calls, "ItemFallback")
		assert.equals(harness.modules.Heuristics.build_context, item_wire.refs.build_context)
		assert.equals(harness.modules.Settings.is_item_ability_enabled, item_wire.refs.is_item_ability_enabled)

		local debug_wire = find_named_call(harness.wire_calls, "Debug")
		assert.equals(harness.modules.Heuristics.build_context, debug_wire.refs.build_context)
		assert.equals(harness.modules.Heuristics.resolve_decision, debug_wire.refs.resolve_decision)
		assert.equals(harness.modules.ItemFallback.can_use_item_fallback, debug_wire.refs.can_use_item_fallback)

		local condition_wire = find_named_call(harness.wire_calls, "ConditionPatch")
		assert.equals(harness.modules.Heuristics, condition_wire.refs.Heuristics)
		assert.equals(harness.modules.MetaData, condition_wire.refs.MetaData)
		assert.equals(harness.modules.Debug, condition_wire.refs.Debug)
		assert.equals(harness.modules.TeamCooldown, condition_wire.refs.TeamCooldown)
		assert.equals(harness.modules.CombatAbilityIdentity, condition_wire.refs.combat_ability_identity)
		assert.equals(harness.modules.Settings.bot_ranged_ammo_threshold, condition_wire.refs.bot_ranged_ammo_threshold)

		local ability_wire = find_named_call(harness.wire_calls, "AbilityQueue")
		assert.equals(harness.modules.ItemFallback, ability_wire.refs.ItemFallback)
		assert.equals(harness.modules.EngagementLeash, ability_wire.refs.EngagementLeash)
		assert.equals(harness.modules.CombatAbilityIdentity, ability_wire.refs.CombatAbilityIdentity)
		assert.equals(harness.modules.HumanLikeness, ability_wire.refs.HumanLikeness)

		local revive_wire = find_named_call(harness.wire_calls, "ReviveAbility")
		assert.equals(harness.modules.MetaData, revive_wire.refs.MetaData)
		assert.equals(harness.modules.EventLog, revive_wire.refs.EventLog)
		assert.equals(harness.modules.Debug, revive_wire.refs.Debug)
		assert.equals(harness.modules.Settings.is_combat_template_enabled, revive_wire.refs.is_combat_template_enabled)

		local grenade_wire = find_named_call(harness.wire_calls, "GrenadeFallback")
		assert.equals(harness.modules.Heuristics.build_context, grenade_wire.refs.build_context)
		assert.equals(harness.modules.Heuristics.normalize_grenade_context, grenade_wire.refs.normalize_grenade_context)
		assert.equals(
			harness.modules.Heuristics.evaluate_grenade_heuristic,
			grenade_wire.refs.evaluate_grenade_heuristic
		)
		assert.equals(harness.modules.Settings.is_grenade_enabled, grenade_wire.refs.is_grenade_enabled)
		assert.equals(harness.modules.BotTargeting, grenade_wire.refs.bot_targeting)

		local weapon_register = find_named_call(harness.register_calls, "WeaponAction")
		assert.is_function(weapon_register.args[1].should_lock_weapon_switch)
		assert.is_function(weapon_register.args[1].should_block_wield_input)
		assert.is_function(weapon_register.args[1].should_block_weapon_action_input)

		harness:invoke_hook_require("scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action", {
			attack = function() end,
		})
		harness:invoke_hook_require("scripts/extension_systems/perception/bot_perception_extension", {
			_update_target_enemy = function() end,
		})
		harness:invoke_hook_require("scripts/extension_systems/input/bot_unit_input", {})
		harness:invoke_hook_require("scripts/extension_systems/group/bot_group", {})
		harness:invoke_hook_require("scripts/settings/bot/bot_settings", {})

		assert.is_truthy(find_install_call(harness.install_calls, "MeleeAttackChoice", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "Poxburster", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "EngagementLeash", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "SustainedFire", "install_bot_unit_input_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "Sprint", "install_bot_unit_input_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HealingDeferral", "install_bot_group_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "MulePickup", "install_bot_group_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HumanLikeness", "patch_bot_settings"))
		assert.is_truthy(find_echo(harness.echoes, "BetterBots loaded"))
	end)

	it("registers every hook_require path declared in BetterBots.lua", function()
		local harness = make_bootstrap_harness()
		harness:load()

		assert.same({
			"scripts/extension_systems/ability/actions/action_character_state_change",
			"scripts/extension_systems/ability/player_unit_ability_extension",
			"scripts/extension_systems/behavior/bot_behavior_extension",
			"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
			"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action",
			"scripts/extension_systems/group/bot_group",
			"scripts/extension_systems/input/bot_unit_input",
			"scripts/extension_systems/perception/bot_perception_extension",
			"scripts/settings/ability/ability_templates/ability_templates",
			"scripts/settings/bot/bot_settings",
			"scripts/settings/equipment/weapon_templates/weapon_templates",
		}, sorted_keys(harness.hook_require_callbacks))
	end)

	it("registers a single hook on BotBehaviorExtension._refresh_destination from BetterBots.lua", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local count = 0
		for _ in source:gmatch('"_refresh_destination"') do
			count = count + 1
		end

		assert.equals(1, count)
	end)

	it("registers a single hook on BotPerceptionExtension._update_target_enemy from BetterBots.lua", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local count = 0
		for _ in source:gmatch('"_update_target_enemy"') do
			count = count + 1
		end

		assert.equals(1, count)
	end)

	it("fails bootstrap when a required module API is missing", function()
		local harness = make_bootstrap_harness({
			WeaponAction = {
				__strict = true,
				init = function() end,
			},
		})

		local ok, err = pcall(function()
			harness:load()
		end)

		assert.is_false(ok)
		assert.matches("register_hooks", tostring(err))
	end)

	it("fails when fake hook wrappers target a missing method", function()
		local harness = make_bootstrap_harness()

		local ok, err = pcall(function()
			harness.mod:hook({}, "extensions_ready", function() end)
		end)

		assert.is_false(ok)
		assert.matches("extensions_ready", tostring(err))
	end)

	it("wires Perf into AbilityQueue initialization", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local init_block = assert(source:match("AbilityQueue%.init%(%{%s*(.-)%s*%}%)"))

		assert.is_truthy(init_block:find("perf%s*=%s*Perf", 1))
	end)

	it("restores close-range daemonhost suppression for ability activation", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")
		local condition_init_block = assert(source:match("ConditionPatch%.init%(%{%s*(.-)%s*%}%)"))

		assert.is_truthy(source:find("Sprint%.is_near_daemonhost%(unit, Sprint%.DAEMONHOST_COMBAT_RANGE_SQ%)", 1))
		assert.is_truthy(condition_init_block:find("is_near_daemonhost%s*=%s*function%(unit%)", 1))
		assert.is_truthy(
			condition_init_block:find("Sprint%.is_near_daemonhost%(unit, Sprint%.DAEMONHOST_COMBAT_RANGE_SQ%)", 1)
		)
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

		-- The raw DMF function must be stashed on the shared mod table so repeated script
		-- executions (hot reload) don't recursively wrap the previous guard.
		assert.is_truthy(source:find("mod%._raw_hook_require = mod%.hook_require", 1))
		assert.is_truthy(source:find("local _original_hook_require = mod%._raw_hook_require", 1))
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
		assert.is_truthy(main_source:find("ReviveAbility%.on_refresh_destination", 1))
		assert.is_truthy(main_source:find("MulePickup%.on_refresh_destination", 1))
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

	it("heuristics_context.lua uses breed.ranged for ranged_count (not tags.ranged)", function()
		local handle = assert(io.open("scripts/mods/BetterBots/heuristics_context.lua", "r"))
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
	it("passes split heuristics modules into Heuristics.init", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local heuristics_init = find_named_call(harness.init_calls, "Heuristics")

		assert.equals(harness.modules.HeuristicsContext, heuristics_init.deps.context_module)
		assert.equals(harness.modules.HeuristicsVeteran, heuristics_init.deps.veteran_module)
		assert.equals(harness.modules.HeuristicsZealot, heuristics_init.deps.zealot_module)
		assert.equals(harness.modules.HeuristicsPsyker, heuristics_init.deps.psyker_module)
		assert.equals(harness.modules.HeuristicsOgryn, heuristics_init.deps.ogryn_module)
		assert.equals(harness.modules.HeuristicsArbites, heuristics_init.deps.arbites_module)
		assert.equals(harness.modules.HeuristicsHiveScum, heuristics_init.deps.hive_scum_module)
		assert.equals(harness.modules.HeuristicsGrenade, heuristics_init.deps.grenade_module)
	end)
end)
