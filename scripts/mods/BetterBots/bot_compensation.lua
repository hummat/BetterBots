local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_config_identifier_override
local _bot_incoming_damage_reduction_enabled
local _unpack = rawget(table or {}, "unpack") or unpack

local BOT_SPAWNING_PATH = "scripts/managers/bot/bot_spawning"
local MINION_ATTACK_PATH = "scripts/utilities/minion_attack"
local BOT_SPAWNING_SENTINEL = "__bb_bot_compensation_installed"
local MINION_ATTACK_SENTINEL = "__bb_bot_compensation_installed"
local _logged_config_identifiers = {}

local MINION_ATTACK_DAMAGE_HOOKS = {
	{
		method = "shoot_hit_scan",
		kind = "ranged",
		target_arg = 4,
		modifier_arg = 8,
	},
	{
		method = "sweep",
		kind = "melee",
		target_arg = 6,
		modifier_arg = 7,
	},
	{
		method = "melee",
		kind = "melee",
		target_arg = 5,
		modifier_arg = 6,
	},
	{
		method = "update_lag_compensation_melee",
		kind = "melee",
		target_getter = function(args)
			local scratchpad = args[3]
			return scratchpad and scratchpad.lag_compensation_target_unit or nil
		end,
		modifier_arg = 6,
	},
}

M.MINION_ATTACK_DAMAGE_HOOKS = MINION_ATTACK_DAMAGE_HOOKS

local function _damage_reduction_enabled()
	if not _bot_incoming_damage_reduction_enabled then
		return true
	end

	return _bot_incoming_damage_reduction_enabled() ~= false
end

local function _with_cleared_field(owner, field_name, callback)
	local original_value = owner[field_name]
	owner[field_name] = nil

	local ok, result = pcall(callback)

	owner[field_name] = original_value
	if not ok then
		error(result, 0)
	end

	return result
end

local function _log_modifier_suppressed(kind, target_unit, owner)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(
		"bot_compensation:" .. kind .. ":" .. tostring(target_unit),
		_fixed_time and _fixed_time() or 0,
		"suppressed base-game bot incoming damage modifier on " .. kind .. " attack (" .. tostring(owner) .. ")",
		nil,
		"info"
	)
end

local function _log_config_identifier(source, identifier)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	local key = "bot_compensation:profile:" .. source .. ":" .. tostring(identifier)
	if _logged_config_identifiers[key] then
		return
	end

	_logged_config_identifiers[key] = true
	_debug_log(
		key,
		_fixed_time and _fixed_time() or 0,
		"bot compensation profile " .. source .. ": " .. tostring(identifier),
		nil,
		"info"
	)
end

local function _call_original(func, args)
	return func(_unpack(args, 1, args.n))
end

local function _install_minion_attack_damage_hook(MinionAttack, spec)
	_mod:hook(MinionAttack, spec.method, function(func, ...)
		local args = { n = select("#", ...), ... }
		local modifier_owner = args[spec.modifier_arg]

		if _damage_reduction_enabled() or not (modifier_owner and modifier_owner.bot_power_level_modifier) then
			return _call_original(func, args)
		end

		local target_unit = spec.target_getter and spec.target_getter(args) or args[spec.target_arg]

		_log_modifier_suppressed(spec.kind, target_unit, modifier_owner)

		-- action_data/shoot_template are shared engine tables. The mutation is
		-- deliberately bounded to the synchronous vanilla attack call.
		return _with_cleared_field(modifier_owner, "bot_power_level_modifier", function()
			return _call_original(func, args)
		end)
	end)
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_config_identifier_override = deps.bot_config_identifier_override
	_bot_incoming_damage_reduction_enabled = deps.bot_incoming_damage_reduction_enabled
end

function M.register_hooks()
	_mod:hook_require(BOT_SPAWNING_PATH, function(BotSpawning)
		if BotSpawning[BOT_SPAWNING_SENTINEL] then
			return
		end

		_mod:hook(BotSpawning, "get_bot_config_identifier", function(func)
			local override = _bot_config_identifier_override and _bot_config_identifier_override() or nil
			if override then
				_log_config_identifier("override", override)
				return override
			end

			local identifier = func()
			_log_config_identifier("base-game", identifier)

			return identifier
		end)

		BotSpawning[BOT_SPAWNING_SENTINEL] = true
	end)

	_mod:hook_require(MINION_ATTACK_PATH, function(MinionAttack)
		if MinionAttack[MINION_ATTACK_SENTINEL] then
			return
		end

		for i = 1, #MINION_ATTACK_DAMAGE_HOOKS do
			_install_minion_attack_damage_hook(MinionAttack, MINION_ATTACK_DAMAGE_HOOKS[i])
		end

		MinionAttack[MINION_ATTACK_SENTINEL] = true
	end)
end

return M
