-- Shared rule tables used across multiple BetterBots modules.
-- Keep duplicated gameplay identifiers here so drift becomes a single-file edit.
local M = {}

M.DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

M.DAEMONHOST_STAGE_AGGROED = 6

M.RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

-- Parser-level pre-check for bot ability inputs. Checks whether the action
-- input has a matching sequence config in the parser before falling back to
-- the action handler's action_input_is_currently_valid.
function M.action_input_is_bot_queueable(
	action_input_extension,
	ability_extension,
	ability_component_name,
	ability_template_name,
	action_input,
	used_input,
	fixed_t
)
	local parser = action_input_extension
		and action_input_extension._action_input_parsers
		and action_input_extension._action_input_parsers[ability_component_name]
	local sequence_configs = parser
		and parser._ACTION_INPUT_SEQUENCE_CONFIGS
		and parser._ACTION_INPUT_SEQUENCE_CONFIGS[ability_template_name]

	if sequence_configs and sequence_configs[action_input] then
		return true
	end

	return ability_extension:action_input_is_currently_valid(ability_component_name, action_input, used_input, fixed_t)
end

function M.daemonhost_state(target_unit)
	local target_blackboard = BLACKBOARDS and BLACKBOARDS[target_unit]
	local target_perception = target_blackboard and target_blackboard.perception
	local aggro_state = target_perception and target_perception.aggro_state or nil
	local managers_state = Managers and Managers.state
	local unit_spawner = managers_state and managers_state.unit_spawner
	local game_session_manager = managers_state and managers_state.game_session
	local game_session = game_session_manager
		and game_session_manager.game_session
		and game_session_manager:game_session()
	local game_object_id = unit_spawner and unit_spawner.game_object_id and unit_spawner:game_object_id(target_unit)
	local stage = nil

	local game_session_api = rawget(_G, "GameSession")
	if game_session and game_object_id ~= nil and game_session_api and game_session_api.game_object_field then
		stage = game_session_api.game_object_field(game_session, game_object_id, "stage")
	end

	return aggro_state, stage
end

function M.is_non_aggroed_daemonhost(target_unit)
	local aggro_state, stage = M.daemonhost_state(target_unit)
	if stage ~= nil then
		return stage < M.DAEMONHOST_STAGE_AGGROED, aggro_state, stage
	end
	if aggro_state ~= nil then
		return aggro_state ~= "aggroed", aggro_state, stage
	end
	return true, aggro_state, stage
end

return M
