-- bot_profiles.lua — hardcoded default class profiles for bots (#45)
-- Replaces vanilla all-veteran profiles with class-diverse loadouts so players
-- without leveled characters can still benefit from BetterBots' ability support.
-- Weapon choices sourced from hadrons-blessing bot-weapon-recommendations.json.

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
}

local DEFAULT_PROFILES = {
	veteran = {
		archetype = "veteran",
		current_level = 1,
		gender = "male",
		selected_voice = "veteran_male_a",
		loadout = {
			slot_primary = "combatsword_p2_m1",
			slot_secondary = "plasmagun_p1_m1",
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
			slot_primary = "powersword_2h_p1_m2",
			slot_secondary = "flamer_p1_m1",
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
			slot_primary = "forcesword_2h_p1_m1",
			slot_secondary = "forcestaff_p4_m1",
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
			slot_primary = "ogryn_powermaul_p1_m1",
			slot_secondary = "ogryn_thumper_p1_m2",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		talents = {},
	},
}

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

local function register_hooks()
	_mod:hook("BotSynchronizerHost", "add_bot", function(func, self, local_player_id, profile)
		_spawn_counter = _spawn_counter + 1
		local slot_index = _spawn_counter

		if slot_index > #SLOT_SETTING_IDS then
			return func(self, local_player_id, profile)
		end

		local choice = _get_slot_profile_choice(slot_index)
		if choice == "none" then
			return func(self, local_player_id, profile)
		end

		local template = DEFAULT_PROFILES[choice]
		if not template then
			if _debug_enabled() then
				_debug_log(
					"bot_profiles:unknown_choice",
					0,
					"bot slot "
						.. tostring(slot_index)
						.. " has unknown profile choice: "
						.. tostring(choice)
						.. ", using vanilla"
				)
			end
			return func(self, local_player_id, profile)
		end

		-- Build replacement profile by overlaying our defaults onto the vanilla profile.
		-- This preserves any fields the engine expects that we don't set (cosmetic slots, etc).
		local new_profile = _deep_copy_profile(profile)
		new_profile.archetype = template.archetype
		new_profile.gender = template.gender
		new_profile.selected_voice = template.selected_voice
		new_profile.current_level = template.current_level
		new_profile.talents = {}
		new_profile.bot_gestalts = _deep_copy_profile(template.bot_gestalts)
		new_profile.loadout = new_profile.loadout or {}
		new_profile.loadout.slot_primary = template.loadout.slot_primary
		new_profile.loadout.slot_secondary = template.loadout.slot_secondary

		if _debug_enabled() then
			_debug_log(
				"bot_profiles:swap",
				0,
				"bot slot "
					.. tostring(slot_index)
					.. " → "
					.. template.archetype
					.. " (melee="
					.. template.loadout.slot_primary
					.. ", ranged="
					.. template.loadout.slot_secondary
					.. ")"
			)
		end

		return func(self, local_player_id, new_profile)
	end)
end

local function reset()
	_spawn_counter = 0
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
	end,
	register_hooks = register_hooks,
	reset = reset,
	-- Test-only accessors
	_get_profiles = function()
		return DEFAULT_PROFILES
	end,
}
