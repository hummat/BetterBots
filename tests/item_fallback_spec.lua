local test_helper = require("tests.test_helper")

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
local _combat_ability_component
local _interaction_component
local _weapon_action_component
local _weapon_templates
local _query_weapon_switch_lock

local unit = "bot_unit_1"

local mock_action_input_extension = test_helper.make_player_action_input_extension({
	bot_queue_action_input = function(_self, component, input_name, raw_input)
		_queued_inputs[#_queued_inputs + 1] = {
			component = component,
			input = input_name,
			raw_input = raw_input,
		}
	end,
})

local mock_ability_extension = test_helper.make_player_ability_extension({
	can_use_ability = function(_self, ability_type)
		return ability_type == "combat_ability"
	end,
})

local mock_unit_data_extension = {
	read_component = function(_self, component_name)
		if component_name == "inventory" then
			return _inventory_component
		end
		if component_name == "combat_ability" then
			return _combat_ability_component
		end
		if component_name == "interaction" then
			return _interaction_component
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
	_combat_ability_component = { active = false }
	_interaction_component = { target_unit = nil }
	_weapon_action_component = { template_name = "dummy_primary" }
	_query_weapon_switch_lock = function()
		return false
	end
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
		unit_data_system = test_helper.make_player_unit_data_extension(nil, {
			read_component = mock_unit_data_extension.read_component,
		}),
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
		fixed_time = function()
			return 42
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
		query_weapon_switch_lock = function(unit_arg)
			return _query_weapon_switch_lock(unit_arg)
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

local function make_item_ability(name)
	return {
		name = name,
		inventory_item_name = "content/items/weapons/player/" .. name,
	}
end

local function install_force_field_templates()
	_weapon_templates.psyker_force_field = {
		action_inputs = {
			aim_force_field = {},
			place_force_field = {},
			unwield_to_previous = {},
			instant_aim_force_field = {},
			instant_place_force_field = {},
		},
	}
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
			find_log(
				"fallback item confirmed charge consume for zealot_relic (profile=channel, rule=zealot_relic_hazard)"
			)
		)
	end)

	it("locks active relic weapon switches outside interaction", function()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_combat_ability_component.active = true

		local should_lock, ability_name, reason, slot_to_keep = ItemFallback.should_lock_weapon_switch(unit)

		assert.is_true(should_lock)
		assert.equals("zealot_relic", ability_name)
		assert.equals("active", reason)
		assert.equals("slot_combat_ability", slot_to_keep)
	end)

	it("does not lock active relic weapon switches while interaction is pending", function()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_combat_ability_component.active = true
		_interaction_component.target_unit = "medicae_station"

		local should_lock = ItemFallback.should_lock_weapon_switch(unit)

		assert.is_false(should_lock)
	end)

	it("schedule_retry resets active stage and keeps the earliest retry time", function()
		_fallback_state_by_unit[unit] = {
			item_stage = "waiting_start",
			item_ability_name = "zealot_relic",
			next_try_t = 12,
		}

		ItemFallback.schedule_retry(unit, _mock_time, 0.6)
		ItemFallback.schedule_retry(unit, _mock_time, 1.2)

		assert.is_nil(_fallback_state_by_unit[unit].item_stage)
		assert.equals(10.6, _fallback_state_by_unit[unit].next_try_t)
	end)

	it("does not lock sequence weapon switch while interaction is pending", function()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_interaction_component.target_unit = "medicae_station"
		_fallback_state_by_unit[unit] = {
			item_stage = "waiting_unwield",
			item_ability_name = "psyker_force_field",
		}

		local should_lock = ItemFallback.should_lock_weapon_switch(unit)

		assert.is_false(should_lock)
	end)

	it("fast-retries when another locked slot blocks combat-ability wield", function()
		local state = {}
		local combat_ability = make_item_ability("zealot_relic")

		_query_weapon_switch_lock = function()
			return true, "veteran_frag_grenade", "sequence", "slot_grenade_ability"
		end

		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		assert.is_nil(state.item_stage)
		assert.equals(10.35, state.next_try_t)
		assert.equals(0, #_queued_inputs)
		assert.is_not_nil(find_log("fallback item blocked zealot_relic (slot locked by veteran_frag_grenade sequence)"))
		assert.same({
			t = 10,
			event = "blocked",
			bot = 5,
			ability = "zealot_relic",
			rule = "zealot_relic_hazard",
			stage = nil,
			profile = nil,
			attempt_id = nil,
			reason = "slot_locked",
			blocked_by = "veteran_frag_grenade",
			lock_reason = "sequence",
			held_slot = "slot_grenade_ability",
		}, _events[1])
	end)

	it("retries and rotates when combat-ability wield is lost before followup", function()
		local state = {}
		local combat_ability = make_item_ability("psyker_force_field")

		install_force_field_templates()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_weapon_action_component.template_name = "psyker_force_field"

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

		_mock_time = _mock_time + 0.01
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.equals("waiting_start", state.item_stage)

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
		assert.equals("waiting_followup", state.item_stage)

		_inventory_component.wielded_slot = "slot_primary"
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

		assert.is_nil(state.item_stage)
		assert.equals(_mock_time + 1, state.next_try_t)
		assert.equals(2, state.item_profile_index_by_key["psyker_force_field:psyker_force_field"])
	end)

	it("retries when combat-ability wield is lost before start", function()
		local state = {}
		local combat_ability = make_item_ability("psyker_force_field")

		install_force_field_templates()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_weapon_action_component.template_name = "psyker_force_field"

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

		_mock_time = _mock_time + 0.01
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.equals("waiting_start", state.item_stage)

		_inventory_component.wielded_slot = "slot_primary"
		_mock_time = _mock_time + 0.01
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		assert.is_nil(state.item_stage)
		assert.equals(_mock_time + 1, state.next_try_t)
	end)

	it("rotates force-field profile after charge-confirm timeout and uses instant variant next", function()
		local state = {}
		local combat_ability = make_item_ability("psyker_force_field")

		install_force_field_templates()
		_inventory_component.wielded_slot = "slot_combat_ability"
		_weapon_action_component.template_name = "psyker_force_field"

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

		_mock_time = _mock_time + 0.01
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.equals("force_field_regular", state.item_profile_name)
		assert.equals("waiting_start", state.item_stage)

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
		_mock_time = _mock_time + 0.4
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		_mock_time = _mock_time + 1.7
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)

		assert.equals("waiting_charge_confirmation", state.item_stage)

		_mock_time = _mock_time + 2.3
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.is_nil(state.item_stage)
		assert.equals(2, state.item_profile_index_by_key["psyker_force_field:psyker_force_field"])

		_mock_time = state.next_try_t
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

		_mock_time = _mock_time + 0.01
		ItemFallback.try_queue_item(
			unit,
			mock_unit_data_extension,
			mock_ability_extension,
			state,
			_mock_time,
			combat_ability,
			{}
		)
		assert.equals("force_field_instant", state.item_profile_name)
	end)

	describe("on_state_change_finish", function()
		local original_schedule_retry
		local scheduled

		before_each(function()
			original_schedule_retry = ItemFallback.schedule_retry
			scheduled = nil
			ItemFallback.schedule_retry = function(unit_arg, fixed_t_arg, window_arg)
				scheduled = {
					unit = unit_arg,
					fixed_t = fixed_t_arg,
					window = window_arg,
				}
			end
		end)

		after_each(function()
			ItemFallback.schedule_retry = original_schedule_retry
		end)

		it("chains original func then schedules retry when a bot combat ability state transition fails", function()
			local called_order = {}
			local orig_func = function()
				called_order[#called_order + 1] = "orig"
			end

			ItemFallback.schedule_retry = function(unit_arg, fixed_t_arg, window_arg)
				scheduled = {
					unit = unit_arg,
					fixed_t = fixed_t_arg,
					window = window_arg,
				}
				called_order[#called_order + 1] = "retry"
			end

			local self = {
				_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				_player_unit = "unit_stub",
				_wanted_state_name = "stunned",
				_character_sate_component = { state_name = "walking" },
			}

			ItemFallback.on_state_change_finish(orig_func, self, "interrupted", nil, 100, 0.1)

			assert.same({ "orig", "retry" }, called_order)
			assert.equals("unit_stub", scheduled.unit)
			assert.equals(42, scheduled.fixed_t)
			assert.equals(0.35, scheduled.window)
		end)

		it("does not schedule retry when human-controlled", function()
			local self = {
				_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
				_player = {
					is_human_controlled = function()
						return true
					end,
				},
				_player_unit = "unit_stub",
				_wanted_state_name = "stunned",
				_character_sate_component = { state_name = "walking" },
			}

			ItemFallback.on_state_change_finish(function() end, self, "interrupted", nil, 100, 0.1)

			assert.is_nil(scheduled)
		end)

		it("does not schedule retry when state transition succeeded", function()
			local self = {
				_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				_player_unit = "unit_stub",
				_wanted_state_name = "walking",
				_character_sate_component = { state_name = "walking" },
			}

			ItemFallback.on_state_change_finish(function() end, self, "finished", nil, 100, 0.1)

			assert.is_nil(scheduled)
		end)

		it("does not schedule retry for non-combat ability type", function()
			local self = {
				_action_settings = { ability_type = "grenade_ability", use_ability_charge = true },
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				_player_unit = "unit_stub",
				_wanted_state_name = "stunned",
				_character_sate_component = { state_name = "walking" },
			}

			ItemFallback.on_state_change_finish(function() end, self, "interrupted", nil, 100, 0.1)

			assert.is_nil(scheduled)
		end)

		it("does not schedule retry when use_ability_charge is false", function()
			local self = {
				_action_settings = { ability_type = "combat_ability", use_ability_charge = false },
				_player = {
					is_human_controlled = function()
						return false
					end,
				},
				_player_unit = "unit_stub",
				_wanted_state_name = "stunned",
				_character_sate_component = { state_name = "walking" },
			}

			ItemFallback.on_state_change_finish(function() end, self, "interrupted", nil, 100, 0.1)

			assert.is_nil(scheduled)
		end)
	end)
end)
