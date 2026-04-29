-- melee_attack_choice.lua — replace vanilla melee attack scoring so bots stop
-- over-valuing wide heavies into unarmored horde trash.
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _armored_type
local _super_armor_type
local _armor
local _is_enabled
local _logged_choice_keys = {}
local _logged_missing_special_action_meta = {}
local _logged_defend_suppression_keys = {}
local _logged_special_pace_keys = {}
local _last_direct_special_t_by_unit = setmetatable({}, { __mode = "k" })
local _direct_special_meta = setmetatable({}, { __mode = "k" })
local _direct_special_template_names = {}
local _melee_horde_light_bias
local MELEE_HOOK_PATCH_SENTINEL = "__bb_melee_attack_choice_installed"

local DEFAULT_MAXIMAL_MELEE_RANGE = 2.5
local DIRECT_SPECIAL_REUSE_DELAY_S = 6
local FORCE_SWORD_2H_MIN_CHARGES = 10
local FORCE_SWORD_2H_MIN_ENEMIES = 4
local HIGH_HEALTH_BREEDS = {
	-- Approximate "worth folding the latrine shovel for" table, sourced from
	-- docs/knowledge/enemy-stats.md (Damnation/Auric HP). Keep this intentionally
	-- narrow: only breeds that clearly sit above ordinary elite/special health.
	cultist_mutant = true,
	chaos_ogryn_gunner = true,
	chaos_ogryn_bulwark = true,
	chaos_ogryn_executor = true,
	renegade_executor = true,
}
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

local function normalize_attack_meta_data(attack_meta_data)
	if type(attack_meta_data) ~= "table" then
		return nil
	end

	local action_inputs = attack_meta_data.action_inputs
	if type(action_inputs) ~= "table" or type(action_inputs[1]) ~= "table" or action_inputs[1].action_input == nil then
		return nil
	end

	if attack_meta_data.arc == nil then
		attack_meta_data.arc = 0
	end
	if attack_meta_data.penetrating == nil then
		attack_meta_data.penetrating = false
	end
	if attack_meta_data.no_damage == nil then
		attack_meta_data.no_damage = false
	end
	if attack_meta_data.max_range == nil then
		attack_meta_data.max_range = DEFAULT_MAXIMAL_MELEE_RANGE
	end

	return attack_meta_data
end

local function _is_armored_bucket(target_armor, armored_type, super_armor_type)
	return target_armor == armored_type or (super_armor_type ~= nil and target_armor == super_armor_type)
end

local function _score_attack(attack_input, attack_meta_data, target_armor, num_enemies, armored_type, super_armor_type)
	local outnumbered = num_enemies > 1
	local massively_outnumbered = num_enemies > 3
	local armored_bucket = _is_armored_bucket(target_armor, armored_type, super_armor_type)
	local utility = 0
	local arc = attack_meta_data.arc or 0
	local penetrating = not not attack_meta_data.penetrating
	local no_damage = not not attack_meta_data.no_damage

	if outnumbered and arc == 1 then
		utility = utility + 1
	elseif no_damage and massively_outnumbered and arc > 1 then
		utility = utility + 2
	elseif not no_damage and ((outnumbered and arc > 1) or (not outnumbered and arc == 0)) then
		utility = utility + 4
	end

	if not armored_bucket or penetrating then
		utility = utility + 8
	end

	local horde_bias = _melee_horde_light_bias and _melee_horde_light_bias() or 4
	if horde_bias > 0 and outnumbered and not armored_bucket and attack_input == "light_attack" and not no_damage then
		utility = utility + horde_bias
	end

	return utility
end

local function choose_attack_meta_data(weapon_meta_data, target_armor, num_enemies, armored_type, super_armor_type)
	local meta_data = type(weapon_meta_data) == "table" and weapon_meta_data or DEFAULT_ATTACK_META_DATA
	local best_attack_input
	local best_attack_meta_data
	local best_utility = -math.huge

	for attack_input, attack_meta_data in pairs(meta_data) do
		local normalized_attack_meta_data = normalize_attack_meta_data(attack_meta_data)
		if normalized_attack_meta_data then
			local utility = _score_attack(
				attack_input,
				normalized_attack_meta_data,
				target_armor,
				num_enemies,
				armored_type,
				super_armor_type
			)
			local prefer_light_tie = utility == best_utility
				and attack_input == "light_attack"
				and best_attack_input ~= "light_attack"

			if best_utility < utility or prefer_light_tie then
				best_attack_input = attack_input
				best_attack_meta_data = normalized_attack_meta_data
				best_utility = utility
			end
		end
	end

	return best_attack_meta_data or DEFAULT_ATTACK_META_DATA.light_attack
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
	local meta_data = type(weapon_meta_data) == "table" and weapon_meta_data or DEFAULT_ATTACK_META_DATA

	for attack_input, attack_meta_data in pairs(meta_data) do
		if attack_meta_data == chosen_attack_meta_data then
			return attack_input
		end
	end

	return "unknown"
