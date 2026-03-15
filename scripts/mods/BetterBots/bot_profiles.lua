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
	-- Cosmetics sourced from Darktide Seven (misc_bot_profiles.lua) and tutorial bots.
	-- Each non-veteran class gets full body/gear overrides so the bot looks correct.
	zealot = {
		archetype = "zealot",
		current_level = 1,
		gender = "female",
		selected_voice = "zealot_female_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/powersword_2h_p1_m2",
			slot_secondary = "content/items/weapons/player/ranged/flamer_p1_m1",
		},
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/human/attachment_base/female_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_brown_02",
			slot_body_face = "content/items/characters/player/human/faces/female_asian_face_02",
			slot_body_face_hair = "content/items/characters/player/human/face_hair/female_facial_hair_base",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/human/face_tattoo/empty_face_tattoo",
			slot_body_hair = "content/items/characters/player/human/hair/hair_short_bobcut_a",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_black_02",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_asian_01",
			slot_body_tattoo = "content/items/characters/player/human/body_tattoo/empty_body_tattoo",
			slot_body_torso = "content/items/characters/player/human/attachment_base/female_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/empty_headgear",
			slot_gear_lowerbody = "content/items/characters/player/human/gear_lowerbody/d7_zealot_f_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/human/gear_upperbody/d7_zealot_f_upperbody",
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
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/human/attachment_base/male_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_psyker_02",
			slot_body_face = "content/items/characters/player/human/faces/male_african_face_01",
			slot_body_face_hair = "content/items/characters/player/human/face_hair/empty_face_hair",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/human/face_tattoo/face_tattoo_psyker_05",
			slot_body_hair = "content/items/characters/player/human/hair/empty_hair",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_black_01",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_african_02",
			slot_body_tattoo = "content/items/characters/player/human/body_tattoo/empty_body_tattoo",
			slot_body_torso = "content/items/characters/player/human/gear_torso/empty_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/d7_psyker_m_headgear",
			slot_gear_lowerbody = "content/items/characters/player/human/gear_lowerbody/d7_psyker_m_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/human/gear_upperbody/d7_psyker_m_upperbody",
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
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/ogryn/attachment_base/male_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_green_02",
			slot_body_face = "content/items/characters/player/ogryn/attachment_base/male_face_caucasian_02",
			slot_body_face_hair = "content/items/characters/player/ogryn/face_hair/ogryn_facial_hair_b_eyebrows",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/ogryn/face_tattoo/face_tattoo_ogryn_01",
			slot_body_hair = "content/items/characters/player/human/hair/empty_hair",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_brown_01",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_caucasian_02",
			slot_body_tattoo = "content/items/characters/player/ogryn/body_tattoo/body_tattoo_ogryn_03",
			slot_body_torso = "content/items/characters/player/ogryn/attachment_base/male_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/empty_headgear",
			slot_gear_lowerbody = "content/items/characters/player/ogryn/gear_lowerbody/d7_ogryn_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/ogryn/gear_upperbody/d7_ogryn_upperbody",
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
	local Archetypes = require("scripts/settings/archetype/archetypes")

	if not MasterItems or not LocalProfileBackendParser or not Archetypes then
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

	-- Resolve archetype string to the Archetypes table entry.
	-- The spawning pipeline (package_synchronizer_client) reads archetype.name,
	-- so it must be the resolved table, not the raw string.
	local archetype_table = Archetypes[template.archetype]
	if not archetype_table then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:bad_archetype",
				0,
				"unknown archetype '" .. tostring(template.archetype) .. "' for " .. class_name
			)
		end
		return nil
	end
	profile.archetype = archetype_table

	-- Add cosmetic overrides (e.g. ogryn body meshes) to loadout for resolution
	if template.cosmetic_overrides then
		for slot_name, item_id in pairs(template.cosmetic_overrides) do
			profile.loadout[slot_name] = item_id
		end
	end

	-- Resolve all template strings to item objects (same as bot_character_profiles.lua)
	for slot_name, item_id in pairs(profile.loadout) do
		local item = MasterItems.get_item_or_fallback(item_id, slot_name, item_definitions)
		profile.loadout[slot_name] = item
	end

	-- Run parse_profile to inject base talents and build loadout metadata.
	-- Note: parse_profile reads profile.archetype as a string for the archetype name,
	-- but we've already resolved it to a table. Save and restore.
	local saved_archetype = profile.archetype
	profile.archetype = template.archetype -- string for parse_profile
	LocalProfileBackendParser.parse_profile(profile, "betterbots_" .. class_name)
	profile.archetype = saved_archetype -- restore table for spawning pipeline

	-- The package synchronizer client iterates visual_loadout to resolve item packages.
	-- Bot profiles don't have visual_loadout natively — vanilla bots get it set elsewhere.
	-- Set it to loadout so the package system finds our weapons.
	profile.visual_loadout = profile.visual_loadout or profile.loadout

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

	-- Mutate the vanilla profile in-place rather than replacing it entirely.
	-- The vanilla profile has cosmetic slots, body data, and visual_loadout already
	-- set up correctly. We only swap gameplay-relevant fields: archetype, weapons,
	-- talents, gestalts, and voice. Item objects are direct MasterItems cache references
	-- — no copying needed.
	profile.archetype = resolved.archetype
	profile.gender = resolved.gender
	profile.selected_voice = resolved.selected_voice
	profile.talents = resolved.talents or {}
	profile.bot_gestalts = resolved.bot_gestalts
	profile.loadout.slot_primary = resolved.loadout.slot_primary
	profile.loadout.slot_secondary = resolved.loadout.slot_secondary
	if resolved.loadout_item_ids then
		profile.loadout_item_ids = profile.loadout_item_ids or {}
		profile.loadout_item_ids.slot_primary = resolved.loadout_item_ids.slot_primary
		profile.loadout_item_ids.slot_secondary = resolved.loadout_item_ids.slot_secondary
	end
	if resolved.loadout_item_data then
		profile.loadout_item_data = profile.loadout_item_data or {}
		profile.loadout_item_data.slot_primary = resolved.loadout_item_data.slot_primary
		profile.loadout_item_data.slot_secondary = resolved.loadout_item_data.slot_secondary
	end
	-- Apply cosmetic slot overrides (e.g. ogryn body meshes)
	local template = DEFAULT_PROFILE_TEMPLATES[choice]
	if template and template.cosmetic_overrides then
		for slot_name in pairs(template.cosmetic_overrides) do
			if resolved.loadout[slot_name] then
				profile.loadout[slot_name] = resolved.loadout[slot_name]
				if resolved.loadout_item_ids and resolved.loadout_item_ids[slot_name] then
					profile.loadout_item_ids[slot_name] = resolved.loadout_item_ids[slot_name]
				end
				if resolved.loadout_item_data and resolved.loadout_item_data[slot_name] then
					profile.loadout_item_data[slot_name] = resolved.loadout_item_data[slot_name]
				end
			end
		end
	end

	-- visual_loadout mirrors loadout for package resolution
	if profile.visual_loadout then
		profile.visual_loadout.slot_primary = resolved.loadout.slot_primary
		profile.visual_loadout.slot_secondary = resolved.loadout.slot_secondary
		if template and template.cosmetic_overrides then
			for slot_name in pairs(template.cosmetic_overrides) do
				if resolved.loadout[slot_name] then
					profile.visual_loadout[slot_name] = resolved.loadout[slot_name]
				end
			end
		end
	end

	if _debug_enabled() then
		_debug_log("bot_profiles:swap", 0, "bot slot " .. tostring(slot_index) .. " → " .. tostring(choice))
	end

	return profile, true
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
