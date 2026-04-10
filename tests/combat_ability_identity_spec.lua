local Identity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local helper = require("tests.test_helper")

describe("combat_ability_identity", function()
	it("separates engine template from veteran shout semantic identity", function()
		local ability_extension = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout")
		local identity = Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })

		assert.equals("veteran_combat_ability", identity.template_name)
		assert.equals("veteran_combat_ability_shout", identity.ability_name)
		assert.equals("veteran_combat_ability_shout", identity.semantic_key)
		assert.equals("squad_leader", identity.class_tag)
		assert.equals("class_tag", identity.class_tag_source)
	end)

	it("falls back to ability name when veteran class_tag is absent", function()
		local ability_extension = helper.make_veteran_ability_extension(nil, "veteran_combat_ability_shout")
		local identity = Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })

		assert.equals("veteran_combat_ability_shout", identity.semantic_key)
		assert.equals("squad_leader", identity.class_tag)
		assert.equals("ability_name", identity.class_tag_source)
	end)

	it("keeps non-shared templates as their template semantic key", function()
		local ability_extension = {
			_equipped_abilities = {
				combat_ability = {
					name = "psyker_combat_ability_stance",
				},
			},
		}
		local identity = Identity.resolve(nil, ability_extension, { template_name = "psyker_overcharge_stance" })

		assert.equals("psyker_overcharge_stance", identity.template_name)
		assert.equals("psyker_combat_ability_stance", identity.ability_name)
		assert.equals("psyker_overcharge_stance", identity.semantic_key)
	end)

	it("maps semantic identity to settings category", function()
		local shout = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)
		local stance = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("ranger", "veteran_combat_ability_stance"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.equals("enable_shouts", Identity.category_setting_id(shout))
		assert.equals("enable_stances", Identity.category_setting_id(stance))
		assert.equals("enable_stances", Identity.category_setting_id({ semantic_key = "psyker_overcharge_stance" }))
	end)

	it("uses semantic identity for revive defensive and cooldown categories", function()
		local shout = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)
		local stance = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("ranger", "veteran_combat_ability_stance"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.is_true(Identity.is_revive_defensive(shout))
		assert.is_false(Identity.is_revive_defensive(stance))
		assert.equals("aoe_shout", Identity.team_cooldown_category(shout))
		assert.is_nil(Identity.team_cooldown_category(stance))
	end)
end)
