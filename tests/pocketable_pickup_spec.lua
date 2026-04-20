local test_helper = require("tests.test_helper")

local function load_module()
	local ok, module_or_err = pcall(dofile, "scripts/mods/BetterBots/pocketable_pickup.lua")
	return ok, module_or_err
end

describe("pocketable_pickup", function()
	local PocketablePickup
	local ok
	local debug_logs
	local queued_inputs
	local fixed_t
	local state_by_unit
	local build_context_result
	local unit
	local human_units
	local extension_map
	local inventory_component
	local carried_templates
	local pickups
	local saved_script_unit

	local function init_module()
		ok, PocketablePickup = load_module()
		assert.is_true(ok, tostring(PocketablePickup))

		PocketablePickup.init({
			mod = {},
			debug_log = function(key, _t, message)
				debug_logs[#debug_logs + 1] = {
					key = key,
					message = message,
				}
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return fixed_t
			end,
			state_by_unit = state_by_unit,
			build_context = function()
				return build_context_result
			end,
			pickups = pickups,
			is_enabled = function()
				return true
			end,
			human_units = function()
				return human_units
			end,
			script_unit_has_extension = function(target_unit, system_name)
				local exts = extension_map[target_unit]
				return exts and exts[system_name] or nil
			end,
			visual_loadout_api = {
				weapon_template_from_slot = function(_, slot_name)
					return carried_templates[slot_name]
				end,
			},
			health_module = {
				current_health_percent = function(target_unit)
					return target_unit.health_pct
				end,
				permanent_damage_taken_percent = function(target_unit)
					return target_unit.corruption_pct or 0
				end,
			},
			ammo_module = {
				uses_ammo = function(target_unit)
					return target_unit.uses_ammo == true
				end,
				current_total_percentage = function(target_unit)
					return target_unit.ammo_pct
				end,
			},
			unit_get_data = function(target_unit, key)
				return target_unit and target_unit[key]
			end,
		})
	end

	before_each(function()
		saved_script_unit = rawget(_G, "ScriptUnit")
		debug_logs = {}
		queued_inputs = {}
		fixed_t = 10
		state_by_unit = {}
		build_context_result = test_helper.make_context()
		unit = "bot_unit"
		human_units = {}
		pickups = {
			by_name = {
				ammo_cache_pocketable = {
					name = "ammo_cache_pocketable",
					inventory_slot_name = "slot_pocketable",
				},
				medical_crate_pocketable = {
					name = "medical_crate_pocketable",
					inventory_slot_name = "slot_pocketable",
				},
				syringe_power_boost_pocketable = {
					name = "syringe_power_boost_pocketable",
					inventory_slot_name = "slot_pocketable_small",
				},
			},
		}
		inventory_component = {
			wielded_slot = "slot_primary",
			slot_pocketable = "medical_item",
			slot_pocketable_small = "stim_item",
		}
		carried_templates = {
			slot_pocketable = {
				pickup_name = "medical_crate_pocketable",
				action_inputs = {
					place = {},
				},
			},
			slot_pocketable_small = {
				pickup_name = "syringe_power_boost_pocketable",
				action_inputs = {
					use_self = {},
				},
			},
		}
		extension_map = {
			[unit] = {
				action_input_system = test_helper.make_player_action_input_extension({
					bot_queue_action_input = function(_self, component, input_name, raw_input)
						queued_inputs[#queued_inputs + 1] = {
							component = component,
							input = input_name,
							raw_input = raw_input,
						}
					end,
				}),
				unit_data_system = test_helper.make_player_unit_data_extension({
					inventory = inventory_component,
				}),
				visual_loadout_system = {},
			},
		}
		_G.ScriptUnit = test_helper.make_script_unit_mock(extension_map)
	end)

	after_each(function()
		_G.ScriptUnit = saved_script_unit
	end)

	it("loads", function()
		ok, PocketablePickup = load_module()
		assert.is_true(ok, tostring(PocketablePickup))
	end)

	it("patches supported pocketable pickup metadata into mule slots", function()
		init_module()

		PocketablePickup.patch_pickups()

		assert.is_true(pickups.by_name.ammo_cache_pocketable.bots_mule_pickup)
		assert.equals("slot_pocketable", pickups.by_name.ammo_cache_pocketable.slot_name)
		assert.is_true(pickups.by_name.medical_crate_pocketable.bots_mule_pickup)
		assert.equals("slot_pocketable_small", pickups.by_name.syringe_power_boost_pocketable.slot_name)
	end)

	it("leaves supported pocketables for humans when a matching slot is empty", function()
		init_module()

		human_units = {
			{ inventory = { slot_pocketable = "not_equipped", slot_pocketable_small = "stim_item" } },
		}

		local allowed, reason =
			PocketablePickup.should_allow_mule_pickup(unit, { pickup_type = "medical_crate_pocketable" }, nil, nil)

		assert.is_false(allowed)
		assert.equals("human_slot_open", reason)
	end)

	it("allows ordered pocketables even when a human matching slot is empty", function()
		init_module()
		local pickup_unit = { pickup_type = "syringe_power_boost_pocketable" }

		human_units = {
			{ inventory = { slot_pocketable = "crate_item", slot_pocketable_small = "not_equipped" } },
		}

		local allowed, reason = PocketablePickup.should_allow_mule_pickup(unit, pickup_unit, nil, {
			pickup_orders = {
				slot_pocketable_small = {
					unit = pickup_unit,
				},
			},
		})

		assert.is_true(allowed)
		assert.is_nil(reason)
	end)

	it("queues wield then self-use for a carried combat stim in high-threat combat", function()
		init_module()

		build_context_result = test_helper.make_context({
			num_nearby = 4,
			challenge_rating_sum = 8,
			target_is_elite_special = true,
		})

		PocketablePickup.try_queue(unit, { perception = {} })
		assert.same({
			component = "weapon_action",
			input = "wield",
			raw_input = "wield_4",
		}, queued_inputs[1])

		inventory_component.wielded_slot = "slot_pocketable_small"
		fixed_t = fixed_t + 0.1
		PocketablePickup.try_queue(unit, { perception = {} })

		assert.same({
			component = "weapon_action",
			input = "use_self",
		}, queued_inputs[2])
	end)

	it("queues wield then deploy for a carried medical crate when the team needs healing", function()
		init_module()

		human_units = {
			{
				health_pct = 0.45,
				corruption_pct = 0.1,
				inventory = {
					slot_pocketable = "crate_item",
					slot_pocketable_small = "stim_item",
				},
			},
		}
		build_context_result = test_helper.make_context({
			num_nearby = 0,
			allies_in_coherency = 2,
		})
		inventory_component.slot_pocketable_small = "not_equipped"

		PocketablePickup.try_queue(unit, { perception = {} })
		assert.same({
			component = "weapon_action",
			input = "wield",
			raw_input = "wield_3",
		}, queued_inputs[1])

		inventory_component.wielded_slot = "slot_pocketable"
		fixed_t = fixed_t + 0.1
		PocketablePickup.try_queue(unit, { perception = {} })

		assert.same({
			component = "weapon_action",
			input = "place",
			raw_input = nil,
		}, queued_inputs[2])
	end)

	it("does not report success when the carried slot empties without a confirmed use transition", function()
		init_module()

		build_context_result = test_helper.make_context({
			num_nearby = 4,
			challenge_rating_sum = 8,
			target_is_elite_special = true,
		})

		PocketablePickup.try_queue(unit, { perception = {} })
		inventory_component.wielded_slot = "slot_pocketable_small"
		fixed_t = fixed_t + 0.1
		PocketablePickup.try_queue(unit, { perception = {} })

		inventory_component.slot_pocketable_small = "not_equipped"
		PocketablePickup.try_queue(unit, { perception = {} })

		for i = 1, #debug_logs do
			assert.is_nil(string.find(debug_logs[i].message, "pocketable use completed", 1, true))
		end
	end)

	it("reports success after the carried slot empties and the bot unwields the pocketable", function()
		init_module()

		build_context_result = test_helper.make_context({
			num_nearby = 4,
			challenge_rating_sum = 8,
			target_is_elite_special = true,
		})

		PocketablePickup.try_queue(unit, { perception = {} })
		inventory_component.wielded_slot = "slot_pocketable_small"
		fixed_t = fixed_t + 0.1
		PocketablePickup.try_queue(unit, { perception = {} })

		inventory_component.slot_pocketable_small = "not_equipped"
		inventory_component.wielded_slot = "slot_primary"
		PocketablePickup.try_queue(unit, { perception = {} })

		assert.is_truthy(debug_logs[#debug_logs].message:find("pocketable use completed", 1, true))
	end)

	-- Static-source check. Every cooldown-form _reset_state(state, <expr>) call MUST be
	-- followed by `return` so the retry-delay actually defers the next attempt. Falling
	-- through leaves a stale state.next_try_t that silently suppresses wield-timeout
	-- monitoring on the following tick. See GitHub comment on pocketable_pickup.lua:510
	-- and the bug-catch-audit rule in CLAUDE.md.
	it("pairs every _reset_state cooldown call with a return", function()
		local path = "scripts/mods/BetterBots/pocketable_pickup.lua"
		local handle = assert(io.open(path, "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		local lines = {}
		for line in (source .. "\n"):gmatch("([^\n]*)\n") do
			lines[#lines + 1] = line
		end

		local function is_trivial(line)
			local trimmed = line:match("^%s*(.-)%s*$") or ""
			if trimmed == "" then
				return true
			end
			if trimmed:sub(1, 2) == "--" then
				return true
			end
			-- Block terminator; control falls through to the statement below.
			if trimmed == "end" then
				return true
			end
			return false
		end

		local function first_word(line)
			local trimmed = line:match("^%s*(.-)%s*$") or ""
			return trimmed:match("^(%w+)")
		end

		local violations = {}
		for i, line in ipairs(lines) do
			-- Two-arg form sets state.next_try_t. One-arg form (no comma) is the cancel
			-- path at line ~504 and handled by the surrounding block's explicit return.
			local is_declaration = line:find("function%s+_reset_state") ~= nil
			if not is_declaration and line:find("_reset_state%(state,") then
				local follower_idx
				for j = i + 1, #lines do
					if not is_trivial(lines[j]) then
						follower_idx = j
						break
					end
				end

				if not follower_idx or first_word(lines[follower_idx]) ~= "return" then
					violations[#violations + 1] = string.format(
						"line %d: `%s` is not followed by `return` (next statement at line %s: `%s`)",
						i,
						line:match("^%s*(.-)%s*$") or line,
						tostring(follower_idx),
						follower_idx and (lines[follower_idx]:match("^%s*(.-)%s*$") or lines[follower_idx]) or "<EOF>"
					)
				end
			end
		end

		assert.equals(
			0,
			#violations,
			"pocketable_pickup.lua has cooldown resets without a terminating return:\n  "
				.. table.concat(violations, "\n  ")
		)
	end)
end)
