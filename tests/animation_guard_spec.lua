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

	it("falls back to plain anim_event for bot units when the variable id is invalid without warning", function()
		local AnimationGuard = load_animation_guard()
		local hook_handler
		local warnings = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, method_name, handler)
				if method_name == "anim_event_with_variable_float" then
					hook_handler = handler
				end
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
		assert.equals(0, #warnings)
	end)

	it("falls back to plain anim_event when variable lookup throws", function()
		local AnimationGuard = load_animation_guard()
		local hook_handler
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, method_name, handler)
				if method_name == "anim_event_with_variable_float" then
					hook_handler = handler
				end
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
			hook = function(_, _, method_name, handler)
				if method_name == "anim_event_with_variable_float" then
					hook_handler = handler
				end
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

	-- Disruptive character states emit anim events straight after wielding a
	-- different slot. If the wielded state machine lacks the event, the engine
	-- raises through DMF's hook chain and takes the session down. Bots must
	-- degrade to a wrong-looking animation instead of a crash.
	describe("anim_event crash guard", function()
		local missing_event_error = "stingray::plugin_api::unit::animation_event failed, "
			.. "state machine `#ID[f70fd69d9db3e65e]` does not have an event with name `#ID[14a07e0f]`"

		local function setup(method_name)
			local AnimationGuard = load_animation_guard()
			local handlers = {}
			local warnings = {}
			local stub_mod = {
				hook_require = function(_, _, callback)
					callback({})
				end,
				hook = function(_, _, hooked_name, handler)
					handlers[hooked_name] = handler
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

			return handlers[method_name], warnings
		end

		local function bot_self()
			return {
				_unit = "bot_unit",
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
			}
		end

		it("swallows a failed bot anim_event and warns once per event name", function()
			local handler, warnings = setup("anim_event")
			assert.is_function(handler)

			local raising = function()
				error(missing_event_error)
			end

			assert.has_no.errors(function()
				handler(raising, bot_self(), "airtime_bwd")
			end)
			assert.equals(1, #warnings)
			assert.is_truthy(warnings[1]:find("airtime_bwd", 1, true))

			handler(raising, bot_self(), "airtime_bwd")
			assert.equals(1, #warnings)

			handler(raising, bot_self(), "airtime_fwd")
			assert.equals(2, #warnings)
		end)

		it("passes a successful bot anim_event through untouched", function()
			local handler, warnings = setup("anim_event")
			local seen_event
			local result = handler(function(_self, event_name)
				seen_event = event_name
				return 42
			end, bot_self(), "swing")

			assert.equals("swing", seen_event)
			assert.equals(42, result)
			assert.equals(0, #warnings)
		end)

		-- player_character_state_catapulted.lua:106 fires anim_event_1p before
		-- anim_event, so guarding only the third-person call leaves the crash
		-- reachable one line earlier.
		it("swallows a failed bot anim_event_1p", function()
			local handler, warnings = setup("anim_event_1p")
			assert.is_function(handler)

			assert.has_no.errors(function()
				handler(function()
					error(missing_event_error)
				end, bot_self(), "airtime_bwd_1p")
			end)
			assert.equals(1, #warnings)
			assert.is_truthy(warnings[1]:find("airtime_bwd_1p", 1, true))
		end)

		it("does not depend on the Stingray error detail wording", function()
			local handler, warnings = setup("anim_event")

			assert.has_no.errors(function()
				handler(function()
					error("stingray::plugin_api::unit::animation_event failed, rejected animation event")
				end, bot_self(), "airtime_bwd")
			end)
			assert.equals(1, #warnings)
		end)

		it("lets unrelated bot anim_event errors raise", function()
			local handler, warnings = setup("anim_event")

			assert.has_error(function()
				handler(function()
					error("animation state recorder failed")
				end, bot_self(), "airtime_bwd")
			end)
			assert.equals(0, #warnings)
		end)

		it("lets a failed human anim_event raise so vanilla bugs stay visible", function()
			local handler = setup("anim_event")
			local human_self = {
				_unit = "human_unit",
				_player = {
					is_human_controlled = function()
						return true
					end,
				},
			}

			assert.has_error(function()
				handler(function()
					error("boom")
				end, human_self, "airtime_bwd")
			end)
		end)
	end)
end)
