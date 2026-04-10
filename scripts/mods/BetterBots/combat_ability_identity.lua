-- Central combat ability identity resolver.
-- Keep engine template identity separate from equipped/semantic ability identity.
local M = {}

local VETERAN_CLASS_TAG_TO_SEMANTIC_KEY = {
	base = "veteran_combat_ability_stance",
	ranger = "veteran_combat_ability_stance",
	squad_leader = "veteran_combat_ability_shout",
}

local CATEGORY_SETTING_BY_SEMANTIC_KEY = {
	veteran_combat_ability_stance = "enable_stances",
	veteran_combat_ability_shout = "enable_shouts",
	psyker_overcharge_stance = "enable_stances",
	ogryn_gunlugger_stance = "enable_stances",
	adamant_stance = "enable_stances",
	broker_focus = "enable_stances",
	broker_punk_rage = "enable_stances",
	zealot_dash = "enable_charges",
	zealot_targeted_dash = "enable_charges",
	zealot_targeted_dash_improved = "enable_charges",
	zealot_targeted_dash_improved_double = "enable_charges",
	ogryn_charge = "enable_charges",
	ogryn_charge_increased_distance = "enable_charges",
	adamant_charge = "enable_charges",
	psyker_shout = "enable_shouts",
	ogryn_taunt_shout = "enable_shouts",
	adamant_shout = "enable_shouts",
	veteran_stealth_combat_ability = "enable_stealth",
	zealot_invisibility = "enable_stealth",
}

local REVIVE_DEFENSIVE_BY_SEMANTIC_KEY = {
	ogryn_taunt_shout = true,
	psyker_shout = true,
	adamant_shout = true,
	adamant_stance = true,
	zealot_invisibility = true,
	veteran_stealth_combat_ability = true,
	veteran_combat_ability_shout = true,
}

local TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY = {
	ogryn_taunt_shout = "taunt",
	adamant_shout = "taunt",
	psyker_shout = "aoe_shout",
	veteran_combat_ability_shout = "aoe_shout",
	zealot_dash = "dash",
	zealot_targeted_dash = "dash",
	zealot_targeted_dash_improved = "dash",
	zealot_targeted_dash_improved_double = "dash",
	ogryn_charge = "dash",
	ogryn_charge_increased_distance = "dash",
	adamant_charge = "dash",
}

local function _combat_ability(ability_extension)
	local equipped = ability_extension and ability_extension._equipped_abilities
	return equipped and equipped.combat_ability or nil
end

local function _veteran_class_tag_from_ability_name(ability_name)
	if not ability_name then
		return nil
	end

	if string.find(ability_name, "shout", 1, true) then
		return "squad_leader"
	end
	if string.find(ability_name, "stance", 1, true) then
		return "ranger"
	end

	return nil
end

local function _resolve_veteran_semantic_key(ability_name, class_tag)
	local name_class_tag = _veteran_class_tag_from_ability_name(ability_name)
	local normalized_class_tag = name_class_tag or class_tag
	local source = "unknown"
	if normalized_class_tag then
		source = (class_tag and class_tag == normalized_class_tag) and "class_tag" or "ability_name"
	end
	return VETERAN_CLASS_TAG_TO_SEMANTIC_KEY[normalized_class_tag], normalized_class_tag, source
end

function M.resolve(_unit, ability_extension, ability_component)
	local template_name = ability_component and ability_component.template_name or nil
	local combat_ability = _combat_ability(ability_extension)
	local ability_name = combat_ability and combat_ability.name or nil
	local tweak_data = combat_ability and combat_ability.ability_template_tweak_data
	local class_tag = tweak_data and tweak_data.class_tag or nil
	local class_tag_source = class_tag and "class_tag" or nil
	local semantic_key = template_name

	if template_name == "veteran_combat_ability" then
		semantic_key, class_tag, class_tag_source = _resolve_veteran_semantic_key(ability_name, class_tag)
	end

	if not semantic_key then
		semantic_key = template_name or ability_name
	end

	return {
		template_name = template_name,
		ability_name = ability_name,
		semantic_key = semantic_key,
		class_tag = class_tag,
		class_tag_source = class_tag_source or "unknown",
	}
end

function M.effective_name(identity)
	if not identity then
		return "unknown"
	end

	return identity.semantic_key or identity.ability_name or identity.template_name or "unknown"
end

function M.category_setting_id(identity)
	if
		identity
		and identity.template_name == "veteran_combat_ability"
		and not CATEGORY_SETTING_BY_SEMANTIC_KEY[identity.semantic_key]
	then
		return "enable_stances"
	end

	return identity and CATEGORY_SETTING_BY_SEMANTIC_KEY[identity.semantic_key] or nil
end

function M.is_revive_defensive(identity)
	return identity and REVIVE_DEFENSIVE_BY_SEMANTIC_KEY[identity.semantic_key] == true or false
end

function M.team_cooldown_category(identity_or_key)
	local semantic_key = type(identity_or_key) == "table" and identity_or_key.semantic_key or identity_or_key
	return TEAM_COOLDOWN_CATEGORY_BY_SEMANTIC_KEY[semantic_key]
end

return M
