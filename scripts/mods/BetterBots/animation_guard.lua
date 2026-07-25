-- animation_guard.lua — degrade invalid bot anim-event variable writes to a
-- plain anim event so bot-only item abilities cannot crash the animation path.
-- luacheck: globals Unit
local _mod -- luacheck: ignore 231

local function _hook_require_now(path, callback)
	local hook_require_now = _mod and _mod.hook_require_now
	if hook_require_now then
		return hook_require_now(_mod, path, callback, 4)
	end

	if _mod and _mod.warning and _mod._raw_hook_require then
		_mod:warning("BetterBots: hook_require_now_missing for " .. tostring(path))
	end
	return _mod["hook_require"](_mod, path, callback)
end

local _debug_log
local _debug_enabled
local _fixed_time

local INVALID_ANIMATION_VARIABLE_INDEX = 4294967295
local ANIMATION_EXTENSION_SENTINEL = "__bb_animation_guard_installed"
local ANIMATION_EVENT_API_ERROR = "stingray::plugin_api::unit::animation_event failed"

-- Event names come from a fixed engine set, so a plain string-keyed table
-- cannot grow without bound.
local _warned_anim_events = {}

local function is_valid_variable_index(variable_index)
	return variable_index ~= nil and variable_index ~= INVALID_ANIMATION_VARIABLE_INDEX
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

local function _is_animation_event_api_error(err)
	local message = tostring(err)
	return message:find(ANIMATION_EVENT_API_ERROR, 1, true) ~= nil
end

-- Disruptive character states (catapulted, pounced, netted, grabbed, ledge) wield
-- a slot and then immediately emit an anim event. If the wielded state machine
-- lacks that event, `Unit.animation_event` raises through DMF's hook chain and
-- ends the session. A wrong-looking bot animation is always better than a crash,
-- so bots degrade to a logged warning. Humans keep the raise: their path is
-- vanilla and a swallowed error there would hide a real bug.
local function _guard_bot_anim_event(method_name)
	return function(func, self, event_name, ...)
		if not _is_bot_unit(self) then
			return func(self, event_name, ...)
		end

		local ok, result = pcall(func, self, event_name, ...)
		if ok then
			return result
		end
		if not _is_animation_event_api_error(result) then
			error(result, 0)
		end

		local warn_key = method_name .. ":" .. tostring(event_name)
		if not _warned_anim_events[warn_key] then
			_warned_anim_events[warn_key] = true
			if _mod and _mod.warning then
				_mod:warning(
					"BetterBots: suppressed failed bot "
						.. method_name
						.. " '"
						.. tostring(event_name)
						.. "' ("
						.. tostring(result)
						.. ")"
				)
			end
		end

		return nil
	end
end

local function register_hooks()
	_hook_require_now(
		"scripts/extension_systems/animation/authoritative_player_unit_animation_extension",
		function(AuthoritativePlayerUnitAnimationExtension)
			if
				not AuthoritativePlayerUnitAnimationExtension
				or rawget(AuthoritativePlayerUnitAnimationExtension, ANIMATION_EXTENSION_SENTINEL)
			then
				return
			end

			AuthoritativePlayerUnitAnimationExtension[ANIMATION_EXTENSION_SENTINEL] = true

			_mod:hook(AuthoritativePlayerUnitAnimationExtension, "anim_event", _guard_bot_anim_event("anim_event"))

			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_1p",
				_guard_bot_anim_event("anim_event_1p")
			)

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
