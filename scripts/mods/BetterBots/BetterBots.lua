local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local LogLevels = mod:io_dofile("BetterBots/scripts/mods/BetterBots/log_levels")
local SharedRules = mod:io_dofile("BetterBots/scripts/mods/BetterBots/shared_rules")
local BotTargeting = mod:io_dofile("BetterBots/scripts/mods/BetterBots/bot_targeting")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local EVENT_LOG_SETTING_ID = "enable_event_log"
local ABILITY_STATE_FAIL_RETRY_S = 0.35
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
local _fallback_queue_dumped_by_key = {}
local _decision_context_cache_by_unit = setmetatable({}, { __mode = "k" })
local _session_start_emitted = false
local _SNAPSHOT_INTERVAL_S = 30
local _last_snapshot_t_by_unit = setmetatable({}, { __mode = "k" })
local _super_armor_breed_flag_by_name = {}
local _log_level = 0
local PERF_SETTING_ID = "enable_perf_timing"

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
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local movement = unit_data_extension:read_component("movement_state")
	if movement then
		if movement.is_dodging then
			return true, "dodging"
		end
		if movement.method == "falling" then
			return true, "falling"
		end
	end

	local lunge = unit_data_extension:read_component("lunge_character_state")
	if lunge and (lunge.is_lunging or lunge.is_aiming) then
		return true, "lunging"
	end

	local character_state = unit_data_extension:read_component("character_state")
	if character_state and _SUPPRESSED_STATES[character_state.state_name] then
		return true, character_state.state_name
	end

	local locomotion = unit_data_extension:read_component("locomotion")
	if locomotion and locomotion.parent_unit ~= nil then
		return true, "moving_platform"
	end

	-- #17: daemonhost combat suppression is handled target-specifically in
	-- condition_patch.lua (melee/ranged suppression when targeting a dormant DH).
	-- Blanket proximity suppression was removed — it blocked abilities in mixed
	-- encounters where bots fight other enemies near a sleeping daemonhost.

	return false
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

local Settings = mod:io_dofile("BetterBots/scripts/mods/BetterBots/settings")
assert(Settings, "BetterBots: failed to load settings module")

local Heuristics = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics")
assert(Heuristics, "BetterBots: failed to load heuristics module")

local ItemFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/item_fallback")
assert(ItemFallback, "BetterBots: failed to load item_fallback module")

local Debug = mod:io_dofile("BetterBots/scripts/mods/BetterBots/debug")
assert(Debug, "BetterBots: failed to load debug module")

local EventLog = mod:io_dofile("BetterBots/scripts/mods/BetterBots/event_log")
assert(EventLog, "BetterBots: failed to load event_log module")

local Perf = mod:io_dofile("BetterBots/scripts/mods/BetterBots/perf")
assert(Perf, "BetterBots: failed to load perf module")

local Sprint = mod:io_dofile("BetterBots/scripts/mods/BetterBots/sprint")
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

local ConditionPatch = mod:io_dofile("BetterBots/scripts/mods/BetterBots/condition_patch")
assert(ConditionPatch, "BetterBots: failed to load condition_patch module")

local AbilityQueue = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ability_queue")
assert(AbilityQueue, "BetterBots: failed to load ability_queue module")

local GrenadeFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/grenade_fallback")
assert(GrenadeFallback, "BetterBots: failed to load grenade_fallback module")

local PingSystem = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ping_system")
assert(PingSystem, "BetterBots: failed to load ping_system module")

local HealingDeferral = mod:io_dofile("BetterBots/scripts/mods/BetterBots/healing_deferral")
assert(HealingDeferral, "BetterBots: failed to load healing_deferral module")

local AmmoPolicy = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ammo_policy")
assert(AmmoPolicy, "BetterBots: failed to load ammo_policy module")

local BotProfiles = mod:io_dofile("BetterBots/scripts/mods/BetterBots/bot_profiles")
assert(BotProfiles, "BetterBots: failed to load bot_profiles module")

local EngagementLeash = mod:io_dofile("BetterBots/scripts/mods/BetterBots/engagement_leash")
assert(EngagementLeash, "BetterBots: failed to load engagement_leash module")

