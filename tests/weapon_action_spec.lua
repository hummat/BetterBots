local test_helper = require("tests.test_helper")

local _extensions = {}
local _blackboards = {}
local _debug_logs = {}
local _echoes = {}
local _warnings = {}
local _saved_globals = {}
local _saved_position_lookup = rawget(_G, "POSITION_LOOKUP")
local _saved_vector3 = rawget(_G, "Vector3")
local _saved_quaternion = rawget(_G, "Quaternion")

local WeaponActionLogging = dofile("scripts/mods/BetterBots/weapon_action_logging.lua")
local WeaponActionShoot = dofile("scripts/mods/BetterBots/weapon_action_shoot.lua")
local WeaponActionVoidblast = dofile("scripts/mods/BetterBots/weapon_action_voidblast.lua")
local WeaponAction = dofile("scripts/mods/BetterBots/weapon_action.lua")

local vec_mt = {}

vec_mt.__add = function(a, b)
	return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vec_mt)
end

vec_mt.__sub = function(a, b)
	return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec_mt)
end

vec_mt.__mul = function(a, b)
	if type(a) == "number" then
		return setmetatable({ x = a * b.x, y = a * b.y, z = a * b.z }, vec_mt)
	end

	return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, vec_mt)
end

local function vec(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, vec_mt)
end

local function install_rotation_math_globals()
	_G.Vector3 = {
		flat = function(v)
			return vec(v.x, v.y, 0)
		end,
		normalize = function(v)
			local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
			if length == 0 then
				return vec(0, 0, 0)
			end

			return vec(v.x / length, v.y / length, v.z / length)
		end,
		up = function()
			return vec(0, 0, 1)
		end,
		right = function()
			return vec(1, 0, 0)
		end,
		length_squared = function(v)
			return v.x * v.x + v.y * v.y + v.z * v.z
		end,
	}

	local Quaternion = {}
	Quaternion.look = function(direction)
		local yaw = math.atan(direction.x, direction.y)
		local flat_length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
		local pitch = math.atan(direction.z, flat_length)

		return {
			yaw = yaw,
			pitch = pitch,
		}
	end
	Quaternion.multiply = function(a, b)
		return {
			yaw = a.yaw or 0,
			pitch = (a.pitch or 0) + (b.angle or 0),
		}
	end
	Quaternion.to_yaw_pitch_roll = function(rotation)
		return rotation.yaw or 0, rotation.pitch or 0, rotation.roll or 0
	end
	Quaternion.from_yaw_pitch_roll = function(yaw, pitch, roll)
		return {
			yaw = yaw,
			pitch = pitch,
			roll = roll,
		}
	end

	setmetatable(Quaternion, {
		__call = function(_, axis, angle)
			return {
				axis = axis,
				angle = angle,
			}
		end,
	})

	_G.Quaternion = Quaternion
end

setup(function()
	_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")
	_saved_globals.BLACKBOARDS = rawget(_G, "BLACKBOARDS")
	_saved_globals.HEALTH_ALIVE = rawget(_G, "HEALTH_ALIVE")
	_saved_globals.ALIVE = rawget(_G, "ALIVE")
	_saved_globals.Unit = rawget(_G, "Unit")

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
	rawset(_G, "BLACKBOARDS", _saved_globals.BLACKBOARDS)
	rawset(_G, "ScriptUnit", _saved_globals.ScriptUnit)
end)

