-- bot_profiles.lua — hardcoded default class profiles for bots (#45)
-- Replaces vanilla all-veteran profiles with class-diverse loadouts so players
-- without leveled characters can still benefit from BetterBots' ability support.
-- Weapon choices sourced from hadrons-blessing bot-weapon-recommendations.json.
--
-- Profile resolution: vanilla bot profiles are pre-baked by bot_character_profiles.lua
-- (items resolved, parse_profile called) BEFORE reaching add_bot. We must resolve our
-- items the same way, or the engine gets string IDs where it expects item objects.

local _mod
local _debug_log
local _debug_enabled

-- Spawn counter: incremented per add_bot call within a mission, maps to slot 1-3.
-- Reset on GameplayStateRun enter.
local _spawn_counter = 0

local SLOT_SETTING_IDS = {
	"bot_slot_1_profile",
	"bot_slot_2_profile",
	"bot_slot_3_profile",
	"bot_slot_4_profile",
	"bot_slot_5_profile",
}

-- Raw profile templates — archetype as string, loadout as template ID strings.
-- These get resolved to full item objects at hook time via MasterItems.
local DEFAULT_PROFILE_TEMPLATES = {
	veteran = {
		archetype = "veteran",
		current_level = 1,
		gender = "male",
		selected_voice = "veteran_male_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/combatsword_p2_m1",
			slot_secondary = "content/items/weapons/player/ranged/plasmagun_p1_m1",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		talents = {},
	},
	zealot = {
		archetype = "zealot",
		current_level = 1,
		gender = "female",
		selected_voice = "zealot_female_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/powersword_2h_p1_m2",
			slot_secondary = "content/items/weapons/player/ranged/flamer_p1_m1",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		talents = {},
	},
	psyker = {
		archetype = "psyker",
		current_level = 1,
		gender = "male",
		selected_voice = "psyker_male_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/forcesword_2h_p1_m1",
			slot_secondary = "content/items/weapons/player/ranged/forcestaff_p4_m1",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		talents = {},
	},
	ogryn = {
		archetype = "ogryn",
		current_level = 1,
		gender = "male",
		selected_voice = "ogryn_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/ogryn_powermaul_p1_m1",
			slot_secondary = "content/items/weapons/player/ranged/ogryn_thumper_p1_m2",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		talents = {},
	},
}

-- Resolved profiles cache: built on first use by resolving item strings to objects.
-- Keyed by class name. Reset on GameplayStateRun enter (item catalog may change).
local _resolved_profiles = {}

local function _get_slot_profile_choice(slot_index)
	if not _mod then
		return "none"
	end

	local setting_id = SLOT_SETTING_IDS[slot_index]
	if not setting_id then
		return "none"
	end

	return _mod:get(setting_id) or "none"
end

local function _deep_copy_profile(source)
	local copy = {}
	for k, v in pairs(source) do
		if type(v) == "table" then
			copy[k] = _deep_copy_profile(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function _resolve_profile_template(class_name)
	if _resolved_profiles[class_name] then
		return _resolved_profiles[class_name]
	end

	local template = DEFAULT_PROFILE_TEMPLATES[class_name]
	if not template then
		return nil
	end

	local MasterItems = require("scripts/backend/master_items")
	local LocalProfileBackendParser = require("scripts/utilities/local_profile_backend_parser")

	if not MasterItems or not LocalProfileBackendParser then
		return nil
	end

	local item_definitions = MasterItems.get_cached()

	if not item_definitions then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:no_items",
				0,
				"MasterItems not cached yet, cannot resolve profile for " .. class_name
			)
		end
		return nil
	end

	local profile = _deep_copy_profile(template)

	-- Resolve weapon template strings to item objects (same as bot_character_profiles.lua)
	for slot_name, item_id in pairs(profile.loadout) do
		local item = MasterItems.get_item_or_fallback(item_id, slot_name, item_definitions)
		profile.loadout[slot_name] = item
	end

	-- Run parse_profile to inject base talents and build loadout metadata
	LocalProfileBackendParser.parse_profile(profile, "betterbots_" .. class_name)

	_resolved_profiles[class_name] = profile

	if _debug_enabled() then
		_debug_log(
			"bot_profiles:resolved",
			0,
			"resolved profile for " .. class_name .. " (archetype=" .. tostring(profile.archetype) .. ")"
		)
	end

	return profile
end

-- Resolve the profile for a given bot spawn. Returns (resolved_profile, was_swapped).
-- Extracted from the hook for testability.
local function resolve_profile(profile)
	_spawn_counter = _spawn_counter + 1
	local slot_index = _spawn_counter

	if slot_index > #SLOT_SETTING_IDS then
		return profile, false
	end

	-- If another mod (Tertium4Or5/6) already swapped the profile to a non-veteran
	-- class, yield — vanilla only spawns veterans, so a non-veteran archetype means
	-- another mod provided a real player character for this slot.
	-- Note: profile.archetype can be a resolved table (with .name field) or a string.
	local archetype = profile.archetype
	local archetype_name = type(archetype) == "table" and archetype.name or archetype
	if archetype_name and archetype_name ~= "veteran" then
		return profile, false
	end

	local choice = _get_slot_profile_choice(slot_index)
	if choice == "none" then
		return profile, false
	end

	local resolved = _resolve_profile_template(choice)
	if not resolved then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:resolve_failed",
				0,
				"bot slot " .. tostring(slot_index) .. " failed to resolve profile for " .. tostring(choice)
			)
		end
		return profile, false
	end

	-- Overlay resolved profile onto the vanilla profile to preserve engine-expected fields
	-- (cosmetic slots, personal data, etc.)
	local new_profile = _deep_copy_profile(profile)
	new_profile.archetype = resolved.archetype
	new_profile.gender = resolved.gender
	new_profile.selected_voice = resolved.selected_voice
	new_profile.current_level = resolved.current_level
	new_profile.talents = resolved.talents or {}
	new_profile.bot_gestalts = _deep_copy_profile(resolved.bot_gestalts)
	new_profile.loadout.slot_primary = resolved.loadout.slot_primary
	new_profile.loadout.slot_secondary = resolved.loadout.slot_secondary
	if resolved.loadout_item_ids then
		new_profile.loadout_item_ids = new_profile.loadout_item_ids or {}
		new_profile.loadout_item_ids.slot_primary = resolved.loadout_item_ids.slot_primary
		new_profile.loadout_item_ids.slot_secondary = resolved.loadout_item_ids.slot_secondary
	end
	if resolved.loadout_item_data then
		new_profile.loadout_item_data = new_profile.loadout_item_data or {}
		new_profile.loadout_item_data.slot_primary = resolved.loadout_item_data.slot_primary
		new_profile.loadout_item_data.slot_secondary = resolved.loadout_item_data.slot_secondary
	end

	if _debug_enabled() then
		_debug_log("bot_profiles:swap", 0, "bot slot " .. tostring(slot_index) .. " → " .. tostring(choice))
	end

	return new_profile, true
end

local function register_hooks()
	_mod:hook("BotSynchronizerHost", "add_bot", function(func, self, local_player_id, profile)
		local resolved, swapped = resolve_profile(profile)
		local archetype_raw = profile.archetype
		local archetype_display = type(archetype_raw) == "table"
				and (archetype_raw.name or archetype_raw.archetype_name or "table")
			or tostring(archetype_raw)
		_mod:echo(
			"BetterBots: add_bot slot "
				.. tostring(_spawn_counter)
				.. " archetype="
				.. archetype_display
				.. " swapped="
				.. tostring(swapped)
		)
		return func(self, local_player_id, resolved)
	end)
end

local function reset()
	_spawn_counter = 0
	-- Clear resolved cache — item catalog may have changed between missions
	for k in pairs(_resolved_profiles) do
		_resolved_profiles[k] = nil
	end
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
	end,
	register_hooks = register_hooks,
	reset = reset,
	resolve_profile = resolve_profile,
	_get_profiles = function()
		return DEFAULT_PROFILE_TEMPLATES
	end,
}
