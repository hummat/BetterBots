-- Stub globals that engagement_leash.lua needs
local BLACKBOARDS_STUB = {}
local POSITION_LOOKUP_STUB = {}

local function setup_globals()
	_G.BLACKBOARDS = BLACKBOARDS_STUB
	_G.POSITION_LOOKUP = POSITION_LOOKUP_STUB
	_G.ScriptUnit = {
		has_extension = function()
			return nil
		end,
	}
	_G.Managers = { time = {
		time = function()
			return 0
		end,
	} }
	_G.Vector3 = {
		distance_squared = function(a, b)
			local dx = (a.x or 0) - (b.x or 0)
			local dy = (a.y or 0) - (b.y or 0)
			local dz = (a.z or 0) - (b.z or 0)
			return dx * dx + dy * dy + dz * dz
		end,
	}
end

local function teardown_globals()
	_G.BLACKBOARDS = nil
	_G.POSITION_LOOKUP = nil
	_G.ScriptUnit = nil
	_G.Managers = nil
	_G.Vector3 = nil
end

local function make_unit(id)
	return { _test_id = id }
end

local function make_pos(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

local function make_breed(overrides)
	local b = { name = "test_breed", tags = {}, challenge_rating = 1 }
	if overrides then
		for k, v in pairs(overrides) do
			b[k] = v
		end
	end
	return b
end

local EngagementLeash

describe("engagement_leash", function()
	before_each(function()
		setup_globals()
		-- Fresh load each test
		package.loaded["scripts.mods.BetterBots.engagement_leash"] = nil
		EngagementLeash = dofile("scripts/mods/BetterBots/engagement_leash.lua")
		EngagementLeash.init({
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			perf = nil,
			is_enabled = function()
				return true
			end,
		})
	end)

	after_each(function()
		teardown_globals()
	end)

	describe("compute_effective_leash", function()
		local unit, target

		before_each(function()
			unit = make_unit("bot1")
			target = make_unit("enemy1")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
		end)

		after_each(function()
			POSITION_LOOKUP_STUB[unit] = nil
			POSITION_LOOKUP_STUB[target] = nil
			BLACKBOARDS_STUB[target] = nil
		end)

		it("returns base leash (12m) for idle bot with default coherency", function()
			local breed = make_breed()
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
			assert.equals(12, leash)
			assert.equals("base", reason)
		end)

		it("scales base leash with coherency radius", function()
			_G.ScriptUnit = {
				has_extension = function(_, ext_name)
					if ext_name == "coherency_system" then
						return {
							current_radius = function()
								return 14
							end,
						}
					end
					return nil
				end,
			}

			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 2)
			assert.equals(18, leash)
			assert.equals("base", reason)
		end)

		it("returns stickiness_limit (20m) when already engaged", function()
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 0)
			assert.equals(20, leash)
			assert.equals("already_engaged", reason)
		end)

		it("returns stickiness_limit (20m) during post-charge grace", function()
			EngagementLeash.record_charge(unit, 10)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 12)
			assert.equals(20, leash)
			assert.equals("post_charge_grace", reason)
		end)

		it("returns base leash after post-charge grace expires", function()
			EngagementLeash.record_charge(unit, 10)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 15)
			assert.equals(12, leash)
			assert.equals("base", reason)
		end)

		it("returns stickiness_limit (20m) when enemy within 3m (under attack)", function()
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			POSITION_LOOKUP_STUB[target] = make_pos(2, 0, 0)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 0)
			assert.equals(20, leash)
			assert.equals("under_attack", reason)
		end)

		it("does not trigger under_attack when enemy beyond 3m", function()
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			POSITION_LOOKUP_STUB[target] = make_pos(4, 0, 0)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 0)
			assert.equals(12, leash)
			assert.equals("base", reason)
		end)

		it("returns stickiness_limit (20m) for ranged foray", function()
			local breed = make_breed({ ranged = true })
			BLACKBOARDS_STUB[target] = {
				perception = { target_unit = unit },
			}
			POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
			assert.equals(20, leash)
			assert.equals("ranged_foray", reason)
		end)

		it("does not trigger ranged foray when enemy not targeting bot", function()
			local breed = make_breed({ ranged = true })
			local other_unit = make_unit("other_player")
			BLACKBOARDS_STUB[target] = {
				perception = { target_unit = other_unit },
			}
			POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
			assert.equals(12, leash)
			assert.equals("base", reason)
		end)

		it("does not trigger ranged foray for melee breeds", function()
			local breed = make_breed({ ranged = false })
			BLACKBOARDS_STUB[target] = {
				perception = { target_unit = unit },
			}
			POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0)
			local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
			assert.equals(12, leash)
			assert.equals("base", reason)
		end)

		it("hard cap is 25m by default", function()
			EngagementLeash.record_charge(unit, 0)
			local leash, _ = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 1)
			assert.is_true(leash <= 25)
		end)

		it("hard cap is 30m with always-in-coherency talent", function()
			_G.ScriptUnit = {
				has_extension = function(_, ext_name)
					if ext_name == "talent_system" then
						return {
							has_special_rule = function(_, rule_name)
								return rule_name == "zealot_always_at_least_one_coherency"
							end,
						}
					end
					return nil
				end,
			}
			local leash, _ = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 2)
			assert.equals(20, leash)
			assert.equals(30, EngagementLeash._CONSTANTS.HARD_CAP_ALWAYS_COHERENCY)
		end)

		it("priority action_data check: post_charge_grace takes precedence over already_engaged", function()
			EngagementLeash.record_charge(unit, 10)
			local _, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 12)
			assert.equals("post_charge_grace", reason)
		end)
	end)

	describe("should_extend_approach", function()
		it("returns false when no extension condition", function()
			local unit = make_unit("bot")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			local target = make_unit("enemy")
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
			assert.is_false(EngagementLeash.should_extend_approach(unit, target, make_breed(), false, 0))
		end)

		it("returns true when already engaged", function()
			local unit = make_unit("bot")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			local target = make_unit("enemy")
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
			assert.is_true(EngagementLeash.should_extend_approach(unit, target, make_breed(), true, 0))
		end)

		it("returns true during post-charge grace", function()
			local unit = make_unit("bot")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			local target = make_unit("enemy")
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
			EngagementLeash.record_charge(unit, 5)
			assert.is_true(EngagementLeash.should_extend_approach(unit, target, make_breed(), false, 7))
		end)
	end)

	describe("is_movement_ability", function()
		it("recognizes all charge/dash templates", function()
			assert.is_true(EngagementLeash.is_movement_ability("zealot_dash"))
			assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash"))
			assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash_improved"))
			assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash_improved_double"))
			assert.is_true(EngagementLeash.is_movement_ability("ogryn_charge"))
			assert.is_true(EngagementLeash.is_movement_ability("ogryn_charge_increased_distance"))
			assert.is_true(EngagementLeash.is_movement_ability("adamant_charge"))
		end)

		it("rejects non-movement abilities", function()
			assert.is_false(EngagementLeash.is_movement_ability("psyker_overcharge_stance"))
			assert.is_false(EngagementLeash.is_movement_ability("veteran_combat_ability"))
			assert.is_false(EngagementLeash.is_movement_ability("ogryn_taunt_shout"))
			assert.is_false(EngagementLeash.is_movement_ability("unknown"))
		end)
	end)

	describe("record_charge", function()
		it("records timestamp and enables grace period", function()
			local unit = make_unit("bot")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			local target = make_unit("enemy")
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)

			local _, reason1 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 10)
			assert.equals("base", reason1)

			EngagementLeash.record_charge(unit, 10)
			local _, reason2 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 12)
			assert.equals("post_charge_grace", reason2)

			local _, reason3 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 15)
			assert.equals("base", reason3)
		end)
	end)

	describe("action_data restoration", function()
		it("compute_effective_leash is pure (no side effects on inputs)", function()
			local unit = make_unit("bot")
			POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
			local target = make_unit("enemy")
			POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
			local breed = make_breed()

			EngagementLeash.record_charge(unit, 0)
			EngagementLeash.compute_effective_leash(unit, target, breed, true, 1)

			assert.is_nil(breed.ranged)
			assert.equals("test_breed", breed.name)
		end)
	end)
end)
