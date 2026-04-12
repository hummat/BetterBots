local SustainedFire = dofile("scripts/mods/BetterBots/sustained_fire.lua")

describe("sustained_fire", function()
	it("arms held-primary sustained state for recon lasgun fire", function()
		local state = SustainedFire.resolve_state("bot_1", "lasgun_p3_m1", "shoot")

		assert.is_not_nil(state)
		assert.is_true(state.hold_inputs.action_one_hold)
	end)

	it("arms held-primary sustained state for bolter fire", function()
		local state = SustainedFire.resolve_state("bot_1", "bolter_p1_m2", "shoot_pressed")

		assert.is_not_nil(state)
		assert.is_true(state.hold_inputs.action_one_hold)
	end)

	it("arms sustained state for flamer braced stream", function()
		local state = SustainedFire.resolve_state("bot_1", "flamer_p1_m1", "shoot_braced")

		assert.is_not_nil(state)
		assert.is_true(state.hold_inputs.action_one_hold)
	end)

	it("arms sustained state for purgatus stream and keeps charge hold alive", function()
		local state = SustainedFire.resolve_state("bot_1", "forcestaff_p2_m1", "trigger_charge_flame")

		assert.is_not_nil(state)
		assert.is_true(state.hold_inputs.action_two_hold)
		assert.is_nil(state.hold_inputs.action_one_hold)
	end)

	it("does not arm sustained state for rippergun burst hipfire", function()
		local state = SustainedFire.resolve_state("bot_1", "ogryn_rippergun_p1_m1", "shoot")

		assert.is_nil(state)
	end)

	it("arms sustained state for rippergun braced fire", function()
		local state = SustainedFire.resolve_state("bot_1", "ogryn_rippergun_p1_m1", "zoom_shoot")

		assert.is_not_nil(state)
		assert.is_true(state.hold_inputs.action_one_hold)
	end)

	it("injects held inputs while sustained state is active", function()
		local unit = {}
		local input = {}
		SustainedFire.arm(unit, {
			template_name = "lasgun_p3_m1",
			action_input = "shoot",
			hold_inputs = {
				action_one_hold = true,
			},
		})

		SustainedFire.update_actions(unit, input, "lasgun_p3_m1")

		assert.is_true(input.action_one_hold)
	end)

	it("clears sustained state on reload", function()
		local unit = {}
		SustainedFire.arm(unit, {
			template_name = "lasgun_p3_m1",
			action_input = "shoot",
			hold_inputs = {
				action_one_hold = true,
			},
		})

		SustainedFire.observe_weapon_action_input(unit, "lasgun_p3_m1", "reload")

		assert.is_nil(SustainedFire.active_state(unit))
	end)

	it("clears stale sustained state when template changes", function()
		local unit = {}
		local input = {}
		SustainedFire.arm(unit, {
			template_name = "lasgun_p3_m1",
			action_input = "shoot",
			hold_inputs = {
				action_one_hold = true,
			},
		})

		SustainedFire.update_actions(unit, input, "combat_axe_p1_m1")

		assert.is_nil(SustainedFire.active_state(unit))
		assert.is_nil(input.action_one_hold)
	end)
end)
