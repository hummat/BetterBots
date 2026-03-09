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

local function find_action_for_input(weapon_template, input_name)
	for action_name, action in pairs(weapon_template.actions or {}) do
		if action.start_input == input_name then
			return action_name, action
		end
	end
	return nil, nil
end

local FIRE_INPUT_PREFERENCE = { "shoot_pressed", "shoot_charge" }

local function find_fire_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}
	local candidates = {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_one_pressed" and first.value == true and not first.hold_input then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					candidates[#candidates + 1] = { input_name = input_name, action_name = action_name }
				end
			end
		end
	end

	if #candidates == 0 then
		return nil, nil
	elseif #candidates == 1 then
		return candidates[1].input_name, candidates[1].action_name
	end

	for _, preferred in ipairs(FIRE_INPUT_PREFERENCE) do
		for _, c in ipairs(candidates) do
			if c.input_name == preferred then
				return c.input_name, c.action_name
			end
		end
	end

	return candidates[1].input_name, candidates[1].action_name
end

local function find_aim_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_two_hold" and first.value == true then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					return input_name, action_name
				end
			end
		end
	end

	return nil, nil
end

local function find_aim_fire_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if
				first.input == "action_one_pressed"
				and first.value == true
				and first.hold_input == "action_two_hold"
			then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					return input_name, action_name
				end
			end
		end
	end

	return nil, nil
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
	_find_fire_input = find_fire_input,
	_find_aim_input = find_aim_input,
	_find_aim_fire_input = find_aim_fire_input,
}
