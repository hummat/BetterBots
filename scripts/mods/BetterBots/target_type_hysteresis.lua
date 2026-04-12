local M = {}

local MARGIN_FACTOR = 0.10 -- Score difference must exceed this fraction of max to flip type
local MOMENTUM_FACTOR = 0.05 -- Bonus added to current type's score to resist flipping
local REEVALUATION_INTERVAL_S = 0.3 -- Matches vanilla target reevaluation period

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _is_enabled
local _bot_target_selection
local _breed

local function _load_runtime_deps()
	if not _bot_target_selection then
		_bot_target_selection = require("scripts/utilities/bot_target_selection")
	end

	if not _breed then
		_breed = require("scripts/utilities/breed")
	end

	return _bot_target_selection, _breed
end

local function _abs(x)
	return x < 0 and -x or x
end

local function _max3(a, b, c)
	local ab = a > b and a or b
	return ab > c and ab or c
end

local function _calculate_common_score(unit, target_unit, target_breed, t, bot_group, current_target_enemy)
	local BotTargetSelection = _load_runtime_deps()
	local score = 0
	local opportunity_weight = BotTargetSelection.opportunity_weight(unit, target_unit, target_breed, t)
	score = score + opportunity_weight

	local priority_weight = BotTargetSelection.priority_weight(target_unit, bot_group)
	score = score + priority_weight

	local monster_weight = BotTargetSelection.monster_weight(unit, target_unit, target_breed, t)
	score = score + monster_weight

	local current_target_weight = BotTargetSelection.current_target_weight(target_unit, current_target_enemy)
	score = score + current_target_weight

	return score
end

local function _calculate_melee_score(unit, target_unit, melee_gestalt, target_breed, target_distance_sq, target_ally)
	local BotTargetSelection = _load_runtime_deps()
	local score = 0
	score = score + BotTargetSelection.gestalt_weight(melee_gestalt, target_breed)
	score = score + BotTargetSelection.slot_weight(unit, target_unit, target_distance_sq, target_breed, target_ally)
	score = score + BotTargetSelection.melee_distance_weight(target_distance_sq)

	return score
end

local function _calculate_ranged_score(
	unit,
	target_unit,
	ranged_gestalt,
	target_breed,
	target_distance_sq,
	_threat_units
)
	local BotTargetSelection = _load_runtime_deps()
	local score = 0
	score = score + BotTargetSelection.gestalt_weight(ranged_gestalt, target_breed)
	score = score + BotTargetSelection.ranged_distance_weight(target_distance_sq)
	score = score + BotTargetSelection.line_of_sight_weight(unit, target_unit)

	return score
end

local function _calculate_score(
	unit,
	target_unit,
	target_breed,
	target_distance_sq,
	melee_gestalt,
	ranged_gestalt,
	t,
	bot_group,
	current_target_enemy,
	target_ally,
	threat_units
)
	local common_score = _calculate_common_score(unit, target_unit, target_breed, t, bot_group, current_target_enemy)
	local melee_score = common_score
		+ _calculate_melee_score(unit, target_unit, melee_gestalt, target_breed, target_distance_sq, target_ally)
	local ranged_score = common_score
		+ _calculate_ranged_score(unit, target_unit, ranged_gestalt, target_breed, target_distance_sq, threat_units)

	return melee_score, ranged_score
end

local function _is_valid_target(target_unit, target_breed, aggroed_minion_target_units)
	local _, Breed = _load_runtime_deps()
	return not target_breed.not_bot_target
		and (aggroed_minion_target_units[target_unit] or Breed.is_player(target_breed))
end

local function _choose_raw_target_type(melee_score, ranged_score)
	return ranged_score < melee_score and "melee" or "ranged"
end

