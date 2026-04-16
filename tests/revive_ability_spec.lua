-- tests/revive_ability_spec.lua
local test_helper = require("tests.test_helper")

local _extensions = {}
local _debug_logs = {}
local _debug_on = false
local _recorded_inputs = {}
local _suppressed = false
local _suppressed_reason = nil
local _combat_template_enabled = true
local _hook_require_callbacks = {}
local _hook_safe_calls = {}

_G.ScriptUnit = {
	has_extension = function(unit, system_name)
		local unit_exts = _extensions[unit]
		return unit_exts and unit_exts[system_name] or nil
	end,
	extension = function(unit, system_name)
		local ext = _extensions[unit] and _extensions[unit][system_name]
		if not ext then
			error("No extension " .. system_name .. " for " .. tostring(unit))
		end
		return ext
	end,
}
_G.ALIVE = setmetatable({}, {
	__index = function()
		return true
	end,
})
_G.Managers = { state = { extension = {
	system = function()
		return nil
	end,
} } }

local _orig_require = require
local _ability_templates = {}
local function _mock_require(path)
	if path == "scripts/settings/ability/ability_templates/ability_templates" then
		return _ability_templates
	end
	if path:match("^scripts/") then
		return {}
	end
	return _orig_require(path)
end
rawset(_G, "require", _mock_require)

local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local ReviveAbility = dofile("scripts/mods/BetterBots/revive_ability.lua")

-- Mock factories
local function make_unit(id)
	return { _test_id = id or "bot_1" }
end

local function make_action_input_ext()
	return test_helper.make_player_action_input_extension({
		bot_queue_action_input = function(_, component, input, raw)
			_recorded_inputs[#_recorded_inputs + 1] = {
				component = component,
				input = input,
				raw = raw,
			}
		end,
		action_input_parsers = {},
	})
end

local function make_ability_ext(can_use, charges, opts)
	local combat_ability_name = opts and opts.combat_ability_name or "test_combat_ability"
	local combat_ability_tweak_data = opts and opts.combat_ability_tweak_data or nil
	return test_helper.make_player_ability_extension({
		can_use_ability = function(_, _ability_type)
			return can_use
		end,
		remaining_ability_charges = function(_, _ability_type)
			return charges or 1
		end,
		action_input_is_currently_valid = function(_, _ability_component_name, _action_input, _used_input, _fixed_t)
			return true
		end,
		_equipped_abilities = {
			combat_ability = {
				name = combat_ability_name,
				ability_template_tweak_data = combat_ability_tweak_data,
			},
		},
	})
end

local function make_unit_data_ext(template_name)
	return test_helper.make_player_unit_data_extension({
		combat_ability_action = { template_name = template_name or "none" },
	})
end

local _perception_enemy_count = 3

local function make_perception_ext(num_enemies)
	return test_helper.make_bot_perception_extension({
		enemies_in_proximity = function()
			local n = num_enemies or _perception_enemy_count
			return {}, n
		end,
	})
end

local function setup_unit(unit, template_name, can_use, charges, num_enemies, opts)
	local action_input_ext = make_action_input_ext()
	local ability_ext = make_ability_ext(can_use ~= false, charges or 1, opts)
	local unit_data_ext = make_unit_data_ext(template_name)
	local perception_ext = make_perception_ext(num_enemies)
	_extensions[unit] = {
		unit_data_system = unit_data_ext,
		ability_system = ability_ext,
		action_input_system = action_input_ext,
		perception_system = perception_ext,
	}
	return action_input_ext, ability_ext, unit_data_ext
end

local function make_blackboard()
	return {}
end

local _fallback_state = {}
local _event_log_events = {}

