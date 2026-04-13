local helper = require("test_helper")

-- resolve_decision calls build_context which needs ScriptUnit
helper.setup_engine_stubs()

local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")

-- Init with minimal deps so build_context and caching work
local fixed_t = 100
Heuristics.init({
	fixed_time = function()
		return fixed_t
	end,
	decision_context_cache = {},
	super_armor_breed_cache = {},
	ARMOR_TYPE_SUPER_ARMOR = 6,
	combat_ability_identity = CombatAbilityIdentity,
})

local resolve = Heuristics.resolve_decision

describe("resolve_decision", function()
	before_each(function()
		-- Bump fixed_t to bust the per-tick cache
		fixed_t = fixed_t + 1
		Heuristics.init({
			fixed_time = function()
				return fixed_t
			end,
			decision_context_cache = {},
			super_armor_breed_cache = {},
			ARMOR_TYPE_SUPER_ARMOR = 6,
			combat_ability_identity = CombatAbilityIdentity,
		})
	end)

	teardown(function()
		helper.teardown_engine_stubs()
	end)

	describe("fallback_nearby", function()
		it("falls back to num_nearby check for unknown templates", function()
			-- ScriptUnit stub returns nil extensions, so build_context produces
			-- default context with num_nearby = 0 -> false
			local ok, rule, context = resolve("nonexistent_template", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_false(ok)
			-- rule chain shows original reason + fallback action
			assert.matches("fallback_unhandled_template", rule)
			assert.matches("fallback_nearby", rule)
			assert.is_not_nil(string.find(rule, "->", 1, true))
			assert.is_table(context)
			assert.equals(0, context.num_nearby)
		end)

		it("result is based on num_nearby", function()
			local ok, _ = resolve("nonexistent_template", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_false(ok) -- num_nearby=0 from stub -> false
		end)
	end)

	describe("fallback_veteran_vanilla", function()
		it("delegates to vanilla condition when heuristic returns nil", function()
			-- veteran_combat_ability with no class_tag -> returns nil
			-- -> fallback calls conditions._can_activate_veteran_ranger_ability
			local conditions = {
				_can_activate_veteran_ranger_ability = function()
					return true
				end,
			}
			local ability_ext = helper.make_veteran_ability_extension(nil, "something_unknown")

			local ok, rule =
				resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
			assert.is_true(ok)
			assert.matches("fallback_veteran_vanilla", rule)
		end)

		it("returns false when vanilla condition rejects", function()
			local conditions = {
				_can_activate_veteran_ranger_ability = function()
					return false
				end,
			}
			local ability_ext = helper.make_veteran_ability_extension(nil, "something_unknown")

			local ok, rule =
				resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
			assert.is_false(ok)
			assert.matches("fallback_veteran_vanilla", rule)
		end)

		it("appends to existing rule string", function()
			-- Unknown veteran variant produces rule like "veteran_variant_unknown"
			-- Fallback should append "->fallback_veteran_vanilla"
			local conditions = {
				_can_activate_veteran_ranger_ability = function()
					return true
				end,
			}
			local ability_ext = helper.make_veteran_ability_extension(nil, "something_unknown")

			local _, rule =
				resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
			assert.matches("veteran_variant", rule)
			assert.matches("fallback_veteran_vanilla", rule)
			assert.is_not_nil(string.find(rule, "->", 1, true))
		end)
	end)

	describe("known templates skip fallback", function()
		it("returns heuristic result directly for zealot_dash", function()
			-- Default context has no target_enemy -> zealot_dash blocks
			local ok, rule = resolve("zealot_dash", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_false(ok)
			assert.matches("zealot_dash_block_no_target", rule)
			-- Should NOT contain "fallback"
			assert.is_nil(string.find(rule, "fallback"))
		end)

		it("returns heuristic result for psyker_shout", function()
			-- Default context has num_nearby=0 -> blocks
			local ok, rule = resolve("psyker_shout", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_false(ok)
			assert.matches("psyker_shout_block_no_enemies", rule)
		end)
	end)

	describe("veteran threshold dispatch", function()
		-- Stub a perception_system that returns N enemies so build_context produces
		-- the surround pressure needed to distinguish VOC from stance thresholds.
		local _saved_has_extension
		local _num_enemies

		before_each(function()
			_saved_has_extension = _G.ScriptUnit.has_extension
			_G.ScriptUnit.has_extension = function(_unit, system_name)
				if system_name == "perception_system" then
					return helper.make_bot_perception_extension({
						num_enemies = _num_enemies or 0,
					})
				end

				return nil
			end
		end)

		after_each(function()
			_G.ScriptUnit.has_extension = _saved_has_extension
		end)

		it("dispatches squad_leader veteran to VOC thresholds (voc_surrounded at 4 enemies)", function()
			_num_enemies = 4
			local conditions = {
				_can_activate_veteran_ranger_ability = function()
					error("stance fallback must not be reached for squad_leader")
				end,
			}
			local ability_ext = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout")

			local ok, rule =
				resolve("veteran_combat_ability", conditions, "vet_bot_voc", nil, nil, nil, nil, false, ability_ext)

			assert.is_true(ok)
			assert.matches("veteran_voc_surrounded", rule)
			assert.is_nil(string.find(rule, "stance"))
			assert.is_nil(string.find(rule, "fallback_veteran_vanilla"))
		end)

		it("dispatches ranger veteran to stance thresholds (never VOC rule)", function()
			_num_enemies = 4
			local vanilla_called = false
			local conditions = {
				_can_activate_veteran_ranger_ability = function()
					vanilla_called = true
					return true
				end,
			}
			local ability_ext = helper.make_veteran_ability_extension("ranger", "veteran_combat_ability_stance")

			local ok, rule =
				resolve("veteran_combat_ability", conditions, "vet_bot_stance", nil, nil, nil, nil, false, ability_ext)

			assert.is_true(ok)
			assert.matches("veteran_stance", rule)
			assert.is_nil(string.find(rule, "voc"))
			assert.is_true(vanilla_called)
		end)
	end)

	describe("context is returned", function()
		it("always returns a context table as third value", function()
			local _, _, context = resolve("nonexistent_template", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_table(context)
			assert.is_number(context.num_nearby)
			assert.is_number(context.health_pct)
			assert.is_number(context.toughness_pct)
		end)
	end)

	-- Issue #17: Verify build_context actually populates the
	-- target_is_dormant_daemonhost flag from the target perception blackboard.
	-- The heuristic carve-out tests in heuristics_spec.lua inject the flag
	-- directly via make_context overrides; this test exercises the real
	-- BLACKBOARDS + perception read that runs in-game.
	describe("build_context dormant daemonhost flag (#17)", function()
		local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
		local _saved_has_extension
		local _saved_blackboards
		local _saved_alive

		before_each(function()
			_saved_has_extension = _G.ScriptUnit.has_extension
			_saved_blackboards = rawget(_G, "BLACKBOARDS")
			_saved_alive = rawget(_G, "ALIVE")

			-- Re-init with shared_rules so build_context consults
			-- DAEMONHOST_BREED_NAMES when inspecting target_breed.
			Heuristics.init({
				fixed_time = function()
					return fixed_t
				end,
				decision_context_cache = {},
				super_armor_breed_cache = {},
				ARMOR_TYPE_SUPER_ARMOR = 6,
				combat_ability_identity = CombatAbilityIdentity,
				shared_rules = SharedRules,
			})

			-- Stub unit_data_system for the DH target unit so _enemy_breed
			-- returns a chaos_daemonhost breed with monster tag.
			_G.ScriptUnit.has_extension = function(unit, system_name)
				if unit == "dh_unit" and system_name == "unit_data_system" then
					return helper.make_minion_unit_data_extension({
						name = "chaos_daemonhost",
						tags = { monster = true, witch = true },
					})
				end
				return nil
			end

			_G.BLACKBOARDS = {}
			_G.ALIVE = setmetatable({}, {
				__index = function()
					return true
				end,
			})
		end)

		after_each(function()
			_G.ScriptUnit.has_extension = _saved_has_extension
			_G.BLACKBOARDS = _saved_blackboards
			_G.ALIVE = _saved_alive
		end)

		it("sets flag true when DH has no perception blackboard (fail-safe dormant)", function()
			local blackboard = { perception = { target_enemy = "dh_unit" } }
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_true(ctx.target_is_monster)
			assert.is_true(ctx.target_is_dormant_daemonhost)
		end)

		it("sets flag true when DH perception aggro_state is passive", function()
			local blackboard = { perception = { target_enemy = "dh_unit" } }
			BLACKBOARDS["dh_unit"] = { perception = { aggro_state = "passive" } }
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_true(ctx.target_is_dormant_daemonhost)
		end)

		it("sets flag true when DH perception aggro_state is alerted", function()
			local blackboard = { perception = { target_enemy = "dh_unit" } }
			BLACKBOARDS["dh_unit"] = { perception = { aggro_state = "alerted" } }
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_true(ctx.target_is_dormant_daemonhost)
		end)

		it("clears flag when DH perception aggro_state is aggroed", function()
			local blackboard = { perception = { target_enemy = "dh_unit" } }
			BLACKBOARDS["dh_unit"] = { perception = { aggro_state = "aggroed" } }
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_true(ctx.target_is_monster)
			assert.is_false(ctx.target_is_dormant_daemonhost)
		end)

		it("clears flag when DH is aggroed on a different unit (global semantics)", function()
			-- The whole group commits once any DH enters aggroed — target_unit
			-- identity must not matter for the dormancy discriminator.
			local blackboard = { perception = { target_enemy = "dh_unit" } }
			BLACKBOARDS["dh_unit"] = {
				perception = { aggro_state = "aggroed", target_unit = "some_other_bot" },
			}
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_false(ctx.target_is_dormant_daemonhost)
		end)

		it("leaves flag false for non-daemonhost monster breeds", function()
			_G.ScriptUnit.has_extension = function(unit, system_name)
				if unit == "beast_unit" and system_name == "unit_data_system" then
					return helper.make_minion_unit_data_extension({
						name = "chaos_beast_of_nurgle",
						tags = { monster = true },
					})
				end
				return nil
			end

			local blackboard = { perception = { target_enemy = "beast_unit" } }
			BLACKBOARDS["beast_unit"] = { perception = { aggro_state = "passive" } }
			local ctx = Heuristics.build_context("bot1", blackboard)
			assert.is_true(ctx.target_is_monster)
			assert.is_false(ctx.target_is_dormant_daemonhost)
		end)
	end)
end)
