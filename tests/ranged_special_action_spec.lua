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

local function reset(opts)
	opts = opts or {}

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
		rippergun_bayonet_distance = opts.rippergun_bayonet_distance,
		ranged_bash_distance = opts.ranged_bash_distance,
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

local function set_target(bot_unit, target_unit, target_distance)
	_blackboards[bot_unit] = {
		perception = {
			target_enemy = target_unit,
			target_enemy_distance = target_distance,
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

	it("does not rewrite rippergun fire without a close target distance", function()
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

	it("does not rewrite close rippergun fire for low-value targets", function()
		local bot_unit = "bot_1"
		local target_unit = "poxwalker_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 1
			end,
		})

		mount_bot(bot_unit, "ogryn_rippergun_p1_m3", false)
		mount_target(target_unit, {
			name = "chaos_poxwalker",
			tags = {},
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("rewrites close rippergun fire into a bayonet stab for armored elite targets", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_rippergun_p1_m3", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input, raw_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("stab", action_input)
		assert.is_nil(raw_input)
	end)

	it("does not rewrite rippergun fire into bayonet stabs at range", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_rippergun_p1_m3", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 5.1)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("honors the configured rippergun bayonet distance", function()
		reset({
			rippergun_bayonet_distance = function()
				return 2
			end,
		})

		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_rippergun_p1_m3", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("shoot_pressed", action_input)
	end)

	it("logs queued rippergun bayonet stabs against the current target breed", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		mount_bot(bot_unit, "ogryn_rippergun_p1_m3", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		RangedSpecialAction.observe_queued_weapon_action(bot_unit, "stab", "shoot_pressed")

		assert.is_truthy(find_debug_log("queued rippergun bayonet for ogryn_rippergun_p1_m3 target=renegade_executor"))
	end)

	it("rewrites close heavy stubber fire into a weapon bash for armored elite targets", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_heavystubber_p1_m2", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input, raw_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot", nil)

		assert.equals("stab", action_input)
		assert.is_nil(raw_input)
	end)

	it("rewrites close thumper fire into a weapon bash for armored elite targets", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_thumper_p1_m1", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input, raw_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil)

		assert.equals("bash", action_input)
		assert.is_nil(raw_input)
	end)

	it("does not rewrite heavy stubber flashlight variants into ranged bashes", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_heavystubber_p2_m1", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot", nil)

		assert.equals("shoot", action_input)
	end)

	it("honors the configured ranged bash distance", function()
		reset({
			ranged_bash_distance = function()
				return 2
			end,
		})

		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_bot(bot_unit, "ogryn_heavystubber_p1_m2", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		local action_input = RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot", nil)

		assert.equals("shoot", action_input)
	end)

	it("logs queued ranged bashes against the current target breed", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		mount_bot(bot_unit, "ogryn_heavystubber_p1_m3", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		RangedSpecialAction.observe_queued_weapon_action(bot_unit, "stab", "shoot")

		assert.is_truthy(find_debug_log("queued ranged bash for ogryn_heavystubber_p1_m3 target=renegade_executor"))
	end)

	it("rewrites direct human ranged bash fire for armored elite targets", function()
		local cases = {
			{ template = "autogun_p2_m1", fire_input = "shoot", expected_input = "special_action" },
			{ template = "bolter_p1_m1", fire_input = "shoot_pressed", expected_input = "special_action" },
			{ template = "boltpistol_p1_m2", fire_input = "zoom_shoot", expected_input = "special_action" },
			{ template = "flamer_p1_m1", fire_input = "shoot_braced", expected_input = "special_action" },
			{ template = "laspistol_p1_m3", fire_input = "shoot_pressed", expected_input = "special_action_push" },
			{
				template = "stubrevolver_p1_m2",
				fire_input = "shoot_pressed",
				expected_input = "special_action_pistol_whip",
			},
			{ template = "dual_autopistols_p1_m1", fire_input = "shoot", expected_input = "weapon_special" },
		}

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		for _, case in ipairs(cases) do
			local bot_unit = "bot_" .. case.template
			local target_unit = "crusher_" .. case.template

			mount_bot(bot_unit, case.template, false)
			mount_target(target_unit, {
				name = "renegade_executor",
				tags = { elite = true },
			})
			set_target(bot_unit, target_unit, 2.4)

			local action_input, raw_input =
				RangedSpecialAction.rewrite_weapon_action_input(bot_unit, case.fire_input, nil)

			assert.equals(case.expected_input, action_input, case.template)
			assert.is_nil(raw_input)
		end
	end)

	it("keeps hold-release ranged bash families unsupported", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		rawset(_G, "Armor", {
			armor_type = function()
				return 2
			end,
		})

		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})

		mount_bot(bot_unit, "autogun_p3_m1", false)
		set_target(bot_unit, target_unit, 2.4)
		assert.equals("shoot", RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot", nil))

		mount_bot(bot_unit, "shotgun_p2_m1", false)
		set_target(bot_unit, target_unit, 2.4)
		assert.equals("shoot_pressed", RangedSpecialAction.rewrite_weapon_action_input(bot_unit, "shoot_pressed", nil))
	end)

	it("logs queued direct human ranged bashes against the current target breed", function()
		local bot_unit = "bot_1"
		local target_unit = "crusher_1"

		mount_bot(bot_unit, "stubrevolver_p1_m2", false)
		mount_target(target_unit, {
			name = "renegade_executor",
			tags = { elite = true },
		})
		set_target(bot_unit, target_unit, 2.4)

		RangedSpecialAction.observe_queued_weapon_action(bot_unit, "special_action_pistol_whip", "shoot_pressed")

		assert.is_truthy(find_debug_log("queued ranged bash for stubrevolver_p1_m2 target=renegade_executor"))
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