local function init_module()
	_fallback_state = {}
	_event_log_events = {}
	_debug_logs = {}
	_recorded_inputs = {}
	_suppressed = false
	_suppressed_reason = nil
	_combat_template_enabled = true

	ReviveAbility.init({
		mod = {
			echo = function() end,
			hook = function() end,
			hook_require = function() end,
		},
		debug_log = function(key, fixed_t, message)
			_debug_logs[#_debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
		end,
		debug_enabled = function()
			return _debug_on
		end,
		fixed_time = function()
			return 100
		end,
		is_suppressed = function()
			return _suppressed, _suppressed_reason
		end,
		equipped_combat_ability_name = function()
			return "test_ability"
		end,
		fallback_state_by_unit = _fallback_state,
		perf = nil,
		shared_rules = SharedRules,
		combat_ability_identity = CombatAbilityIdentity,
	})

	local mock_meta_data = {
		inject = function() end,
	}
	local mock_event_log = {
		is_enabled = function()
			return true
		end,
		emit = function(evt)
			_event_log_events[#_event_log_events + 1] = evt
		end,
	}
	local mock_debug = {
		bot_slot_for_unit = function()
			return 1
		end,
	}

	ReviveAbility.wire({
		MetaData = mock_meta_data,
		EventLog = mock_event_log,
		Debug = mock_debug,
		is_combat_template_enabled = function()
			return _combat_template_enabled
		end,
	})
end

describe("revive_ability", function()
	before_each(function()
		_extensions = {}
		init_module()
	end)

	teardown(function()
		rawset(_G, "require", _orig_require)
	end)

	it("loads without error", function()
		assert.is_table(ReviveAbility)
		assert.is_function(ReviveAbility.init)
		assert.is_function(ReviveAbility.wire)
		assert.is_function(ReviveAbility.try_pre_revive)
	end)

	describe("try_pre_revive", function()
		local unit, blackboard

		before_each(function()
			_debug_on = true
			unit = make_unit("bot_1")
			blackboard = make_blackboard()
		end)

		it("queues ability for revive interaction with enemies nearby", function()
			setup_unit(unit, "ogryn_taunt_shout")
			_ability_templates.ogryn_taunt_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
			local action_data = { interaction_type = "revive" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals(1, #_recorded_inputs)
			assert.equals("combat_ability_action", _recorded_inputs[1].component)
			assert.equals("shout_pressed", _recorded_inputs[1].input)
		end)

		it("sets up fallback state machine for hold+release", function()
			setup_unit(unit, "psyker_shout")
			_ability_templates.psyker_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
			local action_data = { interaction_type = "revive" }
			ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			local state = _fallback_state[unit]
			assert.is_not_nil(state)
			assert.is_true(state.active)
			assert.equals(100 + 0.075, state.hold_until)
			assert.equals("shout_released", state.wait_action_input)
			assert.is_false(state.wait_sent)
		end)

		it("queues stealth ability (zealot_invisibility)", function()
			setup_unit(unit, "zealot_invisibility")
			_ability_templates.zealot_invisibility = {
				ability_meta_data = {
					activation = { action_input = "stance_pressed" },
				},
			}
			local action_data = { interaction_type = "revive" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals("stance_pressed", _recorded_inputs[1].input)
		end)

		it("queues veteran stealth ability", function()
			setup_unit(unit, "veteran_stealth_combat_ability")
			_ability_templates.veteran_stealth_combat_ability = {
				ability_meta_data = {
					activation = { action_input = "combat_ability_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "combat_ability_released" },
				},
			}
			local action_data = { interaction_type = "rescue" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals("combat_ability_pressed", _recorded_inputs[1].input)
		end)

		it("queues veteran voice of command but not veteran stance", function()
			setup_unit(unit, "veteran_combat_ability", true, 1, nil, {
				combat_ability_name = "veteran_combat_ability_shout",
			})
			_ability_templates.veteran_combat_ability = {
				ability_meta_data = {
					activation = { action_input = "combat_ability_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "combat_ability_released" },
				},
			}
			local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.is_true(result)
			assert.equals("combat_ability_pressed", _recorded_inputs[1].input)

			_recorded_inputs = {}
			setup_unit(unit, "veteran_combat_ability", true, 1, nil, {
				combat_ability_name = "veteran_combat_ability_stance",
				combat_ability_tweak_data = { class_tag = "squad_leader" },
			})
			result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.is_false(result)
			assert.equals(0, #_recorded_inputs)
		end)

		it("queues adamant stance during revive", function()
			setup_unit(unit, "adamant_stance")
			_ability_templates.adamant_stance = {
				ability_meta_data = {
					activation = { action_input = "stance_pressed" },
				},
			}
			local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.is_true(result)
			assert.equals("stance_pressed", _recorded_inputs[1].input)
		end)

		describe("rejection guards", function()
			before_each(function()
				_ability_templates.ogryn_taunt_shout = {
					ability_meta_data = {
						activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
						wait_action = { action_input = "shout_released" },
					},
				}
			end)

			it("rejects non-rescue interaction types", function()
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "health_station" })
				assert.is_false(result)
				assert.equals(0, #_recorded_inputs)
			end)

			it("rejects nil action_data", function()
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, nil)
				assert.is_false(result)
			end)

			it("rejects when no enemies nearby", function()
				setup_unit(unit, "ogryn_taunt_shout", true, 1, 0)
				blackboard = make_blackboard()
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when suppressed", function()
				_suppressed = true
				_suppressed_reason = "dodging"
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects non-whitelisted ability (charge)", function()
				setup_unit(unit, "ogryn_charge")
				_ability_templates.ogryn_charge = {
					ability_meta_data = {
						activation = { action_input = "aim_pressed", min_hold_time = 0.01 },
						wait_action = { action_input = "aim_released" },
					},
				}
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects non-whitelisted ability (stance)", function()
				setup_unit(unit, "veteran_combat_ability")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when ability on cooldown", function()
				setup_unit(unit, "ogryn_taunt_shout", false)
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when no charges remaining", function()
				setup_unit(unit, "ogryn_taunt_shout", true, 0)
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when category disabled", function()
				_combat_template_enabled = false
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("fires for all rescue interaction types", function()
				for _, itype in ipairs({ "revive", "rescue", "pull_up", "remove_net" }) do
					_recorded_inputs = {}
					_fallback_state = {}
					ReviveAbility.init({
						mod = { echo = function() end, hook = function() end, hook_require = function() end },
						debug_log = function() end,
						debug_enabled = function()
							return false
						end,
						fixed_time = function()
							return 100
						end,
						is_suppressed = function()
							return false
						end,
						equipped_combat_ability_name = function()
							return "test"
						end,
						fallback_state_by_unit = _fallback_state,
						shared_rules = SharedRules,
						combat_ability_identity = CombatAbilityIdentity,
					})
					ReviveAbility.wire({
						MetaData = { inject = function() end },
						EventLog = {
							is_enabled = function()
								return false
							end,
						},
						Debug = {
							bot_slot_for_unit = function()
								return 1
							end,
						},
						is_combat_template_enabled = function()
							return true
						end,
					})
					setup_unit(unit, "ogryn_taunt_shout")
					local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = itype })
					assert.is_true(result, "expected true for interaction_type=" .. itype)
				end
			end)
		end)
	end)

	describe("logging", function()
		local unit, blackboard

		before_each(function()
			unit = make_unit("bot_1")
			blackboard = make_blackboard()
			init_module()
			setup_unit(unit, "adamant_shout")
			_ability_templates.adamant_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
		end)

		it("emits debug log with per-bot key", function()
			_debug_on = true
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.is_true(#_debug_logs > 0)
			local log = _debug_logs[1]
			assert.truthy(string.find(log.key, "revive_ability:"))
			assert.truthy(string.find(log.key, "adamant_shout"))
			assert.truthy(string.find(log.key, tostring(unit)))
		end)

		it("does not emit debug log when debug disabled", function()
			_debug_on = false
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.equals(0, #_debug_logs)
		end)

		it("emits event log with interaction type", function()
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "rescue" })
			assert.equals(1, #_event_log_events)
			local evt = _event_log_events[1]
			assert.equals("revive_ability", evt.event)
			assert.equals("adamant_shout", evt.template)
			assert.equals("rescue", evt.interaction)
			assert.equals(3, evt.enemies)
		end)

		it("logs revive candidates before interact enter for defensive revive templates", function()
			setup_unit(unit, "veteran_combat_ability", true, 1, nil, {
				combat_ability_name = "veteran_combat_ability_shout",
			})
			local behavior_component = { interaction_unit = make_unit("downed_ally") }
			local perception_component = {
				target_ally = behavior_component.interaction_unit,
				target_ally_needs_aid = true,
				target_ally_need_type = "knocked_down",
			}

			_debug_on = true
			ReviveAbility.log_revive_candidate(unit, behavior_component, perception_component)

			assert.is_true(#_debug_logs > 0)
			local log = _debug_logs[1]
			assert.truthy(string.find(log.key, "revive_candidate:"))
			assert.truthy(string.find(log.message, "veteran_combat_ability_shout"))
			assert.truthy(string.find(log.message, "knocked_down"))
		end)

		it("does not log revive candidates for non-defensive shared templates", function()
			setup_unit(unit, "veteran_combat_ability", true, 1, nil, {
				combat_ability_name = "veteran_combat_ability_stance",
				combat_ability_tweak_data = { class_tag = "squad_leader" },
			})
			local ally = make_unit("downed_ally")

			_debug_on = true
			ReviveAbility.log_revive_candidate(unit, { interaction_unit = ally }, {
				target_ally = ally,
				target_ally_needs_aid = true,
				target_ally_need_type = "knocked_down",
			})

			assert.equals(0, #_debug_logs)
		end)
	end)

	describe("register_hooks", function()
		it("wraps BtBotInteractAction.enter and runs pre-revive logic", function()
			local unit = make_unit("bot_1")
			local blackboard = make_blackboard()
			local fake_mod = {
				echo = function() end,
				hook = function() end,
				hook_safe = function(_, target, method, handler)
					_hook_safe_calls[#_hook_safe_calls + 1] = { target = target, method = method, handler = handler }
				end,
				hook_require = function(_, path, callback)
					_hook_require_callbacks[path] = callback
				end,
			}

			ReviveAbility.init({
				mod = fake_mod,
				debug_log = function(key, fixed_t, message)
					_debug_logs[#_debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 100
				end,
				is_suppressed = function()
					return false
				end,
				equipped_combat_ability_name = function()
					return "test_ability"
				end,
				fallback_state_by_unit = _fallback_state,
				perf = nil,
				shared_rules = SharedRules,
				combat_ability_identity = CombatAbilityIdentity,
			})
			ReviveAbility.wire({
				MetaData = { inject = function() end },
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})
			setup_unit(unit, "ogryn_taunt_shout")
			_ability_templates.ogryn_taunt_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}

			ReviveAbility.register_hooks()
			local interact_require =
				_hook_require_callbacks["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action"]
			assert.is_not_nil(interact_require)

			local enter_called = 0
			local fake_action = {
				enter = function(_self, enter_unit, _breed, _blackboard, _scratchpad, action_data, _t)
					enter_called = enter_called + 1
					assert.equals(unit, enter_unit)
					assert.equals("revive", action_data.interaction_type)
					return "orig_enter"
				end,
			}
			interact_require(fake_action)

			local result = fake_action.enter(fake_action, unit, nil, blackboard, {}, { interaction_type = "revive" }, 0)
			assert.equals("orig_enter", result)
			assert.equals(1, enter_called)
			assert.equals(1, #_recorded_inputs)
			assert.equals("shout_pressed", _recorded_inputs[1].input)
		end)

		it("does not register a BotBehaviorExtension hook_require via register_hooks", function()
			local fake_mod = {
				echo = function() end,
				hook = function() end,
				hook_safe = function(_, target, method, handler)
					_hook_safe_calls[#_hook_safe_calls + 1] = { target = target, method = method, handler = handler }
				end,
				hook_require = function(_, path, callback)
					_hook_require_callbacks[path] = callback
				end,
			}

			ReviveAbility.init({
				mod = fake_mod,
				debug_log = function(key, fixed_t, message)
					_debug_logs[#_debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 100
				end,
				is_suppressed = function()
					return false
				end,
				equipped_combat_ability_name = function()
					return "test_ability"
				end,
				fallback_state_by_unit = _fallback_state,
				perf = nil,
				shared_rules = SharedRules,
				combat_ability_identity = CombatAbilityIdentity,
			})
			ReviveAbility.wire({
				MetaData = { inject = function() end },
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			ReviveAbility.register_hooks()

			assert.is_nil(_hook_require_callbacks["scripts/extension_systems/behavior/bot_behavior_extension"])
			assert.is_function(ReviveAbility.on_refresh_destination)
		end)

		it("is idempotent when the hook_require callback fires twice on the same BtBotInteractAction", function()
			local unit = make_unit("bot_1")
			local blackboard = make_blackboard()
			local fake_mod = {
				echo = function() end,
				hook = function() end,
				hook_safe = function(_, target, method, handler)
					_hook_safe_calls[#_hook_safe_calls + 1] = { target = target, method = method, handler = handler }
				end,
				hook_require = function(_, path, callback)
					_hook_require_callbacks[path] = callback
				end,
			}

			ReviveAbility.init({
				mod = fake_mod,
				debug_log = function(key, fixed_t, message)
					_debug_logs[#_debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 100
				end,
				is_suppressed = function()
					return false
				end,
				equipped_combat_ability_name = function()
					return "test_ability"
				end,
				fallback_state_by_unit = _fallback_state,
				perf = nil,
				shared_rules = SharedRules,
				combat_ability_identity = CombatAbilityIdentity,
			})
			ReviveAbility.wire({
				MetaData = { inject = function() end },
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})
			setup_unit(unit, "ogryn_taunt_shout")
			_ability_templates.ogryn_taunt_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}

			ReviveAbility.register_hooks()
			local interact_require =
				_hook_require_callbacks["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action"]
			local fake_action = {
				enter = function()
					return "orig_enter"
				end,
			}

			interact_require(fake_action)
			interact_require(fake_action)

			fake_action.enter(fake_action, unit, nil, blackboard, {}, { interaction_type = "revive" }, 0)

			assert.equals(1, #_recorded_inputs)
		end)
	end)
end)
