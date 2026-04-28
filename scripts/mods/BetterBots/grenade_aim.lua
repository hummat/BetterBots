-- Grenade/blitz aim helpers: target retention, projectile metadata lookup,
-- ballistic trajectory solving, and BotUnitInput aim writes.
local M = {}

local _equipped_grenade_ability
local _mod
local _debug_log
local _debug_enabled
local _grenade_profiles
local _resolve_bot_target_unit_fn
local _resolve_precision_target_unit_fn
local _resolve_grenade_projectile_data
local _solve_ballistic_rotation
local _weapon_template_by_inventory_item_name
local _projectile_template_by_inventory_item_name
local _Trajectory
local _missing_los_method_warned

local BALLISTIC_GRAVITY_EPSILON = 0.5
local ACCEPTABLE_ACCURACY = 0.1

local EXCLUDED_FLAT_GRENADE_NAMES = {
	adamant_shock_mine = true,
	adamant_whistle = true,
	broker_missile_launcher = true,
	psyker_chain_lightning = true,
	psyker_smite = true,
	psyker_throwing_knives = true,
}

local function extract_projectile_template(weapon_template)
	if not weapon_template then
		return nil
	end

	if weapon_template.projectile_template then
		return weapon_template.projectile_template
	end

	local actions = weapon_template.actions
	if not actions then
		return nil
	end

	for _, action in pairs(actions) do
		if action.projectile_template then
			return action.projectile_template
		end
	end

	return nil
end

function M.prime_weapon_templates(WeaponTemplates)
	_weapon_template_by_inventory_item_name = {}

	for _, weapon_template in pairs(WeaponTemplates or {}) do
		local projectile_template = extract_projectile_template(weapon_template)
		local item_name = projectile_template and projectile_template.item_name
		if item_name and not _weapon_template_by_inventory_item_name[item_name] then
			_weapon_template_by_inventory_item_name[item_name] = weapon_template
		end
	end
end

local function weapon_template_by_item_name(inventory_item_name)
	if not inventory_item_name then
		return nil
	end

	if not _weapon_template_by_inventory_item_name then
		M.prime_weapon_templates(require("scripts/settings/equipment/weapon_templates/weapon_templates"))
	end

	return _weapon_template_by_inventory_item_name[inventory_item_name]
end

local function projectile_template_by_item_name(inventory_item_name)
	if not inventory_item_name then
		return nil
	end

	if not _projectile_template_by_inventory_item_name then
		_projectile_template_by_inventory_item_name = {}
		local ProjectileTemplates = require("scripts/settings/projectile/projectile_templates")

		for _, projectile_template in pairs(ProjectileTemplates) do
			local item_name = projectile_template and projectile_template.item_name
			if item_name and not _projectile_template_by_inventory_item_name[item_name] then
				_projectile_template_by_inventory_item_name[item_name] = projectile_template
			end
		end
	end

	return _projectile_template_by_inventory_item_name[inventory_item_name]
end

function M.resolve_grenade_projectile_data(unit, grenade_name)
	if EXCLUDED_FLAT_GRENADE_NAMES[grenade_name] then
		return {
			mode = "flat",
			reason = "excluded_family",
		}
	end

	local grenade_ability = _equipped_grenade_ability and select(2, _equipped_grenade_ability(unit))
	local inventory_item_name = grenade_ability and grenade_ability.inventory_item_name
	if not inventory_item_name then
		return {
			mode = "flat",
			reason = "inventory_item_missing",
		}
	end

	local weapon_template = weapon_template_by_item_name(inventory_item_name)
	local projectile_template = weapon_template and extract_projectile_template(weapon_template)
		or projectile_template_by_item_name(inventory_item_name)
	if not projectile_template then
		return {
			mode = "flat",
			reason = "projectile_template_missing",
		}
	end

	local locomotion_template = projectile_template and projectile_template.locomotion_template
	local integrator_parameters = locomotion_template and locomotion_template.integrator_parameters
	local trajectory_parameters = locomotion_template and locomotion_template.trajectory_parameters
	local throw_parameters = trajectory_parameters and trajectory_parameters.throw
	local spawn_parameters = locomotion_template and locomotion_template.spawn_projectile_parameters
	local speed = throw_parameters and (throw_parameters.speed_maximal or throw_parameters.speed_initial)
		or spawn_parameters and spawn_parameters.initial_speed
	local gravity = integrator_parameters and integrator_parameters.gravity

	if not speed then
		return {
			mode = "flat",
			reason = "speed_missing",
		}
	end

	if not gravity or gravity <= BALLISTIC_GRAVITY_EPSILON then
		return {
			mode = "flat",
			reason = "non_ballistic_projectile",
		}
	end

	return {
		mode = "ballistic",
		speed = speed,
		gravity = gravity,
	}
