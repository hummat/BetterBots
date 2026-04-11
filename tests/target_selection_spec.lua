describe("TargetSelection", function()
	local TargetSelection
	local _mod
	local original_slot_weight
	local original_line_of_sight_weight

	local function make_smart_tag_system(target_unit, is_human)
		return {
			unit_tag = function(_self, unit)
				if unit == target_unit then
					return {
						tagger_player = function()
							return {
								is_human_controlled = function()
									return is_human
								end,
							}
						end,
					}
				end
				return nil
			end,
		}
	end

	before_each(function()
		TargetSelection = require("scripts.mods.BetterBots.target_selection")
		_G.BLACKBOARDS = {}
		_G.ScriptUnit = {
			has_extension = function(unit, name)
				if name == "unit_data_system" and unit and unit._breed then
					return {
						breed = function()
							return unit._breed
						end,
					}
				end
				return nil
			end,
		}

		-- Default: no smart tags
		_G.Managers = {
			state = {
				extension = {
					system = function(_self, name)
						if name == "smart_tag_system" then
							return {
								unit_tag = function()
									return nil
								end,
							}
						end
					end,
				},
			},
		}

		-- Mock the mod object
		_mod = {
			hook_require = function(_self, path, callback)
				if path == "scripts/utilities/bot_target_selection" then
					local mock_module = {}
					callback(mock_module)
				end
			end,
			hook = function(_self, _module, name, handler)
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

		original_slot_weight = function(_unit, _target_unit, _target_distance_sq, _target_breed, _target_ally)
			return 5 -- arbitrary base score
		end
		original_line_of_sight_weight = function()
			return 1
		end

		-- Mock Ammo
		package.loaded["scripts/utilities/ammo"] = {
			current_slot_percentage = function(unit, _slot)
				if unit.has_ammo then
					return 1.0
				end
				if unit.low_ammo then
					return 0.3
				end
				return 0.0
			end,
		}
		package.loaded["scripts/utilities/breed"] = {
			is_companion = function(breed)
				return breed and breed.breed_type == "companion"
			end,
		}

		TargetSelection.register_hooks()
	end)

	after_each(function()
		package.loaded["scripts/utilities/ammo"] = nil
		package.loaded["scripts/utilities/breed"] = nil
		_G.Managers = nil
		_G.BLACKBOARDS = nil
		_G.ScriptUnit = nil
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
					system = function(_self, name)
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
					system = function(_self, name)
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
		_G.Managers.state.extension.system = function(_self, name)
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
		_G.Managers.state.extension.system = function(_self, name)
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
		_G.Managers.state.extension.system = function()
			return nil
		end
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

	-- #81: settings wiring tests
	describe("settings wiring (#81)", function()
		it("disables player tag boost when player_tag_bonus=0", function()
			local target_unit = {}
			_G.Managers.state.extension.system = function(_self, name)
				if name == "smart_tag_system" then
					return make_smart_tag_system(target_unit, true)
				end
			end

			TargetSelection.init({
				mod = _mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
				player_tag_bonus = function()
					return 0
				end,
			})
			TargetSelection.register_hooks()

			local unit = { has_ammo = true }
			local breed = { tags = { elite = true }, name = "chaos_hound" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(5, score) -- no boost when bonus=0
		end)

		it("disables special chase penalty when special_chase_penalty_range=0", function()
			TargetSelection.init({
				mod = _mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
				special_chase_penalty_range = function()
					return 0
				end,
			})
			TargetSelection.register_hooks()

			local unit = { has_ammo = true }
			local breed_special = { tags = { special = true } }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_special, nil)
			assert.are.equal(5, score) -- no penalty when range=0
		end)

		it("uses configurable chase range", function()
			TargetSelection.init({
				mod = _mod,
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
				special_chase_penalty_range = function()
					return 24
				end,
			})
			TargetSelection.register_hooks()

			local unit = { has_ammo = true }
			local breed_special = { tags = { special = true } }
			-- 400 = 20m, which is < 24m threshold (576 sq) — should NOT penalize
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 400, breed_special, nil)
			assert.are.equal(5, score)

			-- 625 = 25m, which is > 24m threshold — SHOULD penalize
			local score2 = _mod.handlers.slot_weight(original_slot_weight, unit, nil, 625, breed_special, nil)
			assert.are.equal(-95, score2) -- 5 - 100
		end)
	end)

	-- #69: friendly mastiff-pinned targets should be de-prioritized, not boosted.
	describe("friendly companion pin handling (#69)", function()
		it("penalizes melee slot score for enemy pinned by friendly companion mastiff", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local unit = { has_ammo = true }
			local breed = { tags = { elite = true }, name = "renegade_captain" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(-95, score) -- 5 base - 100 pinned-target penalty
		end)

		it("penalizes melee slot score even when base slot_weight is zero", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local zero_slot_weight = function()
				return 0
			end

			local unit = { has_ammo = true }
			local breed = { tags = { elite = true }, name = "renegade_captain" }
			local score = _mod.handlers.slot_weight(zero_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(-100, score)
		end)

		it("penalizes ranged line-of-sight score for enemy pinned by friendly companion mastiff", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local unit = { has_ammo = true }
			local score = _mod.handlers.line_of_sight_weight(original_line_of_sight_weight, unit, target_unit)
			assert.are.equal(-99, score) -- 1 base - 100 pinned-target penalty
		end)

		it("does not penalize non-companion pounced targets", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "minion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local unit = { has_ammo = true }
			local breed = { tags = { elite = true }, name = "renegade_captain" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(5, score)
		end)

		it("does not penalize non-pounced disabled enemies", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "consumed", attacker_unit = attacker_unit },
			}

			local unit = { has_ammo = true }
			local breed = { tags = { elite = true }, name = "renegade_captain" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(5, score)
		end)

		it("does not penalize when disable component is absent", function()
			local target_unit = {}
			_G.BLACKBOARDS[target_unit] = {}

			local unit = { has_ammo = true }
			local breed = { tags = {}, name = "cultist" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(5, score)
		end)

		it("does not penalize when enemy is not disabled", function()
			local target_unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = false, type = "pounced", attacker_unit = attacker_unit },
			}

			local unit = { has_ammo = true }
			local breed = { tags = {}, name = "cultist" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			assert.are.equal(5, score)
		end)

		it("includes the acting bot in the companion-pin debug key and dedups repeated melee logs", function()
			local logs = {}
			TargetSelection.init({
				mod = _mod,
				debug_log = function(key, fixed_t, message)
					logs[#logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 0
				end,
			})
			TargetSelection.register_hooks()

			local target_unit = {}
			local unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local breed = { tags = { elite = true }, name = "renegade_captain" }
			local score = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
			local score_repeat = _mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)

			assert.are.equal(-95, score)
			assert.are.equal(-95, score_repeat)
			assert.equals(1, #logs)
			assert.equals("target_sel_companion_pin:" .. tostring(target_unit) .. ":" .. tostring(unit), logs[1].key)
		end)

		it("dedups repeated ranged companion-pin logs", function()
			local logs = {}
			TargetSelection.init({
				mod = _mod,
				debug_log = function(key, fixed_t, message)
					logs[#logs + 1] = {
						key = key,
						fixed_t = fixed_t,
						message = message,
					}
				end,
				debug_enabled = function()
					return true
				end,
				fixed_time = function()
					return 0
				end,
			})
			TargetSelection.register_hooks()

			local target_unit = {}
			local unit = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[target_unit] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}

			local score = _mod.handlers.line_of_sight_weight(original_line_of_sight_weight, unit, target_unit)
			local score_repeat = _mod.handlers.line_of_sight_weight(original_line_of_sight_weight, unit, target_unit)

			assert.are.equal(-99, score)
			assert.are.equal(-99, score_repeat)
			assert.equals(1, #logs)
			assert.equals(
				"target_sel_companion_pin_ranged:" .. tostring(target_unit) .. ":" .. tostring(unit),
				logs[1].key
			)
		end)
	end)

	-- #69: pure function unit tests
	describe("is_friendly_companion_pin", function()
		it("returns true for enemy pinned by friendly companion", function()
			local enemy = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[enemy] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}
			assert.is_true(TargetSelection.is_friendly_companion_pin(enemy))
		end)

		it("returns false for non-companion attacker", function()
			local enemy = {}
			local attacker_unit = {
				_breed = { breed_type = "minion" },
			}
			_G.BLACKBOARDS[enemy] = {
				disable = { is_disabled = true, type = "pounced", attacker_unit = attacker_unit },
			}
			assert.is_false(TargetSelection.is_friendly_companion_pin(enemy))
		end)

		it("returns false when no blackboard", function()
			assert.is_false(TargetSelection.is_friendly_companion_pin({}))
		end)

		it("returns false when disable not set", function()
			local enemy = {}
			_G.BLACKBOARDS[enemy] = {}
			assert.is_false(TargetSelection.is_friendly_companion_pin(enemy))
		end)

		it("returns false when enemy is not disabled", function()
			local enemy = {}
			local attacker_unit = {
				_breed = { breed_type = "companion" },
			}
			_G.BLACKBOARDS[enemy] = {
				disable = { is_disabled = false, type = "pounced", attacker_unit = attacker_unit },
			}
			assert.is_false(TargetSelection.is_friendly_companion_pin(enemy))
		end)
	end)
end)
