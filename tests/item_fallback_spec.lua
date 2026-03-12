local ItemFallback = dofile("scripts/mods/BetterBots/item_fallback.lua")

local _mock_time = 10
local _debug_logs = {}
local _events = {}
local _queued_inputs = {}
local _extensions = {}
local _fallback_state_by_unit = {}
local _last_charge_event_by_unit = {}
local _fallback_queue_dumped_by_key = {}
local _debug_enabled_result = true
local _item_enabled_result = true
local _heuristic_result = true
local _heuristic_rule = "zealot_relic_hazard"
local _inventory_component
local _weapon_action_component
local _weapon_templates

local unit = "bot_unit_1"

local mock_action_input_extension = {
	bot_queue_action_input = function(_self, component, input_name, raw_input)
		_queued_inputs[#_queued_inputs + 1] = {
			component = component,
			input = input_name,
			raw_input = raw_input,
		}
	end,
}

local mock_ability_extension = {
	can_use_ability = function(_self, ability_type)
		return ability_type == "combat_ability"
	end,
}

local mock_unit_data_extension = {
	read_component = function(_self, component_name)
		if component_name == "inventory" then
			return _inventory_component
		end
		if component_name == "weapon_action" then
			return _weapon_action_component
		end
		return nil
	end,
}

local saved_script_unit = rawget(_G, "ScriptUnit")

local function reset()
	_G.ScriptUnit = {
		has_extension = function(u, system_name)
			local exts = _extensions[u]
			return exts and exts[system_name] or nil
		end,
		extension = function(u, system_name)
			local exts = _extensions[u]
			return exts and exts[system_name] or nil
		end,
	}

	_mock_time = 10
	_debug_logs = {}
	_events = {}
	_queued_inputs = {}
	_fallback_state_by_unit = {}
	_last_charge_event_by_unit = {}
	_fallback_queue_dumped_by_key = {}
	_debug_enabled_result = true
	_item_enabled_result = true
	_heuristic_result = true
	_heuristic_rule = "zealot_relic_hazard"
	_inventory_component = { wielded_slot = "slot_primary" }
	_weapon_action_component = { template_name = "dummy_primary" }
	_weapon_templates = {
		dummy_primary = {
			action_inputs = {
				combat_ability = {},
			},
		},
		zealot_relic = {
			action_inputs = {
				channel = {},
				wield_previous = {},
			},
		},
	}

	package.loaded["scripts/settings/equipment/weapon_templates/weapon_templates"] = _weapon_templates

	_extensions[unit] = {
		action_input_system = mock_action_input_extension,
	}

	ItemFallback.init({
		mod = {
			echo = function() end,
			dump = function() end,
		},
		debug_log = function(key, fixed_t, message, _interval, level)
			_debug_logs[#_debug_logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
				level = level,
			}
		end,
		debug_enabled = function()
			return _debug_enabled_result
		end,
		equipped_combat_ability_name = function()
			return "zealot_relic"
		end,
		fallback_state_by_unit = _fallback_state_by_unit,
		last_charge_event_by_unit = _last_charge_event_by_unit,
		fallback_queue_dumped_by_key = _fallback_queue_dumped_by_key,
		ITEM_WIELD_TIMEOUT_S = 2,
		ITEM_SEQUENCE_RETRY_S = 1,
		ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.5,
		ITEM_DEFAULT_START_DELAY_S = 0,
		event_log = {
			is_enabled = function()
				return true
			end,
			next_attempt_id = function()
				return 7
			end,
			emit = function(event)
				_events[#_events + 1] = event
			end,
		},
		bot_slot_for_unit = function()
			return 5
		end,
	})

	ItemFallback.wire({
		build_context = function()
			return {
				num_nearby = 4,
				in_hazard = true,
			}
		end,
		context_snapshot = function(context)
			return context
		end,
		fallback_state_snapshot = function(state)
			return {
				item_stage = state.item_stage,
				item_profile_name = state.item_profile_name,
			}
		end,
		evaluate_item_heuristic = function()
			return _heuristic_result, _heuristic_rule
		end,
		is_item_ability_enabled = function()
			return _item_enabled_result
		end,
	})
end

local function find_log(pattern)
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			return _debug_logs[i]
		end
	end

	return nil
end

describe("item_fallback", function()
	before_each(function()
		reset()
	end)

	after_each(function()
		package.loaded["scripts/settings/equipment/weapon_templates/weapon_templates"] = nil
		_G.ScriptUnit = saved_script_unit
	end)

	it("carries the heuristic rule into queued item logs and events", function()
		local state = {}
		local combat_ability = {
			name = "zealot_relic",
			inventory_item_name = "content/items/weapons/player/zealot_relic",
		}

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.equals("waiting_wield", state.item_stage)
		assert.equals("zealot_relic_hazard", state.item_rule)
		assert.equals("combat_ability", _queued_inputs[1].input)

		_inventory_component.wielded_slot = "slot_combat_ability"
		_weapon_action_component.template_name = "zealot_relic"
		_mock_time = _mock_time + 0.1

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		assert.equals("channel", _queued_inputs[2].input)
		assert.is_not_nil(find_log("fallback item queued zealot_relic input=channel (rule=zealot_relic_hazard)"))

		local queued_event
		for i = 1, #_events do
			if _events[i].event == "queued" then
				queued_event = _events[i]
				break
			end
		end

		assert.is_not_nil(queued_event)
		assert.equals("zealot_relic_hazard", queued_event.rule)
		assert.equals(7, queued_event.attempt_id)
	end)

	it("includes the heuristic rule in charge confirmation logs", function()
		local state = {}
		local combat_ability = {
			name = "zealot_relic",
			inventory_item_name = "content/items/weapons/player/zealot_relic",
		}

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		_inventory_component.wielded_slot = "slot_combat_ability"
		_weapon_action_component.template_name = "zealot_relic"
		_mock_time = _mock_time + 0.1

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		_last_charge_event_by_unit[unit] = {
			ability_name = "zealot_relic",
			fixed_t = _mock_time + 0.1,
		}
		_mock_time = _mock_time + 0.2

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		assert.is_not_nil(
			find_log("fallback item confirmed charge consume for zealot_relic (profile=channel, rule=zealot_relic_hazard)")
		)
	end)
end)
