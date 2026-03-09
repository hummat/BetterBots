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
end)
