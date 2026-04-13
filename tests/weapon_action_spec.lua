local test_helper = require("tests.test_helper")

local _extensions = {}
local _blackboards = {}
local _debug_logs = {}

_G.ScriptUnit = {
	has_extension = function(unit, system_name)
		local exts = _extensions[unit]
		return exts and exts[system_name] or nil
	end,
}

_G.BLACKBOARDS = setmetatable({}, {
	__index = function(_, unit)
		return _blackboards[unit]
	end,
})

local WeaponAction = dofile("scripts/mods/BetterBots/weapon_action.lua")

local function reset(opts)
	opts = opts or {}

	for unit in pairs(_extensions) do
		_extensions[unit] = nil
	end
	for unit in pairs(_blackboards) do
		_blackboards[unit] = nil
	end
	_debug_logs = {}

	WeaponAction.init({
		mod = opts.mod or {
			hook_require = function() end,
			hook = function() end,
			hook_safe = function() end,
			echo = function() end,
		},
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
			return 12
		end,
		bot_slot_for_unit = function()
			return 3
		end,
		ammo = {
			current_slot_percentage = function()
				return 0.35
			end,
		},
	})
end

local function make_hooking_mod(hook_targets)
	return {
		hook_require = function(_, path, callback)
			local target = hook_targets[path]
			if target then
				callback(target)
			end
		end,
		hook = function(_, target, method_name, handler)
			local original = target[method_name]
			target[method_name] = function(...)
				return handler(original, ...)
			end
		end,
		hook_safe = function(_, target, method_name, handler)
			local original = target[method_name]
			target[method_name] = function(...)
				local result = original(...)
				handler(...)
				return result
			end
		end,
		echo = function() end,
	}
end

local function find_debug_log(pattern)
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			return _debug_logs[i]
		end
	end

	return nil
end

describe("weapon_action", function()
	before_each(function()
		reset()
	end)

	it("detects normal ranged fire in the old ammo dead zone", function()
		local unit = "bot_1"
		local target = "poxwalker_1"

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "bolter_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}
		_extensions[target] = {
			unit_data_system = test_helper.make_minion_unit_data_extension({ name = "chaos_poxwalker", tags = {} }),
		}
		_blackboards[unit] = {
			perception = {
				target_enemy = target,
			},
		}

		local info = WeaponAction.dead_zone_ranged_fire_context(unit, "shoot_pressed")

		assert.is_not_nil(info)
		assert.equals(0.35, info.ammo_pct)
		assert.equals("chaos_poxwalker", info.target_breed_name)
		assert.equals("bolter_p1_m1", info.weapon_template_name)
	end)

	it("ignores elite/special priority targets for dead-zone fire logging", function()
		local unit = "bot_1"
		local target = "gunner_1"

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "bolter_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}
		_extensions[target] = {
			unit_data_system = test_helper.make_minion_unit_data_extension({
				name = "renegade_gunner",
				tags = { elite = true },
			}),
		}
		_blackboards[unit] = {
			perception = {
				target_enemy = target,
			},
		}

		assert.is_nil(WeaponAction.dead_zone_ranged_fire_context(unit, "shoot_pressed"))
	end)

	it("logs dead-zone ranged fire confirmations with target context", function()
		local unit = "bot_1"
		local target = "poxwalker_1"

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "bolter_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}
		_extensions[target] = {
			unit_data_system = test_helper.make_minion_unit_data_extension({ name = "chaos_poxwalker", tags = {} }),
		}
		_blackboards[unit] = {
			perception = {
				target_enemy = target,
			},
		}

		local logged = WeaponAction.log_dead_zone_ranged_fire(unit, "shoot_pressed")

		assert.is_true(logged)
		assert.is_truthy(find_debug_log("ranged dead-zone override kept normal shot"))
	end)

	it("normalizes braced stream scratchpads to use brace release", function()
		local weapon_template = {
			action_inputs = {
				brace_pressed = { input_sequence = { { input = "action_two_hold", value = true } } },
				brace_release = { input_sequence = { { input = "action_two_hold", value = false } } },
				shoot_braced = { input_sequence = { { input = "action_one_hold", value = true } } },
			},
			actions = {
				action_brace = {
					start_input = "brace_pressed",
					allowed_chain_actions = {
						shoot_braced = { action_name = "action_shoot_braced" },
						brace_release = { action_name = "action_unbrace" },
					},
				},
				action_unbrace = { start_input = "brace_release", kind = "unaim" },
				action_shoot_braced = { start_input = "shoot_braced" },
			},
		}
		local scratchpad = {
			aim_fire_action_input = "shoot_braced",
			aim_fire_action_name = "action_shoot_braced",
			aim_action_input = "zoom",
			aim_action_name = "action_zoom",
			unaim_action_input = "unzoom",
			unaim_action_name = "action_unzoom",
		}

		local changed = WeaponAction._normalize_bt_shoot_scratchpad(weapon_template, scratchpad)

		assert.is_true(changed)
		assert.equals("brace_pressed", scratchpad.aim_action_input)
		assert.equals("action_brace", scratchpad.aim_action_name)
		assert.equals("brace_release", scratchpad.unaim_action_input)
		assert.equals("action_unbrace", scratchpad.unaim_action_name)
	end)

	it("logs stream action confirmations for flamer and purgatus queue inputs", function()
		local logged_flamer = WeaponAction.log_stream_action(3, "flamer_p1_m1", "shoot_braced")
		local logged_purgatus = WeaponAction.log_stream_action(3, "forcestaff_p2_m1", "trigger_charge_flame")

		assert.is_true(logged_flamer)
		assert.is_true(logged_purgatus)
		assert.is_truthy(find_debug_log("stream action queued for flamer_p1_m1 via shoot_braced"))
		assert.is_truthy(find_debug_log("stream action queued for forcestaff_p2_m1 via trigger_charge_flame"))
	end)

	it("forwards queued stream actions to the observer hook", function()
		local observed_unit, observed_action_input
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function(_self, _id, _action_input, _raw_input)
				return 0
			end,
		}
		local bot_unit = "bot_1"

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "flamer_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}

		WeaponAction.register_hooks({
			should_lock_weapon_switch = function()
				return false
			end,
			should_block_wield_input = function()
				return false
			end,
			should_block_weapon_action_input = function()
				return false
			end,
			observe_queued_weapon_action = function(unit, action_input)
				observed_unit = unit
				observed_action_input = action_input
			end,
		})

		PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_braced", nil)

		assert.equals(bot_unit, observed_unit)
		assert.equals("shoot_braced", observed_action_input)
		assert.is_truthy(find_debug_log("stream action queued for flamer_p1_m1 via shoot_braced"))
	end)

	it("translates warp reload to vent before forwarding queued actions", function()
		local forwarded_action_input
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function(_self, _id, action_input, _raw_input)
				forwarded_action_input = action_input
				return 1
			end,
		}
		local bot_unit = "bot_1"

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "forcestaff_p2_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
				warp_charge = { current_percentage = 0.5 },
			}),
		}

		WeaponAction.register_hooks({
			should_lock_weapon_switch = function()
				return false
			end,
			should_block_wield_input = function()
				return false
			end,
			should_block_weapon_action_input = function()
				return false
			end,
			observe_queued_weapon_action = function() end,
		})

		PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "reload", nil)

		assert.equals("vent", forwarded_action_input)
	end)
end)
