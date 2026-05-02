local test_helper = require("tests.test_helper")
local Localization = dofile("scripts/mods/BetterBots/BetterBots_localization.lua")
local unpack_results = unpack
if table and table.unpack then -- luacheck: ignore 143
	unpack_results = table.unpack -- luacheck: ignore 143
end

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

local function read_bootstrap_surface()
	return read_file("scripts/mods/BetterBots/BetterBots.lua")
		.. "\n"
		.. read_file("scripts/mods/BetterBots/bootstrap.lua")
end

local function assert_module_loaded(source, filename)
	local direct = 'mod:io_dofile("BetterBots/scripts/mods/BetterBots/' .. filename .. '")'
	local via_bootstrap = 'load_module(mod, "' .. filename .. '")'

	assert.is_truthy(source:find(direct, 1, true) or source:find(via_bootstrap, 1, true))
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

local function count_echoes(echoes, pattern)
	local count = 0

	for i = 1, #echoes do
		if string.find(echoes[i], pattern, 1, true) then
			count = count + 1
		end
	end

	return count
end

local function sorted_keys(map)
	local keys = {}

	for key in pairs(map) do
		keys[#keys + 1] = key
	end

	table.sort(keys)

	return keys
end

local function count_hooks(hook_registrations, target, method_name, hook_type)
	local count = 0

	for _, reg in ipairs(hook_registrations) do
		if reg.target == target and reg.method == method_name and reg.hook_type == hook_type then
			count = count + 1
		end
	end

	return count
end

local function trim(str)
	return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function line_for_position(source, position)
	local line = 1
	for _ in source:sub(1, position):gmatch("\n") do
		line = line + 1
	end

	return line
end

local function read_call_argument(source, position)
	local depth = 0
	local quote
	local escaped = false

	for i = position, #source do
		local char = source:sub(i, i)
		if quote then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == quote then
				quote = nil
			end
		else
			if char == '"' or char == "'" then
				quote = char
			elseif char == "(" or char == "{" or char == "[" then
				depth = depth + 1
			elseif char == ")" or char == "}" or char == "]" then
				if depth > 0 then
					depth = depth - 1
				end
			elseif char == "," and depth == 0 then
				return trim(source:sub(position, i - 1)), i + 1
			end
		end
	end

	return nil, position
end

local function collect_method_hooks(path, source)
	local hooks = {}
	local patterns = {
		{ hook_type = "hook_safe", pattern = "([_%w]*mod):hook_safe%s*%(" },
		{ hook_type = "hook", pattern = "([_%w]*mod):hook%s*%(" },
	}

	for _, spec in ipairs(patterns) do
		local position = 1
		while true do
			local start_pos, open_pos = source:find(spec.pattern, position)
			if not start_pos then
				break
			end

			local target, method_pos = read_call_argument(source, open_pos + 1)
			local method_arg = target and read_call_argument(source, method_pos)
			local method_name = method_arg and method_arg:match([[^%s*["']([^"']+)["']%s*$]])
			if method_name then
				hooks[#hooks + 1] = {
					path = path,
					line = line_for_position(source, start_pos),
					target = target,
					method_name = method_name,
					hook_type = spec.hook_type,
				}
			end

			position = open_pos + 1
		end
	end

	return hooks
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
	local saved_managers = rawget(_G, "Managers")
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
	if module_overrides.__settings then
		for key, value in pairs(module_overrides.__settings) do
			settings[key] = value
		end
	end
	local fixed_frame_module = module_overrides.__fixed_frame
		or {
			get_latest_fixed_time = function()
				return 0
			end,
		}
	local managers = module_overrides.__managers

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
	if module_overrides.LogLevels then
		for key, value in pairs(module_overrides.LogLevels) do
			modules.LogLevels[key] = value
		end
	end

	modules.Bootstrap = dofile("scripts/mods/BetterBots/bootstrap.lua")
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
	modules.ItemProfiles = make_runtime_module("ItemProfiles", install_calls, {})
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
	modules.ChargeTracker = make_runtime_module("ChargeTracker", install_calls, {
		handle = function() end,
	})
	modules.GestaltInjector = make_runtime_module("GestaltInjector", install_calls, {
		inject = function(gestalts_or_nil)
			return gestalts_or_nil, false
		end,
	})
	modules.UpdateDispatcher = make_runtime_module("UpdateDispatcher", install_calls, {
		dispatch = function() end,
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
		install_combat_utility_diagnostics = function(...)
			record_install("Debug", "install_combat_utility_diagnostics", ...)
		end,
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
	modules.ScenarioHarness = make_runtime_module("ScenarioHarness", install_calls, {
		register_commands = function()
			install_calls.register_calls[#install_calls.register_calls + 1] = {
				module = "ScenarioHarness",
				args = {},
			}
		end,
	})
	modules.HazardAvoidance = make_runtime_module("HazardAvoidance", install_calls, {
		install_hazard_prop_hooks = function(target)
			record_install("HazardAvoidance", "install_hazard_prop_hooks", target)
		end,
		install_bot_group_hooks = function(target)
			record_install("HazardAvoidance", "install_bot_group_hooks", target)
		end,
		on_bot_input_movement_updated = function() end,
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
	modules.WeaponActionLogging = make_runtime_module("WeaponActionLogging", install_calls, {})
	modules.WeaponActionShoot = make_runtime_module("WeaponActionShoot", install_calls, {})
	modules.WeaponActionVoidblast = make_runtime_module("WeaponActionVoidblast", install_calls, {})
	modules.WeaponAction = make_runtime_module("WeaponAction", install_calls)
	modules.RangedSpecialAction = make_runtime_module("RangedSpecialAction", install_calls)
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
	modules.GrenadeProfiles = make_runtime_module("GrenadeProfiles", install_calls, {})
	modules.GrenadeAim = make_runtime_module("GrenadeAim", install_calls, {
		prime_weapon_templates = function(target)
			record_install("GrenadeAim", "prime_weapon_templates", target)
		end,
	})
	modules.GrenadeRuntime = make_runtime_module("GrenadeRuntime", install_calls, {})
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
	modules.ComWheelResponse = make_runtime_module("ComWheelResponse", install_calls, {
		override_behavior_profile = function()
			return nil
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
		should_block_pickup_order = function()
			return false
		end,
	})
	modules.PocketablePickup = make_runtime_module("PocketablePickup", install_calls, {
		patch_pickups = function() end,
	})
	modules.SmartTagOrders = make_runtime_module("SmartTagOrders", install_calls)
	modules.BotProfileTemplates = make_runtime_module("BotProfileTemplates", install_calls, {
		DEFAULT_PROFILE_TEMPLATES = {},
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
	modules.WeakspotAim = make_runtime_module("WeakspotAim", install_calls, {})
	modules.ChargeNavValidation = make_runtime_module("ChargeNavValidation", install_calls, {
		should_validate = function()
			return false
		end,
		validate = function()
			return true
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
		if module_name == "__fixed_frame" or module_name == "__managers" or module_name == "__settings" then
			-- test-only harness knobs, not runtime modules
			local _ = override
		elseif override.__strict then
			modules[module_name] = override
		else
			local module = assert(modules[module_name], "unknown fake module override: " .. tostring(module_name))
			for key, value in pairs(override) do
				module[key] = value
			end
		end
	end

	local module_path_map = {
		["BetterBots/scripts/mods/BetterBots/bootstrap"] = modules.Bootstrap,
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
		["BetterBots/scripts/mods/BetterBots/item_profiles"] = modules.ItemProfiles,
		["BetterBots/scripts/mods/BetterBots/item_fallback"] = modules.ItemFallback,
		["BetterBots/scripts/mods/BetterBots/charge_tracker"] = modules.ChargeTracker,
		["BetterBots/scripts/mods/BetterBots/gestalt_injector"] = modules.GestaltInjector,
		["BetterBots/scripts/mods/BetterBots/update_dispatcher"] = modules.UpdateDispatcher,
		["BetterBots/scripts/mods/BetterBots/debug"] = modules.Debug,
		["BetterBots/scripts/mods/BetterBots/event_log"] = modules.EventLog,
		["BetterBots/scripts/mods/BetterBots/scenario_harness"] = modules.ScenarioHarness,
		["BetterBots/scripts/mods/BetterBots/hazard_avoidance"] = modules.HazardAvoidance,
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
		["BetterBots/scripts/mods/BetterBots/weapon_action_logging"] = modules.WeaponActionLogging,
		["BetterBots/scripts/mods/BetterBots/weapon_action_shoot"] = modules.WeaponActionShoot,
		["BetterBots/scripts/mods/BetterBots/weapon_action_voidblast"] = modules.WeaponActionVoidblast,
		["BetterBots/scripts/mods/BetterBots/weapon_action"] = modules.WeaponAction,
		["BetterBots/scripts/mods/BetterBots/ranged_special_action"] = modules.RangedSpecialAction,
		["BetterBots/scripts/mods/BetterBots/sustained_fire"] = modules.SustainedFire,
		["BetterBots/scripts/mods/BetterBots/condition_patch"] = modules.ConditionPatch,
		["BetterBots/scripts/mods/BetterBots/ability_queue"] = modules.AbilityQueue,
		["BetterBots/scripts/mods/BetterBots/grenade_fallback"] = modules.GrenadeFallback,
		["BetterBots/scripts/mods/BetterBots/grenade_profiles"] = modules.GrenadeProfiles,
		["BetterBots/scripts/mods/BetterBots/grenade_aim"] = modules.GrenadeAim,
		["BetterBots/scripts/mods/BetterBots/grenade_runtime"] = modules.GrenadeRuntime,
		["BetterBots/scripts/mods/BetterBots/ping_system"] = modules.PingSystem,
		["BetterBots/scripts/mods/BetterBots/companion_tag"] = modules.CompanionTag,
		["BetterBots/scripts/mods/BetterBots/healing_deferral"] = modules.HealingDeferral,
		["BetterBots/scripts/mods/BetterBots/ammo_policy"] = modules.AmmoPolicy,
		["BetterBots/scripts/mods/BetterBots/com_wheel_response"] = modules.ComWheelResponse,
		["BetterBots/scripts/mods/BetterBots/mule_pickup"] = modules.MulePickup,
		["BetterBots/scripts/mods/BetterBots/pocketable_pickup"] = modules.PocketablePickup,
		["BetterBots/scripts/mods/BetterBots/smart_tag_orders"] = modules.SmartTagOrders,
		["BetterBots/scripts/mods/BetterBots/bot_profile_templates"] = modules.BotProfileTemplates,
		["BetterBots/scripts/mods/BetterBots/bot_profiles"] = modules.BotProfiles,
		["BetterBots/scripts/mods/BetterBots/human_likeness"] = modules.HumanLikeness,
		["BetterBots/scripts/mods/BetterBots/target_type_hysteresis"] = modules.TargetTypeHysteresis,
		["BetterBots/scripts/mods/BetterBots/weakspot_aim"] = modules.WeakspotAim,
		["BetterBots/scripts/mods/BetterBots/charge_nav_validation"] = modules.ChargeNavValidation,
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
				return unpack_results(results)
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
			rawset(_G, "Managers", managers)
			rawset(_G, "require", function(path)
				if path == "scripts/utilities/fixed_frame" then
					return fixed_frame_module
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
			rawset(_G, "Managers", saved_managers)

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

	it("keeps fixed_time bootstrap-safe before extension managers exist", function()
		local fixed_time_seen
		local harness = make_bootstrap_harness({
			__fixed_frame = {
				get_latest_fixed_time = function()
					error("fixed_frame unavailable during bootstrap")
				end,
			},
			PocketablePickup = {
				init = function(deps)
					fixed_time_seen = deps.fixed_time()
				end,
			},
		})

		harness:load()

		assert.equals(0, fixed_time_seen)
	end)

	it("keeps fixed_time bootstrap-safe when the extension manager lacks latest_fixed_t", function()
		local fixed_frame_calls = 0
		local fixed_time_seen
		local harness = make_bootstrap_harness({
			__managers = {
				state = {
					extension = {},
				},
			},
			__fixed_frame = {
				get_latest_fixed_time = function()
					fixed_frame_calls = fixed_frame_calls + 1
					error("FixedFrame should not be touched without latest_fixed_t")
				end,
			},
			PocketablePickup = {
				init = function(deps)
					fixed_time_seen = deps.fixed_time()
				end,
			},
		})

		harness:load()

		assert.equals(0, fixed_time_seen)
		assert.equals(0, fixed_frame_calls)
	end)

	it("calls FixedFrame when the extension manager exposes latest_fixed_t", function()
		local fixed_frame_calls = 0
		local fixed_time_seen
		local harness = make_bootstrap_harness({
			__managers = {
				state = {
					extension = {
						latest_fixed_t = 123.45,
					},
				},
			},
			__fixed_frame = {
				get_latest_fixed_time = function()
					fixed_frame_calls = fixed_frame_calls + 1
					return 123.45
				end,
			},
			PocketablePickup = {
				init = function(deps)
					fixed_time_seen = deps.fixed_time()
				end,
			},
		})

		harness:load()

		assert.equals(123.45, fixed_time_seen)
		assert.equals(1, fixed_frame_calls)
	end)

	it("emits a one-shot debug breadcrumb when fixed_time is unavailable during bootstrap", function()
		local harness = make_bootstrap_harness({
			__settings = {
				enable_debug_logs = 2,
			},
			LogLevels = {
				resolve_setting = function(value)
					return value
				end,
				should_log = function(_current, _level)
					return true
				end,
				level_name = function()
					return "debug"
				end,
			},
			PocketablePickup = {
				init = function(deps)
					deps.fixed_time()
					deps.fixed_time()
				end,
			},
		})

		harness:load()

		local breadcrumb = find_echo(harness.echoes, "fixed_time unavailable during bootstrap")
		assert.is_not_nil(breadcrumb)
		assert.equals(1, count_echoes(harness.echoes, "fixed_time unavailable during bootstrap"))
	end)

	it("loads shared helper modules through mod io", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/shared_rules"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/bot_targeting"%)', 1))
	end)

	it("loads split heuristics modules through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "heuristics_context")
		assert_module_loaded(source, "heuristics_veteran")
		assert_module_loaded(source, "heuristics_zealot")
		assert_module_loaded(source, "heuristics_psyker")
		assert_module_loaded(source, "heuristics_ogryn")
		assert_module_loaded(source, "heuristics_arbites")
		assert_module_loaded(source, "heuristics_hive_scum")
		assert_module_loaded(source, "heuristics_grenade")
	end)

	it("loads smart_targeting through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "smart_targeting")
	end)

	it("loads animation_guard through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "animation_guard")
	end)

	it("loads airlock_guard through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "airlock_guard")
	end)

	it("loads melee_attack_choice through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "melee_attack_choice")
	end)

	it("loads revive_ability through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "revive_ability")
	end)

	it("loads sustained_fire through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "sustained_fire")
	end)

	it("loads mule_pickup through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "mule_pickup")
	end)

	it("loads pocketable_pickup through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "pocketable_pickup")
	end)

	it("loads com_wheel_response through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "com_wheel_response")
	end)

	it("loads companion_tag through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "companion_tag")
	end)

	it("loads charge_nav_validation through mod io", function()
		local source = read_bootstrap_surface()

		assert_module_loaded(source, "charge_nav_validation")
	end)

	it("initializes and registers extracted runtime modules", function()
		local source = read_bootstrap_surface()

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
		assert.is_truthy(source:find("HazardAvoidance%.install_bot_group_hooks%(", 1))
		assert.is_truthy(
			source:find('mod:hook_require%("scripts/extension_systems/hazard_prop/hazard_prop_extension"', 1)
		)
		assert.is_truthy(source:find("HealingDeferral%.install_bot_group_hooks%(", 1))
		assert.is_truthy(source:find("MulePickup%.install_bot_group_hooks%(", 1))
		assert.is_truthy(source:find("MulePickup%.init%(", 1))
		assert.is_truthy(source:find("MulePickup%.register_hooks%(", 1))
		assert.is_truthy(source:find("ComWheelResponse%.init%(", 1))
		assert.is_truthy(source:find("ComWheelResponse%.register_hooks%(", 1))
		assert.is_truthy(source:find("SmartTagOrders%.init%(", 1))
		assert.is_truthy(source:find("SmartTagOrders%.register_hooks%(", 1))
		assert.is_truthy(source:find("ChargeTracker%.init%(", 1))
		assert.is_truthy(source:find("ChargeTracker%.handle%(", 1))
		assert.is_truthy(source:find("GestaltInjector%.init%(", 1))
		assert.is_truthy(source:find("GestaltInjector%.inject%(", 1))
		assert.is_truthy(source:find("UpdateDispatcher%.init%(", 1))
		assert.is_truthy(source:find("UpdateDispatcher%.dispatch%(", 1))
		assert.is_truthy(source:find("CompanionTag%.init%(", 1))
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
		assert.equals(harness.modules.ChargeNavValidation, ability_wire.refs.ChargeNavValidation)
		assert.equals(harness.modules.CombatAbilityIdentity, ability_wire.refs.CombatAbilityIdentity)
		assert.equals(harness.modules.HumanLikeness, ability_wire.refs.HumanLikeness)

		local smart_tag_init = find_named_call(harness.init_calls, "SmartTagOrders")
		assert.is_truthy(smart_tag_init)
		assert.equals(harness.modules.Debug.bot_slot_for_unit, smart_tag_init.deps.bot_slot_for_unit)

		local com_wheel_init = find_named_call(harness.init_calls, "ComWheelResponse")
		assert.is_truthy(com_wheel_init)
		assert.is_function(com_wheel_init.deps.is_enabled)

		local settings_wire = find_named_call(harness.wire_calls, "Settings")
		assert.is_truthy(settings_wire)
		assert.equals(
			harness.modules.ComWheelResponse.override_behavior_profile,
			settings_wire.refs.behavior_profile_override
		)

		local smart_tag_wire = find_named_call(harness.wire_calls, "SmartTagOrders")
		assert.is_truthy(smart_tag_wire)
		assert.is_function(smart_tag_wire.refs.should_block_pickup_order)

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

		local charge_init = find_named_call(harness.init_calls, "ChargeTracker")
		assert.equals(harness.modules.GrenadeFallback, charge_init.deps.grenade_fallback)
		assert.equals(harness.modules.Settings, charge_init.deps.settings)
		assert.equals(harness.modules.TeamCooldown, charge_init.deps.team_cooldown)
		assert.equals(harness.modules.CombatAbilityIdentity, charge_init.deps.combat_ability_identity)
		assert.equals(harness.modules.EventLog, charge_init.deps.event_log)

		local bot_profiles_init = find_named_call(harness.init_calls, "BotProfiles")
		assert.equals(harness.modules.BotProfileTemplates, bot_profiles_init.deps.profile_templates)

		local item_fallback_init = find_named_call(harness.init_calls, "ItemFallback")
		assert.equals(harness.modules.ItemProfiles, item_fallback_init.deps.item_profiles)

		local weapon_action_init = find_named_call(harness.init_calls, "WeaponAction")
		assert.equals(harness.modules.WeaponActionLogging, weapon_action_init.deps.weapon_action_logging)
		assert.equals(harness.modules.WeaponActionShoot, weapon_action_init.deps.weapon_action_shoot)
		assert.equals(harness.modules.WeaponActionVoidblast, weapon_action_init.deps.weapon_action_voidblast)

		local grenade_fallback_init = find_named_call(harness.init_calls, "GrenadeFallback")
		assert.equals(harness.modules.GrenadeProfiles, grenade_fallback_init.deps.grenade_profiles)
		assert.equals(harness.modules.GrenadeAim, grenade_fallback_init.deps.grenade_aim)
		assert.equals(harness.modules.GrenadeRuntime, grenade_fallback_init.deps.grenade_runtime)

		local gestalt_init = find_named_call(harness.init_calls, "GestaltInjector")
		assert.equals("killshot", gestalt_init.deps.default_ranged_gestalt)
		assert.equals("linesman", gestalt_init.deps.default_melee_gestalt)
		assert.equals("table", type(gestalt_init.deps.injected_units))

		local dispatcher_init = find_named_call(harness.init_calls, "UpdateDispatcher")
		assert.equals(harness.modules.Perf, dispatcher_init.deps.perf)
		assert.equals(harness.modules.EventLog, dispatcher_init.deps.event_log)
		assert.equals(harness.modules.Debug, dispatcher_init.deps.debug)
		assert.equals(harness.modules.AbilityQueue, dispatcher_init.deps.ability_queue)
		assert.equals(harness.modules.GrenadeFallback, dispatcher_init.deps.grenade_fallback)
		assert.equals(harness.modules.PingSystem, dispatcher_init.deps.ping_system)
		assert.equals(harness.modules.CompanionTag, dispatcher_init.deps.companion_tag)
		assert.equals(harness.modules.Settings, dispatcher_init.deps.settings)
		assert.equals(harness.modules.Heuristics.build_context, dispatcher_init.deps.build_context)
		assert.equals("table", type(dispatcher_init.deps.session_start_state))
		assert.equals("number", type(dispatcher_init.deps.snapshot_interval_s))

		local scenario_init = find_named_call(harness.init_calls, "ScenarioHarness")
		assert.equals(harness.modules.EventLog, scenario_init.deps.event_log)
		assert.equals(harness.modules.Debug, scenario_init.deps.debug)

		local weapon_register = find_named_call(harness.register_calls, "WeaponAction")
		assert.is_function(weapon_register.args[1].should_lock_weapon_switch)
		assert.is_function(weapon_register.args[1].should_block_wield_input)
		assert.is_function(weapon_register.args[1].should_block_weapon_action_input)
		assert.is_function(weapon_register.args[1].rewrite_weapon_action_input)

		local ranged_special_init = find_named_call(harness.init_calls, "RangedSpecialAction")
		assert.equals(harness.modules.Debug.bot_slot_for_unit, ranged_special_init.deps.bot_slot_for_unit)

		local scenario_register = find_named_call(harness.register_calls, "ScenarioHarness")
		assert.is_truthy(scenario_register)

		harness:invoke_hook_require("scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action", {
			attack = function() end,
		})
		harness:invoke_hook_require("scripts/extension_systems/perception/bot_perception_extension", {
			_update_target_enemy = function() end,
		})
		harness:invoke_hook_require("scripts/extension_systems/behavior/nodes/bt_random_utility_node", {})
		harness:invoke_hook_require("scripts/extension_systems/input/bot_unit_input", {})
		harness:invoke_hook_require("scripts/extension_systems/group/bot_group", {})
		harness:invoke_hook_require("scripts/extension_systems/hazard_prop/hazard_prop_extension", {})
		harness:invoke_hook_require("scripts/settings/bot/bot_settings", {})

		assert.is_truthy(find_install_call(harness.install_calls, "MeleeAttackChoice", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "Poxburster", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "EngagementLeash", "install_melee_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "SustainedFire", "install_bot_unit_input_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "Sprint", "install_bot_unit_input_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HealingDeferral", "install_bot_group_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "MulePickup", "install_bot_group_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HazardAvoidance", "install_bot_group_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HazardAvoidance", "install_hazard_prop_hooks"))
		assert.is_truthy(find_install_call(harness.install_calls, "HumanLikeness", "patch_bot_settings"))
		assert.is_truthy(find_install_call(harness.install_calls, "Debug", "install_combat_utility_diagnostics"))
		assert.is_truthy(find_echo(harness.echoes, "BetterBots loaded"))
	end)

	it("blocks weapon actions against a non-aggroed daemonhost target", function()
		local bot = "bot_1"
		local daemonhost = "daemonhost_1"
		local non_aggroed = true
		local harness = make_bootstrap_harness({
			Settings = {
				is_feature_enabled = function(setting_id)
					return setting_id == "daemonhost_avoidance"
				end,
			},
			SharedRules = {
				DAEMONHOST_BREED_NAMES = {
					chaos_daemonhost = true,
				},
				is_non_aggroed_daemonhost = function(target_unit)
					assert.equals(daemonhost, target_unit)
					if non_aggroed then
						return true, "passive", 1
					end
					return false, "aggroed", 6
				end,
			},
		})
		harness:load()
		local weapon_register = find_named_call(harness.register_calls, "WeaponAction")
		local saved_blackboards = rawget(_G, "BLACKBOARDS")
		local saved_script_unit = rawget(_G, "ScriptUnit")

		rawset(_G, "BLACKBOARDS", {
			[bot] = {
				perception = {
					target_enemy = daemonhost,
				},
			},
		})
		rawset(_G, "ScriptUnit", {
			has_extension = function(unit, system_name)
				if unit == daemonhost and system_name == "unit_data_system" then
					return test_helper.make_minion_unit_data_extension({ name = "chaos_daemonhost" })
				end
				return nil
			end,
		})

		local blocked, reason, details = weapon_register.args[1].should_block_weapon_action_input(bot, "shoot_pressed")
		local cleanup_blocked = weapon_register.args[1].should_block_weapon_action_input(bot, "unwield_to_previous")
		non_aggroed = false
		local aggroed_blocked = weapon_register.args[1].should_block_weapon_action_input(bot, "shoot_pressed")

		rawset(_G, "ScriptUnit", saved_script_unit)
		rawset(_G, "BLACKBOARDS", saved_blackboards)

		assert.is_true(blocked)
		assert.equals("daemonhost_avoidance", reason)
		assert.matches("target=chaos_daemonhost", details)
		assert.matches("stage=1", details)
		assert.matches("aggro_state=passive", details)
		assert.is_false(cleanup_blocked)
		assert.is_false(aggroed_blocked)
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
			"scripts/extension_systems/behavior/nodes/bt_random_utility_node",
			"scripts/extension_systems/group/bot_group",
			"scripts/extension_systems/hazard_prop/hazard_prop_extension",
			"scripts/extension_systems/input/bot_unit_input",
			"scripts/extension_systems/perception/bot_perception_extension",
			"scripts/settings/ability/ability_templates/ability_templates",
			"scripts/settings/bot/bot_settings",
			"scripts/settings/equipment/weapon_templates/weapon_templates",
		}, sorted_keys(harness.hook_require_callbacks))
	end)

	it("dispatches use_ability_charge through ChargeTracker.handle", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local handled = {}
		harness.modules.ChargeTracker.handle = function(self, ability_type, optional_num_charges)
			handled[#handled + 1] = {
				self = self,
				ability_type = ability_type,
				charges = optional_num_charges,
			}
		end

		local ability_ext = {
			use_ability_charge = function(_self, ability_type, optional_num_charges)
				return "orig", ability_type, optional_num_charges
			end,
		}

		harness:invoke_hook_require("scripts/extension_systems/ability/player_unit_ability_extension", ability_ext)
		local tag, ability_type, charges = ability_ext:use_ability_charge("combat_ability", 2)

		assert.equals("orig", tag)
		assert.equals("combat_ability", ability_type)
		assert.equals(2, charges)
		assert.equals(1, #handled)
		assert.same(ability_ext, handled[1].self)
		assert.equals("combat_ability", handled[1].ability_type)
		assert.equals(2, handled[1].charges)
	end)

	it("dispatches ActionCharacterStateChange.finish through ItemFallback", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local forwarded = {}
		harness.modules.ItemFallback.on_state_change_finish = function(func, self, reason, data, t, time_in_action)
			forwarded[#forwarded + 1] = {
				self = self,
				reason = reason,
				t = t,
				time_in_action = time_in_action,
			}
			return func(self, reason, data, t, time_in_action)
		end

		local action = {
			finish = function(_self, reason, _data, t, time_in_action)
				return "orig-finish", reason, t, time_in_action
			end,
		}

		harness:invoke_hook_require("scripts/extension_systems/ability/actions/action_character_state_change", action)
		local tag, reason, t, time_in_action = action:finish("interrupted", {}, 12, 0.1)

		assert.equals("orig-finish", tag)
		assert.equals("interrupted", reason)
		assert.equals(12, t)
		assert.equals(0.1, time_in_action)
		assert.equals(1, #forwarded)
		assert.same(action, forwarded[1].self)
		assert.equals("interrupted", forwarded[1].reason)
		assert.equals(12, forwarded[1].t)
		assert.equals(0.1, forwarded[1].time_in_action)
	end)

	it("blocks BtBotActivateAbilityAction.enter when charge nav validation fails", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local validated = {}
		local emitted_events = {}
		harness.modules.ChargeNavValidation.should_validate = function(template_name)
			return template_name == "zealot_dash"
		end
		harness.modules.ChargeNavValidation.should_emit_block_event = function(reason)
			return reason ~= "cached_ray_blocked"
		end
		local validate_calls = 0
		harness.modules.ChargeNavValidation.validate = function(unit, template_name, source)
			validate_calls = validate_calls + 1
			validated[#validated + 1] = {
				unit = unit,
				template_name = template_name,
				source = source,
			}
			return false, validate_calls == 1 and "ray_blocked" or "cached_ray_blocked"
		end
		harness.modules.EventLog.is_enabled = function()
			return true
		end
		harness.modules.EventLog.emit = function(event)
			emitted_events[#emitted_events + 1] = event
		end

		local called = 0
		local action = {
			enter = function()
				called = called + 1
			end,
		}
		local unit_data_extension = test_helper.make_player_unit_data_extension({
			combat_ability_action = { template_name = "zealot_dash" },
		})
		local input_extension = test_helper.make_player_input_extension()

		_G.ScriptUnit = test_helper.make_script_unit_mock({
			bot_unit = {
				unit_data_system = unit_data_extension,
				input_system = input_extension,
			},
		})

		harness:invoke_hook_require(
			"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
			action
		)
		action:enter("bot_unit", nil, {}, {}, { ability_component_name = "combat_ability_action" }, 10)
		action:enter("bot_unit", nil, {}, {}, { ability_component_name = "combat_ability_action" }, 10.1)

		assert.equals(0, called)
		assert.same({
			{
				unit = "bot_unit",
				template_name = "zealot_dash",
				source = "bt_enter",
			},
			{
				unit = "bot_unit",
				template_name = "zealot_dash",
				source = "bt_enter",
			},
		}, validated)
		assert.same({
			{
				t = 0,
				event = "blocked",
				bot = 1,
				ability = "unknown",
				template = "zealot_dash",
				source = "bt_enter",
				reason = "ray_blocked",
			},
		}, emitted_events)
	end)

	it("does not mutate rescue aim before bt_enter charge validation blocks the action", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local ally_pos = { x = 12, y = -3, z = 0 }
		local call_order = {}
		local validated = {}
		local condition_init = find_named_call(harness.init_calls, "ConditionPatch")
		local rescue_intent = condition_init and condition_init.deps and condition_init.deps.rescue_intent

		assert.is_not_nil(rescue_intent, "ConditionPatch rescue_intent dep was not wired")

		harness.modules.ChargeNavValidation.should_validate = function(template_name)
			return template_name == "ogryn_charge"
		end
		harness.modules.ChargeNavValidation.validate = function(unit, template_name, source, opts)
			call_order[#call_order + 1] = "validate"
			validated[#validated + 1] = {
				unit = unit,
				template_name = template_name,
				source = source,
				target_position = opts and opts.target_position or nil,
			}
			return false, "ray_blocked"
		end

		local action = {
			enter = function()
				call_order[#call_order + 1] = "enter"
			end,
		}
		local unit_data_extension = test_helper.make_player_unit_data_extension({
			combat_ability_action = { template_name = "ogryn_charge" },
		})
		local bot_unit_input = test_helper.make_bot_unit_input({
			set_aiming = function()
				call_order[#call_order + 1] = "set_aiming"
			end,
			set_aim_position = function()
				call_order[#call_order + 1] = "set_aim_position"
			end,
		})
		local input_extension = test_helper.make_player_input_extension({
			bot_unit_input = bot_unit_input,
		})

		_G.POSITION_LOOKUP = {
			ally_unit = ally_pos,
		}
		_G.ScriptUnit = test_helper.make_script_unit_mock({
			bot_unit = {
				unit_data_system = unit_data_extension,
				input_system = input_extension,
			},
		})
		rescue_intent["bot_unit"] = "ally_unit"

		harness:invoke_hook_require(
			"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
			action
		)
		action:enter("bot_unit", nil, { perception = {} }, {}, { ability_component_name = "combat_ability_action" }, 10)

		assert.same({ "validate" }, call_order)
		assert.same({
			{
				unit = "bot_unit",
				template_name = "ogryn_charge",
				source = "bt_enter",
				target_position = ally_pos,
			},
		}, validated)
	end)

	it("installs behavior hooks once and dispatches update/init through extracted modules", function()
		local harness = make_bootstrap_harness()
		harness:load()

		local dispatched = { update = 0, inject = 0 }
		harness.modules.UpdateDispatcher.dispatch = function(self, unit)
			dispatched.update = dispatched.update + 1
			dispatched.last_self = self
			dispatched.last_unit = unit
		end
		harness.modules.GestaltInjector.inject = function(gestalts_or_nil, unit)
			dispatched.inject = dispatched.inject + 1
			dispatched.inject_unit = unit
			return gestalts_or_nil or { ranged = "killshot" }, true
		end

		local behavior_ext = {
			update = function() end,
			_init_blackboard_components = function(_self, _blackboard, _physics_world, gestalts_or_nil)
				return gestalts_or_nil
			end,
			_verify_target_ally_aid_destination = function() end,
			_refresh_destination = function() end,
		}

		harness:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)
		harness:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)

		assert.equals(1, count_hooks(harness.hook_registrations, behavior_ext, "_refresh_destination", "hook_safe"))
		assert.equals(
			1,
			count_hooks(harness.hook_registrations, behavior_ext, "_verify_target_ally_aid_destination", "hook_safe")
		)
		assert.equals(1, count_hooks(harness.hook_registrations, behavior_ext, "_init_blackboard_components", "hook"))
		assert.equals(1, count_hooks(harness.hook_registrations, behavior_ext, "update", "hook_safe"))

		behavior_ext._unit = "bot_unit_1"
		behavior_ext:update("bot_unit_1")
		local gestalts = behavior_ext:_init_blackboard_components({}, nil, nil)

		assert.equals(1, dispatched.update)
		assert.same(behavior_ext, dispatched.last_self)
		assert.equals("bot_unit_1", dispatched.last_unit)
		assert.equals(1, dispatched.inject)
		assert.equals("bot_unit_1", dispatched.inject_unit)
		assert.equals("killshot", gestalts.ranged)
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

	it("is idempotent on _update_target_enemy install across hot-reload (file re-execution)", function()
		-- Simulates Ctrl+Shift+R: BetterBots.lua re-executes, module-level
		-- locals reset, but BotPerceptionExtension class table persists.
		-- Sentinel must live on the class, not in a module-level local.
		local perception_ext = { _update_target_enemy = function() end }

		local harness1 = make_bootstrap_harness()
		harness1:load()
		harness1:invoke_hook_require("scripts/extension_systems/perception/bot_perception_extension", perception_ext)

		local harness2 = make_bootstrap_harness()
		harness2:load()
		harness2:invoke_hook_require("scripts/extension_systems/perception/bot_perception_extension", perception_ext)

		local count = 0
		for _, reg in ipairs(harness2.hook_registrations) do
			if reg.target == perception_ext and reg.method == "_update_target_enemy" then
				count = count + 1
			end
		end

		assert.equals(0, count)
	end)

	it("is idempotent on _refresh_destination install across hot-reload (file re-execution)", function()
		local behavior_ext = {
			_refresh_destination = function() end,
			_verify_target_ally_aid_destination = function() end,
			_init_blackboard_components = function() end,
			update = function() end,
		}

		local harness1 = make_bootstrap_harness()
		harness1:load()
		harness1:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)

		local harness2 = make_bootstrap_harness()
		harness2:load()
		harness2:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)

		assert.equals(0, count_hooks(harness2.hook_registrations, behavior_ext, "_refresh_destination", "hook_safe"))
		assert.equals(
			0,
			count_hooks(harness2.hook_registrations, behavior_ext, "_verify_target_ally_aid_destination", "hook_safe")
		)
		assert.equals(0, count_hooks(harness2.hook_registrations, behavior_ext, "_init_blackboard_components", "hook"))
		assert.equals(0, count_hooks(harness2.hook_registrations, behavior_ext, "update", "hook_safe"))
	end)

	it("is idempotent on BotGroup hook installation across hot-reload (file re-execution)", function()
		local bot_group = {
			init = function() end,
			_update_mule_pickups = function() end,
			_update_pickups_and_deployables_near_player = function() end,
		}

		local harness1 = make_bootstrap_harness()
		harness1:load()
		harness1:invoke_hook_require("scripts/extension_systems/group/bot_group", bot_group)

		local harness2 = make_bootstrap_harness()
		harness2:load()
		harness2:invoke_hook_require("scripts/extension_systems/group/bot_group", bot_group)

		assert.equals(0, count_hooks(harness2.hook_registrations, bot_group, "init", "hook_safe"))
		assert.equals(0, count_hooks(harness2.hook_registrations, bot_group, "_update_mule_pickups", "hook_safe"))
		assert.equals(
			0,
			count_hooks(
				harness2.hook_registrations,
				bot_group,
				"_update_pickups_and_deployables_near_player",
				"hook_safe"
			)
		)
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
		local source = read_bootstrap_surface()
		local init_block = assert(source:match("AbilityQueue%.init%(%{%s*(.-)%s*%}%)"))

		assert.is_truthy(init_block:find("perf%s*=%s*Perf", 1))
	end)

	it("restores close-range daemonhost suppression for ability activation", function()
		local source = read_bootstrap_surface()
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

		local function record_owner(target, path)
			local owners = owners_by_target[target]
			if not owners then
				owners = {}
				owners_by_target[target] = owners
			end

			for i = 1, #owners do
				if owners[i] == path then
					return
				end
			end

			owners[#owners + 1] = path
		end

		each_mod_source_file(function(path)
			local source = read_file(path)

			-- Collect `local IDENT = "LITERAL"` assignments so that
			-- `hook_require(IDENT, cb)` resolves to the underlying path.
			-- Without this step, wrapping the path in a module-local constant
			-- silently bypasses the duplicate check (as happened with #92 in
			-- weakspot_aim.lua before Codex caught the P0 at runtime).
			local local_string_consts = {}
			for ident, literal in source:gmatch('local%s+([%w_]+)%s*=%s*"([^"]+)"') do
				local_string_consts[ident] = literal
			end

			for target in source:gmatch('hook_require%(%s*"([^"]+)"') do
				record_owner(target, path)
			end

			for ident in source:gmatch("hook_require%(%s*([%w_]+)[,%)]") do
				local resolved = local_string_consts[ident]
				if resolved then
					record_owner(resolved, path)
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

	it("rejects duplicate DMF method hook ownership across BetterBots source files", function()
		local allowed_duplicates = {
			-- Test-only legacy helpers kept beside the production consolidated
			-- BotPerceptionExtension dispatcher; BetterBots.lua owns runtime install.
			["BotPerceptionExtension::_update_target_enemy"] = true,
		}
		local owners_by_target_method = {}
		local duplicates = {}

		each_mod_source_file(function(path)
			local source = read_file(path)
			for _, hook in ipairs(collect_method_hooks(path, source)) do
				local key = hook.target .. "::" .. hook.method_name
				local owners = owners_by_target_method[key]
				if not owners then
					owners = {}
					owners_by_target_method[key] = owners
				end

				owners[#owners + 1] = string.format("%s:%d:%s", hook.path, hook.line, hook.hook_type)
			end
		end)

		for key, owners in pairs(owners_by_target_method) do
			if #owners > 1 and not allowed_duplicates[key] then
				table.sort(owners)
				duplicates[#duplicates + 1] = key .. " => " .. table.concat(owners, ", ")
			end
		end

		table.sort(duplicates)
		assert.same({}, duplicates)
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

	it("restores session-scoped EventLog behavior on bootstrap after hot reload", function()
		local saved_mods = rawget(_G, "Mods")
		local event_log = dofile("scripts/mods/BetterBots/event_log.lua")

		_G.Mods = {
			lua = {
				io = {
					open = function()
						return nil
					end,
				},
				os = {
					execute = function() end,
					time = function()
						return 123
					end,
				},
			},
		}

		event_log._reset()

		local harness = make_bootstrap_harness({
			Debug = {
				collect_alive_bots = function()
					return { { unit = "bot_unit_1" } }
				end,
			},
			EventLog = event_log,
		})

		harness.mod:set("enable_event_log", true)
		harness:load()

		assert.is_true(event_log.is_enabled())
		assert.are.equal(0, #event_log._get_buffer())
		event_log.emit({ event = "probe" })
		assert.are.equal(1, #event_log._get_buffer())

		_G.Mods = saved_mods
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

	it("exposes the full 0-100 bot ranged ammo slider and warp peril slider in DMF settings", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots_data.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('make_numeric("bot_ranged_ammo_threshold", { 0, 100 }, 5)', 1, true))
		assert.is_truthy(source:find('make_numeric("warp_weapon_peril_threshold", { 0, 100 }, 1)', 1, true))
	end)

	it("surfaces weapon-special behavior in the melee and ranged settings copy", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots_localization.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find("supported melee weapon specials", 1, true))
		assert.is_truthy(source:find("supported shotgun special shells", 1, true))
		assert.is_truthy(source:find("warp_weapon_peril_threshold = {", 1, true))
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
