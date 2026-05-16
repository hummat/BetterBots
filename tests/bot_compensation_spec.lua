local function load_module()
	local ok, module = pcall(dofile, "scripts/mods/BetterBots/bot_compensation.lua")
	assert.is_true(ok, "bot_compensation.lua should load")
	return module
end

local function setup_module(opts)
	local BotCompensation = load_module()
	local hooks = {}
	local hooks_by_target = {}
	local hook_counts = {}
	local logs = {}
	local bot_spawning = {}
	local minion_attack = {}
	local coop_game_mode = {}
	local expedition_game_mode = {}
	local opts_or_empty = opts or {}
	local stub_mod = {
		hook_require = function(_, path, callback)
			if path == "scripts/managers/bot/bot_spawning" then
				callback(bot_spawning)
			elseif path == "scripts/utilities/minion_attack" then
				callback(minion_attack)
			elseif path == "scripts/managers/game_mode/game_modes/game_mode_coop_complete_objective" then
				callback(coop_game_mode)
			elseif path == "scripts/managers/game_mode/game_modes/game_mode_expedition" then
				callback(expedition_game_mode)
			else
				error("unexpected hook_require path: " .. tostring(path))
			end
		end,
		hook = function(_, target, method_name, handler)
			hook_counts[method_name] = (hook_counts[method_name] or 0) + 1
			hooks_by_target[target] = hooks_by_target[target] or {}
			hooks_by_target[target][method_name] = handler
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
		bot_compensation_buff_enabled = function()
			return opts_or_empty.compensation_buff_enabled
		end,
		bot_incoming_damage_reduction_enabled = function()
			return opts_or_empty.damage_reduction_enabled
		end,
	})
	BotCompensation.register_hooks()

	return hooks,
		logs,
		BotCompensation,
		hook_counts,
		bot_spawning,
		minion_attack,
		hooks_by_target,
		coop_game_mode,
		expedition_game_mode
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

	it("logs the base-game bot config selection once when debug is enabled", function()
		local hooks, logs = setup_module({ config_override = nil, debug_enabled = true })

		local first_result = hooks.get_bot_config_identifier(function()
			return "high"
		end)
		local second_result = hooks.get_bot_config_identifier(function()
			return "high"
		end)

		assert.equals("high", first_result)
		assert.equals("high", second_result)
		assert.equals(1, #logs)
		assert.equals("bot_compensation:profile:base-game:high", logs[1].key)
		assert.equals("bot compensation profile base-game: high", logs[1].message)
		assert.equals("info", logs[1].level)
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

	it("does not force low bot config outside spawn-buff suppression when compensation buff is disabled", function()
		local hooks = setup_module({ config_override = nil, compensation_buff_enabled = false })
		local original_called = false

		local result = hooks.get_bot_config_identifier(function()
			original_called = true
			return "high"
		end)

		assert.is_true(original_called)
		assert.equals("high", result)
	end)

	it("suppresses only the bot spawn compensation buff when survivability is none", function()
		local hooks, logs, _, _, _, _, hooks_by_target, coop_game_mode =
			setup_module({ config_override = nil, compensation_buff_enabled = false, debug_enabled = true })
		local bot_player = {
			is_human_controlled = function()
				return false
			end,
		}
		local original_called = false
		local identifier_during_spawn

		local result = hooks_by_target[coop_game_mode].on_player_unit_spawn(function()
			original_called = true
			identifier_during_spawn = hooks.get_bot_config_identifier(function()
				return "high"
			end)
			return "spawned"
		end, "game_mode", bot_player, "bot_unit", false)

		local identifier_after_spawn = hooks.get_bot_config_identifier(function()
			return "high"
		end)

		assert.is_true(original_called)
		assert.equals("spawned", result)
		assert.equals("low", identifier_during_spawn)
		assert.equals("high", identifier_after_spawn)
		assert.equals(2, #logs)
		assert.equals("bot_compensation:profile:buff-suppressed:low", logs[1].key)
		assert.equals("bot compensation profile buff-suppressed: low", logs[1].message)
		assert.equals("bot_compensation:profile:base-game:high", logs[2].key)
	end)

	it("does not suppress spawn config selection for human players", function()
		local hooks, _, _, _, _, _, hooks_by_target, coop_game_mode =
			setup_module({ config_override = nil, compensation_buff_enabled = false })
		local human_player = {
			is_human_controlled = function()
				return true
			end,
		}
		local identifier_during_spawn

		hooks_by_target[coop_game_mode].on_player_unit_spawn(function()
			identifier_during_spawn = hooks.get_bot_config_identifier(function()
				return "high"
			end)
		end, "game_mode", human_player, "player_unit", false)

		assert.equals("high", identifier_during_spawn)
	end)

	it("logs the override bot config selection once when debug is enabled", function()
		local hooks, logs = setup_module({ config_override = "medium", debug_enabled = true })

		local first_result = hooks.get_bot_config_identifier(function()
			return "high"
		end)
		local second_result = hooks.get_bot_config_identifier(function()
			return "high"
		end)

		assert.equals("medium", first_result)
		assert.equals("medium", second_result)
		assert.equals(1, #logs)
		assert.equals("bot_compensation:profile:override:medium", logs[1].key)
		assert.equals("bot compensation profile override: medium", logs[1].message)
		assert.equals("info", logs[1].level)
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
		assert.equals(
			"suppressed base-game bot incoming damage modifier on ranged attack (" .. tostring(shoot_template) .. ")",
			logs[1].message
		)
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
		local _, _, BotCompensation, hook_counts, bot_spawning, minion_attack, _, coop_game_mode, expedition_game_mode =
			setup_module({ damage_reduction_enabled = false })

		BotCompensation.register_hooks()

		assert.equals(1, hook_counts.get_bot_config_identifier)
		assert.equals(1, hook_counts.shoot_hit_scan)
		assert.equals(1, hook_counts.melee)
		assert.equals(1, hook_counts.sweep)
		assert.equals(1, hook_counts.update_lag_compensation_melee)
		assert.equals(2, hook_counts.on_player_unit_spawn)
		assert.is_true(bot_spawning.__bb_bot_compensation_installed)
		assert.is_true(minion_attack.__bb_bot_compensation_installed)
		assert.is_true(coop_game_mode.__bb_bot_compensation_installed)
		assert.is_true(expedition_game_mode.__bb_bot_compensation_installed)
	end)
end)