local function _collect_stabilized_choice(
	unit,
	unit_position,
	side,
	perception_component,
	behavior_component,
	target_units,
	t,
	threat_units,
	bot_group,
	current_target_enemy
)
	local melee_gestalt = behavior_component.melee_gestalt
	local ranged_gestalt = behavior_component.ranged_gestalt
	local aggroed_minion_target_units = side.aggroed_minion_target_units
	local target_ally = perception_component.target_ally
	local vector3_distance_squared = Vector3.distance_squared
	local position_lookup = POSITION_LOOKUP

	local best_melee_score, best_melee_target, best_melee_target_distance_sq = -math.huge, nil, math.huge
	local best_ranged_score, best_ranged_target, best_ranged_target_distance_sq = -math.huge, nil, math.huge

	local should_fully_reevaluate = not current_target_enemy or t > perception_component.target_enemy_reevaluation_t

	if should_fully_reevaluate then
		for i = 1, #target_units do
			local target_unit = target_units[i]
			local target_unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")

			if not target_unit_data_extension then
				goto continue
			end

			local target_breed = target_unit_data_extension:breed()

			if _is_valid_target(target_unit, target_breed, aggroed_minion_target_units) then
				local target_position = position_lookup[target_unit]

				if not target_position then
					goto continue
				end

				local target_distance_sq = vector3_distance_squared(unit_position, target_position)
				local melee_score, ranged_score = _calculate_score(
					unit,
					target_unit,
					target_breed,
					target_distance_sq,
					melee_gestalt,
					ranged_gestalt,
					t,
					bot_group,
					current_target_enemy,
					target_ally,
					threat_units
				)

				if best_melee_score < melee_score then
					best_melee_score, best_melee_target, best_melee_target_distance_sq =
						melee_score, target_unit, target_distance_sq
				end

				if best_ranged_score < ranged_score then
					best_ranged_score, best_ranged_target, best_ranged_target_distance_sq =
						ranged_score, target_unit, target_distance_sq
				end
			end

			::continue::
		end

		if not best_melee_target and not best_ranged_target then
			return nil
		end

		local chosen_type =
			M.choose_target_type(perception_component.target_enemy_type, best_melee_score, best_ranged_score)

		if chosen_type == "melee" then
			return {
				target_enemy = best_melee_target,
				target_enemy_distance = math.sqrt(best_melee_target_distance_sq),
				target_enemy_type = "melee",
			}
		end

		return {
			target_enemy = best_ranged_target,
			target_enemy_distance = math.sqrt(best_ranged_target_distance_sq),
			target_enemy_type = "ranged",
		}
	end

	if current_target_enemy then
		local target_unit = current_target_enemy
		local target_position = position_lookup[target_unit]

		if not target_position then
			return nil
		end

		local target_unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")

		if not target_unit_data_extension then
			return nil
		end

		local target_breed = target_unit_data_extension:breed()
		local target_distance_sq = vector3_distance_squared(unit_position, target_position)
		local melee_score, ranged_score = _calculate_score(
			unit,
			target_unit,
			target_breed,
			target_distance_sq,
			melee_gestalt,
			ranged_gestalt,
			t,
			bot_group,
			current_target_enemy,
			target_ally,
			threat_units
		)
		local chosen_type = M.choose_target_type(perception_component.target_enemy_type, melee_score, ranged_score)

		return {
			target_enemy = current_target_enemy,
			target_enemy_distance = math.sqrt(target_distance_sq),
			target_enemy_type = chosen_type,
		}
	end

	return nil
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_enabled = deps.is_enabled
end

function M.choose_target_type(current_type, melee_score, ranged_score)
	local raw_choice = _choose_raw_target_type(melee_score, ranged_score)
	if current_type ~= "melee" and current_type ~= "ranged" then
		return raw_choice
	end

	local stabilized_scale = _max3(_abs(melee_score), _abs(ranged_score), 1)
	local momentum_bonus = stabilized_scale * MOMENTUM_FACTOR
	local melee_stabilized = melee_score
	local ranged_stabilized = ranged_score

	if current_type == "melee" then
		melee_stabilized = melee_stabilized + momentum_bonus
	else
		ranged_stabilized = ranged_stabilized + momentum_bonus
	end

	local margin = stabilized_scale * MARGIN_FACTOR
	local candidate = _choose_raw_target_type(melee_stabilized, ranged_stabilized)
	if candidate == current_type then
		return current_type
	end

	local winner = candidate == "melee" and melee_stabilized or ranged_stabilized
	local loser = candidate == "melee" and ranged_stabilized or melee_stabilized
	if winner - loser > margin then
		return candidate
	end

	return current_type
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template",
		function(target_selection_template)
			local original = target_selection_template.bot_default

			target_selection_template.bot_default = function(
				unit,
				unit_position,
				side,
				perception_component,
				behavior_component,
				breed,
				target_units,
				t,
				threat_units,
				bot_group,
				target_selection_debug_info_or_nil
			)
				local previous_target_enemy = perception_component.target_enemy
				previous_target_enemy = HEALTH_ALIVE[previous_target_enemy] and previous_target_enemy or nil
				local previous_target_type = perception_component.target_enemy_type
				local previous_reevaluation_t = perception_component.target_enemy_reevaluation_t

				original(
					unit,
					unit_position,
					side,
					perception_component,
					behavior_component,
					breed,
					target_units,
					t,
					threat_units,
					bot_group,
					target_selection_debug_info_or_nil
				)

				local ok, err = pcall(function()
					if _is_enabled and not _is_enabled() then
						return
					end

					local reevaluation_view = {
						target_enemy = previous_target_enemy,
						target_enemy_type = previous_target_type,
						target_enemy_reevaluation_t = previous_reevaluation_t,
						target_ally = perception_component.target_ally,
					}
					local stabilized = _collect_stabilized_choice(
						unit,
						unit_position,
						side,
						reevaluation_view,
						behavior_component,
						target_units,
						t,
						threat_units,
						bot_group,
						previous_target_enemy
					)

					if not stabilized then
						return
					end

					perception_component.target_enemy = stabilized.target_enemy
					perception_component.target_enemy_distance = stabilized.target_enemy_distance
					perception_component.target_enemy_type = stabilized.target_enemy_type

					if previous_target_type ~= stabilized.target_enemy_type and _debug_enabled and _debug_enabled() then
						_debug_log(
							"target_type_flip:" .. tostring(unit),
							_fixed_time and _fixed_time() or t or 0,
							"type flip "
								.. tostring(previous_target_type)
								.. " -> "
								.. tostring(stabilized.target_enemy_type),
							nil,
							"debug"
						)
					end

					if previous_target_enemy == nil or t > previous_reevaluation_t then
						perception_component.target_enemy_reevaluation_t = t + REEVALUATION_INTERVAL_S
					end
				end)

				if not ok and _debug_enabled and _debug_enabled() then
					_debug_log(
						"target_type_hysteresis_error:" .. tostring(unit),
						_fixed_time and _fixed_time() or t or 0,
						tostring(err),
						nil,
						"debug"
					)
				end
			end
		end
	)
end

return M
