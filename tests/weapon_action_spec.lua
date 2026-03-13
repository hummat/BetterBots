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

local function reset()
	for unit in pairs(_extensions) do
		_extensions[unit] = nil
	end
	for unit in pairs(_blackboards) do
		_blackboards[unit] = nil
	end
	_debug_logs = {}

	WeaponAction.init({
		mod = {
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
			unit_data_system = {
				read_component = function(_, component_name)
					if component_name == "inventory" then
						return { wielded_slot = "slot_secondary" }
					end
					if component_name == "weapon_action" then
						return { template_name = "bolter_p1_m1" }
					end
					if component_name == "weapon_tweak_templates" then
						return { warp_charge_template_name = "none" }
					end
					return nil
				end,
			},
		}
		_extensions[target] = {
			unit_data_system = {
				breed = function()
					return { name = "chaos_poxwalker", tags = {} }
				end,
			},
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
			unit_data_system = {
				read_component = function(_, component_name)
					if component_name == "inventory" then
						return { wielded_slot = "slot_secondary" }
					end
					if component_name == "weapon_action" then
						return { template_name = "bolter_p1_m1" }
					end
					if component_name == "weapon_tweak_templates" then
						return { warp_charge_template_name = "none" }
					end
					return nil
				end,
			},
		}
		_extensions[target] = {
			unit_data_system = {
				breed = function()
					return { name = "renegade_gunner", tags = { elite = true } }
				end,
			},
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
			unit_data_system = {
				read_component = function(_, component_name)
					if component_name == "inventory" then
						return { wielded_slot = "slot_secondary" }
					end
					if component_name == "weapon_action" then
						return { template_name = "bolter_p1_m1" }
					end
					if component_name == "weapon_tweak_templates" then
						return { warp_charge_template_name = "none" }
					end
					return nil
				end,
			},
		}
		_extensions[target] = {
			unit_data_system = {
				breed = function()
					return { name = "chaos_poxwalker", tags = {} }
				end,
			},
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
end)
