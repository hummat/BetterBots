-- Mock engine globals before loading the sprint module
local _extensions = {}
local _positions = {}
local _alive = {}
local _sides = {}

_G.ScriptUnit = {
	has_extension = function(unit, system_name)
		local unit_exts = _extensions[unit]
		return unit_exts and unit_exts[system_name] or nil
	end,
}

_G.POSITION_LOOKUP = setmetatable({}, {
	__index = function(_, unit)
		return _positions[unit]
	end,
})

_G.ALIVE = setmetatable({}, {
	__index = function(_, unit)
		return _alive[unit]
	end,
})

_G.Vector3 = {
	distance_squared = function(a, b)
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return dx * dx + dy * dy + dz * dz
	end,
}

-- Mock BLACKBOARDS for daemonhost aggro state detection (#17)
local _blackboards = {}
_G.BLACKBOARDS = setmetatable({}, {
	__index = function(_, unit)
		return _blackboards[unit]
	end,
})

-- Mock Managers.state.extension:system("side_system") for daemonhost detection
local _mock_side_system = nil

_G.Managers = {
	state = {
		extension = {
			system = function(_self, name)
				if name == "side_system" and _mock_side_system then
					return _mock_side_system
				end
				return nil
			end,
		},
	},
}

local Sprint = dofile("scripts/mods/BetterBots/sprint.lua")

-- Helper: build a mock BotUnitInput self with _move and _group_extension
local function make_self(opts)
	opts = opts or {}
	return {
		_move = opts.move or { x = 0, y = 1 },
		_group_extension = opts.group_extension or nil,
	}
end

-- Helper: build a position vector
local function pos(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

-- Helper: set up perception extension with enemies
local function setup_perception(unit, enemies)
	local enemy_list = enemies or {}
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].perception_system = {
		enemies_in_proximity = function()
			return enemy_list, #enemy_list
		end,
	}
end

-- Helper: set up behavior extension with blackboard
local function setup_behavior(unit, perception_data)
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].behavior_system = {
		_brain = {
			_blackboard = {
				perception = perception_data or {},
			},
		},
	}
end

-- Helper: set up unit_data extension for a breed
local function setup_breed(unit, breed_name)
	if not _extensions[unit] then
		_extensions[unit] = {}
	end
	_extensions[unit].unit_data_system = {
		breed = function()
			return { name = breed_name }
		end,
	}
end

-- Helper: set up group extension with follow unit
local function make_group_extension(follow_unit)
	return {
		bot_group_data = function()
			return { follow_unit = follow_unit }
		end,
	}
end

-- Helper: set up a mock side system with enemy units for daemonhost detection
local function setup_side_system(bot_unit, enemy_units)
	local enemy_side = {
		ai_target_units = enemy_units or {},
	}
	_mock_side_system = {
		side_by_unit = {
			[bot_unit] = {
				relation_side_names = function()
					return { "enemy" }
				end,
			},
		},
		get_side_from_name = function(_self, _name)
			return enemy_side
		end,
	}
end

-- Reset all mocks between tests
local function reset()
	for k in pairs(_extensions) do
		_extensions[k] = nil
	end
	for k in pairs(_positions) do
		_positions[k] = nil
	end
	for k in pairs(_alive) do
		_alive[k] = nil
	end
	for k in pairs(_blackboards) do
		_blackboards[k] = nil
	end
	_mock_side_system = nil
end

