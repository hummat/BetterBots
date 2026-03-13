local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _fixed_time

local INVALID_ANIMATION_VARIABLE_INDEX = 4294967295

local function is_valid_variable_index(variable_index)
	return variable_index ~= nil and variable_index ~= INVALID_ANIMATION_VARIABLE_INDEX
end

local function register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/animation/authoritative_player_unit_animation_extension",
		function(AuthoritativePlayerUnitAnimationExtension)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_float",
				function(func, self, event_name, variable_name, variable_value)
					local unit = self and self._unit
					local variable_index = unit and Unit.animation_find_variable(unit, variable_name)

					if not is_valid_variable_index(variable_index) then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:" .. tostring(variable_name),
								_fixed_time(),
								"skipped invalid animation variable " .. tostring(variable_name),
								nil,
								"info"
							)
						end
						return
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
}
