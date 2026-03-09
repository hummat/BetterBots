local RangedMetaData = dofile("scripts/mods/BetterBots/ranged_meta_data.lua")

local function noop_debug_log() end

local function make_ranged_template(opts)
	opts = opts or {}
	return {
		keywords = opts.keywords or { "ranged" },
		actions = opts.actions or {},
		action_inputs = opts.action_inputs or {},
	}
end

describe("ranged_meta_data", function()
	before_each(function()
		RangedMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
		})
	end)

	describe("resolve_vanilla_fallback", function()
		it("returns action start_inputs when actions exist", function()
			local t = make_ranged_template({
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
					action_zoom = { start_input = "zoom" },
					action_shoot_zoomed = { start_input = "zoom_shoot" },
				},
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot_pressed", fb.fire_action_input)
			assert.equals("zoom", fb.aim_action_input)
			assert.equals("zoom_shoot", fb.aim_fire_action_input)
		end)

		it("falls back to hardcoded strings when actions missing", function()
			local t = make_ranged_template({ actions = {} })
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
			assert.equals("zoom", fb.aim_action_input)
			assert.equals("zoom_shoot", fb.aim_fire_action_input)
		end)

		it("falls back when action exists but start_input is nil", function()
			local t = make_ranged_template({
				actions = { action_shoot = { kind = "shoot_hit_scan" } },
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
		end)
	end)

	describe("needs_injection", function()
		it("returns false when fire input is valid", function()
			local t = make_ranged_template({
				actions = { action_shoot = { start_input = "shoot_pressed" } },
				action_inputs = { shoot_pressed = { input_sequence = {} } },
			})
			assert.is_false(RangedMetaData._needs_injection(t))
		end)

		it("returns true when fire input is invalid", function()
			local t = make_ranged_template({
				actions = { action_shoot = {} },
				action_inputs = { shoot_charge = { input_sequence = {} } },
			})
			assert.is_true(RangedMetaData._needs_injection(t))
		end)

		it("returns true when action_shoot missing and no shoot input", function()
			local t = make_ranged_template({
				actions = { rapid_left = { start_input = "shoot_pressed" } },
				action_inputs = { shoot_pressed = { input_sequence = {} } },
			})
			assert.is_true(RangedMetaData._needs_injection(t))
		end)
	end)

	describe("find_fire_input", function()
		it("finds single action_one_pressed input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					reload = { input_sequence = {
						{ input = "weapon_reload_pressed", value = true },
					} },
				},
				actions = {
					action_shoot_hip = { start_input = "shoot_pressed" },
				},
			})
			local input, action = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_pressed", input)
			assert.equals("action_shoot_hip", action)
		end)

		it("disambiguates multiple candidates preferring shoot_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					shoot_charge = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_shoot_hip = { start_input = "shoot_pressed" },
					action_charge_direct = { start_input = "shoot_charge" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_pressed", input)
		end)

		it("disambiguates preferring shoot_charge when no shoot_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_charge = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					shoot_braced = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_charge_direct = { start_input = "shoot_charge" },
				},
			})
			local input, action = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_charge", input)
			assert.equals("action_charge_direct", action)
		end)

		it("filters out hold_input entries", function()
			local t = make_ranged_template({
				action_inputs = {
					trigger_explosion = { input_sequence = {
						{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
					} },
				},
				actions = {
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)

		it("filters chain-only inputs without matching start_input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_braced = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_shoot_charged = { kind = "shoot_hit_scan" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)

		it("returns nil when no action_inputs", function()
			local t = make_ranged_template({ actions = {} })
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)
	end)

	describe("find_aim_input", function()
		it("finds action_two_hold input", function()
			local t = make_ranged_template({
				action_inputs = {
					zoom = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
				},
				actions = {
					action_zoom = { start_input = "zoom" },
				},
			})
			local input, action = RangedMetaData._find_aim_input(t)
			assert.equals("zoom", input)
			assert.equals("action_zoom", action)
		end)

		it("returns nil when no action_two_hold input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {},
			})
			local input, _ = RangedMetaData._find_aim_input(t)
			assert.is_nil(input)
		end)

		it("ignores action_two_hold release (value=false)", function()
			local t = make_ranged_template({
				action_inputs = {
					brace_release = { input_sequence = {
						{ input = "action_two_hold", value = false },
					} },
				},
				actions = {
					action_unbrace = { start_input = "brace_release" },
				},
			})
			local input, _ = RangedMetaData._find_aim_input(t)
			assert.is_nil(input)
		end)
	end)

	describe("find_aim_fire_input", function()
		it("finds input with hold_input and action_one_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					trigger_explosion = { input_sequence = {
						{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
					} },
				},
				actions = {
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			local input, action = RangedMetaData._find_aim_fire_input(t)
			assert.equals("trigger_explosion", input)
			assert.equals("action_explode", action)
		end)

		it("returns nil when no hold_input entries", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {},
			})
			local input, _ = RangedMetaData._find_aim_fire_input(t)
			assert.is_nil(input)
		end)
	end)

	describe("inject", function()
		it("injects attack_meta_data for weapon with broken fire input", function()
			local templates = {
				forcestaff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						wield = { input_sequence = {
							{ input = "weapon_extra_pressed", value = true },
						} },
					},
					actions = {
						rapid_left = { start_input = "shoot_pressed", kind = "spawn_projectile" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.forcestaff.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_pressed", meta.fire_action_input)
			assert.equals("rapid_left", meta.fire_action_name)
		end)

		it("sets fire_action_input but keeps fire_action_name default when action_shoot exists", function()
			local templates = {
				plasma = make_ranged_template({
					action_inputs = {
						shoot_charge = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = {
						action_shoot = { kind = "shoot_hit_scan" },
						action_charge_direct = { start_input = "shoot_charge" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.plasma.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_charge", meta.fire_action_input)
			assert.is_nil(meta.fire_action_name)
		end)

		it("does not derive aim_action_input but mirrors fire input as aim_fire_action_input", function()
			local templates = {
				exotic = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						charge = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
					},
					actions = {
						rapid_left = { start_input = "shoot_pressed" },
						action_charge = { start_input = "charge" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.exotic.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_pressed", meta.fire_action_input)
			assert.is_nil(meta.aim_action_input)
			assert.equals("shoot_pressed", meta.aim_fire_action_input)
		end)

		it("mirrors fire input as aim_fire for plasma pattern", function()
			local templates = {
				plasma = make_ranged_template({
					action_inputs = {
						shoot_charge = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = {
						action_shoot = { kind = "shoot_hit_scan" },
						action_charge_direct = { start_input = "shoot_charge" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.plasma.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_charge", meta.fire_action_input)
			assert.equals("shoot_charge", meta.aim_fire_action_input)
			assert.is_nil(meta.aim_action_input)
		end)

		it("skips weapons where vanilla fallback is valid", function()
			local templates = {
				lasgun = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = { input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						} },
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.lasgun.attack_meta_data)
		end)

		it("skips non-ranged weapons", function()
			local templates = {
				sword = {
					keywords = { "melee", "combat_sword" },
					actions = {},
					action_inputs = {},
				},
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.sword.attack_meta_data)
		end)

		it("does not overwrite existing attack_meta_data", function()
			local existing = { fire_action_input = "custom" }
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = { rapid_left = { start_input = "shoot_pressed" } },
			})
			template.attack_meta_data = existing
			local templates = { staff = template }

			RangedMetaData.inject(templates)

			assert.equals(existing, templates.staff.attack_meta_data)
		end)

		it("is idempotent for the same table", function()
			local templates = {
				staff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = { rapid_left = { start_input = "shoot_pressed" } },
				}),
			}

			RangedMetaData.inject(templates)
			local first_meta = templates.staff.attack_meta_data

			RangedMetaData.inject(templates)
			assert.equals(first_meta, templates.staff.attack_meta_data)
		end)

		it("skips non-table entries in WeaponTemplates", function()
			local templates = {
				staff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = { rapid_left = { start_input = "shoot_pressed" } },
				}),
				_version = 42,
			}

			assert.has_no.errors(function()
				RangedMetaData.inject(templates)
			end)
			assert.is_table(templates.staff.attack_meta_data)
		end)

		it("handles weapon with no derivable fire input", function()
			local templates = {
				broken = make_ranged_template({
					action_inputs = {
						reload = { input_sequence = {
							{ input = "weapon_reload_pressed", value = true },
						} },
					},
					actions = {},
				}),
			}

			assert.has_no.errors(function()
				RangedMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)
	end)
end)