describe("sprint", function()
	before_each(function()
		reset()
	end)

	describe("should_sprint", function()
		it("blocks when not moving forward", function()
			local self_obj = make_self({ move = { x = 0, y = 0.3 } })
			local ok, reason = Sprint.should_sprint(self_obj, "bot1", {})
			assert.is_false(ok)
			assert.equals("not_moving_forward", reason)
		end)

		it("blocks when move is nil", function()
			local self_obj = { _move = nil }
			local ok, reason = Sprint.should_sprint(self_obj, "bot1", {})
			assert.is_false(ok)
			assert.equals("not_moving_forward", reason)
		end)

		it("sprints during traversal with no enemies", function()
			local unit = "bot1"
			setup_perception(unit, {})
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)

		it("blocks sprint when enemies nearby", function()
			local unit = "bot1"
			local enemy = "enemy1"
			setup_perception(unit, { enemy })
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("sprints to catch up when far from follow unit", function()
			local unit = "bot1"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(20, 0, 0)
			_alive[follow] = true
			setup_perception(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("catch_up", reason)
		end)

		it("does not catch-up sprint when close to follow unit", function()
			local unit = "bot1"
			local follow = "player1"
			_positions[unit] = pos(0, 0, 0)
			_positions[follow] = pos(5, 0, 0)
			_alive[follow] = true
			setup_perception(unit, {})
			setup_behavior(unit, {})
			setup_side_system(unit, {})
			local self_obj = make_self({
				group_extension = make_group_extension(follow),
			})
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- Close to follow, no enemies -> traversal
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)

		it("sprints to rescue allies", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "knocked_down",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_true(ok)
			assert.equals("ally_rescue", reason)
		end)

		it("does not sprint for attention_look ally aid", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "in_need_of_attention_look",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("does not sprint for attention_stop ally aid", function()
			local unit = "bot1"
			setup_perception(unit, { "enemy1" })
			setup_behavior(unit, {
				target_ally_needs_aid = true,
				target_ally_need_type = "in_need_of_attention_stop",
			})
			setup_side_system(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("enemies_nearby", reason)
		end)

		it("blocks sprint near daemonhost", function()
			local unit = "bot1"
			local dh = "daemonhost1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("daemonhost_nearby", reason)
		end)

		it("blocks sprint near mutator daemonhost", function()
			local unit = "bot1"
			local dh = "mdh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(15, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_mutator_daemonhost")
			setup_side_system(unit, { dh })
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			assert.is_false(ok)
			assert.equals("daemonhost_nearby", reason)
		end)

		it("allows sprint when daemonhost is beyond safe range", function()
			local unit = "bot1"
			local dh = "daemonhost_far"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(25, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			setup_perception(unit, {})
			setup_behavior(unit, {})
			local self_obj = make_self()
			local ok, reason = Sprint.should_sprint(self_obj, unit, {})
			-- Daemonhost at 25m > 20m safe range, no aggroed enemies -> traversal
			assert.is_true(ok)
			assert.equals("traversal", reason)
		end)
	end)

	describe("is_near_daemonhost", function()
		it("returns false with no side system", function()
			_positions["bot1"] = pos(0, 0, 0)
			assert.is_false(Sprint.is_near_daemonhost("bot1"))
		end)

		it("returns false with no enemies on side", function()
			local unit = "bot1"
			_positions[unit] = pos(0, 0, 0)
			setup_side_system(unit, {})
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true for close daemonhost", function()
			local unit = "bot1"
			local dh = "dh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for far daemonhost", function()
			local unit = "bot1"
			local dh = "dh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(25, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for non-daemonhost enemy", function()
			local unit = "bot1"
			local enemy = "poxwalker1"
			_positions[unit] = pos(0, 0, 0)
			_positions[enemy] = pos(3, 0, 0)
			_alive[enemy] = true
			setup_breed(enemy, "chaos_poxwalker")
			setup_side_system(unit, { enemy })
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("detects mutator daemonhost", function()
			local unit = "bot1"
			local dh = "mdh1"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(10, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_mutator_daemonhost")
			setup_side_system(unit, { dh })
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns false for aggroed daemonhost", function()
			local unit = "bot1"
			local dh = "dh_aggro"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			_blackboards[dh] = { perception = { aggro_state = "aggroed" } }
			assert.is_false(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true for alerted (non-aggroed) daemonhost", function()
			local unit = "bot1"
			local dh = "dh_alerted"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			_blackboards[dh] = { perception = { aggro_state = "alerted" } }
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)

		it("returns true when daemonhost has no blackboard", function()
			local unit = "bot1"
			local dh = "dh_no_bb"
			_positions[unit] = pos(0, 0, 0)
			_positions[dh] = pos(5, 0, 0)
			_alive[dh] = true
			setup_breed(dh, "chaos_daemonhost")
			setup_side_system(unit, { dh })
			-- No BLACKBOARDS entry — treat as dormant (conservative)
			assert.is_true(Sprint.is_near_daemonhost(unit))
		end)
	end)
end)
