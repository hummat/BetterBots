-- Loads BetterBots modules and wires the cross-module dependency graph.
-- BetterBots.lua stays responsible for DMF entrypoints; this owns startup order.
local M = {}

local MODULE_ROOT = "BetterBots/scripts/mods/BetterBots/"

local function load_module(mod, filename)
	local module = mod:io_dofile(MODULE_ROOT .. filename)
	assert(module, "BetterBots: failed to load " .. filename .. " module")

	return module
end

function M.load_and_init(ctx)
	local mod = ctx.mod
	local modules = {
		LogLevels = ctx.LogLevels,
		SharedRules = ctx.SharedRules,
		CombatAbilityIdentity = ctx.CombatAbilityIdentity,
		BotTargeting = ctx.BotTargeting,
		TeamCooldown = ctx.TeamCooldown,
	}

	modules.MetaData = load_module(mod, "meta_data")
	modules.Settings = load_module(mod, "settings")
	modules.HeuristicsContext = load_module(mod, "heuristics_context")
	modules.HeuristicsVeteran = load_module(mod, "heuristics_veteran")
	modules.HeuristicsZealot = load_module(mod, "heuristics_zealot")
	modules.HeuristicsPsyker = load_module(mod, "heuristics_psyker")
	modules.HeuristicsOgryn = load_module(mod, "heuristics_ogryn")
	modules.HeuristicsArbites = load_module(mod, "heuristics_arbites")
	modules.HeuristicsHiveScum = load_module(mod, "heuristics_hive_scum")
	modules.HeuristicsGrenade = load_module(mod, "heuristics_grenade")
	modules.Heuristics = load_module(mod, "heuristics")
	modules.ItemProfiles = load_module(mod, "item_profiles")
	modules.ItemFallback = load_module(mod, "item_fallback")
	modules.ChargeTracker = load_module(mod, "charge_tracker")
	modules.GestaltInjector = load_module(mod, "gestalt_injector")
	modules.UpdateDispatcher = load_module(mod, "update_dispatcher")
	modules.Debug = load_module(mod, "debug")
	modules.EventLog = load_module(mod, "event_log")
	modules.Perf = load_module(mod, "perf")
	modules.Sprint = load_module(mod, "sprint")
	modules.MeleeMetaData = load_module(mod, "melee_meta_data")
	modules.MeleeAttackChoice = load_module(mod, "melee_attack_choice")
	modules.RangedMetaData = load_module(mod, "ranged_meta_data")
	modules.TargetSelection = load_module(mod, "target_selection")
	modules.Poxburster = load_module(mod, "poxburster")
	modules.SmartTargeting = load_module(mod, "smart_targeting")
	modules.AnimationGuard = load_module(mod, "animation_guard")
	modules.AirlockGuard = load_module(mod, "airlock_guard")
	modules.VfxSuppression = load_module(mod, "vfx_suppression")
	modules.WeaponActionLogging = load_module(mod, "weapon_action_logging")
	modules.WeaponActionShoot = load_module(mod, "weapon_action_shoot")
	modules.WeaponActionVoidblast = load_module(mod, "weapon_action_voidblast")
	modules.WeaponAction = load_module(mod, "weapon_action")
	modules.RangedSpecialAction = load_module(mod, "ranged_special_action")
	modules.SustainedFire = load_module(mod, "sustained_fire")
	modules.ConditionPatch = load_module(mod, "condition_patch")
	modules.AbilityQueue = load_module(mod, "ability_queue")
	modules.GrenadeFallback = load_module(mod, "grenade_fallback")
	modules.GrenadeProfiles = load_module(mod, "grenade_profiles")
	modules.GrenadeAim = load_module(mod, "grenade_aim")
	modules.GrenadeRuntime = load_module(mod, "grenade_runtime")
	modules.PingSystem = load_module(mod, "ping_system")
	modules.CompanionTag = load_module(mod, "companion_tag")
	modules.HealingDeferral = load_module(mod, "healing_deferral")
	modules.AmmoPolicy = load_module(mod, "ammo_policy")
	modules.ComWheelResponse = load_module(mod, "com_wheel_response")
	modules.MulePickup = load_module(mod, "mule_pickup")
	modules.PocketablePickup = load_module(mod, "pocketable_pickup")
	modules.SmartTagOrders = load_module(mod, "smart_tag_orders")
	modules.BotProfileTemplates = load_module(mod, "bot_profile_templates")
	modules.BotProfiles = load_module(mod, "bot_profiles")
	modules.HumanLikeness = load_module(mod, "human_likeness")
	modules.TargetTypeHysteresis = load_module(mod, "target_type_hysteresis")
	modules.WeakspotAim = load_module(mod, "weakspot_aim")
	modules.ChargeNavValidation = load_module(mod, "charge_nav_validation")
	modules.EngagementLeash = load_module(mod, "engagement_leash")
	modules.ReviveAbility = load_module(mod, "revive_ability")

	local Settings = modules.Settings
	local CombatAbilityIdentity = modules.CombatAbilityIdentity
	local BotTargeting = modules.BotTargeting
	local SharedRules = modules.SharedRules
	local TeamCooldown = modules.TeamCooldown
	local MetaData = modules.MetaData
	local Heuristics = modules.Heuristics
	local HeuristicsContext = modules.HeuristicsContext
	local HeuristicsVeteran = modules.HeuristicsVeteran
	local HeuristicsZealot = modules.HeuristicsZealot
	local HeuristicsPsyker = modules.HeuristicsPsyker
	local HeuristicsOgryn = modules.HeuristicsOgryn
	local HeuristicsArbites = modules.HeuristicsArbites
	local HeuristicsHiveScum = modules.HeuristicsHiveScum
	local HeuristicsGrenade = modules.HeuristicsGrenade
	local ItemProfiles = modules.ItemProfiles
	local ItemFallback = modules.ItemFallback
	local ChargeTracker = modules.ChargeTracker
	local GestaltInjector = modules.GestaltInjector
	local UpdateDispatcher = modules.UpdateDispatcher
	local Debug = modules.Debug
	local EventLog = modules.EventLog
	local Perf = modules.Perf
	local Sprint = modules.Sprint
	local MeleeMetaData = modules.MeleeMetaData
	local MeleeAttackChoice = modules.MeleeAttackChoice
	local RangedMetaData = modules.RangedMetaData
	local TargetSelection = modules.TargetSelection
	local Poxburster = modules.Poxburster
	local SmartTargeting = modules.SmartTargeting
	local AnimationGuard = modules.AnimationGuard
	local AirlockGuard = modules.AirlockGuard
	local VfxSuppression = modules.VfxSuppression
	local WeaponActionLogging = modules.WeaponActionLogging
	local WeaponActionShoot = modules.WeaponActionShoot
	local WeaponActionVoidblast = modules.WeaponActionVoidblast
	local WeaponAction = modules.WeaponAction
	local RangedSpecialAction = modules.RangedSpecialAction
	local SustainedFire = modules.SustainedFire
	local ConditionPatch = modules.ConditionPatch
	local AbilityQueue = modules.AbilityQueue
	local GrenadeFallback = modules.GrenadeFallback
	local GrenadeProfiles = modules.GrenadeProfiles
	local GrenadeAim = modules.GrenadeAim
	local GrenadeRuntime = modules.GrenadeRuntime
	local PingSystem = modules.PingSystem
	local CompanionTag = modules.CompanionTag
	local HealingDeferral = modules.HealingDeferral
	local AmmoPolicy = modules.AmmoPolicy
	local ComWheelResponse = modules.ComWheelResponse
	local MulePickup = modules.MulePickup
	local PocketablePickup = modules.PocketablePickup
	local SmartTagOrders = modules.SmartTagOrders
	local BotProfileTemplates = modules.BotProfileTemplates
	local BotProfiles = modules.BotProfiles
	local HumanLikeness = modules.HumanLikeness
	local TargetTypeHysteresis = modules.TargetTypeHysteresis
	local WeakspotAim = modules.WeakspotAim
	local ChargeNavValidation = modules.ChargeNavValidation
	local EngagementLeash = modules.EngagementLeash
	local ReviveAbility = modules.ReviveAbility

	CombatAbilityIdentity.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
	})

	Settings.init({
		mod = mod,
		combat_ability_identity = CombatAbilityIdentity,
	})

	BotProfiles.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		profile_templates = BotProfileTemplates,
	})

	HumanLikeness.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		get_timing_config = Settings.resolve_human_timing_config,
		get_pressure_leash_config = Settings.resolve_pressure_leash_config,
	})

	TargetTypeHysteresis.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		close_range_ranged_policy = RangedMetaData.close_range_ranged_policy,
		is_enabled = function()
			return Settings.is_feature_enabled("target_type_hysteresis")
		end,
		perf = Perf,
	})

	WeakspotAim.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		is_enabled = function()
			return Settings.is_feature_enabled("weakspot_aim")
		end,
	})

	ChargeNavValidation.init({
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_targeting = BotTargeting,
		is_enabled = function()
			return Settings.is_feature_enabled("charge_nav_validation")
		end,
	})

	EngagementLeash.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		is_enabled = function()
			return Settings.is_feature_enabled("engagement_leash")
		end,
		HumanLikeness = HumanLikeness,
		Heuristics = Heuristics,
	})

	MetaData.init({
		mod = mod,
		patched_ability_templates = ctx.patched_ability_templates,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		META_PATCH_VERSION = ctx.META_PATCH_VERSION,
	})

	Heuristics.init({
		fixed_time = ctx.fixed_time,
		decision_context_cache = ctx.decision_context_cache_by_unit,
		resolve_decision_cache = ctx.resolve_decision_cache_by_unit,
		resolve_decision_cache_hits_logged = ctx.resolve_decision_cache_hits_logged_by_unit,
		super_armor_breed_cache = ctx.super_armor_breed_flag_by_name,
		ARMOR_TYPE_SUPER_ARMOR = ctx.ARMOR_TYPE_SUPER_ARMOR,
		is_testing_profile = Settings.is_testing_profile,
		resolve_preset = Settings.resolve_preset,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		combat_ability_identity = CombatAbilityIdentity,
		shared_rules = SharedRules,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
		warp_weapon_peril_threshold = Settings.warp_weapon_peril_threshold,
		context_module = HeuristicsContext,
		veteran_module = HeuristicsVeteran,
		zealot_module = HeuristicsZealot,
		psyker_module = HeuristicsPsyker,
		ogryn_module = HeuristicsOgryn,
		arbites_module = HeuristicsArbites,
		hive_scum_module = HeuristicsHiveScum,
		grenade_module = HeuristicsGrenade,
	})

	ItemFallback.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		last_charge_event_by_unit = ctx.last_charge_event_by_unit,
		fallback_queue_dumped_by_key = ctx.fallback_queue_dumped_by_key,
		ITEM_WIELD_TIMEOUT_S = 1.5,
		ITEM_SEQUENCE_RETRY_S = 1.0,
		ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.2,
		ITEM_DEFAULT_START_DELAY_S = 0.2,
		event_log = EventLog,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		item_profiles = ItemProfiles,
	})

	Debug.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		last_charge_event_by_unit = ctx.last_charge_event_by_unit,
	})

	EventLog.init({
		mod = mod,
		context_snapshot = Debug.context_snapshot,
	})

	ChargeTracker.init({
		fixed_time = ctx.fixed_time,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		last_charge_event_by_unit = ctx.last_charge_event_by_unit,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		grenade_fallback = GrenadeFallback,
		settings = Settings,
		team_cooldown = TeamCooldown,
		combat_ability_identity = CombatAbilityIdentity,
		event_log = EventLog,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
	})

	GestaltInjector.init({
		default_ranged_gestalt = ctx.DEFAULT_RANGED_GESTALT,
		default_melee_gestalt = ctx.DEFAULT_MELEE_GESTALT,
		injected_units = ctx.gestalt_injected_units,
	})

	UpdateDispatcher.init({
		perf = Perf,
		event_log = EventLog,
		debug = Debug,
		ability_queue = AbilityQueue,
		grenade_fallback = GrenadeFallback,
		pocketable_pickup = PocketablePickup,
		ping_system = PingSystem,
		companion_tag = CompanionTag,
		settings = Settings,
		build_context = Heuristics.build_context,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		last_snapshot_t_by_unit = ctx.last_snapshot_t_by_unit,
		session_start_state = ctx.session_start_state,
		snapshot_interval_s = ctx.SNAPSHOT_INTERVAL_S,
		meta_patch_version = ctx.META_PATCH_VERSION,
		fixed_time = ctx.fixed_time,
	})

	Perf.init({
		get_setting = function(setting_id)
			return mod:get(setting_id)
		end,
		setting_id = ctx.PERF_SETTING_ID,
	})

	Sprint.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		shared_rules = SharedRules,
		sprint_follow_distance = Settings.sprint_follow_distance,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
	})

	MeleeMetaData.init({
		mod = mod,
		patched_weapon_templates = ctx.patched_weapon_templates,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		ARMOR_TYPE_ARMORED = ctx.ARMOR_TYPES and ctx.ARMOR_TYPES.armored,
		is_enabled = function()
			return Settings.is_feature_enabled("melee_improvements")
		end,
	})

	MeleeAttackChoice.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		ARMOR_TYPE_ARMORED = ctx.ARMOR_TYPES and ctx.ARMOR_TYPES.armored,
		ARMOR_TYPE_SUPER_ARMOR = ctx.ARMOR_TYPE_SUPER_ARMOR,
		is_enabled = function()
			return Settings.is_feature_enabled("melee_improvements")
		end,
		melee_horde_light_bias = Settings.melee_horde_light_bias,
	})

	RangedMetaData.init({
		mod = mod,
		patched_weapon_templates = ctx.patched_weapon_templates_ranged,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		is_enabled = function()
			return Settings.is_feature_enabled("ranged_improvements")
		end,
		rippergun_bayonet_distance = Settings.rippergun_bayonet_distance,
	})

	TargetSelection.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		player_tag_bonus = Settings.player_tag_bonus,
		special_chase_penalty_range = Settings.special_chase_penalty_range,
		shared_rules = SharedRules,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
	})

	Poxburster.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		is_enabled = function()
			return Settings.is_feature_enabled("poxburster")
		end,
		should_suppress_defend = MeleeAttackChoice.should_suppress_defend,
	})

	AnimationGuard.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
	})

	AirlockGuard.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
	})

	SmartTargeting.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_targeting = BotTargeting,
		is_enabled = function()
			return Settings.is_feature_enabled("smart_targeting")
		end,
	})

	VfxSuppression.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
	})

	WeaponAction.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		perf = Perf,
		close_range_ranged_policy = RangedMetaData.close_range_ranged_policy,
		is_enabled = function()
			return Settings.is_feature_enabled("ranged_improvements")
		end,
		warp_weapon_peril_threshold = Settings.warp_weapon_peril_threshold,
		is_weakspot_aim_enabled = function()
			return Settings.is_feature_enabled("weakspot_aim")
		end,
		weapon_action_logging = WeaponActionLogging,
		weapon_action_shoot = WeaponActionShoot,
		weapon_action_voidblast = WeaponActionVoidblast,
	})

	RangedSpecialAction.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		ARMOR_TYPE_ARMORED = ctx.ARMOR_TYPES and ctx.ARMOR_TYPES.armored,
		ARMOR_TYPE_SUPER_ARMOR = ctx.ARMOR_TYPE_SUPER_ARMOR,
		is_enabled = function()
			return Settings.is_feature_enabled("ranged_improvements")
		end,
		rippergun_bayonet_distance = Settings.rippergun_bayonet_distance,
		ranged_bash_distance = Settings.ranged_bash_distance,
	})

	SustainedFire.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		is_enabled = function()
			return Settings.is_feature_enabled("ranged_improvements")
		end,
	})

	ConditionPatch.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		is_suppressed = ctx.is_suppressed,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		patched_bt_bot_conditions = ctx.patched_bt_bot_conditions,
		patched_bt_conditions = ctx.patched_bt_conditions,
		rescue_intent = ctx.rescue_intent,
		DEBUG_SKIP_RELIC_LOG_INTERVAL_S = ctx.DEBUG_SKIP_RELIC_LOG_INTERVAL_S,
		CONDITIONS_PATCH_VERSION = ctx.CONDITIONS_PATCH_VERSION,
		perf = Perf,
		shared_rules = SharedRules,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
		is_near_daemonhost = function(unit)
			return Sprint.is_near_daemonhost(unit, Sprint.DAEMONHOST_COMBAT_RANGE_SQ)
		end,
	})

	AbilityQueue.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		equipped_combat_ability = ctx.equipped_combat_ability,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		is_suppressed = ctx.is_suppressed,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		fallback_queue_dumped_by_key = ctx.fallback_queue_dumped_by_key,
		DEBUG_SKIP_RELIC_LOG_INTERVAL_S = ctx.DEBUG_SKIP_RELIC_LOG_INTERVAL_S,
		perf = Perf,
		shared_rules = SharedRules,
	})

	ReviveAbility.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		is_suppressed = ctx.is_suppressed,
		equipped_combat_ability_name = ctx.equipped_combat_ability_name,
		fallback_state_by_unit = ctx.fallback_state_by_unit,
		perf = Perf,
		shared_rules = SharedRules,
		combat_ability_identity = CombatAbilityIdentity,
	})

	GrenadeFallback.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		event_log = EventLog,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		is_suppressed = ctx.is_suppressed,
		grenade_state_by_unit = ctx.grenade_state_by_unit,
		last_grenade_charge_event_by_unit = ctx.last_grenade_charge_event_by_unit,
		perf = Perf,
		warp_weapon_peril_threshold = Settings.warp_weapon_peril_threshold,
		grenade_profiles = GrenadeProfiles,
		grenade_aim = GrenadeAim,
		grenade_runtime = GrenadeRuntime,
	})

	PingSystem.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		bot_targeting = BotTargeting,
		has_recent_companion_target = CompanionTag.is_recent_command_target,
		shared_rules = SharedRules,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
	})

	CompanionTag.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		bot_targeting = BotTargeting,
		shared_rules = SharedRules,
		is_daemonhost_avoidance_enabled = function()
			return Settings.is_feature_enabled("daemonhost_avoidance")
		end,
	})

	HealingDeferral.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		com_wheel = ComWheelResponse,
	})

	AmmoPolicy.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		perf = Perf,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		settings = Settings,
		com_wheel = ComWheelResponse,
		is_enabled = function()
			return Settings.is_feature_enabled("ammo_policy")
		end,
	})

	ComWheelResponse.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		is_enabled = function()
			return Settings.is_feature_enabled("com_wheel_responses")
		end,
	})

	PocketablePickup.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		state_by_unit = ctx.pocketable_state_by_unit,
		build_context = Heuristics.build_context,
		is_enabled = function()
			return Settings.is_feature_enabled("pocketable_support")
		end,
	})

	SmartTagOrders.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		fixed_time = ctx.fixed_time,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		is_enabled = function()
			return Settings.is_feature_enabled("smart_tag_orders")
		end,
	})

	MulePickup.init({
		mod = mod,
		debug_log = ctx.debug_log,
		debug_enabled = ctx.debug_enabled,
		bot_slot_for_unit = Debug.bot_slot_for_unit,
		is_grimoire_pickup_enabled = function()
			return Settings.is_bot_grimoire_pickup_enabled()
		end,
		is_tome_pickup_enabled = function()
			return Settings.is_feature_enabled("bot_tome_pickup")
		end,
		should_allow_mule_pickup = PocketablePickup.should_allow_mule_pickup,
		should_block_pickup_order = PocketablePickup.should_block_pickup_order,
	})

	SmartTagOrders.wire({
		should_block_pickup_order = MulePickup.should_block_pickup_order,
		needs_ammo_pickup = function(unit)
			local Ammo = require("scripts/utilities/ammo")
			local missing_reserve_ammo = Ammo and not Ammo.reserve_ammo_is_full(unit) or false

			return missing_reserve_ammo
				or (
					AmmoPolicy.needs_ammo_pickup_for_grenade_refill
					and AmmoPolicy.needs_ammo_pickup_for_grenade_refill(unit)
				)
		end,
	})

	Settings.wire({
		behavior_profile_override = ComWheelResponse.override_behavior_profile,
	})

	ItemFallback.wire({
		build_context = Heuristics.build_context,
		context_snapshot = Debug.context_snapshot,
		fallback_state_snapshot = Debug.fallback_state_snapshot,
		evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
		is_item_ability_enabled = Settings.is_item_ability_enabled,
		query_weapon_switch_lock = function(unit)
			local should_lock, ability_name, lock_reason, slot_to_keep = ItemFallback.should_lock_weapon_switch(unit)
			if should_lock then
				return should_lock, ability_name, lock_reason, slot_to_keep
			end

			return GrenadeFallback.should_lock_weapon_switch(unit)
		end,
	})

	Debug.wire({
		build_context = Heuristics.build_context,
		resolve_decision = Heuristics.resolve_decision,
		enemy_breed = Heuristics.enemy_breed,
		can_use_item_fallback = ItemFallback.can_use_item_fallback,
	})

	ConditionPatch.wire({
		Heuristics = Heuristics,
		MetaData = MetaData,
		Debug = Debug,
		EventLog = EventLog,
		is_combat_template_enabled = Settings.is_combat_template_enabled,
		bot_ranged_ammo_threshold = Settings.bot_ranged_ammo_threshold,
		TeamCooldown = TeamCooldown,
		combat_ability_identity = CombatAbilityIdentity,
		is_team_cooldown_enabled = function()
			return Settings.is_feature_enabled("team_cooldown")
		end,
	})

	AbilityQueue.wire({
		Heuristics = Heuristics,
		MetaData = MetaData,
		ItemFallback = ItemFallback,
		Debug = Debug,
		EventLog = EventLog,
		EngagementLeash = EngagementLeash,
		ChargeNavValidation = ChargeNavValidation,
		TeamCooldown = TeamCooldown,
		CombatAbilityIdentity = CombatAbilityIdentity,
		HumanLikeness = HumanLikeness,
		is_combat_template_enabled = Settings.is_combat_template_enabled,
		is_team_cooldown_enabled = function()
			return Settings.is_feature_enabled("team_cooldown")
		end,
	})

	return modules
end

return M
