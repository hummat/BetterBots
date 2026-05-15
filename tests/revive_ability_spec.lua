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
local _saved_globals = {}

local _orig_require = require
local _ability_templates = {}
local _bot_actions = {}
local function _mock_require(path)
	if path == "scripts/settings/ability/ability_templates/ability_templates" then
		return _ability_templates
	end
	if path == "scripts/settings/breed/breed_actions/bot_actions" then
		return _bot_actions
	end
	if path:match("^scripts/") then
		return {}
	end
	return _orig_require(path)
end

local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local ReviveAbility = dofile("scripts/mods/BetterBots/revive_ability.lua")

setup(function()
	_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")
	_saved_globals.ALIVE = rawget(_G, "ALIVE")
	_saved_globals.HEALTH_ALIVE = rawget(_G, "HEALTH_ALIVE")
	_saved_globals.POSITION_LOOKUP = rawget(_G, "POSITION_LOOKUP")
	_saved_globals.Managers = rawget(_G, "Managers")
	_saved_globals.require = rawget(_G, "require")

	rawset(_G, "ScriptUnit", {
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
	})
	rawset(
		_G,
		"ALIVE",
		setmetatable({}, {
			__index = function()
				return true
			end,
		})
	)
	rawset(
		_G,
		"HEALTH_ALIVE",
		setmetatable({}, {
			__index = function()
				return true
			end,
		})
	)
	rawset(_G, "POSITION_LOOKUP", {})
	rawset(_G, "Managers", {
		state = {
			extension = {
				system = function()
					return nil
				end,
			},
		},
	})
	rawset(_G, "require", _mock_require)
end)

teardown(function()
	rawset(_G, "require", _saved_globals.require)
	rawset(_G, "Managers", _saved_globals.Managers)
	rawset(_G, "POSITION_LOOKUP", _saved_globals.POSITION_LOOKUP)
	rawset(_G, "HEALTH_ALIVE", _saved_globals.HEALTH_ALIVE)
	rawset(_G, "ALIVE", _saved_globals.ALIVE)
	rawset(_G, "ScriptUnit", _saved_globals.ScriptUnit)
end)

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

local function make_unit_data_ext(template_name, state_name)
	return test_helper.make_player_unit_data_extension({
		combat_ability_action = { template_name = template_name or "none" },
		character_state = { state_name = state_name or "walking" },
	})
end

local function setup_human_unit(unit, state_name, disabling_type, disabling_unit)
	_extensions[unit] = {
		unit_data_system = test_helper.make_player_unit_data_extension({
			combat_ability_action = { template_name = "none" },
			character_state = { state_name = state_name or "walking" },
			disabled_character_state = {
				is_disabled = disabling_type ~= nil,
				disabling_type = disabling_type or "none",
				disabling_unit = disabling_unit,
			},
		}),
	}
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
local _fixed_t = 100

