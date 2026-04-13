local MeleeMetaData = dofile("scripts/mods/BetterBots/melee_meta_data.lua")

local ARMORED = 2

local function noop_debug_log() end

local function make_weapon_template(keywords, light_dp, heavy_dp, opts)
	opts = opts or {}
	local actions = {
		action_melee_start_left = {
			start_input = "start_attack",
			allowed_chain_actions = {},
		},
	}
	if light_dp then
		actions.action_melee_start_left.allowed_chain_actions.light_attack = {
			action_name = "action_left_light",
			chain_time = opts.light_chain_time,
		}
		actions.action_left_light = { damage_profile = light_dp }
	end
	if heavy_dp then
		actions.action_melee_start_left.allowed_chain_actions.heavy_attack = {
			action_name = "action_left_heavy",
			chain_time = opts.heavy_chain_time,
		}
		actions.action_left_heavy = { damage_profile = heavy_dp }
	end
	return {
		keywords = keywords,
		actions = actions,
	}
end

local function make_damage_profile(cleave_max, armored_max)
	return {
		cleave_distribution = {
			attack = { cleave_max * 0.5, cleave_max },
		},
		armor_damage_modifier = {
			attack = {
				[ARMORED] = { armored_max * 0.5, armored_max },
			},
		},
	}
end