local function reset(opts)
	opts = opts or {}
	local ammo = opts.ammo

	for unit in pairs(_extensions) do
		_extensions[unit] = nil
	end
	for unit in pairs(_blackboards) do
		_blackboards[unit] = nil
	end
	_debug_logs = {}
	_echoes = {}
	_warnings = {}
	if ammo == nil and not opts.no_ammo then
		ammo = {
			current_slot_percentage = function()
				return 0.35
			end,
		}
	end

	WeaponAction.init({
		mod = opts.mod or {
			hook_require = function() end,
			hook = function() end,
			hook_safe = function() end,
			echo = function(_, message)
				_echoes[#_echoes + 1] = message
			end,
			warning = function(_, message)
				_warnings[#_warnings + 1] = message
			end,
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
		ammo = ammo,
		is_enabled = opts.is_enabled,
		close_range_ranged_policy = opts.close_range_ranged_policy or function(weapon_template)
			local keywords = weapon_template and weapon_template.keywords or {}
			for i = 1, #keywords do
				if keywords[i] == "flamer" then
					return {
						family = "flamer",
						hold_ranged_target_distance_sq = 100,
						hipfire_distance_sq = 100,
					}
				end
			end

			return nil
		end,
		warp_weapon_peril_threshold = opts.warp_weapon_peril_threshold or function()
			return 0.99
		end,
		is_weakspot_aim_enabled = opts.is_weakspot_aim_enabled or function()
			return true
		end,
		weapon_action_logging = WeaponActionLogging,
		weapon_action_shoot = WeaponActionShoot,
		weapon_action_voidblast = WeaponActionVoidblast,
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
		echo = function(_, message)
			_echoes[#_echoes + 1] = message
		end,
		warning = function(_, message)
			_warnings[#_warnings + 1] = message
		end,
	}
end

local function make_duplicate_detecting_hooking_mod(hook_targets)
	local installed = {}

	local function install_hook(hook_type, target, method_name, installer)
		local key = tostring(target) .. ":" .. tostring(method_name) .. ":" .. tostring(hook_type)
		assert.is_nil(installed[key], "duplicate " .. hook_type .. " install for " .. tostring(method_name))
		installed[key] = true
		return installer()
	end

	return {
		hook_require = function(_, path, callback)
			local target = hook_targets[path]
			if target then
				callback(target)
				callback(target)
			end
		end,
		hook = function(_, target, method_name, handler)
			return install_hook("hook", target, method_name, function()
				local original = target[method_name]
				target[method_name] = function(...)
					return handler(original, ...)
				end
			end)
		end,
		hook_safe = function(_, target, method_name, handler)
			return install_hook("hook_safe", target, method_name, function()
				local original = target[method_name]
				target[method_name] = function(...)
					local result = original(...)
					handler(...)
					return result
				end
			end)
		end,
		echo = function(_, message)
			_echoes[#_echoes + 1] = message
		end,
		warning = function(_, message)
			_warnings[#_warnings + 1] = message
		end,
	}
end

local function make_classname_duplicate_detecting_hooking_mod(path_to_targets)
	local installed = {}

	local function target_name(target)
		return tostring(rawget(target, "__name") or rawget(target, "name") or target)
	end

	local function install_hook(hook_type, target, method_name, installer)
		local key = target_name(target) .. ":" .. tostring(method_name) .. ":" .. tostring(hook_type)
		assert.is_nil(installed[key], "duplicate " .. hook_type .. " install for " .. tostring(method_name))
		installed[key] = true
		return installer()
	end

	return {
		hook_require = function(_, path, callback)
			local targets = path_to_targets[path]
			if targets then
				for i = 1, #targets do
					callback(targets[i])
				end
			end
		end,
		hook = function(_, target, method_name, handler)
			return install_hook("hook", target, method_name, function()
				local original = target[method_name]
				target[method_name] = function(...)
					return handler(original, ...)
				end
			end)
		end,
		hook_safe = function(_, target, method_name, handler)
			return install_hook("hook_safe", target, method_name, function()
				local original = target[method_name]
				target[method_name] = function(...)
					local result = original(...)
					handler(...)
					return result
				end
			end)
		end,
		echo = function(_, message)
			_echoes[#_echoes + 1] = message
		end,
		warning = function(_, message)
			_warnings[#_warnings + 1] = message
		end,
	}
end

local function make_dmf_like_hooking_mod(path_to_targets)
	local installed = {}

	local function install_hook(target, method_name, handler, installer)
		local key = tostring(target) .. ":" .. tostring(method_name)
		assert.is_nil(installed[key], "dmf duplicate method hook for " .. tostring(method_name))
		installed[key] = handler
		return installer()
	end

	return {
		hook_require = function(_, path, callback)
			local target = path_to_targets[path]
			if target then
				callback(target)
			end
		end,
		hook = function(_, target, method_name, handler)
			return install_hook(target, method_name, handler, function()
				local original = target[method_name]
				target[method_name] = function(...)
					return handler(original, ...)
				end
			end)
		end,
		hook_safe = function(_, target, method_name, handler)
			return install_hook(target, method_name, handler, function()
				local original = target[method_name]
				target[method_name] = function(...)
					local result = original(...)
					handler(...)
					return result
				end
			end)
		end,
		echo = function(_, message)
			_echoes[#_echoes + 1] = message
		end,
		warning = function(_, message)
			_warnings[#_warnings + 1] = message
		end,
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

local function count_debug_logs(pattern)
	local count = 0
	for i = 1, #_debug_logs do
		if string.find(_debug_logs[i].message, pattern, 1, true) then
			count = count + 1
		end
	end

	return count
end

local function find_warning(pattern)
	for i = 1, #_warnings do
		if string.find(_warnings[i], pattern, 1, true) then
			return _warnings[i]
		end
	end

	return nil
end

local function find_echo(pattern)
	for i = 1, #_echoes do
		if string.find(_echoes[i], pattern, 1, true) then
			return _echoes[i]
		end
	end

	return nil
end

describe("weapon_action", function()
	before_each(function()
		reset()
	end)

	after_each(function()
		rawset(_G, "POSITION_LOOKUP", _saved_position_lookup)
		rawset(_G, "Vector3", _saved_vector3)
		rawset(_G, "Quaternion", _saved_quaternion)
		rawset(_G, "HEALTH_ALIVE", _saved_globals.HEALTH_ALIVE)
		rawset(_G, "ALIVE", _saved_globals.ALIVE)
		rawset(_G, "Unit", _saved_globals.Unit)
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

	it("clears stale zoom inputs when the current weapon has no aim chain", function()
		local weapon_template = {
			action_inputs = {
				shoot_pressed = { input_sequence = { { input = "action_one_pressed", value = true } } },
			},
			actions = {
				action_shoot = { start_input = "shoot_pressed" },
			},
		}
		local scratchpad = {
			aim_fire_action_input = "shoot_pressed",
			aim_action_input = "zoom",
			aim_action_name = "action_zoom",
			unaim_action_input = "unzoom",
			unaim_action_name = "action_unzoom",
		}

		local changed = WeaponAction._normalize_bt_shoot_scratchpad(weapon_template, scratchpad)

		assert.is_true(changed)
		assert.is_nil(scratchpad.aim_action_input)
		assert.is_nil(scratchpad.aim_action_name)
		assert.is_nil(scratchpad.unaim_action_input)
		assert.is_nil(scratchpad.unaim_action_name)
	end)

	it("normalizes plasma scratchpads away from vanilla shoot defaults", function()
		local weapon_template = {
			action_inputs = {
				shoot_charge = { input_sequence = { { input = "action_one_pressed", value = true } } },
				vent = { input_sequence = { { input = "weapon_extra_hold", value = true } } },
			},
			actions = {
				action_charge_direct = { start_input = "shoot_charge" },
			},
		}
		local scratchpad = {
			fire_action_input = "shoot",
			aim_fire_action_input = "zoom_shoot",
			aim_action_input = "zoom",
			unaim_action_input = "vent",
		}

		local changed = WeaponAction._normalize_bt_shoot_scratchpad(weapon_template, scratchpad)

		assert.is_true(changed)
		assert.equals("shoot_charge", scratchpad.fire_action_input)
		assert.equals("shoot_charge", scratchpad.aim_fire_action_input)
		assert.is_nil(scratchpad.aim_action_input)
		assert.is_nil(scratchpad.unaim_action_input)
	end)

	it("logs stream action confirmations for flamer and purgatus queue inputs", function()
		local logged_flamer = WeaponAction.log_stream_action(3, "flamer_p1_m1", "shoot_braced")
		local logged_purgatus = WeaponAction.log_stream_action(3, "forcestaff_p2_m1", "trigger_charge_flame")

		assert.is_true(logged_flamer)
		assert.is_true(logged_purgatus)
		assert.is_truthy(find_debug_log("stream action queued for flamer_p1_m1 via shoot_braced"))
		assert.is_truthy(find_debug_log("stream action queued for forcestaff_p2_m1 via trigger_charge_flame"))
	end)

	it("drops blocked foreign weapon actions before forwarding them", function()
		local forwarded_calls = 0
		local observed_action_input
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				forwarded_calls = forwarded_calls + 1
				return 1
			end,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
		})

		WeaponAction.register_hooks({
			should_lock_weapon_switch = function()
				return false
			end,
			should_block_wield_input = function()
				return false
			end,
			should_block_weapon_action_input = function(_unit, action_input)
				if action_input == "charge_release" then
					return true, "psyker_smite", "wait_followup"
				end
				return false
			end,
			observe_queued_weapon_action = function(_unit, action_input)
				observed_action_input = action_input
			end,
		})

		local result = PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = "bot_1",
		}, "weapon_action", "charge_release", nil)

		assert.is_nil(result)
		assert.equals(0, forwarded_calls)
		assert.is_nil(observed_action_input)
		assert.is_truthy(find_debug_log("blocked foreign weapon action charge_release while keeping psyker_smite"))
	end)

	it("drops unsupported queued zoom inputs for the current template", function()
		local forwarded_calls = 0
		local observed_action_input
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				forwarded_calls = forwarded_calls + 1
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
				weapon_action = { template_name = "plasmagun_p1_m1" },
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
			observe_queued_weapon_action = function(_unit, action_input)
				observed_action_input = action_input
			end,
		})

		local result = PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
			_action_input_parsers = {
				weapon_action = {
					_ACTION_INPUT_SEQUENCE_CONFIGS = {
						plasmagun_p1_m1 = {
							brace_pressed = true,
							shoot_charge = true,
						},
					},
				},
			},
		}, "weapon_action", "zoom", nil)

		assert.is_nil(result)
		assert.equals(0, forwarded_calls)
		assert.is_nil(observed_action_input)
		assert.is_truthy(find_debug_log("dropped unsupported queued weapon action zoom"))
	end)

	it("logs weakspot aim selections when the head/spine table is active", function()
		local unit = "bot_1"
		local weapon_template = {
			attack_meta_data = {
				aim_at_node = { "j_head", "j_spine" },
			},
		}
		local scratchpad = {
			aim_at_node = "j_head",
		}

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "lasgun_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}

		local logged = WeaponAction.log_weakspot_aim_selection(unit, weapon_template, scratchpad)

		assert.is_true(logged)
		assert.is_truthy(find_debug_log("weakspot aim selected j_head (weapon=lasgun_p1_m1, bot=3)"))
	end)

	it("does not log weakspot aim selections when weakspot aim is disabled", function()
		local unit = "bot_1"
		local weapon_template = {
			attack_meta_data = {
				aim_at_node = { "j_head", "j_spine" },
			},
		}
		local scratchpad = {
			aim_at_node = "j_head",
		}

		reset({
			is_weakspot_aim_enabled = function()
				return false
			end,
		})

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "lasgun_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}

		local logged = WeaponAction.log_weakspot_aim_selection(unit, weapon_template, scratchpad)

		assert.is_false(logged)
		assert.is_falsy(find_debug_log("weakspot aim selected j_head (weapon=lasgun_p1_m1, bot=3)"))
	end)

	it("warns once when the ammo utility require keeps failing", function()
		local saved_require = require
		local unit = "bot_1"

		reset({
			no_ammo = true,
		})

		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "bolter_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}

		rawset(_G, "require", function(path)
			if path == "scripts/utilities/ammo" then
				error("boom")
			end

			return saved_require(path)
		end)

		WeaponAction.dead_zone_ranged_fire_context(unit, "shoot_pressed")
		WeaponAction.dead_zone_ranged_fire_context(unit, "shoot_pressed")

		rawset(_G, "require", saved_require)

		assert.equals(1, #_warnings)
		assert.is_truthy(find_warning("ammo utility unavailable"))
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

	it("logs queued weapon action target context and refreshes per target", function()
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				return 0
			end,
		}
		local bot_unit = "bot_1"
		local first_target = "gunner_1"
		local second_target = "shotgunner_1"

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "bolter_p1_m2" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
		}
		_extensions[first_target] = {
			unit_data_system = test_helper.make_minion_unit_data_extension({
				name = "renegade_gunner",
				tags = { special = true },
			}),
		}
		_extensions[second_target] = {
			unit_data_system = test_helper.make_minion_unit_data_extension({
				name = "renegade_shocktrooper",
				tags = { minion = true },
			}),
		}
		_blackboards[bot_unit] = {
			perception = {
				target_enemy = first_target,
			},
		}
		rawset(_G, "HEALTH_ALIVE", {
			[first_target] = true,
			[second_target] = false,
		})

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
		})

		PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", nil)
		_blackboards[bot_unit].perception.target_enemy = second_target
		PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", nil)

		assert.is_truthy(find_debug_log("target=gunner_1 target_alive=alive target_breed=renegade_gunner"))
		assert.is_truthy(find_debug_log("target=shotgunner_1 target_alive=dead target_breed=renegade_shocktrooper"))
		assert.equals(2, count_debug_logs("bot weapon: bot=3"))
	end)

	it("applies weapon_action rewrites before forwarding queued inputs", function()
		local forwarded_id, forwarded_action_input, forwarded_raw_input
		local observed_action_input, observed_original_action_input
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function(_self, id, action_input, raw_input)
				forwarded_id = id
				forwarded_action_input = action_input
				forwarded_raw_input = raw_input
				return 0
			end,
		}
		local bot_unit = "bot_1"

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
		})

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
			rewrite_weapon_action_input = function(unit, action_input, raw_input)
				assert.equals(bot_unit, unit)
				assert.equals("shoot_pressed", action_input)
				assert.equals("keep", raw_input)
				return "special_action", raw_input
			end,
			observe_queued_weapon_action = function(_unit, action_input, original_action_input)
				observed_action_input = action_input
				observed_original_action_input = original_action_input
			end,
		})

		PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", "keep")

		assert.equals("weapon_action", forwarded_id)
		assert.equals("special_action", forwarded_action_input)
		assert.equals("keep", forwarded_raw_input)
		assert.equals("special_action", observed_action_input)
		assert.equals("shoot_pressed", observed_original_action_input)
	end)

	it("logs when shoot scratchpad normalization is skipped because bot extensions are missing", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, "bot_1", nil, nil, {})

		rawset(_G, "require", saved_require)

		assert.is_truthy(find_debug_log("shoot scratchpad normalization skipped"))
	end)

	it("logs a plasma _may_fire block reason when shoot selection never queues a shot", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return false
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			fire_action_input = "shoot_charge",
			aim_fire_action_input = "shoot_charge",
			obstructed = true,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})
		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "plasmagun_p1_m1" },
			}),
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		assert.is_false(BtBotShootAction._may_fire({}, bot_unit, scratchpad, 100, 12))

		rawset(_G, "require", saved_require)

		assert.is_truthy(find_debug_log("plasma _may_fire blocked (reason=obstructed"))
	end)

	it("does not reinstall bt_bot_shoot_action hooks when hook_require callback runs twice", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}

		reset({
			mod = make_duplicate_detecting_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		rawset(_G, "require", saved_require)
	end)

	it("does not reinstall bt_bot_shoot_action hooks when hook_require resolves a fresh class table", function()
		local saved_require = require
		local BtBotShootActionA = {
			__name = "BtBotShootAction",
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local BtBotShootActionB = {
			__name = "BtBotShootAction",
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}

		reset({
			mod = make_classname_duplicate_detecting_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = {
					BtBotShootActionA,
					BtBotShootActionB,
				},
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		rawset(_G, "require", saved_require)
	end)

	it("does not compete with weakspot aim for the same BtBotShootAction.enter hook slot", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_set_new_aim_target = function() end,
			_aim_position = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local WeakspotAim = dofile("scripts/mods/BetterBots/weakspot_aim.lua")
		local mod = make_dmf_like_hooking_mod({
			["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
		})

		reset({
			mod = mod,
		})
		WeakspotAim.init({
			mod = mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			is_enabled = function()
				return true
			end,
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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
			install_weakspot_aim = WeakspotAim.install_on_shoot_action,
		})

		rawset(_G, "require", saved_require)
	end)

	it("stores the shooter unit on the scratchpad in the BtBotShootAction.enter post-hook", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local scratchpad = {}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, "bot_1", nil, nil, scratchpad)

		rawset(_G, "require", saved_require)

		assert.equals("bot_1", scratchpad.__bb_weakspot_self_unit)
	end)

	it("locks Voidblast charged aim to the first target while refreshing its target-root point", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_set_new_aim_target = function(_self, _t, target_unit, scratchpad)
				scratchpad.target_unit = target_unit
				scratchpad.target_breed = { name = "chaos_poxwalker" }
				scratchpad.aim_speed_yaw = 0
			end,
			_update_aim = function(self, unit, scratchpad, action_data, dt, t)
				local target_unit = scratchpad.perception_component.target_enemy
				if target_unit ~= scratchpad.target_unit then
					self:_set_new_aim_target(t, target_unit, scratchpad, action_data)
				end

				local _, _, wanted_rotation, _, aim_position = self:_aim_position(
					unit,
					scratchpad,
					action_data,
					dt,
					scratchpad.current_position,
					scratchpad.current_rotation,
					target_unit
				)

				scratchpad.last_wanted_rotation = wanted_rotation
				scratchpad.last_aim_position = aim_position

				return false, false
			end,
			_aim_position = function(
				self,
				self_unit,
				scratchpad,
				_action_data,
				_dt,
				current_position,
				current_rotation,
				target_unit
			)
				local wanted_rotation, aim_position = self:_wanted_aim_rotation(
					self_unit,
					target_unit,
					scratchpad.target_breed,
					current_position,
					nil,
					scratchpad.aim_at_node
				)

				return 0, 0, wanted_rotation, current_rotation, aim_position
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_calculate_aim_speed = function(_self, _dt, current_yaw, current_pitch, wanted_yaw, wanted_pitch)
				return wanted_yaw - current_yaw, wanted_pitch - current_pitch
			end,
			_target_velocity = function(_self, target_unit)
				if target_unit == "target_a" then
					return vec(0, 4, 0)
				end

				return vec(0, 0, 0)
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			aim_speed_yaw = 0,
			charging_shot = true,
			current_position = vec(0, 0, 1.5),
			current_rotation = { yaw = 0, pitch = 0 },
			minimum_charge_time = 0.3,
			perception_component = {
				target_enemy = "target_a",
			},
			target_breed = { name = "chaos_poxwalker" },
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		local first_aim_position = scratchpad.last_aim_position
		local first_wanted_rotation = scratchpad.last_wanted_rotation

		POSITION_LOOKUP.target_a = vec(0, 12, 0)
		scratchpad.perception_component.target_enemy = "target_b"
		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0.1)
		local second_aim_position = scratchpad.last_aim_position
		local second_wanted_rotation = scratchpad.last_wanted_rotation

		rawset(_G, "require", saved_require)

		assert.equals("target_a", scratchpad.target_unit)
		assert.is_true(first_wanted_rotation.pitch < 0)
		assert.is_true(second_wanted_rotation.pitch < 0)
		assert.is_true(first_aim_position.y > 10)
		assert.equals(first_aim_position.x, second_aim_position.x)
		assert.is_true(second_aim_position.y > first_aim_position.y)
		assert.equals(first_aim_position.z, second_aim_position.z)
		assert.is_truthy(find_debug_log("voidblast anchor locked"))
		assert.is_truthy(find_debug_log("voidblast anchor held through retarget"))
	end)

	it("locks Voidblast aim-driven charge to the first target while refreshing its target-root point", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_set_new_aim_target = function(_self, _t, target_unit, scratchpad)
				scratchpad.target_unit = target_unit
				scratchpad.target_breed = { name = "chaos_poxwalker" }
				scratchpad.aim_speed_yaw = 0
			end,
			_update_aim = function(self, unit, scratchpad, action_data, dt, t)
				local target_unit = scratchpad.perception_component.target_enemy
				if target_unit ~= scratchpad.target_unit then
					self:_set_new_aim_target(t, target_unit, scratchpad, action_data)
				end

				local _, _, wanted_rotation, _, aim_position = self:_aim_position(
					unit,
					scratchpad,
					action_data,
					dt,
					scratchpad.current_position,
					scratchpad.current_rotation,
					target_unit
				)

				scratchpad.last_wanted_rotation = wanted_rotation
				scratchpad.last_aim_position = aim_position

				return false, false
			end,
			_aim_position = function(
				self,
				self_unit,
				scratchpad,
				_action_data,
				_dt,
				current_position,
				current_rotation,
				target_unit
			)
				local wanted_rotation, aim_position = self:_wanted_aim_rotation(
					self_unit,
					target_unit,
					scratchpad.target_breed,
					current_position,
					nil,
					scratchpad.aim_at_node
				)

				return 0, 0, wanted_rotation, current_rotation, aim_position
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_calculate_aim_speed = function(_self, _dt, current_yaw, current_pitch, wanted_yaw, wanted_pitch)
				return wanted_yaw - current_yaw, wanted_pitch - current_pitch
			end,
			_target_velocity = function(_self, target_unit)
				if target_unit == "target_a" then
					return vec(0, 4, 0)
				end

				return vec(0, 0, 0)
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			aim_action_input = "charge",
			aim_speed_yaw = 0,
			aiming_shot = true,
			charging_shot = false,
			current_position = vec(0, 0, 1.5),
			current_rotation = { yaw = 0, pitch = 0 },
			minimum_charge_time = 0.3,
			perception_component = {
				target_enemy = "target_a",
			},
			target_breed = { name = "chaos_poxwalker" },
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = {
					template_name = "forcestaff_p1_m1",
					current_action_name = "action_charge",
				},
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

		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		local first_aim_position = scratchpad.last_aim_position
		local first_wanted_rotation = scratchpad.last_wanted_rotation

		POSITION_LOOKUP.target_a = vec(0, 12, 0)
		scratchpad.perception_component.target_enemy = "target_b"
		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0.1)
		local second_aim_position = scratchpad.last_aim_position
		local second_wanted_rotation = scratchpad.last_wanted_rotation

		rawset(_G, "require", saved_require)

		assert.equals("target_a", scratchpad.target_unit)
		assert.is_true(first_wanted_rotation.pitch < 0)
		assert.is_true(second_wanted_rotation.pitch < 0)
		assert.is_true(first_aim_position.y > 10)
		assert.equals(first_aim_position.x, second_aim_position.x)
		assert.is_true(second_aim_position.y > first_aim_position.y)
		assert.equals(first_aim_position.z, second_aim_position.z)
		assert.is_truthy(find_debug_log("voidblast anchor locked"))
		assert.is_truthy(find_debug_log("voidblast anchor held through retarget"))
	end)

	it("leaves non-Voidblast charged retargeting on the vanilla path", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_set_new_aim_target = function(_self, _t, target_unit, scratchpad)
				scratchpad.target_unit = target_unit
			end,
			_update_aim = function(self, unit, scratchpad, action_data, dt, t)
				local target_unit = scratchpad.perception_component.target_enemy
				if target_unit ~= scratchpad.target_unit then
					self:_set_new_aim_target(t, target_unit, scratchpad, action_data)
				end

				local _, _, _, _, aim_position = self:_aim_position(
					unit,
					scratchpad,
					action_data,
					dt,
					scratchpad.current_position,
					scratchpad.current_rotation,
					target_unit
				)

				scratchpad.last_aim_position = aim_position

				return false, false
			end,
			_aim_position = function(
				self,
				self_unit,
				scratchpad,
				_action_data,
				_dt,
				current_position,
				current_rotation,
				target_unit
			)
				local wanted_rotation, aim_position = self:_wanted_aim_rotation(
					self_unit,
					target_unit,
					scratchpad.target_breed,
					current_position,
					nil,
					scratchpad.aim_at_node
				)

				return 0, 0, wanted_rotation, current_rotation, aim_position
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_calculate_aim_speed = function(_self, _dt, current_yaw, current_pitch, wanted_yaw, wanted_pitch)
				return wanted_yaw - current_yaw, wanted_pitch - current_pitch
			end,
			_target_velocity = function()
				return vec(0, 4, 0)
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			aim_speed_yaw = 0,
			charging_shot = true,
			current_position = vec(0, 0, 1.5),
			current_rotation = { yaw = 0, pitch = 0 },
			minimum_charge_time = 0.3,
			perception_component = {
				target_enemy = "target_a",
			},
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p4_m1" },
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

		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		scratchpad.perception_component.target_enemy = "target_b"
		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0.1)
		local aim_position = scratchpad.last_aim_position

		rawset(_G, "require", saved_require)

		assert.equals("target_b", scratchpad.target_unit)
		assert.equals(POSITION_LOOKUP.target_b.x, aim_position.x)
		assert.equals(POSITION_LOOKUP.target_b.y, aim_position.y)
		assert.equals(POSITION_LOOKUP.target_b.z, aim_position.z)
		assert.is_nil(find_debug_log("voidblast anchor locked"))
		assert.is_nil(find_debug_log("voidblast anchor held through retarget"))
	end)

	it("does not lock Voidblast charge aim when ranged improvements are disabled", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_set_new_aim_target = function(_self, _t, target_unit, scratchpad)
				scratchpad.target_unit = target_unit
				scratchpad.target_breed = { name = "chaos_poxwalker" }
				scratchpad.aim_speed_yaw = 0
			end,
			_update_aim = function(self, unit, scratchpad, action_data, dt, t)
				local target_unit = scratchpad.perception_component.target_enemy
				if target_unit ~= scratchpad.target_unit then
					self:_set_new_aim_target(t, target_unit, scratchpad, action_data)
				end

				local _, _, _, _, aim_position = self:_aim_position(
					unit,
					scratchpad,
					action_data,
					dt,
					scratchpad.current_position,
					scratchpad.current_rotation,
					target_unit
				)

				scratchpad.last_aim_position = aim_position

				return false, false
			end,
			_aim_position = function(
				self,
				self_unit,
				scratchpad,
				_action_data,
				_dt,
				current_position,
				current_rotation,
				target_unit
			)
				local wanted_rotation, aim_position = self:_wanted_aim_rotation(
					self_unit,
					target_unit,
					scratchpad.target_breed,
					current_position,
					nil,
					scratchpad.aim_at_node
				)

				return 0, 0, wanted_rotation, current_rotation, aim_position
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			aim_speed_yaw = 0,
			charging_shot = true,
			current_position = vec(0, 0, 1.5),
			current_rotation = { yaw = 0, pitch = 0 },
			minimum_charge_time = 0.3,
			perception_component = {
				target_enemy = "target_a",
			},
			target_breed = { name = "chaos_poxwalker" },
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
			is_enabled = function()
				return false
			end,
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		scratchpad.perception_component.target_enemy = "target_b"
		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0.1)
		local aim_position = scratchpad.last_aim_position

		rawset(_G, "require", saved_require)

		assert.equals("target_b", scratchpad.target_unit)
		assert.equals(POSITION_LOOKUP.target_b.x, aim_position.x)
		assert.equals(POSITION_LOOKUP.target_b.y, aim_position.y)
		assert.equals(POSITION_LOOKUP.target_b.z, aim_position.z)
		assert.is_nil(find_debug_log("voidblast anchor locked"))
		assert.is_nil(find_debug_log("voidblast anchor held through retarget"))
	end)

	it("forces Voidblast charged fire through trigger_explosion even without ADS aim state", function()
		local saved_require = require
		local queued_inputs = {}
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
			_fire = function(_self, scratchpad)
				scratchpad.charging_shot, scratchpad.charge_start_time, scratchpad.fired = false, nil, true

				local action_input_extension = scratchpad.action_input_extension
				local aiming_shot = scratchpad.aiming_shot
				local fire_action_input = scratchpad.fire_action_input
				local aim_fire_action_input = scratchpad.aim_fire_action_input
				local action_input = aiming_shot and aim_fire_action_input or fire_action_input

				action_input_extension:bot_queue_action_input("weapon_action", action_input, nil)
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
				bot_queue_action_input = function(_, component, input)
					queued_inputs[#queued_inputs + 1] = {
						component = component,
						input = input,
					}
				end,
			},
			aim_fire_action_input = "trigger_explosion",
			aiming_shot = false,
			charging_shot = true,
			fire_action_input = "shoot_pressed",
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		BtBotShootAction._fire(BtBotShootAction, scratchpad, {}, nil, 0)
		rawset(_G, "require", saved_require)

		assert.equals(1, #queued_inputs)
		assert.equals("weapon_action", queued_inputs[1].component)
		assert.equals("trigger_explosion", queued_inputs[1].input)
		assert.is_truthy(find_debug_log("voidblast charged fire override"))
	end)

	it(
		"forces Voidblast charged fire through trigger_explosion when live metadata still exposes shoot_pressed",
		function()
			local saved_require = require
			local queued_inputs = {}
			local BtBotShootAction = {
				enter = function() end,
				_start_aiming = function() end,
				_may_fire = function()
					return true
				end,
				_fire = function(_self, scratchpad)
					scratchpad.charging_shot, scratchpad.charge_start_time, scratchpad.fired = false, nil, true

					local action_input_extension = scratchpad.action_input_extension
					local aiming_shot = scratchpad.aiming_shot
					local fire_action_input = scratchpad.fire_action_input
					local aim_fire_action_input = scratchpad.aim_fire_action_input
					local action_input = aiming_shot and aim_fire_action_input or fire_action_input

					action_input_extension:bot_queue_action_input("weapon_action", action_input, nil)
				end,
			}
			local bot_unit = "bot_1"
			local scratchpad = {
				action_input_extension = {
					_betterbots_player_unit = bot_unit,
					bot_queue_action_input = function(_, component, input)
						queued_inputs[#queued_inputs + 1] = {
							component = component,
							input = input,
						}
					end,
				},
				aim_fire_action_input = "shoot_pressed",
				aiming_shot = false,
				charging_shot = true,
				fire_action_input = "shoot_pressed",
			}

			reset({
				mod = make_hooking_mod({
					["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
				}),
			})

			rawset(_G, "require", function(path)
				if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
					return {
						wielded_weapon_template = function()
							return nil
						end,
					}
				end

				return saved_require(path)
			end)

			_extensions[bot_unit] = {
				unit_data_system = test_helper.make_player_unit_data_extension({
					weapon_action = { template_name = "forcestaff_p1_m1" },
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

			BtBotShootAction._fire(BtBotShootAction, scratchpad, {}, nil, 0)
			rawset(_G, "require", saved_require)

			assert.equals(1, #queued_inputs)
			assert.equals("weapon_action", queued_inputs[1].component)
			assert.equals("trigger_explosion", queued_inputs[1].input)
			assert.is_truthy(find_debug_log("voidblast charged fire override"))
		end
	)

	it("forces Voidblast charge-state fire through trigger_explosion on the live action_charge path", function()
		local saved_require = require
		local queued_inputs = {}
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
			_fire = function(_self, scratchpad)
				scratchpad.charging_shot, scratchpad.charge_start_time, scratchpad.fired = false, nil, true

				local action_input_extension = scratchpad.action_input_extension
				local aiming_shot = scratchpad.aiming_shot
				local fire_action_input = scratchpad.fire_action_input
				local aim_fire_action_input = scratchpad.aim_fire_action_input
				local action_input = aiming_shot and aim_fire_action_input or fire_action_input

				action_input_extension:bot_queue_action_input("weapon_action", action_input, nil)
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
				bot_queue_action_input = function(_, component, input)
					queued_inputs[#queued_inputs + 1] = {
						component = component,
						input = input,
					}
				end,
			},
			aim_action_input = "charge",
			aim_fire_action_input = "shoot_pressed",
			aiming_shot = false,
			charging_shot = false,
			fire_action_input = "shoot_pressed",
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = {
					template_name = "forcestaff_p1_m1",
					current_action_name = "action_charge",
				},
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

		BtBotShootAction._fire(BtBotShootAction, scratchpad, {}, nil, 0)
		rawset(_G, "require", saved_require)

		assert.equals(1, #queued_inputs)
		assert.equals("weapon_action", queued_inputs[1].component)
		assert.equals("trigger_explosion", queued_inputs[1].input)
		assert.is_truthy(find_debug_log("voidblast charged fire override"))
	end)

	it("passes _fire through unchanged for non-Voidblast templates", function()
		local saved_require = require
		local cases = {
			{
				template_name = "forcestaff_p4_m1",
				aim_fire_action_input = "shoot_charged",
				charging_shot = true,
			},
			{
				template_name = "autogun_p1_m1",
				aim_fire_action_input = "zoom_shoot",
				charging_shot = false,
			},
		}

		for index, case in ipairs(cases) do
			local queued_inputs = {}
			local BtBotShootAction = {
				enter = function() end,
				_start_aiming = function() end,
				_may_fire = function()
					return true
				end,
				_fire = function(_self, scratchpad)
					local action_input_extension = scratchpad.action_input_extension
					local aiming_shot = scratchpad.aiming_shot
					local fire_action_input = scratchpad.fire_action_input
					local aim_fire_action_input = scratchpad.aim_fire_action_input
					local action_input = aiming_shot and aim_fire_action_input or fire_action_input

					action_input_extension:bot_queue_action_input("weapon_action", action_input, nil)

					return "vanilla"
				end,
			}
			local bot_unit = "bot_" .. tostring(index)
			local scratchpad = {
				action_input_extension = {
					_betterbots_player_unit = bot_unit,
					bot_queue_action_input = function(_, component, input)
						queued_inputs[#queued_inputs + 1] = {
							component = component,
							input = input,
						}
					end,
				},
				aim_fire_action_input = case.aim_fire_action_input,
				aiming_shot = false,
				charging_shot = case.charging_shot,
				fire_action_input = "shoot_pressed",
			}

			reset({
				mod = make_hooking_mod({
					["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
				}),
			})

			rawset(_G, "require", function(path)
				if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
					return {
						wielded_weapon_template = function()
							return nil
						end,
					}
				end

				return saved_require(path)
			end)

			_extensions[bot_unit] = {
				unit_data_system = test_helper.make_player_unit_data_extension({
					weapon_action = { template_name = case.template_name },
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

			local result = BtBotShootAction._fire(BtBotShootAction, scratchpad, {}, nil, 0)
			rawset(_G, "require", saved_require)

			assert.equals("vanilla", result, case.template_name)
			assert.equals(1, #queued_inputs, case.template_name)
			assert.equals("weapon_action", queued_inputs[1].component, case.template_name)
			assert.equals("shoot_pressed", queued_inputs[1].input, case.template_name)
			assert.equals(case.aim_fire_action_input, scratchpad.aim_fire_action_input, case.template_name)
			assert.is_false(scratchpad.aiming_shot, case.template_name)
			assert.is_nil(find_debug_log("voidblast charged fire override"), case.template_name)
		end
	end)

	it("restores _fire scratchpad state and rethrows the original Voidblast error", function()
		local saved_require = require
		local observed_aim_fire_action_input, observed_aiming_shot
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
			_fire = function(_self, scratchpad)
				observed_aim_fire_action_input = scratchpad.aim_fire_action_input
				observed_aiming_shot = scratchpad.aiming_shot
				error("boom")
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			aim_fire_action_input = "shoot_pressed",
			aiming_shot = false,
			charging_shot = true,
			fire_action_input = "shoot_pressed",
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		local ok, err = pcall(function()
			BtBotShootAction._fire(BtBotShootAction, scratchpad, {}, nil, 0)
		end)
		rawset(_G, "require", saved_require)

		assert.is_false(ok)
		assert.is_nil(string.find(err, "scripts/mods/BetterBots/weapon_action.lua", 1, true))
		assert.matches("boom", err)
		assert.equals("trigger_explosion", observed_aim_fire_action_input)
		assert.is_true(observed_aiming_shot)
		assert.equals("shoot_pressed", scratchpad.aim_fire_action_input)
		assert.is_false(scratchpad.aiming_shot)
		assert.is_truthy(find_debug_log("voidblast charged fire override"))
	end)

	it("restores the forced Voidblast target and scratchpad context when _update_aim throws", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_update_aim = function()
				error("boom")
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			charging_shot = true,
			current_position = vec(0, 0, 1.5),
			perception_component = {
				target_enemy = "target_b",
			},
			__bb_voidblast_anchor = {
				target_unit = "target_a",
				position = vec(0, 11.2, 0),
			},
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		local ok, err = pcall(function()
			BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		end)
		rawset(_G, "require", saved_require)

		assert.is_false(ok)
		assert.is_nil(string.find(err, "scripts/mods/BetterBots/weapon_action.lua", 1, true))
		assert.matches("boom", err)
		assert.equals("target_b", scratchpad.perception_component.target_enemy)
		assert.truthy(find_debug_log("restored Voidblast locked target after vanilla _update_aim error"))

		local _, aim_position = BtBotShootAction._wanted_aim_rotation(
			BtBotShootAction,
			bot_unit,
			"target_b",
			nil,
			vec(0, 0, 1.5),
			nil,
			"j_head"
		)

		assert.equals(POSITION_LOOKUP.target_b.x, aim_position.x)
		assert.equals(POSITION_LOOKUP.target_b.y, aim_position.y)
		assert.equals(POSITION_LOOKUP.target_b.z, aim_position.z)
	end)

	it("drops a stale Voidblast anchor when target velocity lookup fails before retargeting vanilla aim", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_update_aim = function(self, unit, scratchpad, action_data, dt, t)
				local target_unit = scratchpad.perception_component.target_enemy
				if target_unit ~= scratchpad.target_unit then
					self:_set_new_aim_target(t, target_unit, scratchpad, action_data)
				end

				local _, _, _, _, aim_position = self:_aim_position(
					unit,
					scratchpad,
					action_data,
					dt,
					scratchpad.current_position,
					scratchpad.current_rotation,
					target_unit
				)

				scratchpad.last_aim_position = aim_position

				return false, false
			end,
			_set_new_aim_target = function(_self, _t, target_unit, scratchpad)
				scratchpad.target_unit = target_unit
				scratchpad.target_breed = { name = "chaos_poxwalker" }
			end,
			_aim_position = function(
				self,
				self_unit,
				scratchpad,
				_action_data,
				_dt,
				current_position,
				current_rotation,
				target_unit
			)
				local wanted_rotation, aim_position = self:_wanted_aim_rotation(
					self_unit,
					target_unit,
					scratchpad.target_breed,
					current_position,
					nil,
					scratchpad.aim_at_node
				)

				return 0, 0, wanted_rotation, current_rotation, aim_position
			end,
			_wanted_aim_rotation = function(_self, _self_unit, target_unit)
				return { yaw = 0, pitch = 0 }, POSITION_LOOKUP[target_unit]
			end,
			_target_velocity = function(_self, target_unit)
				if target_unit == "target_a" then
					error("missing locomotion_system")
				end

				return vec(0, 0, 0)
			end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function() end,
			_stop_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
			},
			charging_shot = true,
			current_position = vec(0, 0, 1.5),
			current_rotation = { yaw = 0, pitch = 0 },
			minimum_charge_time = 0.3,
			perception_component = {
				target_enemy = "target_b",
			},
			target_breed = { name = "chaos_poxwalker" },
			target_unit = "target_b",
			__bb_voidblast_anchor = {
				target_unit = "target_a",
				position = vec(0, 11.2, 0),
			},
		}

		install_rotation_math_globals()
		_G.POSITION_LOOKUP = {
			target_a = vec(0, 10, 0),
			target_b = vec(10, 0, 0),
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "forcestaff_p1_m1" },
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

		BtBotShootAction._update_aim(BtBotShootAction, bot_unit, scratchpad, {}, 1, 0)
		rawset(_G, "require", saved_require)

		assert.equals("target_b", scratchpad.perception_component.target_enemy)
		assert.is_nil(scratchpad.__bb_voidblast_anchor)
		assert.equals(POSITION_LOOKUP.target_b.x, scratchpad.last_aim_position.x)
		assert.equals(POSITION_LOOKUP.target_b.y, scratchpad.last_aim_position.y)
		assert.equals(POSITION_LOOKUP.target_b.z, scratchpad.last_aim_position.z)
		assert.truthy(find_debug_log("voidblast aim fallback (reason=target_velocity_unavailable"))
	end)

	it("reinstalls bt_bot_shoot_action hooks after init resets the module-local guard", function()
		local saved_require = require
		local BtBotShootActionA = {
			__name = "BtBotShootAction",
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local BtBotShootActionB = {
			__name = "BtBotShootAction",
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}

		reset({
			mod = make_classname_duplicate_detecting_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = {
					BtBotShootActionA,
				},
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		reset({
			mod = make_classname_duplicate_detecting_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = {
					BtBotShootActionB,
				},
			}),
		})

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

		rawset(_G, "require", saved_require)
	end)

	it("warns when bt_bot_shoot_action hook_require resolves nil", function()
		reset({
			mod = {
				hook_require = function(_, _path, callback)
					callback(nil)
				end,
				hook = function() end,
				hook_safe = function() end,
				echo = function(_, message)
					_echoes[#_echoes + 1] = message
				end,
				warning = function(_, message)
					_warnings[#_warnings + 1] = message
				end,
			},
		})

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

		assert.is_truthy(find_warning("bt_bot_shoot_action hook_require resolved nil"))
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

	it("bridges warp peril into Overheat.slot_percentage when config is missing", function()
		local unit = "bot_1"
		local Overheat = {
			slot_percentage = function()
				return 0
			end,
			configuration = function()
				return nil
			end,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/utilities/overheat"] = Overheat,
			}),
		})

		_extensions[unit] = {
			visual_loadout_system = {},
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
				warp_charge = { current_percentage = 0.72 },
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

		assert.equals(0.72, Overheat.slot_percentage(unit, "slot_secondary", "venting"))
	end)

	it("falls back to the original Overheat.slot_percentage when config exists", function()
		local unit = "bot_1"
		local original_calls = 0
		local Overheat = {
			slot_percentage = function()
				original_calls = original_calls + 1
				return 0.41
			end,
			configuration = function()
				return {
					venting = true,
				}
			end,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/utilities/overheat"] = Overheat,
			}),
		})

		_extensions[unit] = {
			visual_loadout_system = {},
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

		assert.equals(0.41, Overheat.slot_percentage(unit, "slot_secondary", "venting"))
		assert.equals(1, original_calls)
	end)

	it("is idempotent when the Overheat hook_require callback fires twice", function()
		local unit = "bot_1"
		local configuration_calls = 0
		local Overheat = {
			slot_percentage = function()
				return 0.41
			end,
			configuration = function()
				configuration_calls = configuration_calls + 1
				return { venting = true }
			end,
		}

		local double_fire_mod = {
			hook_require = function(_, path, callback)
				if path == "scripts/utilities/overheat" then
					callback(Overheat)
					callback(Overheat)
				end
			end,
			hook = function() end,
			hook_safe = function() end,
			echo = function() end,
			warning = function() end,
		}

		reset({ mod = double_fire_mod })
		_extensions[unit] = { visual_loadout_system = {} }

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

		Overheat.slot_percentage(unit, "slot_secondary", "venting")

		assert.equals(1, configuration_calls)
	end)

	it("blocks non-vent warp actions at critical peril", function()
		local forwarded_calls = 0
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				forwarded_calls = forwarded_calls + 1
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
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
				warp_charge = { current_percentage = 0.99 },
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

		local result = PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", nil)

		assert.is_nil(result)
		assert.equals(0, forwarded_calls)
		assert.is_truthy(find_debug_log("blocked shoot_pressed"))
	end)

	it("allows non-vent warp actions below the 99 percent peril guard", function()
		local forwarded_calls = 0
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				forwarded_calls = forwarded_calls + 1
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
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
				warp_charge = { current_percentage = 0.98 },
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

		local result = PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", nil)

		assert.equals(1, result)
		assert.equals(1, forwarded_calls)
		assert.is_falsy(find_debug_log("blocked shoot_pressed"))
	end)

	it("respects the configured warp peril threshold", function()
		local forwarded_calls = 0
		local PlayerUnitActionInputExtension = {
			extensions_ready = function() end,
			bot_queue_action_input = function()
				forwarded_calls = forwarded_calls + 1
				return 1
			end,
		}
		local bot_unit = "bot_1"

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/action_input/player_unit_action_input_extension"] = PlayerUnitActionInputExtension,
			}),
			warp_weapon_peril_threshold = function()
				return 0.98
			end,
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
				warp_charge = { current_percentage = 0.98 },
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

		local result = PlayerUnitActionInputExtension.bot_queue_action_input({
			_betterbots_player_unit = bot_unit,
		}, "weapon_action", "shoot_pressed", nil)

		assert.is_nil(result)
		assert.equals(0, forwarded_calls)
		assert.is_truthy(find_debug_log("blocked shoot_pressed"))
	end)

	it("skips ADS for close-range hipfire families when the target is near", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_should_aim = function()
				return true
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			perception_component = {
				target_ally = nil,
				target_ally_needs_aid = false,
				target_ally_distance = 0,
				target_enemy_distance = 5,
			},
			ranged_gestalt = "killshot",
		}
		local action_data = {
			gestalt_behaviors = {
				killshot = { wants_aim = true },
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "flamer_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
			visual_loadout_system = {},
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return {
							name = "flamer_p1_m1",
							keywords = { "ranged", "flamer", "p1" },
							actions = {},
						}
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, bot_unit, nil, nil, scratchpad)
		local should_aim = BtBotShootAction._should_aim({}, 0, scratchpad, action_data)

		rawset(_G, "require", saved_require)

		assert.is_false(should_aim)
	end)

	it("preserves ADS for close-range families once the target is outside the hipfire window", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_should_aim = function()
				return true
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			perception_component = {
				target_ally = nil,
				target_ally_needs_aid = false,
				target_ally_distance = 0,
				target_enemy_distance = 20,
			},
			ranged_gestalt = "killshot",
		}
		local action_data = {
			gestalt_behaviors = {
				killshot = { wants_aim = true },
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "flamer_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
			visual_loadout_system = {},
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return {
							name = "flamer_p1_m1",
							keywords = { "ranged", "flamer", "p1" },
							actions = {},
						}
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, bot_unit, nil, nil, scratchpad)
		local should_aim = BtBotShootAction._should_aim({}, 0, scratchpad, action_data)

		rawset(_G, "require", saved_require)

		assert.is_true(should_aim)
	end)

	it("preserves ADS for Purgatus inside the close-range hipfire window", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_should_aim = function()
				return true
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			perception_component = {
				target_ally = nil,
				target_ally_needs_aid = false,
				target_ally_distance = 0,
				target_enemy_distance = 5,
			},
			ranged_gestalt = "killshot",
		}
		local action_data = {
			gestalt_behaviors = {
				killshot = { wants_aim = true },
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "forcestaff_p2_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p2_m1_charge" },
			}),
			visual_loadout_system = {},
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return {
							name = "forcestaff_p2_m1",
							keywords = { "ranged", "staff" },
							actions = {},
						}
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, bot_unit, nil, nil, scratchpad)
		local should_aim = BtBotShootAction._should_aim({}, 0, scratchpad, action_data)

		rawset(_G, "require", saved_require)

		assert.is_true(should_aim)
	end)

	it("preserves ADS for ripperguns inside the close-range ranged window", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_should_aim = function()
				return true
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			perception_component = {
				target_ally = nil,
				target_ally_needs_aid = false,
				target_ally_distance = 0,
				target_enemy_distance = 5,
			},
			ranged_gestalt = "killshot",
		}
		local action_data = {
			gestalt_behaviors = {
				killshot = { wants_aim = true },
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "ogryn_rippergun_p1_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "none" },
			}),
			visual_loadout_system = {},
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return {
							name = "ogryn_rippergun_p1_m1",
							keywords = { "ranged", "rippergun", "p1" },
							actions = {},
						}
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, bot_unit, nil, nil, scratchpad)
		local should_aim = BtBotShootAction._should_aim({}, 0, scratchpad, action_data)

		rawset(_G, "require", saved_require)

		assert.is_true(should_aim)
	end)

	it("preserves ADS for forcestaff_p3_m1 inside the close-range ranged window", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_should_aim = function()
				return true
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			perception_component = {
				target_ally = nil,
				target_ally_needs_aid = false,
				target_ally_distance = 0,
				target_enemy_distance = 5,
			},
			ranged_gestalt = "killshot",
		}
		local action_data = {
			gestalt_behaviors = {
				killshot = { wants_aim = true },
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				inventory = { wielded_slot = "slot_secondary" },
				weapon_action = { template_name = "forcestaff_p3_m1" },
				weapon_tweak_templates = { warp_charge_template_name = "forcestaff_p3_m1_charge" },
			}),
			visual_loadout_system = {},
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return {
							name = "forcestaff_p3_m1",
							keywords = { "ranged", "staff" },
							actions = {},
						}
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction.enter({}, bot_unit, nil, nil, scratchpad)
		local should_aim = BtBotShootAction._should_aim({}, 0, scratchpad, action_data)

		rawset(_G, "require", saved_require)

		assert.is_true(should_aim)
	end)

	it("logs ADS confirmation on _start_aiming once per scratchpad", function()
		local saved_require = require
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_may_fire = function()
				return true
			end,
		}
		local scratchpad = { ranged_gestalt = "killshot" }

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction._start_aiming({}, 0, scratchpad)
		BtBotShootAction._start_aiming({}, 0, scratchpad)

		rawset(_G, "require", saved_require)

		assert.is_truthy(find_echo("bot ADS confirmed"))
	end)

	it("suppresses stale aim inputs when the live weapon no longer supports aiming", function()
		local saved_require = require
		local queued_calls = {}
		local BtBotShootAction = {
			enter = function() end,
			_should_aim = function()
				return true
			end,
			_start_aiming = function(_self, t, scratchpad)
				if not scratchpad.aiming_shot then
					scratchpad.aiming_shot = true
					scratchpad.aim_done_t = t + 0.2
					scratchpad.action_input_extension:bot_queue_action_input(
						"weapon_action",
						scratchpad.aim_action_input,
						nil
					)
				end
			end,
			_stop_aiming = function(_self, scratchpad)
				if scratchpad.aiming_shot then
					scratchpad.aiming_shot = false
					scratchpad.aim_done_t = 0
					scratchpad.action_input_extension:bot_queue_action_input(
						"weapon_action",
						scratchpad.unaim_action_input,
						nil
					)
				end
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			ranged_gestalt = "killshot",
			aim_action_input = "zoom",
			unaim_action_input = "zoom_release",
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
				_action_input_parsers = {
					weapon_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							chainaxe_p1_m2 = {
								start_attack = true,
								light_attack = true,
							},
						},
					},
				},
				bot_queue_action_input = function(_, id, action_input, raw_input)
					queued_calls[#queued_calls + 1] = {
						id = id,
						action_input = action_input,
						raw_input = raw_input,
					}
				end,
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "chainaxe_p1_m2" },
			}),
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		assert.is_false(BtBotShootAction._should_aim({}, 0, scratchpad, { gestalt_behaviors = {} }))

		BtBotShootAction._start_aiming({}, 0, scratchpad)
		scratchpad.aiming_shot = true
		scratchpad.aim_done_t = 1
		BtBotShootAction._stop_aiming({}, scratchpad)

		rawset(_G, "require", saved_require)

		assert.equals(0, #queued_calls)
		assert.is_false(scratchpad.aiming_shot)
		assert.equals(0, scratchpad.aim_done_t)
		assert.is_nil(find_echo("bot ADS confirmed"))
	end)

	it("does not queue plasma vent when stale ADS cleanup leaves no aim input", function()
		local saved_require = require
		local queued_calls = {}
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_stop_aiming = function(_self, scratchpad)
				if scratchpad.aiming_shot then
					scratchpad.aiming_shot = false
					scratchpad.aim_done_t = 0
					scratchpad.action_input_extension:bot_queue_action_input(
						"weapon_action",
						scratchpad.unaim_action_input,
						nil
					)
				end
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			aim_action_input = nil,
			unaim_action_input = "vent",
			aiming_shot = true,
			aim_done_t = 1,
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
				_action_input_parsers = {
					weapon_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							plasmagun_p1_m1 = {
								shoot_charge = true,
								vent = true,
							},
						},
					},
				},
				bot_queue_action_input = function(_, id, action_input, raw_input)
					queued_calls[#queued_calls + 1] = {
						id = id,
						action_input = action_input,
						raw_input = raw_input,
					}
				end,
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "plasmagun_p1_m1" },
			}),
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction._stop_aiming({}, scratchpad)

		rawset(_G, "require", saved_require)

		assert.equals(0, #queued_calls)
		assert.is_false(scratchpad.aiming_shot)
		assert.equals(0, scratchpad.aim_done_t)
		assert.is_truthy(find_debug_log("suppressed stale shoot unaim input vent for plasmagun_p1_m1"))
	end)

	it("preserves valid ADS unaim inputs for live aim-capable weapons", function()
		local saved_require = require
		local queued_calls = {}
		local BtBotShootAction = {
			enter = function() end,
			_start_aiming = function() end,
			_stop_aiming = function(_self, scratchpad)
				if scratchpad.aiming_shot then
					scratchpad.aiming_shot = false
					scratchpad.aim_done_t = 0
					scratchpad.action_input_extension:bot_queue_action_input(
						"weapon_action",
						scratchpad.unaim_action_input,
						nil
					)
				end
			end,
			_may_fire = function()
				return true
			end,
		}
		local bot_unit = "bot_1"
		local scratchpad = {
			aim_action_input = "zoom",
			unaim_action_input = "zoom_release",
			aiming_shot = true,
			aim_done_t = 1,
			action_input_extension = {
				_betterbots_player_unit = bot_unit,
				_action_input_parsers = {
					weapon_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							autogun_ads_test = {
								zoom = true,
								zoom_release = true,
								shoot = true,
							},
						},
					},
				},
				bot_queue_action_input = function(_, id, action_input, raw_input)
					queued_calls[#queued_calls + 1] = {
						id = id,
						action_input = action_input,
						raw_input = raw_input,
					}
				end,
			},
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action"] = BtBotShootAction,
			}),
		})

		_extensions[bot_unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "autogun_ads_test" },
			}),
		}

		rawset(_G, "require", function(path)
			if path == "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout" then
				return {
					wielded_weapon_template = function()
						return nil
					end,
				}
			end

			return saved_require(path)
		end)

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

		BtBotShootAction._stop_aiming({}, scratchpad)

		rawset(_G, "require", saved_require)

		assert.equals(1, #queued_calls)
		assert.equals("weapon_action", queued_calls[1].id)
		assert.equals("zoom_release", queued_calls[1].action_input)
		assert.is_false(scratchpad.aiming_shot)
		assert.equals(0, scratchpad.aim_done_t)
		assert.is_nil(find_debug_log("suppressed stale shoot unaim input zoom_release for autogun_ads_test"))
	end)

	it("redirects wield_slot to slot_combat_ability while lock is active", function()
		local wielded_slot
		local PlayerUnitVisualLoadout = {
			wield_slot = function(slot_to_wield)
				wielded_slot = slot_to_wield
				return slot_to_wield
			end,
		}

		reset({
			mod = make_hooking_mod({
				["scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout"] = PlayerUnitVisualLoadout,
			}),
		})

		WeaponAction.register_hooks({
			should_lock_weapon_switch = function()
				return true, "zealot_relic", "sequence", "slot_combat_ability"
			end,
			should_block_wield_input = function()
				return false
			end,
			should_block_weapon_action_input = function()
				return false
			end,
			observe_queued_weapon_action = function() end,
		})

		PlayerUnitVisualLoadout.wield_slot("slot_secondary", "bot_1", 0, false)

		assert.equals("slot_combat_ability", wielded_slot)
	end)
end)
