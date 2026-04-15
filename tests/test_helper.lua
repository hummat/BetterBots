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
		target_daemonhost_aggro_state = nil,
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

local function _apply_audited_overrides(builder_name, ext, overrides, allowed_keys)
	if not overrides then
		return
	end

	for key, value in pairs(overrides) do
		if not allowed_keys[key] then
			error(
				string.format(
					"tests/test_helper.lua: unknown audited override key '%s' for %s",
					tostring(key),
					builder_name
				)
			)
		end

		ext[key] = value
	end
end

function M.make_player_unit_data_extension(components, overrides)
	local ext = {
		read_component = function(_, component_name)
			return components and components[component_name] or nil
		end,
	}

	_apply_audited_overrides("make_player_unit_data_extension", ext, overrides, {
		read_component = true,
		breed = true,
		breed_name = true,
		is_companion = true,
		is_resimulating = true,
	})

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

	_apply_audited_overrides("make_minion_unit_data_extension", ext, overrides, {
		breed = true,
		faction_name = true,
		is_companion = true,
		breed_name = true,
		breed_size_variation = true,
	})

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

function M.make_player_ability_extension(opts)
	opts = opts or {}
	local equipped_abilities = opts.equipped_abilities or opts._equipped_abilities or {}
	local ext = {
		can_use_ability = opts.can_use_ability or function(_, ability_type)
			if opts.can_use_by_type then
				return opts.can_use_by_type(ability_type)
			end
			if opts.can_use_ability_result ~= nil then
				return opts.can_use_ability_result
			end
			return true
		end,
		action_input_is_currently_valid = opts.action_input_is_currently_valid
			or function(_, _component_name, _action_input, _used_input, _current_fixed_t)
				if opts.action_input_is_currently_valid_result ~= nil then
					return opts.action_input_is_currently_valid_result
				end
				return true
			end,
		remaining_ability_charges = opts.remaining_ability_charges or function(_, _ability_type)
			return opts.remaining_ability_charges_value or 1
		end,
		_equipped_abilities = equipped_abilities,
	}

	_apply_audited_overrides("make_player_ability_extension", ext, opts.overrides, {
		can_use_ability = true,
		action_input_is_currently_valid = true,
		remaining_ability_charges = true,
		max_ability_charges = true,
		get_current_grenade_ability_name = true,
		ability_name = true,
		_equipped_abilities = true,
	})

	return ext
end

function M.make_player_action_input_extension(opts)
	opts = opts or {}
	local ext = {
		_action_input_parsers = opts.action_input_parsers or {},
		bot_queue_action_input = opts.bot_queue_action_input or function() end,
	}

	_apply_audited_overrides("make_player_action_input_extension", ext, opts.overrides, {
		bot_queue_action_input = true,
		_action_input_parsers = true,
	})

	return ext
end

function M.make_bot_perception_extension(opts)
	opts = opts or {}
	local enemies = opts.enemies or {}
	local num_enemies = opts.num_enemies
	local ext = {
		enemies_in_proximity = opts.enemies_in_proximity or function()
			return enemies, num_enemies or #enemies
		end,
	}

	_apply_audited_overrides("make_bot_perception_extension", ext, opts.overrides, {
		enemies_in_proximity = true,
	})

	return ext
end

function M.make_minion_perception_extension(opts)
	opts = opts or {}
	local has_line_of_sight = opts.has_line_of_sight
	local ext = {
		has_line_of_sight = opts.has_line_of_sight_fn
			or (type(has_line_of_sight) == "function" and has_line_of_sight)
			or function()
				if has_line_of_sight ~= nil then
					return has_line_of_sight
				end
				return true
			end,
	}

	_apply_audited_overrides("make_minion_perception_extension", ext, opts.overrides, {
		has_line_of_sight = true,
	})

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

function M.make_smart_tag_extension(tag_id, overrides)
	local ext = {
		tag_id = type(tag_id) == "function" and tag_id or function()
			return tag_id
		end,
	}

	_apply_audited_overrides("make_smart_tag_extension", ext, overrides, {
		tag_id = true,
	})

	return ext
end

function M.make_coherency_extension(current_radius, overrides)
	local ext = {
		current_radius = function()
			return current_radius
		end,
	}

	_apply_audited_overrides("make_coherency_extension", ext, overrides, {
		current_radius = true,
	})

	return ext
end

function M.make_player_talent_extension(opts)
	opts = opts or {}
	local special_rules = opts.special_rules or {}
	local ext = {
		has_special_rule = opts.has_special_rule or function(_, rule_name)
			if special_rules[rule_name] ~= nil then
				return special_rules[rule_name]
			end
			return false
		end,
	}

	_apply_audited_overrides("make_player_talent_extension", ext, opts.overrides, {
		has_special_rule = true,
	})

	return ext
end

function M.make_companion_spawner_extension(opts)
	opts = opts or {}
	local companion_units = opts.companion_units
	local should_have = opts.should_have_companion

	local ext = {
		should_have_companion = function()
			if should_have ~= nil then
				return should_have
			end
			return companion_units ~= nil and #companion_units > 0 or false
		end,
		companion_units = function()
			return companion_units
		end,
	}

	_apply_audited_overrides("make_companion_spawner_extension", ext, opts.overrides, {
		should_have_companion = true,
		companion_units = true,
	})

	return ext
end

function M.copy_table(source)
	return _copy_table(source)
end

return M