end

local function target_velocity(target_unit)
	-- Player units use PlayerUnitDataExtension (has read_component); minions use
	-- MinionUnitDataExtension (has breed/faction only). Guard the component path.
	local unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if unit_data_extension and unit_data_extension.read_component then
		local locomotion_component = unit_data_extension:read_component("locomotion")
		if locomotion_component and locomotion_component.velocity_current then
			return locomotion_component.velocity_current
		end
	end

	local locomotion_extension = ScriptUnit.has_extension(target_unit, "locomotion_system")
	if locomotion_extension and locomotion_extension.current_velocity then
		return locomotion_extension:current_velocity()
	end

	return Vector3.zero()
end

function M.solve_ballistic_rotation(unit, aim_unit, projectile_data)
	if not _Trajectory then
		_Trajectory = require("scripts/utilities/trajectory")
	end

	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit]
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[aim_unit]
	if not unit_position or not target_position then
		return nil, "position_lookup_missing"
	end

	local velocity = target_velocity(aim_unit)
	local angle, solved_target_position = _Trajectory.angle_to_hit_moving_target(
		unit_position,
		target_position,
		projectile_data.speed,
		velocity,
		projectile_data.gravity,
		ACCEPTABLE_ACCURACY,
		false
	)
	if not angle then
		return nil, "trajectory_solver_failed"
	end

	local delta_flat = Vector3.flat(solved_target_position - unit_position)
	if Vector3.length_squared(delta_flat) < 0.001 then
		return nil, "degenerate_direction"
	end
	local flat_direction = Vector3.normalize(delta_flat)
	local look_rotation = Quaternion.look(flat_direction, Vector3.up())
	return Quaternion.multiply(look_rotation, Quaternion(Vector3.right(), angle))
end

