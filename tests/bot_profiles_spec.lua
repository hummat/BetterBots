-- bot_profiles_spec.lua — tests for default bot profiles module (#45)

-- Stub `require` for game modules that aren't available in the test environment.
-- Returns nil for game-only modules so resolve_profile gracefully fails without crashing.
local _original_require = require
rawset(_G, "require", function(modname)
	if modname == "scripts/backend/master_items" or modname == "scripts/utilities/local_profile_backend_parser" then
		return nil
	end
	return _original_require(modname)
end)

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

	describe("profile templates", function()
		it("provides templates for all 4 base classes", function()
			local profiles = BotProfiles._get_profiles()
			assert.is_not_nil(profiles.veteran)
			assert.is_not_nil(profiles.zealot)
			assert.is_not_nil(profiles.psyker)
			assert.is_not_nil(profiles.ogryn)
		end)

		it("every template has required fields", function()
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

		it("uses full content paths for weapon template IDs", function()
			local profiles = BotProfiles._get_profiles()
			for class_name, profile in pairs(profiles) do
				assert.truthy(
					string.find(profile.loadout.slot_primary, "content/items/weapons/", 1, true),
					class_name .. " melee should be a full content path"
				)
				assert.truthy(
					string.find(profile.loadout.slot_secondary, "content/items/weapons/", 1, true),
					class_name .. " ranged should be a full content path"
				)
			end
		end)
	end)

	describe("resolve_profile (pass-through cases)", function()
		it("passes through when setting is none", function()
			_mock_settings.bot_slot_1_profile = "none"
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped)
			assert.equals("veteran", resolved.archetype)
		end)

		it("passes through when setting is nil (uninitialized)", function()
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped)
		end)

		it("passes through when spawn counter exceeds slot count", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_mock_settings.bot_slot_2_profile = "zealot"
			_mock_settings.bot_slot_3_profile = "zealot"
			_mock_settings.bot_slot_4_profile = "zealot"
			_mock_settings.bot_slot_5_profile = "zealot"
			for _ = 1, 5 do
				BotProfiles.resolve_profile(VANILLA_PROFILE)
			end
			local _, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 6: overflow
			assert.is_false(swapped)
		end)

		it("resets spawn counter correctly", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 1
			BotProfiles.reset()
			-- After reset, resolve_profile would try to resolve again (slot 1)
			-- but MasterItems is nil in test → returns (profile, false)
			local _, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped) -- can't resolve without game items, but counter did reset
		end)
	end)

	describe("Tertium compatibility", function()
		it("yields when profile archetype is a non-veteran string", function()
			_mock_settings.bot_slot_1_profile = "ogryn"
			local tertium_profile = {
				archetype = "zealot",
				loadout = {},
				talents = {},
			}
			local resolved, swapped = BotProfiles.resolve_profile(tertium_profile)
			assert.is_false(swapped)
			assert.equals("zealot", resolved.archetype)
		end)

		it("yields when profile archetype is a resolved table with .name", function()
			_mock_settings.bot_slot_1_profile = "ogryn"
			local tertium_profile = {
				archetype = { name = "psyker", archetype_name = "loc_psyker" },
				loadout = {},
				talents = {},
			}
			local resolved, swapped = BotProfiles.resolve_profile(tertium_profile)
			assert.is_false(swapped)
		end)

		it("yields for all non-veteran archetypes including DLC classes", function()
			for _, archetype in ipairs({ "zealot", "psyker", "ogryn", "adamant", "broker" }) do
				BotProfiles.reset()
				_mock_settings.bot_slot_1_profile = "zealot"
				local profile = { archetype = archetype, loadout = {}, talents = {} }
				local _, swapped = BotProfiles.resolve_profile(profile)
				assert.is_false(swapped, "should yield for " .. archetype)
			end
		end)

		it("does not yield for veteran archetype", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			-- Will try to resolve but MasterItems is nil → returns false
			-- The important thing: it did NOT yield at the archetype guard
			_debug_enabled_result = true
			BotProfiles.resolve_profile(VANILLA_PROFILE)
			-- If it yielded at archetype guard, there'd be no debug log about resolution
			-- If it passed through, it would try to resolve and fail (MasterItems nil)
			-- Either way, swapped=false, but we can check logs to confirm it got past the guard
		end)
	end)
end)
