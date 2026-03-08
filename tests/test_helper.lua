-- Minimal test helper for BetterBots unit tests.
-- Pure sub-modules don't call engine globals at load time, so no stubs needed
-- for phase 1. This file provides shared context builders and mock factories.

local M = {}

-- Install a minimal ScriptUnit stub that returns nil for all extensions.
-- build_context() gracefully handles nil extensions and produces a default
-- context (all zeros/nils). Call teardown_engine_stubs() to restore.
local _saved_script_unit

function M.setup_engine_stubs()
	_saved_script_unit = rawget(_G, "ScriptUnit")
	_G.ScriptUnit = {
		has_extension = function()
			return nil
		end,
	}
end

function M.teardown_engine_stubs()
	_G.ScriptUnit = _saved_script_unit
	_saved_script_unit = nil
end

-- Build a default context table with sane defaults.
-- Override any field by passing a table of overrides.
function M.make_context(overrides)
	local ctx = {
		num_nearby = 0,
		challenge_rating_sum = 0,
		elite_count = 0,
		special_count = 0,
		monster_count = 0,
		ranged_count = 0,
		melee_count = 0,
		health_pct = 1,
		toughness_pct = 1,
		peril_pct = nil,
		target_enemy = nil,
		target_enemy_distance = nil,
		target_enemy_type = nil,
		priority_target_enemy = nil,
		opportunity_target_enemy = nil,
		urgent_target_enemy = nil,
		target_ally_needs_aid = false,
		target_ally_distance = nil,
		target_ally_unit = nil,
		target_is_elite_special = false,
		target_is_monster = false,
		target_is_super_armor = false,
		allies_in_coherency = 0,
		avg_ally_toughness_pct = 1,
		max_ally_corruption_pct = 0,
	}

	if overrides then
		for k, v in pairs(overrides) do
			ctx[k] = v
		end
	end

	return ctx
end

-- Build a mock ability_extension for veteran class_tag resolution.
function M.make_veteran_ability_extension(class_tag, ability_name)
	return {
		_equipped_abilities = {
			combat_ability = {
				name = ability_name or "",
				ability_template_tweak_data = class_tag and { class_tag = class_tag } or nil,
			},
		},
	}
end

-- Build a mock conditions table for veteran vanilla fallback.
function M.make_conditions(vanilla_result)
	return {
		_can_activate_veteran_ranger_ability = function()
			return vanilla_result
		end,
	}
end

return M
