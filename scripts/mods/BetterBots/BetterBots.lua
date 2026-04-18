local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local LogLevels = mod:io_dofile("BetterBots/scripts/mods/BetterBots/log_levels")
local SharedRules = mod:io_dofile("BetterBots/scripts/mods/BetterBots/shared_rules")
local CombatAbilityIdentity = mod:io_dofile("BetterBots/scripts/mods/BetterBots/combat_ability_identity")
assert(CombatAbilityIdentity, "BetterBots: failed to load combat_ability_identity module")
local BotTargeting = mod:io_dofile("BetterBots/scripts/mods/BetterBots/bot_targeting")
local TeamCooldown = mod:io_dofile("BetterBots/scripts/mods/BetterBots/team_cooldown")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local EVENT_LOG_SETTING_ID = "enable_event_log"
local META_PATCH_VERSION = "2026-03-04-tier2-v3"
local CONDITIONS_PATCH_VERSION = "2026-03-05-conditions-v4"
local _last_debug_log_t_by_key = {}
local _patched_bt_bot_conditions = setmetatable({}, { __mode = "k" })
local _patched_bt_conditions = setmetatable({}, { __mode = "k" })
local _patched_ability_templates = setmetatable({}, { __mode = "k" })
local _patched_weapon_templates = setmetatable({}, { __mode = "k" })
local _patched_weapon_templates_ranged = setmetatable({}, { __mode = "k" })
local _fallback_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_charge_event_by_unit = setmetatable({}, { __mode = "k" })
local _grenade_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_grenade_charge_event_by_unit = setmetatable({}, { __mode = "k" })
local _pocketable_state_by_unit = setmetatable({}, { __mode = "k" })
local _fallback_queue_dumped_by_key = {}
local _decision_context_cache_by_unit = setmetatable({}, { __mode = "k" })
local _resolve_decision_cache_by_unit = setmetatable({}, { __mode = "k" })
local _resolve_decision_cache_hits_logged_by_unit = setmetatable({}, { __mode = "k" })
local _suppression_cache_by_unit = setmetatable({}, { __mode = "k" })
local _session_start_state = { emitted = false }
local _SNAPSHOT_INTERVAL_S = 30
local _last_snapshot_t_by_unit = setmetatable({}, { __mode = "k" })
local _super_armor_breed_flag_by_name = {}
local _log_level = 0
local _bot_settings
local PERF_SETTING_ID = "enable_perf_timing"
local Settings
local Sprint
local TIMING_SETTING_IDS = {
	human_timing_profile = true,
	human_timing_reaction_min = true,
	human_timing_reaction_max = true,
	human_timing_defensive_jitter_min_ms = true,
	human_timing_defensive_jitter_max_ms = true,
	human_timing_opportunistic_jitter_min_ms = true,
	human_timing_opportunistic_jitter_max_ms = true,
}

