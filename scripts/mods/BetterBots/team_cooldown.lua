-- Team-level combat ability cooldown staggering (#14).
-- Tracks the most recent activation per ability category across all bots.
-- When a bot fires an ability, other bots in the same category are suppressed
-- for a time window. Emergency rules bypass suppression.
--
-- Scope: combat abilities with cooldowns only. Grenades/blitzes (consumable
-- charges, no regeneration) are excluded — different coordination model.
-- Stances (self-buffs) are excluded — each bot benefits independently.

local CATEGORY_MAP = {
	-- taunt
	ogryn_taunt_shout = "taunt",
	adamant_shout = "taunt",
	-- aoe_shout
	psyker_shout = "aoe_shout",
	veteran_combat_ability_shout = "aoe_shout",
	-- dash
	zealot_dash = "dash",
	zealot_targeted_dash = "dash",
	zealot_targeted_dash_improved = "dash",
	zealot_targeted_dash_improved_double = "dash",
	ogryn_charge = "dash",
	ogryn_charge_increased_distance = "dash",
	adamant_charge = "dash",
}

local SUPPRESSION_WINDOW = {
	taunt = 8,
	aoe_shout = 6,
	dash = 4,
}

local EMERGENCY_RULES = {
	psyker_shout_high_peril = true,
	zealot_stealth_emergency = true,
	ogryn_charge_escape = true,
}

-- category → { unit = <unit>, fixed_t = <number> }
local _last_activation_by_category = {}

local function _is_emergency(rule)
	if not rule then
		return false
	end
	if EMERGENCY_RULES[rule] then
		return true
	end
	if string.find(rule, "_ally_aid", 1, true) then
		return true
	end
	return false
end

local function record(unit, template_name, fixed_t)
	local category = CATEGORY_MAP[template_name]
	if not category then
		return
	end
	_last_activation_by_category[category] = {
		unit = unit,
		fixed_t = fixed_t,
	}
end

local function is_suppressed(unit, template_name, fixed_t, rule)
	if _is_emergency(rule) then
		return false, nil
	end

	local category = CATEGORY_MAP[template_name]
	if not category then
		return false, nil
	end

	local last = _last_activation_by_category[category]
	if not last then
		return false, nil
	end

	if last.unit == unit then
		return false, nil
	end

	local window = SUPPRESSION_WINDOW[category]
	if not window then
		return false, nil
	end

	if fixed_t - last.fixed_t < window then
		return true, "team_cd:" .. category
	end

	return false, nil
end

local function reset()
	for k in pairs(_last_activation_by_category) do
		_last_activation_by_category[k] = nil
	end
end

return {
	record = record,
	is_suppressed = is_suppressed,
	reset = reset,
}