end

local SPECIAL_WEAPON_POLICIES = {
	{
		family = "powersword_1h",
		prefixes = {
			"powersword_p1_",
			"powersword_p2_",
		},
		action_kinds = {
			activate_special = true,
			toggle_special_with_block = true,
		},
	},
	{
		family = "powersword_2h",
		prefixes = {
			"powersword_2h_",
		},
		action_kinds = {
			toggle_special = true,
			toggle_special_with_block = true,
		},
	},
	{
		family = "forcesword_1h",
		prefixes = {
			"forcesword_p1_",
		},
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "forcesword_2h",
		prefixes = {
			"forcesword_2h_",
		},
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "thunderhammer",
		prefixes = {
			"thunderhammer_",
		},
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "chain",
		prefixes = {
			"chainaxe_",
			"chainsword_",
		},
		action_kinds = {
			toggle_special = true,
		},
	},
	{
		family = "combat_axe_special",
		prefixes = {
			"combataxe_p1_",
			"combataxe_p2_",
			"combataxe_p3_m1",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "combat_sword_special",
		prefixes = {
			"combatsword_p2_",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "combat_knife_jab",
		prefixes = {
			"combatknife_p1_",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "ogryn_latrine_shovel",
		prefixes = {
			"ogryn_club_p1_m2",
			"ogryn_club_p1_m3",
		},
		action_kinds = {
			toggle_special = true,
		},
	},
	{
		family = "ogryn_club_uppercut",
		prefixes = {
			"ogryn_club_p1_m1",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "ogryn_club_fist",
		prefixes = {
			"ogryn_club_p2_",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "ogryn_pickaxe",
		prefixes = {
			"ogryn_pickaxe_2h_",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "ogryn_combatblade_uppercut",
		prefixes = {
			"ogryn_combatblade_p1_",
		},
		action_kinds = {
			sweep = true,
		},
	},
	{
		family = "powermaul",
		prefixes = {
			"powermaul_p1_",
			"powermaul_p2_",
			"powermaul_2h_",
		},
		action_kinds = {
			activate_special = true,
			sweep = true,
		},
	},
	{
		family = "ogryn_powermaul",
		prefixes = {
			"ogryn_powermaul_p1_",
		},
		action_kinds = {
			activate_special = true,
		},
	},
}

local function _starts_with(value, prefix)
	return type(value) == "string" and string.sub(value, 1, #prefix) == prefix
end

local function _resolve_special_weapon_policy_by_name(weapon_name)
	for i = 1, #SPECIAL_WEAPON_POLICIES do
		local policy = SPECIAL_WEAPON_POLICIES[i]

		for j = 1, #policy.prefixes do
			if _starts_with(weapon_name, policy.prefixes[j]) then
				return policy
			end
		end
	end

	return nil
end

local function _resolve_special_weapon_policy(weapon_template)
	return _resolve_special_weapon_policy_by_name(weapon_template and weapon_template.name or nil)
end

local function _resolve_special_action_meta(weapon_template)
	local policy = _resolve_special_weapon_policy(weapon_template)

	if not policy then
		return nil
	end

	for action_name, action in pairs(weapon_template.actions or {}) do
		if action.start_input == "special_action" and policy.action_kinds[action.kind] then
			local start_attack = (action.allowed_chain_actions or {}).start_attack
			local meta = {
				action_input = "special_action",
				action_name = action_name,
				chain_time = start_attack and start_attack.chain_time or action.activation_time or 0,
				family = policy.family,
			}

			if action.kind == "sweep" then
				_direct_special_meta[meta] = true
			end

			return meta
		end
	end

	local weapon_name = weapon_template and weapon_template.name or "unknown"
	if _debug_log and _debug_enabled and _debug_enabled() and not _logged_missing_special_action_meta[weapon_name] then
		_logged_missing_special_action_meta[weapon_name] = true
		_debug_log(
			"special_action_meta_missing:" .. weapon_name,
			_fixed_time and _fixed_time() or 0,
			"supported special family missing action metadata (weapon="
				.. tostring(weapon_name)
				.. ", family="
				.. tostring(policy.family)
				.. ")",
			nil,
			"debug"
		)
	end

	return nil
end

local function _is_power_sword_target(scratchpad, target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	local num_nearby = scratchpad and scratchpad.num_enemies_in_proximity or 0

	if target_breed and target_breed.is_boss then
		return true
	end

	if tags and (tags.monster or tags.captain or tags.elite or tags.special) then
		return true
	end

	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	return num_nearby >= 2 and num_nearby <= 3
end

local function _is_high_health_target(target_breed)
	local tags = target_breed and target_breed.tags or nil

	if target_breed and target_breed.is_boss then
		return true
	end

	if tags and (tags.monster or tags.captain) then
		return true
	end

	local breed_name = target_breed and target_breed.name or nil
	return breed_name ~= nil and HIGH_HEALTH_BREEDS[breed_name] == true or false
end

local function _is_force_sword_1h_target(_scratchpad, target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil

	if target_breed and target_breed.is_boss then
		return true
	end

	if tags and (tags.elite or tags.special or tags.monster or tags.captain) then
		return true
	end

	return _super_armor_type ~= nil and target_armor == _super_armor_type
end

local function _is_force_sword_2h_target(scratchpad, target_breed, target_armor)
	local inventory_slot_component = scratchpad and scratchpad.inventory_slot_component or nil
	local num_special_charges = inventory_slot_component and inventory_slot_component.num_special_charges or 0
	if num_special_charges < FORCE_SWORD_2H_MIN_CHARGES then
		return false
	end

	if (scratchpad and scratchpad.num_enemies_in_proximity or 0) < FORCE_SWORD_2H_MIN_ENEMIES then
		return false
	end

	if _is_armored_bucket(target_armor, _armored_type, _super_armor_type) then
		return false
	end

	if _is_high_health_target(target_breed) then
		return false
	end

	local tags = target_breed and target_breed.tags or nil

	return not (tags and (tags.elite or tags.special or tags.monster or tags.captain))
end

local function _is_thunder_hammer_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil

	if target_breed and target_breed.is_boss then
		return true
	end

	if tags and (tags.monster or tags.captain) then
		return true
	end

	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	return tags and tags.elite and _is_armored_bucket(target_armor, _armored_type, _super_armor_type) or false
end

local function _is_chain_special_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil

	if target_breed and target_breed.is_boss then
		return true
	end

	if tags and (tags.monster or tags.captain) then
		return true
	end

	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	return tags and tags.elite and _is_armored_bucket(target_armor, _armored_type, _super_armor_type) or false
end

local function _is_ogryn_latrine_shovel_target(target_breed, target_armor)
	return _is_high_health_target(target_breed) or _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
end

local function _is_ogryn_club_uppercut_target(target_breed, target_armor)
	return _is_high_health_target(target_breed) or _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
end

local function _is_direct_melee_special_target(target_breed, target_armor)
	return _is_high_health_target(target_breed) or _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
end

local function _is_powermaul_target(target_breed, target_armor)
	return _is_high_health_target(target_breed) or _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
end

local function _is_ogryn_latrine_shovel_heavy_target(target_breed, target_armor)
	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	return _is_high_health_target(target_breed) and _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
end

local function _is_priority_special_target(special_action_meta, scratchpad, target_breed, target_armor)
	if not special_action_meta then
		return false
	end

	if special_action_meta.family == "powersword_1h" or special_action_meta.family == "powersword_2h" then
		return _is_power_sword_target(scratchpad, target_breed, target_armor)
	end

	if special_action_meta.family == "forcesword_1h" then
		return _is_force_sword_1h_target(scratchpad, target_breed, target_armor)
	end

	if special_action_meta.family == "forcesword_2h" then
		return _is_force_sword_2h_target(scratchpad, target_breed, target_armor)
	end

	if special_action_meta.family == "thunderhammer" then
		return _is_thunder_hammer_target(target_breed, target_armor)
	end

	if special_action_meta.family == "chain" then
		return _is_chain_special_target(target_breed, target_armor)
	end

	if
		special_action_meta.family == "combat_axe_special"
		or special_action_meta.family == "combat_sword_special"
		or special_action_meta.family == "combat_knife_jab"
	then
		return _is_direct_melee_special_target(target_breed, target_armor)
	end

	if special_action_meta.family == "ogryn_latrine_shovel" then
		return _is_ogryn_latrine_shovel_target(target_breed, target_armor)
	end

	if special_action_meta.family == "ogryn_club_uppercut" then
		return _is_ogryn_club_uppercut_target(target_breed, target_armor)
	end

	if
		special_action_meta.family == "ogryn_club_fist"
		or special_action_meta.family == "ogryn_pickaxe"
		or special_action_meta.family == "ogryn_combatblade_uppercut"
	then
		return _is_direct_melee_special_target(target_breed, target_armor)
	end

	if special_action_meta.family == "powermaul" or special_action_meta.family == "ogryn_powermaul" then
		return _is_powermaul_target(target_breed, target_armor)
	end

	return false
end

local function _attack_meta_for_input(weapon_meta_data, attack_input)
	if type(weapon_meta_data) ~= "table" then
		return nil
	end

	local attack_meta_data = weapon_meta_data[attack_input]
	return normalize_attack_meta_data(attack_meta_data)
end

local function _can_activate_special(scratchpad)
	local weapon_extension = scratchpad and scratchpad.weapon_extension or nil

	if not weapon_extension or not weapon_extension.action_input_is_currently_valid then
		return false
	end

	return weapon_extension:action_input_is_currently_valid("weapon_action", "special_action", nil, _fixed_time())
end

local function _is_direct_special_meta(special_action_meta)
	return special_action_meta
		and (_direct_special_meta[special_action_meta] or special_action_meta.is_direct_attack) == true
end

local function _mark_direct_special_template(scratchpad, special_action_meta)
	if not _is_direct_special_meta(special_action_meta) then
		return
	end

	local weapon_template = scratchpad and scratchpad.weapon_template or nil
	if weapon_template and weapon_template.name then
		_direct_special_template_names[weapon_template.name] = true
	end
end

local function _direct_special_on_cooldown(scratchpad, special_action_meta)
	local unit = scratchpad and scratchpad.bb_unit or nil
	local family = special_action_meta and special_action_meta.family or nil
	if not (unit and family and _is_direct_special_meta(special_action_meta)) then
		return false
	end

	local last_t = _last_direct_special_t_by_unit[unit]
	local fixed_t = _fixed_time and _fixed_time() or 0
	if not last_t or fixed_t - last_t >= DIRECT_SPECIAL_REUSE_DELAY_S then
		return false
	end

	if _debug_log and _debug_enabled and _debug_enabled() then
		local key = tostring(unit) .. ":" .. tostring(family)
		if not _logged_special_pace_keys[key] then
			_logged_special_pace_keys[key] = true
			_debug_log(
				"melee_special_paced:" .. key,
				fixed_t,
				"melee direct special paced (family="
					.. tostring(family)
					.. ", elapsed="
					.. tostring(fixed_t - last_t)
					.. ", cooldown="
					.. tostring(DIRECT_SPECIAL_REUSE_DELAY_S)
					.. ")"
			)
		end
	end

	return true
end

local function _prepend_special_action(chosen_attack_meta_data, special_action_meta)
	local action_inputs = chosen_attack_meta_data and chosen_attack_meta_data.action_inputs or nil

	if
		type(action_inputs) ~= "table"
		or type(action_inputs[1]) ~= "table"
		or action_inputs[1].action_input ~= "start_attack"
	then
		return chosen_attack_meta_data
	end

	local wrapped = {}
	for key, value in pairs(chosen_attack_meta_data) do
		wrapped[key] = value
	end

	local wrapped_action_inputs = {
		{
			action_input = special_action_meta.action_input,
			timing = 0,
		},
	}

	for i = 1, #action_inputs do
		local source = action_inputs[i]
		local copy = {}

		for key, value in pairs(source) do
			copy[key] = value
		end

		if i == 1 then
			copy.timing = special_action_meta.chain_time or 0
		end

		wrapped_action_inputs[#wrapped_action_inputs + 1] = copy
	end

	wrapped.action_inputs = wrapped_action_inputs

	return wrapped
end

local function _maybe_wrap_special_attack(target_breed, target_armor, scratchpad, chosen_attack_meta_data)
	local special_action_meta = scratchpad and scratchpad.special_action_meta or nil
	local inventory_slot_component = scratchpad and scratchpad.inventory_slot_component or nil

	if
		not special_action_meta
		or not inventory_slot_component
		or inventory_slot_component.special_active
		or not _is_priority_special_target(special_action_meta, scratchpad, target_breed, target_armor)
		or _direct_special_on_cooldown(scratchpad, special_action_meta)
		or not _can_activate_special(scratchpad)
	then
		return chosen_attack_meta_data, false
	end

	_mark_direct_special_template(scratchpad, special_action_meta)

	return _prepend_special_action(chosen_attack_meta_data, special_action_meta), true
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

local function _target_breed(target_unit)
	local unit_data_extension = target_unit
			and ScriptUnit
			and ScriptUnit.has_extension
			and ScriptUnit.has_extension(target_unit, "unit_data_system")
		or nil

	return unit_data_extension and unit_data_extension.breed and unit_data_extension:breed() or nil
end

local function _num_melee_attackers(scratchpad)
	local attack_intensity_extension = scratchpad and scratchpad.attack_intensity_extension or nil
	if not attack_intensity_extension or not attack_intensity_extension.num_melee_attackers then
		return nil
	end

	local ok, attackers = pcall(attack_intensity_extension.num_melee_attackers, attack_intensity_extension)
	return ok and attackers or nil
end

local function _target_is_attacking_me(self, unit, target_unit)
	if not (self and self._is_attacking_me) then
		return false
	end

	local ok, attacking = pcall(self._is_attacking_me, self, unit, target_unit)
	return ok and attacking == true or false
end

local function _is_commit_defend_suppression_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	if target_breed and target_breed.is_boss or tags and (tags.monster or tags.captain) then
		return false
	end

	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	local armored_bucket = _is_armored_bucket(target_armor, _armored_type, _super_armor_type)
	if tags and (tags.elite or tags.special) and armored_bucket then
		return true
	end

	return _is_high_health_target(target_breed)
end

local function _log_defend_suppressed(unit, target_unit, scratchpad, target_breed, attackers, nearby)
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
		return
	end

	local weapon_template = scratchpad and scratchpad.weapon_template or nil
	local weapon_name = tostring(weapon_template and (weapon_template.name or weapon_template.display_name) or "weapon")
	local breed_name = tostring(target_breed and target_breed.name or "unknown")
	local key = tostring(unit)
		.. ":"
		.. tostring(target_unit)
		.. ":"
		.. tostring(attackers)
		.. ":"
		.. tostring(nearby)
		.. ":"
		.. weapon_name

	if _logged_defend_suppression_keys[key] then
		return
	end
	_logged_defend_suppression_keys[key] = true

	_debug_log(
		"melee_defend_suppressed:" .. key,
		_fixed_time(),
		"melee defend suppressed for attack commit (target="
			.. breed_name
			.. ", attackers="
			.. tostring(attackers)
			.. ", nearby="
			.. tostring(nearby)
			.. ", weapon="
			.. weapon_name
			.. ")"
	)
end

local function should_suppress_defend(self, unit, target_unit, scratchpad, target_breed_override)
	if _is_enabled and not _is_enabled() then
		return false
	end

	local attackers = _num_melee_attackers(scratchpad)
	if not attackers or attackers <= 0 or attackers > 2 then
		return false
	end

	local nearby = scratchpad and scratchpad.num_enemies_in_proximity or attackers
	if nearby > 3 then
		return false
	end

	local target_breed = target_breed_override or _target_breed(target_unit)
	local armor = _armor_api()
	local target_armor = armor and armor.armor_type(target_unit, target_breed) or nil
	if not _is_commit_defend_suppression_target(target_breed, target_armor) then
		return false
	end

	if _target_is_attacking_me(self, unit, target_unit) then
		return false
	end

	_log_defend_suppressed(unit, target_unit, scratchpad, target_breed, attackers, nearby)

	return true
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_armored_type = deps.ARMOR_TYPE_ARMORED
	_super_armor_type = deps.ARMOR_TYPE_SUPER_ARMOR
	_is_enabled = deps.is_enabled
	_melee_horde_light_bias = deps.melee_horde_light_bias
end

-- Called from the consolidated bt_bot_melee_action hook_require in BetterBots.lua (#67).
function M.install_melee_hooks(BtBotMeleeAction)
	if not BtBotMeleeAction or rawget(BtBotMeleeAction, MELEE_HOOK_PATCH_SENTINEL) then
		return
	end

	BtBotMeleeAction[MELEE_HOOK_PATCH_SENTINEL] = true

	_mod:hook(BtBotMeleeAction, "enter", function(func, self, unit, breed, blackboard, scratchpad, action_data, t)
		func(self, unit, breed, blackboard, scratchpad, action_data, t)

		if _is_enabled and not _is_enabled() then
			return
		end

		local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
		local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory") or nil
		local wielded_slot = inventory_component and inventory_component.wielded_slot or nil

		scratchpad.bb_unit = unit
		scratchpad.inventory_slot_component = wielded_slot and unit_data_extension:read_component(wielded_slot) or nil
		scratchpad.special_action_meta = _resolve_special_action_meta(scratchpad.weapon_template)
		_mark_direct_special_template(scratchpad, scratchpad.special_action_meta)
	end)

	_mod:hook(BtBotMeleeAction, "_choose_attack", function(func, self, target_unit, target_breed, scratchpad)
		if _is_enabled and not _is_enabled() then
			return func(self, target_unit, target_breed, scratchpad)
		end
		local num_enemies = scratchpad.num_enemies_in_proximity or 0
		local armor = _armor_api()
		local target_armor = armor and armor.armor_type(target_unit, target_breed) or nil
		local weapon_template = scratchpad.weapon_template or {}
		local chosen = choose_attack_meta_data(
			weapon_template.attack_meta_data,
			target_armor,
			num_enemies,
			_armored_type,
			_super_armor_type
		)

		local special_action_meta = scratchpad.special_action_meta or nil
		if
			special_action_meta
			and special_action_meta.family == "ogryn_latrine_shovel"
			and _is_ogryn_latrine_shovel_heavy_target(target_breed, target_armor)
		then
			chosen = _attack_meta_for_input(weapon_template.attack_meta_data, "heavy_attack") or chosen
		end

		local chosen_attack = _chosen_attack_input(weapon_template.attack_meta_data, chosen)
		local wrapped_special

		chosen, wrapped_special = _maybe_wrap_special_attack(target_breed, target_armor, scratchpad, chosen)
		local armored_bucket = _is_armored_bucket(target_armor, _armored_type, _super_armor_type)

		if _debug_enabled() and ((not armored_bucket and num_enemies > 1) or armored_bucket) then
			local weapon_name = tostring(weapon_template.name or weapon_template.display_name or "weapon")
			local armor_bucket = armored_bucket and "armored" or "unarmored"
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
			and not armored_bucket
			and num_enemies > 1
			and chosen == (weapon_template.attack_meta_data or {}).light_attack
		then
			_debug_log(
				"melee_light_bias:"
					.. tostring(weapon_template.name or weapon_template.display_name or "weapon")
					.. ":"
					.. tostring(scratchpad),
				_fixed_time(),
				"melee light-bias selected light attack for unarmored horde target"
			)
		end

		if _debug_enabled() and wrapped_special then
			_debug_log(
				"melee_special_prelude:"
					.. tostring(weapon_template.name or weapon_template.display_name or "weapon")
					.. ":"
					.. tostring(scratchpad),
				_fixed_time(),
				"melee special prelude queued before "
					.. tostring(chosen_attack)
					.. " (family="
					.. tostring((scratchpad.special_action_meta or {}).family or "powered")
					.. ")"
			)
		end

		return chosen
	end)
end

function M.register_hooks() end

function M.observe_queued_weapon_action(unit, action_input)
	if action_input ~= "special_action" then
		return
	end

	local unit_data_extension = unit
		and ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action") or nil
	local template_name = weapon_action_component and weapon_action_component.template_name or nil

	if _direct_special_template_names[template_name] then
		_last_direct_special_t_by_unit[unit] = _fixed_time and _fixed_time() or 0
	end
end

M.choose_attack_meta_data = choose_attack_meta_data
M.DEFAULT_ATTACK_META_DATA = DEFAULT_ATTACK_META_DATA
M.should_suppress_defend = should_suppress_defend

return M