-- Init each module with its dependencies
Settings.init({
	mod = mod,
})

BotProfiles.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
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
	super_armor_breed_cache = _super_armor_breed_flag_by_name,
	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
	is_testing_profile = Settings.is_testing_profile,
	resolve_preset = Settings.resolve_preset,
})

ItemFallback.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
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
	is_enabled = function()
		return Settings.is_feature_enabled("sprint")
	end,
})

MeleeMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	ARMOR_TYPE_ARMORED = ARMOR_TYPES and ARMOR_TYPES.armored,
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
})

RangedMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates_ranged,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
})

TargetSelection.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	is_enabled = function()
		return Settings.is_feature_enabled("special_penalty")
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
	shared_rules = SharedRules,
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
})

PingSystem.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
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
	settings = Settings,
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
})

AbilityQueue.wire({
	Heuristics = Heuristics,
	MetaData = MetaData,
	ItemFallback = ItemFallback,
	Debug = Debug,
	EventLog = EventLog,
	EngagementLeash = EngagementLeash,
	is_combat_template_enabled = Settings.is_combat_template_enabled,
})

GrenadeFallback.wire({
	build_context = Heuristics.build_context,
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
})
ConditionPatch.register_hooks()
HealingDeferral.register_hooks()
BotProfiles.register_hooks()
EngagementLeash.register_hooks()

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
end)

Sprint.register_hook()

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
				if ally_unit then
					_rescue_intent[unit] = nil
					local ally_pos = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
					if ally_pos then
						local input_ext = ScriptUnit.has_extension(unit, "input_system")
						local bot_input = input_ext and input_ext.bot_unit_input and input_ext:bot_unit_input()
						if bot_input then
							bot_input:set_aiming(true)
							bot_input:set_aim_position(ally_pos)
							_debug_log(
								"rescue_aim:" .. tostring(unit),
								_fixed_time(),
								"rescue aim: directed charge toward disabled ally"
							)
						end
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
		if ability_type ~= "combat_ability" and ability_type ~= "grenade_ability" then
			return
		end

		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		if ability_type == "grenade_ability" then
			local grenade_name = "unknown"
			local equipped_abilities = self._equipped_abilities
			local grenade_ability = equipped_abilities and equipped_abilities.grenade_ability
			if grenade_ability and grenade_ability.name then
				grenade_name = grenade_ability.name
			end

			local unit = self._unit
			if unit then
				GrenadeFallback.record_charge_event(unit, grenade_name, _fixed_time())
			end

			if _debug_enabled() then
				_debug_log(
					"grenade_charge:" .. grenade_name .. ":" .. tostring(unit),
					_fixed_time(),
					"grenade charge consumed for "
						.. grenade_name
						.. " (charges="
						.. tostring(optional_num_charges or 1)
						.. ")"
				)
			end
			return
		end

		local ability_name = "unknown"
		local equipped_abilities = self._equipped_abilities
		local combat_ability = equipped_abilities and equipped_abilities.combat_ability
		if combat_ability and combat_ability.name then
			ability_name = combat_ability.name
		end

		local fixed_t = _fixed_time()
		local unit = self._unit
		if unit then
			_last_charge_event_by_unit[unit] = {
				ability_name = ability_name,
				fixed_t = fixed_t,
			}

			if EventLog.is_enabled() then
				local bot_slot = Debug.bot_slot_for_unit(unit)
				local fb_state = _fallback_state_by_unit[unit]
				EventLog.emit({
					t = fixed_t,
					event = "consumed",
					bot = bot_slot,
					ability = ability_name,
					charges = optional_num_charges or 1,
					rule = fb_state and fb_state.item_rule or nil,
					attempt_id = fb_state and fb_state.attempt_id or nil,
				})
			end
		end

		if not _debug_enabled() then
			return
		end

		_debug_log(
			"charge:" .. ability_name,
			fixed_t,
			"charge consumed for " .. ability_name .. " (charges=" .. tostring(optional_num_charges or 1) .. ")"
		)
	end)
end)

