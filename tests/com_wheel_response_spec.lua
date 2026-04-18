local ComWheelResponse = dofile("scripts/mods/BetterBots/com_wheel_response.lua")

describe("com_wheel_response", function()
	local fixed_t
	local hook_require_callbacks
	local hook_registrations
	local players_by_unit
	local human_unit
	local bot_unit

	local function install_module()
		hook_require_callbacks = {}
		hook_registrations = {}
		players_by_unit = {}
		human_unit = { name = "human" }
		bot_unit = { name = "bot" }
		fixed_t = 10

		_G.Managers = {
			player = {
				player_by_unit = function(_, unit)
					return players_by_unit[unit]
				end,
			},
		}

		ComWheelResponse.init({
			mod = {
				hook_require = function(_, path, callback)
					hook_require_callbacks[path] = callback
				end,
				hook = function(_, target, method_name, handler)
					hook_registrations[#hook_registrations + 1] = {
						target = target,
						method = method_name,
						handler = handler,
					}
				end,
			},
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return fixed_t
			end,
			is_enabled = function()
				return true
			end,
		})
		players_by_unit[human_unit] = {
			is_human_controlled = function()
				return true
			end,
		}
		players_by_unit[bot_unit] = {
			is_human_controlled = function()
				return false
			end,
		}
	end

	before_each(function()
		install_module()
	end)

	it("temporarily overrides the behavior profile to aggressive after battle cry", function()
		ComWheelResponse.record_trigger(human_unit, "com_cheer")

		assert.equals("aggressive", ComWheelResponse.override_behavior_profile("balanced"))

		fixed_t = fixed_t + 6

		assert.is_nil(ComWheelResponse.override_behavior_profile("balanced"))
	end)

	it("tracks recent ammo and health requests for the requesting human", function()
		ComWheelResponse.record_trigger(human_unit, "com_need_ammo")
		ComWheelResponse.record_trigger(human_unit, "com_need_health")

		assert.is_true(ComWheelResponse.has_recent_ammo_request({ human_unit }))
		assert.is_true(ComWheelResponse.has_recent_health_request({ human_unit }))

		fixed_t = fixed_t + 11

		assert.is_false(ComWheelResponse.has_recent_ammo_request({ human_unit }))
		assert.is_false(ComWheelResponse.has_recent_health_request({ human_unit }))
	end)

	it("ignores non-human trigger sources", function()
		ComWheelResponse.record_trigger(bot_unit, "com_cheer")
		ComWheelResponse.record_trigger(bot_unit, "com_need_ammo")

		assert.is_nil(ComWheelResponse.override_behavior_profile("balanced"))
		assert.is_false(ComWheelResponse.has_recent_ammo_request({ human_unit }))
	end)

	it("registers the VO hook once per shared Vo table", function()
		ComWheelResponse.register_hooks()

		local callback = hook_require_callbacks["scripts/utilities/vo"]
		assert.is_function(callback)

		local target = {
			on_demand_vo_event = function() end,
		}

		callback(target)
		callback(target)

		assert.equals(1, #hook_registrations)
		assert.equals(target, hook_registrations[1].target)
		assert.equals("on_demand_vo_event", hook_registrations[1].method)
	end)
end)
