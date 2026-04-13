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
		target_enemy_position = nil,
		target_enemy_distance = nil,
		target_enemy_type = nil,
		priority_target_enemy = nil,
		opportunity_target_enemy = nil,
		urgent_target_enemy = nil,
		companion_unit = nil,
		companion_position = nil,
		target_ally_needs_aid = false,
		target_ally_distance = nil,
		target_ally_unit = nil,
		target_is_elite_special = false,
		target_is_monster = false,
		target_is_dormant_daemonhost = false,
		target_is_super_armor = false,
		allies_in_coherency = 0,
		avg_ally_toughness_pct = 1,
		max_ally_corruption_pct = 0,
		in_hazard = false,
		ally_interacting = false,
		ally_interaction_type = nil,
		ally_interacting_unit = nil,
		ally_interacting_distance = nil,
		ally_interaction_profile = nil,
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

local function _copy_table(source)
	local result = {}
	if source then
		for k, v in pairs(source) do
			result[k] = v
		end
	end
	return result
end

function M.make_player_unit_data_extension(components, overrides)
	local ext = {
		read_component = function(_, component_name)
			return components and components[component_name] or nil
		end,
	}

	if overrides then
		for k, v in pairs(overrides) do
			ext[k] = v
		end
	end

	return ext
end

function M.make_minion_unit_data_extension(breed, overrides)
	local resolved_breed = breed or {}
	local ext = {
		breed = function()
			return resolved_breed
		end,
		faction_name = function()
			return resolved_breed.faction_name
		end,
		is_companion = function()
			return resolved_breed.is_companion == true
		end,
		breed_name = function()
			return resolved_breed.name
		end,
		breed_size_variation = function()
			return resolved_breed.breed_size_variation
		end,
	}

	if overrides then
		for k, v in pairs(overrides) do
			ext[k] = v
		end
	end

	return ext
end

function M.make_player_locomotion_extension(overrides)
	local velocity = overrides and overrides.current_velocity or nil
	local ext = {
		current_velocity = function()
			return velocity
		end,
	}

	if overrides then
		for k, v in pairs(overrides) do
			ext[k] = v
		end
	end

	return ext
end

function M.make_minion_locomotion_extension(current_velocity, overrides)
	local ext = {
		current_velocity = function()
			return current_velocity
		end,
	}

	if overrides then
		for k, v in pairs(overrides) do
			ext[k] = v
		end
	end

	return ext
end

function M.make_script_unit_mock(extension_map)
	return {
		has_extension = function(unit, system_name)
			local exts = extension_map[unit]
			return exts and exts[system_name] or nil
		end,
		extension = function(unit, system_name)
			local exts = extension_map[unit]
			return exts and exts[system_name] or nil
		end,
	}
end

function M.copy_table(source)
	return _copy_table(source)
end

return M
