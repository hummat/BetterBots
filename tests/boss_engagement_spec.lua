describe("Boss engagement", function()
	local TargetSelection
	local _mod
	local original_monster_weight
	local old_blackboards

	before_each(function()
		TargetSelection = require("scripts.mods.BetterBots.target_selection")

		old_blackboards = rawget(_G, "BLACKBOARDS")
		_G.BLACKBOARDS = {}

		_mod = {
			hook_require = function(self, path, callback)
				if path == "scripts/utilities/bot_target_selection" then
					callback({})
				end
			end,
			hook = function(self, module, name, handler)
				_mod.handlers = _mod.handlers or {}
				_mod.handlers[name] = handler
			end,
		}

		package.loaded["scripts/utilities/ammo"] = {
			current_slot_percentage = function()
				return 1.0
			end,
		}

		TargetSelection.init({
			mod = _mod,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 0
			end,
		})

		TargetSelection.register_hooks()

		original_monster_weight = function()
			return 0, false
		end
	end)

	after_each(function()
		package.loaded["scripts/utilities/ammo"] = nil
		_G.BLACKBOARDS = old_blackboards
	end)

	it("registers a monster_weight hook", function()
		assert.is_function(_mod.handlers.monster_weight)
	end)

	it("restores vanilla monster weight when the boss is aggroed on this bot", function()
		local bot_unit = {}
		local monster_unit = {}
		local target_breed = { name = "chaos_plague_ogryn", tags = { monster = true } }

		BLACKBOARDS[monster_unit] = {
			perception = {
				aggro_state = "aggroed",
				target_unit = bot_unit,
			},
		}

		local weight, override =
			_mod.handlers.monster_weight(original_monster_weight, bot_unit, monster_unit, target_breed, 0)

		assert.are.equal(2, weight)
		assert.is_false(override)
	end)

	it("keeps zero monster weight when the boss is aggroed on someone else", function()
		local bot_unit = {}
		local monster_unit = {}
		local other_unit = {}
		local target_breed = { name = "chaos_plague_ogryn", tags = { monster = true } }

		BLACKBOARDS[monster_unit] = {
			perception = {
				aggro_state = "aggroed",
				target_unit = other_unit,
			},
		}

		local weight, override =
			_mod.handlers.monster_weight(original_monster_weight, bot_unit, monster_unit, target_breed, 0)

		assert.are.equal(0, weight)
		assert.is_false(override)
	end)

	it("preserves the original positive monster weight", function()
		local bot_unit = {}
		local monster_unit = {}
		local target_breed = { name = "chaos_plague_ogryn", tags = { monster = true } }
		local func = function()
			return 2, false
		end

		local weight, override = _mod.handlers.monster_weight(func, bot_unit, monster_unit, target_breed, 0)

		assert.are.equal(2, weight)
		assert.is_false(override)
	end)
end)
