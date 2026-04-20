local test_helper = require("tests.test_helper")
local RangedSpecialAction = dofile("scripts/mods/BetterBots/ranged_special_action.lua")

local _extensions = {}
local _blackboards = {}
local _debug_logs = {}
local _saved_globals = {}

setup(function()
	_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")
	_saved_globals.BLACKBOARDS = rawget(_G, "BLACKBOARDS")
	_saved_globals.Armor = rawget(_G, "Armor")

	rawset(_G, "ScriptUnit", {
		has_extension = function(unit, system_name)
			local exts = _extensions[unit]
			return exts and exts[system_name] or nil
		end,
	})

	rawset(
		_G,
		"BLACKBOARDS",
		setmetatable({}, {
			__index = function(_, unit)
				return _blackboards[unit]
			end,
		})
	)
end)

teardown(function()
	rawset(_G, "ScriptUnit", _saved_globals.ScriptUnit)
	rawset(_G, "BLACKBOARDS", _saved_globals.BLACKBOARDS)
	rawset(_G, "Armor", _saved_globals.Armor)
end)

local function reset()
	for unit in pairs(_extensions) do
		_extensions[unit] = nil
	end
	for unit in pairs(_blackboards) do
		_blackboards[unit] = nil
	end
	_debug_logs = {}

	RangedSpecialAction.init({
		debug_log = function(key, fixed_t, message)
			_debug_logs[#_debug_logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
			}
		end,
		debug_enabled = function()
			return true
		end,
		fixed_time = function()
			return 21
		end,
		bot_slot_for_unit = function()
			return 4
		end,
		ARMOR_TYPE_ARMORED = 2,
		ARMOR_TYPE_SUPER_ARMOR = 6,
		is_enabled = function()
			return true
		end,
	})
end

local function find_debug_log(pattern)
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			return _debug_logs[i]
		end
	end

	return nil
end

local function mount_bot(unit, template_name, special_active)
	_extensions[unit] = {
		unit_data_system = test_helper.make_player_unit_data_extension({
			inventory = { wielded_slot = "slot_secondary" },
			slot_secondary = { special_active = special_active == true },
			weapon_action = { template_name = template_name },
		}),
	}
end

local function mount_target(unit, breed)
	_extensions[unit] = {
		unit_data_system = test_helper.make_minion_unit_data_extension(breed),
	}
end

local function set_target(bot_unit, target_unit)
	_blackboards[bot_unit] = {
		perception = {
			target_enemy = target_unit,
		},
	}
end

describe("ranged_special_action", function()
	before_each(function()
		reset()
	end)

	it("rewrites supported shotgun fire into special_action for armored elite targets", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "shotgun_p1_m1", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit)

		local action_input, raw_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("special_action", action_input)
		assert.is_nil(raw_input)
	end)

	it("does not rewrite unsupported shotgun templates", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "shotgun_p2_m1", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("does not rewrite rippergun fire into shotgun special_action", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_rippergun_p1_m1", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("does not rewrite when the shotgun special is already active", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "shotgun_p1_m1", true)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("logs shotgun special arm and spend against the queued target breed", function()
		local bot_unit = "bot_1"
		local first_target = "crusher_1"
		local second_target = "poxwalker_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "shotgun_p1_m1", false)
		mount_target(first_target, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		mount_target(second_target, {
			name = "chaos_poxwalker",
			tags = {},
		})
		set_target(bot_unit, first_target)

		RangedSpecialAction.observe_queued_weapon_action(bot_unit, "special_action", "shoot_pressed")
		assert.is_truthy(find_debug_log("armed shotgun special for shotgun_p1_m1 target=renegade_executor"))

		set_target(bot_unit, second_target)
		RangedSpecialAction.observe_queued_weapon_action(bot_unit, "shoot_pressed", "shoot_pressed")
		assert.is_truthy(find_debug_log("spent shotgun special for shotgun_p1_m1 target=chaos_poxwalker"))
	end)
end)
