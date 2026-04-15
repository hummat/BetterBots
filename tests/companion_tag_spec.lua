local CompanionTag = require("scripts.mods.BetterBots.companion_tag")
local test_helper = require("tests.test_helper")

describe("companion_tag", function()
	local mod_mock, debug_log_mock, fixed_time_mock, bot_unit
	local current_time = 0

	local function reinit(opts)
		opts = opts or {}
		CompanionTag.init({
			mod = mod_mock,
			debug_log = debug_log_mock,
			debug_enabled = function()
				return opts.debug or false
			end,
			fixed_time = fixed_time_mock,
			bot_slot_for_unit = function()
				return 1
			end,
		})
	end

	before_each(function()
		current_time = 0
		bot_unit = { name = "bot_unit" }
		fixed_time_mock = function()
			return current_time
		end
		mod_mock = {
			warning = spy.new(function() end),
		}
		debug_log_mock = spy.new(function() end)

		test_helper.setup_engine_stubs()

		reinit()

		_G.Unit = {
			alive = function(unit)
				return unit ~= nil
			end,
		}
		_G.POSITION_LOOKUP = {}
		_G.Vector3 = {
			distance_squared = function(a, b)
				local dx = a.x - b.x
				local dy = a.y - b.y
				local dz = a.z - b.z
				return dx * dx + dy * dy + dz * dz
			end,
		}
		_G.Managers = {
			state = {
				extension = {
					system = function()
						return nil
					end,
				},
			},
		}
	end)

	after_each(function()
		test_helper.teardown_engine_stubs()
		_G.Unit = nil
		_G.POSITION_LOOKUP = nil
		_G.Vector3 = nil
		_G.Managers = nil
	end)

	-- Helper: set up a bot with companion_spawner_extension
	local function setup_arbites_bot(has_companion)
		_G.ScriptUnit.has_extension = function(unit, ext)
			if unit == bot_unit and ext == "companion_spawner_system" then
				return test_helper.make_companion_spawner_extension({
					should_have_companion = has_companion,
					companion_units = has_companion and { { name = "cyber_mastiff" } } or nil,
				})
			end
			return nil
		end
	end

	-- Helper: set up full environment with targets and smart_tag_system
	local function setup_full_env(opts)
		opts = opts or {}
		local companion_unit = opts.companion_unit or { name = "cyber_mastiff" }
		local set_tag_mock = spy.new(function() end)
		local existing_companion_tags = opts.existing_companion_tags or {}

		_G.ScriptUnit.has_extension = function(unit, ext)
			if unit == bot_unit and ext == "companion_spawner_system" then
				return test_helper.make_companion_spawner_extension({
					should_have_companion = true,
					companion_units = { companion_unit },
				})
			end
			if ext == "unit_data_system" then
				local breed = opts.breeds and opts.breeds[unit]
				if breed then
					return test_helper.make_minion_unit_data_extension(breed)
				end
				return nil
			end
			if ext == "smart_tag_system" then
				return test_helper.make_smart_tag_extension(existing_companion_tags[unit] or nil)
			end
			if ext == "perception_system" then
				return test_helper.make_minion_perception_extension({
					has_line_of_sight = opts.has_los ~= false,
				})
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_tag = set_tag_mock,
					unit_tag = function(_, target_unit)
						if existing_companion_tags[target_unit] then
							return {
								template = function()
									return { name = "enemy_companion_target" }
								end,
							}
						end
						return nil
					end,
				}
			end
			return nil
		end

		return set_tag_mock, companion_unit
	end

	-- ── Guard checks ──────────────────────────────────────────────

	it("does nothing when bot has no companion_spawner_extension", function()
		-- ScriptUnit.has_extension returns nil for all (default stub)
		local blackboard = {
			perception = {
				priority_target_enemy = { name = "elite" },
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		-- Should not crash, should not call anything
	end)

	it("does nothing when bot has no live companion", function()
		setup_arbites_bot(false)

		local blackboard = {
			perception = {
				priority_target_enemy = { name = "elite" },
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		-- Should exit early, no crash
	end)

	it("does nothing when blackboard has no perception", function()
		setup_arbites_bot(true)
		CompanionTag.update(bot_unit, {})
	end)

	it("does nothing when no taggable target in any slot", function()
		local set_tag_mock = setup_full_env({
			breeds = {},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = { name = "trash" },
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_not_called()
	end)

	it("does nothing when target is not elite/special/monster", function()
		local trash = { name = "trash_unit" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[trash] = { name = "poxwalker", tags = { horde = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = trash,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_not_called()
	end)

	-- ── Target selection ──────────────────────────────────────────

	it("tags highest-priority elite target with companion-command tag", function()
		local elite = { name = "elite_unit" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[elite] = { name = "renegade_captain", tags = { elite = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_called(1)
		assert
			.spy(set_tag_mock)
			.was_called_with(match.is_table(), "enemy_companion_target", match.is_ref(bot_unit), match.is_ref(elite), nil)
	end)

	it("tags specials", function()
		local special = { name = "special_unit" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[special] = { name = "cultist_flamer", tags = { special = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = special,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_called(1)
	end)

	it("tags monsters", function()
		local monster = { name = "monster_unit" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[monster] = { name = "chaos_spawn", tags = { monster = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = monster,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_called(1)
	end)

	it("follows ping slot priority order", function()
		local low = { name = "low_priority" }
		local high = { name = "high_priority" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[low] = { name = "renegade_sniper", tags = { special = true } },
				[high] = { name = "renegade_captain", tags = { elite = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = high,
				target_enemy = low,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert
			.spy(set_tag_mock)
			.was_called_with(match.is_table(), "enemy_companion_target", match.is_ref(bot_unit), match.is_ref(high), nil)
	end)

	it("falls back to next slot if top priority target is already companion-tagged", function()
		local tagged = { name = "already_tagged" }
		local untagged = { name = "untagged" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[tagged] = { name = "renegade_captain", tags = { elite = true } },
				[untagged] = { name = "renegade_sniper", tags = { special = true } },
			},
			existing_companion_tags = {
				[tagged] = 999,
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = tagged,
				opportunity_target_enemy = untagged,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert
			.spy(set_tag_mock)
			.was_called_with(match.is_table(), "enemy_companion_target", match.is_ref(bot_unit), match.is_ref(untagged), nil)
	end)

	-- ── Dedup / hold ──────────────────────────────────────────────

	it("does not re-tag the same target on consecutive ticks", function()
		local elite = { name = "elite_unit" }
		local set_tag_mock = setup_full_env({
			breeds = {
				[elite] = { name = "renegade_captain", tags = { elite = true } },
			},
		})

		POSITION_LOOKUP[bot_unit] = { x = 0, y = 0, z = 0 }
		POSITION_LOOKUP[elite] = { x = 10, y = 0, z = 0 }

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(set_tag_mock).was_called(1)

		-- Mark the target as now having a companion tag (our tag took effect)
		local existing_tags = { [elite] = 123 }
		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_tag = set_tag_mock,
					unit_tag = function(_, target_unit)
						if existing_tags[target_unit] then
							return {
								template = function()
									return { name = "enemy_companion_target" }
								end,
							}
						end
						return nil
					end,
				}
			end
			return nil
		end

		current_time = 0.1
		CompanionTag.update(bot_unit, blackboard)
		-- Should not re-tag — already companion-tagged
		assert.spy(set_tag_mock).was_called(1)
	end)

	it("holds the current companion tag during the minimum hold window", function()
		local current_target = { name = "current_target" }
		local lower_priority_target = { name = "lower_priority_target" }
		local existing_tags = {}
		local set_tag_mock = setup_full_env({
			breeds = {
				[current_target] = { name = "renegade_captain", tags = { elite = true } },
				[lower_priority_target] = { name = "renegade_sniper", tags = { special = true } },
			},
			existing_companion_tags = existing_tags,
		})

		CompanionTag.update(bot_unit, {
			perception = {
				priority_target_enemy = current_target,
			},
		})
		assert.spy(set_tag_mock).was_called(1)

		existing_tags[current_target] = 123
		current_time = 0.5

		CompanionTag.update(bot_unit, {
			perception = {
				priority_target_enemy = current_target,
				target_enemy = lower_priority_target,
			},
		})

		assert.spy(set_tag_mock).was_called(1)
	end)

	it("allows an early retag when a strictly higher-priority target appears", function()
		local current_target = { name = "current_target" }
		local higher_priority_target = { name = "higher_priority_target" }
		local existing_tags = {}
		local set_tag_mock = setup_full_env({
			breeds = {
				[current_target] = { name = "renegade_sniper", tags = { special = true } },
				[higher_priority_target] = { name = "chaos_ogryn_executor", tags = { elite = true } },
			},
			existing_companion_tags = existing_tags,
		})

		CompanionTag.update(bot_unit, {
			perception = {
				target_enemy = current_target,
			},
		})
		assert.spy(set_tag_mock).was_called(1)

		existing_tags[current_target] = 123
		current_time = 0.5

		CompanionTag.update(bot_unit, {
			perception = {
				priority_target_enemy = higher_priority_target,
				target_enemy = current_target,
			},
		})

		assert.spy(set_tag_mock).was_called(2)
		assert
			.spy(set_tag_mock)
			.was_called_with(
				match.is_table(),
				"enemy_companion_target",
				match.is_ref(bot_unit),
				match.is_ref(higher_priority_target),
				nil
			)
	end)

	it("allows a lower-priority retag after the hold window expires", function()
		local current_target = { name = "current_target" }
		local lower_priority_target = { name = "lower_priority_target" }
		local existing_tags = {}
		local set_tag_mock = setup_full_env({
			breeds = {
				[current_target] = { name = "renegade_captain", tags = { elite = true } },
				[lower_priority_target] = { name = "renegade_sniper", tags = { special = true } },
			},
			existing_companion_tags = existing_tags,
		})

		CompanionTag.update(bot_unit, {
			perception = {
				priority_target_enemy = current_target,
			},
		})
		assert.spy(set_tag_mock).was_called(1)

		existing_tags[current_target] = 123
		current_time = 2.5

		CompanionTag.update(bot_unit, {
			perception = {
				priority_target_enemy = current_target,
				target_enemy = lower_priority_target,
			},
		})

		assert.spy(set_tag_mock).was_called(2)
		assert
			.spy(set_tag_mock)
			.was_called_with(
				match.is_table(),
				"enemy_companion_target",
				match.is_ref(bot_unit),
				match.is_ref(lower_priority_target),
				nil
			)
	end)

	-- ── Failure backoff ───────────────────────────────────────────

	it("backs off after set_tag failure", function()
		local elite = { name = "elite_unit" }
		local call_count = 0

		setup_full_env({
			breeds = {
				[elite] = { name = "renegade_captain", tags = { elite = true } },
			},
		})

		-- Override to make set_tag fail
		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_tag = function()
						call_count = call_count + 1
						error("boom")
					end,
					unit_tag = function()
						return nil
					end,
				}
			end
			return nil
		end

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.equals(1, call_count)

		-- Immediate retry should be suppressed by backoff
		current_time = 0.5
		CompanionTag.update(bot_unit, blackboard)
		assert.equals(1, call_count)

		-- After backoff expires, should retry
		current_time = 3.0
		CompanionTag.update(bot_unit, blackboard)
		assert.equals(2, call_count)
	end)

	-- ── Managers.state nil safety ─────────────────────────────────

	it("does not crash when Managers.state is nil", function()
		_G.Managers.state = nil
		local elite = { name = "elite_unit" }

		_G.ScriptUnit.has_extension = function(unit, ext)
			if unit == bot_unit and ext == "companion_spawner_system" then
				return test_helper.make_companion_spawner_extension({
					should_have_companion = true,
					companion_units = { { name = "dog" } },
				})
			end
			if ext == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "renegade_captain",
					tags = { elite = true },
				})
			end
			return nil
		end

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		-- Should not crash
		CompanionTag.update(bot_unit, blackboard)
	end)

	-- ── Debug logging ─────────────────────────────────────────────

	it("logs successful companion tag at debug level", function()
		reinit({ debug = true })

		local elite = { name = "elite_unit" }
		setup_full_env({
			breeds = {
				[elite] = { name = "renegade_captain", tags = { elite = true } },
			},
		})

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		assert.spy(debug_log_mock).was_called()
	end)

	it("warns once when smart_tag_system lookup fails", function()
		local elite = { name = "elite_unit" }

		_G.ScriptUnit.has_extension = function(unit, ext)
			if unit == bot_unit and ext == "companion_spawner_system" then
				return test_helper.make_companion_spawner_extension({
					should_have_companion = true,
					companion_units = { { name = "dog" } },
				})
			end
			if ext == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "renegade_captain",
					tags = { elite = true },
				})
			end
			if ext == "smart_tag_system" then
				return test_helper.make_smart_tag_extension(nil)
			end
			if ext == "perception_system" then
				return test_helper.make_minion_perception_extension({
					has_line_of_sight = true,
				})
			end
			return nil
		end

		_G.Managers.state.extension.system = function()
			error("missing smart_tag_system")
		end

		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		CompanionTag.update(bot_unit, blackboard)
		current_time = 3.0
		CompanionTag.update(bot_unit, blackboard)

		assert.spy(mod_mock.warning).was_called(1)
	end)
end)
