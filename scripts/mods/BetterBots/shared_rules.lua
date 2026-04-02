-- Shared rule tables used across multiple BetterBots modules.
-- Keep duplicated gameplay identifiers here so drift becomes a single-file edit.
local M = {}

M.DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

M.RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

-- Parser-level validation for bot ability inputs. Checks whether the action
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

return M
