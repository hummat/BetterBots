-- animation_guard.lua — degrade invalid bot anim-event variable writes to a
-- plain anim event so bot-only item abilities cannot crash the animation path.
-- luacheck: globals Unit
local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _fixed_time
local _warned_keys = {}

local INVALID_ANIMATION_VARIABLE_INDEX = 4294967295

local function is_valid_variable_index(variable_index)
	return variable_index ~= nil and variable_index ~= INVALID_ANIMATION_VARIABLE_INDEX
end

local function _warn_once(key, message)
	if _warned_keys[key] then
		return
	end

	_warned_keys[key] = true

	if _mod and _mod.warning then
		_mod:warning(message)
	end
end

local function _is_bot_unit(self)
	local player = self and self._player
	return player and player.is_human_controlled and not player:is_human_controlled()
end

local function _safe_animation_find_variable(unit, variable_name)
	local ok, variable_index = pcall(Unit.animation_find_variable, unit, variable_name)
	if not ok then
		return nil, "lookup_failed"
	end

	if not is_valid_variable_index(variable_index) then
		return nil, "invalid_variable"
	end

	return variable_index
end

local function register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/animation/authoritative_player_unit_animation_extension",
		function(AuthoritativePlayerUnitAnimationExtension)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_float",
				function(func, self, event_name, variable_name, variable_value)
					if not _is_bot_unit(self) then
						return func(self, event_name, variable_name, variable_value)
					end

					local unit = self and self._unit
					local variable_index
					local failure_reason
					if unit then
						variable_index, failure_reason = _safe_animation_find_variable(unit, variable_name)
					end

					if not variable_index then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:" .. tostring(variable_name) .. ":" .. tostring(failure_reason),
								_fixed_time(),
								"animation guard fell back to plain anim_event for "
									.. tostring(variable_name)
									.. " ("
									.. tostring(failure_reason)
									.. ")",
								nil,
								"info"
							)
						end

						_warn_once(
							tostring(variable_name) .. ":" .. tostring(failure_reason),
							"BetterBots: animation guard fell back to plain anim_event for " .. tostring(variable_name)
						)

						return self:anim_event(event_name)
					end

					return func(self, event_name, variable_name, variable_value)
				end
			)
		end
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
	end,
	register_hooks = register_hooks,
	is_valid_variable_index = is_valid_variable_index,
	_safe_animation_find_variable = _safe_animation_find_variable,
}
