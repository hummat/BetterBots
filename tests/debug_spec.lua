local Debug = dofile("scripts/mods/BetterBots/debug.lua")

describe("debug", function()
	before_each(function()
		Debug.init({
			mod = { command = function() end, echo = function() end, dump = function() end },
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			equipped_combat_ability_name = function()
				return "unknown"
			end,
			fallback_state_by_unit = {},
			last_charge_event_by_unit = {},
		})
	end)

	it("includes hazard state in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			num_nearby = 2,
			health_pct = 0.8,
			toughness_pct = 0.5,
			in_hazard = true,
		})

		assert.is_true(snapshot.in_hazard)
		assert.equals(2, snapshot.num_nearby)
	end)

	it("drops positive infinity target_enemy_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = math.huge,
		})

		assert.is_nil(snapshot.target_enemy_distance)
	end)

	it("drops negative infinity target_ally_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_ally_distance = -math.huge,
		})

		assert.is_nil(snapshot.target_ally_distance)
	end)

	it("drops NaN target_enemy_distance from context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = 0 / 0,
		})

		assert.is_nil(snapshot.target_enemy_distance)
	end)

	it("keeps finite target_enemy_distance in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_enemy_distance = 15.5,
		})

		assert.equals(15.5, snapshot.target_enemy_distance)
	end)

	it("includes daemonhost dormancy diagnostics in context snapshots", function()
		local snapshot = Debug.context_snapshot({
			target_is_dormant_daemonhost = true,
			target_daemonhost_aggro_state = "passive",
		})

		assert.is_true(snapshot.target_is_dormant_daemonhost)
		assert.equals("passive", snapshot.target_daemonhost_aggro_state)
	end)
end)
