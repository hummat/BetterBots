local PingSystem = require("scripts.mods.BetterBots.ping_system")
local test_helper = require("tests.test_helper")

describe("ping_system", function()
	local mod_mock, debug_log_mock, fixed_time_mock, bot_unit
	local current_time = 0

	local function reinit_with_debug(enabled)
		PingSystem.init({
			mod = mod_mock,
			debug_log = debug_log_mock,
			debug_enabled = function()
				return enabled
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

		reinit_with_debug(false)

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

	it("does not crash when Managers.state is nil", function()
		_G.Managers.state = nil
		local elite = { name = "elite" }
		local blackboard = {
			perception = {
				priority_target_enemy = elite,
			},
		}

		-- Setup valid elite target
		_G.ScriptUnit.has_extension = function(_unit, ext)
			if ext == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(debug_log_mock).was_not_called()
	end)

	it("returns when no target exists", function()
		local blackboard = { perception = {} }
		PingSystem.update(bot_unit, blackboard)
		assert.spy(debug_log_mock).was_not_called()
	end)

	it("prioritizes priority_target_enemy", function()
		local priority_target = { name = "priority" }
		local opportunity_target = { name = "opportunity" }

		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
				opportunity_target_enemy = opportunity_target,
			},
		}

		local has_los_mock = spy.new(function()
			return true
		end)
		local tag_id_mock = spy.new(function()
			return nil
		end)
		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = tag_id_mock,
				}
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = has_los_mock }
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return { set_contextual_unit_tag = set_contextual_unit_tag_mock }
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)

		assert.spy(has_los_mock).was_called_with(match.is_table(), match.is_ref(bot_unit))
		assert
			.spy(set_contextual_unit_tag_mock)
			.was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(priority_target))
	end)

	it("falls back to next candidate if top priority is already tagged", function()
		local priority_target = { name = "priority" }
		local opportunity_target = { name = "opportunity" }

		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
				opportunity_target_enemy = opportunity_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return unit == priority_target and 123 or nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return { set_contextual_unit_tag = set_contextual_unit_tag_mock }
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)

		assert
			.spy(set_contextual_unit_tag_mock)
			.was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(opportunity_target))
	end)

	it("holds the current tagged target instead of flipping to a new one", function()
		local priority_target = { name = "priority" }
		local opportunity_target = { name = "opportunity" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
				opportunity_target_enemy = opportunity_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)
		local tag_state = {}

		POSITION_LOOKUP[bot_unit] = { x = 0, y = 0, z = 0 }
		POSITION_LOOKUP[priority_target] = { x = 20, y = 0, z = 0 }
		POSITION_LOOKUP[opportunity_target] = { x = 18, y = 0, z = 0 }

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return tag_state[unit]
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_contextual_unit_tag = function(_, user_unit, target_unit)
						tag_state[target_unit] = 123
						set_contextual_unit_tag_mock(_, user_unit, target_unit)
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)
		assert
			.spy(set_contextual_unit_tag_mock)
			.was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(priority_target))

		current_time = 0.1
		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)
	end)

	it("retags the same target after its previous tag expires", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)
		local tag_state = {}

		POSITION_LOOKUP[bot_unit] = { x = 0, y = 0, z = 0 }
		POSITION_LOOKUP[priority_target] = { x = 20, y = 0, z = 0 }

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return tag_state[unit]
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_contextual_unit_tag = function(_, user_unit, target_unit)
						tag_state[target_unit] = 123
						set_contextual_unit_tag_mock(_, user_unit, target_unit)
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)

		current_time = 0.1
		tag_state[priority_target] = nil
		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(2)
		assert
			.spy(set_contextual_unit_tag_mock)
			.was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(priority_target))
	end)

	it("allows immediate retag when a new target is much closer", function()
		local priority_target = { name = "priority" }
		local opportunity_target = { name = "opportunity" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
				opportunity_target_enemy = opportunity_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)
		local tag_state = {}

		POSITION_LOOKUP[bot_unit] = { x = 0, y = 0, z = 0 }
		POSITION_LOOKUP[priority_target] = { x = 20, y = 0, z = 0 }
		POSITION_LOOKUP[opportunity_target] = { x = 10, y = 0, z = 0 }

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return tag_state[unit]
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_contextual_unit_tag = function(_, user_unit, target_unit)
						tag_state[target_unit] = 123
						set_contextual_unit_tag_mock(_, user_unit, target_unit)
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)

		current_time = 0.1
		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(2)
		assert
			.spy(set_contextual_unit_tag_mock)
			.was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(opportunity_target))
	end)

	it("does not tag if no line of sight", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return false
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return { set_contextual_unit_tag = set_contextual_unit_tag_mock }
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_not_called()
	end)

	it("pings even if perception_system is missing", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { elite = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return { set_contextual_unit_tag = set_contextual_unit_tag_mock }
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)
	end)

	it("ignores enemy whose breed has no tags field", function()
		local blackboard = {
			perception = {
				priority_target_enemy = { name = "unknown" },
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({})
			elseif extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_not_called()
	end)

	it("ignores regular enemies for tagging in all slots", function()
		local blackboard = {
			perception = {
				priority_target_enemy = { name = "trash1" },
				opportunity_target_enemy = { name = "trash2" },
				urgent_target_enemy = { name = "trash3" },
				target_enemy = { name = "trash4" },
			},
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({ tags = { horde = true } })
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return { set_contextual_unit_tag = set_contextual_unit_tag_mock }
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_not_called()
	end)

	it("logs already-tagged suppression once at debug level", function()
		reinit_with_debug(true)

		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return 123
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "renegade_grenadier",
					tags = { elite = true },
				})
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		PingSystem.update(bot_unit, blackboard)

		assert.spy(debug_log_mock).was_called(1)
		assert.spy(debug_log_mock).was_called_with(
			"ping_system_skip:already_tagged:renegade_grenadier",
			0,
			"bot 1 skipped ping for renegade_grenadier (reason: already_tagged)"
		)
	end)

	it("logs no-line-of-sight suppression once at debug level", function()
		reinit_with_debug(true)

		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return false
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "cultist_flamer",
					tags = { special = true },
				})
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		PingSystem.update(bot_unit, blackboard)

		assert.spy(debug_log_mock).was_called(1)
		local expected_msg = "bot 1 skipped ping for cultist_flamer (reason: no_los)"
		assert.spy(debug_log_mock).was_called_with("ping_system_skip:no_los:cultist_flamer", 0, expected_msg)
	end)

	it("logs hold-last-tag suppression once at debug level", function()
		reinit_with_debug(true)

		local priority_target = { name = "priority" }
		local opportunity_target = { name = "opportunity" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
				opportunity_target_enemy = opportunity_target,
			},
		}

		local tag_state = {}
		local set_contextual_unit_tag_mock = spy.new(function() end)

		POSITION_LOOKUP[bot_unit] = { x = 0, y = 0, z = 0 }
		POSITION_LOOKUP[priority_target] = { x = 20, y = 0, z = 0 }
		POSITION_LOOKUP[opportunity_target] = { x = 18, y = 0, z = 0 }

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return tag_state[unit]
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = unit == priority_target and "renegade_grenadier" or "cultist_flamer",
					tags = { elite = true },
				})
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_contextual_unit_tag = function(_, user_unit, target_unit)
						tag_state[target_unit] = 123
						set_contextual_unit_tag_mock(_, user_unit, target_unit)
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		PingSystem.update(bot_unit, blackboard)

		assert.spy(set_contextual_unit_tag_mock).was_called(1)
		assert.spy(debug_log_mock).was_called_with(
			"ping_system_skip:hold_last_tag:cultist_flamer",
			0,
			"bot 1 skipped ping for cultist_flamer (reason: hold_last_tag)"
		)
	end)

	it("logs failure-backoff suppression once at debug level", function()
		reinit_with_debug(true)

		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "renegade_grenadier",
					tags = { elite = true },
				})
			end
			return nil
		end

		_G.Managers.state.extension.system = function(_, system_name)
			if system_name == "smart_tag_system" then
				return {
					set_contextual_unit_tag = function()
						error("boom")
					end,
				}
			end
			return nil
		end

		PingSystem.update(bot_unit, blackboard)
		current_time = 0.1
		PingSystem.update(bot_unit, blackboard)

		assert
			.spy(debug_log_mock)
			.was_called_with("ping_system_skip:failure_backoff", 0.1, "bot 1 skipped pinging (reason: failure_backoff)")
	end)

	it("warns once when smart_tag_system lookup fails", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			},
		}

		_G.ScriptUnit.has_extension = function(_unit, extension_name)
			if extension_name == "smart_tag_system" then
				return {
					tag_id = function()
						return nil
					end,
				}
			elseif extension_name == "perception_system" then
				return {
					has_line_of_sight = function()
						return true
					end,
				}
			elseif extension_name == "unit_data_system" then
				return test_helper.make_minion_unit_data_extension({
					name = "renegade_grenadier",
					tags = { elite = true },
				})
			end
			return nil
		end

		_G.Managers.state.extension.system = function()
			error("missing smart tag system")
		end

		PingSystem.update(bot_unit, blackboard)
		current_time = 0.1
		PingSystem.update(bot_unit, blackboard)

		assert.spy(mod_mock.warning).was_called(1)
	end)
end)
