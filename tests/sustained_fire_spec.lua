local test_helper = require("tests.test_helper")
local SustainedFire = dofile("scripts/mods/BetterBots/sustained_fire.lua")
local Sprint = dofile("scripts/mods/BetterBots/sprint.lua")
local _extensions = setmetatable({}, { __mode = "k" })

_G.ScriptUnit = _G.ScriptUnit or {}
_G.ScriptUnit.has_extension = function(unit, system_name)
	local exts = _extensions[unit]
	return exts and exts[system_name] or nil
end

local function make_hooking_mod()
	return {
		hook_require = function() end,
		hook = function(_, target, method_name, handler)
			local original = target[method_name]
			target[method_name] = function(...)
				return handler(original, ...)
			end
		end,
	}
end

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

	it("expires sustained state when no new fire input arrives", function()
		local t = 10
		local unit = {}

		SustainedFire.init({
			fixed_time = function()
				return t
			end,
		})

		SustainedFire.arm(unit, SustainedFire.resolve_state(unit, "lasgun_p3_m1", "shoot"))

		local input = {}
		SustainedFire.update_actions(unit, input, "lasgun_p3_m1")
		assert.is_true(input.action_one_hold)

		t = t + 0.2
		SustainedFire.update_actions(unit, {}, "lasgun_p3_m1")
		t = t + 0.1
		SustainedFire.update_actions(unit, {}, "lasgun_p3_m1")

		assert.is_nil(SustainedFire.active_state(unit))
	end)

	it("refreshes sustained state when new fire input arrives", function()
		local t = 10
		local unit = {}

		SustainedFire.init({
			fixed_time = function()
				return t
			end,
		})

		SustainedFire.arm(unit, SustainedFire.resolve_state(unit, "lasgun_p3_m1", "shoot"))
		SustainedFire.update_actions(unit, {}, "lasgun_p3_m1")

		t = t + 0.2
		SustainedFire.observe_weapon_action_input(unit, "lasgun_p3_m1", "shoot")

		t = t + 0.2
		local input = {}
		SustainedFire.update_actions(unit, input, "lasgun_p3_m1")

		assert.is_not_nil(SustainedFire.active_state(unit))
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

	it("coexists with sprint on BotUnitInput without losing sustained-fire injection", function()
		local BotUnitInput = {
			update = function(self, unit)
				self.updated_unit = unit
			end,
			_update_actions = function(_self, input)
				input.base_action = true
			end,
			_update_movement = function(self, unit, input)
				self.movement_unit = unit
				input.base_movement = true
			end,
		}
		local original_update = BotUnitInput.update
		local original_update_actions = BotUnitInput._update_actions
		local original_update_movement = BotUnitInput._update_movement
		local mod = make_hooking_mod()
		local unit = {}
		local self = {
			_move = { x = 0, y = 1 },
		}
		_extensions[unit] = {
			unit_data_system = test_helper.make_player_unit_data_extension({
				weapon_action = { template_name = "flamer_p1_m1" },
			}),
		}

		SustainedFire.init({
			mod = mod,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 5
			end,
		})
		Sprint.init({
			mod = mod,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 5
			end,
			sprint_follow_distance = function()
				return 0
			end,
		})

		SustainedFire.install_bot_unit_input_hooks(BotUnitInput)
		Sprint.install_bot_unit_input_hooks(BotUnitInput)

		assert.not_equals(original_update, BotUnitInput.update)
		assert.not_equals(original_update_actions, BotUnitInput._update_actions)
		assert.not_equals(original_update_movement, BotUnitInput._update_movement)

		BotUnitInput.update(self, unit, 0, 0)
		SustainedFire.arm(unit, SustainedFire.resolve_state(unit, "flamer_p1_m1", "shoot_braced"))

		local input = {}
		BotUnitInput._update_actions(self, input)

		assert.equals(unit, self.updated_unit)
		assert.is_true(input.base_action)
		assert.is_true(input.action_one_hold)

		local movement_input = {}
		BotUnitInput._update_movement(self, unit, movement_input, 0, 0)

		assert.equals(unit, self.movement_unit)
		assert.is_true(movement_input.base_movement)
	end)
end)
