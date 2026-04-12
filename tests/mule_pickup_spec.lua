local MulePickup = dofile("scripts/mods/BetterBots/mule_pickup.lua")

local function make_pickups()
	return {
		by_name = {
			tome = {
				name = "tome",
				inventory_slot_name = "slot_pocketable",
			},
			grimoire = {
				name = "grimoire",
				inventory_slot_name = "slot_pocketable",
			},
		},
	}
end

describe("mule_pickup", function()
	local pickups
	local enabled
	local debug_logs
	local fake_mod

	local function find_debug_log(fragment)
		for i = 1, #debug_logs do
			if debug_logs[i].message:find(fragment, 1, true) then
				return debug_logs[i]
			end
		end

		return nil
	end

	setup(function()
		_G.math = _G.math or math
	end)

	before_each(function()
		pickups = make_pickups()
		enabled = false
		debug_logs = {}
		fake_mod = {
			hook_require = function(_, _, callback)
				callback({
					pickup = function(bot_unit, pickup_unit, ordering_player)
						return {
							bot_unit = bot_unit,
							pickup_unit = pickup_unit,
							ordering_player = ordering_player,
						}
					end,
				})
			end,
			hook = function(_, target, method_name, handler)
				local original = target[method_name]
				target[method_name] = function(...)
					return handler(original, ...)
				end
				if method_name == "pickup" then
					fake_mod._hooked_order = target[method_name]
				end
			end,
			hook_safe = function(_, target, method_name, handler)
				local original = target[method_name]
				target[method_name] = function(...)
					local result = original(...)
					handler(...)
					return result
				end
			end,
		}

		MulePickup.init({
			mod = fake_mod,
			debug_enabled = function()
				return true
			end,
			debug_log = function(key, _t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					message = message,
				}
			end,
			is_grimoire_pickup_enabled = function()
				return enabled
			end,
			pickups = pickups,
			unit_get_data = function(unit, key)
				return unit and unit[key]
			end,
		})
	end)

	it("patches tome pickup metadata for vanilla mule flow", function()
		MulePickup.patch_pickups()

		assert.equals("slot_pocketable", pickups.by_name.tome.slot_name)
		assert.is_true(pickups.by_name.tome.bots_mule_pickup)
	end)

	it("keeps grimoire pickup disabled by default", function()
		MulePickup.patch_pickups()

		assert.equals("slot_pocketable", pickups.by_name.grimoire.slot_name)
		assert.is_false(pickups.by_name.grimoire.bots_mule_pickup)
	end)

	it("enables grimoire mule pickup when setting is on", function()
		enabled = true

		MulePickup.patch_pickups()

		assert.is_true(pickups.by_name.grimoire.bots_mule_pickup)
	end)

	it("clears live grimoire mule pickup when setting is off", function()
		local pickup_component = {
			mule_pickup = { pickup_type = "grimoire" },
			mule_pickup_distance = 4,
		}

		local changed = MulePickup.sanitize_mule_pickup(pickup_component, "bot_1")

		assert.is_true(changed)
		assert.is_nil(pickup_component.mule_pickup)
		assert.equals(math.huge, pickup_component.mule_pickup_distance)
		assert.is_truthy(find_debug_log("blocked grimoire mule pickup"))
	end)

	it("preserves non-grimoire mule pickup when setting is off", function()
		local pickup_component = {
			mule_pickup = { pickup_type = "tome" },
			mule_pickup_distance = 4,
		}

		local changed = MulePickup.sanitize_mule_pickup(pickup_component)

		assert.is_false(changed)
		assert.equals("tome", pickup_component.mule_pickup.pickup_type)
		assert.equals(4, pickup_component.mule_pickup_distance)
	end)

	it("blocks grimoire pickup orders when setting is off", function()
		local result

		MulePickup.register_hooks()

		result = fake_mod._hooked_order and fake_mod._hooked_order("bot", { pickup_type = "grimoire" }, "player")

		assert.is_nil(result)
		assert.is_truthy(find_debug_log("blocked grimoire pickup order"))
	end)

	it("allows grimoire pickup orders when setting is on", function()
		enabled = true

		MulePickup.register_hooks()

		local result = fake_mod._hooked_order("bot", { pickup_type = "grimoire" }, "player")

		assert.same({
			bot_unit = "bot",
			pickup_unit = { pickup_type = "grimoire" },
			ordering_player = "player",
		}, result)
	end)
end)