local function target_breed(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system") or nil
	return unit_data_extension and unit_data_extension:breed() or nil
end

function M.resolve_aim_unit(context, grenade_name)
	if _grenade_profiles.is_precision_target_grenade(grenade_name) and _resolve_precision_target_unit_fn then
		return _resolve_precision_target_unit_fn(context)
	end

	if _resolve_bot_target_unit_fn then
		return _resolve_bot_target_unit_fn(context)
	end

	if not context then
		return nil
	end

	return context.target_enemy
		or context.priority_target_enemy
		or context.opportunity_target_enemy
		or context.urgent_target_enemy
end

function M.unit_alive_state(unit)
	-- HEALTH_ALIVE is the authoritative liveness table for minions. ALIVE can lag or
	-- be absent on enemy units, so check HEALTH_ALIVE first whenever it exists.
	if HEALTH_ALIVE ~= nil then
		local alive = HEALTH_ALIVE[unit]
		if alive ~= nil then
			return alive == true, "health_alive"
		end
	end

	if ALIVE ~= nil then
		local alive = ALIVE[unit]
		if alive ~= nil then
			return alive == true, "alive"
		end
	end

	if Unit and Unit.alive then
		return Unit.alive(unit), "unit_alive"
	end

	return false, "unknown"
end

local function alive_label(alive)
	return alive and "alive" or "dead"
end

function M.aim_target_log_suffix(unit, aim_unit)
	local target_alive = nil
	local target_alive_source = nil
	if aim_unit then
		target_alive, target_alive_source = M.unit_alive_state(aim_unit)
	end

	local breed = aim_unit and target_breed(aim_unit) or nil
	local target_breed_name = breed and breed.name or "unknown"

	return " (bot="
		.. tostring(unit)
		.. ", target="
		.. tostring(aim_unit or "none")
		.. ", target_alive="
		.. (aim_unit and alive_label(target_alive) or "none")
		.. ", target_alive_source="
		.. tostring(target_alive_source or "none")
		.. ", target_breed="
		.. tostring(target_breed_name)
		.. ")"
end

function M.aim_target_log_key(base_key, unit, aim_unit)
	return base_key .. ":" .. tostring(unit) .. ":" .. tostring(aim_unit or "none")
end

local function unit_is_alive(unit)
	local alive = M.unit_alive_state(unit)

	return alive
end

function M.has_line_of_sight(unit, aim_unit)
	local target_perception_extension = ScriptUnit.has_extension(aim_unit, "perception_system")
	if not target_perception_extension then
		return true
	end

	if target_perception_extension.has_line_of_sight then
		return target_perception_extension:has_line_of_sight(unit)
	end

	if not _missing_los_method_warned and _mod and _mod.warning then
		_missing_los_method_warned = true
		_mod:warning("BetterBots: perception_system missing has_line_of_sight method for grenade aiming")
	end

	return true
end

function M.set_bot_aim(unit, aim_unit, grenade_name)
	if not aim_unit then
		return false, nil, "no_target_unit"
	end

	if not unit_is_alive(aim_unit) then
		return false, nil, "target_dead"
	end

	if not M.has_line_of_sight(unit, aim_unit) then
		return false, nil, "no_los"
	end

	if not POSITION_LOOKUP then
		return false, nil, "position_lookup_unavailable"
	end

	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local bot_unit_input = input_extension and input_extension.bot_unit_input and input_extension:bot_unit_input()
	if not bot_unit_input then
		return false, nil, "bot_input_missing"
	end

	local projectile_data = _resolve_grenade_projectile_data and _resolve_grenade_projectile_data(unit, grenade_name)
		or nil
	if projectile_data and projectile_data.mode == "ballistic" then
		local wanted_rotation, reason = _solve_ballistic_rotation(unit, aim_unit, projectile_data)
		if wanted_rotation then
			bot_unit_input:set_aiming(true, false, true)
			bot_unit_input:set_aim_rotation(wanted_rotation)

			return true, "ballistic", nil
		end

		local aim_position = POSITION_LOOKUP[aim_unit]
		if not aim_position then
			return false, nil, "target_position_missing"
		end

		bot_unit_input:set_aiming(true, false, false)
		bot_unit_input:set_aim_position(aim_position)

		return true, "flat", reason
	end

	local aim_position = POSITION_LOOKUP[aim_unit]
	if not aim_position then
		return false, nil, "target_position_missing"
	end

	bot_unit_input:set_aiming(true, false, false)
	bot_unit_input:set_aim_position(aim_position)

	return true, "flat", projectile_data and projectile_data.reason or "projectile_data_unavailable"
end

function M.clear_bot_aim(unit)
	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local bot_unit_input = input_extension and input_extension.bot_unit_input and input_extension:bot_unit_input()
	if not bot_unit_input then
		return false, "bot input missing"
	end

	bot_unit_input:set_aiming(false, false, false)
	return true
end

function M.refresh_bot_aim(unit, state, context, fixed_t)
	local resolved_aim_unit = M.resolve_aim_unit(context, state.grenade_name)
	local is_precision_target_grenade = _grenade_profiles.is_precision_target_grenade(state.grenade_name)
	local lost_dead_target = false
	local resolved_aim_alive, resolved_aim_state = nil, nil
	if resolved_aim_unit then
		resolved_aim_alive, resolved_aim_state = M.unit_alive_state(resolved_aim_unit)
	end
	if resolved_aim_unit and not resolved_aim_alive then
		resolved_aim_unit = nil
		lost_dead_target = resolved_aim_state ~= "unknown"
	end

	local retained_aim_alive, retained_aim_state = nil, nil
	if state.aim_unit then
		retained_aim_alive, retained_aim_state = M.unit_alive_state(state.aim_unit)
	end
	if state.aim_unit and not retained_aim_alive then
		state.aim_unit = nil
		lost_dead_target = lost_dead_target or retained_aim_state ~= "unknown"
	end

	if resolved_aim_unit then
		state.aim_unit = resolved_aim_unit
		state.precision_target_retained_logged = nil
	elseif is_precision_target_grenade and state.aim_unit and unit_is_alive(state.aim_unit) then
		if _debug_enabled() and not state.precision_target_retained_logged then
			state.precision_target_retained_logged = true
			_debug_log(
				"grenade_precision_target_retained:" .. tostring(unit),
				fixed_t,
				"grenade retained live precision target for " .. tostring(state.grenade_name)
			)
		end
	elseif is_precision_target_grenade then
		state.aim_unit = nil
		state.precision_target_retained_logged = nil
	end
	state.aim_distance = context and context.target_enemy_distance or nil

	if not state.aim_unit then
		if _debug_enabled() then
			if lost_dead_target then
				_debug_log(
					"grenade_aim_lost_dead:" .. tostring(unit),
					fixed_t,
					"grenade aim lost dead target for " .. tostring(state.grenade_name)
				)
			else
				_debug_log(
					M.aim_target_log_key("grenade_aim_no_target", unit, state.aim_unit),
					fixed_t,
					"grenade aim unavailable for "
						.. tostring(state.grenade_name)
						.. " (no target unit resolved)"
						.. M.aim_target_log_suffix(unit, state.aim_unit)
				)
			end
		end
		return false
	end

	local aim_ok, aim_mode, aim_reason = M.set_bot_aim(unit, state.aim_unit, state.grenade_name)
	if aim_ok then
		if _debug_enabled() then
			if aim_mode == "ballistic" then
				_debug_log(
					M.aim_target_log_key("grenade_aim_ballistic", unit, state.aim_unit),
					fixed_t,
					"grenade aim ballistic for "
						.. tostring(state.grenade_name)
						.. M.aim_target_log_suffix(unit, state.aim_unit)
				)
			else
				_debug_log(
					M.aim_target_log_key("grenade_aim_flat_fallback", unit, state.aim_unit),
					fixed_t,
					"grenade aim flat fallback for "
						.. tostring(state.grenade_name)
						.. " ("
						.. tostring(aim_reason)
						.. ")"
						.. M.aim_target_log_suffix(unit, state.aim_unit)
				)
			end
		end
		return true
	end

	if _debug_enabled() then
		_debug_log(
			M.aim_target_log_key("grenade_aim_unavailable", unit, state.aim_unit),
			fixed_t,
			"grenade aim unavailable for "
				.. tostring(state.grenade_name)
				.. " ("
				.. tostring(aim_reason)
				.. ")"
				.. M.aim_target_log_suffix(unit, state.aim_unit)
		)
	end

	return false
end

function M.init(deps)
	deps = deps or {}
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled or function()
		return false
	end
	_equipped_grenade_ability = deps.equipped_grenade_ability
	_grenade_profiles = deps.grenade_profiles
	_resolve_grenade_projectile_data = M.resolve_grenade_projectile_data
	_solve_ballistic_rotation = M.solve_ballistic_rotation
	_weapon_template_by_inventory_item_name = nil
	_projectile_template_by_inventory_item_name = nil
	_Trajectory = nil
	_missing_los_method_warned = nil
end

function M.wire(refs)
	refs = refs or {}
	local bot_targeting = refs.bot_targeting
	_equipped_grenade_ability = refs.equipped_grenade_ability or _equipped_grenade_ability
	_resolve_bot_target_unit_fn = bot_targeting and bot_targeting.resolve_bot_target_unit or nil
	_resolve_precision_target_unit_fn = bot_targeting and bot_targeting.resolve_precision_target_unit or nil
	_resolve_grenade_projectile_data = refs.resolve_grenade_projectile_data or M.resolve_grenade_projectile_data
	_solve_ballistic_rotation = refs.solve_ballistic_rotation or M.solve_ballistic_rotation
end

return M
