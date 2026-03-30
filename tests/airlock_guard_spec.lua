local function load_airlock_guard()
	local ok, airlock_guard = pcall(dofile, "scripts/mods/BetterBots/airlock_guard.lua")
	assert.is_true(ok, "airlock_guard.lua should load")
	return airlock_guard
end

describe("airlock_guard", function()
	it("calls through to original teleport_bots when it succeeds", function()
		local AirlockGuard = load_airlock_guard()
		local hook_handler
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
			warning = function() end,
		}

		AirlockGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AirlockGuard.register_hooks()

		local original_called = false
		hook_handler(function()
			original_called = true
		end, { _unit = "door_unit" })

		assert.is_true(original_called)
	end)

	it("catches crashes and warns once", function()
		local AirlockGuard = load_airlock_guard()
		local hook_handler
		local warnings = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
			warning = function(_, message)
				warnings[#warnings + 1] = message
			end,
		}

		AirlockGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AirlockGuard.register_hooks()

		-- First crash: should warn
		hook_handler(function()
			error("bad argument #2 to 'has_node' (string expected, got nil)")
		end, { _unit = "door_unit" })

		assert.equals(1, #warnings)
		assert.truthy(warnings[1]:find("airlock teleport guard"))

		-- Second crash: should not warn again
		hook_handler(function()
			error("bad argument #2 to 'has_node' (string expected, got nil)")
		end, { _unit = "door_unit_2" })

		assert.equals(1, #warnings)
	end)

	it("logs when debug is enabled", function()
		local AirlockGuard = load_airlock_guard()
		local hook_handler
		local logged = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
			warning = function() end,
		}

		AirlockGuard.init({
			mod = stub_mod,
			debug_log = function(key, _, message)
				logged[#logged + 1] = { key = key, message = message }
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 5.0
			end,
		})
		AirlockGuard.register_hooks()

		hook_handler(function()
			error("has_node boom")
		end, { _unit = "door_unit" })

		assert.equals(1, #logged)
		assert.equals("airlock_guard:teleport", logged[1].key)
		assert.truthy(logged[1].message:find("vanilla crash prevented"))
	end)

	it("hooks the correct module path", function()
		local AirlockGuard = load_airlock_guard()
		local hooked_path
		local stub_mod = {
			hook_require = function(_, path, callback)
				hooked_path = path
				callback({})
			end,
			hook = function() end,
			warning = function() end,
		}

		AirlockGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AirlockGuard.register_hooks()

		assert.equals("scripts/extension_systems/door/door_extension", hooked_path)
	end)
end)
