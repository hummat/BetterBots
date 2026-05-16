local function load_module()
	local ok, module = pcall(dofile, "scripts/mods/BetterBots/bot_compensation.lua")
	assert.is_true(ok, "bot_compensation.lua should load")
	return module
end

local function setup_module(opts)
	local BotCompensation = load_module()
	local hooks = {}
	local hook_counts = {}
	local logs = {}
	local bot_spawning = {}
	local minion_attack = {}
	local opts_or_empty = opts or {}
	local stub_mod = {
		hook_require = function(_, path, callback)
			if path == "scripts/managers/bot/bot_spawning" then
				callback(bot_spawning)
			elseif path == "scripts/utilities/minion_attack" then
				callback(minion_attack)
			else
				error("unexpected hook_require path: " .. tostring(path))
			end
		end,
		hook = function(_, _, method_name, handler)
			hook_counts[method_name] = (hook_counts[method_name] or 0) + 1
			hooks[method_name] = handler
		end,
	}

	BotCompensation.init({
		mod = stub_mod,
		debug_log = function(key, fixed_t, message, interval, level)
			logs[#logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
				interval = interval,
				level = level,
			}
		end,
		debug_enabled = function()
			return opts_or_empty.debug_enabled == true
		end,
		fixed_time = function()
			return 12.5
		end,
		bot_config_identifier_override = function()
			return opts_or_empty.config_override
		end,
		bot_incoming_damage_reduction_enabled = function()
			return opts_or_empty.damage_reduction_enabled
		end,
	})
	BotCompensation.register_hooks()

	return hooks, logs, BotCompensation, hook_counts, bot_spawning, minion_attack
end

describe("bot_compensation", function()
	it("preserves vanilla bot config selection when profile is auto", function()
		local hooks = setup_module({ config_override = nil })
		local original_called = false

		local result = hooks.get_bot_config_identifier(function()
			original_called = true
			return "high"
		end)

		assert.is_true(original_called)
		assert.equals("high", result)
	end)

	it("overrides vanilla bot config selection when a fixed profile is configured", function()
		local hooks = setup_module({ config_override = "medium" })
		local original_called = false

		local result = hooks.get_bot_config_identifier(function()
			original_called = true
			return "high"
		end)

		assert.is_false(original_called)
		assert.equals("medium", result)
	end)

	it("leaves ranged bot damage modifier intact when reduction is enabled", function()
		local hooks = setup_module({ damage_reduction_enabled = true })
		local shoot_template = { bot_power_level_modifier = 0.5 }
		local seen_modifier

		local result = hooks.shoot_hit_scan(function(_, _, _, _, _, _, _, incoming_template)
			seen_modifier = incoming_template.bot_power_level_modifier
			return "hit_position"
		end, nil, nil, "enemy", "bot", nil, nil, nil, shoot_template, nil, nil, nil)

		assert.equals(0.5, seen_modifier)
		assert.equals(0.5, shoot_template.bot_power_level_modifier)
		assert.equals("hit_position", result)
	end)

	it("clears and restores ranged bot damage modifier when reduction is disabled", function()
		local hooks, logs = setup_module({ damage_reduction_enabled = false, debug_enabled = true })
		local shoot_template = { bot_power_level_modifier = 0.5 }
		local seen_modifier

		local result = hooks.shoot_hit_scan(function(_, _, _, _, _, _, _, incoming_template)
			seen_modifier = incoming_template.bot_power_level_modifier
			return "hit_position"
		end, nil, nil, "enemy", "bot_unit", nil, nil, nil, shoot_template, nil, nil, nil)

		assert.is_nil(seen_modifier)
		assert.equals(0.5, shoot_template.bot_power_level_modifier)
		assert.equals("hit_position", result)
		assert.equals(1, #logs)
		assert.equals("bot_compensation:ranged:bot_unit", logs[1].key)
		assert.equals("info", logs[1].level)
	end)

	it("clears and restores melee bot damage modifier when reduction is disabled", function()
		local hooks = setup_module({ damage_reduction_enabled = false })
		local action_data = { bot_power_level_modifier = 0.5 }
		local seen_modifier

		local result = hooks.melee(function(_, _, _, _, _, incoming_action_data)
			seen_modifier = incoming_action_data.bot_power_level_modifier
			return true
		end, "enemy", nil, nil, nil, "bot", action_data, nil, nil, nil, nil)

		assert.is_nil(seen_modifier)
		assert.equals(0.5, action_data.bot_power_level_modifier)
		assert.is_true(result)
	end)

	it("clears and restores sweep bot damage modifier when reduction is disabled", function()
		local hooks = setup_module({ damage_reduction_enabled = false })
		local action_data = { bot_power_level_modifier = 0.5 }
		local seen_modifier

		local result = hooks.sweep(function(_, _, _, _, _, _, incoming_action_data)
			seen_modifier = incoming_action_data.bot_power_level_modifier
			return true
		end, "enemy", nil, nil, nil, nil, "bot", action_data, nil, nil, nil, nil, nil)

		assert.is_nil(seen_modifier)
		assert.equals(0.5, action_data.bot_power_level_modifier)
		assert.is_true(result)
	end)

	it("clears and restores lag-compensation melee bot damage modifier when reduction is disabled", function()
		local hooks = setup_module({ damage_reduction_enabled = false })
		local action_data = { bot_power_level_modifier = 0.5 }
		local scratchpad = { lag_compensation_target_unit = "bot_unit" }
		local seen_modifier

		hooks.update_lag_compensation_melee(function(_, _, _, _, _, incoming_action_data)
			seen_modifier = incoming_action_data.bot_power_level_modifier
		end, "enemy", nil, scratchpad, nil, 1.0, action_data)

		assert.is_nil(seen_modifier)
		assert.equals(0.5, action_data.bot_power_level_modifier)
	end)

	it("restores damage modifier after vanilla attack errors", function()
		local hooks = setup_module({ damage_reduction_enabled = false })
		local action_data = { bot_power_level_modifier = 0.5 }

		local ok, err = pcall(function()
			hooks.melee(function()
				error("vanilla failure")
			end, "enemy", nil, nil, nil, "bot", action_data, nil, nil, nil, nil)
		end)

		assert.is_false(ok)
		assert.matches("vanilla failure", err)
		assert.equals(0.5, action_data.bot_power_level_modifier)
	end)

	it("does not double-install hooks when register_hooks runs twice against the same engine tables", function()
		local _, _, BotCompensation, hook_counts, bot_spawning, minion_attack =
			setup_module({ damage_reduction_enabled = false })

		BotCompensation.register_hooks()

		assert.equals(1, hook_counts.get_bot_config_identifier)
		assert.equals(1, hook_counts.shoot_hit_scan)
		assert.equals(1, hook_counts.melee)
		assert.equals(1, hook_counts.sweep)
		assert.equals(1, hook_counts.update_lag_compensation_melee)
		assert.is_true(bot_spawning.__bb_bot_compensation_installed)
		assert.is_true(minion_attack.__bb_bot_compensation_installed)
	end)
end)
