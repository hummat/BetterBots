-- melee_attack_choice.lua — replace vanilla melee attack scoring so bots stop
-- over-valuing wide heavies into unarmored horde trash.
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _armored_type
local _armor

local DEFAULT_MAXIMAL_MELEE_RANGE = 2.5
local LIGHT_HORDE_BIAS = 4
local DEFAULT_ATTACK_META_DATA = {
	light_attack = {
		arc = 0,
		penetrating = false,
		max_range = DEFAULT_MAXIMAL_MELEE_RANGE,
		action_inputs = {
			{
				action_input = "start_attack",
				timing = 0,
			},
			{
				action_input = "light_attack",
				timing = 0,
			},
		},
	},
}

local function _score_attack(attack_input, attack_meta_data, target_armor, num_enemies, armored_type)
	local outnumbered = num_enemies > 1
	local massively_outnumbered = num_enemies > 3
	local utility = 0

	if outnumbered and attack_meta_data.arc == 1 then
		utility = utility + 1
	elseif attack_meta_data.no_damage and massively_outnumbered and attack_meta_data.arc > 1 then
		utility = utility + 2
	elseif
		not attack_meta_data.no_damage
		and ((outnumbered and attack_meta_data.arc > 1) or (not outnumbered and attack_meta_data.arc == 0))
	then
		utility = utility + 4
	end

	if target_armor ~= armored_type or attack_meta_data.penetrating then
		utility = utility + 8
	end

	if
		outnumbered
		and target_armor ~= armored_type
		and attack_input == "light_attack"
		and not attack_meta_data.no_damage
	then
		utility = utility + LIGHT_HORDE_BIAS
	end

	return utility
end

local function choose_attack_meta_data(weapon_meta_data, target_armor, num_enemies, armored_type)
	local meta_data = weapon_meta_data or DEFAULT_ATTACK_META_DATA
	local best_attack_input
	local best_attack_meta_data
	local best_utility = -math.huge

	for attack_input, attack_meta_data in pairs(meta_data) do
		local utility = _score_attack(attack_input, attack_meta_data, target_armor, num_enemies, armored_type)
		local prefer_light_tie = utility == best_utility
			and attack_input == "light_attack"
			and best_attack_input ~= "light_attack"

		if best_utility < utility or prefer_light_tie then
			best_attack_input = attack_input
			best_attack_meta_data = attack_meta_data
			best_utility = utility
		end
	end

	return best_attack_meta_data
end

local function _armor_api()
	if _armor then
		return _armor
	end

	local global_armor = rawget(_G, "Armor")
	if global_armor then
		_armor = global_armor
		return _armor
	end

	local ok, armor = pcall(require, "scripts/utilities/attack/armor")
	if ok then
		_armor = armor
	elseif _mod and _mod.warning then
		_mod:warning("BetterBots: melee attack-choice disabled; failed to load scripts/utilities/attack/armor")
	end

	return _armor
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_armored_type = deps.ARMOR_TYPE_ARMORED
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action",
		function(BtBotMeleeAction)
			_mod:hook(BtBotMeleeAction, "_choose_attack", function(_func, _self, target_unit, target_breed, scratchpad)
				local num_enemies = scratchpad.num_enemies_in_proximity or 0
				local armor = _armor_api()
				local target_armor = armor and armor.armor_type(target_unit, target_breed) or nil
				local weapon_template = scratchpad.weapon_template or {}
				local chosen =
					choose_attack_meta_data(weapon_template.attack_meta_data, target_armor, num_enemies, _armored_type)

				if
					_debug_enabled()
					and target_armor ~= _armored_type
					and num_enemies > 1
					and chosen == (weapon_template.attack_meta_data or {}).light_attack
				then
					_debug_log(
						"melee_light_bias:"
							.. tostring(weapon_template.name or weapon_template.display_name or "weapon"),
						_fixed_time(),
						"melee light-bias selected light attack for unarmored horde target"
					)
				end

				return chosen
			end)
		end
	)
end

M.choose_attack_meta_data = choose_attack_meta_data
M.DEFAULT_ATTACK_META_DATA = DEFAULT_ATTACK_META_DATA

return M
