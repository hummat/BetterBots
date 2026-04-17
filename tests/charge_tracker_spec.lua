local test_helper = require("tests.test_helper")

local ChargeTracker = dofile("scripts/mods/BetterBots/charge_tracker.lua")

local saved_script_unit = rawget(_G, "ScriptUnit")

describe("charge_tracker", function()
	local recorded
	local last_charge_event_by_unit
	local fallback_state_by_unit
	local extension_map

	local function make_deps(overrides)
		local deps = {
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
				record_charge_event = function(unit, name, t)
					recorded.grenade[#recorded.grenade + 1] = { unit = unit, name = name, t = t }
				end,
			},
			settings = {
				is_feature_enabled = function(feature_name)
					assert.equals("team_cooldown", feature_name)
					return true
				end,
			},
			team_cooldown = {
				record = function(unit, key, t)
					recorded.team_cooldown[#recorded.team_cooldown + 1] = { unit, key, t }
				end,
			},
			combat_ability_identity = {
				resolve = function()
					return { semantic_key = "psyker_shout" }
				end,
			},
			event_log = {
				is_enabled = function()
					return true
				end,
				emit = function(event)
					recorded.event_log[#recorded.event_log + 1] = event
				end,
			},
			bot_slot_for_unit = function()
				return 1
			end,
		}

		for key, value in pairs(overrides or {}) do
			deps[key] = value
		end

		return deps
	end

	local function make_self(equipped, is_human)
		return {
			_unit = "unit_stub",
			_player = {
				is_human_controlled = function()
					return is_human == true
				end,
			},
			_equipped_abilities = equipped,
		}
	end

	before_each(function()
		recorded = {
			grenade = {},
			team_cooldown = {},
			event_log = {},
		}
		last_charge_event_by_unit = {}
		fallback_state_by_unit = {}
		extension_map = {
			unit_stub = {
				unit_data_system = test_helper.make_player_unit_data_extension({
					combat_ability_action = { template_name = "veteran_stance" },
				}),
				ability_system = test_helper.make_player_ability_extension(),
			},
		}
		_G.ScriptUnit = test_helper.make_script_unit_mock(extension_map)
		ChargeTracker.init(make_deps())
	end)

	after_each(function()
		_G.ScriptUnit = saved_script_unit
	end)

	it("returns early for non-combat non-grenade ability types", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "x" } }), "weapon_ability", 1)

		assert.equals(0, #recorded.team_cooldown)
		assert.equals(0, #recorded.event_log)
		assert.is_nil(last_charge_event_by_unit.unit_stub)
	end)

	it("returns early for human-controlled players", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "x" } }, true), "combat_ability", 1)

		assert.equals(0, #recorded.team_cooldown)
		assert.equals(0, #recorded.event_log)
		assert.is_nil(last_charge_event_by_unit.unit_stub)
	end)

	it("grenade charges route to grenade fallback", function()
		ChargeTracker.handle(make_self({ grenade_ability = { name = "frag" } }), "grenade_ability", 1)

		assert.equals(1, #recorded.grenade)
		assert.same({ unit = "unit_stub", name = "frag", t = 10 }, recorded.grenade[1])
		assert.equals(0, #recorded.team_cooldown)
		assert.equals(0, #recorded.event_log)
	end)

	it("combat charges record team cooldown with semantic key", function()
		ChargeTracker.handle(
			make_self({ combat_ability = { name = "psyker_discharge_shout_improved" } }),
			"combat_ability",
			1
		)

		assert.equals(1, #recorded.team_cooldown)
		assert.same({ "unit_stub", "psyker_shout", 10 }, recorded.team_cooldown[1])
	end)

	it("combat charges emit consumed event", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 2)

		assert.equals(1, #recorded.event_log)
		assert.equals("consumed", recorded.event_log[1].event)
		assert.equals(2, recorded.event_log[1].charges)
		assert.equals("veteran_stance", recorded.event_log[1].ability)
	end)

	it("records last charge event name and fixed time", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)

		assert.same({ ability_name = "veteran_stance", fixed_t = 10 }, last_charge_event_by_unit.unit_stub)
	end)

	it("consumed event carries fallback rule and attempt_id when present", function()
		fallback_state_by_unit.unit_stub = {
			item_rule = "retry_wield",
			attempt_id = "abc123",
		}

		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)

		assert.equals("retry_wield", recorded.event_log[1].rule)
		assert.equals("abc123", recorded.event_log[1].attempt_id)
	end)

	it("does not record team cooldown when feature disabled", function()
		ChargeTracker.init(make_deps({
			settings = {
				is_feature_enabled = function()
					return false
				end,
			},
		}))

		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)

		assert.equals(0, #recorded.team_cooldown)
		assert.same({ ability_name = "veteran_stance", fixed_t = 10 }, last_charge_event_by_unit.unit_stub)
	end)
end)
