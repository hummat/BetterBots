local test_helper = require("tests.test_helper")

describe("TargetSelection", function()
	local TargetSelection
	local _mod
	local original_slot_weight

	before_each(function()
		TargetSelection = require("scripts.mods.BetterBots.target_selection")
		
		-- Mock the mod object
		_mod = {
			hook_require = function(self, path, callback)
				if path == "scripts/utilities/bot_target_selection" then
					local mock_module = {}
					callback(mock_module)
				end
			end,
			hook = function(self, module, name, handler)
				-- Store the handler so we can test it
				_mod.stored_handler = handler
			end,
		}
		
		TargetSelection.init(_mod)
		TargetSelection.register_hooks()
		
		original_slot_weight = function(unit, target_unit, target_distance_sq, target_breed, target_ally)
			return 5 -- arbitrary base score
		end
		
		-- Mock Ammo
		package.loaded["scripts/utilities/ammo"] = {
			current_slot_percentage = function(unit, slot)
				if unit.has_ammo then
					return 1.0
				end
				return 0.0
			end
		}
	end)

	after_each(function()
		package.loaded["scripts/utilities/ammo"] = nil
	end)

	it("does not penalize normal targets at any distance", function()
		local unit = { has_ammo = true }
		local breed = { tags = {} } -- no special/elite tags
		
		-- < 18m (324 sq)
		local score1 = _mod.stored_handler(original_slot_weight, unit, nil, 100, breed, nil)
		assert.are.equal(5, score1)
		
		-- > 18m
		local score2 = _mod.stored_handler(original_slot_weight, unit, nil, 400, breed, nil)
		assert.are.equal(5, score2)
	end)

	it("does not penalize special/elite targets within 18m", function()
		local unit = { has_ammo = true }
		local breed_special = { tags = { special = true } }
		local breed_elite = { tags = { elite = true } }
		
		local score1 = _mod.stored_handler(original_slot_weight, unit, nil, 324, breed_special, nil)
		assert.are.equal(5, score1)
		
		local score2 = _mod.stored_handler(original_slot_weight, unit, nil, 100, breed_elite, nil)
		assert.are.equal(5, score2)
	end)

	it("penalizes special/elite targets >18m when bot has ranged ammo", function()
		local unit = { has_ammo = true }
		local breed_special = { tags = { special = true } }
		local breed_elite = { tags = { elite = true } }
		
		-- 325 is just over 18m squared (324)
		local score1 = _mod.stored_handler(original_slot_weight, unit, nil, 325, breed_special, nil)
		assert.are.equal(-95, score1) -- 5 - 100
		
		local score2 = _mod.stored_handler(original_slot_weight, unit, nil, 400, breed_elite, nil)
		assert.are.equal(-95, score2)
	end)

	it("does not penalize special/elite targets >18m when bot has NO ranged ammo", function()
		local unit = { has_ammo = false }
		local breed_special = { tags = { special = true } }
		
		local score = _mod.stored_handler(original_slot_weight, unit, nil, 400, breed_special, nil)
		assert.are.equal(5, score)
	end)
end)