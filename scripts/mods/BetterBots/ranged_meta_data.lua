local _mod -- luacheck: ignore 231
local _patched_set
local _debug_log

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

local function has_keyword(weapon_template, keyword)
	for _, kw in ipairs(weapon_template.keywords or {}) do
		if kw == keyword then
			return true
		end
	end
	return false
end

local function build_meta_data(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	local meta = {}
	local changed = false

	if not is_valid_input(weapon_template, fallback.fire_action_input) then
		local fire_input, fire_action = find_fire_input(weapon_template)
		if fire_input then
			meta.fire_action_input = fire_input
			if not (weapon_template.actions or {})["action_shoot"] then
				meta.fire_action_name = fire_action
			end
			changed = true
		end
	end

	-- Aim/aim-fire derivation deliberately omitted: action_two_hold is
	-- overloaded (ADS on guns, charged secondary on staffs). Injecting the
	-- wrong action causes bots to start alt-fire when they should be aiming.
	-- See #43 for charge-weapon secondary fire support.

	return changed and meta or nil
end

local function inject(WeaponTemplates)
	if _patched_set[WeaponTemplates] then
		return
	end

	local injected = 0
	local skipped = 0

	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		if type(template) == "table" and has_keyword(template, "ranged") then
			if template.attack_meta_data then
				skipped = skipped + 1
			else
				local meta = build_meta_data(template)
				if meta then
					template.attack_meta_data = meta
					injected = injected + 1
				end
			end
		end
	end

	_patched_set[WeaponTemplates] = true
	_debug_log(
		"ranged_meta_injection:" .. tostring(WeaponTemplates),
		0,
		"ranged attack_meta_data patch installed (injected=" .. injected .. ", skipped=" .. skipped .. ")"
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
	end,
	inject = inject,
	_resolve_vanilla_fallback = resolve_vanilla_fallback,
	_needs_injection = needs_injection,
	_find_fire_input = find_fire_input,
	_find_aim_input = find_aim_input,
	_find_aim_fire_input = find_aim_fire_input,
}