local function init_module(opts)
	_fallback_state = {}
	_event_log_events = {}
	_debug_logs = {}
	_recorded_inputs = {}
	_suppressed = false
	_suppressed_reason = nil
	_combat_template_enabled = true
	_fixed_t = 100
	_bot_actions = opts and opts.bot_actions
		or {
			shoot = {
				aim_speed = { 10, 10, 12, 20, 20 },
			},
			shoot_priority_target = {},
		}

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
			return _fixed_t
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
		is_feature_enabled = function(feature_name)
			if opts and opts.disabled_features and opts.disabled_features[feature_name] then
				return false
			end
			return true
		end,
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

	it("loads without error", function()
		assert.is_table(ReviveAbility)
		assert.is_function(ReviveAbility.init)
		assert.is_function(ReviveAbility.wire)
		assert.is_function(ReviveAbility.try_pre_revive)
	end)

	it("patches priority shooting with vanilla aim speed metadata", function()
		assert.equals(_bot_actions.shoot.aim_speed, _bot_actions.shoot_priority_target.aim_speed)
	end)

	it("does not overwrite priority shooting aim speed when vanilla provides it", function()
		local vanilla_priority_aim_speed = { 8, 8, 10, 12, 12 }
		init_module({
			bot_actions = {
				shoot = {
					aim_speed = { 10, 10, 12, 20, 20 },
				},
				shoot_priority_target = {
					aim_speed = vanilla_priority_aim_speed,
				},
			},
		})

		assert.equals(vanilla_priority_aim_speed, _bot_actions.shoot_priority_target.aim_speed)
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

	describe("rescue priority", function()
		local function vec(x, y, z)
			return { x = x, y = y or 0, z = z or 0 }
		end

		local function make_priority_self(bot_unit, side, bot_data)
			local registered
			local aid_destination = {
				value = nil,
				store = function(self, value)
					self.value = value
				end,
				unbox = function(self)
					return self.value
				end,
			}
			local self = {
				_unit = bot_unit,
				_side = side,
				_behavior_component = {
					revive_with_urgent_target = false,
					interaction_unit = nil,
					target_ally_aid_destination = aid_destination,
				},
				_perception_component = {
					target_enemy = "priority_enemy",
					target_enemy_distance = 8,
					opportunity_target_enemy = "opportunity_enemy",
					priority_target_enemy = "priority_enemy",
					urgent_target_enemy = "urgent_enemy",
					target_ally = nil,
					target_ally_distance = math.huge,
					target_ally_needs_aid = false,
					target_ally_need_type = "n/a",
					force_aid = false,
				},
				_follow_component = {
					needs_destination_refresh = false,
				},
				_bot_group = {
					data = function()
						return bot_data or { [bot_unit] = {} }
					end,
					register_ally_needs_aid_priority = function(_, unit, target)
						registered = { unit = unit, target = target }
					end,
				},
			}

			return self, function()
				return registered
			end, aid_destination
		end

		before_each(function()
			init_module()
			for unit in pairs(_G.POSITION_LOOKUP) do
				_G.POSITION_LOOKUP[unit] = nil
			end
		end)

		it("assigns the nearest bot to a downed solo human and forces ally-aid path refresh", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)

			local self, registered = make_priority_self(bot, { valid_human_units = { human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(applied)
			assert.equals(human, self._perception_component.target_ally)
			assert.equals("knocked_down", self._perception_component.target_ally_need_type)
			assert.is_true(self._perception_component.target_ally_needs_aid)
			assert.is_true(self._behavior_component.revive_with_urgent_target)
			assert.is_true(self._follow_component.needs_destination_refresh)
			assert.is_true(self._perception_component.force_aid)
			assert.is_nil(self._perception_component.target_enemy)
			assert.is_nil(self._perception_component.opportunity_target_enemy)
			assert.is_nil(self._perception_component.priority_target_enemy)
			assert.is_nil(self._perception_component.urgent_target_enemy)
			assert.equals(math.huge, self._perception_component.target_enemy_distance)
			assert.equals(bot, registered().unit)
			assert.equals(human, registered().target)
		end)

		it("opens the vanilla revive condition when the assigned rescuer can already interact", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			local can_interact_args
			setup_human_unit(human, "knocked_down")
			_extensions[bot] = {
				interactor_system = test_helper.make_interactor_extension({
					can_interact = function(_, target, interaction_type)
						can_interact_args = { target = target, interaction_type = interaction_type }
						return true
					end,
				}),
			}
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(0.9)

			local self, _, aid_destination = make_priority_self(bot, { valid_human_units = { human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(applied)
			assert.same({ target = human, interaction_type = "revive" }, can_interact_args)
			assert.equals(human, self._behavior_component.interaction_unit)
			assert.equals(_G.POSITION_LOOKUP[bot], aid_destination.value)
		end)

		it("assigns the nearest bot to a netted solo human and forces remove-net path refresh", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			setup_human_unit(human, "walking", "netted")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)

			local self, registered = make_priority_self(bot, { valid_human_units = { human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(applied)
			assert.equals(human, self._perception_component.target_ally)
			assert.equals("netted", self._perception_component.target_ally_need_type)
			assert.is_true(self._perception_component.target_ally_needs_aid)
			assert.is_true(self._behavior_component.revive_with_urgent_target)
			assert.is_true(self._follow_component.needs_destination_refresh)
			assert.equals(bot, registered().unit)
			assert.equals(human, registered().target)
		end)

		it("assigns the nearest available bot to a netted bot ally", function()
			local rescuer = make_unit("bot_rescuer")
			local disabled_bot = make_unit("bot_netted")
			setup_human_unit(disabled_bot, "netted", "netted")
			_G.POSITION_LOOKUP[rescuer] = vec(0)
			_G.POSITION_LOOKUP[disabled_bot] = vec(3)

			local self, registered = make_priority_self(rescuer, {
				valid_human_units = {},
				valid_player_units = { rescuer, disabled_bot },
			}, {
				[rescuer] = {},
				[disabled_bot] = {},
			})

			local applied = ReviveAbility.apply_human_revive_priority(self, rescuer)

			assert.is_true(applied)
			assert.equals(disabled_bot, self._perception_component.target_ally)
			assert.equals("netted", self._perception_component.target_ally_need_type)
			assert.is_true(self._perception_component.target_ally_needs_aid)
			assert.is_true(self._behavior_component.revive_with_urgent_target)
			assert.is_true(self._follow_component.needs_destination_refresh)
			assert.equals(rescuer, registered().unit)
			assert.equals(disabled_bot, registered().target)
		end)

		it("prioritizes the disabler for pounced allies instead of forcing an unsupported interaction", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			local hound = make_unit("hound")
			setup_human_unit(human, "pounced", "pounced", hound)
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)
			_G.POSITION_LOOKUP[hound] = vec(4.5)
			_debug_on = true

			local self, registered = make_priority_self(bot, { valid_human_units = { human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(applied)
			assert.equals(human, self._perception_component.target_ally)
			assert.equals("pounced", self._perception_component.target_ally_need_type)
			assert.is_false(self._perception_component.target_ally_needs_aid)
			assert.equals(hound, self._perception_component.target_enemy)
			assert.equals(hound, self._perception_component.priority_target_enemy)
			assert.equals(hound, self._perception_component.urgent_target_enemy)
			assert.is_false(self._perception_component.force_aid)
			assert.truthy(
				string.find(_debug_logs[1].message, "need_type=pounced mode=disabler target_kind=human", 1, true)
			)
			assert.is_nil(registered())
		end)

		it("prioritizes disablers for hard-disabled allies that cannot be interact-rescued", function()
			local cases = {
				{ disabling_type = "pounced", enemy = "hound" },
				{ disabling_type = "mutant_charged", enemy = "mutant" },
				{ disabling_type = "grabbed", enemy = "chaos_spawn" },
				{ disabling_type = "consumed", enemy = "beast_of_nurgle" },
				{ disabling_type = "warp_grabbed", enemy = "daemonhost" },
			}

			for i, case in ipairs(cases) do
				init_module()
				local bot = make_unit("bot_" .. i)
				local human = make_unit("human_" .. i)
				local disabler = make_unit(case.enemy .. "_" .. i)
				setup_human_unit(human, case.disabling_type, case.disabling_type, disabler)
				_G.POSITION_LOOKUP[bot] = vec(0)
				_G.POSITION_LOOKUP[human] = vec(4)
				_G.POSITION_LOOKUP[disabler] = vec(4.5)

				local self = make_priority_self(bot, { valid_human_units = { human } })

				assert.is_true(ReviveAbility.apply_human_revive_priority(self, bot), case.disabling_type)
				assert.equals(human, self._perception_component.target_ally)
				assert.equals(case.disabling_type, self._perception_component.target_ally_need_type)
				assert.is_false(self._perception_component.target_ally_needs_aid)
				assert.is_false(self._behavior_component.revive_with_urgent_target)
				assert.equals(disabler, self._perception_component.target_enemy)
				assert.equals(disabler, self._perception_component.priority_target_enemy)
				assert.equals(disabler, self._perception_component.urgent_target_enemy)
			end
		end)

		it("prefers a disabled human over a closer disabled bot", function()
			local rescuer = make_unit("bot_rescuer")
			local disabled_bot = make_unit("bot_netted")
			local disabled_human = make_unit("human_netted")
			setup_human_unit(disabled_bot, "netted", "netted")
			setup_human_unit(disabled_human, "netted", "netted")
			_G.POSITION_LOOKUP[rescuer] = vec(0)
			_G.POSITION_LOOKUP[disabled_bot] = vec(2)
			_G.POSITION_LOOKUP[disabled_human] = vec(10)

			local self = make_priority_self(rescuer, {
				valid_human_units = { disabled_human },
				valid_player_units = { rescuer, disabled_bot, disabled_human },
			}, {
				[rescuer] = {},
				[disabled_bot] = {},
			})

			local applied = ReviveAbility.apply_human_revive_priority(self, rescuer)

			assert.is_true(applied)
			assert.equals(disabled_human, self._perception_component.target_ally)
			assert.equals("netted", self._perception_component.target_ally_need_type)
			assert.is_true(self._perception_component.target_ally_needs_aid)
		end)

		it("does not assign a disabled bot as the rescuer", function()
			local disabled_rescuer = make_unit("bot_disabled")
			local human = make_unit("human_downed")
			setup_human_unit(disabled_rescuer, "pounced", "pounced", make_unit("hound"))
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[disabled_rescuer] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)

			local self = make_priority_self(disabled_rescuer, { valid_human_units = { human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, disabled_rescuer)

			assert.is_false(applied)
			assert.is_nil(self._perception_component.target_ally)
			assert.is_false(self._behavior_component.revive_with_urgent_target)
		end)

		it("leaves non-nearest bots unassigned when multiple bots can reach the downed human", function()
			local far_bot = make_unit("bot_far")
			local near_bot = make_unit("bot_near")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[far_bot] = vec(0)
			_G.POSITION_LOOKUP[near_bot] = vec(8)
			_G.POSITION_LOOKUP[human] = vec(10)

			local self = make_priority_self(far_bot, { valid_human_units = { human } }, {
				[far_bot] = {},
				[near_bot] = {},
			})

			local applied = ReviveAbility.apply_human_revive_priority(self, far_bot)

			assert.is_false(applied)
			assert.is_nil(self._perception_component.target_ally)
			assert.is_false(self._behavior_component.revive_with_urgent_target)
		end)

		it("keeps the first assigned bot briefly even when another bot becomes slightly closer", function()
			local first_bot = make_unit("bot_first")
			local second_bot = make_unit("bot_second")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[first_bot] = vec(0)
			_G.POSITION_LOOKUP[second_bot] = vec(4)
			_G.POSITION_LOOKUP[human] = vec(1)

			local bot_data = {
				[first_bot] = {},
				[second_bot] = {},
			}
			local first_self = make_priority_self(first_bot, { valid_human_units = { human } }, bot_data)
			local second_self = make_priority_self(second_bot, { valid_human_units = { human } }, bot_data)

			assert.is_true(ReviveAbility.apply_human_revive_priority(first_self, first_bot))

			_fixed_t = 101
			_G.POSITION_LOOKUP[first_bot] = vec(1.3)
			_G.POSITION_LOOKUP[second_bot] = vec(0.8)

			assert.is_false(ReviveAbility.apply_human_revive_priority(second_self, second_bot))
			assert.is_nil(second_self._perception_component.target_ally)
			assert.is_false(second_self._behavior_component.revive_with_urgent_target)
			assert.is_true(ReviveAbility.apply_human_revive_priority(first_self, first_bot))
			assert.equals(human, first_self._perception_component.target_ally)
		end)

		it("allows a closer bot to take over after the revive owner lease expires", function()
			local first_bot = make_unit("bot_first")
			local second_bot = make_unit("bot_second")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[first_bot] = vec(0)
			_G.POSITION_LOOKUP[second_bot] = vec(4)
			_G.POSITION_LOOKUP[human] = vec(1)

			local bot_data = {
				[first_bot] = {},
				[second_bot] = {},
			}
			local first_self = make_priority_self(first_bot, { valid_human_units = { human } }, bot_data)
			local second_self = make_priority_self(second_bot, { valid_human_units = { human } }, bot_data)

			assert.is_true(ReviveAbility.apply_human_revive_priority(first_self, first_bot))

			_fixed_t = 105
			_G.POSITION_LOOKUP[first_bot] = vec(5)
			_G.POSITION_LOOKUP[second_bot] = vec(1.2)

			assert.is_true(ReviveAbility.apply_human_revive_priority(second_self, second_bot))
			assert.equals(human, second_self._perception_component.target_ally)
			assert.is_true(second_self._behavior_component.revive_with_urgent_target)
		end)

		it("releases the current owner when another bot becomes much closer", function()
			local first_bot = make_unit("bot_first")
			local second_bot = make_unit("bot_second")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[first_bot] = vec(0)
			_G.POSITION_LOOKUP[second_bot] = vec(8)
			_G.POSITION_LOOKUP[human] = vec(1)

			local bot_data = {
				[first_bot] = {},
				[second_bot] = {},
			}
			local first_self = make_priority_self(first_bot, { valid_human_units = { human } }, bot_data)
			local second_self = make_priority_self(second_bot, { valid_human_units = { human } }, bot_data)

			assert.is_true(ReviveAbility.apply_human_revive_priority(first_self, first_bot))

			_fixed_t = 101
			_G.POSITION_LOOKUP[first_bot] = vec(8)
			_G.POSITION_LOOKUP[second_bot] = vec(1.2)

			assert.is_true(ReviveAbility.apply_human_revive_priority(first_self, first_bot))
			assert.is_nil(first_self._perception_component.target_ally)
			assert.is_false(first_self._behavior_component.revive_with_urgent_target)
			assert.is_true(ReviveAbility.apply_human_revive_priority(second_self, second_bot))
			assert.equals(human, second_self._perception_component.target_ally)
			assert.is_true(second_self._behavior_component.revive_with_urgent_target)
			assert.is_false(ReviveAbility.apply_human_revive_priority(first_self, first_bot))
			assert.is_nil(first_self._perception_component.target_ally)
			assert.is_false(first_self._behavior_component.revive_with_urgent_target)
		end)

		it("still prioritizes a downed human over bot or enemy targets when another human is active", function()
			local bot = make_unit("bot_1")
			local downed_human = make_unit("human_downed")
			local active_human = make_unit("human_active")
			setup_human_unit(downed_human, "knocked_down")
			setup_human_unit(active_human, "walking")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[downed_human] = vec(5)
			_G.POSITION_LOOKUP[active_human] = vec(1)

			local self = make_priority_self(bot, { valid_human_units = { active_human, downed_human } })

			local applied = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(applied)
			assert.equals(downed_human, self._perception_component.target_ally)
			assert.is_true(self._behavior_component.revive_with_urgent_target)
		end)

		it("logs priority assignments with bot and human discriminators", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)
			_debug_on = true

			local self = make_priority_self(bot, { valid_human_units = { human } })

			assert.is_true(ReviveAbility.apply_human_revive_priority(self, bot))

			assert.equals(1, #_debug_logs)
			assert.equals("human_revive_priority:" .. tostring(bot) .. ":" .. tostring(human), _debug_logs[1].key)
			assert.truthy(string.find(_debug_logs[1].message, "[bot=1]", 1, true))
			assert.truthy(string.find(_debug_logs[1].message, "target=" .. tostring(human), 1, true))
		end)

		it("cleans up its forced target when the human is no longer knocked down", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)

			local self = make_priority_self(bot, { valid_human_units = { human } })
			assert.is_true(ReviveAbility.apply_human_revive_priority(self, bot))
			self._behavior_component.interaction_unit = human

			setup_human_unit(human, "walking")
			local cleared = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(cleared)
			assert.is_nil(self._perception_component.target_ally)
			assert.equals("n/a", self._perception_component.target_ally_need_type)
			assert.is_false(self._perception_component.target_ally_needs_aid)
			assert.is_false(self._perception_component.force_aid)
			assert.is_false(self._behavior_component.revive_with_urgent_target)
			assert.is_nil(self._behavior_component.interaction_unit)
			assert.is_true(self._follow_component.needs_destination_refresh)
		end)

		it("cleans up its forced target when the setting is disabled", function()
			local bot = make_unit("bot_1")
			local human = make_unit("human_1")
			setup_human_unit(human, "knocked_down")
			_G.POSITION_LOOKUP[bot] = vec(0)
			_G.POSITION_LOOKUP[human] = vec(4)

			local self = make_priority_self(bot, { valid_human_units = { human } })
			assert.is_true(ReviveAbility.apply_human_revive_priority(self, bot))

			init_module({ disabled_features = { human_revive_priority = true } })
			local cleared = ReviveAbility.apply_human_revive_priority(self, bot)

			assert.is_true(cleared)
			assert.is_nil(self._perception_component.target_ally)
			assert.is_false(self._behavior_component.revive_with_urgent_target)
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
