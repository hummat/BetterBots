local saved_script_unit = rawget(_G, "ScriptUnit")
local saved_position_lookup = rawget(_G, "POSITION_LOOKUP")

local function vec(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

describe("charge_nav_validation", function()
	local ChargeNavValidation
	local fixed_t
	local nav_queries
	local nav_extension

	before_each(function()
		fixed_t = 10
		nav_queries = {
			ray_can_go = function()
				error("ray_can_go stub not configured")
			end,
		}
		nav_extension = nil

		_G.POSITION_LOOKUP = {}
		_G.ScriptUnit = {
			has_extension = function(_, system_name)
				if system_name == "navigation_system" then
					return nav_extension
				end
				return nil
			end,
		}

		ChargeNavValidation = dofile("scripts/mods/BetterBots/charge_nav_validation.lua")
		ChargeNavValidation.init({
			fixed_time = function()
				return fixed_t
			end,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			nav_queries = nav_queries,
		})
	end)

	after_each(function()
		_G.ScriptUnit = saved_script_unit
		_G.POSITION_LOOKUP = saved_position_lookup
	end)

	it("recognizes charge and dash templates plus live talent variants", function()
		assert.is_true(ChargeNavValidation.should_validate("zealot_dash"))
		assert.is_true(ChargeNavValidation.should_validate("zealot_targeted_dash"))
		assert.is_true(ChargeNavValidation.should_validate("zealot_targeted_dash_improved"))
		assert.is_true(ChargeNavValidation.should_validate("zealot_targeted_dash_improved_double"))
		assert.is_true(ChargeNavValidation.should_validate("ogryn_charge"))
		assert.is_true(ChargeNavValidation.should_validate("ogryn_charge_increased_distance"))
		assert.is_true(ChargeNavValidation.should_validate("adamant_charge"))
		assert.is_false(ChargeNavValidation.should_validate("psyker_shout"))
	end)

	it("fails open before runtime deps are wired", function()
		local uninitialized = dofile("scripts/mods/BetterBots/charge_nav_validation.lua")
		local ok_call, ok = pcall(uninitialized.validate, "bot_unit", "zealot_dash", "fallback")

		assert.is_true(ok_call)
		assert.is_true(ok)
	end)

	it("respects the feature gate", function()
		ChargeNavValidation.init({
			fixed_time = function()
				return fixed_t
			end,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			is_enabled = function()
				return false
			end,
			nav_queries = nav_queries,
		})

		assert.is_false(ChargeNavValidation.should_validate("zealot_dash"))
		assert.is_true(ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback"))
	end)

	it("blocks when the bot has no navigation extension", function()
		_G.POSITION_LOOKUP.bot_unit = vec(0, 0, 0)

		local ok, reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback")

		assert.is_false(ok)
		assert.equals("missing_navigation_extension", reason)
	end)

	it("caches same-destination failures for a short cooldown", function()
		local calls = 0
		_G.POSITION_LOOKUP.bot_unit = vec(0, 0, 0)
		nav_extension = {
			destination = function()
				return vec(12, 0, 0)
			end,
			destination_reached = function()
				return false
			end,
			_nav_world = "nav_world",
			_traverse_logic = "traverse_logic",
		}
		nav_queries.ray_can_go = function()
			calls = calls + 1
			return false, vec(0, 0, 0), vec(12, 0, 0)
		end

		local first_ok, first_reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback")
		fixed_t = 10.2
		local second_ok, second_reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback")

		assert.is_false(first_ok)
		assert.equals("ray_blocked", first_reason)
		assert.is_false(second_ok)
		assert.equals("cached_ray_blocked", second_reason)
		assert.equals(1, calls)
	end)

	it("keeps negative-cache state isolated per bot unit", function()
		local calls = 0

		_G.POSITION_LOOKUP.bot_a = vec(0, 0, 0)
		_G.POSITION_LOOKUP.bot_b = vec(0, 0, 0)
		nav_extension = {
			destination = function()
				return vec(12, 0, 0)
			end,
			destination_reached = function()
				return false
			end,
			_nav_world = "nav_world",
			_traverse_logic = "traverse_logic",
		}
		nav_queries.ray_can_go = function()
			calls = calls + 1
			return false, vec(0, 0, 0), vec(12, 0, 0)
		end

		local first_ok, first_reason = ChargeNavValidation.validate("bot_a", "zealot_dash", "fallback")
		fixed_t = 10.2
		local second_ok, second_reason = ChargeNavValidation.validate("bot_b", "zealot_dash", "fallback")

		assert.is_false(first_ok)
		assert.equals("ray_blocked", first_reason)
		assert.is_false(second_ok)
		assert.equals("ray_blocked", second_reason)
		assert.equals(2, calls)
	end)

	it("revalidates immediately when the navigation destination changes", function()
		local calls = 0
		local destination = vec(12, 0, 0)

		_G.POSITION_LOOKUP.bot_unit = vec(0, 0, 0)
		nav_extension = {
			destination = function()
				return destination
			end,
			destination_reached = function()
				return false
			end,
			_nav_world = "nav_world",
			_traverse_logic = "traverse_logic",
		}
		nav_queries.ray_can_go = function(_, _, _, _, _, _)
			calls = calls + 1
			if calls == 1 then
				return false, vec(0, 0, 0), vec(12, 0, 0)
			end
			return true, vec(0, 0, 0), vec(20, 0, 0)
		end

		local first_ok, first_reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback")
		destination = vec(20, 0, 0)
		fixed_t = 10.2
		local second_ok, second_reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback")

		assert.is_false(first_ok)
		assert.equals("ray_blocked", first_reason)
		assert.is_true(second_ok)
		assert.is_nil(second_reason)
		assert.equals(2, calls)
	end)

	it("uses the targeted dash enemy position instead of a reached nav destination", function()
		local ray_end_position
		local blackboard = {
			perception = {
				target_enemy = "enemy_unit",
			},
		}

		_G.POSITION_LOOKUP.bot_unit = vec(0, 0, 0)
		_G.POSITION_LOOKUP.enemy_unit = vec(15, 0, 0)
		nav_extension = {
			destination = function()
				return vec(0, 0, 0)
			end,
			destination_reached = function()
				return true
			end,
			_nav_world = "nav_world",
			_traverse_logic = "traverse_logic",
		}
		nav_queries.ray_can_go = function(_, _, destination)
			ray_end_position = destination
			return true, vec(0, 0, 0), destination
		end

		local ok, reason = ChargeNavValidation.validate("bot_unit", "zealot_dash", "fallback", {
			blackboard = blackboard,
		})

		assert.is_true(ok)
		assert.is_nil(reason)
		assert.same(vec(15, 0, 0), ray_end_position)
	end)

	it("prefers an explicit launch target position over the nav destination", function()
		local ray_end_position

		_G.POSITION_LOOKUP.bot_unit = vec(0, 0, 0)
		nav_extension = {
			destination = function()
				return vec(4, 0, 0)
			end,
			destination_reached = function()
				return false
			end,
			_nav_world = "nav_world",
			_traverse_logic = "traverse_logic",
		}
		nav_queries.ray_can_go = function(_, _, destination)
			ray_end_position = destination
			if destination.x == 20 then
				return false, vec(0, 0, 0), destination
			end
			return true, vec(0, 0, 0), destination
		end

		local ok, reason = ChargeNavValidation.validate("bot_unit", "ogryn_charge", "fallback", {
			target_position = vec(20, 0, 0),
		})

		assert.is_false(ok)
		assert.equals("ray_blocked", reason)
		assert.same(vec(20, 0, 0), ray_end_position)
	end)
end)
