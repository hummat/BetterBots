local Settings = dofile("scripts/mods/BetterBots/settings.lua")

describe("settings", function()
	describe("resolve_behavior_profile", function()
		it("defaults to standard", function()
			Settings.init({
				mod = {
					get = function()
						return nil
					end,
				},
			})

			assert.equals("standard", Settings.resolve_behavior_profile())
		end)

		it("accepts testing profile", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "behavior_profile" then
							return "testing"
						end
					end,
				},
			})

			assert.equals("testing", Settings.resolve_behavior_profile())
		end)

		it("falls back to standard for invalid values", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "behavior_profile" then
							return "broken"
						end
					end,
				},
			})

			assert.equals("standard", Settings.resolve_behavior_profile())
		end)
	end)

	describe("tier gates", function()
		it("disables tier 1 combat templates when the setting is off", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "enable_tier_1_abilities" then
							return false
						end
					end,
				},
			})

			assert.is_false(Settings.is_combat_template_enabled("veteran_stealth_combat_ability"))
			assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability"))
		end)

		it("disables tier 2 combat templates when the setting is off", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "enable_tier_2_abilities" then
							return false
						end
					end,
				},
			})

			assert.is_false(Settings.is_combat_template_enabled("zealot_dash"))
			assert.is_false(Settings.is_combat_template_enabled("psyker_shout"))
		end)

		it("disables tier 3 item abilities when the setting is off", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "enable_tier_3_abilities" then
							return false
						end
					end,
				},
			})

			assert.is_false(Settings.is_item_ability_enabled("zealot_relic"))
			assert.is_false(Settings.is_item_ability_enabled("adamant_area_buff_drone"))
		end)

		it("disables grenade and blitz abilities when the setting is off", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "enable_grenade_blitz_abilities" then
							return false
						end
					end,
				},
			})

			assert.is_false(Settings.is_grenade_enabled("veteran_frag_grenade"))
			assert.is_false(Settings.is_grenade_enabled("psyker_throwing_knives"))
		end)

		it("leaves unknown combat and item identifiers enabled", function()
			Settings.init({
				mod = {
					get = function()
						return false
					end,
				},
			})

			assert.is_true(Settings.is_combat_template_enabled("unknown_template"))
			assert.is_true(Settings.is_item_ability_enabled("unknown_item"))
		end)

		it("treats grenade gating as a global feature toggle", function()
			Settings.init({
				mod = {
					get = function(_, setting_id)
						if setting_id == "enable_grenade_blitz_abilities" then
							return false
						end
					end,
				},
			})

			assert.is_false(Settings.is_grenade_enabled("unknown_grenade"))
		end)
	end)
end)
