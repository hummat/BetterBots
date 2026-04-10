-- Tests for condition_patch.lua daemonhost combat suppression wrappers (#17).
-- Verifies that melee/ranged combat is suppressed only when the bot's
-- current target IS a dormant daemonhost, not when any DH is nearby.
local _extensions = {}
local _blackboards = {}
local _debug_logs = {}
local _debug_enabled_result = false

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

_G.BLACKBOARDS = setmetatable({}, {
	__index = function(_, unit)
		return _blackboards[unit]
	end,
})

_G.POSITION_LOOKUP = {}
_G.Vector3 = {
	distance_squared = function(a, b)
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return dx * dx + dy * dy + dz * dz
	end,
}
local _alive = {}
_G.ALIVE = setmetatable({}, {
	__index = function(_, unit)
		return _alive[unit]
	end,
})
_G.Managers = { state = { extension = {
	system = function()
		return nil
	end,
} } }

-- Stub require so condition_patch.lua doesn't crash on game modules
local _orig_require = require
local function _mock_require(path)
	if path:match("^scripts/") then
		return {}
	end
	return _orig_require(path)
end
rawset(_G, "require", _mock_require)

local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local ConditionPatch = dofile("scripts/mods/BetterBots/condition_patch.lua")

-- Restore require
rawset(_G, "require", _orig_require)

-- Initialize with minimal deps
ConditionPatch.init({
	shared_rules = SharedRules,
	mod = { echo = function() end, hook_require = function() end },
	debug_log = function(key, fixed_t, message)
		_debug_logs[#_debug_logs + 1] = {
			key = key,
			fixed_t = fixed_t,
			message = message,
		}
	end,
	debug_enabled = function()
		return _debug_enabled_result
	end,
	fixed_time = function()
		return 0
	end,
	is_suppressed = function()
		return false
	end,
	equipped_combat_ability_name = function()
		return "none"
	end,
	patched_bt_bot_conditions = {},
	patched_bt_conditions = {},
	rescue_intent = {},
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 5,
	CONDITIONS_PATCH_VERSION = "test",
})

ConditionPatch.wire({
	Heuristics = {
		resolve_decision = function()
			return false
		end,
	},
	MetaData = { inject = function() end },
	Debug = {
		log_ability_decision = function() end,
		bot_slot_for_unit = function()
			return 1
		end,
	},
	EventLog = {
		is_enabled = function()
			return false
		end,
	},
})

-- Helper: set up unit_data extension for a breed (marks unit alive)
local function setup_breed(unit, breed_name)
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].unit_data_system = {
		breed = function()
			return { name = breed_name }
		end,
	}
	_alive[unit] = true
end

-- Helper: build a blackboard with a target_enemy
local function make_blackboard(target_enemy)
	return {
		perception = {
			target_enemy = target_enemy,
			target_enemy_type = "melee",
			target_enemy_distance = 5,
		},
		behavior = {},
	}
end

-- Reset mocks between tests
local function reset()
	for k in pairs(_extensions) do
		_extensions[k] = nil
	end
	for k in pairs(_blackboards) do
		_blackboards[k] = nil
	end
	for k in pairs(_alive) do
		_alive[k] = nil
	end
	_debug_logs = {}
	_debug_enabled_result = false
end

local function find_debug_log(pattern)
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			return _debug_logs[i]
		end
	end

	return nil
end

local function find_debug_log_by_key(key)
	for i = 1, #_debug_logs do
		if _debug_logs[i].key == key then
			return _debug_logs[i]
		end
	end

	return nil
end

