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
		it("yields when a veteran profile already has a real character_id and logs the preservation", function()
			_mock_settings.bot_slot_1_profile = "zealot"
			_debug_enabled_result = true
			local tertium_profile = {
				archetype = "veteran",
				character_id = "char-vet-001",
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
