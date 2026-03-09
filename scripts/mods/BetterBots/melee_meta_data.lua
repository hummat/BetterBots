local _mod
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

local function inject(WeaponTemplates) -- luacheck: ignore 212
	-- placeholder
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
