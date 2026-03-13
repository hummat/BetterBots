local function load_animation_guard()
	local ok, animation_guard = pcall(dofile, "scripts/mods/BetterBots/animation_guard.lua")
	assert.is_true(ok, "animation_guard.lua should load")
	return animation_guard
end

describe("animation_guard", function()
	local _saved_unit

	before_each(function()
		_saved_unit = _G.Unit
	end)

	after_each(function()
		_G.Unit = _saved_unit
	end)

	it("treats nil variable ids as invalid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_false(AnimationGuard.is_valid_variable_index(nil))
	end)

	it("treats 0xFFFFFFFF sentinel variable ids as invalid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_false(AnimationGuard.is_valid_variable_index(4294967295))
	end)

	it("treats normal variable ids as valid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_true(AnimationGuard.is_valid_variable_index(17))
	end)

	it("falls back to plain anim_event for bot units when the variable id is invalid", function()
		local AnimationGuard = load_animation_guard()
		local hook_handler
		local warnings = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, method_name, handler)
				assert.equals("anim_event_with_variable_float", method_name)
				hook_handler = handler
			end,
			warning = function(_, message)
				warnings[#warnings + 1] = message
			end,
		}

		AnimationGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AnimationGuard.register_hooks()

		_G.Unit = {
			animation_find_variable = function()
				return 4294967295
			end,
		}

		local original_called = false
		local fallback_event_name
		local self = {
			_unit = "bot_unit",
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			anim_event = function(_, event_name)
				fallback_event_name = event_name
			end,
		}

		hook_handler(function()
			original_called = true
		end, self, "deploy_drone", "dodge_time", 0.5)

		assert.is_false(original_called)
		assert.equals("deploy_drone", fallback_event_name)
		assert.equals(1, #warnings)
	end)

	it("falls back to plain anim_event when variable lookup throws", function()
		local AnimationGuard = load_animation_guard()
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

		AnimationGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AnimationGuard.register_hooks()

		_G.Unit = {
			animation_find_variable = function()
				error("boom")
			end,
		}

		local fallback_event_name
		local self = {
			_unit = "bot_unit",
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			anim_event = function(_, event_name)
				fallback_event_name = event_name
			end,
		}

		hook_handler(function()
			error("original should not run")
		end, self, "deploy_drone", "dodge_time", 0.5)

		assert.equals("deploy_drone", fallback_event_name)
	end)

	it("passes through unchanged for human-controlled units", function()
		local AnimationGuard = load_animation_guard()
		local hook_handler
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
			warning = function()
				error("warning should not run for humans")
			end,
		}

		AnimationGuard.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		AnimationGuard.register_hooks()

		_G.Unit = {
			animation_find_variable = function()
				error("lookup should not run for humans")
			end,
		}

		local original_called = false
		local self = {
			_unit = "human_unit",
			_player = {
				is_human_controlled = function()
					return true
				end,
			},
			anim_event = function()
				error("fallback should not run for humans")
			end,
		}

		hook_handler(function(_self, event_name, variable_name, variable_value)
			original_called = true
			assert.equals("swing", event_name)
			assert.equals("swing_speed", variable_name)
			assert.equals(1.5, variable_value)
		end, self, "swing", "swing_speed", 1.5)

		assert.is_true(original_called)
	end)
end)
