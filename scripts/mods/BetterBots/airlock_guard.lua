-- airlock_guard.lua — guard against vanilla door_extension.lua crash when
-- more bots exist than hardcoded teleport nodes.
-- Fatshark's teleport_bots() indexes a 4-entry node name table without a nil
-- guard, causing "bad argument #2 to 'has_node' (string expected, got nil)"
-- when bot count exceeds the number of door teleport locations.
-- BetterBots doesn't modify bot counts, but users running SoloPlay mods
-- commonly hit this edge case.

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _warned = false

local function register_hooks()
	_mod:hook_require("scripts/extension_systems/door/door_extension", function(DoorExtension)
		_mod:hook(DoorExtension, "teleport_bots", function(func, self)
			local ok, err = pcall(func, self)
			if not ok then
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