-- ADS fix (#35): T5/T6 bot profiles lack bot_gestalts, causing fallback to
-- "none" gestalt which disables aim-down-sights. Inject safe defaults.
local DEFAULT_RANGED_GESTALT = "killshot"
local DEFAULT_MELEE_GESTALT = "linesman"
local _gestalt_injected_units = setmetatable({}, { __mode = "k" })

-- Rescue aim (#10): when a charge/dash activates for ally rescue, store the
-- ally unit so the enter hook can aim the bot toward it before the lunge fires.
local _rescue_intent = setmetatable({}, { __mode = "k" })

local ARMOR_TYPES = ArmorSettings.types
local ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPES and ARMOR_TYPES.super_armor
if not mod._raw_hook_require then
	mod._raw_hook_require = mod.hook_require
end
local _original_hook_require = mod._raw_hook_require
local _hook_require_callsite_by_path = {}

function mod:hook_require(path, callback)
	local caller = debug.getinfo(2, "Sl")
	local callsite = string.format("%s:%s", caller and caller.short_src or "?", caller and caller.currentline or 0)
	local first_callsite = _hook_require_callsite_by_path[path]

	if first_callsite then
		error(
			string.format(
				"BetterBots duplicate hook_require for %s at %s (first registered at %s)",
				tostring(path),
				callsite,
				first_callsite
			)
		)
	end

	_hook_require_callsite_by_path[path] = callsite

	return _original_hook_require(self, path, callback)
end

local function _fixed_time()
	return FixedFrame.get_latest_fixed_time() or 0
end

local function _refresh_debug_log_level()
	_log_level = LogLevels.resolve_setting(mod:get(DEBUG_SETTING_ID))
end

local function _debug_enabled()
	return _log_level > 0
end

local function _debug_log(key, fixed_t, message, min_interval_s, level)
	if not LogLevels.should_log(_log_level, level) then
		return
	end

	local t = fixed_t or 0
	local interval_s = min_interval_s or DEBUG_LOG_INTERVAL_S
	local last_t = _last_debug_log_t_by_key[key]
	if last_t and t - last_t < interval_s then
		return
	end

	_last_debug_log_t_by_key[key] = t
	mod:echo("BetterBots DEBUG: " .. message:gsub("%%", "%%%%"))
end

_refresh_debug_log_level()

local _SUPPRESSED_STATES = {
	jumping = true,
	ladder_climbing = true,
	ladder_top_entering = true,
	ladder_top_leaving = true,
	ladder_bottom_entering = true,
	ladder_bottom_leaving = true,
}

local function _is_suppressed(unit)
	local fixed_t = _fixed_time()
	local cached = _suppression_cache_by_unit[unit]
	if cached and cached.fixed_t == fixed_t then
		return cached.suppressed, cached.reason
	end

	local function remember(suppressed, reason)
		_suppression_cache_by_unit[unit] = {
			fixed_t = fixed_t,
			suppressed = suppressed,
			reason = reason,
		}
		return suppressed, reason
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return remember(false)
	end

	local movement = unit_data_extension:read_component("movement_state")
	if movement then
		if movement.is_dodging then
			return remember(true, "dodging")
		end
		if movement.method == "falling" then
			return remember(true, "falling")
		end
	end

	local lunge = unit_data_extension:read_component("lunge_character_state")
	if lunge and (lunge.is_lunging or lunge.is_aiming) then
		return remember(true, "lunging")
	end

	local character_state = unit_data_extension:read_component("character_state")
	if character_state and _SUPPRESSED_STATES[character_state.state_name] then
		return remember(true, character_state.state_name)
	end

	local locomotion = unit_data_extension:read_component("locomotion")
	if locomotion and locomotion.parent_unit ~= nil then
		return remember(true, "moving_platform")
	end

	-- #17: keep offensive abilities and blitzes quiet when the bot is actually
	-- inside the close daemonhost safety radius. This is intentionally tighter
	-- than the sprint safety radius so bots still fight mixed encounters unless
	-- they are crowding the sleeping daemonhost.
	if
		Settings.is_feature_enabled("daemonhost_avoidance")
		and Sprint.is_near_daemonhost(unit, Sprint.DAEMONHOST_COMBAT_RANGE_SQ)
	then
		return remember(true, "daemonhost_nearby")
	end

	return remember(false)
end

local function _equipped_combat_ability(unit)
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	local equipped_abilities = ability_extension and ability_extension._equipped_abilities
	local combat_ability = equipped_abilities and equipped_abilities.combat_ability

	return ability_extension, combat_ability
end

local function _equipped_combat_ability_name(unit)
	local _, combat_ability = _equipped_combat_ability(unit)

	return combat_ability and combat_ability.name or "unknown"
end

local function _equipped_grenade_ability(unit)
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	local equipped_abilities = ability_extension and ability_extension._equipped_abilities
	local grenade_ability = equipped_abilities and equipped_abilities.grenade_ability
	return ability_extension, grenade_ability
end

-- Sub-modules
local MetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/meta_data")
assert(MetaData, "BetterBots: failed to load meta_data module")

Settings = mod:io_dofile("BetterBots/scripts/mods/BetterBots/settings")
assert(Settings, "BetterBots: failed to load settings module")

local HeuristicsContext = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_context")
assert(HeuristicsContext, "BetterBots: failed to load heuristics_context module")

local HeuristicsVeteran = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_veteran")
assert(HeuristicsVeteran, "BetterBots: failed to load heuristics_veteran module")

local HeuristicsZealot = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_zealot")
assert(HeuristicsZealot, "BetterBots: failed to load heuristics_zealot module")

local HeuristicsPsyker = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_psyker")
assert(HeuristicsPsyker, "BetterBots: failed to load heuristics_psyker module")

local HeuristicsOgryn = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_ogryn")
assert(HeuristicsOgryn, "BetterBots: failed to load heuristics_ogryn module")

local HeuristicsArbites = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_arbites")
assert(HeuristicsArbites, "BetterBots: failed to load heuristics_arbites module")

local HeuristicsHiveScum = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_hive_scum")
assert(HeuristicsHiveScum, "BetterBots: failed to load heuristics_hive_scum module")

local HeuristicsGrenade = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_grenade")
assert(HeuristicsGrenade, "BetterBots: failed to load heuristics_grenade module")

local Heuristics = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics")
assert(Heuristics, "BetterBots: failed to load heuristics module")

local ItemFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/item_fallback")
assert(ItemFallback, "BetterBots: failed to load item_fallback module")

local ChargeTracker = mod:io_dofile("BetterBots/scripts/mods/BetterBots/charge_tracker")
assert(ChargeTracker, "BetterBots: failed to load charge_tracker module")

local GestaltInjector = mod:io_dofile("BetterBots/scripts/mods/BetterBots/gestalt_injector")
assert(GestaltInjector, "BetterBots: failed to load gestalt_injector module")

local UpdateDispatcher = mod:io_dofile("BetterBots/scripts/mods/BetterBots/update_dispatcher")
assert(UpdateDispatcher, "BetterBots: failed to load update_dispatcher module")

local Debug = mod:io_dofile("BetterBots/scripts/mods/BetterBots/debug")
assert(Debug, "BetterBots: failed to load debug module")

local EventLog = mod:io_dofile("BetterBots/scripts/mods/BetterBots/event_log")
assert(EventLog, "BetterBots: failed to load event_log module")

local Perf = mod:io_dofile("BetterBots/scripts/mods/BetterBots/perf")
assert(Perf, "BetterBots: failed to load perf module")

Sprint = mod:io_dofile("BetterBots/scripts/mods/BetterBots/sprint")
assert(Sprint, "BetterBots: failed to load sprint module")

local MeleeMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/melee_meta_data")
assert(MeleeMetaData, "BetterBots: failed to load melee_meta_data module")

local MeleeAttackChoice = mod:io_dofile("BetterBots/scripts/mods/BetterBots/melee_attack_choice")
assert(MeleeAttackChoice, "BetterBots: failed to load melee_attack_choice module")

local RangedMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ranged_meta_data")
assert(RangedMetaData, "BetterBots: failed to load ranged_meta_data module")

local TargetSelection = mod:io_dofile("BetterBots/scripts/mods/BetterBots/target_selection")
assert(TargetSelection, "BetterBots: failed to load target_selection module")

local Poxburster = mod:io_dofile("BetterBots/scripts/mods/BetterBots/poxburster")
assert(Poxburster, "BetterBots: failed to load poxburster module")

local SmartTargeting = mod:io_dofile("BetterBots/scripts/mods/BetterBots/smart_targeting")
assert(SmartTargeting, "BetterBots: failed to load smart_targeting module")

local AnimationGuard = mod:io_dofile("BetterBots/scripts/mods/BetterBots/animation_guard")
assert(AnimationGuard, "BetterBots: failed to load animation_guard module")

local AirlockGuard = mod:io_dofile("BetterBots/scripts/mods/BetterBots/airlock_guard")
assert(AirlockGuard, "BetterBots: failed to load airlock_guard module")

local VfxSuppression = mod:io_dofile("BetterBots/scripts/mods/BetterBots/vfx_suppression")
assert(VfxSuppression, "BetterBots: failed to load vfx_suppression module")

local WeaponAction = mod:io_dofile("BetterBots/scripts/mods/BetterBots/weapon_action")
assert(WeaponAction, "BetterBots: failed to load weapon_action module")

local SustainedFire = mod:io_dofile("BetterBots/scripts/mods/BetterBots/sustained_fire")
assert(SustainedFire, "BetterBots: failed to load sustained_fire module")

local ConditionPatch = mod:io_dofile("BetterBots/scripts/mods/BetterBots/condition_patch")
assert(ConditionPatch, "BetterBots: failed to load condition_patch module")

local AbilityQueue = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ability_queue")
assert(AbilityQueue, "BetterBots: failed to load ability_queue module")

local GrenadeFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/grenade_fallback")
assert(GrenadeFallback, "BetterBots: failed to load grenade_fallback module")

local PingSystem = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ping_system")
assert(PingSystem, "BetterBots: failed to load ping_system module")

local CompanionTag = mod:io_dofile("BetterBots/scripts/mods/BetterBots/companion_tag")
assert(CompanionTag, "BetterBots: failed to load companion_tag module")

local HealingDeferral = mod:io_dofile("BetterBots/scripts/mods/BetterBots/healing_deferral")
assert(HealingDeferral, "BetterBots: failed to load healing_deferral module")

local AmmoPolicy = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ammo_policy")
assert(AmmoPolicy, "BetterBots: failed to load ammo_policy module")

local MulePickup = mod:io_dofile("BetterBots/scripts/mods/BetterBots/mule_pickup")
assert(MulePickup, "BetterBots: failed to load mule_pickup module")

local PocketablePickup = mod:io_dofile("BetterBots/scripts/mods/BetterBots/pocketable_pickup")
assert(PocketablePickup, "BetterBots: failed to load pocketable_pickup module")

local BotProfiles = mod:io_dofile("BetterBots/scripts/mods/BetterBots/bot_profiles")
assert(BotProfiles, "BetterBots: failed to load bot_profiles module")

local HumanLikeness = mod:io_dofile("BetterBots/scripts/mods/BetterBots/human_likeness")
assert(HumanLikeness, "BetterBots: failed to load human_likeness module")

local TargetTypeHysteresis = mod:io_dofile("BetterBots/scripts/mods/BetterBots/target_type_hysteresis")
assert(TargetTypeHysteresis, "BetterBots: failed to load target_type_hysteresis module")

local WeakspotAim = mod:io_dofile("BetterBots/scripts/mods/BetterBots/weakspot_aim")
assert(WeakspotAim, "BetterBots: failed to load weakspot_aim module")

local ChargeNavValidation = mod:io_dofile("BetterBots/scripts/mods/BetterBots/charge_nav_validation")
assert(ChargeNavValidation, "BetterBots: failed to load charge_nav_validation module")

local EngagementLeash = mod:io_dofile("BetterBots/scripts/mods/BetterBots/engagement_leash")
assert(EngagementLeash, "BetterBots: failed to load engagement_leash module")

local ReviveAbility = mod:io_dofile("BetterBots/scripts/mods/BetterBots/revive_ability")
assert(ReviveAbility, "BetterBots: failed to load revive_ability module")

-- Init each module with its dependencies
CombatAbilityIdentity.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
})

