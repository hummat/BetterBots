local HazardAvoidance = dofile("scripts/mods/BetterBots/hazard_avoidance.lua")

local function make_hooking_mod()
	return {
		hook = function(_, target, method_name, handler)
			local original = target[method_name]
			target[method_name] = function(...)
				return handler(original, ...)
			end
		end,
	}
end

local function vector(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

local function vector_box(value)
	return {
		unbox = function()
			return value
		end,
	}
end

local function init_module(logs, opts)
	opts = opts or {}
	HazardAvoidance.init({
		mod = make_hooking_mod(),
		debug_enabled = function()
			return opts.debug_enabled ~= false
		end,
		debug_log = function(_key, _t, message)
			logs[#logs + 1] = message
		end,
		fixed_time = function()
			return opts.fixed_time or 10
		end,
		bot_slot_for_unit = function(unit)
			return unit.slot or "?"
		end,
	})
end

describe("hazard_avoidance diagnostics", function()
	before_each(function()
		_G.POSITION_LOOKUP = {}
		_G.Unit = {
			has_node = function(_unit, node_name)
				return node_name == "c_explosion"
			end,
			node = function(_unit, node_name)
				return node_name
			end,
			world_position = function(unit, node_name)
				return unit.node_positions and unit.node_positions[node_name] or vector()
			end,
		}
	end)

	it("logs fused barrel trigger positions and explosion radius", function()
		local logs = {}
		local unit = {
			node_positions = {
				c_explosion = vector(2, 0, 0),
			},
		}
		local HazardPropExtension = {
			set_current_state = function(self, state)
				self.state = state
			end,
		}
		local instance = {
			_unit = unit,
			_content = {
				explosion_template = {
					radius = 6,
				},
			},
			broadphase_position = function()
				return vector(1, 0, 0)
			end,
		}
		_G.POSITION_LOOKUP[unit] = vector(0, 0, 0)

		init_module(logs)
		HazardAvoidance.install_hazard_prop_hooks(HazardPropExtension)
		HazardPropExtension.set_current_state(instance, "triggered")

		assert.equals(1, #logs)
		assert.is_truthy(logs[1]:find("hazard_prop triggered", 1, true))
		assert.is_truthy(logs[1]:find("radius=6", 1, true))
		assert.is_truthy(logs[1]:find("position=(0.00,0.00,0.00)", 1, true))
		assert.is_truthy(logs[1]:find("broadphase=(1.00,0.00,0.00)", 1, true))
		assert.is_truthy(logs[1]:find("explosion=(2.00,0.00,0.00)", 1, true))
	end)

	it("logs accepted, skipped, and missed vanilla AoE threats per bot", function()
		local logs = {}
		local accepted_unit = { slot = "bot_1" }
		local skipped_unit = { slot = "bot_2" }
		local missed_unit = { slot = "bot_3" }
		local BotGroup = {
			aoe_threat_created = function(self, _position, _shape, _size, _rotation, duration)
				local expires = self._t + duration
				self._bot_data[accepted_unit].aoe_threat.expires = expires
				self._bot_data[accepted_unit].aoe_threat.escape_direction = vector_box(vector(1, 0, 0))
			end,
		}
		local instance = {
			_t = 10,
			_bot_data = {
				[accepted_unit] = {
					aoe_threat = {
						expires = 4,
						escape_direction = vector_box(vector()),
					},
				},
				[skipped_unit] = {
					aoe_threat = {
						expires = 30,
						escape_direction = vector_box(vector(0, 1, 0)),
					},
				},
				[missed_unit] = {
					aoe_threat = {
						expires = 4,
						escape_direction = vector_box(vector()),
					},
				},
			},
		}

		init_module(logs)
		HazardAvoidance.install_bot_group_hooks(BotGroup)
		BotGroup.aoe_threat_created(instance, vector(), "sphere", 6, nil, 3)

		assert.equals(3, #logs)
		assert.is_truthy(table.concat(logs, "\n"):find("aoe_threat accepted unit=bot_1", 1, true))
		assert.is_truthy(table.concat(logs, "\n"):find("aoe_threat skipped unit=bot_2", 1, true))
		assert.is_truthy(table.concat(logs, "\n"):find("aoe_threat missed unit=bot_3", 1, true))
	end)

	it("logs when BotUnitInput consumes an AoE threat for movement", function()
		local logs = {}
		local unit = { slot = "bot_1" }
		local instance = {
			_betterbots_player_unit = unit,
			_avoiding_aoe_threat = true,
			_move = vector(0, -1, 0),
			_group_extension = {
				bot_group_data = function()
					return {
						aoe_threat = {
							expires = 12,
							escape_direction = vector_box(vector(0, -1, 0)),
						},
					}
				end,
			},
		}

		init_module(logs)
		HazardAvoidance.on_bot_input_movement_updated(instance, unit)

		assert.equals(1, #logs)
		assert.is_truthy(logs[1]:find("aoe_threat consumed unit=bot_1", 1, true))
		assert.is_truthy(logs[1]:find("remaining=2.00", 1, true))
		assert.is_truthy(logs[1]:find("move=(0.00,-1.00,0.00)", 1, true))
	end)
end)
