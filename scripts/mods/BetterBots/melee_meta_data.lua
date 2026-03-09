local _mod -- luacheck: ignore 231
local _patched_set
local _debug_log
local _armored_type

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
	local max_cleave = cleave[2] or cleave[1] or 0
	if max_cleave > CLEAVE_ARC_2_THRESHOLD then
		return 2
	elseif max_cleave > CLEAVE_ARC_1_THRESHOLD then
		return 1
	else
		return 0
	end
end

local function classify_penetrating(damage_profile, armored_type)
	if not damage_profile or not armored_type then
		return false
	end
	local am = damage_profile.armor_damage_modifier
	if not am or not am.attack then
		return false
	end
	local armored_lerp = am.attack[armored_type]
	if not armored_lerp then
		return false
	end
	local max_modifier = armored_lerp[2] or armored_lerp[1] or 0
	return max_modifier >= PENETRATING_THRESHOLD
end

local function find_start_action(weapon_template)
	for _, action in pairs(weapon_template.actions or {}) do
		if action.start_input == "start_attack" then
			return action
		end
	end
	return nil
end

local function build_attack_entry(damage_profile, input_name, armored_type)
	return {
		arc = classify_arc(damage_profile),
		penetrating = classify_penetrating(damage_profile, armored_type),
		max_range = DEFAULT_MELEE_RANGE,
		action_inputs = {
			{ action_input = "start_attack", timing = 0 },
			{ action_input = input_name, timing = 0 },
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
				meta[input_name] = build_attack_entry(action.damage_profile, input_name, armored_type)
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
	if _patched_set[WeaponTemplates] then
		return
	end

	local injected = 0
	local skipped = 0

	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		if type(template) == "table" and has_keyword(template, "melee") then
			if template.attack_meta_data then
				skipped = skipped + 1
			else
				local meta = build_meta_data(template, _armored_type)
				if meta then
					template.attack_meta_data = meta
					injected = injected + 1
				end
			end
		end
	end

	_patched_set[WeaponTemplates] = true
	_debug_log(
		"melee_meta_injection:" .. tostring(WeaponTemplates),
		0,
		"melee attack_meta_data patch installed (injected=" .. injected .. ", skipped=" .. skipped .. ")"
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
		_armored_type = deps.ARMOR_TYPE_ARMORED
	end,
	inject = inject,
	_classify_arc = classify_arc,
	_classify_penetrating = classify_penetrating,
}