Settings.init({
	mod = mod,
	combat_ability_identity = CombatAbilityIdentity,
})

BotProfiles.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
})

HumanLikeness.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	get_timing_config = Settings.resolve_human_timing_config,
	get_pressure_leash_config = Settings.resolve_pressure_leash_config,
})

TargetTypeHysteresis.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	close_range_ranged_policy = RangedMetaData.close_range_ranged_policy,
	is_enabled = function()
		return Settings.is_feature_enabled("target_type_hysteresis")
	end,
	perf = Perf,
})

WeakspotAim.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	is_enabled = function()
		return Settings.is_feature_enabled("weakspot_aim")
	end,
})

ChargeNavValidation.init({
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_targeting = BotTargeting,
	is_enabled = function()
		return Settings.is_feature_enabled("charge_nav_validation")
	end,
})

EngagementLeash.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	is_enabled = function()
		return Settings.is_feature_enabled("engagement_leash")
	end,
	HumanLikeness = HumanLikeness,
	Heuristics = Heuristics,
})

MetaData.init({
	mod = mod,
	patched_ability_templates = _patched_ability_templates,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	META_PATCH_VERSION = META_PATCH_VERSION,
})

Heuristics.init({
	fixed_time = _fixed_time,
	decision_context_cache = _decision_context_cache_by_unit,
	resolve_decision_cache = _resolve_decision_cache_by_unit,
	resolve_decision_cache_hits_logged = _resolve_decision_cache_hits_logged_by_unit,
	super_armor_breed_cache = _super_armor_breed_flag_by_name,
	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
	is_testing_profile = Settings.is_testing_profile,
	resolve_preset = Settings.resolve_preset,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	combat_ability_identity = CombatAbilityIdentity,
	shared_rules = SharedRules,
	is_daemonhost_avoidance_enabled = function()
		return Settings.is_feature_enabled("daemonhost_avoidance")
	end,
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
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_charge_event_by_unit = _last_charge_event_by_unit,
	fallback_queue_dumped_by_key = _fallback_queue_dumped_by_key,
	ITEM_WIELD_TIMEOUT_S = 1.5,
	ITEM_SEQUENCE_RETRY_S = 1.0,
	ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.2,
	ITEM_DEFAULT_START_DELAY_S = 0.2,
	event_log = EventLog,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
})

