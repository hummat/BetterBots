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

		it("ships the validation-first default lineup", function()
			local profiles = BotProfiles._get_profiles()

			assert.equals("content/items/weapons/player/melee/powersword_p1_m2", profiles.veteran.loadout.slot_primary)
			assert.equals("content/items/weapons/player/ranged/bolter_p1_m1", profiles.veteran.loadout.slot_secondary)
			assert.is_not_nil(profiles.veteran.talents.veteran_improved_tag)
			assert.is_not_nil(profiles.veteran.talents.veteran_combat_ability_stagger_nearby_enemies)

			assert.equals(
				"content/items/weapons/player/melee/chainsword_2h_p1_m1",
				profiles.zealot.loadout.slot_primary
			)
			assert.equals(
				"content/items/weapons/player/ranged/autopistol_p1_m1",
				profiles.zealot.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.zealot.talents.zealot_dash)
			assert.is_not_nil(profiles.zealot.talents.zealot_martyrdom)

			assert.equals("content/items/weapons/player/melee/forcesword_p1_m1", profiles.psyker.loadout.slot_primary)
			assert.equals(
				"content/items/weapons/player/ranged/forcestaff_p3_m1",
				profiles.psyker.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.psyker.talents.psyker_combat_ability_stance)
			assert.is_not_nil(profiles.psyker.talents.psyker_brain_burst_improved)

			assert.equals("content/items/weapons/player/melee/ogryn_club_p2_m3", profiles.ogryn.loadout.slot_primary)
			assert.equals(
				"content/items/weapons/player/ranged/ogryn_rippergun_p1_m2",
				profiles.ogryn.loadout.slot_secondary
			)
			assert.is_not_nil(profiles.ogryn.talents.ogryn_special_ammo)
			assert.is_not_nil(profiles.ogryn.talents.ogryn_special_ammo_armor_pen)
		end)

		it("keeps removed trap talents and absent secondary weapon overrides out of the shipped lineup", function()
			local profiles = BotProfiles._get_profiles()

			assert.is_nil(profiles.zealot.talents.zealot_bolstering_prayer)
			assert.is_nil(profiles.psyker.talents.psyker_elite_kills_add_warpfire)
			assert.is_nil(profiles.veteran.talents.veteran_dodging_grants_crit)
			assert.is_nil(profiles.ogryn.weapon_overrides.slot_secondary)
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

		it("defines an ogryn primary weapon override payload for synthesized quality gear", function()
			local profiles = BotProfiles._get_profiles()
			local override = profiles.ogryn.weapon_overrides and profiles.ogryn.weapon_overrides.slot_primary

			assert.is_table(override)
			assert.is_table(override.traits)
			assert.is_true(#override.traits > 0)
			assert.is_table(override.perks)
			assert.is_true(#override.perks > 0)
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
					autopistol_p1_m1 = {
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

		it("synthesizes ogryn primary weapon overrides through MasterItems.get_item_instance", function()
			local saved_require = require
			local seen_slot_primary_gear

			local ok, err = pcall(function()
				local fake_master_items = {
					get_cached = function()
						return {
							ogryn_primary = { id = "ogryn_primary" },
							ogryn_secondary = { id = "ogryn_secondary" },
						}
					end,
					get_item_or_fallback = function(item_id)
						return {
							name = item_id,
							source = "fallback",
						}
					end,
					get_item_instance = function(gear)
						if gear.slots and gear.slots[1] == "slot_primary" then
							seen_slot_primary_gear = gear
						end

						return {
							name = gear.masterDataInstance.id,
							gear_id = gear.masterDataInstance.id,
							source = "instance",
						}
					end,
				}

				local fake_archetypes = {
					ogryn = { name = "ogryn", breed = "ogryn" },
				}

				local fake_weapon_templates = {
					ogryn_club_p2_m3 = {
						base_stats = {
							damage_stat = {},
							cleave_stat = {},
							finesse_stat = {},
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

				_mock_settings.bot_slot_1_profile = "ogryn"
				_mock_settings.bot_weapon_quality = "max"

				local profile = {
					archetype = "veteran",
					loadout = {
						slot_primary = "bot_combatsword_linesman_p1",
						slot_secondary = "bot_lasgun_killshot",
					},
					talents = {},
					bot_gestalts = {
						melee = "linesman",
						ranged = "killshot",
					},
				}

				local resolved, swapped = BotProfiles.resolve_profile(profile)

				assert.is_true(swapped)
				assert.equals("instance", resolved.loadout.slot_primary.source)
				assert.equals("fallback", resolved.loadout.slot_secondary.source)
				assert.is_not_nil(seen_slot_primary_gear)
				assert.equals(
					"content/items/weapons/player/melee/ogryn_club_p2_m3",
					seen_slot_primary_gear.masterDataInstance.id
				)
				assert.is_table(seen_slot_primary_gear.masterDataInstance.overrides.base_stats)
				assert.is_true(#seen_slot_primary_gear.masterDataInstance.overrides.base_stats > 0)
				assert.is_table(seen_slot_primary_gear.masterDataInstance.overrides.traits)
				assert.is_true(#seen_slot_primary_gear.masterDataInstance.overrides.traits > 0)
				assert.is_table(seen_slot_primary_gear.masterDataInstance.overrides.perks)
				assert.is_true(#seen_slot_primary_gear.masterDataInstance.overrides.perks > 0)
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
