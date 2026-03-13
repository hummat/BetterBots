describe("TargetSelection", function()
	local TargetSelection
	local _mod
	local original_slot_weight

	local function make_smart_tag_system(target_unit, is_human)
		return {
			unit_tag = function(self, unit)
				if unit == target_unit then
					return {
						tagger_player = function()
							return { is_human_controlled = function() return is_human end }
						end,
					}
				end
				return nil
			end,
		}
	end

	before_each(function()
		TargetSelection = require("scripts.mods.BetterBots.target_selection")

		-- Default: no smart tags
		_G.Managers = {
			state = {
				extension = {
					system = function(self, name)
						if name == "smart_tag_system" then
							return { unit_tag = function() return nil end }
						end
					end,
				},
			},
		}

		-- Mock the mod object
		_mod = {
			hook_require = function(self, path, callback)
				if path == "scripts/utilities/bot_target_selection" then
					local mock_module = {}
					callback(mock_module)
				end
			end,
			hook = function(self, module, name, handler)
				_mod.handlers = _mod.handlers or {}
				_mod.handlers[name] = handler
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

		original_slot_weight = function(unit, target_unit, target_distance_sq, target_breed, target_ally)
			return 5 -- arbitrary base score
		end

		-- Mock Ammo
		package.loaded["scripts/utilities/ammo"] = {
			current_slot_percentage = function(unit, slot)
				if unit.has_ammo then
					return 1.0
				end
				if unit.low_ammo then
					return 0.3
				end
				return 0.0
			end,
		}

		TargetSelection.register_hooks()
	end)

	after_each(function()
		package.loaded["scripts/utilities/ammo"] = nil
		_G.Managers = nil
	end)

	it("does not penalize normal targets at any distance", function()
		local unit = { has_ammo = true }
		local breed = { tags = {} } -- no special/elite tags

		-- < 18m (324 sq)
		local score1 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 100, breed, nil)
		assert.are.equal(5, score1)

		-- > 18m
		local score2 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed, nil)
		assert.are.equal(5, score2)
	end)

	it("does not penalize targets with nil tags", function()
		local unit = { has_ammo = true }
		local breed = {} -- nil tags

		local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed, nil)
		assert.are.equal(5, score)
	end)

	it("does not penalize special targets within 18m", function()
		local unit = { has_ammo = true }
		local breed_special = { tags = { special = true } }

		local score1 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 324, breed_special, nil)
		assert.are.equal(5, score1)
	end)

	it("does not penalize elite targets even if >18m and has ammo", function()
		local unit = { has_ammo = true }
		local breed_elite = { tags = { elite = true } }

		local score1 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_elite, nil)
		assert.are.equal(5, score1)
	end)

	it("penalizes special targets >18m when bot has sufficient ranged ammo (>50%)", function()
		local unit = { has_ammo = true }
		local breed_special = { tags = { special = true } }

		-- 325 is just over 18m squared (324)
		local score1 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 325, breed_special, nil)
		assert.are.equal(-95, score1) -- 5 - 100
	end)

	it("does not penalize special targets >18m when bot has low ranged ammo (<=50%)", function()
		local unit = { low_ammo = true }
		local breed_special = { tags = { special = true } }

		local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_special, nil)
		assert.are.equal(5, score)
	end)

	it("does not penalize special targets >18m when bot has NO ranged ammo", function()
		local unit = { has_ammo = false }
		local breed_special = { tags = { special = true } }

		local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_special, nil)
		assert.are.equal(5, score)
	end)

	it("does not penalize special targets >18m when ammo percentage is nil", function()
		-- Setup a unit without any ammo fields so it returns nil from mock if mock handled it.
		-- Actually mock currently returns 0.0 if not has_ammo and not low_ammo.
		-- Let's temporarily override the mock to return nil.
		package.loaded["scripts/utilities/ammo"].current_slot_percentage = function()
			return nil
		end

		local unit = {}
		local breed_special = { tags = { special = true } }

		local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_special, nil)
		assert.are.equal(5, score)
	end)

	-- #48: player tag boost
	it("has_human_player_tag returns true for human-tagged unit", function()
		local target_unit = {}
		_G.Managers = {
			state = {
				extension = {
					system = function(self, name)
						if name == "smart_tag_system" then
							return make_smart_tag_system(target_unit, true)
						end
					end,
				},
			},
		}
		assert.is_true(TargetSelection.has_human_player_tag(target_unit))
	end)

	it("boosts score when target is tagged by a human player", function()
		local target_unit = {}
		_G.Managers = {
			state = {
				extension = {
					system = function(self, name)
						if name == "smart_tag_system" then
							return make_smart_tag_system(target_unit, true)
						end
					end,
				},
			},
		}

		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }
		local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.are.equal(8, score) -- 5 + 3
	end)

	it("does not boost score when vanilla slot_weight is zero", function()
		local target_unit = {}
		_G.Managers.state.extension.system = function(self, name)
			if name == "smart_tag_system" then
				return make_smart_tag_system(target_unit, true)
			end
		end

		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }
		local score = _mod.handlers.slot_weight(function()
			return 0
		end, unit, target_unit, 100, breed, nil)
		assert.are.equal(0, score)
	end)

	it("does not boost score when target is tagged by a bot (not human)", function()
		local target_unit = {}
		_G.Managers.state.extension.system = function(self, name)
			if name == "smart_tag_system" then
				return make_smart_tag_system(target_unit, false)
			end
		end

		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }
		local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.are.equal(5, score)
	end)

	it("does not boost score when target has no tag", function()
		local target_unit = {}
		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }
		local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.are.equal(5, score)
	end)

	it("does not boost score when smart_tag_system is unavailable", function()
		_G.Managers.state.extension.system = function() return nil end
		local target_unit = {}
		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }
		local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.are.equal(5, score)
	end)

	it("does not boost score when target_unit is nil", function()
		local unit = { has_ammo = true }
		local breed = { tags = {}, name = "cultist" }
		local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 100, breed, nil)
		assert.are.equal(5, score)
	end)
end)