describe("condition_patch", function()
	before_each(function()
		reset()
	end)

	describe("_action_input_is_bot_queueable", function()
		it("accepts parser-level ability inputs even when action validation rejects them", function()
			local action_input_extension = {
				_action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							veteran_combat_ability = {
								stance_pressed = {
									buffer_time = 0.5,
								},
							},
						},
					},
				},
			}
			local ability_extension = {
				action_input_is_currently_valid = function()
					return false
				end,
			}

			assert.is_true(
				ConditionPatch._action_input_is_bot_queueable(
					action_input_extension,
					ability_extension,
					"combat_ability_action",
					"veteran_combat_ability",
					"stance_pressed",
					nil,
					0
				)
			)
		end)
	end)

	describe("_is_dormant_daemonhost_target", function()
		it("returns false when target is not a daemonhost", function()
			local target = "poxwalker1"
			setup_breed(target, "chaos_poxwalker")
			local bb = make_blackboard(target)
			assert.is_false(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns true when target is a dormant daemonhost", function()
			local target = "dh1"
			setup_breed(target, "chaos_daemonhost")
			local bb = make_blackboard(target)
			-- No BLACKBOARDS entry → conservative (treat as dormant)
			assert.is_true(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns true for dormant mutator daemonhost target", function()
			local target = "mdh1"
			setup_breed(target, "chaos_mutator_daemonhost")
			local bb = make_blackboard(target)
			assert.is_true(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns false when target daemonhost is aggroed", function()
			local target = "dh_aggro"
			setup_breed(target, "chaos_daemonhost")
			_blackboards[target] = { perception = { aggro_state = "aggroed" } }
			local bb = make_blackboard(target)
			assert.is_false(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns true when target daemonhost is alerted (non-aggroed)", function()
			local target = "dh_alert"
			setup_breed(target, "chaos_daemonhost")
			_blackboards[target] = { perception = { aggro_state = "alerted" } }
			local bb = make_blackboard(target)
			assert.is_true(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns false when target enemy is dead", function()
			local target = "dh_dead"
			setup_breed(target, "chaos_daemonhost")
			_alive[target] = nil -- dead
			local bb = make_blackboard(target)
			assert.is_false(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns false when no target enemy", function()
			local bb = { perception = { target_enemy = nil } }
			assert.is_false(ConditionPatch._is_dormant_daemonhost_target("bot1", bb))
		end)

		it("returns false when no blackboard", function()
			assert.is_false(ConditionPatch._is_dormant_daemonhost_target("bot1", nil))
		end)
	end)

	describe("combat wrapper integration", function()
		it("allows melee against non-DH target with sleeping DH nearby", function()
			-- Bot targets a poxwalker. A sleeping DH is nearby but not the target.
			local target = "poxwalker1"
			local dh = "dh_sleeping"
			setup_breed(target, "chaos_poxwalker")
			setup_breed(dh, "chaos_daemonhost")

			local bb = make_blackboard(target)
			local melee_called = false
			local conditions = {
				bot_in_melee_range = function()
					melee_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.bot_in_melee_range("bot1", bb, {}, {}, {}, false)
			assert.is_true(result)
			assert.is_true(melee_called)
		end)

		it("suppresses melee against dormant daemonhost target", function()
			local target = "dh1"
			setup_breed(target, "chaos_daemonhost")

			local bb = make_blackboard(target)
			local orig_called = false
			local conditions = {
				bot_in_melee_range = function()
					orig_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.bot_in_melee_range("bot1", bb, {}, {}, {}, false)
			assert.is_false(result)
			assert.is_false(orig_called) -- original never called
		end)

		it("allows melee against aggroed daemonhost target", function()
			local target = "dh_aggro"
			setup_breed(target, "chaos_daemonhost")
			_blackboards[target] = { perception = { aggro_state = "aggroed" } }

			local bb = make_blackboard(target)
			local orig_called = false
			local conditions = {
				bot_in_melee_range = function()
					orig_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.bot_in_melee_range("bot1", bb, {}, {}, {}, false)
			assert.is_true(result)
			assert.is_true(orig_called)
		end)

		it("allows melee against dormant daemonhost when avoidance is disabled", function()
			ConditionPatch.init({
				shared_rules = SharedRules,
				mod = { echo = function() end, hook_require = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
				is_suppressed = function()
					return false
				end,
				equipped_combat_ability_name = function()
					return "none"
				end,
				patched_bt_bot_conditions = {},
				patched_bt_conditions = {},
				rescue_intent = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 5,
				CONDITIONS_PATCH_VERSION = "test",
				is_daemonhost_avoidance_enabled = function()
					return false
				end,
			})

			local target = "dh_avoidance_off"
			setup_breed(target, "chaos_daemonhost")

			local bb = make_blackboard(target)
			local orig_called = false
			local conditions = {
				bot_in_melee_range = function()
					orig_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test_dh_off")

			local result = conditions.bot_in_melee_range("bot1", bb, {}, {}, {}, false)
			assert.is_true(result) -- not suppressed when avoidance disabled
			assert.is_true(orig_called) -- original was called

			-- Re-init without the gate for other tests
			ConditionPatch.init({
				shared_rules = SharedRules,
				mod = { echo = function() end, hook_require = function() end },
				debug_log = function(key, fixed_t, message)
					_debug_logs[#_debug_logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
					}
				end,
				debug_enabled = function()
					return _debug_enabled_result
				end,
				fixed_time = function()
					return 0
				end,
				is_suppressed = function()
					return false
				end,
				equipped_combat_ability_name = function()
					return "none"
				end,
				patched_bt_bot_conditions = {},
				patched_bt_conditions = {},
				rescue_intent = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 5,
				CONDITIONS_PATCH_VERSION = "test",
			})
		end)

		it("suppresses ranged against dormant daemonhost target", function()
			local target = "dh1"
			setup_breed(target, "chaos_daemonhost")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local orig_called = false
			local conditions = {
				has_target_and_ammo_greater_than = function()
					orig_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, {}, {}, false)
			assert.is_false(result)
			assert.is_false(orig_called)
		end)

		it("allows ranged against non-DH target near sleeping DH", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local orig_called = false
			local conditions = {
				has_target_and_ammo_greater_than = function()
					orig_called = true
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, {}, {}, false)
			assert.is_true(result)
			assert.is_true(orig_called)
		end)

		it("uses the configured ammo threshold for opportunistic ranged fire", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local seen_ammo_percentage
			local conditions = {
				has_target_and_ammo_greater_than = function(_unit, _bb, _scratchpad, condition_args)
					seen_ammo_percentage = condition_args.ammo_percentage
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}
			local condition_args = { ammo_percentage = 0.5 }

			ConditionPatch.wire({
				Heuristics = {
					resolve_decision = function()
						return false
					end,
				},
				MetaData = { inject = function() end },
				Debug = {
					log_ability_decision = function() end,
					bot_slot_for_unit = function()
						return 1
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				bot_ranged_ammo_threshold = function()
					return 0.25
				end,
			})
			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, condition_args, {}, false)
			assert.is_true(result)
			assert.equals(0.25, seen_ammo_percentage)
		end)

		it("leaves the priority-target 0 percent gate untouched", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local seen_ammo_percentage
			local conditions = {
				has_target_and_ammo_greater_than = function(_unit, _bb, _scratchpad, condition_args)
					seen_ammo_percentage = condition_args.ammo_percentage
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}
			local condition_args = { ammo_percentage = 0 }

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, condition_args, {}, false)
			assert.is_true(result)
			assert.equals(0, seen_ammo_percentage)
		end)

		it("leaves non-default ammo thresholds untouched", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local seen_ammo_percentage
			local conditions = {
				has_target_and_ammo_greater_than = function(_unit, _bb, _scratchpad, condition_args)
					seen_ammo_percentage = condition_args.ammo_percentage
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}
			local condition_args = { ammo_percentage = 0.4 }

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, condition_args, {}, false)
			assert.is_true(result)
			assert.equals(0.4, seen_ammo_percentage)
		end)

		it("returns false without throwing when unit_data_system extension is absent", function()
			local unit = "stale_bot"
			-- No extensions registered for this unit — has_extension returns nil
			local bb = { behavior = {}, perception = { target_enemy = nil } }
			local conditions = {
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local ok, result = pcall(
				conditions.can_activate_ability,
				unit,
				bb,
				{}, -- scratchpad (ability_component_name absent → won't match action_data's)
				{},
				{ ability_component_name = "combat_ability_action" },
				false
			)
			assert.is_true(ok, "can_activate_ability threw: " .. tostring(result))
			assert.is_false(result)
		end)

		it("logs when BetterBots overrides the vanilla ranged ammo threshold", function()
			_debug_enabled_result = true
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local conditions = {
				has_target_and_ammo_greater_than = function()
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}
			local condition_args = { ammo_percentage = 0.5 }

			ConditionPatch.wire({
				Heuristics = {
					resolve_decision = function()
						return false
					end,
				},
				MetaData = { inject = function() end },
				Debug = {
					log_ability_decision = function() end,
					bot_slot_for_unit = function()
						return 1
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				bot_ranged_ammo_threshold = function()
					return 0.25
				end,
			})
			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, condition_args, {}, false)
			assert.is_true(result)
			assert.is_truthy(find_debug_log("ranged ammo gate lowered"))
			assert.is_truthy(find_debug_log("to 25%"))
			assert.is_not_nil(find_debug_log_by_key("ranged_ammo_threshold_override:bot1"))
		end)

		it("blocks ability activation when team cooldown suppression is active", function()
			local unit = "bot1"
			_extensions[unit] = {
				unit_data_system = {
					read_component = function(_self, component_name)
						assert.equals("combat_ability_action", component_name)
						return { template_name = "ogryn_taunt_shout" }
					end,
				},
				ability_system = {
					action_input_is_currently_valid = function()
						return true
					end,
				},
				action_input_system = {
					_action_input_parsers = {
						combat_ability_action = {
							_ACTION_INPUT_SEQUENCE_CONFIGS = {
								ogryn_taunt_shout = {
									shout_pressed = {
										buffer_time = 0.5,
									},
								},
							},
						},
					},
				},
			}

			ConditionPatch.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "ogryn_taunt_surrounded", {}
					end,
				},
				MetaData = { inject = function() end },
				Debug = {
					log_ability_decision = function() end,
					bot_slot_for_unit = function()
						return 1
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function()
						return true, "team_cd:taunt"
					end,
				},
			})

			local ability_templates = {
				ogryn_taunt_shout = {
					ability_meta_data = {
						activation = {
							action_input = "shout_pressed",
						},
					},
				},
			}
			local orig_require = require
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return ability_templates
				end

				return orig_require(path)
			end)

			local ok, result = pcall(
				ConditionPatch.can_activate_ability,
				{},
				unit,
				{ behavior = {}, perception = {} },
				{},
				{},
				{ ability_component_name = "combat_ability_action" },
				false
			)

			rawset(_G, "require", orig_require)

			assert.is_true(ok, "can_activate_ability threw: " .. tostring(result))
			assert.is_false(result)
		end)

		it("passes the veteran shout semantic key into the team cooldown lookup", function()
			-- Regression for #14 / c7c9954: team cooldown family lookups must use
			-- identity.semantic_key (veteran_combat_ability_shout), not the raw
			-- engine template_name (veteran_combat_ability) — otherwise Veteran
			-- shout bots never match the aoe_shout category map.
			local unit = "vet_bot"
			_extensions[unit] = {
				unit_data_system = {
					read_component = function(_self, component_name)
						assert.equals("combat_ability_action", component_name)
						return { template_name = "veteran_combat_ability" }
					end,
				},
				ability_system = {
					action_input_is_currently_valid = function()
						return true
					end,
					_equipped_abilities = {
						combat_ability = {
							name = "veteran_combat_ability_shout",
							ability_template_tweak_data = { class_tag = "squad_leader" },
						},
					},
				},
				action_input_system = {
					_action_input_parsers = {
						combat_ability_action = {
							_ACTION_INPUT_SEQUENCE_CONFIGS = {
								veteran_combat_ability = {
									combat_ability_pressed = {
										buffer_time = 0.5,
									},
								},
							},
						},
					},
				},
			}

			local recorded_team_key
			ConditionPatch.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "veteran_voc_surrounded", {}
					end,
				},
				MetaData = { inject = function() end },
				Debug = {
					log_ability_decision = function() end,
					bot_slot_for_unit = function()
						return 1
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
				TeamCooldown = {
					is_suppressed = function(_u, team_key, _t, _rule)
						recorded_team_key = team_key
						return false
					end,
				},
				combat_ability_identity = CombatAbilityIdentity,
			})

			local ability_templates = {
				veteran_combat_ability = {
					ability_meta_data = {
						activation = {
							action_input = "combat_ability_pressed",
						},
					},
				},
			}
			local orig_require = require
			rawset(_G, "require", function(path)
				if path == "scripts/settings/ability/ability_templates/ability_templates" then
					return ability_templates
				end

				return orig_require(path)
			end)

			local ok, result = pcall(
				ConditionPatch.can_activate_ability,
				{},
				unit,
				{ behavior = {}, perception = {} },
				{},
				{},
				{ ability_component_name = "combat_ability_action" },
				false
			)

			rawset(_G, "require", orig_require)

			-- Restore the module-level base wiring so later tests in this spec
			-- don't inherit the CombatAbilityIdentity and stub dependencies
			-- injected above.
			ConditionPatch.wire({
				Heuristics = {
					resolve_decision = function()
						return false
					end,
				},
				MetaData = { inject = function() end },
				Debug = {
					log_ability_decision = function() end,
					bot_slot_for_unit = function()
						return 1
					end,
				},
				EventLog = {
					is_enabled = function()
						return false
					end,
				},
			})

			assert.is_true(ok, "can_activate_ability threw: " .. tostring(result))
			assert.equals("veteran_combat_ability_shout", recorded_team_key)
			assert.is_true(result)
		end)
	end)
end)
