local _mod -- luacheck: ignore 231
local _patched_set
local _debug_log
local _debug_enabled
local _armored_type
local _is_enabled

local ABSENT = {}
local DEFAULT_MELEE_RANGE = 2.5
local CLEAVE_ARC_1_THRESHOLD = 2
local CLEAVE_ARC_2_THRESHOLD = 9
local PENETRATING_THRESHOLD = 0.5

local function classify_arc(damage_profile)
	if not damage_profile or not damage_profile.cleave_distribution then
		return 0
	end
	local cleave = damage_profile.cleave_distribution.attack
	if not cleave then
		return 0
	end
	local max_cleave
	if type(cleave) == "number" then
		max_cleave = cleave
	else
		max_cleave = cleave[2] or cleave[1] or 0
	end
	if max_cleave > CLEAVE_ARC_2_THRESHOLD then
		return 2
	elseif max_cleave > CLEAVE_ARC_1_THRESHOLD then
		return 1
	else
		return 0
	end
end

local function get_armor_modifier_table(damage_profile)
	local targets = damage_profile.targets
	local first_target = targets and targets[1]
	local am = first_target and first_target.armor_damage_modifier or damage_profile.armor_damage_modifier
	return am
end

local function classify_penetrating(damage_profile, armored_type)
	if not damage_profile or not armored_type then
		return false
	end
	local am = get_armor_modifier_table(damage_profile)
	if not am or not am.attack then
		return false
	end
	local armored_lerp = am.attack[armored_type]
	if not armored_lerp then
		return false
	end
	local max_modifier
	if type(armored_lerp) == "number" then
		max_modifier = armored_lerp
	else
		max_modifier = armored_lerp[2] or armored_lerp[1] or 0
	end
	return max_modifier >= PENETRATING_THRESHOLD
end

local function find_start_action(weapon_template)
	for _, action in pairs(weapon_template.actions or {}) do
		if action.start_input == "start_attack" and not action.invalid_start_action_for_stat_calculation then
			return action
		end
	end
	return nil
end

local function build_attack_entry(damage_profile, input_name, chain_time, armored_type)
	return {
		arc = classify_arc(damage_profile),
		penetrating = classify_penetrating(damage_profile, armored_type),
		max_range = DEFAULT_MELEE_RANGE,
		action_inputs = {
			{ action_input = "start_attack", timing = 0 },
			{ action_input = input_name, timing = chain_time or 0 },
		},
	}
end

local function build_meta_data(weapon_template, armored_type)
	local start_action = find_start_action(weapon_template)
	if not start_action then
		return nil
	end

	local chains = start_action.allowed_chain_actions
	if not chains then
		return nil
	end

	local meta = {}
	local count = 0

	for _, input_name in ipairs({ "light_attack", "heavy_attack" }) do
		local chain = chains[input_name]
		if chain and chain.action_name then
			local action = weapon_template.actions[chain.action_name]
			if action and action.damage_profile then
				meta[input_name] = build_attack_entry(action.damage_profile, input_name, chain.chain_time, armored_type)
				count = count + 1
			end
		end
	end

	return count > 0 and meta or nil
end

local function has_keyword(weapon_template, keyword)
	for _, kw in ipairs(weapon_template.keywords or {}) do
		if kw == keyword then
			return true
		end
	end
	return false
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
					for attack_input, original_fields in pairs(change.original_fields or {}) do
						local entry = template.attack_meta_data[attack_input]
						if type(entry) == "table" then
							for key, original_value in pairs(original_fields) do
								if original_value == ABSENT then
									entry[key] = nil
								else
									entry[key] = original_value
								end
							end
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
		if mode == "fields" and change.mode ~= "replace" then
			change.mode = "fields"
			change.original_fields = change.original_fields or {}
		end
		return change
	end

	local function record_original_field(change, attack_input, entry, key)
		local original_fields = change.original_fields
		local attack_fields = original_fields[attack_input]
		if not attack_fields then
			attack_fields = {}
			original_fields[attack_input] = attack_fields
		end
		if attack_fields[key] ~= nil then
			return
		end

		if entry[key] == nil then
			attack_fields[key] = ABSENT
		else
			attack_fields[key] = entry[key]
		end
	end

	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		if type(template) == "table" and has_keyword(template, "melee") then
			local change = state.changes[template]
			if change and change.mode == "replace" then
				if template.attack_meta_data == nil then
					template.attack_meta_data = change.injected_table
				end
				skipped = skipped + 1
			elseif change and change.mode == "replace_invalid" then
				skipped = skipped + 1
			elseif type(template.attack_meta_data) == "table" then
				local meta = build_meta_data(template, _armored_type)
				local merged = 0
				if meta then
					for attack_input, generated_entry in pairs(meta) do
						local existing_entry = template.attack_meta_data[attack_input]
						if type(existing_entry) == "table" then
							for key, value in pairs(generated_entry) do
								if existing_entry[key] == nil then
									local field_change = ensure_change(template, "fields")
									record_original_field(field_change, attack_input, existing_entry, key)
									existing_entry[key] = value
									merged = merged + 1
								end
							end
						end
					end
				end
				if merged > 0 then
					patched = patched + 1
				else
					skipped = skipped + 1
				end
			else
				local meta = build_meta_data(template, _armored_type)
				if meta then
					local replace_change
					if template.attack_meta_data == nil then
						replace_change = ensure_change(template, "replace")
					else
						replace_change = ensure_change(template, "replace_invalid")
						replace_change.original_value = template.attack_meta_data
					end
					template.attack_meta_data = meta
					replace_change.injected_table = meta
					injected = injected + 1
				end
			end
		end
	end

	state.applied = true
	if _debug_enabled() then
		_debug_log(
			"melee_meta_injection:" .. tostring(WeaponTemplates),
			0,
			"melee attack_meta_data patch installed (injected="
				.. injected
				.. ", patched="
				.. patched
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
		_armored_type = deps.ARMOR_TYPE_ARMORED
		_is_enabled = deps.is_enabled
	end,
	inject = inject,
	sync_all = function()
		for WeaponTemplates in pairs(_patched_set) do
			inject(WeaponTemplates)
		end
	end,
	_classify_arc = classify_arc,
	_classify_penetrating = classify_penetrating,
}