Debug.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_charge_event_by_unit = _last_charge_event_by_unit,
})

EventLog.init({
	mod = mod,
	context_snapshot = Debug.context_snapshot,
})

ChargeTracker.init({
	fixed_time = _fixed_time,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	last_charge_event_by_unit = _last_charge_event_by_unit,
	fallback_state_by_unit = _fallback_state_by_unit,
	grenade_fallback = GrenadeFallback,
	settings = Settings,
	team_cooldown = TeamCooldown,
	combat_ability_identity = CombatAbilityIdentity,
	event_log = EventLog,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
})

GestaltInjector.init({
	default_ranged_gestalt = DEFAULT_RANGED_GESTALT,
	default_melee_gestalt = DEFAULT_MELEE_GESTALT,
	injected_units = _gestalt_injected_units,
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
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_snapshot_t_by_unit = _last_snapshot_t_by_unit,
	session_start_state = _session_start_state,
	snapshot_interval_s = _SNAPSHOT_INTERVAL_S,
	meta_patch_version = META_PATCH_VERSION,
	fixed_time = _fixed_time,
})

Perf.init({
	get_setting = function(setting_id)
		return mod:get(setting_id)
	end,
	setting_id = PERF_SETTING_ID,
})

Sprint.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	shared_rules = SharedRules,
	sprint_follow_distance = Settings.sprint_follow_distance,
	is_daemonhost_avoidance_enabled = function()
		return Settings.is_feature_enabled("daemonhost_avoidance")
	end,
})

MeleeMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	ARMOR_TYPE_ARMORED = ARMOR_TYPES and ARMOR_TYPES.armored,
	is_enabled = function()
		return Settings.is_feature_enabled("melee_improvements")
	end,
})

MeleeAttackChoice.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	ARMOR_TYPE_ARMORED = ARMOR_TYPES and ARMOR_TYPES.armored,
	is_enabled = function()
		return Settings.is_feature_enabled("melee_improvements")
	end,
	melee_horde_light_bias = Settings.melee_horde_light_bias,
})

RangedMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates_ranged,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	is_enabled = function()
		return Settings.is_feature_enabled("ranged_improvements")
	end,
})

TargetSelection.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
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
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	is_enabled = function()
		return Settings.is_feature_enabled("poxburster")
	end,
})

AnimationGuard.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
})

AirlockGuard.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
})

SmartTargeting.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_targeting = BotTargeting,
	is_enabled = function()
		return Settings.is_feature_enabled("smart_targeting")
	end,
})

VfxSuppression.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
})

WeaponAction.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	perf = Perf,
	close_range_ranged_policy = RangedMetaData.close_range_ranged_policy,
	is_enabled = function()
		return Settings.is_feature_enabled("ranged_improvements")
	end,
})

SustainedFire.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	is_enabled = function()
		return Settings.is_feature_enabled("ranged_improvements")
	end,
})

ConditionPatch.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	is_suppressed = _is_suppressed,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	patched_bt_bot_conditions = _patched_bt_bot_conditions,
	patched_bt_conditions = _patched_bt_conditions,
	rescue_intent = _rescue_intent,
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = DEBUG_SKIP_RELIC_LOG_INTERVAL_S,
	CONDITIONS_PATCH_VERSION = CONDITIONS_PATCH_VERSION,
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
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	equipped_combat_ability = _equipped_combat_ability,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	is_suppressed = _is_suppressed,
	fallback_state_by_unit = _fallback_state_by_unit,
	fallback_queue_dumped_by_key = _fallback_queue_dumped_by_key,
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = DEBUG_SKIP_RELIC_LOG_INTERVAL_S,
	perf = Perf,
	shared_rules = SharedRules,
})

ReviveAbility.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	is_suppressed = _is_suppressed,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	perf = Perf,
	shared_rules = SharedRules,
	combat_ability_identity = CombatAbilityIdentity,
})

GrenadeFallback.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	event_log = EventLog,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	is_suppressed = _is_suppressed,
	grenade_state_by_unit = _grenade_state_by_unit,
	last_grenade_charge_event_by_unit = _last_grenade_charge_event_by_unit,
	perf = Perf,
})

PingSystem.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
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
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	bot_targeting = BotTargeting,
	shared_rules = SharedRules,
	is_daemonhost_avoidance_enabled = function()
		return Settings.is_feature_enabled("daemonhost_avoidance")
	end,
})

HealingDeferral.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
})

AmmoPolicy.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
	settings = Settings,
	is_enabled = function()
		return Settings.is_feature_enabled("ammo_policy")
	end,
})

PocketablePickup.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	state_by_unit = _pocketable_state_by_unit,
	build_context = Heuristics.build_context,
	is_enabled = function()
		return Settings.is_feature_enabled("pocketable_support")
	end,
})

MulePickup.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
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

