local function load_module()
	local ok, mod = pcall(dofile, "scripts/mods/BetterBots/melee_attack_choice.lua")
	assert.is_true(ok, "melee_attack_choice.lua should load")
	return mod
end

local ARMORED = 2

local function attack_meta(opts)
	opts = opts or {}
	return {
		arc = opts.arc or 0,
		penetrating = opts.penetrating or false,
		no_damage = opts.no_damage or false,
		max_range = 2.5,
		action_inputs = {},
	}
end

describe("melee_attack_choice", function()
	it("prefers light attacks into unarmored hordes when heavy only wins on wide-arc bias", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = attack_meta({ arc = 0, penetrating = false }),
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, 1, 4, ARMORED)

		assert.equals(weapon_meta_data.light_attack, chosen)
	end)

	it("preserves heavy preference against armored targets", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = attack_meta({ arc = 0, penetrating = false }),
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, ARMORED, 4, ARMORED)

		assert.equals(weapon_meta_data.heavy_attack, chosen)
	end)

	it("falls back to the vanilla light-only default when attack_meta_data is missing", function()
		local MeleeAttackChoice = load_module()

		local chosen = MeleeAttackChoice.choose_attack_meta_data(nil, 1, 1, ARMORED)

		assert.equals("light_attack", chosen.action_inputs[2].action_input)
	end)

	it("registers a _choose_attack hook", function()
		local MeleeAttackChoice = load_module()
		local hooked_method
		local stub_mod = {
			hook_require = function(_, path, callback)
				assert.equals(
					"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action",
					path
				)
				callback({})
			end,
			hook = function(_, _, method_name, _handler)
				hooked_method = method_name
			end,
		}

		_G.Armor = {
			armor_type = function()
				return 1
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
		})

		MeleeAttackChoice.register_hooks()

		assert.equals("_choose_attack", hooked_method)
		_G.Armor = nil
	end)
end)
