-- airlock_guard.lua — guard against vanilla door_extension.lua crash when
-- more bots exist than hardcoded teleport nodes.
-- Fatshark's teleport_bots() indexes a 4-entry node name table without a nil
-- guard, causing "bad argument #2 to 'has_node' (string expected, got nil)"
-- when bot count exceeds the number of door teleport locations.
-- BetterBots doesn't modify bot counts, but users running SoloPlay mods
-- commonly hit this edge case.

local _mod

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
local _warned = false
local DOOR_EXTENSION_SENTINEL = "__bb_airlock_guard_installed"

local function _is_known_nil_node_crash(err)
	local message = tostring(err)

	return message:find("bad argument #2 to 'has_node'", 1, true) ~= nil
		and message:find("string expected, got nil", 1, true) ~= nil
end

local function register_hooks()
	_hook_require_now("scripts/extension_systems/door/door_extension", function(DoorExtension)
		if not DoorExtension or rawget(DoorExtension, DOOR_EXTENSION_SENTINEL) then
			return
		end

		DoorExtension[DOOR_EXTENSION_SENTINEL] = true

		_mod:hook(DoorExtension, "teleport_bots", function(func, self)
			local ok, err = pcall(func, self)
			if not ok then
				if not _is_known_nil_node_crash(err) then
					error(err, 0)
				end

				if not _warned then
					_warned = true
					if _mod.warning then
						_mod:warning(
							"BetterBots: airlock teleport guard caught vanilla crash — bots will catch up normally"
						)
					end
				end
				if _debug_enabled() then
					_debug_log(
						"airlock_guard:teleport",
						_fixed_time(),
						"airlock teleport guarded — vanilla crash prevented: " .. tostring(err),
						nil,
						"warning"
					)
				end
			end
		end)
	end)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
	end,
	register_hooks = register_hooks,
}
