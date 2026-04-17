local test_helper = require("tests.test_helper")

local ChargeTracker = dofile("scripts/mods/BetterBots/charge_tracker.lua")
local ItemFallback = dofile("scripts/mods/BetterBots/item_fallback.lua")

describe("runtime contracts", function()
	local saved_script_unit
	local fallback_state_by_unit
	local last_charge_event_by_unit
	local emitted
	local scheduled

	before_each(function()
		saved_script_unit = rawget(_G, "ScriptUnit")
		fallback_state_by_unit = {
			unit_stub = {
				item_rule = "zealot_relic_hazard",
				attempt_id = "attempt-7",
			},
		}
		last_charge_event_by_unit = {}
		emitted = {}
		scheduled = {}

		_G.ScriptUnit = test_helper.make_script_unit_mock({
			unit_stub = {
				unit_data_system = test_helper.make_player_unit_data_extension({
					combat_ability_action = { template_name = "veteran_stance" },
				}),
				ability_system = test_helper.make_player_ability_extension(),
			},
		})

		ChargeTracker.init({
			fixed_time = function()
				return 10
			end,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			last_charge_event_by_unit = last_charge_event_by_unit,
			fallback_state_by_unit = fallback_state_by_unit,
			grenade_fallback = {
				record_charge_event = function() end,
			},
			settings = {
				is_feature_enabled = function()
					return false
				end,
			},
			team_cooldown = {
				record = function() end,
			},
			combat_ability_identity = {
				resolve = function()
					return nil
				end,
			},
			event_log = {
				is_enabled = function()
					return true
				end,
				emit = function(event)
					emitted[#emitted + 1] = event
				end,
			},
			bot_slot_for_unit = function()
				return 1
			end,
		})

		ItemFallback.init({
			mod = { echo = function() end, dump = function() end },
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 10
			end,
			equipped_combat_ability_name = function()
				return "veteran_stance"
			end,
			fallback_state_by_unit = fallback_state_by_unit,
			last_charge_event_by_unit = last_charge_event_by_unit,
			fallback_queue_dumped_by_key = {},
			ITEM_WIELD_TIMEOUT_S = 2,
			ITEM_SEQUENCE_RETRY_S = 1,
			ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.5,
			ITEM_DEFAULT_START_DELAY_S = 0,
			event_log = {
				is_enabled = function()
					return false
				end,
				emit = function() end,
				next_attempt_id = function()
					return 8
				end,
			},
			bot_slot_for_unit = function()
				return 1
			end,
		})

		ItemFallback.schedule_retry = function(unit, fixed_t, retry_delay_s)
			scheduled[#scheduled + 1] = {
				unit = unit,
				fixed_t = fixed_t,
				retry_delay_s = retry_delay_s,
			}
		end
	end)

	after_each(function()
		rawset(_G, "ScriptUnit", saved_script_unit)
	end)

	it("carries fallback rule and attempt id into consumed event", function()
		ChargeTracker.handle({
			_unit = "unit_stub",
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			_equipped_abilities = {
				combat_ability = { name = "veteran_stance" },
			},
		}, "combat_ability", 1)

		assert.equals("consumed", emitted[1].event)
		assert.equals("zealot_relic_hazard", emitted[1].rule)
		assert.equals("attempt-7", emitted[1].attempt_id)
	end)

	it("schedules a retry after a failed combat-ability state transition", function()
		ItemFallback.on_state_change_finish(function() end, {
			_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			_player_unit = "unit_stub",
			_wanted_state_name = "stunned",
			_character_sate_component = { state_name = "walking" },
		}, "interrupted", nil, 10, 0.1)

		assert.equals(1, #scheduled)
		assert.equals("unit_stub", scheduled[1].unit)
		assert.equals(0.35, scheduled[1].retry_delay_s)
	end)
end)