describe("melee_meta_data", function()
	local enabled

	before_each(function()
		enabled = true
		MeleeMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
			debug_enabled = function()
				return false
			end,
			ARMOR_TYPE_ARMORED = ARMORED,
			is_enabled = function()
				return enabled
			end,
		})
	end)

	describe("classify_arc", function()
		it("returns 0 for no cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(0.001, 0)))
		end)

		it("returns 0 for single cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(2, 0)))
		end)

		it("returns 1 for light to medium cleave", function()
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(4, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(6, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(9, 0)))
		end)

		it("returns 2 for large and big cleave", function()
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(10.5, 0)))
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(12.5, 0)))
		end)

		it("returns 0 for nil damage profile", function()
			assert.equals(0, MeleeMetaData._classify_arc(nil))
		end)

		it("returns 0 for missing cleave_distribution", function()
			assert.equals(0, MeleeMetaData._classify_arc({}))
		end)

		it("handles scalar cleave attack value", function()
			local dp = { cleave_distribution = { attack = 5 } }
			assert.equals(1, MeleeMetaData._classify_arc(dp))
		end)

		it("handles scalar cleave attack value below threshold", function()
			local dp = { cleave_distribution = { attack = 1.5 } }
			assert.equals(0, MeleeMetaData._classify_arc(dp))
		end)

		it("handles scalar cleave attack value above arc 2 threshold", function()
			local dp = { cleave_distribution = { attack = 12 } }
			assert.equals(2, MeleeMetaData._classify_arc(dp))
		end)
	end)

	describe("classify_penetrating", function()
		it("returns false for low armor modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.426), ARMORED))
		end)

		it("returns true for high armor modifier", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.675), ARMORED))
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.33), ARMORED))
		end)

		it("returns true at exact threshold", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.5), ARMORED))
		end)

		it("returns false for nil damage profile", function()
			assert.is_false(MeleeMetaData._classify_penetrating(nil, ARMORED))
		end)

		it("returns false for missing armor_damage_modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating({}, ARMORED))
		end)

		it("returns false for nil armored_type", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.0), nil))
		end)

		it("prefers per-target armor modifier over top-level", function()
			local dp = {
				armor_damage_modifier = {
					attack = { [ARMORED] = { 0.174, 0.426 } },
				},
				targets = {
					{ armor_damage_modifier = {
						attack = { [ARMORED] = { 0.48, 1.02 } },
					} },
				},
			}
			assert.is_true(MeleeMetaData._classify_penetrating(dp, ARMORED))
		end)

		it("falls back to top-level when targets has no armor modifier", function()
			local dp = {
				armor_damage_modifier = {
					attack = { [ARMORED] = { 0.4, 0.8 } },
				},
				targets = {
					{ boost_curve_multiplier_finesse = 1.5 },
				},
			}
			assert.is_true(MeleeMetaData._classify_penetrating(dp, ARMORED))
		end)

		it("falls back to top-level when no targets table", function()
			local dp = make_damage_profile(0, 0.675)
			assert.is_true(MeleeMetaData._classify_penetrating(dp, ARMORED))
		end)

		it("handles scalar armor modifier value", function()
			local dp = {
				armor_damage_modifier = {
					attack = { [ARMORED] = 2 },
				},
			}
			assert.is_true(MeleeMetaData._classify_penetrating(dp, ARMORED))
		end)

		it("handles scalar armor modifier value below threshold", function()
			local dp = {
				armor_damage_modifier = {
					attack = { [ARMORED] = 0.3 },
				},
			}
			assert.is_false(MeleeMetaData._classify_penetrating(dp, ARMORED))
		end)
	end)

	describe("inject", function()
		it("does not inject when melee improvements are disabled", function()
			enabled = false
			local templates = {
				sword = make_weapon_template({ "melee", "combat_sword" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)

			assert.is_nil(templates.sword.attack_meta_data)
		end)

		it("reverts injected attack_meta_data when melee improvements are disabled at runtime", function()
			local templates = {
				sword = make_weapon_template({ "melee", "combat_sword" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)
			assert.is_table(templates.sword.attack_meta_data)

			enabled = false
			MeleeMetaData.sync_all()

			assert.is_nil(templates.sword.attack_meta_data)
		end)

		it("preserves pre-existing attack_meta_data when disabling melee improvements", function()
			local existing = { custom = { arc = 99 } }
			local template = make_weapon_template({ "melee", "combat_sword" }, make_damage_profile(6, 0.3), nil)
			template.attack_meta_data = existing
			local templates = { sword = template }

			MeleeMetaData.inject(templates)
			enabled = false
			MeleeMetaData.sync_all()

			assert.equals(existing, templates.sword.attack_meta_data)
		end)

		it("injects attack_meta_data for melee weapon with light and heavy", function()
			local light_dp = make_damage_profile(6, 0.3)
			local heavy_dp = make_damage_profile(0.001, 1.0)
			local templates = {
				sword = make_weapon_template({ "melee", "combat_sword" }, light_dp, heavy_dp),
			}

			MeleeMetaData.inject(templates)

			local meta = templates.sword.attack_meta_data
			assert.is_table(meta)
			assert.is_table(meta.light_attack)
			assert.equals(1, meta.light_attack.arc)
			assert.is_false(meta.light_attack.penetrating)
			assert.equals(2.5, meta.light_attack.max_range)
			assert.is_table(meta.heavy_attack)
			assert.equals(0, meta.heavy_attack.arc)
			assert.is_true(meta.heavy_attack.penetrating)
		end)

		it("generates correct action_inputs sequences", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), make_damage_profile(0.001, 1.0)),
			}

			MeleeMetaData.inject(templates)

			local light_inputs = templates.sword.attack_meta_data.light_attack.action_inputs
			assert.equals(2, #light_inputs)
			assert.equals("start_attack", light_inputs[1].action_input)
			assert.equals(0, light_inputs[1].timing)
			assert.equals("light_attack", light_inputs[2].action_input)

			local heavy_inputs = templates.sword.attack_meta_data.heavy_attack.action_inputs
			assert.equals("start_attack", heavy_inputs[1].action_input)
			assert.equals("heavy_attack", heavy_inputs[2].action_input)
		end)

		it("handles weapon with only light attack", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)

			assert.is_table(templates.sword.attack_meta_data)
			assert.is_table(templates.sword.attack_meta_data.light_attack)
			assert.is_nil(templates.sword.attack_meta_data.heavy_attack)
		end)

		it("skips non-melee weapons", function()
			local templates = {
				gun = make_weapon_template({ "ranged", "lasgun" }, make_damage_profile(0, 0), nil),
			}

			MeleeMetaData.inject(templates)

			assert.is_nil(templates.gun.attack_meta_data)
		end)

		it("does not overwrite existing attack_meta_data", function()
			local existing = { custom = { arc = 99 } }
			local template = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil)
			template.attack_meta_data = existing
			local templates = { sword = template }

			MeleeMetaData.inject(templates)

			assert.equals(existing, templates.sword.attack_meta_data)
		end)

		it("is idempotent for the same table", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)
			local first_meta = templates.sword.attack_meta_data

			MeleeMetaData.inject(templates)
			assert.equals(first_meta, templates.sword.attack_meta_data)
		end)

		it("handles weapon with no start_attack action", function()
			local templates = {
				broken = {
					keywords = { "melee" },
					actions = {
						some_action = { start_input = "other_input" },
					},
				},
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)

		it("handles weapon with no allowed_chain_actions", function()
			local templates = {
				broken = {
					keywords = { "melee" },
					actions = {
						action_start = { start_input = "start_attack" },
					},
				},
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)

		it("skips non-table entries in WeaponTemplates", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
				_version = 42,
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_table(templates.sword.attack_meta_data)
		end)

		it("uses chain_time as timing for heavy_attack input", function()
			local templates = {
				sword = make_weapon_template(
					{ "melee" },
					make_damage_profile(6, 0.3),
					make_damage_profile(0.001, 1.0),
					{ heavy_chain_time = 0.75 }
				),
			}

			MeleeMetaData.inject(templates)

			local heavy_inputs = templates.sword.attack_meta_data.heavy_attack.action_inputs
			assert.equals(0.75, heavy_inputs[2].timing)
		end)

		it("uses chain_time as timing for light_attack input", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil, { light_chain_time = 0.1 }),
			}

			MeleeMetaData.inject(templates)

			local light_inputs = templates.sword.attack_meta_data.light_attack.action_inputs
			assert.equals(0.1, light_inputs[2].timing)
		end)

		it("defaults timing to 0 when chain_time is nil", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)

			local light_inputs = templates.sword.attack_meta_data.light_attack.action_inputs
			assert.equals(0, light_inputs[2].timing)
		end)

		it("skips start actions marked invalid_start_action_for_stat_calculation", function()
			local special_dp = { cleave_distribution = { attack = { 999, 999 } } }
			local normal_dp = make_damage_profile(6, 0.3)
			local templates = {
				force_sword = {
					keywords = { "melee" },
					actions = {
						action_melee_start_special = {
							start_input = "start_attack",
							invalid_start_action_for_stat_calculation = true,
							allowed_chain_actions = {
								light_attack = { action_name = "action_special_light" },
							},
						},
						action_special_light = { damage_profile = special_dp },
						action_melee_start_left = {
							start_input = "start_attack",
							allowed_chain_actions = {
								light_attack = { action_name = "action_left_light" },
							},
						},
						action_left_light = { damage_profile = normal_dp },
					},
				},
			}

			MeleeMetaData.inject(templates)

			local meta = templates.force_sword.attack_meta_data
			assert.is_table(meta)
			assert.equals(1, meta.light_attack.arc)
		end)
	end)
end)
