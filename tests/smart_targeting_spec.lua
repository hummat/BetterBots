local test_helper = require("tests.test_helper")

local function load_smart_targeting()
	local ok, smart_targeting = pcall(dofile, "scripts/mods/BetterBots/smart_targeting.lua")
	assert.is_true(ok, "smart_targeting.lua should load")
	return smart_targeting
end

describe("smart_targeting", function()
	it("prefers the bot perception target enemy", function()
		local SmartTargeting = load_smart_targeting()
		local target = SmartTargeting.resolve_bot_target_unit({
			target_enemy = "enemy_1",
			priority_target_enemy = "enemy_2",
		})

		assert.equals("enemy_1", target)
	end)

	it("returns nil when the bot has no current perception target", function()
		local SmartTargeting = load_smart_targeting()
		assert.is_nil(SmartTargeting.resolve_bot_target_unit({}))
	end)

	it("registers a fixed_update hook that preserves the original logic for bots", function()
		local SmartTargeting = load_smart_targeting()
		local hook_handler
		local debug_logs = {}
		local stub_mod = {
			hook_require = function(_, path, callback)
				assert.equals(
					"scripts/extension_systems/weapon/actions/modules/smart_target_targeting_action_module",
					path
				)
				callback({})
			end,
			hook = function(_, _, method_name, handler)
				assert.equals("fixed_update", method_name)
				hook_handler = handler
			end,
		}

		SmartTargeting.init({
			mod = stub_mod,
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 12.5
			end,
		})
		SmartTargeting.register_hooks()

		local targeting_data = { unit = "vanilla_target" }
		local component = {}
		local seen_target_during_original
		local original_calls = 0
		local self = {
			_unit = "bot_unit",
			_component = component,
			_unit_data_extension = test_helper.make_player_unit_data_extension({
				perception = {
					target_enemy = "bot_target",
				},
			}, {
				is_resimulating = false,
			}),
			_smart_targeting_extension = {
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				targeting_data = function()
					return targeting_data
				end,
			},
		}

		hook_handler(function(_self)
			original_calls = original_calls + 1
			seen_target_during_original = targeting_data.unit
			_self._component.target_unit_1 = seen_target_during_original
		end, self, 0.1, 99)

		assert.equals(1, original_calls)
		assert.equals("bot_target", seen_target_during_original)
		assert.equals("bot_target", component.target_unit_1)
		assert.equals("vanilla_target", targeting_data.unit)
		assert.equals(1, #debug_logs)
	end)

	it("passes through unchanged for human-controlled units", function()
		local SmartTargeting = load_smart_targeting()
		local hook_handler
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
		}

		SmartTargeting.init({
			mod = stub_mod,
			debug_log = function()
				error("debug_log should not fire for humans")
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 0
			end,
		})
		SmartTargeting.register_hooks()

		local original_calls = 0
		local self = {
			_unit_data_extension = {
				is_resimulating = false,
			},
			_smart_targeting_extension = {
				_player = {
					is_human_controlled = function()
						return true
					end,
				},
			},
		}

		hook_handler(function()
			original_calls = original_calls + 1
		end, self, 0.1, 99)

		assert.equals(1, original_calls)
	end)

	it("logs target confirmation even when vanilla targeting already matches bot perception", function()
		local SmartTargeting = load_smart_targeting()
		local hook_handler
		local debug_logs = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				callback({})
			end,
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
		}

		SmartTargeting.init({
			mod = stub_mod,
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 7
			end,
		})
		SmartTargeting.register_hooks()

		local targeting_data = { unit = "bot_target" }
		local self = {
			_component = {},
			_unit_data_extension = test_helper.make_player_unit_data_extension({
				perception = {
					target_enemy = "bot_target",
				},
			}, {
				is_resimulating = false,
			}),
			_smart_targeting_extension = {
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				targeting_data = function()
					return targeting_data
				end,
			},
		}

		hook_handler(function() end, self, 0.1, 99)

		assert.equals(1, #debug_logs)
		assert.matches("smart targeting using bot perception target", debug_logs[1].message, 1, true)
	end)

	-- #81: settings wiring
	it("passes through to vanilla when is_enabled returns false", function()
		local SmartTargeting = load_smart_targeting()
		local hook_handler
		local stub_mod = {
			hook_require = function(_, _path, callback)
				callback({})
			end,
			hook = function(_, _, _method_name, handler)
				hook_handler = handler
			end,
		}

		SmartTargeting.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			is_enabled = function()
				return false
			end,
		})
		SmartTargeting.register_hooks()

		local targeting_data = { unit = "vanilla_target" }
		local original_called = false
		local self = {
			_unit_data_extension = test_helper.make_player_unit_data_extension({
				perception = { target_enemy = "bot_target" },
			}),
			_smart_targeting_extension = {
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				targeting_data = function()
					return targeting_data
				end,
			},
			_component = {},
		}

		hook_handler(function()
			original_called = true
		end, self, 0.1, 99)

		assert.is_true(original_called)
		-- targeting_data.unit should remain unchanged (vanilla passthrough)
		assert.equals("vanilla_target", targeting_data.unit)
	end)

	it("is idempotent when the hook_require callback fires twice on the same SmartTargetingActionModule", function()
		local SmartTargeting = load_smart_targeting()
		local hook_calls = 0
		local captured_callback
		local shared_module = {}
		local stub_mod = {
			hook_require = function(_, _, callback)
				captured_callback = callback
			end,
			hook = function(_, _, _, _)
				hook_calls = hook_calls + 1
			end,
		}

		SmartTargeting.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})
		SmartTargeting.register_hooks()

		captured_callback(shared_module)
		captured_callback(shared_module)

		assert.equals(1, hook_calls)
	end)
end)
