local mod = get_mod("BetterBots")
local FixedFrame = require("scripts/utilities/fixed_frame")
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local DEBUG_SETTING_ID = "enable_debug_logs"
local DEBUG_LOG_INTERVAL_S = 2
local DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20
local DEBUG_FORCE_ENABLED = false
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
local _fallback_queue_dumped_by_key = {}
local _decision_context_cache_by_unit = setmetatable({}, { __mode = "k" })
local _session_start_emitted = false
local _SNAPSHOT_INTERVAL_S = 30
local _last_snapshot_t_by_unit = setmetatable({}, { __mode = "k" })
local _super_armor_breed_flag_by_name = {}

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

local function _debug_enabled()
	if DEBUG_FORCE_ENABLED then
		return true
	end

	return mod:get(DEBUG_SETTING_ID) == true
end

local function _debug_log(key, fixed_t, message, min_interval_s)
	if not _debug_enabled() then
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

-- Sub-modules
local MetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/meta_data")
assert(MetaData, "BetterBots: failed to load meta_data module")

local Heuristics = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics")
assert(Heuristics, "BetterBots: failed to load heuristics module")

local ItemFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/item_fallback")
assert(ItemFallback, "BetterBots: failed to load item_fallback module")

local Debug = mod:io_dofile("BetterBots/scripts/mods/BetterBots/debug")
assert(Debug, "BetterBots: failed to load debug module")

local EventLog = mod:io_dofile("BetterBots/scripts/mods/BetterBots/event_log")
assert(EventLog, "BetterBots: failed to load event_log module")

local Sprint = mod:io_dofile("BetterBots/scripts/mods/BetterBots/sprint")
assert(Sprint, "BetterBots: failed to load sprint module")

local MeleeMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/melee_meta_data")
assert(MeleeMetaData, "BetterBots: failed to load melee_meta_data module")

local RangedMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ranged_meta_data")
assert(RangedMetaData, "BetterBots: failed to load ranged_meta_data module")

local Poxburster = mod:io_dofile("BetterBots/scripts/mods/BetterBots/poxburster")
assert(Poxburster, "BetterBots: failed to load poxburster module")

local VfxSuppression = mod:io_dofile("BetterBots/scripts/mods/BetterBots/vfx_suppression")
assert(VfxSuppression, "BetterBots: failed to load vfx_suppression module")

local WeaponAction = mod:io_dofile("BetterBots/scripts/mods/BetterBots/weapon_action")
assert(WeaponAction, "BetterBots: failed to load weapon_action module")

local ConditionPatch = mod:io_dofile("BetterBots/scripts/mods/BetterBots/condition_patch")
assert(ConditionPatch, "BetterBots: failed to load condition_patch module")

local AbilityQueue = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ability_queue")
assert(AbilityQueue, "BetterBots: failed to load ability_queue module")

-- Init each module with its dependencies
MetaData.init({
	mod = mod,
	patched_ability_templates = _patched_ability_templates,
	debug_log = _debug_log,
	META_PATCH_VERSION = META_PATCH_VERSION,
})

Heuristics.init({
	fixed_time = _fixed_time,
	decision_context_cache = _decision_context_cache_by_unit,
	super_armor_breed_cache = _super_armor_breed_flag_by_name,
	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
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
	fixed_time = _fixed_time,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	last_charge_event_by_unit = _last_charge_event_by_unit,
})

EventLog.init({
	mod = mod,
	context_snapshot = Debug.context_snapshot,
})

Sprint.init({
	mod = mod,
	debug_log = _debug_log,
	fixed_time = _fixed_time,
})

MeleeMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates,
	debug_log = _debug_log,
	ARMOR_TYPE_ARMORED = ARMOR_TYPES and ARMOR_TYPES.armored,
})

RangedMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates_ranged,
	debug_log = _debug_log,
})

Poxburster.init({
	mod = mod,
	debug_log = _debug_log,
	fixed_time = _fixed_time,
})

VfxSuppression.init({
	mod = mod,
	debug_log = _debug_log,
})

WeaponAction.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
})

