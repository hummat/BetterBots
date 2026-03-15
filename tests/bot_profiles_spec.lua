-- bot_profiles_spec.lua — tests for default bot profiles module (#45)

local _mock_settings = {}
local _debug_logs = {}
local _debug_enabled_result = false

local mock_mod = {
	get = function(_self, setting_id)
		return _mock_settings[setting_id]
	end,
	hook = function() end,
}

local BotProfiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")

BotProfiles.init({
	mod = mock_mod,
	debug_log = function(key, fixed_t, message)
		_debug_logs[#_debug_logs + 1] = {
			key = key,
			fixed_t = fixed_t,
			message = message,
		}
	end,
	debug_enabled = function()
		return _debug_enabled_result
	end,
})

local VANILLA_PROFILE = {
	archetype = "veteran",
	current_level = 1,
	gender = "male",
	selected_voice = "veteran_male_a",
	loadout = {
		slot_primary = "bot_combatsword_linesman_p1",
		slot_secondary = "bot_lasgun_killshot",
		slot_gear_head = "some_helmet",
	},
	bot_gestalts = {
		melee = "linesman",
		ranged = "killshot",
	},
	talents = {},
}

describe("bot_profiles", function()
	before_each(function()
		_mock_settings = {}
		_debug_logs = {}
		_debug_enabled_result = false
		BotProfiles.reset()
	end)

	describe("profile tables", function()
		it("provides profiles for all 4 base classes", function()
			local profiles = BotProfiles._get_profiles()
			assert.is_not_nil(profiles.veteran)
			assert.is_not_nil(profiles.zealot)
			assert.is_not_nil(profiles.psyker)
			assert.is_not_nil(profiles.ogryn)
		end)

		it("every profile has required fields", function()
			local profiles = BotProfiles._get_profiles()
			for class_name, profile in pairs(profiles) do
				assert.equals(class_name, profile.archetype, class_name .. " archetype mismatch")
				assert.is_not_nil(profile.gender, class_name .. " missing gender")
				assert.is_not_nil(profile.selected_voice, class_name .. " missing voice")
				assert.is_not_nil(profile.loadout, class_name .. " missing loadout")
				assert.is_not_nil(profile.loadout.slot_primary, class_name .. " missing melee")
				assert.is_not_nil(profile.loadout.slot_secondary, class_name .. " missing ranged")
				assert.same({}, profile.talents, class_name .. " talents must be empty")
				assert.is_not_nil(profile.bot_gestalts, class_name .. " missing gestalts")
				assert.equals("linesman", profile.bot_gestalts.melee, class_name .. " melee gestalt")
				assert.equals("killshot", profile.bot_gestalts.ranged, class_name .. " ranged gestalt")
			end
		end)

		it("uses hadrons-blessing weapon recommendations", function()
			local profiles = BotProfiles._get_profiles()
			assert.equals("combatsword_p2_m1", profiles.veteran.loadout.slot_primary)
			assert.equals("plasmagun_p1_m1", profiles.veteran.loadout.slot_secondary)
			assert.equals("powersword_2h_p1_m2", profiles.zealot.loadout.slot_primary)
			assert.equals("flamer_p1_m1", profiles.zealot.loadout.slot_secondary)
			assert.equals("forcesword_2h_p1_m1", profiles.psyker.loadout.slot_primary)
			assert.equals("forcestaff_p4_m1", profiles.psyker.loadout.slot_secondary)
			assert.equals("ogryn_powermaul_p1_m1", profiles.ogryn.loadout.slot_primary)
			assert.equals("ogryn_thumper_p1_m2", profiles.ogryn.loadout.slot_secondary)
		end)
	end)

	describe("resolve_profile", function()
		it("passes through vanilla profile when slot setting is none", function()
			_mock_settings.bot_slot_1_profile = "none"
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped)
			assert.equals("veteran", resolved.archetype)
			assert.equals("bot_combatsword_linesman_p1", resolved.loadout.slot_primary)
		end)

		it("passes through vanilla profile when slot setting is nil", function()
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped)
			assert.equals("veteran", resolved.archetype)
		end)

		it("swaps to zealot when slot 1 is set to zealot", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_true(swapped)
			assert.equals("zealot", resolved.archetype)
			assert.equals("powersword_2h_p1_m2", resolved.loadout.slot_primary)
			assert.equals("flamer_p1_m1", resolved.loadout.slot_secondary)
			assert.equals("female", resolved.gender)
			assert.same({}, resolved.talents)
		end)

		it("preserves vanilla cosmetic slots in swapped profile", function()
			_mock_settings.bot_slot_1_profile = "psyker"
			local resolved = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.equals("psyker", resolved.archetype)
			assert.equals("some_helmet", resolved.loadout.slot_gear_head)
		end)

		it("does not mutate the original profile", function()
			_mock_settings.bot_slot_1_profile = "ogryn"
			BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.equals("veteran", VANILLA_PROFILE.archetype)
			assert.equals("bot_combatsword_linesman_p1", VANILLA_PROFILE.loadout.slot_primary)
		end)

		it("assigns sequential slots across multiple spawns", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_mock_settings.bot_slot_2_profile = "psyker"
			_mock_settings.bot_slot_3_profile = "ogryn"

			local r1 = BotProfiles.resolve_profile(VANILLA_PROFILE)
			local r2 = BotProfiles.resolve_profile(VANILLA_PROFILE)
			local r3 = BotProfiles.resolve_profile(VANILLA_PROFILE)

			assert.equals("zealot", r1.archetype)
			assert.equals("psyker", r2.archetype)
			assert.equals("ogryn", r3.archetype)
		end)

		it("passes through when spawn counter exceeds 3 slots", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_mock_settings.bot_slot_2_profile = "psyker"
			_mock_settings.bot_slot_3_profile = "ogryn"

			BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 1
			BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 2
			BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 3
			local r4, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 4: overflow

			assert.is_false(swapped)
			assert.equals("veteran", r4.archetype)
		end)

		it("resets spawn counter correctly", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 1 → zealot
			BotProfiles.reset()

			local resolved = BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 1 again
			assert.equals("zealot", resolved.archetype)
		end)
	end)

	describe("Tertium compatibility", function()
		it("yields when profile is already non-veteran (Tertium assigned)", function()
			_mock_settings.bot_slot_1_profile = "ogryn"

			local tertium_profile = {
				archetype = "zealot",
				current_level = 30,
				gender = "female",
				selected_voice = "zealot_female_b",
				loadout = {
					slot_primary = "thunderhammer_2h_p1_m1",
					slot_secondary = "autogun_p1_m1",
				},
				talents = {},
			}

			local resolved, swapped = BotProfiles.resolve_profile(tertium_profile)
			assert.is_false(swapped)
			assert.equals("zealot", resolved.archetype)
			assert.equals("thunderhammer_2h_p1_m1", resolved.loadout.slot_primary)
			assert.equals(30, resolved.current_level)
		end)

		it("applies BetterBots profile when Tertium slot is none (veteran passes through)", function()
			_mock_settings.bot_slot_1_profile = "psyker"

			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_true(swapped)
			assert.equals("psyker", resolved.archetype)
		end)

		it("yields for all non-veteran archetypes including DLC classes", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_mock_settings.bot_slot_2_profile = "zealot"
			_mock_settings.bot_slot_3_profile = "zealot"

			for _, archetype in ipairs({ "zealot", "psyker", "ogryn", "adamant", "broker" }) do
				BotProfiles.reset()
				local profile = { archetype = archetype, loadout = {}, talents = {} }
				local _, swapped = BotProfiles.resolve_profile(profile)
				assert.is_false(swapped, "should yield for " .. archetype)
			end
		end)
	end)
end)
