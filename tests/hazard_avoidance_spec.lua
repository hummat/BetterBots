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
		is_hazard_movement_avoidance_enabled = function()
			return opts.hazard_enabled ~= false
		end,
		hazard_avoidance_buffer = function()
			return opts.hazard_buffer or 1.5
		end,
		nav_queries = opts.nav_queries,
	})
end

describe("hazard_avoidance diagnostics", function()
	local saved_position_lookup
	local saved_unit
	local saved_managers
	local saved_quaternion
	local saved_vector3

	before_each(function()
		saved_position_lookup = _G.POSITION_LOOKUP
		saved_unit = _G.Unit
		saved_managers = _G.Managers
		saved_quaternion = _G.Quaternion
		saved_vector3 = _G.Vector3

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

	after_each(function()
		_G.POSITION_LOOKUP = saved_position_lookup
		_G.Unit = saved_unit
		_G.Managers = saved_managers
		_G.Quaternion = saved_quaternion
		_G.Vector3 = saved_vector3
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

	it("emits a buffered threat from the explosion node when a barrel starts fusing", function()
		local logs = {}
		local calls = {}
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
		}
		_G.POSITION_LOOKUP[unit] = vector(0, 0, 0)
		_G.Quaternion = {
			identity = function()
				return "identity"
			end,
		}
		_G.Managers = {
			state = {
				extension = {
					system = function(_, name)
						if name == "side_system" then
							return {
								sides = function()
									return { "heroes" }
								end,
							}
						elseif name == "group_system" then
							return {
								bot_groups_from_sides = function(_, sides)
									assert.equals("heroes", sides[1])
									return {
										{
											aoe_threat_created = function(_, position, shape, size, rotation, duration)
												calls[#calls + 1] = {
													position = position,
													shape = shape,
													size = size,
													rotation = rotation,
													duration = duration,
												}
											end,
										},
									}
								end,
							}
						end
						return nil
					end,
				},
			},
		}

		init_module(logs, { hazard_buffer = 1.5 })
		HazardAvoidance.install_hazard_prop_hooks(HazardPropExtension)
		HazardPropExtension.set_current_state(instance, "triggered")

		assert.equals(1, #calls)
		assert.equals(2, calls[1].position.x)
		assert.equals(0, calls[1].position.y)
		assert.equals(0, calls[1].position.z)
		assert.equals("sphere", calls[1].shape)
		assert.equals(7.5, calls[1].size)
		assert.equals("identity", calls[1].rotation)
		assert.equals(3, calls[1].duration)
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

	it("cancels movement and pending dodge when projected endpoint leaves safe nav", function()
		local logs = {}
		local unit = { slot = "bot_1" }
		_G.POSITION_LOOKUP[unit] = vector(0, 0, 0)
		_G.Quaternion = {
			right = function()
				return vector(1, 0, 0)
			end,
			forward = function()
				return vector(0, 1, 0)
			end,
		}
		_G.Vector3 = function(x, y, z)
			return vector(x, y, z)
		end
		local instance = {
			_betterbots_player_unit = unit,
			_dodge = true,
			_move = { x = 0, y = 1 },
			_first_person_component = {
				rotation = "rotation",
			},
			_navigation_extension = {
				_nav_world = "nav",
				_traverse_logic = "traverse",
			},
		}

		init_module(logs, {
			nav_queries = {
				ray_can_go = function()
					return false, vector(0, 0, 0), vector(0, 2, -2)
				end,
			},
		})
		HazardAvoidance.on_bot_input_movement_updated(instance, unit)

		assert.equals(0, instance._move.x)
		assert.equals(0, instance._move.y)
		assert.is_false(instance._dodge)
		assert.equals("ledge_ray_blocked", instance._bb_movement_safety_blocked)
		assert.is_truthy(logs[1]:find("movement safety blocked", 1, true))
	end)
end)