ConditionPatch.init({
	mod = mod,
	debug_log = _debug_log,
	fixed_time = _fixed_time,
	is_suppressed = _is_suppressed,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	patched_bt_bot_conditions = _patched_bt_bot_conditions,
	patched_bt_conditions = _patched_bt_conditions,
	rescue_intent = _rescue_intent,
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = DEBUG_SKIP_RELIC_LOG_INTERVAL_S,
	CONDITIONS_PATCH_VERSION = CONDITIONS_PATCH_VERSION,
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
})

-- Wire cross-module references (late-bound to avoid circular deps)
ItemFallback.wire({
	build_context = Heuristics.build_context,
	context_snapshot = Debug.context_snapshot,
	fallback_state_snapshot = Debug.fallback_state_snapshot,
	evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
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
})

AbilityQueue.wire({
	Heuristics = Heuristics,
	MetaData = MetaData,
	ItemFallback = ItemFallback,
	Debug = Debug,
	EventLog = EventLog,
})

-- Register hooks for extracted modules
Poxburster.register_hooks()
VfxSuppression.register_hooks()
WeaponAction.register_hooks({
	should_lock_weapon_switch = ItemFallback.should_lock_weapon_switch,
})
ConditionPatch.register_hooks()

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

-- BT activate ability enter hook: rescue aim (#10) + event logging
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

				func(self, unit, breed, blackboard, scratchpad, action_data, t)

				local ability_component_name = action_data and action_data.ability_component_name or "?"
				local activation_data = scratchpad and scratchpad.activation_data
				local action_input = activation_data and activation_data.action_input or "?"
				local fixed_t = _fixed_time()

				_debug_log(
					"enter:" .. tostring(ability_component_name) .. ":" .. tostring(action_input),
					fixed_t,
					"enter ability node component="
						.. tostring(ability_component_name)
						.. " action_input="
						.. tostring(action_input)
				)

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

-- Charge consume tracking
mod:hook_require("scripts/extension_systems/ability/player_unit_ability_extension", function(PlayerUnitAbilityExtension)
	mod:hook_safe(PlayerUnitAbilityExtension, "use_ability_charge", function(self, ability_type, optional_num_charges)
		if ability_type ~= "combat_ability" then
			return
		end

		local player = self._player
		if not player or player:is_human_controlled() then
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
		end)
	end
)

-- BotBehaviorExtension: ADS gestalt injection (#35) + main update tick
mod:hook_require("scripts/extension_systems/behavior/bot_behavior_extension", function(BotBehaviorExtension)
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
						"injected default bot_gestalts (ranged=killshot, melee=linesman)"
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

		local brain = self._brain
		local blackboard = brain and brain._blackboard or nil

		if EventLog.is_enabled() and not _session_start_emitted then
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
		end

		AbilityQueue.try_queue(unit, blackboard)
		EventLog.try_flush(_fixed_time())

		if EventLog.is_enabled() then
			local fixed_t = _fixed_time()
			local last_snap = _last_snapshot_t_by_unit[unit]
			if not last_snap or fixed_t - last_snap >= _SNAPSHOT_INTERVAL_S then
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
			end
		end
	end)
end)

function mod.on_game_state_changed(status, state)
	if status == "enter" and state == "GameplayStateRun" then
		for key in pairs(_fallback_queue_dumped_by_key) do
			_fallback_queue_dumped_by_key[key] = nil
		end
		for unit in pairs(_decision_context_cache_by_unit) do
			_decision_context_cache_by_unit[unit] = nil
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

-- Re-enable EventLog after hot-reload if we're mid-session.
if mod:get(EVENT_LOG_SETTING_ID) == true then
	local bots = Debug.collect_alive_bots()
	if bots and #bots > 0 then
		EventLog.set_enabled(true)
		EventLog.start_session(_fixed_time())
		_session_start_emitted = false
	end
end

mod:echo("BetterBots loaded")
if _debug_enabled() then
	mod:echo("BetterBots DEBUG: logging enabled (force=" .. tostring(DEBUG_FORCE_ENABLED) .. ")")
end
