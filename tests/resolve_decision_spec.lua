local helper = require("test_helper")

-- resolve_decision calls build_context which needs ScriptUnit
helper.setup_engine_stubs()

local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")

-- Init with minimal deps so build_context and caching work
local fixed_t = 100
Heuristics.init({
	fixed_time = function()
		return fixed_t
	end,
	decision_context_cache = {},
	super_armor_breed_cache = {},
	ARMOR_TYPE_SUPER_ARMOR = 6,
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

			local ok, rule = resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
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

			local ok, rule = resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
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

			local _, rule = resolve("veteran_combat_ability", conditions, "unit", nil, nil, nil, nil, false, ability_ext)
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

	describe("context is returned", function()
		it("always returns a context table as third value", function()
			local _, _, context = resolve("nonexistent_template", {}, "unit", nil, nil, nil, nil, false, nil)
			assert.is_table(context)
			assert.is_number(context.num_nearby)
			assert.is_number(context.health_pct)
			assert.is_number(context.toughness_pct)
		end)
	end)
end)
