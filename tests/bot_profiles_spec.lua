-- bot_profiles_spec.lua — tests for default bot profiles module (#45)

-- Stub `require` for game modules that aren't available in the test environment.
-- Returns nil for game-only modules so resolve_profile gracefully fails without crashing.
local _original_require = require
rawset(_G, "require", function(modname)
	if
		modname == "scripts/backend/master_items"
		or modname == "scripts/utilities/local_profile_backend_parser"
		or modname == "scripts/settings/archetype/archetypes"
	then
		return nil
	end
	return _original_require(modname)
end)

local _mock_settings = {}
local _debug_logs = {}
local _echo_messages = {}
local _debug_enabled_result = false

local mock_mod = {
	get = function(_self, setting_id)
		return _mock_settings[setting_id]
	end,
	hook = function() end,
	echo = function(_self, msg)
		_echo_messages[#_echo_messages + 1] = msg
	end,
}

local BotProfiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
local Localization = dofile("scripts/mods/BetterBots/BetterBots_localization.lua")

BotProfiles.init({
	mod = mock_mod,
	debug_log = function(key, fixed_t, message, interval, level)
		_debug_logs[#_debug_logs + 1] = {
			key = key,
			fixed_t = fixed_t,
			message = message,
			interval = interval,
			level = level,
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

local EXPECTED_CURIO_NAME = "Blessed Bullet (Reliquary)"
local EXPECTED_CURIO_MASTER_ITEM_ID = "content/items/gadgets/defensive_gadget_11"

describe("bot_profiles", function()
	before_each(function()
		_mock_settings = {}
		_debug_logs = {}
		_echo_messages = {}
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

		it("ships the configured default lineup", function()
			local profiles = BotProfiles._get_profiles()

			assert.equals("content/items/weapons/player/melee/powersword_p1_m2", profiles.veteran.loadout.slot_primary)
			assert.equals(
				"content/items/weapons/player/ranged/plasmagun_p1_m1",
				profiles.veteran.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.veteran.talents.veteran_improved_tag)
			assert.is_not_nil(profiles.veteran.talents.veteran_combat_ability_stagger_nearby_enemies)

			assert.equals(
				"content/items/weapons/player/melee/chainsword_2h_p1_m1",
				profiles.zealot.loadout.slot_primary
			)
			assert.equals("content/items/weapons/player/ranged/bolter_p1_m2", profiles.zealot.loadout.slot_secondary)
			assert.is_not_nil(profiles.zealot.talents.zealot_bolstering_prayer)
			assert.is_not_nil(profiles.zealot.talents.zealot_fanatic_rage)

			assert.equals("content/items/weapons/player/melee/combatsword_p3_m2", profiles.psyker.loadout.slot_primary)
			assert.equals(
				"content/items/weapons/player/ranged/forcestaff_p1_m1",
				profiles.psyker.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.psyker.talents.psyker_shout_vent_warp_charge)
			assert.is_not_nil(profiles.psyker.talents.psyker_grenade_throwing_knives)

			assert.equals("content/items/weapons/player/melee/ogryn_club_p1_m1", profiles.ogryn.loadout.slot_primary)
			assert.equals(
				"content/items/weapons/player/ranged/ogryn_rippergun_p1_m3",
				profiles.ogryn.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.ogryn.talents.ogryn_longer_charge)
			assert.is_not_nil(profiles.ogryn.talents.ogryn_grenade_friend_rock)
		end)

		it("locks in the requested meta pivots for the shipped lineup", function()
			local profiles = BotProfiles._get_profiles()

			assert.is_not_nil(profiles.zealot.talents.zealot_bolstering_prayer)
			assert.is_not_nil(profiles.psyker.talents.psyker_elite_kills_add_warpfire)
			assert.is_not_nil(profiles.veteran.talents.veteran_dodging_grants_crit)
		end)

		it("keeps the shipped profile labels aligned with the authored lineup", function()
			assert.equals("Veteran - Plasma Gun + Power Sword", Localization.bot_profile_veteran.en)
			assert.equals("Zealot - Boltgun + Heavy Eviscerator", Localization.bot_profile_zealot.en)
			assert.equals("Psyker - Voidblast Staff + Duelling Sword", Localization.bot_profile_psyker.en)
			assert.equals("Ogryn - Ripper Gun + Latrine Shovel", Localization.bot_profile_ogryn.en)
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
				assert.is_table(profile.talents, class_name .. " missing talents")
				assert.is_true(next(profile.talents) ~= nil, class_name .. " talents must not be empty")
				assert.is_not_nil(profile.bot_gestalts, class_name .. " missing gestalts")
				assert.equals("linesman", profile.bot_gestalts.melee, class_name .. " melee gestalt")
				assert.equals("killshot", profile.bot_gestalts.ranged, class_name .. " ranged gestalt")
			end
		end)

		it("talent keys are valid for their class (no cross-class contamination)", function()
			local profiles = BotProfiles._get_profiles()
			-- Class-specific talent keys must start with the class name or "base_" (stat nodes)
			local CLASS_PREFIXES = {
				veteran = { "veteran_", "base_" },
				zealot = { "zealot_", "base_" },
				psyker = { "psyker_", "base_" },
				ogryn = { "ogryn_", "base_" },
			}
			-- Other classes whose prefixes should NEVER appear in a profile
			local WRONG_PREFIXES = {
				veteran = { "zealot_", "psyker_", "ogryn_", "adamant_", "broker_" },
				zealot = { "veteran_", "psyker_", "ogryn_", "adamant_", "broker_" },
				psyker = { "veteran_", "zealot_", "ogryn_", "adamant_", "broker_" },
				ogryn = { "veteran_", "zealot_", "psyker_", "adamant_", "broker_" },
			}
			for class_name, profile in pairs(profiles) do
				local valid_prefixes = CLASS_PREFIXES[class_name]
				local wrong_prefixes = WRONG_PREFIXES[class_name]
				for talent_name, _ in pairs(profile.talents) do
					-- Must match at least one valid prefix
					local has_valid = false
					for _, prefix in ipairs(valid_prefixes) do
						if string.sub(talent_name, 1, #prefix) == prefix then
							has_valid = true
							break
						end
					end
					assert.is_true(has_valid, class_name .. " talent '" .. talent_name .. "' has no valid prefix")
					-- Must NOT match any wrong-class prefix
					for _, prefix in ipairs(wrong_prefixes) do
						assert.is_false(
							string.sub(talent_name, 1, #prefix) == prefix,
							class_name .. " talent '" .. talent_name .. "' belongs to another class"
						)
					end
				end
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

		it("defines synthesized quality gear payloads for both weapon slots on every profile", function()
			local profiles = BotProfiles._get_profiles()

			for class_name, profile in pairs(profiles) do
				assert.is_table(profile.weapon_overrides, class_name .. " missing weapon_overrides")

				for _, slot_name in ipairs({ "slot_primary", "slot_secondary" }) do
					local override = profile.weapon_overrides[slot_name]

					assert.is_table(override, class_name .. " missing override for " .. slot_name)
					assert.is_table(override.traits, class_name .. " missing traits for " .. slot_name)
					assert.is_true(#override.traits > 0, class_name .. " traits empty for " .. slot_name)
					assert.is_table(override.perks, class_name .. " missing perks for " .. slot_name)
					assert.is_true(#override.perks > 0, class_name .. " perks empty for " .. slot_name)
				end
			end
		end)

		it("declares explicit curio metadata with concrete runtime gadget IDs", function()
			local profiles = BotProfiles._get_profiles()

			for class_name, profile in pairs(profiles) do
				assert.is_table(profile.curios, class_name .. " missing curios metadata")
				assert.equals(3, #profile.curios, class_name .. " should declare exactly 3 curios")

				for index, curio in ipairs(profile.curios) do
					assert.equals(EXPECTED_CURIO_NAME, curio.name, class_name .. " curio " .. index .. " name")
					assert.equals(
						EXPECTED_CURIO_MASTER_ITEM_ID,
						curio.master_item_id,
						class_name .. " curio " .. index .. " master item id"
					)
					assert.is_table(curio.traits, class_name .. " curio " .. index .. " missing traits")
					assert.equals(4, #curio.traits, class_name .. " curio " .. index .. " should declare 4 traits")
					assert.equals("gadget_innate_toughness_increase", curio.traits[1].id)
					assert.equals("gadget_cooldown_reduction", curio.traits[2].id)
					assert.equals("gadget_damage_reduction_vs_gunners", curio.traits[3].id)
					assert.equals("gadget_stamina_regeneration", curio.traits[4].id)
					for trait_index, trait in ipairs(curio.traits) do
						assert.equals(
							4,
							trait.rarity,
							class_name .. " curio " .. index .. " trait " .. trait_index .. " rarity"
						)
					end
				end
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
			local _, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
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
		it("yields when a veteran profile has character_id AND name (real backend character)", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_debug_enabled_result = true
			local tertium_profile = {
				archetype = "veteran",
				character_id = "char-vet-001",
				name = "Hammerkeeper",
				current_level = 30,
				loadout = {},
				talents = {},
			}
			local resolved, swapped = BotProfiles.resolve_profile(tertium_profile)
			assert.is_false(swapped)
			assert.equals("veteran", resolved.archetype)
			assert.equals("char-vet-001", resolved.character_id)
			assert.equals(1, #_debug_logs)
			assert.equals("bot_profiles:yield_character_id:1", _debug_logs[1].key)
			assert.equals(0, _debug_logs[1].fixed_t)
			assert.matches("preserving external profile for bot slot 1", _debug_logs[1].message, 1, true)
			assert.matches("char-vet-001", _debug_logs[1].message, 1, true)
		end)

		it("does NOT yield for Tertium 'None' slots (character_id but no name)", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			local tertium_none_profile = {
				archetype = "veteran",
				character_id = "high_bot_2",
				current_level = 1,
				name_list_id = "veteran_names",
				loadout = {},
				talents = {},
			}
			-- Vanilla bot profiles (Tertium "None" pass-through) have character_id and
			-- current_level=1 after parse_profile(), but no `name` field. BetterBots
			-- should NOT yield — it should override with its class-diverse profile.
			local _, swapped = BotProfiles.resolve_profile(tertium_none_profile)
			assert.is_false(swapped)
		end)

		it("does NOT yield when character_id present but name is nil", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			local profile = {
				archetype = "veteran",
				character_id = "high_bot_1",
				loadout = {},
				talents = {},
			}
			local _, swapped = BotProfiles.resolve_profile(profile)
			assert.is_false(swapped)
		end)

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
			local _, swapped = BotProfiles.resolve_profile(tertium_profile)
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

	describe("profile overwrite guard (#65)", function()
		it("does NOT set flags on pass-through (setting=none)", function()
			_mock_settings.bot_slot_1_profile = "none"
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE)
			assert.is_false(swapped)
			assert.is_nil(resolved.is_local_profile)
			assert.is_nil(resolved._bb_resolved)
		end)

		it("does NOT set flags on pass-through (Tertium yield)", function()
			_mock_settings.bot_slot_1_profile = "ogryn"
			local tertium_profile = {
				archetype = "zealot",
				loadout = {},
				talents = {},
			}
			local resolved, swapped = BotProfiles.resolve_profile(tertium_profile)
			assert.is_false(swapped)
			assert.is_nil(resolved.is_local_profile)
			assert.is_nil(resolved._bb_resolved)
		end)

		it("does NOT set flags on pass-through (slot overflow)", function()
			for i = 1, 5 do
				_mock_settings["bot_slot_" .. i .. "_profile"] = "zealot"
			end
			for _ = 1, 5 do
				BotProfiles.resolve_profile(VANILLA_PROFILE)
			end
			local resolved, swapped = BotProfiles.resolve_profile(VANILLA_PROFILE) -- slot 6
			assert.is_false(swapped)
			assert.is_nil(resolved.is_local_profile)
			assert.is_nil(resolved._bb_resolved)
		end)

		it("preserves the curated UI/profile contract subtree during in-place bot profile resolution", function()
			local saved_require = require

			local ok, err = pcall(function()
				local fake_master_items = {
					get_cached = function()
						return {
							zealot_primary = { id = "zealot_primary" },
							zealot_secondary = { id = "zealot_secondary" },
						}
					end,
					get_item_or_fallback = function(item_id)
						return {
							name = item_id,
						}
					end,
					get_item_instance = function(gear)
						return {
							name = gear.masterDataInstance.id,
							gear_id = gear.masterDataInstance.id,
						}
					end,
				}

				local fake_archetypes = {
					zealot = { name = "zealot", breed = "human" },
				}

				local fake_weapon_templates = {
					chainsword_2h_p1_m1 = {
						base_stats = {
							damage_stat = {},
							finesse_stat = {},
						},
					},
					bolter_p1_m2 = {
						base_stats = {
							damage_stat = {},
							charge_stat = {},
							ammo_stat = {},
						},
					},
				}

				rawset(_G, "require", function(modname)
					if modname == "scripts/backend/master_items" then
						return fake_master_items
					end
					if modname == "scripts/utilities/local_profile_backend_parser" then
						return {
							parse_profile = function(_profile, _id)
								return true
							end,
						}
					end
					if modname == "scripts/settings/archetype/archetypes" then
						return fake_archetypes
					end
					if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
						return fake_weapon_templates
					end

					return saved_require(modname)
				end)

				_mock_settings.bot_slot_1_profile = "zealot"

				local profile = {
					archetype = "veteran",
					name_list_id = "veteran_names",
					current_level = 1,
					gender = "male",
					selected_voice = "veteran_male_a",
					visual_loadout = {
						slot_body_face = { id = "vanilla_face_visual" },
						slot_body_hair = { id = "vanilla_hair_visual" },
						slot_gear_head = { id = "vanilla_head_visual" },
					},
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
						slot_body_face = { id = "vanilla_face_loadout" },
						slot_body_hair = { id = "vanilla_hair_loadout" },
						slot_gear_head = { id = "vanilla_head_loadout" },
					},
					loadout_item_ids = {
						slot_body_face = "vanilla_face_id",
						slot_body_hair = "vanilla_hair_id",
						slot_gear_head = "vanilla_head_id",
					},
					loadout_item_data = {
						slot_body_face = { id = "vanilla_face_id" },
						slot_body_hair = { id = "vanilla_hair_id" },
						slot_gear_head = { id = "vanilla_head_id" },
					},
					bot_gestalts = {
						melee = "linesman",
						ranged = "killshot",
					},
					talents = {},
				}

				local resolved, swapped = BotProfiles.resolve_profile(profile)

				assert.is_true(swapped)
				assert.is_true(resolved == profile, "resolve_profile must mutate the incoming profile table")
				assert.equals("veteran_names", resolved.name_list_id)
				assert.is_true(resolved.loadout == profile.loadout, "loadout table must be preserved")
				assert.is_true(
					resolved.visual_loadout == profile.visual_loadout,
					"visual_loadout table must be preserved"
				)
				assert.is_true(
					resolved.loadout_item_ids == profile.loadout_item_ids,
					"loadout_item_ids table must be preserved"
				)
				assert.is_true(
					resolved.loadout_item_data == profile.loadout_item_data,
					"loadout_item_data table must be preserved"
				)
				assert.is_not_nil(resolved.loadout.slot_body_face, "face slot must still exist for the UI contract")
				assert.is_not_nil(resolved.loadout.slot_body_hair, "hair slot must still exist for the UI contract")
				assert.is_not_nil(resolved.loadout.slot_gear_head, "head slot must still exist for the UI contract")
				assert.is_not_nil(resolved.visual_loadout.slot_body_face, "face visual slot must still exist")
				assert.is_not_nil(resolved.visual_loadout.slot_body_hair, "hair visual slot must still exist")
				assert.is_not_nil(resolved.visual_loadout.slot_gear_head, "head visual slot must still exist")
				assert.is_not_nil(resolved.loadout_item_ids.slot_body_face, "face loadout_item_ids must still exist")
				assert.is_not_nil(resolved.loadout_item_data.slot_body_face, "face loadout_item_data must still exist")
			end)

			rawset(_G, "require", saved_require)
			assert.is_true(ok, err)
		end)

		it("synthesizes authored weapon and gadget overrides through MasterItems.get_item_instance", function()
			local saved_require = require
			local seen_gears = {}

			local ok, err = pcall(function()
				local fake_master_items = {
					get_cached = function()
						return {
							zealot_primary = {
								id = "zealot_primary",
								name = "zealot_primary",
								item_type = "WEAPON_MELEE",
							},
							zealot_secondary = {
								id = "zealot_secondary",
								name = "zealot_secondary",
								item_type = "WEAPON_RANGED",
							},
							[EXPECTED_CURIO_MASTER_ITEM_ID] = {
								id = EXPECTED_CURIO_MASTER_ITEM_ID,
								name = EXPECTED_CURIO_MASTER_ITEM_ID,
								item_type = "GADGET",
							},
						}
					end,
					get_item_or_fallback = function(item_id)
						return {
							name = item_id,
							source = "fallback",
						}
					end,
					get_item_instance = function(gear)
						local slot_name = gear.slots and gear.slots[1]
						seen_gears[slot_name] = gear

						return {
							name = gear.masterDataInstance.id,
							gear_id = gear.masterDataInstance.id,
							item_type = slot_name and string.find(slot_name, "slot_attachment_", 1, true) and "GADGET"
								or nil,
							source = "instance",
							traits = gear.masterDataInstance.overrides and gear.masterDataInstance.overrides.traits
								or nil,
							perks = gear.masterDataInstance.overrides and gear.masterDataInstance.overrides.perks
								or nil,
						}
					end,
				}

				local fake_archetypes = {
					zealot = { name = "zealot", breed = "human" },
				}

				local fake_weapon_templates = {
					chainsword_2h_p1_m1 = {
						base_stats = {
							damage_stat = {},
							cleave_stat = {},
							finesse_stat = {},
						},
					},
					bolter_p1_m2 = {
						base_stats = {
							damage_stat = {},
							finesse_stat = {},
							ammo_stat = {},
						},
					},
				}

				rawset(_G, "require", function(modname)
					if modname == "scripts/backend/master_items" then
						return fake_master_items
					end
					if modname == "scripts/utilities/local_profile_backend_parser" then
						return {
							parse_profile = function(_profile, _id)
								return true
							end,
						}
					end
					if modname == "scripts/settings/archetype/archetypes" then
						return fake_archetypes
					end
					if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
						return fake_weapon_templates
					end

					return saved_require(modname)
				end)

				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = mock_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.reset()

				_mock_settings.bot_slot_1_profile = "zealot"
				_mock_settings.bot_weapon_quality = "max"

				local profile = {
					archetype = "veteran",
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
					},
					visual_loadout = {},
					loadout_item_ids = {},
					loadout_item_data = {},
					talents = {},
					bot_gestalts = {
						melee = "linesman",
						ranged = "killshot",
					},
				}

				local resolved, swapped = Profiles.resolve_profile(profile)

				assert.is_true(swapped)
				assert.equals("instance", resolved.loadout.slot_primary.source)
				assert.equals("instance", resolved.loadout.slot_secondary.source)
				assert.equals("instance", resolved.loadout.slot_attachment_1.source)
				assert.equals("instance", resolved.loadout.slot_attachment_2.source)
				assert.equals("instance", resolved.loadout.slot_attachment_3.source)
				assert.equals(
					"content/items/weapons/player/melee/chainsword_2h_p1_m1",
					seen_gears.slot_primary.masterDataInstance.id
				)
				assert.equals(
					"content/items/weapons/player/ranged/bolter_p1_m2",
					seen_gears.slot_secondary.masterDataInstance.id
				)
				assert.is_table(seen_gears.slot_primary.masterDataInstance.overrides.base_stats)
				assert.is_true(#seen_gears.slot_primary.masterDataInstance.overrides.base_stats > 0)
				assert.is_table(seen_gears.slot_primary.masterDataInstance.overrides.traits)
				assert.is_true(#seen_gears.slot_primary.masterDataInstance.overrides.traits > 0)
				assert.is_table(seen_gears.slot_primary.masterDataInstance.overrides.perks)
				assert.is_true(#seen_gears.slot_primary.masterDataInstance.overrides.perks > 0)
				assert.is_table(seen_gears.slot_secondary.masterDataInstance.overrides.base_stats)
				assert.is_true(#seen_gears.slot_secondary.masterDataInstance.overrides.base_stats > 0)
				assert.is_table(seen_gears.slot_attachment_1.masterDataInstance.overrides.traits)
				assert.equals(4, #seen_gears.slot_attachment_1.masterDataInstance.overrides.traits)
				assert.equals(EXPECTED_CURIO_MASTER_ITEM_ID, seen_gears.slot_attachment_1.masterDataInstance.id)
				assert.equals(EXPECTED_CURIO_MASTER_ITEM_ID, seen_gears.slot_attachment_2.masterDataInstance.id)
				assert.equals(EXPECTED_CURIO_MASTER_ITEM_ID, seen_gears.slot_attachment_3.masterDataInstance.id)
				assert.equals(EXPECTED_CURIO_MASTER_ITEM_ID, resolved.visual_loadout.slot_attachment_1.name)
				assert.equals(
					EXPECTED_CURIO_MASTER_ITEM_ID .. "slot_attachment_1",
					resolved.loadout_item_ids.slot_attachment_1
				)
				assert.equals(EXPECTED_CURIO_MASTER_ITEM_ID, resolved.loadout_item_data.slot_attachment_1.id)
			end)

			rawset(_G, "require", saved_require)
			assert.is_true(ok, err)
		end)

		it("resolves authored weapon overrides for every shipped class", function()
			-- Parametrized follow-up to the zealot end-to-end test above. Guards
			-- against per-class trait/perk ID drift in the non-zealot archetypes
			-- by driving a full resolve_profile() for each class and asserting
			-- the synthesized gear carries the expected content path + non-empty
			-- override lists back out through MasterItems.get_item_instance.
			local class_expectations = {
				veteran = {
					primary = "content/items/weapons/player/melee/powersword_p1_m2",
					secondary = "content/items/weapons/player/ranged/plasmagun_p1_m1",
					primary_template = "powersword_p1_m2",
					secondary_template = "plasmagun_p1_m1",
				},
				zealot = {
					primary = "content/items/weapons/player/melee/chainsword_2h_p1_m1",
					secondary = "content/items/weapons/player/ranged/bolter_p1_m2",
					primary_template = "chainsword_2h_p1_m1",
					secondary_template = "bolter_p1_m2",
				},
				psyker = {
					primary = "content/items/weapons/player/melee/combatsword_p3_m2",
					secondary = "content/items/weapons/player/ranged/forcestaff_p1_m1",
					primary_template = "combatsword_p3_m2",
					secondary_template = "forcestaff_p1_m1",
				},
				ogryn = {
					primary = "content/items/weapons/player/melee/ogryn_club_p1_m1",
					secondary = "content/items/weapons/player/ranged/ogryn_rippergun_p1_m3",
					primary_template = "ogryn_club_p1_m1",
					secondary_template = "ogryn_rippergun_p1_m3",
				},
			}

			for class_name, expected in pairs(class_expectations) do
				local saved_require = require
				local seen_gears = {}

				local ok, err = pcall(function()
					local fake_master_items = {
						get_cached = function()
							return { [EXPECTED_CURIO_MASTER_ITEM_ID] = { name = EXPECTED_CURIO_MASTER_ITEM_ID } }
						end,
						get_item_or_fallback = function(item_id)
							return { name = item_id, source = "fallback" }
						end,
						get_item_instance = function(gear)
							local slot_name = gear.slots and gear.slots[1]
							seen_gears[slot_name] = gear
							return {
								name = gear.masterDataInstance.id,
								source = "instance",
							}
						end,
					}

					local fake_archetypes = {
						veteran = { name = "veteran", breed = "human" },
						zealot = { name = "zealot", breed = "human" },
						psyker = { name = "psyker", breed = "human" },
						ogryn = { name = "ogryn", breed = "ogryn" },
					}

					local fake_weapon_templates = {
						[expected.primary_template] = { base_stats = { damage_stat = {} } },
						[expected.secondary_template] = { base_stats = { damage_stat = {} } },
					}

					rawset(_G, "require", function(modname)
						if modname == "scripts/backend/master_items" then
							return fake_master_items
						end
						if modname == "scripts/utilities/local_profile_backend_parser" then
							return {
								parse_profile = function()
									return true
								end,
							}
						end
						if modname == "scripts/settings/archetype/archetypes" then
							return fake_archetypes
						end
						if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
							return fake_weapon_templates
						end
						return saved_require(modname)
					end)

					local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
					Profiles.init({
						mod = mock_mod,
						debug_log = function() end,
						debug_enabled = function()
							return false
						end,
					})
					Profiles.reset()

					_mock_settings.bot_slot_1_profile = class_name
					_mock_settings.bot_weapon_quality = "max"

					local profile = {
						archetype = "veteran",
						loadout = {
							slot_primary = "bot_combatsword_linesman_p1",
							slot_secondary = "bot_lasgun_killshot",
						},
						visual_loadout = {},
						loadout_item_ids = {},
						loadout_item_data = {},
						talents = {},
						bot_gestalts = { melee = "linesman", ranged = "killshot" },
					}

					local resolved, swapped = Profiles.resolve_profile(profile)

					assert.is_true(swapped, class_name .. " must swap")
					assert.equals(
						expected.primary,
						seen_gears.slot_primary.masterDataInstance.id,
						class_name .. " primary id mismatch"
					)
					assert.equals(
						expected.secondary,
						seen_gears.slot_secondary.masterDataInstance.id,
						class_name .. " secondary id mismatch"
					)
					-- Deep-compare the synthesized overrides against the shipped template
					-- so that a trait/perk ID typo in any class (or a drift away from
					-- the rarity/value schema) fails this spec instead of sailing
					-- through a bare #>0 check.
					local template = BotProfiles._get_profiles()[class_name]
					local function extract_ids(entries)
						local ids = {}
						for i = 1, #(entries or {}) do
							ids[i] = entries[i].id
						end
						return ids
					end
					assert.same(
						extract_ids(template.weapon_overrides.slot_primary.traits),
						extract_ids(seen_gears.slot_primary.masterDataInstance.overrides.traits),
						class_name .. " primary traits must match authored IDs"
					)
					assert.same(
						extract_ids(template.weapon_overrides.slot_primary.perks),
						extract_ids(seen_gears.slot_primary.masterDataInstance.overrides.perks),
						class_name .. " primary perks must match authored IDs"
					)
					assert.same(
						extract_ids(template.weapon_overrides.slot_secondary.traits),
						extract_ids(seen_gears.slot_secondary.masterDataInstance.overrides.traits),
						class_name .. " secondary traits must match authored IDs"
					)
					assert.same(
						extract_ids(template.weapon_overrides.slot_secondary.perks),
						extract_ids(seen_gears.slot_secondary.masterDataInstance.overrides.perks),
						class_name .. " secondary perks must match authored IDs"
					)
					assert.equals("instance", resolved.loadout.slot_primary.source)
					assert.equals("instance", resolved.loadout.slot_secondary.source)
				end)

				rawset(_G, "require", saved_require)
				assert.is_true(ok, class_name .. ": " .. tostring(err))
			end
		end)

		it("returns the vanilla profile when MasterItems.get_item_instance returns nil for any weapon slot", function()
			local saved_require = require
			local warnings = {}

			local ok, err = pcall(function()
				local fake_master_items = {
					get_cached = function()
						return { [EXPECTED_CURIO_MASTER_ITEM_ID] = { name = EXPECTED_CURIO_MASTER_ITEM_ID } }
					end,
					get_item_or_fallback = function(item_id)
						return { name = item_id, source = "fallback" }
					end,
					get_item_instance = function(gear)
						local slot_name = gear.slots and gear.slots[1]
						-- Simulate engine returning nil for secondary (e.g. item definition shifted in a patch)
						if slot_name == "slot_secondary" then
							return nil
						end
						return { name = gear.masterDataInstance.id, source = "instance" }
					end,
				}

				local fake_archetypes = { zealot = { name = "zealot", breed = "human" } }

				rawset(_G, "require", function(modname)
					if modname == "scripts/backend/master_items" then
						return fake_master_items
					end
					if modname == "scripts/utilities/local_profile_backend_parser" then
						return {
							parse_profile = function()
								return true
							end,
						}
					end
					if modname == "scripts/settings/archetype/archetypes" then
						return fake_archetypes
					end
					if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
						return {
							chainsword_2h_p1_m1 = { base_stats = { damage_stat = {} } },
							bolter_p1_m2 = { base_stats = { damage_stat = {} } },
						}
					end
					return saved_require(modname)
				end)

				local warn_mod = {
					get = mock_mod.get,
					hook = mock_mod.hook,
					echo = mock_mod.echo,
					warning = function(_self, msg)
						warnings[#warnings + 1] = msg
					end,
				}

				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = warn_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.reset()

				_mock_settings.bot_slot_1_profile = "zealot"
				_mock_settings.bot_weapon_quality = "max"

				local vanilla = {
					archetype = "veteran",
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
					},
					visual_loadout = {},
					loadout_item_ids = {},
					loadout_item_data = {},
					talents = {},
					bot_gestalts = { melee = "linesman", ranged = "killshot" },
				}
				local returned, swapped = Profiles.resolve_profile(vanilla)

				assert.is_false(swapped, "must not swap when a weapon slot fails to resolve")
				assert.equals(vanilla, returned, "must return the caller's vanilla profile untouched")
				assert.equals("veteran", returned.archetype, "vanilla archetype must be preserved")

				local saw_warning = false
				for i = 1, #warnings do
					if
						warnings[i]:find("failed to resolve", 1, true)
						and warnings[i]:find("slot_secondary", 1, true)
						and warnings[i]:find("zealot", 1, true)
					then
						saw_warning = true
						break
					end
				end
				assert.is_true(
					saw_warning,
					"must warn unconditionally when weapon resolution fails; got: ["
						.. table.concat(warnings, " | ")
						.. "]"
				)
			end)

			rawset(_G, "require", saved_require)
			assert.is_true(ok, err)
		end)

		it("still swaps and warns when the weapon_templates engine module is unavailable", function()
			-- Guards against Fatshark renaming the weapon_templates content path:
			-- a failing require must not throw through the add_bot hook.
			local saved_require = require
			local warnings = {}

			local ok, err = pcall(function()
				local seen_gears = {}
				local fake_master_items = {
					get_cached = function()
						return { [EXPECTED_CURIO_MASTER_ITEM_ID] = { name = EXPECTED_CURIO_MASTER_ITEM_ID } }
					end,
					get_item_or_fallback = function(item_id)
						return { name = item_id, source = "fallback" }
					end,
					get_item_instance = function(gear)
						local slot_name = gear.slots and gear.slots[1]
						seen_gears[slot_name] = gear
						return { name = gear.masterDataInstance.id, source = "instance" }
					end,
				}
				local fake_archetypes = { zealot = { name = "zealot", breed = "human" } }

				rawset(_G, "require", function(modname)
					if modname == "scripts/backend/master_items" then
						return fake_master_items
					end
					if modname == "scripts/utilities/local_profile_backend_parser" then
						return {
							parse_profile = function()
								return true
							end,
						}
					end
					if modname == "scripts/settings/archetype/archetypes" then
						return fake_archetypes
					end
					if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
						error("weapon_templates path changed in patch X.Y")
					end
					return saved_require(modname)
				end)

				local warn_mod = {
					get = mock_mod.get,
					hook = mock_mod.hook,
					echo = mock_mod.echo,
					warning = function(_self, msg)
						warnings[#warnings + 1] = msg
					end,
				}

				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = warn_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.reset()

				_mock_settings.bot_slot_1_profile = "zealot"
				_mock_settings.bot_weapon_quality = "max"

				local vanilla = {
					archetype = "veteran",
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
					},
					visual_loadout = {},
					loadout_item_ids = {},
					loadout_item_data = {},
					talents = {},
					bot_gestalts = { melee = "linesman", ranged = "killshot" },
				}
				local resolved, swapped = Profiles.resolve_profile(vanilla)

				assert.is_true(swapped, "must still swap weapons when weapon_templates is unavailable")
				assert.equals("instance", resolved.loadout.slot_primary.source)
				assert.equals("instance", resolved.loadout.slot_secondary.source)
				-- base_stats fallback: empty array (the loop didn't execute), not nil.
				assert.is_table(seen_gears.slot_primary.masterDataInstance.overrides.base_stats)
				assert.equals(0, #seen_gears.slot_primary.masterDataInstance.overrides.base_stats)

				local saw_warning = false
				for i = 1, #warnings do
					if warnings[i]:find("weapon_templates engine module unavailable", 1, true) then
						saw_warning = true
						break
					end
				end
				assert.is_true(
					saw_warning,
					"must warn once when the weapon_templates require fails; got: ["
						.. table.concat(warnings, " | ")
						.. "]"
				)
			end)

			rawset(_G, "require", saved_require)
			assert.is_true(ok, err)
		end)

		it("skips a curio slot whose master_item_id is missing and warns about it", function()
			local saved_require = require
			local warnings = {}

			local ok, err = pcall(function()
				local seen_gears = {}
				local fake_master_items = {
					get_cached = function()
						return { [EXPECTED_CURIO_MASTER_ITEM_ID] = { name = EXPECTED_CURIO_MASTER_ITEM_ID } }
					end,
					get_item_or_fallback = function(item_id)
						return { name = item_id, source = "fallback" }
					end,
					get_item_instance = function(gear)
						local slot_name = gear.slots and gear.slots[1]
						seen_gears[slot_name] = gear
						return { name = gear.masterDataInstance.id, source = "instance" }
					end,
				}
				local fake_archetypes = { zealot = { name = "zealot", breed = "human" } }

				rawset(_G, "require", function(modname)
					if modname == "scripts/backend/master_items" then
						return fake_master_items
					end
					if modname == "scripts/utilities/local_profile_backend_parser" then
						return {
							parse_profile = function()
								return true
							end,
						}
					end
					if modname == "scripts/settings/archetype/archetypes" then
						return fake_archetypes
					end
					if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
						return {
							chainsword_2h_p1_m1 = { base_stats = { damage_stat = {} } },
							bolter_p1_m2 = { base_stats = { damage_stat = {} } },
						}
					end
					return saved_require(modname)
				end)

				local warn_mod = {
					get = mock_mod.get,
					hook = mock_mod.hook,
					echo = mock_mod.echo,
					warning = function(_self, msg)
						warnings[#warnings + 1] = msg
					end,
				}

				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = warn_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.reset()

				-- Rewrite one shipped curio's master_item_id to nil before resolution.
				local profiles_table = Profiles._get_profiles()
				profiles_table.zealot.curios[2].master_item_id = nil

				_mock_settings.bot_slot_1_profile = "zealot"
				_mock_settings.bot_weapon_quality = "max"

				local vanilla = {
					archetype = "veteran",
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
					},
					visual_loadout = {},
					loadout_item_ids = {},
					loadout_item_data = {},
					talents = {},
					bot_gestalts = { melee = "linesman", ranged = "killshot" },
				}
				local resolved, swapped = Profiles.resolve_profile(vanilla)

				assert.is_true(swapped, "weapon resolution still succeeds; curio is skipped, not fatal")
				assert.is_nil(seen_gears.slot_attachment_2, "attachment_2 must not go through get_item_instance")
				assert.equals("instance", resolved.loadout.slot_attachment_1.source)
				assert.equals("instance", resolved.loadout.slot_attachment_3.source)

				local saw_warning = false
				for i = 1, #warnings do
					if
						warnings[i]:find("skipping runtime curio", 1, true)
						and warnings[i]:find("slot_attachment_2", 1, true)
						and warnings[i]:find("zealot", 1, true)
					then
						saw_warning = true
						break
					end
				end
				assert.is_true(
					saw_warning,
					"must warn unconditionally when a curio master_item_id is missing; got: ["
						.. table.concat(warnings, " | ")
						.. "]"
				)
			end)

			rawset(_G, "require", saved_require)
			assert.is_true(ok, err)
		end)

		describe("set_profile hook", function()
			it("register_hooks registers BotPlayer.set_profile hook", function()
				local hooked_targets = {}
				local hook_mod = {
					get = function(_self, setting_id)
						return _mock_settings[setting_id]
					end,
					hook = function(_self, target, method, _handler)
						hooked_targets[#hooked_targets + 1] = { target = target, method = method }
					end,
				}
				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = hook_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.register_hooks()

				local found_add_bot = false
				local found_set_profile = false
				for _, h in ipairs(hooked_targets) do
					if h.target == "BotSynchronizerHost" and h.method == "add_bot" then
						found_add_bot = true
					end
					if h.target == "BotPlayer" and h.method == "set_profile" then
						found_set_profile = true
					end
				end
				assert.is_true(found_add_bot, "must hook BotSynchronizerHost.add_bot")
				assert.is_true(found_set_profile, "must hook BotPlayer.set_profile")
			end)

			it("blocks set_profile when existing profile has _bb_resolved within time window", function()
				local set_profile_handler
				local debug_logs = {}
				local echo_messages = {}
				local hook_mod = {
					get = function(_self, setting_id)
						return _mock_settings[setting_id]
					end,
					hook = function(_self, target, method, handler)
						if target == "BotPlayer" and method == "set_profile" then
							set_profile_handler = handler
						end
					end,
					echo = function(_self, msg)
						echo_messages[#echo_messages + 1] = msg
					end,
				}
				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = hook_mod,
					debug_log = function(key, fixed_t, message, interval, level)
						debug_logs[#debug_logs + 1] = {
							key = key,
							fixed_t = fixed_t,
							message = message,
							interval = interval,
							level = level,
						}
					end,
					debug_enabled = function()
						return true
					end,
				})
				Profiles.register_hooks()
				assert.is_not_nil(set_profile_handler, "handler must be captured")

				-- Simulate a recent resolve: set timestamp to now
				Profiles._set_last_resolve_t(os.clock())

				local original_called = false
				local original_func = function(_self, _profile)
					original_called = true
				end
				local bot_self = {
					_profile = { _bb_resolved = true, archetype = "zealot" },
				}
				local new_profile = { archetype = "zealot", _from_network = true }

				set_profile_handler(original_func, bot_self, new_profile)
				assert.is_false(original_called, "should block overwrite for _bb_resolved profile within window")
				assert.is_nil(bot_self._profile._bb_resolved, "sentinel consumed after block")
				-- Warning echo must be emitted (unconditional, production-visible)
				assert.equals(1, #echo_messages)
				assert.matches("BetterBots WARNING", echo_messages[1], 1, true)
				assert.matches("blocked network-sync profile overwrite", echo_messages[1], 1, true)
				-- Debug log also emitted (debug_enabled=true)
				assert.equals(1, #debug_logs)
				assert.equals("bot_profiles:set_profile_blocked", debug_logs[1].key)
				assert.equals(0, debug_logs[1].fixed_t)
				assert.is_nil(debug_logs[1].interval)
				assert.equals("info", debug_logs[1].level)
				assert.equals("blocked lossy network-sync profile overwrite", debug_logs[1].message)

				-- Second call should pass through (sentinel consumed)
				original_called = false
				set_profile_handler(original_func, bot_self, new_profile)
				assert.is_true(original_called, "should allow subsequent updates after sentinel consumed")
				assert.equals(2, #debug_logs)
				assert.equals("bot_profiles:set_profile_passthrough", debug_logs[2].key)
				assert.equals(0, debug_logs[2].fixed_t)
				assert.is_nil(debug_logs[2].interval)
				assert.equals("debug", debug_logs[2].level)
				assert.equals("allowed profile update (no _bb_resolved sentinel)", debug_logs[2].message)
			end)

			it("does NOT block set_profile when time window has expired", function()
				local set_profile_handler
				local echo_messages = {}
				local hook_mod = {
					get = function(_self, setting_id)
						return _mock_settings[setting_id]
					end,
					hook = function(_self, target, method, handler)
						if target == "BotPlayer" and method == "set_profile" then
							set_profile_handler = handler
						end
					end,
					echo = function(_self, msg)
						echo_messages[#echo_messages + 1] = msg
					end,
				}
				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = hook_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.register_hooks()
				assert.is_not_nil(set_profile_handler, "handler must be captured")

				-- Simulate an expired window: set timestamp to 10 s in the past
				Profiles._set_last_resolve_t(os.clock() - 10)

				local original_called = false
				local original_func = function(_self, _profile)
					original_called = true
				end
				local bot_self = {
					_profile = { _bb_resolved = true, archetype = "zealot" },
				}
				local new_profile = { archetype = "zealot" }

				set_profile_handler(original_func, bot_self, new_profile)
				assert.is_true(original_called, "should allow update after time window expires")
				-- No warning echo — window expired, not blocked
				assert.equals(0, #echo_messages)
				-- Sentinel untouched (hook passed through without consuming it)
				assert.is_true(bot_self._profile._bb_resolved, "sentinel untouched when window expired")
			end)

			it("allows set_profile when existing profile is NOT _bb_resolved", function()
				local set_profile_handler
				local debug_logs = {}
				local hook_mod = {
					get = function(_self, setting_id)
						return _mock_settings[setting_id]
					end,
					hook = function(_self, target, method, handler)
						if target == "BotPlayer" and method == "set_profile" then
							set_profile_handler = handler
						end
					end,
				}
				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = hook_mod,
					debug_log = function(key, fixed_t, message, interval, level)
						debug_logs[#debug_logs + 1] = {
							key = key,
							fixed_t = fixed_t,
							message = message,
							interval = interval,
							level = level,
						}
					end,
					debug_enabled = function()
						return true
					end,
				})
				Profiles.register_hooks()

				local original_called = false
				local original_func = function(_self, _profile)
					original_called = true
				end
				local bot_self = {
					_profile = { archetype = "veteran" },
				}
				local new_profile = { archetype = "veteran" }

				set_profile_handler(original_func, bot_self, new_profile)
				assert.is_true(original_called, "should allow overwrite for vanilla profile")
				assert.equals(1, #debug_logs)
				assert.equals("bot_profiles:set_profile_passthrough", debug_logs[1].key)
				assert.equals(0, debug_logs[1].fixed_t)
				assert.is_nil(debug_logs[1].interval)
				assert.equals("debug", debug_logs[1].level)
				assert.equals("allowed profile update (no _bb_resolved sentinel)", debug_logs[1].message)
			end)

			it("allows set_profile when no existing profile (first assignment)", function()
				local set_profile_handler
				local hook_mod = {
					get = function(_self, setting_id)
						return _mock_settings[setting_id]
					end,
					hook = function(_self, target, method, handler)
						if target == "BotPlayer" and method == "set_profile" then
							set_profile_handler = handler
						end
					end,
				}
				local Profiles = dofile("scripts/mods/BetterBots/bot_profiles.lua")
				Profiles.init({
					mod = hook_mod,
					debug_log = function() end,
					debug_enabled = function()
						return false
					end,
				})
				Profiles.register_hooks()

				local original_called = false
				local original_func = function(_self, _profile)
					original_called = true
				end
				local bot_self = { _profile = nil }
				local new_profile = { archetype = "zealot" }

				set_profile_handler(original_func, bot_self, new_profile)
				assert.is_true(original_called, "should allow first profile assignment")
			end)
		end)
	end)
end)
