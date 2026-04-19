local _mod -- luacheck: ignore 231
local _patched_set
local _debug_log
local _debug_enabled
local _is_enabled
local _fixed_time
local ABSENT = {}
local is_valid_input
local find_aim_fire_input
local find_aim_action_for_fire

local function actions_table(weapon_template)
	local actions = weapon_template and weapon_template.actions or nil

	return type(actions) == "table" and actions or nil
end

local function action_inputs_table(weapon_template)
	local action_inputs = weapon_template and weapon_template.action_inputs or nil

	return type(action_inputs) == "table" and action_inputs or nil
end

local function attack_meta_data_table(weapon_template)
	if type(weapon_template) ~= "table" then
		return nil
	end

	local attack_meta_data = weapon_template and weapon_template.attack_meta_data or nil

	return type(attack_meta_data) == "table" and attack_meta_data or nil
end

local function resolve_vanilla_fallback(weapon_template)
	local actions = actions_table(weapon_template) or {}
	local has_action_inputs = action_inputs_table(weapon_template) ~= nil
	local aim_action = type(actions["action_zoom"]) == "table" and actions["action_zoom"] or nil
	local attack_action = type(actions["action_shoot"]) == "table" and actions["action_shoot"] or nil
	local aim_attack_action = type(actions["action_shoot_zoomed"]) == "table" and actions["action_shoot_zoomed"] or nil
	local fire_action_input = attack_action and attack_action.start_input or "shoot"
	local aim_fire_action_input = aim_attack_action and aim_attack_action.start_input or nil
	local aim_action_input = aim_action and aim_action.start_input or nil
	local aim_action_from_actions = aim_action_input ~= nil
	local aim_fire_from_actions = aim_fire_action_input ~= nil
	local unaim_action_input = nil

	if aim_fire_action_input == nil then
		aim_fire_action_input = find_aim_fire_input(weapon_template)
	end

	if aim_fire_action_input then
		local derived_aim_input, _, derived_unaim_input =
			find_aim_action_for_fire(weapon_template, aim_fire_action_input)
		aim_action_input = aim_action_input or derived_aim_input
		unaim_action_input = derived_unaim_input
	end

	if has_action_inputs and not aim_action_from_actions and not is_valid_input(weapon_template, aim_action_input) then
		aim_action_input = nil
	end

	if
		has_action_inputs
		and not aim_fire_from_actions
		and not is_valid_input(weapon_template, aim_fire_action_input)
	then
		aim_fire_action_input = nil
	end

	if has_action_inputs and not is_valid_input(weapon_template, unaim_action_input) then
		unaim_action_input = nil
	end

	return {
		fire_action_input = fire_action_input,
		aim_action_input = aim_action_input,
		aim_fire_action_input = aim_fire_action_input,
		unaim_action_input = unaim_action_input,
	}
end

is_valid_input = function(weapon_template, input_name)
	if type(input_name) ~= "string" then
		return false
	end

	local action_inputs = action_inputs_table(weapon_template)
	return action_inputs ~= nil and action_inputs[input_name] ~= nil
end