-- State change retry: schedule fast retry when ability state transition fails
mod:hook_require(
	"scripts/extension_systems/ability/actions/action_character_state_change",
	function(ActionCharacterStateChange)
		mod:hook(ActionCharacterStateChange, "finish", function(func, self, reason, data, t, time_in_action)
			local action_settings = self._action_settings
			local ability_type = action_settings and action_settings.ability_type
			local use_ability_charge = action_settings and action_settings.use_ability_charge
			local player = self._player
			local unit = self._player_unit
			local wanted_state_name = self._wanted_state_name
			local character_state_component = self._character_sate_component
			local current_state_name = character_state_component and character_state_component.state_name or nil
			local failed_state_transition = wanted_state_name ~= nil and current_state_name ~= wanted_state_name
			local is_bot = player and not player:is_human_controlled()

			func(self, reason, data, t, time_in_action)

			if
				not is_bot
				or not unit
				or ability_type ~= "combat_ability"
				or not use_ability_charge
				or not failed_state_transition
			then
				return
			end

			local fixed_t = _fixed_time()
			local ability_name = _equipped_combat_ability_name(unit)
			ItemFallback.schedule_retry(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
			if _debug_enabled() then
				_debug_log(
					"state_fail_retry:" .. tostring(ability_name) .. ":" .. tostring(reason),
					fixed_t,
					"combat ability state transition failed for "
						.. tostring(ability_name)
						.. " (wanted="
						.. tostring(wanted_state_name)
						.. ", current="
						.. tostring(current_state_name)
						.. ", reason="
						.. tostring(reason)
						.. "); scheduled fast retry"
				)
			end
		end)
	end
)

-- BotBehaviorExtension: ADS gestalt injection (#35) + healing deferral (#39) + main update tick.
-- Consolidated: both modules hook this path (#67).
mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
	local ok, err
	ok, err = pcall(HealingDeferral.install_behavior_ext_hooks, BotBehaviorExtension)
	if not ok then
		mod:echo("BetterBots: healing_deferral behavior hook install failed: " .. tostring(err))
	end
	ok, err = pcall(AmmoPolicy.install_behavior_ext_hooks, BotBehaviorExtension)
	if not ok then
		mod:echo("BetterBots: ammo_policy behavior hook install failed: " .. tostring(err))
	end
	mod:hook(
		BotBehaviorExtension,
		"_init_blackboard_components",
		function(func, self, blackboard, physics_world, gestalts_or_nil)
			local unit = self._unit
			if not gestalts_or_nil or not gestalts_or_nil.ranged then
				gestalts_or_nil = gestalts_or_nil or {}
				gestalts_or_nil.ranged = gestalts_or_nil.ranged or DEFAULT_RANGED_GESTALT
				gestalts_or_nil.melee = gestalts_or_nil.melee or DEFAULT_MELEE_GESTALT
				if unit and not _gestalt_injected_units[unit] then
					_gestalt_injected_units[unit] = true
					_debug_log(
						"gestalt_inject:" .. tostring(unit),
						0,
						"injected default bot_gestalts (ranged=killshot, melee=linesman)",
						nil,
						"info"
					)
				end
			else
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
		local player = self._player
		if not player or player:is_human_controlled() then
			return
		end

		Perf.sync_setting()
		Perf.mark_bot_frame()

		local brain = self._brain
		local blackboard = brain and brain._blackboard or nil

		if EventLog.is_enabled() and not _session_start_emitted then
			local perf_t0 = Perf.begin()
			local bots = Debug.collect_alive_bots()
			if bots and #bots > 0 then
				_session_start_emitted = true
				local bot_info = {}
				for i, bot_entry in ipairs(bots) do
					local p = bot_entry.player
					bot_info[i] = {
						slot = type(p.slot) == "function" and p:slot() or nil,
						archetype = type(p.archetype_name) == "function" and p:archetype_name() or nil,
						ability = _equipped_combat_ability_name(bot_entry.unit),
					}
				end
				EventLog.emit({
					t = _fixed_time(),
					event = "session_start",
					version = META_PATCH_VERSION,
					bots = bot_info,
				})
			end
			Perf.finish("event_log_session_start", perf_t0)
		end

		local perf_t0 = Perf.begin()
		AbilityQueue.try_queue(unit, blackboard)
		Perf.finish("ability_queue", perf_t0)
		perf_t0 = Perf.begin()
		GrenadeFallback.try_queue(unit, blackboard)
		Perf.finish("grenade_fallback", perf_t0)
		if Settings.is_feature_enabled("pinging") then
			perf_t0 = Perf.begin()
			PingSystem.update(unit, blackboard)
			Perf.finish("ping_system", perf_t0)
		end
		perf_t0 = Perf.begin()
		EventLog.try_flush(_fixed_time())
		Perf.finish("event_log_flush", perf_t0)

		if EventLog.is_enabled() then
			local fixed_t = _fixed_time()
			local last_snap = _last_snapshot_t_by_unit[unit]
			if not last_snap or fixed_t - last_snap >= _SNAPSHOT_INTERVAL_S then
				local snapshot_t0 = Perf.begin()
				_last_snapshot_t_by_unit[unit] = fixed_t
				local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
				local bot_slot = Debug.bot_slot_for_unit(unit)
				local fb_state = _fallback_state_by_unit[unit]
				EventLog.emit({
					t = fixed_t,
					event = "snapshot",
					bot = bot_slot,
					ability = _equipped_combat_ability_name(unit),
					cooldown_ready = ability_extension and ability_extension:can_use_ability("combat_ability") or false,
					charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability")
						or nil,
					ctx = Debug.context_snapshot(Heuristics.build_context(unit, blackboard)),
					item_stage = fb_state and fb_state.item_stage or nil,
				})
				Perf.finish("event_log_snapshot", snapshot_t0)
			end
		end
	end)
end)

mod:command("bb_perf", "Print BetterBots runtime timing stats from the current recording window", function()
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

	mod:echo(
		string.format(
			"bb-perf: %.1f µs/bot/frame total (%d bot frames, %d calls, %.3f ms total)",
			report.total_us_per_bot_frame or 0,
			report.bot_frames,
			report.total_calls,
			report.total_us / 1000
		)
	)

	local rows = {}
	for tag, stats in pairs(report.tags) do
		rows[#rows + 1] = {
			tag = tag,
			total_us = stats.total_us,
			calls = stats.calls,
			avg_us_per_call = stats.avg_us_per_call,
		}
	end

	table.sort(rows, function(a, b)
		return a.total_us > b.total_us
	end)

	for i = 1, #rows do
		local row = rows[i]
		mod:echo(
			string.format(
				"bb-perf: %s %.3f ms total (%d calls, %.1f µs/call)",
				row.tag,
				row.total_us / 1000,
				row.calls,
				row.avg_us_per_call
			)
		)
	end
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		_refresh_debug_log_level()
		Perf.enter_run()
		BotProfiles.reset()
		for key in pairs(_fallback_queue_dumped_by_key) do
			_fallback_queue_dumped_by_key[key] = nil
		end
		for unit in pairs(_decision_context_cache_by_unit) do
			_decision_context_cache_by_unit[unit] = nil
		end
		for unit in pairs(_grenade_state_by_unit) do
			_grenade_state_by_unit[unit] = nil
		end
		_debug_log("state:GameplayStateRun", _fixed_time(), "entered GameplayStateRun")
		EventLog.set_enabled(mod:get(EVENT_LOG_SETTING_ID) == true)
		EventLog.start_session(_fixed_time())
		_session_start_emitted = false
		for unit in pairs(_last_snapshot_t_by_unit) do
			_last_snapshot_t_by_unit[unit] = nil
		end
	end

	if status == "exit" and state == "GameplayStateRun" then
		EventLog.end_session()
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
		_session_start_emitted = false
	end
end

-- All modules are assert-guarded above; if any failed to load we'd have
-- crashed already.  The count serves as a deployment sanity check in logs.
-- Bump when adding/removing modules.
local _MODULE_COUNT = 26
mod:echo("BetterBots loaded (" .. _MODULE_COUNT .. " modules)")
_debug_log("startup:logging", 0, "logging enabled (level=" .. LogLevels.level_name(_log_level) .. ")", nil, "debug")
