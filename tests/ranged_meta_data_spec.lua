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
	local enabled

	before_each(function()
		enabled = true
		RangedMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
			debug_enabled = function()
				return false
			end,
			is_enabled = function()
				return enabled
			end,
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

		it("falls back to hardcoded fire input and nil aim inputs when actions are missing", function()
			local t = make_ranged_template({ actions = {} })
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
			assert.is_nil(fb.aim_action_input)
			assert.is_nil(fb.aim_fire_action_input)
		end)

		it("falls back when action exists but start_input is nil", function()
			local t = make_ranged_template({
				actions = { action_shoot = { kind = "shoot_hit_scan" } },
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
			assert.is_nil(fb.aim_action_input)
			assert.is_nil(fb.aim_fire_action_input)
		end)

		it("derives brace inputs for braced ranged weapons", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = { { input = "action_one_pressed", value = true } } },
					brace_pressed = { input_sequence = { { input = "action_two_hold", value = true } } },
					brace_release = { input_sequence = { { input = "action_two_hold", value = false } } },
					shoot_braced = { input_sequence = { { input = "action_one_hold", value = true } } },
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
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
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)

			assert.equals("shoot_pressed", fb.fire_action_input)
			assert.equals("brace_pressed", fb.aim_action_input)
			assert.equals("shoot_braced", fb.aim_fire_action_input)
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

	describe("close_range_ranged_policy", function()
		it("treats flamer as the widest close-range hipfire family", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "flamer_p1_m1",
				keywords = { "ranged", "flamer", "p1" },
			})

			assert.equals("flamer", policy.family)
			assert.equals(144, policy.hold_ranged_target_distance_sq)
			assert.equals(144, policy.hipfire_distance_sq)
		end)

		it("treats autopistol-family weapons as close-range hipfire ranged weapons", function()
			local policy = RangedMetaData.close_range_ranged_policy(make_ranged_template({
				keywords = { "ranged", "autopistol", "p1" },
			}))

			assert.equals("autopistol", policy.family)
			assert.equals(100, policy.hold_ranged_target_distance_sq)
			assert.equals(100, policy.hipfire_distance_sq)
		end)

		it("covers dual autopistols through the same family policy", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "dual_autopistols_p1_m1",
				keywords = { "ranged", "autopistol", "p1" },
			})

			assert.equals("autopistol", policy.family)
			assert.equals(100, policy.hold_ranged_target_distance_sq)
			assert.equals(100, policy.hipfire_distance_sq)
		end)

		it("keeps ripperguns ranged at close range without forcing hipfire", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "ogryn_rippergun_p1_m1",
				keywords = { "ranged", "rippergun", "p1" },
			})

			assert.equals("rippergun", policy.family)
			assert.equals(81, policy.hold_ranged_target_distance_sq)
			assert.is_nil(policy.hipfire_distance_sq)
		end)

		it("keeps Purgatus ranged at a wider close-range window than the electrokinetic staff", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "forcestaff_p2_m1",
				keywords = { "ranged", "staff", "p2" },
			})

			assert.equals("forcestaff_p2_m1", policy.family)
			assert.equals(144, policy.hold_ranged_target_distance_sq)
			assert.is_nil(policy.hipfire_distance_sq)
		end)

		it("keeps forcestaff_p3_m1 ranged at close range without forcing hipfire", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "forcestaff_p3_m1",
				keywords = { "ranged", "staff", "p3" },
			})

			assert.equals("forcestaff_p3_m1", policy.family)
			assert.equals(64, policy.hold_ranged_target_distance_sq)
			assert.is_nil(policy.hipfire_distance_sq)
		end)

		it("keeps shotgun family resolution intact after the new keyword branches", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "shotgun_p1_m1",
				keywords = { "ranged", "shotgun", "p1" },
			})

			assert.equals("shotgun", policy.family)
			assert.equals(64, policy.hold_ranged_target_distance_sq)
			assert.equals(64, policy.hipfire_distance_sq)
		end)

		it("keeps heavy stubbers between shotgun and flamer in the hipfire window", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "ogryn_heavystubber_p1_m1",
				keywords = { "ranged", "heavystubber", "p1" },
			})

			assert.equals("heavystubber", policy.family)
			assert.equals(121, policy.hold_ranged_target_distance_sq)
			assert.equals(121, policy.hipfire_distance_sq)
		end)

		it("returns nil for weapons outside the explicit close-range family set", function()
			local policy = RangedMetaData.close_range_ranged_policy({
				name = "lasgun_p1_m1",
				keywords = { "ranged", "lasgun", "p1" },
			})

			assert.is_nil(policy)
		end)
	end)

	describe("anti_armor_ranged_policy", function()
		it("covers ranged families with local anti-armor evidence", function()
			local cases = {
				{
					family = "plasmagun",
					template = { name = "plasmagun_p1_m1", keywords = { "ranged", "plasmagun", "p1" } },
					min_distance_sq = 100,
				},
				{
					family = "bolter",
					template = { name = "bolter_p1_m2", keywords = { "ranged", "bolter", "p1" } },
					min_distance_sq = 144,
				},
				{
					family = "boltpistol",
					template = { name = "boltpistol_p1_m1", keywords = { "ranged", "boltpistol", "p1" } },
					min_distance_sq = 100,
				},
				{
					family = "lasgun_p2",
					template = { name = "lasgun_p2_m1", keywords = { "ranged", "lasgun", "p2" } },
					min_distance_sq = 144,
				},
				{
					family = "stubrevolver",
					template = { name = "stubrevolver_p1_m2", keywords = { "ranged", "stub_pistol", "p1" } },
					min_distance_sq = 144,
				},
				{
					family = "heavystubber",
					template = {
						name = "ogryn_heavystubber_p2_m2",
						keywords = { "ranged", "heavystubber", "p2" },
					},
					min_distance_sq = 144,
				},
			}

			for i = 1, #cases do
				local case = cases[i]
				local policy = RangedMetaData.anti_armor_ranged_policy(case.template)

				assert.equals(case.family, policy.family)
				assert.equals(case.min_distance_sq, policy.min_target_distance_sq)
			end
		end)

		it("does not treat generic weakspot-capable guns as anti-armor ranged families", function()
			local excluded = {
				{ name = "lasgun_p1_m1", keywords = { "ranged", "lasgun", "p1" } },
				{ name = "lasgun_p3_m1", keywords = { "ranged", "lasgun", "p3" } },
				{ name = "autogun_p1_m1", keywords = { "ranged", "autogun", "p1" } },
				{ name = "autopistol_p1_m1", keywords = { "ranged", "autopistol", "p1" } },
				{ name = "shotgun_p1_m1", keywords = { "ranged", "shotgun", "p1" } },
				{ name = "ogryn_rippergun_p1_m1", keywords = { "ranged", "rippergun", "p1" } },
			}

			for i = 1, #excluded do
				assert.is_nil(RangedMetaData.anti_armor_ranged_policy(excluded[i]))
			end
		end)
	end)

	describe("supports_weakspot_aim", function()
		it("covers the original finesse families plus anti-armor ranged families", function()
			local supported = {
				{ name = "lasgun_p1_m1", keywords = { "ranged", "lasgun", "p1" } },
				{ name = "autogun_p1_m1", keywords = { "ranged", "autogun", "p1" } },
				{ name = "bolter_p1_m2", keywords = { "ranged", "bolter", "p1" } },
				{ name = "stubrevolver_p1_m2", keywords = { "ranged", "stub_pistol", "p1" } },
				{ name = "plasmagun_p1_m1", keywords = { "ranged", "plasmagun", "p1" } },
				{ name = "boltpistol_p1_m1", keywords = { "ranged", "boltpistol", "p1" } },
				{ name = "ogryn_heavystubber_p1_m1", keywords = { "ranged", "heavystubber", "p1" } },
				{ name = "ogryn_heavystubber_p2_m2", keywords = { "ranged", "heavystubber", "p2" } },
			}

			for i = 1, #supported do
				assert.is_true(
					RangedMetaData.supports_weakspot_aim(supported[i]),
					supported[i].name .. " should support weakspot aim"
				)
			end
		end)

		it("still excludes close-range spray and blast families", function()
			local excluded = {
				{ name = "autopistol_p1_m1", keywords = { "ranged", "autopistol", "p1" } },
				{ name = "shotgun_p1_m1", keywords = { "ranged", "shotgun", "p1" } },
				{ name = "flamer_p1_m1", keywords = { "ranged", "flamer", "p1" } },
				{ name = "ogryn_rippergun_p1_m1", keywords = { "ranged", "rippergun", "p1" } },
				{ name = "ogryn_thumper_p1_m1", keywords = { "ranged", "grenade_launcher", "p1" } },
			}

			for i = 1, #excluded do
				assert.is_false(
					RangedMetaData.supports_weakspot_aim(excluded[i]),
					excluded[i].name .. " should not support weakspot aim"
				)
			end
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
					trigger_explosion = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
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
					trigger_explosion = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			local input, action = RangedMetaData._find_aim_fire_input(t)
			assert.equals("trigger_explosion", input)
			assert.equals("action_explode", action)
		end)

		it("finds chain-only fire input when action has no start_input", function()
			local t = make_ranged_template({
				action_inputs = {
					trigger_charge_flame = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					action_charge_flame = {
						start_input = "charge_flame",
						allowed_chain_actions = {
							trigger_charge_flame = { action_name = "action_shoot_charged_flame" },
						},
					},
					action_shoot_charged_flame = {
						stop_input = "cancel_flame",
					},
				},
			})
			local input, action = RangedMetaData._find_aim_fire_input(t)
			assert.equals("trigger_charge_flame", input)
			assert.equals("action_shoot_charged_flame", action)
		end)

		it("prefers direct start_input over chain target", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_charged = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					action_shoot_charged = { start_input = "shoot_charged" },
					action_charge = {
						start_input = "charge",
						allowed_chain_actions = {
							shoot_charged = { action_name = "action_shoot_charged" },
						},
					},
				},
			})
			local input, action = RangedMetaData._find_aim_fire_input(t)
			assert.equals("shoot_charged", input)
			assert.equals("action_shoot_charged", action)
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

	describe("find_aim_action_for_fire", function()
		it("finds the hold action that chains into the aimed fire input", function()
			local t = make_ranged_template({
				action_inputs = {
					charge = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					keep_charging = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					charge_release = { input_sequence = {
						{ input = "action_two_hold", value = false },
					} },
					shoot_charged = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					action_keep_charging = {
						start_input = "keep_charging",
						allowed_chain_actions = {},
					},
					action_charge = {
						start_input = "charge",
						stop_input = "charge_release",
						allowed_chain_actions = {
							shoot_charged = { action_name = "action_shoot_charged" },
						},
					},
					action_shoot_charged = { start_input = "shoot_charged" },
				},
			})

			local aim_input, aim_action, unaim_input, unaim_action =
				RangedMetaData._find_aim_action_for_fire(t, "shoot_charged")

			assert.equals("charge", aim_input)
			assert.equals("action_charge", aim_action)
			assert.equals("charge_release", unaim_input)
			assert.is_nil(unaim_action)
		end)
	end)

	describe("inject", function()
		it("does not inject when ranged improvements are disabled", function()
			enabled = false
			local templates = {
				forcestaff = make_ranged_template({
					keywords = { "ranged", "force_staff" },
					actions = {
						action_shoot = {},
						action_charge = { start_input = "charge" },
						action_shoot_charged = { start_input = "trigger_explosion" },
					},
					action_inputs = {
						shoot_charge = { input_sequence = { { input = "action_one_pressed", value = true } } },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.forcestaff.attack_meta_data)
		end)

		it("reverts injected ranged attack_meta_data when setting is disabled at runtime", function()
			local templates = {
				staff = make_ranged_template({
					keywords = { "ranged", "force_staff" },
					actions = {
						action_shoot = {},
						action_shoot_charged = { start_input = "shoot_charge" },
					},
					action_inputs = {
						shoot_charge = { input_sequence = { { input = "action_one_pressed", value = true } } },
					},
				}),
			}

			RangedMetaData.inject(templates)
			assert.is_table(templates.staff.attack_meta_data)

			enabled = false
			RangedMetaData.sync_all()

			assert.is_nil(templates.staff.attack_meta_data)
		end)

		it("replaces malformed attack_meta_data and restores it on disable", function()
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = {
						input_sequence = {
							{ input = "action_one_pressed", value = true },
						},
					},
				},
				actions = {
					rapid_left = { start_input = "shoot_pressed" },
				},
			})
			template.attack_meta_data = "broken"
			local templates = { staff = template }

			RangedMetaData.inject(templates)

			assert.is_table(templates.staff.attack_meta_data)
			assert.equals("shoot_pressed", templates.staff.attack_meta_data.fire_action_input)
			assert.equals("rapid_left", templates.staff.attack_meta_data.fire_action_name)

			enabled = false
			RangedMetaData.sync_all()

			assert.equals("broken", templates.staff.attack_meta_data)
		end)

		it("restores original attack_meta_data fields when disabling ranged improvements", function()
			local template = make_ranged_template({
				keywords = { "ranged", "force_staff" },
				actions = {
					action_shoot = {},
					action_charge = {
						start_input = "charge",
						allowed_chain_actions = {
							trigger_explosion = { action_name = "action_explode" },
						},
					},
					action_explode = {
						stop_input = "charge_release",
					},
				},
				action_inputs = {
					charge = { input_sequence = { { input = "action_two_hold", value = true } } },
					trigger_explosion = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
					charge_release = { input_sequence = { { input = "action_two_hold", value = false } } },
				},
			})
			template.attack_meta_data = {
				fire_action_input = "shoot_pressed",
				aim_fire_action_input = "zoom_shoot",
			}
			local templates = { staff = template }

			RangedMetaData.inject(templates)
			assert.equals("trigger_explosion", template.attack_meta_data.aim_fire_action_input)

			enabled = false
			RangedMetaData.sync_all()

			assert.equals("shoot_pressed", template.attack_meta_data.fire_action_input)
			assert.equals("zoom_shoot", template.attack_meta_data.aim_fire_action_input)
			assert.is_nil(template.attack_meta_data.aim_action_input)
			assert.is_nil(template.attack_meta_data.aim_action_name)
			assert.is_nil(template.attack_meta_data.unaim_action_input)
			assert.is_nil(template.attack_meta_data.unaim_action_name)
		end)

		it("injects attack_meta_data for weapon with broken fire input", function()
			local templates = {
				forcestaff = make_ranged_template({
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
					name = "plasmagun_p1_m1",
					keywords = { "ranged", "plasmagun", "p1" },
					action_inputs = {
						shoot_charge = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
			assert.same({ "j_head", "j_spine" }, meta.aim_at_node)
			assert.is_nil(meta.fire_action_name)
		end)

		it("does not derive aim_action_input but mirrors fire input as aim_fire_action_input", function()
			local templates = {
				exotic = make_ranged_template({
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
						shoot_charge = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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

		it("skips non-allowlisted weapons where vanilla fallback is valid", function()
			local templates = {
				autopistol = make_ranged_template({
					keywords = { "ranged", "autopistol", "p1" },
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = {
							input_sequence = {
								{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
							},
						},
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.autopistol.attack_meta_data)
		end)

		it("injects weakspot aim nodes for allowlisted ranged families", function()
			local templates = {
				lasgun = make_ranged_template({
					keywords = { "ranged", "lasgun", "p1" },
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = {
							input_sequence = {
								{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
							},
						},
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.same({ "j_head", "j_spine" }, templates.lasgun.attack_meta_data.aim_at_node)
		end)

		it("merges weakspot aim nodes into existing attack_meta_data", function()
			local template = make_ranged_template({
				keywords = { "ranged", "autogun", "p2" },
				action_inputs = {
					shoot_pressed = {
						input_sequence = {
							{ input = "action_one_pressed", value = true },
						},
					},
					zoom = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					zoom_shoot = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
					action_zoom = { start_input = "zoom" },
					action_shoot_zoomed = { start_input = "zoom_shoot" },
				},
			})
			template.attack_meta_data = { aim_data = { min_distance = 5 } }

			RangedMetaData.inject({ autogun = template })

			assert.equals(5, template.attack_meta_data.aim_data.min_distance)
			assert.same({ "j_head", "j_spine" }, template.attack_meta_data.aim_at_node)
		end)

		it("preserves existing aim_at_node values", function()
			local template = make_ranged_template({
				keywords = { "ranged", "bolter", "p1" },
				action_inputs = {
					shoot_pressed = {
						input_sequence = {
							{ input = "action_one_pressed", value = true },
						},
					},
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
				},
			})
			template.attack_meta_data = { aim_at_node = "j_neck" }

			RangedMetaData.inject({ bolter = template })

			assert.equals("j_neck", template.attack_meta_data.aim_at_node)
		end)

		it("combines fire-input correction with weakspot aim injection", function()
			local templates = {
				stubrevolver = make_ranged_template({
					keywords = { "ranged", "stub_pistol", "p1" },
					action_inputs = {
						shoot_charge = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
					},
					actions = {
						action_shoot = { kind = "shoot_hit_scan" },
						action_charge_direct = { start_input = "shoot_charge" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.equals("shoot_charge", templates.stubrevolver.attack_meta_data.fire_action_input)
			assert.same({ "j_head", "j_spine" }, templates.stubrevolver.attack_meta_data.aim_at_node)
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

		it("merges corrections into existing attack_meta_data without overwriting", function()
			local existing = { aim_data = { min_distance = 5 } }
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
			assert.equals("shoot_pressed", existing.fire_action_input)
			assert.equals("rapid_left", existing.fire_action_name)
			assert.same({ min_distance = 5 }, existing.aim_data)
		end)

		it("does not overwrite existing fields in attack_meta_data", function()
			local existing = { fire_action_input = "custom_fire" }
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

			assert.equals("custom_fire", existing.fire_action_input)
		end)

		it("is idempotent for the same table", function()
			local templates = {
				staff = make_ranged_template({
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
						reload = {
							input_sequence = {
								{ input = "weapon_reload_pressed", value = true },
							},
						},
					},
					actions = {},
				}),
			}

			assert.has_no.errors(function()
				RangedMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)

		it("overrides aim metadata for charge weapons (#43)", function()
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					charge = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					trigger_explosion = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					rapid_left = { start_input = "shoot_pressed" },
					action_charge = {
						start_input = "charge",
						stop_input = "charge_release",
						allowed_chain_actions = {
							trigger_explosion = { action_name = "action_explode" },
						},
					},
					action_charge_release = { start_input = "charge_release" },
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			-- Simulate vanilla attack_meta_data with primary fire as aim_fire
			template.attack_meta_data = {
				fire_action_input = "shoot_pressed",
				fire_action_name = "rapid_left",
				aim_action_name = "action_charge",
				aim_fire_action_input = "shoot_pressed",
				aim_fire_action_name = "rapid_left",
				unaim_action_name = "action_vent",
			}
			local templates = { forcestaff = template }

			RangedMetaData.inject(templates)

			assert.equals("trigger_explosion", template.attack_meta_data.aim_fire_action_input)
			assert.equals("action_explode", template.attack_meta_data.aim_fire_action_name)
			assert.equals("charge", template.attack_meta_data.aim_action_input)
			assert.equals("action_charge", template.attack_meta_data.aim_action_name)
			assert.equals("charge_release", template.attack_meta_data.unaim_action_input)
			assert.equals("action_charge_release", template.attack_meta_data.unaim_action_name)
			-- Other fields unchanged
			assert.equals("shoot_pressed", template.attack_meta_data.fire_action_input)
			assert.equals("rapid_left", template.attack_meta_data.fire_action_name)
		end)

		it("overrides aim metadata for chain-only charge weapons (#43 p2 flame staff)", function()
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					charge_flame = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					trigger_charge_flame = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					rapid_left = { start_input = "shoot_pressed" },
					action_charge_flame = {
						start_input = "charge_flame",
						stop_input = "charge_flame_release",
						allowed_chain_actions = {
							trigger_charge_flame = { action_name = "action_shoot_charged_flame" },
						},
					},
					action_charge_flame_release = { start_input = "charge_flame_release" },
					action_shoot_charged_flame = {
						stop_input = "cancel_flame",
					},
				},
			})
			template.attack_meta_data = {
				fire_action_input = "shoot_pressed",
				fire_action_name = "rapid_left",
				aim_fire_action_input = "shoot_pressed",
				aim_fire_action_name = "rapid_left",
				unaim_action_name = "action_vent",
			}
			local templates = { forcestaff_p2 = template }

			RangedMetaData.inject(templates)

			assert.equals("trigger_charge_flame", template.attack_meta_data.aim_fire_action_input)
			assert.equals("action_shoot_charged_flame", template.attack_meta_data.aim_fire_action_name)
			assert.equals("charge_flame", template.attack_meta_data.aim_action_input)
			assert.equals("action_charge_flame", template.attack_meta_data.aim_action_name)
			assert.equals("charge_flame_release", template.attack_meta_data.unaim_action_input)
			assert.equals("action_charge_flame_release", template.attack_meta_data.unaim_action_name)
			assert.equals("shoot_pressed", template.attack_meta_data.fire_action_input)
		end)

		it("restores invalid original attack_meta_data after the charge-override pass", function()
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					charge_flame = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					trigger_charge_flame = {
						input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						},
					},
				},
				actions = {
					rapid_left = { start_input = "shoot_pressed" },
					action_charge_flame = {
						start_input = "charge_flame",
						stop_input = "charge_flame_release",
						allowed_chain_actions = {
							trigger_charge_flame = { action_name = "action_shoot_charged_flame" },
						},
					},
					action_charge_flame_release = { start_input = "charge_flame_release" },
					action_shoot_charged_flame = {
						stop_input = "cancel_flame",
					},
				},
			})
			local templates = { forcestaff_p2 = template }

			template.attack_meta_data = "invalid_meta"
			RangedMetaData.inject(templates)

			assert.is_table(template.attack_meta_data)

			enabled = false
			RangedMetaData.sync_all()

			assert.equals("invalid_meta", template.attack_meta_data)
		end)

		it("overrides aim metadata for braced stream weapons (#87 flamer)", function()
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					brace_pressed = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					brace_release = { input_sequence = {
						{ input = "action_two_hold", value = false },
					} },
					shoot_braced = { input_sequence = {
						{ input = "action_one_hold", value = true },
					} },
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
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
			})
			template.attack_meta_data = {
				fire_action_input = "shoot_pressed",
				fire_action_name = "action_shoot",
				aim_fire_action_input = "shoot_pressed",
				aim_fire_action_name = "action_shoot",
			}
			local templates = { flamer = template }

			RangedMetaData.inject(templates)

			assert.equals("shoot_braced", template.attack_meta_data.aim_fire_action_input)
			assert.equals("action_shoot_braced", template.attack_meta_data.aim_fire_action_name)
			assert.equals("brace_pressed", template.attack_meta_data.aim_action_input)
			assert.equals("action_brace", template.attack_meta_data.aim_action_name)
			assert.equals("brace_release", template.attack_meta_data.unaim_action_input)
			assert.equals("action_unbrace", template.attack_meta_data.unaim_action_name)
			assert.equals("shoot_pressed", template.attack_meta_data.fire_action_input)
		end)

		it("derives chain-only unaim actions for braced stream weapons", function()
			local template = make_ranged_template({
				action_inputs = {
					brace_pressed = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					brace_release = { input_sequence = {
						{ input = "action_two_hold", value = false },
					} },
					shoot_braced = { input_sequence = {
						{ input = "action_one_hold", value = true },
					} },
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
			})

			local aim_input, aim_action, unaim_input, unaim_action =
				RangedMetaData._find_aim_action_for_fire(template, "shoot_braced")

			assert.equals("brace_pressed", aim_input)
			assert.equals("action_brace", aim_action)
			assert.equals("brace_release", unaim_input)
			assert.equals("action_unbrace", unaim_action)
		end)

		it("does not override aim_fire when it already matches hold_input input", function()
			local templates = {
				lasgun = make_ranged_template({
					action_inputs = {
						shoot_pressed = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = {
							input_sequence = {
								{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
							},
						},
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}
			-- Simulate vanilla attack_meta_data already correct
			templates.lasgun.attack_meta_data = {
				fire_action_input = "shoot_pressed",
				aim_fire_action_input = "zoom_shoot",
				aim_fire_action_name = "action_shoot_zoomed",
			}

			RangedMetaData.inject(templates)

			-- Unchanged — zoom_shoot matches find_aim_fire_input result
			assert.equals("zoom_shoot", templates.lasgun.attack_meta_data.aim_fire_action_input)
			assert.equals("action_shoot_zoomed", templates.lasgun.attack_meta_data.aim_fire_action_name)
		end)

		it("does not override aim_fire for weapons without hold_input input", function()
			local templates = {
				plasma = make_ranged_template({
					action_inputs = {
						shoot_charge = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
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
			-- No trigger_explosion → aim_fire mirrors fire (from existing logic)
			assert.equals("shoot_charge", meta.aim_fire_action_input)
			assert.is_nil(meta.aim_fire_action_name)
		end)

		it(
			"does not crash when a replace-injected template also hits charge-override (#v0.11.0 startup crash)",
			function()
				-- Regression: template with no attack_meta_data is replace-injected by
				-- the main loop (mode = "replace"), then matched again by the charge
				-- override loop. ensure_change preserves replace mode and does not
				-- initialize original_fields; record_original_field must no-op rather
				-- than nil-index. Double-inject mirrors Tertium4Or5's require hook
				-- re-firing inject() with persistent state.changes.
				local template = make_ranged_template({
					action_inputs = {
						shoot_charge = {
							input_sequence = {
								{ input = "action_one_pressed", value = true },
							},
						},
						charge = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						trigger_explosion = {
							input_sequence = {
								{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
							},
						},
					},
					actions = {
						rapid_left = { start_input = "shoot_charge" },
						action_charge = {
							start_input = "charge",
							allowed_chain_actions = {
								trigger_explosion = { action_name = "action_explode" },
							},
						},
						action_explode = { start_input = "trigger_explosion" },
					},
				})
				local templates = { forcestaff = template }

				assert.has_no.errors(function()
					RangedMetaData.inject(templates)
				end)
				assert.has_no.errors(function()
					RangedMetaData.inject(templates)
				end)

				assert.is_table(template.attack_meta_data)
				assert.equals("trigger_explosion", template.attack_meta_data.aim_fire_action_input)
			end
		)
	end)
end)
