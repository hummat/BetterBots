local MeleeMetaData = dofile("scripts/mods/BetterBots/melee_meta_data.lua")

local ARMORED = 2

local function noop_debug_log() end

local function make_damage_profile(cleave_max, armored_max)
	return {
		cleave_distribution = {
			attack = { cleave_max * 0.5, cleave_max },
		},
		armor_damage_modifier = {
			attack = {
				[ARMORED] = { armored_max * 0.5, armored_max },
			},
		},
	}
end

describe("melee_meta_data", function()
	before_each(function()
		MeleeMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
			ARMOR_TYPE_ARMORED = ARMORED,
		})
	end)

	describe("classify_arc", function()
		it("returns 0 for no cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(0.001, 0)))
		end)

		it("returns 0 for single cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(2, 0)))
		end)

		it("returns 1 for light to medium cleave", function()
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(4, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(6, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(9, 0)))
		end)

		it("returns 2 for large and big cleave", function()
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(10.5, 0)))
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(12.5, 0)))
		end)

		it("returns 0 for nil damage profile", function()
			assert.equals(0, MeleeMetaData._classify_arc(nil))
		end)

		it("returns 0 for missing cleave_distribution", function()
			assert.equals(0, MeleeMetaData._classify_arc({}))
		end)
	end)

	describe("classify_penetrating", function()
		it("returns false for low armor modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.426), ARMORED))
		end)

		it("returns true for high armor modifier", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.675), ARMORED))
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.33), ARMORED))
		end)

		it("returns true at exact threshold", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.5), ARMORED))
		end)

		it("returns false for nil damage profile", function()
			assert.is_false(MeleeMetaData._classify_penetrating(nil, ARMORED))
		end)

		it("returns false for missing armor_damage_modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating({}, ARMORED))
		end)

		it("returns false for nil armored_type", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.0), nil))
		end)
	end)
end)
