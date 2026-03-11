local _mod
local _patched_set
local _debug_log
local _debug_enabled
local _patch_version

-- Tier 2 templates exist but are missing ability_meta_data.
-- This metadata is consumed by BtBotActivateAbilityAction.
local TIER2_META_DATA = {
	zealot_invisibility = {
		activation = {
			action_input = "stance_pressed",
		},
	},
	zealot_dash = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
	ogryn_taunt_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	psyker_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_shout = {
		activation = {
			action_input = "shout_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "shout_released",
		},
	},
	adamant_charge = {
		activation = {
			action_input = "aim_pressed",
			min_hold_time = 0.01,
		},
		wait_action = {
			action_input = "aim_released",
		},
		end_condition = {
			done_when_arriving_at_destination = true,
		},
	},
}

-- Veteran templates ship with stance_pressed metadata, but runtime validation
-- for bot input expects combat_ability_pressed/combat_ability_released.
local META_DATA_OVERRIDES = {
	veteran_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
	veteran_stealth_combat_ability = {
		activation = {
			action_input = "combat_ability_pressed",
			min_hold_time = 0.075,
		},
		wait_action = {
			action_input = "combat_ability_released",
		},
	},
}

local function inject(AbilityTemplates)
	if _patched_set[AbilityTemplates] then
		return
	end

	local injected_count = 0
	local overridden_count = 0

	for template_name, meta_data in pairs(TIER2_META_DATA) do
		local template = rawget(AbilityTemplates, template_name)
		if template and not template.ability_meta_data then
			template.ability_meta_data = meta_data
			injected_count = injected_count + 1
			_mod:echo("BetterBots: injected meta_data for " .. template_name)
		end
	end

	for template_name, meta_data in pairs(META_DATA_OVERRIDES) do
		local template = rawget(AbilityTemplates, template_name)
		local current_input = template
			and template.ability_meta_data
			and template.ability_meta_data.activation
			and template.ability_meta_data.activation.action_input
		local target_input = meta_data.activation.action_input

		if template and current_input ~= target_input then
			template.ability_meta_data = meta_data
			overridden_count = overridden_count + 1
			_mod:echo(
				"BetterBots: patched meta_data for "
					.. template_name
					.. " (action_input="
					.. tostring(current_input)
					.. " -> "
					.. tostring(target_input)
					.. ")"
			)
		end
	end

	_patched_set[AbilityTemplates] = true
	if _debug_enabled() then
		_debug_log(
			"meta_injection:" .. tostring(AbilityTemplates),
			0,
			"ability template metadata patch installed (version="
				.. _patch_version
				.. ", injected="
				.. tostring(injected_count)
				.. ", overridden="
				.. tostring(overridden_count)
				.. ")"
		)
	end
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_ability_templates
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_patch_version = deps.META_PATCH_VERSION
	end,
	inject = inject,
}
