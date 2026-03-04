local mod = get_mod("BotAbilities")

-- Ability templates that already have ability_meta_data and just need the
-- whitelist gate removed in can_activate_ability. All use action_input = "stance_pressed".
local TIER1_TEMPLATES = {
	veteran_stealth_combat_ability = true,
	psyker_overcharge_stance = true,
	ogryn_gunlugger_stance = true,
	adamant_stance = true,
	broker_focus = true,
	broker_punk_rage = true,
}

-- Tier 2: templates that exist but lack ability_meta_data.
-- We inject it at load time so the BT node can read activation data.
local TIER2_META_DATA = {
	zealot_invisibility = {
		activation = { action_input = "stance_pressed" },
	},
	zealot_dash = {
		activation = { action_input = "stance_pressed" },
	},
	ogryn_charge = {
		activation = { action_input = "stance_pressed" },
		end_condition = { done_when_arriving_at_destination = true },
	},
	ogryn_taunt_shout = {
		activation = { action_input = "stance_pressed" },
	},
	psyker_shout = {
		activation = { action_input = "stance_pressed" },
	},
	adamant_shout = {
		activation = { action_input = "stance_pressed" },
	},
	adamant_charge = {
		activation = { action_input = "stance_pressed" },
		end_condition = { done_when_arriving_at_destination = true },
	},
}

-- Inject ability_meta_data into templates that are missing it.
local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")

for template_name, meta_data in pairs(TIER2_META_DATA) do
	local template = AbilityTemplates[template_name]
	if template and not template.ability_meta_data then
		template.ability_meta_data = meta_data
		mod:echo("BotAbilities: injected meta_data for " .. template_name)
	end
end

-- Hook the bot condition that gates ability activation.
-- The original has a hardcoded whitelist that only allows "zealot_relic" and
-- "veteran_combat_ability". We replace the final gate to allow all templates
-- that have ability_meta_data (which now includes our Tier 2 injections).
local bt_bot_conditions = require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
local _original_can_activate = bt_bot_conditions.can_activate_ability

bt_bot_conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
	local ability_component_name = action_data.ability_component_name

	-- If already running this ability node, keep going (mirrors original logic).
	if ability_component_name == scratchpad.ability_component_name then
		return true
	end

	local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
	local ability_component = unit_data_extension:read_component(ability_component_name)
	local ability_template_name = ability_component.template_name

	if ability_template_name == "none" then
		return false
	end

	local ability_template = AbilityTemplates[ability_template_name]
	if not ability_template then
		return false
	end

	local ability_meta_data = ability_template.ability_meta_data
	if not ability_meta_data then
		return false
	end

	-- Check if ability is off cooldown and ready to fire.
	local activation_data = ability_meta_data.activation
	local action_input = activation_data.action_input
	local FixedFrame = require("scripts/utilities/fixed_frame")
	local fixed_t = FixedFrame.get_latest_fixed_time()
	local ability_extension = ScriptUnit.extension(unit, "ability_system")
	local action_input_is_valid = ability_extension:action_input_is_currently_valid(
		ability_component_name, action_input, nil, fixed_t
	)

	if not action_input_is_valid then
		return false
	end

	-- Use the original veteran condition for veteran_combat_ability (it checks
	-- for elite/special targets which is good decision-making).
	if ability_template_name == "veteran_combat_ability" then
		return bt_bot_conditions._can_activate_veteran_ranger_ability(
			unit, blackboard, scratchpad, condition_args, action_data, is_running
		)
	end

	-- For zealot_relic, use the original threat-based condition.
	if ability_template_name == "zealot_relic" then
		return bt_bot_conditions._can_activate_zealot_relic(
			unit, blackboard, scratchpad, condition_args, action_data, is_running
		)
	end

	-- For all other abilities with meta_data: activate when enemies are nearby.
	-- This is a simple but reasonable heuristic for Phase 1.
	local perception_extension = ScriptUnit.extension(unit, "perception_system")
	local _, num_nearby = perception_extension:enemies_in_proximity()

	return num_nearby > 0
end

mod:echo("BotAbilities loaded")
