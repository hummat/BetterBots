local function load_module()
	local ok, mod = pcall(dofile, "scripts/mods/BetterBots/vfx_suppression.lua")
	assert.is_true(ok, "vfx_suppression.lua should load")
	return mod
end

describe("vfx_suppression", function()
	it("restores the original is_local_unit value after visual loadout init succeeds", function()
		local VfxSuppression = load_module()
		local visual_loadout_init
		local stub_mod = {
			hook_require = function(_, path, callback)
				if path == "scripts/extension_systems/visual_loadout/player_unit_visual_loadout_extension" then
					callback({})
				elseif
					path == "scripts/extension_systems/character_state_machine/character_state_machine_extension"
				then
					callback({})
				else
					error("unexpected hook_require path: " .. tostring(path))
				end
			end,
			hook = function(_, _, method_name, handler)
				if method_name == "init" and not visual_loadout_init then
					visual_loadout_init = handler
				end
			end,
			hook_safe = function() end,
		}

		VfxSuppression.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
		})
		VfxSuppression.register_hooks()

		local extension_init_data = {
			player = {
				is_human_controlled = function()
					return false
				end,
			},
			is_local_unit = nil,
		}
		local seen_during_call

		visual_loadout_init(function(_, _, _, incoming_init_data)
			seen_during_call = incoming_init_data.is_local_unit
		end, {}, {}, "bot_unit", extension_init_data)

		assert.equals(false, seen_during_call)
		assert.is_nil(extension_init_data.is_local_unit)
	end)

	it("restores the original is_local_unit value when visual loadout init throws", function()
		local VfxSuppression = load_module()
		local visual_loadout_init
		local stub_mod = {
			hook_require = function(_, path, callback)
				if path == "scripts/extension_systems/visual_loadout/player_unit_visual_loadout_extension" then
					callback({})
				elseif
					path == "scripts/extension_systems/character_state_machine/character_state_machine_extension"
				then
					callback({})
				else
					error("unexpected hook_require path: " .. tostring(path))
				end
			end,
			hook = function(_, _, method_name, handler)
				if method_name == "init" and not visual_loadout_init then
					visual_loadout_init = handler
				end
			end,
			hook_safe = function() end,
		}

		VfxSuppression.init({
			mod = stub_mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
		})
		VfxSuppression.register_hooks()

		local extension_init_data = {
			player = {
				is_human_controlled = function()
					return false
				end,
			},
			is_local_unit = true,
		}

		local ok = pcall(function()
			visual_loadout_init(function()
				error("boom")
			end, {}, {}, "bot_unit", extension_init_data)
		end)

		assert.is_false(ok)
		assert.equals(true, extension_init_data.is_local_unit)
	end)
end)