-- Wire cross-module references (late-bound to avoid circular deps)
ItemFallback.wire({
	build_context = Heuristics.build_context,
	context_snapshot = Debug.context_snapshot,
	fallback_state_snapshot = Debug.fallback_state_snapshot,
	evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
	is_item_ability_enabled = Settings.is_item_ability_enabled,
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

local function _patch_human_likeness_bot_settings(BotSettings)
	_bot_settings = BotSettings
	HumanLikeness.patch_bot_settings(BotSettings)
end

mod:hook_require("scripts/settings/bot/bot_settings", function(BotSettings)
	_patch_human_likeness_bot_settings(BotSettings)
end)

do
	local ok, BotSettings = pcall(require, "scripts/settings/bot/bot_settings")
	if ok and BotSettings then
		_patch_human_likeness_bot_settings(BotSettings)
	else
		mod:warning(
			"BetterBots: fallback require of bot_settings failed; human-likeness reaction-time patch may be skipped. "
				.. tostring(BotSettings)
		)
	end
end

ReviveAbility.wire({
	MetaData = MetaData,
	EventLog = EventLog,
	Debug = Debug,
	is_combat_template_enabled = Settings.is_combat_template_enabled,
})

GrenadeFallback.wire({
	build_context = Heuristics.build_context,
	normalize_grenade_context = Heuristics.normalize_grenade_context,
	evaluate_grenade_heuristic = Heuristics.evaluate_grenade_heuristic,
	equipped_grenade_ability = _equipped_grenade_ability,
	is_combat_ability_active = function(unit)
		return (ItemFallback.should_lock_weapon_switch(unit))
	end,
	is_grenade_enabled = Settings.is_grenade_enabled,
	bot_targeting = BotTargeting,
})

local function _should_lock_weapon_switch(unit)
	local should_lock, ability_name, lock_reason, slot_to_keep = ItemFallback.should_lock_weapon_switch(unit)
	if should_lock then
		return should_lock, ability_name, lock_reason, slot_to_keep
	end

	return GrenadeFallback.should_lock_weapon_switch(unit)
end

-- Block BT wield inputs for the full grenade sequence (including wait_unwield).
-- Separate from should_lock_weapon_switch so the wield_slot redirect can be
-- lifted in wait_unwield without also letting the BT switch weapons mid-throw.
local function _should_block_wield_input(unit)
	local should_lock, ability_name = ItemFallback.should_lock_weapon_switch(unit)
	if should_lock then
		return true, ability_name
	end

	return GrenadeFallback.should_block_wield_input(unit)
end

local function _should_block_weapon_action_input(unit, action_input)
	return GrenadeFallback.should_block_weapon_action_input(unit, action_input)
end

-- Register hooks for extracted modules
TargetSelection.register_hooks()
TargetTypeHysteresis.register_hooks()
Poxburster.register_hooks()
MeleeAttackChoice.register_hooks()
AnimationGuard.register_hooks()
AirlockGuard.register_hooks()
SmartTargeting.register_hooks()
VfxSuppression.register_hooks()
WeaponAction.register_hooks({
	should_lock_weapon_switch = _should_lock_weapon_switch,
	should_block_wield_input = _should_block_wield_input,
	should_block_weapon_action_input = _should_block_weapon_action_input,
	observe_queued_weapon_action = SustainedFire.observe_queued_weapon_action,
	install_weakspot_aim = WeakspotAim.install_on_shoot_action,
})
ConditionPatch.register_hooks()
HealingDeferral.register_hooks()
AmmoPolicy.register_hooks()
MulePickup.register_hooks()
BotProfiles.register_hooks()
EngagementLeash.register_hooks()
ReviveAbility.register_hooks()

-- Consolidated bot_perception_extension hook_require: two modules post-process
-- _update_target_enemy. DMF dedupes hook registrations by (mod, obj, method)
-- and silently discards duplicates, so both handlers dispatch from a single
-- hook here. One wrapper captures the pre-state (used by hysteresis) and then
-- calls both post-process functions (#90).
local PERCEPTION_DISPATCHER_SENTINEL = "__bb_perception_dispatcher_installed"
local function _install_bot_perception_extension_hooks(BotPerceptionExtension)
	if not BotPerceptionExtension or rawget(BotPerceptionExtension, PERCEPTION_DISPATCHER_SENTINEL) then
		return
	end
	local original = BotPerceptionExtension._update_target_enemy
	if type(original) ~= "function" then
		return
	end
	BotPerceptionExtension[PERCEPTION_DISPATCHER_SENTINEL] = true

	mod:hook(
		BotPerceptionExtension,
		"_update_target_enemy",
		function(
			func,
			self,
			self_unit,
			self_position,
			perception_component,
			behavior_component,
			enemies_in_proximity,
			side,
			bot_group,
			dt,
			t
		)
			local pre_state = {
				target_enemy = perception_component.target_enemy,
				target_enemy_type = perception_component.target_enemy_type,
				target_enemy_reevaluation_t = perception_component.target_enemy_reevaluation_t,
			}
			func(
				self,
				self_unit,
				self_position,
				perception_component,
				behavior_component,
				enemies_in_proximity,
				side,
				bot_group,
				dt,
				t
			)
			local h_ok, h_err = pcall(
				TargetTypeHysteresis.post_update_target_enemy,
				self,
				pre_state,
				self_unit,
				self_position,
				perception_component,
				behavior_component,
				enemies_in_proximity,
				side,
				bot_group,
				dt,
				t
			)
			if not h_ok then
				mod:echo("BetterBots: target_type_hysteresis dispatch failed: " .. tostring(h_err))
			end
			local p_ok, p_err =
				pcall(Poxburster.post_update_target_enemy, self, self_unit, self_position, perception_component, side)
			if not p_ok then
				mod:echo("BetterBots: poxburster dispatch failed: " .. tostring(p_err))
			end
		end
	)

	if _debug_enabled() then
		_debug_log(
			"hook_require:bot_perception_extension",
			0,
			"installed consolidated _update_target_enemy hook (target_type_hysteresis + poxburster)",
			nil,
			"info"
		)
	end
end

mod:hook_require(
	"scripts/extension_systems/perception/bot_perception_extension",
	_install_bot_perception_extension_hooks
)

do
	local ok, BotPerceptionExtension = pcall(require, "scripts/extension_systems/perception/bot_perception_extension")
	if ok and BotPerceptionExtension then
		_install_bot_perception_extension_hooks(BotPerceptionExtension)
	end
end

-- Consolidated bt_bot_melee_action hook_require: three modules hook this path.
-- DMF hook_require is keyed by (path, mod_name) — multiple calls from the same mod
-- on the same path silently clobber each other (#67). Single callback installs all hooks.
mod:hook_require("scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action", function(BtBotMeleeAction)
	local ok, err
	ok, err = pcall(MeleeAttackChoice.install_melee_hooks, BtBotMeleeAction)
	if not ok then
		mod:echo("BetterBots: melee_attack_choice hook install failed: " .. tostring(err))
	end
	ok, err = pcall(Poxburster.install_melee_hooks, BtBotMeleeAction)
	if not ok then
		mod:echo("BetterBots: poxburster melee hook install failed: " .. tostring(err))
	end
	ok, err = pcall(EngagementLeash.install_melee_hooks, BtBotMeleeAction)
	if not ok then
		mod:echo("BetterBots: engagement_leash hook install failed: " .. tostring(err))
	end
	if _debug_enabled() then
		_debug_log(
			"hook_require:bt_bot_melee_action",
			0,
			"installed consolidated bt_bot_melee_action hooks (melee_attack_choice, poxburster, engagement_leash)",
			nil,
			"info"
		)
	end
end)

-- Hooks that remain in main: template injection, sprint, BT enter,
-- charge consume, state change retry, ADS gestalt, update tick.

mod:hook_require("scripts/settings/ability/ability_templates/ability_templates", function(AbilityTemplates)
	MetaData.inject(AbilityTemplates)
end)

mod:hook_require("scripts/settings/equipment/weapon_templates/weapon_templates", function(WeaponTemplates)
	MeleeMetaData.inject(WeaponTemplates)
	RangedMetaData.inject(WeaponTemplates)
	GrenadeFallback.prime_weapon_templates(WeaponTemplates)
end)

-- DMF hook_require is keyed by (path, mod_name) — multiple callbacks from the
-- same mod on the same path silently clobber each other. Install all
-- BotUnitInput hooks through one callback so sprint and sustained-fire coexist.
mod:hook_require("scripts/extension_systems/input/bot_unit_input", function(BotUnitInput)
	SustainedFire.install_bot_unit_input_hooks(BotUnitInput)
	Sprint.install_bot_unit_input_hooks(BotUnitInput)
end)

-- DMF hook_require is keyed by (path, mod_name) — multiple callbacks from the
-- same mod on the same path silently clobber each other. Install all BotGroup
-- hooks through one callback so healing deferral and mule pickup both survive.
mod:hook_require("scripts/extension_systems/group/bot_group", function(BotGroup)
	HealingDeferral.install_bot_group_hooks(BotGroup)
	MulePickup.install_bot_group_hooks(BotGroup)
end)

-- BT activate ability enter hook: category gate (#6), rescue aim (#10), event logging
mod:hook_require(
	"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action",
	function(BtBotActivateAbilityAction)
		mod:hook(
			BtBotActivateAbilityAction,
			"enter",
			function(func, self, unit, breed, blackboard, scratchpad, action_data, t)
				-- Rescue aim (#10): aim the bot toward the disabled ally before
				-- the original enter() reads first_person_component.rotation for
				-- the lunge direction.
				local ally_unit = _rescue_intent[unit]
				local rescue_ally_position
				if ally_unit then
					_rescue_intent[unit] = nil
					local ally_pos = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
					if ally_pos then
						rescue_ally_position = ally_pos
					end
				end

				-- Category gate: block abilities disabled by settings (#6).
				-- The generated BT selector (bt_bot_selector_node.lua, vanilla engine file)
				-- inlines condition logic, bypassing our condition_patch gate. This enter
				-- hook is the last check before the ability action starts.
				-- NOTE: skipping func() means the BT node's enter() never initializes
				-- scratchpad. If the BT framework still calls run() after a no-op enter(),
				-- uninitialised scratchpad fields could cause nil-access errors. Verified
				-- safe in v0.8.0 testing — the BT selector re-evaluates conditions each
				-- frame, so a blocked node is not re-entered. If future Fatshark BT
				-- changes break this assumption, add a scratchpad sentinel here.
				local gate_comp_name = action_data and action_data.ability_component_name
				if gate_comp_name then
					local gate_unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
					local gate_comp = gate_unit_data and gate_unit_data:read_component(gate_comp_name)
					local gate_template = gate_comp and gate_comp.template_name
					if gate_template and gate_template ~= "none" then
						local is_grenade = string.find(gate_comp_name, "grenade", 1, true) ~= nil
						local enabled = is_grenade and Settings.is_grenade_enabled(gate_template)
							or not is_grenade
								and Settings.is_combat_template_enabled(
									gate_template,
									ScriptUnit.has_extension(unit, "ability_system")
								)
						if not enabled then
							_debug_log(
								"bt_enter_blocked:" .. gate_template .. ":" .. tostring(unit),
								_fixed_time(),
								"BT enter blocked " .. gate_template .. " (disabled by mod setting)",
								nil,
								"info"
							)
							return
						end
					end
					if gate_template and ChargeNavValidation.should_validate(gate_template) then
						local nav_ok, nav_reason = ChargeNavValidation.validate(unit, gate_template, "bt_enter", {
							blackboard = blackboard,
							target_position = rescue_ally_position,
						})
						if not nav_ok then
							if EventLog.is_enabled() then
								EventLog.emit({
									t = _fixed_time(),
									event = "blocked",
									bot = Debug.bot_slot_for_unit(unit),
									ability = _equipped_combat_ability_name(unit),
									template = gate_template,
									source = "bt_enter",
									reason = nav_reason,
								})
							end
							return
						end
					end
				end

				if rescue_ally_position then
					local input_ext = ScriptUnit.has_extension(unit, "input_system")
					local bot_input = input_ext and input_ext.bot_unit_input and input_ext:bot_unit_input()
					if bot_input then
						bot_input:set_aiming(true)
						bot_input:set_aim_position(rescue_ally_position)
						_debug_log(
							"rescue_aim:" .. tostring(unit),
							_fixed_time(),
							"rescue aim: directed charge toward disabled ally"
						)
					end
				end

				func(self, unit, breed, blackboard, scratchpad, action_data, t)

				-- Engagement leash (#47): record movement ability for post-charge grace
				if unit then
					local el_unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
					local el_comp = el_unit_data
						and action_data
						and action_data.ability_component_name
						and el_unit_data:read_component(action_data.ability_component_name)
					local el_template = el_comp and el_comp.template_name
					if el_template and EngagementLeash.is_movement_ability(el_template) then
						EngagementLeash.record_charge(unit, _fixed_time())
					end
				end

				local ability_component_name = action_data and action_data.ability_component_name or "?"
				local activation_data = scratchpad and scratchpad.activation_data
				local action_input = activation_data and activation_data.action_input or "?"
				local fixed_t = _fixed_time()

				if _debug_enabled() then
					_debug_log(
						"enter:"
							.. tostring(ability_component_name)
							.. ":"
							.. tostring(action_input)
							.. ":"
							.. tostring(unit),
						fixed_t,
						"enter ability node component="
							.. tostring(ability_component_name)
							.. " action_input="
							.. tostring(action_input)
					)
				end

				if EventLog.is_enabled() and unit then
					local state = _fallback_state_by_unit[unit]
					if not state then
						state = {}
						_fallback_state_by_unit[unit] = state
					end
					local attempt_id = EventLog.next_attempt_id()
					state.attempt_id = attempt_id
					local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
					local ability_comp = unit_data_ext and unit_data_ext:read_component(ability_component_name)
					local template_name = ability_comp and ability_comp.template_name or "?"
					EventLog.emit({
						t = fixed_t,
						event = "queued",
						bot = Debug.bot_slot_for_unit(unit),
						ability = _equipped_combat_ability_name(unit),
						template = template_name,
						input = action_input,
						source = "bt",
						attempt_id = attempt_id,
					})
				end
			end
		)
	end
)

-- Charge consume tracking + VFX suppression (#42). Consolidated: both modules hook this path (#67).
mod:hook_require("scripts/extension_systems/ability/player_unit_ability_extension", function(PlayerUnitAbilityExtension)
	local ok, err = pcall(VfxSuppression.install_ability_ext_hooks, PlayerUnitAbilityExtension)
	if not ok then
		mod:echo("BetterBots: vfx_suppression ability hook install failed: " .. tostring(err))
	end
	mod:hook_safe(PlayerUnitAbilityExtension, "use_ability_charge", function(self, ability_type, optional_num_charges)
		ChargeTracker.handle(self, ability_type, optional_num_charges)
	end)
end)

-- State change retry: schedule fast retry when ability state transition fails
mod:hook_require(
	"scripts/extension_systems/ability/actions/action_character_state_change",
	function(ActionCharacterStateChange)
		mod:hook(ActionCharacterStateChange, "finish", function(func, self, reason, data, t, time_in_action)
			return ItemFallback.on_state_change_finish(func, self, reason, data, t, time_in_action)
		end)
	end
)

-- BotBehaviorExtension: ADS gestalt injection (#35) + healing deferral (#39)
-- + revive-candidate diagnostics (#7) + main update tick.
-- Consolidated: multiple modules hook this path (#67).
local BEHAVIOR_DISPATCHER_SENTINEL = "__bb_behavior_dispatcher_installed"
mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
	if not BotBehaviorExtension or rawget(BotBehaviorExtension, BEHAVIOR_DISPATCHER_SENTINEL) then
		return
	end
	BotBehaviorExtension[BEHAVIOR_DISPATCHER_SENTINEL] = true
	local ok, err
	ok, err = pcall(HealingDeferral.install_behavior_ext_hooks, BotBehaviorExtension)
	if not ok then
		mod:echo("BetterBots: healing_deferral behavior hook install failed: " .. tostring(err))
	end
	ok, err = pcall(AmmoPolicy.install_behavior_ext_hooks, BotBehaviorExtension)
	if not ok then
		mod:echo("BetterBots: ammo_policy behavior hook install failed: " .. tostring(err))
	end
	-- Consolidated _refresh_destination hook. DMF dedupes hook registrations by
	-- (mod, obj, method) and silently discards duplicates, so each feature's
	-- handler is dispatched from a single hook_safe here.
	mod:hook_safe(
		BotBehaviorExtension,
		"_refresh_destination",
		function(
			self,
			t,
			self_position,
			previous_destination,
			hold_position,
			hold_position_max_distance_sq,
			bot_group_data,
			navigation_extension,
			follow_component,
			perception_component
		)
			local m_ok, m_err = pcall(MulePickup.on_refresh_destination, self)
			if not m_ok then
				mod:echo("BetterBots: mule_pickup _refresh_destination dispatch failed: " .. tostring(m_err))
			end
			local r_ok, r_err = pcall(
				ReviveAbility.on_refresh_destination,
				self,
				t,
				self_position,
				previous_destination,
				hold_position,
				hold_position_max_distance_sq,
				bot_group_data,
				navigation_extension,
				follow_component,
				perception_component
			)
			if not r_ok then
				mod:echo("BetterBots: revive_ability _refresh_destination dispatch failed: " .. tostring(r_err))
			end
		end
	)
	mod:hook(
		BotBehaviorExtension,
		"_init_blackboard_components",
		function(func, self, blackboard, physics_world, gestalts_or_nil)
			local unit = self._unit
			local had_ranged = gestalts_or_nil and gestalts_or_nil.ranged ~= nil
			local injected
			gestalts_or_nil, injected = GestaltInjector.inject(gestalts_or_nil, unit)
			if injected then
				_debug_log(
					"gestalt_inject:" .. tostring(unit),
					0,
					"injected default bot_gestalts (ranged=killshot, melee=linesman)",
					nil,
					"info"
				)
			elseif had_ranged then
				_debug_log(
					"gestalt_skip:" .. tostring(unit),
					0,
					"bot already has gestalts (ranged=" .. tostring(gestalts_or_nil.ranged) .. ")"
				)
			end
			return func(self, blackboard, physics_world, gestalts_or_nil)
		end
	)

	mod:hook_safe(BotBehaviorExtension, "update", function(self, unit)
		UpdateDispatcher.dispatch(self, unit)
	end)
end)

mod:command("bb_perf", "Show and clear BetterBots timing stats for the current session", function()
	Perf.sync_setting()

	local report = Perf.report_and_reset()
	if not report then
		if Perf.is_enabled() then
			mod:echo("bb-perf: no samples yet")
		else
			mod:echo("bb-perf: no samples — enable 'per-frame timing' in mod settings")
		end
		return
	end

	local lines = Perf.format_report_lines(report, "bb-perf:")
	for i = 1, #lines do
		mod:echo(lines[i])
	end
end)

local function _auto_dump_perf_report()
	local report = Perf.report_and_reset()
	if not report or report.bot_frames <= 0 then
		return
	end

	local lines = Perf.format_report_lines(report, "bb-perf:auto:")
	for i = 1, #lines do
		mod:echo(lines[i])
	end
end

mod:command("bb_reset", "Reset all BetterBots settings to their default values", function()
	local failures = {}
	for setting_id, default_value in pairs(Settings.DEFAULTS) do
		local ok, err = pcall(function()
			mod:set(setting_id, default_value, true)
		end)
		if not ok then
			local entry = setting_id
			if err ~= nil then
				entry = entry .. " (" .. tostring(err) .. ")"
			end
			failures[#failures + 1] = entry
		end
	end

	-- Always attempt to persist, even on partial failure — keeping the successful
	-- resets on disk is better than losing them alongside the failed ones.
	local dmf_module = rawget(_G, "dmf")
	if type(dmf_module) == "table" and type(dmf_module.save_unsaved_settings_to_file) == "function" then
		pcall(function()
			dmf_module.save_unsaved_settings_to_file()
		end)
	end

	if #failures == 0 then
		mod:echo("BetterBots: all settings reset to defaults")
	else
		mod:echo("BetterBots: reset partially failed: " .. table.concat(failures, ", "))
	end
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		_refresh_debug_log_level()
		Perf.enter_run()
		BotProfiles.reset()
		TeamCooldown.reset()
		for key in pairs(_fallback_queue_dumped_by_key) do
			_fallback_queue_dumped_by_key[key] = nil
		end
		for unit in pairs(_decision_context_cache_by_unit) do
			_decision_context_cache_by_unit[unit] = nil
		end
		for unit in pairs(_resolve_decision_cache_by_unit) do
			_resolve_decision_cache_by_unit[unit] = nil
		end
		for unit in pairs(_resolve_decision_cache_hits_logged_by_unit) do
			_resolve_decision_cache_hits_logged_by_unit[unit] = nil
		end
		for unit in pairs(_suppression_cache_by_unit) do
			_suppression_cache_by_unit[unit] = nil
		end
		for unit in pairs(_grenade_state_by_unit) do
			_grenade_state_by_unit[unit] = nil
		end
		_debug_log("state:GameplayStateRun", _fixed_time(), "entered GameplayStateRun")
		EventLog.set_enabled(mod:get(EVENT_LOG_SETTING_ID) == true)
		EventLog.start_session(_fixed_time())
		_session_start_state.emitted = false
		for unit in pairs(_last_snapshot_t_by_unit) do
			_last_snapshot_t_by_unit[unit] = nil
		end
	end

	if status == "exit" and state == "GameplayStateRun" then
		_auto_dump_perf_report()
		EventLog.end_session()
	end
end

function mod.on_setting_changed(setting_id)
	if setting_id == DEBUG_SETTING_ID then
		_refresh_debug_log_level()
	end

	if TIMING_SETTING_IDS[setting_id] then
		HumanLikeness.patch_bot_settings(_bot_settings)
	end

	if setting_id == "enable_bot_grimoire_pickup" then
		MulePickup.patch_pickups()
		MulePickup.sync_live_bot_groups()
	end

	if setting_id == "enable_pocketable_support" then
		PocketablePickup.patch_pickups()
		MulePickup.sync_live_bot_groups()
	end

	if setting_id == "enable_melee_improvements" then
		MeleeMetaData.sync_all()
	end

	if setting_id == "enable_ranged_improvements" then
		RangedMetaData.sync_all()
	end

	if setting_id == "enable_team_cooldown" then
		TeamCooldown.reset()
	end
end

Debug.register_commands()
_refresh_debug_log_level()

-- Re-enable EventLog after hot-reload if we're mid-session.
if mod:get(EVENT_LOG_SETTING_ID) == true then
	local bots = Debug.collect_alive_bots()
	if bots and #bots > 0 then
		EventLog.set_enabled(true)
		EventLog.start_session(_fixed_time())
		_session_start_state.emitted = false
	end
end

mod:echo("BetterBots loaded")
_debug_log("startup:logging", 0, "logging enabled (level=" .. LogLevels.level_name(_log_level) .. ")", nil, "debug")

-- Emit a concise startup summary of the highest-signal behavior settings.
-- This is intentionally not a full config dump; keep it small and update
-- docs/dev/logging.md when changing the included fields.
if _debug_enabled() then
	local parts = {
		"preset=" .. Settings.resolve_preset(),
		"sprint_dist=" .. Settings.sprint_follow_distance(),
		"chase_range=" .. Settings.special_chase_penalty_range(),
		"tag_bonus=" .. Settings.player_tag_bonus(),
		"horde_bias=" .. Settings.melee_horde_light_bias(),
		"smart_targeting=" .. tostring(Settings.is_feature_enabled("smart_targeting")),
		"dh_avoidance=" .. tostring(Settings.is_feature_enabled("daemonhost_avoidance")),
	}
	_debug_log("startup:settings", 0, "settings: " .. table.concat(parts, ", "), nil, "info")
end
