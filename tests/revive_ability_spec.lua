-- tests/revive_ability_spec.lua
local _extensions = {}
local _debug_logs = {}
local _debug_on = false
local _recorded_inputs = {}
local _suppressed = false
local _suppressed_reason = nil
local _combat_template_enabled = true

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
local ReviveAbility = dofile("scripts/mods/BetterBots/revive_ability.lua")

-- Mock factories
local function make_unit(id)
	return { _test_id = id or "bot_1" }
end

local function make_action_input_ext()
	return {
		bot_queue_action_input = function(_, component, input, raw)
			_recorded_inputs[#_recorded_inputs + 1] = {
				component = component,
				input = input,
				raw = raw,
			}
		end,
		_action_input_parsers = {},
	}
end

local function make_ability_ext(can_use, charges)
	return {
		can_use_ability = function(_, _ability_type)
			return can_use
		end,
		remaining_ability_charges = function(_, _ability_type)
			return charges or 1
		end,
		action_input_is_currently_valid = function(_, _ability_component_name, _action_input, _used_input, _fixed_t)
			return true
		end,
	}
end

local function make_unit_data_ext(template_name)
	return {
		read_component = function(_, component_name)
			if component_name == "combat_ability_action" then
				return { template_name = template_name or "none" }
			end
			return nil
		end,
	}
end

local function setup_unit(unit, template_name, can_use, charges)
	local action_input_ext = make_action_input_ext()
	local ability_ext = make_ability_ext(can_use ~= false, charges or 1)
	local unit_data_ext = make_unit_data_ext(template_name)
	_extensions[unit] = {
		unit_data_system = unit_data_ext,
		ability_system = ability_ext,
		action_input_system = action_input_ext,
	}
	return action_input_ext, ability_ext, unit_data_ext
end

local function make_blackboard(enemies)
	return {
		perception = {
			enemies_in_proximity = enemies or 3,
		},
	}
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
			blackboard = make_blackboard(3)
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
	end)
end)
