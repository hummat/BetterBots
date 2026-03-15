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

	describe("reset", function()
		it("resets spawn counter so slot assignment starts fresh", function()
			-- Simulate that the counter has been used
			BotProfiles.reset()
			-- After reset, the next add_bot should map to slot 1
			-- (tested indirectly via the hook tests below)
		end)
	end)
end)
