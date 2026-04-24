local function load_module()
	local ok, mod = pcall(dofile, "scripts/mods/BetterBots/melee_attack_choice.lua")
	assert.is_true(ok, "melee_attack_choice.lua should load")
	return mod
end

local ARMORED = 2
local SUPER_ARMOR = 6
local saved_script_unit = rawget(_G, "ScriptUnit")
local saved_armor = rawget(_G, "Armor")

local function attack_meta(opts)
	opts = opts or {}
	return {
		arc = opts.arc or 0,
		penetrating = opts.penetrating or false,
		no_damage = opts.no_damage or false,
		max_range = 2.5,
		action_inputs = opts.action_inputs or {
			{ action_input = "start_attack", timing = 0 },
			{ action_input = "light_attack", timing = 0 },
		},
	}
end

describe("melee_attack_choice", function()
	after_each(function()
		_G.ScriptUnit = saved_script_unit
		_G.Armor = saved_armor
	end)

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

	it("treats super-armor targets as armored for attack scoring", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = attack_meta({ arc = 0, penetrating = false }),
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, SUPER_ARMOR, 1, ARMORED, SUPER_ARMOR)

		assert.equals(weapon_meta_data.heavy_attack, chosen)
	end)

	it("falls back to the vanilla light-only default when attack_meta_data is missing", function()
		local MeleeAttackChoice = load_module()

		local chosen = MeleeAttackChoice.choose_attack_meta_data(nil, 1, 1, ARMORED)

		assert.equals("light_attack", chosen.action_inputs[2].action_input)
	end)

	it("falls back to the vanilla light-only default when attack_meta_data is not a table", function()
		local MeleeAttackChoice = load_module()

		local chosen = MeleeAttackChoice.choose_attack_meta_data("broken", 1, 1, ARMORED)

		assert.equals("light_attack", chosen.action_inputs[2].action_input)
	end)

	it("prefers medium-arc control swings against a small crowd when armor is equal", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			jab_attack = attack_meta({ arc = 0, penetrating = false }),
			control_attack = attack_meta({ arc = 1, penetrating = false }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, ARMORED, 2, ARMORED)

		assert.equals(weapon_meta_data.control_attack, chosen)
	end)

	it("prefers non-damaging wide control swings only when massively outnumbered", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = attack_meta({ arc = 0, penetrating = false, no_damage = true }),
			control_attack = attack_meta({ arc = 2, penetrating = false, no_damage = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, ARMORED, 4, ARMORED)

		assert.equals(weapon_meta_data.control_attack, chosen)
	end)

	it("treats missing attack meta fields as safe defaults", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = {
				action_inputs = {
					{ action_input = "start_attack", timing = 0 },
					{ action_input = "light_attack", timing = 0 },
				},
			},
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, 1, 4, ARMORED)

		assert.equals(weapon_meta_data.light_attack, chosen)
	end)

	it("backfills chosen attack entries with a safe max_range default", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = {
				action_inputs = {
					{ action_input = "start_attack", timing = 0 },
					{ action_input = "light_attack", timing = 0 },
				},
			},
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, 1, 4, ARMORED)

		assert.equals(weapon_meta_data.light_attack, chosen)
		assert.equals(2.5, chosen.max_range)
	end)

	it("skips malformed attack entries that cannot drive a bot attack", function()
		local MeleeAttackChoice = load_module()
		local weapon_meta_data = {
			light_attack = {
				max_range = 2.5,
			},
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, 1, 4, ARMORED)

		assert.equals(weapon_meta_data.heavy_attack, chosen)
	end)

	it("installs a _choose_attack hook via install_melee_hooks", function()
		local MeleeAttackChoice = load_module()
		local hooked_methods = {}
		local stub_mod = {
			hook = function(_, _, method_name, _handler)
				hooked_methods[#hooked_methods + 1] = method_name
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

		MeleeAttackChoice.install_melee_hooks({})

		table.sort(hooked_methods)
		assert.same({ "_choose_attack", "enter" }, hooked_methods)
	end)

	it("installs melee hooks only once per shared BtBotMeleeAction table", function()
		local MeleeAttackChoice = load_module()
		local hook_calls = {}
		local stub_mod = {
			hook = function(_, target, method_name)
				hook_calls[#hook_calls + 1] = {
					target = target,
					method = method_name,
				}
			end,
		}
		local BtBotMeleeAction = {}

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

		MeleeAttackChoice.install_melee_hooks(BtBotMeleeAction)
		MeleeAttackChoice.install_melee_hooks(BtBotMeleeAction)

		assert.equals(2, #hook_calls)
	end)

	it("logs the chosen attack context for unarmored horde targets", function()
		local MeleeAttackChoice = load_module()
		local hook_handler
		local debug_logs = {}
		local stub_mod = {
			hook = function(_, _, _, handler)
				hook_handler = handler
			end,
		}

		_G.Armor = {
			armor_type = function()
				return 1
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 42
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({ arc = 2, penetrating = true })
		local scratchpad = {
			num_enemies_in_proximity = 4,
			weapon_template = {
				name = "powermaul_shield_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
		}

		local chosen = hook_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals(light_attack, chosen)
		assert.equals(1, #debug_logs)
		assert.matches("melee choice light_attack vs unarmored target", debug_logs[1].message, 1, true)
	end)

	it("prepends special_action before elite-target attacks for supported powered weapons", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "powersword_2h_p1_m2",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.65,
				family = "powersword_2h",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function(_self, _id, action_input)
					return action_input == "special_action"
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
		assert.equals(0.65, chosen.action_inputs[2].timing)
		assert.equals("heavy_attack", chosen.action_inputs[3].action_input)
		assert.equals(heavy_attack.max_range, chosen.max_range)
	end)

	it("resolves powersword_2h specials through enter when the template uses toggle_special", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function()
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return { special_active = false }
						end
						return nil
					end,
				}
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local scratchpad = {
			weapon_template = {
				name = "powersword_2h_p1_m1",
				actions = {
					action_toggle_special = {
						start_input = "special_action",
						kind = "toggle_special",
						allowed_chain_actions = {
							start_attack = {
								chain_time = 0.2,
							},
						},
					},
				},
			},
		}

		enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

		assert.same({
			action_input = "special_action",
			action_name = "action_toggle_special",
			chain_time = 0.2,
			family = "powersword_2h",
		}, scratchpad.special_action_meta)
	end)

	it("does not arm 1h power swords for solo trash cleanup", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "powersword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "powersword_1h",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals(light_attack, chosen)
	end)

	it("arms 1h power swords in live combat windows even against non-elite pack pressure", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 3,
			weapon_template = {
				name = "powersword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "powersword_1h",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
	end)

	it("keeps 1h force swords targeted at elite or harder targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 3,
			weapon_template = {
				name = "forcesword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "forcesword_1h",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals(light_attack, chosen)
	end)

	it("requires middle charge before arming 2h force sword specials", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 5,
			peril_pct = 0.3,
			weapon_template = {
				name = "forcesword_2h_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.7,
				family = "forcesword_2h",
			},
			inventory_slot_component = {
				special_active = false,
				num_special_charges = 9,
			},
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals(light_attack, chosen)
	end)

	it("prepends 2h force sword specials for middle-charge unarmored hordes", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 5,
			peril_pct = 0.3,
			weapon_template = {
				name = "forcesword_2h_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.7,
				family = "forcesword_2h",
			},
			inventory_slot_component = {
				special_active = false,
				num_special_charges = 10,
			},
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
		assert.equals("light_attack", chosen.action_inputs[3].action_input)
	end)

	it("does not prepend 2h force sword specials into armored or high-value targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 5,
			peril_pct = 0.3,
			weapon_template = {
				name = "forcesword_2h_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.7,
				family = "forcesword_2h",
			},
			inventory_slot_component = {
				special_active = false,
				num_special_charges = 10,
			},
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { name = "renegade_executor", tags = { elite = true } }, scratchpad)

		assert.equals(heavy_attack, chosen)
	end)

	it("widens thunder hammer special use to armored elites", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "thunderhammer_2h_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.45,
				family = "thunderhammer",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
	end)

	it("skips the special-action prelude when the powered state is already active", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "powersword_2h_p1_m2",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.65,
			},
			inventory_slot_component = { special_active = true },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals(heavy_attack, chosen)
	end)

	it("resolves chainaxe toggle specials during enter and prepends them for elite targets", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				elseif method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}
		local slot_component = { special_active = false }

		_G.ScriptUnit = {
			has_extension = function(_, system_name)
				assert.equals("unit_data_system", system_name)
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return slot_component
						end
						return nil
					end,
				}
			end,
		}
		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "chainaxe_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
				actions = {
					action_toggle_special = {
						start_input = "special_action",
						kind = "toggle_special",
						activation_time = 0.3,
						allowed_chain_actions = {
							start_attack = {
								chain_time = 0.4,
							},
						},
					},
				},
			},
		}

		enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

		assert.same({
			action_input = "special_action",
			action_name = "action_toggle_special",
			chain_time = 0.4,
			family = "chain",
		}, scratchpad.special_action_meta)

		scratchpad.weapon_extension = {
			action_input_is_currently_valid = function(_self, _id, action_input)
				return action_input == "special_action"
			end,
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
		assert.equals(0.4, chosen.action_inputs[2].timing)
		assert.equals("heavy_attack", chosen.action_inputs[3].action_input)
	end)

	it("prepends chain specials for super-armor targets and keeps the heavy opener", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return SUPER_ARMOR
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "chainsword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "chain",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", {}, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("heavy_attack", chosen.action_inputs[3].action_input)
	end)

	it("logs supported special families missing action metadata once", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local debug_logs = {}
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function(_, system_name)
				assert.equals("unit_data_system", system_name)
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return { special_active = false }
						end
						return nil
					end,
				}
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					fixed_t = fixed_t,
					message = message,
				}
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local weapon_template = {
			name = "chainaxe_p1_m1",
			actions = {
				action_toggle_special = {
					start_input = "special_action",
					kind = "activate_special",
				},
			},
		}
		local first_scratchpad = { weapon_template = weapon_template }
		local second_scratchpad = { weapon_template = weapon_template }

		enter_handler(function() end, nil, "bot_unit", nil, nil, first_scratchpad, nil, 13)
		enter_handler(function() end, nil, "bot_unit", nil, nil, second_scratchpad, nil, 13)

		assert.is_nil(first_scratchpad.special_action_meta)
		assert.is_nil(second_scratchpad.special_action_meta)
		assert.equals(1, #debug_logs)
		assert.equals("special_action_meta_missing:chainaxe_p1_m1", debug_logs[1].key)
		assert.matches(
			"supported special family missing action metadata %(weapon=chainaxe_p1_m1, family=chain%)",
			debug_logs[1].message
		)
	end)

	it("resolves 2h chainsword specials through action_start_special", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function()
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return { special_active = false }
						end
						return nil
					end,
				}
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local scratchpad = {
			weapon_template = {
				name = "chainsword_2h_p1_m1",
				actions = {
					action_start_special = {
						start_input = "special_action",
						kind = "toggle_special",
						activation_time = 0.3,
						allowed_chain_actions = {
							start_attack = {
								chain_time = 0.65,
							},
						},
					},
				},
			},
		}

		enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

		assert.same({
			action_input = "special_action",
			action_name = "action_start_special",
			chain_time = 0.65,
			family = "chain",
		}, scratchpad.special_action_meta)
	end)

	it("does not prepend chain specials for specialist-only targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "chainsword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "chain",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { special = true } }, scratchpad)

		assert.equals(heavy_attack, chosen)
	end)

	it("does not prepend specials when inventory_slot_component is missing", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "chainsword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "chain",
			},
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals(heavy_attack, chosen)
	end)

	it("resolves latrine shovel fold specials during enter", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function()
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return { special_active = false }
						end
						return nil
					end,
				}
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local scratchpad = {
			weapon_template = {
				name = "ogryn_club_p1_m2",
				actions = {
					action_special_activate = {
						start_input = "special_action",
						kind = "toggle_special",
						activation_time = 0.3,
						allowed_chain_actions = {
							start_attack = {
								chain_time = 0.62,
							},
						},
					},
				},
			},
		}

		enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

		assert.same({
			action_input = "special_action",
			action_name = "action_special_activate",
			chain_time = 0.62,
			family = "ogryn_latrine_shovel",
		}, scratchpad.special_action_meta)
	end)

	it("prepends latrine shovel specials for high-health targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "ogryn_club_p1_m3",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.62,
				family = "ogryn_latrine_shovel",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { name = "cultist_mutant", tags = { special = true } }, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
		assert.equals("light_attack", chosen.action_inputs[3].action_input)
	end)

	it(
		"uses special plus heavy for armored high-health latrine shovel targets even when generic scoring ties",
		function()
			local MeleeAttackChoice = load_module()
			local choose_attack_handler
			local stub_mod = {
				hook = function(_, _, method_name, handler)
					if method_name == "_choose_attack" then
						choose_attack_handler = handler
					end
				end,
			}

			_G.Armor = {
				armor_type = function()
					return ARMORED
				end,
			}

			MeleeAttackChoice.init({
				mod = stub_mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 13
				end,
				ARMOR_TYPE_ARMORED = ARMORED,
				ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
			})

			MeleeAttackChoice.install_melee_hooks({})

			local light_attack = attack_meta({ arc = 0, penetrating = true })
			local heavy_attack = attack_meta({
				arc = 2,
				penetrating = true,
				action_inputs = {
					{ action_input = "start_attack", timing = 0 },
					{ action_input = "heavy_attack", timing = 0 },
				},
			})
			local scratchpad = {
				num_enemies_in_proximity = 1,
				weapon_template = {
					name = "ogryn_club_p1_m2",
					attack_meta_data = {
						light_attack = light_attack,
						heavy_attack = heavy_attack,
					},
				},
				special_action_meta = {
					action_input = "special_action",
					chain_time = 0.62,
					family = "ogryn_latrine_shovel",
				},
				inventory_slot_component = { special_active = false },
				weapon_extension = {
					action_input_is_currently_valid = function()
						return true
					end,
				},
			}

			local chosen = choose_attack_handler(function()
				error("original _choose_attack should not run")
			end, nil, "target_unit", { name = "renegade_executor", tags = { elite = true } }, scratchpad)

			assert.equals("special_action", chosen.action_inputs[1].action_input)
			assert.equals("start_attack", chosen.action_inputs[2].action_input)
			assert.equals("heavy_attack", chosen.action_inputs[3].action_input)
		end
	)

	it("does not prepend latrine shovel specials for low-health elite unarmored targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "ogryn_club_p1_m3",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.62,
				family = "ogryn_latrine_shovel",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { name = "cultist_gunner", tags = { elite = true } }, scratchpad)

		assert.equals(light_attack, chosen)
	end)

	it("does not prepend latrine shovel specials for specialist-only targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
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
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "ogryn_club_p1_m3",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.62,
				family = "ogryn_latrine_shovel",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { special = true } }, scratchpad)

		assert.equals(light_attack, chosen)
	end)

	it("resolves Ogryn club uppercut specials during enter", function()
		local MeleeAttackChoice = load_module()
		local enter_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "enter" then
					enter_handler = handler
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function()
				return {
					read_component = function(_, component_name)
						if component_name == "inventory" then
							return { wielded_slot = "slot_primary" }
						end
						if component_name == "slot_primary" then
							return { special_active = false }
						end
						return nil
					end,
				}
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local scratchpad = {
			weapon_template = {
				name = "ogryn_club_p1_m1",
				actions = {
					action_special_uppercut = {
						start_input = "special_action",
						kind = "sweep",
						allowed_chain_actions = {
							start_attack = {
								chain_time = 0.45,
							},
						},
					},
				},
			},
		}

		enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

		assert.same({
			action_input = "special_action",
			action_name = "action_special_uppercut",
			chain_time = 0.45,
			family = "ogryn_club_uppercut",
		}, scratchpad.special_action_meta)
	end)

	it("prepends Ogryn club uppercut specials for armored targets", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "ogryn_club_p1_m1",
				attack_meta_data = {
					light_attack = attack_meta({ arc = 0, penetrating = false }),
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.45,
				family = "ogryn_club_uppercut",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return true
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { name = "renegade_executor", tags = { elite = true } }, scratchpad)

		assert.equals("special_action", chosen.action_inputs[1].action_input)
		assert.equals("start_attack", chosen.action_inputs[2].action_input)
		assert.equals("heavy_attack", chosen.action_inputs[3].action_input)
	end)

	it("does not prepend specials when special_action is currently invalid", function()
		local MeleeAttackChoice = load_module()
		local choose_attack_handler
		local stub_mod = {
			hook = function(_, _, method_name, handler)
				if method_name == "_choose_attack" then
					choose_attack_handler = handler
				end
			end,
		}

		_G.Armor = {
			armor_type = function()
				return ARMORED
			end,
		}

		MeleeAttackChoice.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 13
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
		})

		MeleeAttackChoice.install_melee_hooks({})

		local light_attack = attack_meta({ arc = 0, penetrating = false })
		local heavy_attack = attack_meta({
			arc = 2,
			penetrating = true,
			action_inputs = {
				{ action_input = "start_attack", timing = 0 },
				{ action_input = "heavy_attack", timing = 0 },
			},
		})
		local scratchpad = {
			num_enemies_in_proximity = 1,
			weapon_template = {
				name = "chainsword_p1_m1",
				attack_meta_data = {
					light_attack = light_attack,
					heavy_attack = heavy_attack,
				},
			},
			special_action_meta = {
				action_input = "special_action",
				chain_time = 0.3,
				family = "chain",
			},
			inventory_slot_component = { special_active = false },
			weapon_extension = {
				action_input_is_currently_valid = function()
					return false
				end,
			},
		}

		local chosen = choose_attack_handler(function()
			error("original _choose_attack should not run")
		end, nil, "target_unit", { tags = { elite = true } }, scratchpad)

		assert.equals(heavy_attack, chosen)
	end)

	-- #81: settings wiring
	it("disables horde light bias when melee_horde_light_bias=0", function()
		local MeleeAttackChoice = load_module()
		MeleeAttackChoice.init({
			mod = nil,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			melee_horde_light_bias = function()
				return 0
			end,
		})

		-- With bias=0, light should NOT get the extra bias in unarmored hordes.
		-- Both light (arc=0) and heavy (arc=2,penetrating) compete on base utility only.
		local weapon_meta_data = {
			light_attack = attack_meta({ arc = 0, penetrating = false }),
			heavy_attack = attack_meta({ arc = 2, penetrating = true }),
		}

		-- With 4 unarmored enemies and bias=0, the heavy's wide arc + penetrating
		-- should beat the light since the light bias is gone.
		local chosen = MeleeAttackChoice.choose_attack_meta_data(weapon_meta_data, 1, 4, ARMORED)
		assert.equals(weapon_meta_data.heavy_attack, chosen)
	end)
end)
