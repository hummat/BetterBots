-- Tests for condition_patch.lua daemonhost combat suppression wrappers (#17).
-- Verifies that melee/ranged combat is suppressed only when the bot's
-- current target IS a dormant daemonhost, not when any DH is nearby.
local _extensions = {}
local _blackboards = {}

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
_G.Managers = { state = { extension = { system = function() return nil end } } }

-- Stub require so condition_patch.lua doesn't crash on game modules
local _orig_require = require
local function _mock_require(path)
	if path:match("^scripts/") then
		return {}
	end
	return _orig_require(path)
end
rawset(_G, "require", _mock_require)

local ConditionPatch = dofile("scripts/mods/BetterBots/condition_patch.lua")

-- Restore require
rawset(_G, "require", _orig_require)

-- Initialize with minimal deps
ConditionPatch.init({
	mod = { echo = function() end, hook_require = function() end },
	debug_log = function() end,
	fixed_time = function() return 0 end,
	is_suppressed = function() return false end,
	equipped_combat_ability_name = function() return "none" end,
	patched_bt_bot_conditions = {},
	patched_bt_conditions = {},
	rescue_intent = {},
	DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 5,
	CONDITIONS_PATCH_VERSION = "test",
})

ConditionPatch.wire({
	Heuristics = { resolve_decision = function() return false end },
	MetaData = { inject = function() end },
	Debug = { log_ability_decision = function() end, bot_slot_for_unit = function() return 1 end },
	EventLog = { is_enabled = function() return false end },
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
end

describe("condition_patch", function()
	before_each(function()
		reset()
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
				can_activate_ability = function() return false end,
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
				can_activate_ability = function() return false end,
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
				can_activate_ability = function() return false end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.bot_in_melee_range("bot1", bb, {}, {}, {}, false)
			assert.is_true(result)
			assert.is_true(orig_called)
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
				can_activate_ability = function() return false end,
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
				can_activate_ability = function() return false end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			local result = conditions.has_target_and_ammo_greater_than("bot1", bb, {}, {}, {}, false)
			assert.is_true(result)
			assert.is_true(orig_called)
		end)
	end)
end)
