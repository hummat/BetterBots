-- melee_attack_choice.lua — replace vanilla melee attack scoring so bots stop
-- over-valuing wide heavies into unarmored horde trash.
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _armored_type
local _armor
local _logged_choice_keys = {}

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

local function _enemy_bucket(num_enemies)
	if num_enemies > 3 then
		return "horde"
	end
	if num_enemies > 1 then
		return "pack"
	end
	return "solo"
end

local function _chosen_attack_input(weapon_meta_data, chosen_attack_meta_data)
	for attack_input, attack_meta_data in pairs(weapon_meta_data or DEFAULT_ATTACK_META_DATA) do
		if attack_meta_data == chosen_attack_meta_data then
			return attack_input
		end
	end

	return "unknown"
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

local _is_enabled

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_armored_type = deps.ARMOR_TYPE_ARMORED
	_is_enabled = deps.is_enabled
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action",
		function(BtBotMeleeAction)
			_mod:hook(BtBotMeleeAction, "_choose_attack", function(func, self, target_unit, target_breed, scratchpad)
				if _is_enabled and not _is_enabled() then
					return func(self, target_unit, target_breed, scratchpad)
				end
				local num_enemies = scratchpad.num_enemies_in_proximity or 0
				local armor = _armor_api()
				local target_armor = armor and armor.armor_type(target_unit, target_breed) or nil
				local weapon_template = scratchpad.weapon_template or {}
				local chosen =
					choose_attack_meta_data(weapon_template.attack_meta_data, target_armor, num_enemies, _armored_type)
				local chosen_attack = _chosen_attack_input(weapon_template.attack_meta_data, chosen)

				if
					_debug_enabled()
					and ((target_armor ~= _armored_type and num_enemies > 1) or target_armor == _armored_type)
				then
					local weapon_name = tostring(weapon_template.name or weapon_template.display_name or "weapon")
					local armor_bucket = target_armor == _armored_type and "armored" or "unarmored"
					local choice_key = weapon_name
						.. ":"
						.. tostring(chosen_attack)
						.. ":"
						.. armor_bucket
						.. ":"
						.. _enemy_bucket(num_enemies)

					if not _logged_choice_keys[choice_key] then
						_logged_choice_keys[choice_key] = true
						_debug_log(
							"melee_choice:" .. choice_key,
							_fixed_time(),
							"melee choice "
								.. tostring(chosen_attack)
								.. " vs "
								.. armor_bucket
								.. " target (crowd="
								.. tostring(num_enemies)
								.. ", bucket="
								.. _enemy_bucket(num_enemies)
								.. ", weapon="
								.. weapon_name
								.. ")"
						)
					end
				elseif
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
