local _mod -- luacheck: ignore 231
local _patched_set -- luacheck: ignore 231
local _debug_log -- luacheck: ignore 231

local function resolve_vanilla_fallback(weapon_template)
	local actions = weapon_template.actions or {}
	local aim_action = actions["action_zoom"] or {}
	local attack_action = actions["action_shoot"] or {}
	local aim_attack_action = actions["action_shoot_zoomed"] or {}
	return {
		fire_action_input = attack_action.start_input or "shoot",
		aim_action_input = aim_action.start_input or "zoom",
		aim_fire_action_input = aim_attack_action.start_input or "zoom_shoot",
	}
end

local function is_valid_input(weapon_template, input_name)
	local action_inputs = weapon_template.action_inputs
	return action_inputs ~= nil and action_inputs[input_name] ~= nil
end

local function needs_injection(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	return not is_valid_input(weapon_template, fallback.fire_action_input)
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
	end,
	inject = function() end,
	_resolve_vanilla_fallback = resolve_vanilla_fallback,
	_needs_injection = needs_injection,
}