local function needs_injection(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	return not is_valid_input(weapon_template, fallback.fire_action_input)
end

local function find_action_for_input(weapon_template, input_name)
	for action_name, action in pairs(actions_table(weapon_template) or {}) do
		if action.start_input == input_name then
			return action_name, action
		end
	end
	return nil, nil
end

local FIRE_INPUT_PREFERENCE = { "shoot_pressed", "shoot_charge" }

local function find_fire_input(weapon_template)
	local action_inputs = action_inputs_table(weapon_template) or {}
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
	local action_inputs = action_inputs_table(weapon_template) or {}

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

local function find_chain_target_action(weapon_template, input_name)
	for _, action in pairs(actions_table(weapon_template) or {}) do
		local chain_entry = (action.allowed_chain_actions or {})[input_name]
		if chain_entry and chain_entry.action_name then
			return chain_entry.action_name
		end
	end
	return nil
end

local function has_braced_chain_action(weapon_template, input_name)
	local action_inputs = action_inputs_table(weapon_template) or {}

	for _, action in pairs(actions_table(weapon_template) or {}) do
		local start_input = action.start_input
		local start_def = start_input and action_inputs[start_input]
		local seq = start_def and start_def.input_sequence
		local first = seq and seq[1]

		if
			first
			and first.input == "action_two_hold"
			and first.value == true
			and (action.allowed_chain_actions or {})[input_name]
		then
			return true
		end
	end

	return false
end

find_aim_fire_input = function(weapon_template)
	local action_inputs = action_inputs_table(weapon_template) or {}

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
					or find_chain_target_action(weapon_template, input_name)
				if action_name then
					return input_name, action_name
				end
			end
		end
	end

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_one_hold" and first.value == true then
				local action_name = find_action_for_input(weapon_template, input_name)
					or find_chain_target_action(weapon_template, input_name)
				if action_name and has_braced_chain_action(weapon_template, input_name) then
					return input_name, action_name
				end
			end
		end
	end

	return nil, nil
end

local function has_hold_start_input(weapon_template, input_name)
	local input_def = (action_inputs_table(weapon_template) or {})[input_name]
	local seq = input_def and input_def.input_sequence
	local first = seq and seq[1]

	return first and first.input == "action_two_hold" and first.value == true
end

local function find_unaim_action_for_action(weapon_template, action)
	local actions = actions_table(weapon_template) or {}
	local unaim_input = action and action.stop_input
	if unaim_input then
		local unaim_action_name = find_action_for_input(weapon_template, unaim_input)

		return unaim_input, unaim_action_name
	end

	for input_name, chain_entry in pairs((action and action.allowed_chain_actions) or {}) do
		local action_name = chain_entry and chain_entry.action_name
		local target_action = action_name and actions[action_name]
		if target_action and target_action.kind == "unaim" then
			return input_name, action_name
		end
	end

	return nil, nil
end

find_aim_action_for_fire = function(weapon_template, aim_fire_input)
	if not aim_fire_input then
		return nil, nil, nil, nil
	end

	for action_name, action in pairs(actions_table(weapon_template) or {}) do
		local start_input = action.start_input
		local allowed_chain_actions = action.allowed_chain_actions or {}

		if
			start_input
			and has_hold_start_input(weapon_template, start_input)
			and allowed_chain_actions[aim_fire_input]
		then
			local unaim_input, unaim_action = find_unaim_action_for_action(weapon_template, action)

			return start_input, action_name, unaim_input, unaim_action
		end
	end

	return nil, nil, nil, nil
end

local function has_keyword(weapon_template, keyword)
	for _, kw in ipairs(weapon_template.keywords or {}) do
		if kw == keyword then
			return true
		end
	end
	return false
end

local CLOSE_RANGE_RANGED_DISTANCE_SQ = 10 * 10
local CLOSE_RANGE_RANGED_POLICIES = {
	flamer = {
		family = "flamer",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
		hipfire_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	shotgun = {
		family = "shotgun",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
		hipfire_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	heavystubber = {
		family = "heavystubber",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
		hipfire_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	autopistol = {
		family = "autopistol",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
		hipfire_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	rippergun = {
		family = "rippergun",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	forcestaff_p2_m1 = {
		family = "forcestaff_p2_m1",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
	forcestaff_p3_m1 = {
		family = "forcestaff_p3_m1",
		hold_ranged_target_distance_sq = CLOSE_RANGE_RANGED_DISTANCE_SQ,
	},
}

local function close_range_ranged_policy(weapon_template)
	if type(weapon_template) ~= "table" then
		return nil
	end

	if weapon_template.name == "forcestaff_p2_m1" then
		return CLOSE_RANGE_RANGED_POLICIES.forcestaff_p2_m1
	end

	if weapon_template.name == "forcestaff_p3_m1" then
		return CLOSE_RANGE_RANGED_POLICIES.forcestaff_p3_m1
	end

	if has_keyword(weapon_template, "flamer") then
		return CLOSE_RANGE_RANGED_POLICIES.flamer
	end

	if has_keyword(weapon_template, "shotgun") then
		return CLOSE_RANGE_RANGED_POLICIES.shotgun
	end

	if has_keyword(weapon_template, "heavystubber") then
		return CLOSE_RANGE_RANGED_POLICIES.heavystubber
	end

	if has_keyword(weapon_template, "autopistol") then
		return CLOSE_RANGE_RANGED_POLICIES.autopistol
	end

	if has_keyword(weapon_template, "rippergun") then
		return CLOSE_RANGE_RANGED_POLICIES.rippergun
	end

	return nil
end

local WEAKSPOT_AIM_NODES = { -- (#91)
	"j_head",
	"j_spine",
}

local function has_any_keyword(weapon_template, keywords)
	for _, keyword in ipairs(keywords) do
		if has_keyword(weapon_template, keyword) then
			return true
		end
	end

	return false
end

local function should_inject_weakspot_aim(weapon_template)
	return has_any_keyword(weapon_template, {
		"lasgun",
		"autogun",
		"bolter",
		"stub_pistol",
	})
end

local function build_meta_data(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	local attack_meta_data = attack_meta_data_table(weapon_template) or {}
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

	-- Aim derivation deliberately omitted: action_two_hold is overloaded
	-- (ADS on guns, charged secondary on staffs). Injecting the wrong
	-- action causes bots to start alt-fire when they should be aiming.
	-- Charge weapon aim-fire override handled separately in inject() (#43).
	--
	-- However, when aim-fire fallback is invalid, mirror the fire input so
	-- the bot fires correctly regardless of aim state (killshot gestalt
	-- forces aimed shots, and invalid aim_fire_action_input silently fails).
	local effective_fire = meta.fire_action_input or fallback.fire_action_input
	if
		not is_valid_input(weapon_template, fallback.aim_fire_action_input)
		and is_valid_input(weapon_template, effective_fire)
	then
		meta.aim_fire_action_input = effective_fire
		changed = true
	end

	if should_inject_weakspot_aim(weapon_template) and attack_meta_data.aim_at_node == nil then
		meta.aim_at_node = WEAKSPOT_AIM_NODES
		changed = true
	end

	return changed and meta or nil
end

local function inject(WeaponTemplates)
	local state = _patched_set[WeaponTemplates]
	if not state then
		state = {
			applied = false,
			changes = {},
		}
		_patched_set[WeaponTemplates] = state
	end

	if _is_enabled and not _is_enabled() then
		if state.applied then
			for template, change in pairs(state.changes) do
				if change.mode == "replace" then
					if template.attack_meta_data == change.injected_table then
						template.attack_meta_data = nil
					end
				elseif change.mode == "replace_invalid" then
					if template.attack_meta_data == change.injected_table then
						template.attack_meta_data = change.original_value
					end
				elseif change.mode == "fields" and type(template.attack_meta_data) == "table" then
					for key, original_value in pairs(change.original_fields or {}) do
						if original_value == ABSENT then
							template.attack_meta_data[key] = nil
						else
							template.attack_meta_data[key] = original_value
						end
					end
				end
			end
			state.changes = {}
			state.applied = false
		end
		return
	end

	local injected = 0
	local patched = 0
	local skipped = 0

	local function ensure_change(template, mode)
		local change = state.changes[template]
		if not change then
			change = { mode = mode }
			state.changes[template] = change
		end
		if mode == "replace_invalid" then
			change.mode = "replace_invalid"
			return change
		end
		if mode == "fields" and change.mode ~= "replace" and change.mode ~= "replace_invalid" then
			change.mode = "fields"
			change.original_fields = change.original_fields or {}
		end
		return change
	end

	local function record_original_field(change, meta, key)
		-- Replace-mode changes nil the whole attack_meta_data on disable,
		-- so field-level originals are irrelevant. original_fields is only
		-- populated for mode == "fields".
		local original_fields = change.original_fields
		if original_fields == nil then
			return
		end
		if original_fields[key] ~= nil then
			return
		end

		if meta[key] == nil then
			original_fields[key] = ABSENT
		else
			original_fields[key] = meta[key]
		end
	end

	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		if type(template) == "table" and has_keyword(template, "ranged") then
			local corrections = build_meta_data(template)
			if corrections then
				local existing_attack_meta_data = attack_meta_data_table(template)
				if existing_attack_meta_data then
					local merged = 0
					for k, v in pairs(corrections) do
						if existing_attack_meta_data[k] == nil then
							local change = ensure_change(template, "fields")
							record_original_field(change, existing_attack_meta_data, k)
							existing_attack_meta_data[k] = v
							merged = merged + 1
						end
					end
					if merged > 0 then
						patched = patched + 1
					else
						skipped = skipped + 1
					end
				else
					local replace_change
					if template.attack_meta_data == nil then
						replace_change = ensure_change(template, "replace")
					else
						replace_change = ensure_change(template, "replace_invalid")
						replace_change.original_value = template.attack_meta_data
					end
					template.attack_meta_data = corrections
					replace_change.injected_table = corrections
					injected = injected + 1
				end
			else
				skipped = skipped + 1
			end
		end
	end

	-- #43: override broken aim metadata for charge weapons. Force staves use
	-- action_two_hold to start charging and a hold-combo fire input for the
	-- actual charged attack. Their hardcoded "zoom"/"zoom_shoot" fallback is
	-- wrong, so derive the charge action and its matching aimed fire input.
	local charge_overrides = 0
	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		local existing_attack_meta_data = attack_meta_data_table(template)
		if type(template) == "table" and has_keyword(template, "ranged") and existing_attack_meta_data then
			local aim_fire_input, aim_fire_action = find_aim_fire_input(template)
			if aim_fire_input and existing_attack_meta_data.aim_fire_action_input ~= aim_fire_input then
				local changed = false
				local change = ensure_change(template, "fields")
				local aim_input, aim_action, unaim_input, unaim_action =
					find_aim_action_for_fire(template, aim_fire_input)

				if existing_attack_meta_data.aim_fire_action_input ~= aim_fire_input then
					record_original_field(change, existing_attack_meta_data, "aim_fire_action_input")
					record_original_field(change, existing_attack_meta_data, "aim_fire_action_name")
					existing_attack_meta_data.aim_fire_action_input = aim_fire_input
					existing_attack_meta_data.aim_fire_action_name = aim_fire_action
					changed = true
				end

				if aim_input and existing_attack_meta_data.aim_action_input ~= aim_input then
					record_original_field(change, existing_attack_meta_data, "aim_action_input")
					existing_attack_meta_data.aim_action_input = aim_input
					changed = true
				end

				if aim_action and existing_attack_meta_data.aim_action_name ~= aim_action then
					record_original_field(change, existing_attack_meta_data, "aim_action_name")
					existing_attack_meta_data.aim_action_name = aim_action
					changed = true
				end

				if unaim_input and existing_attack_meta_data.unaim_action_input ~= unaim_input then
					record_original_field(change, existing_attack_meta_data, "unaim_action_input")
					existing_attack_meta_data.unaim_action_input = unaim_input
					changed = true
				end

				if unaim_action and existing_attack_meta_data.unaim_action_name ~= unaim_action then
					record_original_field(change, existing_attack_meta_data, "unaim_action_name")
					existing_attack_meta_data.unaim_action_name = unaim_action
					changed = true
				end

				if changed then
					charge_overrides = charge_overrides + 1
				end
			end
		end
	end

	state.applied = true
	if _debug_enabled() then
		_debug_log(
			"ranged_meta_injection:" .. tostring(WeaponTemplates),
			_fixed_time and _fixed_time() or 0,
			"ranged attack_meta_data patch installed (injected="
				.. injected
				.. ", patched="
				.. patched
				.. ", charge="
				.. charge_overrides
				.. ", skipped="
				.. skipped
				.. ")",
			nil,
			"info"
		)
	end
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_is_enabled = deps.is_enabled
		_fixed_time = deps.fixed_time
	end,
	inject = inject,
	sync_all = function()
		for WeaponTemplates in pairs(_patched_set) do
			inject(WeaponTemplates)
		end
	end,
	_resolve_vanilla_fallback = resolve_vanilla_fallback,
	_needs_injection = needs_injection,
	_find_fire_input = find_fire_input,
	_find_aim_input = find_aim_input,
	_find_aim_fire_input = find_aim_fire_input,
	_find_aim_action_for_fire = find_aim_action_for_fire,
	close_range_ranged_policy = close_range_ranged_policy,
	_should_inject_weakspot_aim = should_inject_weakspot_aim,
}
