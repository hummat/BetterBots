local PingSystem = require("scripts.mods.BetterBots.ping_system")
local test_helper = require("tests.test_helper")

describe("ping_system", function()
	local mod_mock, debug_log_mock, fixed_time_mock, bot_unit
	local current_time = 0

	before_each(function()
		current_time = 0
		bot_unit = { name = "bot_unit" }
		fixed_time_mock = function()
			return current_time
		end
		mod_mock = {}
		debug_log_mock = spy.new(function() end)

		PingSystem.init({
			mod = mod_mock,
			debug_log = debug_log_mock,
			fixed_time = fixed_time_mock,
			bot_slot_for_unit = function() return 1 end,
		})

		_G.Unit = {
			alive = function(unit) return unit ~= nil end
		}
		_G.ScriptUnit = {
			has_extension = function() return nil end
		}
		_G.Managers = {
			state = {
				extension = {
					system = function() return nil end
				}
			}
		}
	end)

	it("returns nil when no target exists", function()
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
			}
		}

		local has_los_mock = spy.new(function() return true end)
		local tag_id_mock = spy.new(function() return nil end)
		local contextual_tag_template_mock = spy.new(function() return { name = "enemy_over_here" } end)
		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = tag_id_mock, contextual_tag_template = contextual_tag_template_mock }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = has_los_mock }
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
		assert.spy(set_contextual_unit_tag_mock).was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(priority_target))
	end)

	it("respects cooldown", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			}
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = function() return nil end, contextual_tag_template = function() return { name = "enemy_over_here" } end }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = function() return true end }
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

		-- Should not fire again immediately
		current_time = 1.0
		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(1)

		-- Should fire after cooldown
		current_time = 2.1
		PingSystem.update(bot_unit, blackboard)
		assert.spy(set_contextual_unit_tag_mock).was_called(2)
	end)

	it("does not tag if target already has tag_id", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			}
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = function() return 123 end, contextual_tag_template = function() return { name = "enemy_over_here" } end }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = function() return true end }
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

	it("does not tag if no line of sight", function()
		local priority_target = { name = "priority" }
		local blackboard = {
			perception = {
				priority_target_enemy = priority_target,
			}
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = function() return nil end, contextual_tag_template = function() return { name = "enemy_over_here" } end }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = function() return false end }
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

	it("detects elite targets when fallback to target_enemy", function()
		local target_enemy = { name = "crusher" }
		local blackboard = {
			perception = {
				target_enemy = target_enemy,
			}
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = function() return nil end, contextual_tag_template = function() return { name = "enemy_over_here" } end }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = function() return true end }
			elseif extension_name == "unit_data_system" then
				return { breed = function() return { tags = { elite = true } } end }
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
		assert.spy(set_contextual_unit_tag_mock).was_called_with(match.is_table(), match.is_ref(bot_unit), match.is_ref(target_enemy))
	end)

	it("ignores regular enemies for tagging", function()
		local target_enemy = { name = "poxwalker" }
		local blackboard = {
			perception = {
				target_enemy = target_enemy,
			}
		}

		local set_contextual_unit_tag_mock = spy.new(function() end)

		_G.ScriptUnit.has_extension = function(unit, extension_name)
			if extension_name == "smart_tag_system" then
				return { tag_id = function() return nil end, contextual_tag_template = function() return { name = "enemy_over_here" } end }
			elseif extension_name == "perception_system" then
				return { has_line_of_sight = function() return true end }
			elseif extension_name == "unit_data_system" then
				return { breed = function() return { tags = { horde = true } } end }
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
end)