local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _last_charge_event_by_unit

-- Late-bound cross-module refs, set via wire()
local _build_context
local _resolve_decision
local _enemy_breed
local _can_use_item_fallback

local function fmt_percent(value)
	if value == nil then
		return "n/a"
	end

	return string.format("%.2f", value)
end

local function fmt_seconds(value)
	if value == nil then
		return "n/a"
	end

	if value == math.huge then
		return "inf"
	end

	return string.format("%.2f", value)
end

local function _sanitize_dump_name_fragment(value)
	local fragment = tostring(value or "unknown")
	fragment = string.gsub(fragment, "[^%w_%-]", "_")

	return fragment
end

local function enemy_unit_label(enemy_unit)
	if not enemy_unit then
		return "none"
	end

	local breed = _enemy_breed(enemy_unit)

	return (breed and breed.name) or tostring(enemy_unit)
end

local function context_snapshot(context)
	if not context then
		return nil
	end

	return {
		num_nearby = context.num_nearby,
		challenge_rating_sum = context.challenge_rating_sum,
		elite_count = context.elite_count,
		special_count = context.special_count,
		monster_count = context.monster_count,
		ranged_count = context.ranged_count,
		melee_count = context.melee_count,
		health_pct = context.health_pct,
		toughness_pct = context.toughness_pct,
		peril_pct = context.peril_pct,
		target_enemy_distance = context.target_enemy_distance,
		target_enemy_type = context.target_enemy_type,
		target_enemy = enemy_unit_label(context.target_enemy),
		priority_target_enemy = enemy_unit_label(context.priority_target_enemy),
		opportunity_target_enemy = enemy_unit_label(context.opportunity_target_enemy),
		urgent_target_enemy = enemy_unit_label(context.urgent_target_enemy),
		target_ally_needs_aid = context.target_ally_needs_aid,
		target_ally_distance = context.target_ally_distance,
		target_is_elite_special = context.target_is_elite_special,
		target_is_monster = context.target_is_monster,
		target_is_super_armor = context.target_is_super_armor,
		allies_in_coherency = context.allies_in_coherency,
		avg_ally_toughness_pct = context.avg_ally_toughness_pct,
		max_ally_corruption_pct = context.max_ally_corruption_pct,
	}
end

local function fallback_state_snapshot(state, fixed_t)
	if not state then
		return {
			active = false,
			item_stage = "none",
		}
	end

	return {
		active = state.active == true,
		hold_until = state.hold_until,
		hold_remaining_s = state.hold_until and math.max(state.hold_until - fixed_t, 0) or nil,
		wait_action_input = state.wait_action_input,
		wait_sent = state.wait_sent == true,
		next_try_t = state.next_try_t,
		next_try_in_s = state.next_try_t and (state.next_try_t - fixed_t) or nil,
		item_stage = state.item_stage or "none",
		item_profile_name = state.item_profile_name,
		item_wait_t = state.item_wait_t,
		item_wait_in_s = state.item_wait_t and (state.item_wait_t - fixed_t) or nil,
		item_charge_confirmed = state.item_charge_confirmed == true,
		item_start_input = state.item_start_input,
		item_followup_input = state.item_followup_input,
		item_unwield_input = state.item_unwield_input,
	}
end

local function _player_debug_label(player)
	local name = type(player.name) == "function" and player:name() or "unknown"
	local slot = type(player.slot) == "function" and player:slot() or "?"
	local archetype = type(player.archetype_name) == "function" and player:archetype_name() or "?"

	return tostring(name) .. " [slot=" .. tostring(slot) .. ", archetype=" .. tostring(archetype) .. "]"
end

local function _collect_alive_bots()
	local manager_table = rawget(_G, "Managers")
	local alive_lookup = rawget(_G, "ALIVE")
	local player_manager = manager_table and manager_table.player
	if not player_manager then
		return nil, "Managers.player unavailable"
	end

	local players = player_manager:players()
	local bots = {}
	if not players then
		return bots
	end

	for _, player in pairs(players) do
		if player and not player:is_human_controlled() then
			local unit = player.player_unit
			if unit and alive_lookup and alive_lookup[unit] then
				bots[#bots + 1] = {
					player = player,
					unit = unit,
				}
			end
		end
	end

	table.sort(bots, function(a, b)
		local a_slot = type(a.player.slot) == "function" and a.player:slot() or math.huge
		local b_slot = type(b.player.slot) == "function" and b.player:slot() or math.huge
		return a_slot < b_slot
	end)

	return bots
end

local function bot_slot_for_unit(unit)
	local manager_table = rawget(_G, "Managers")
	local player_manager = manager_table and manager_table.player
	if not player_manager then
		return nil
	end

	local players = player_manager:players()
	if not players then
		return nil
	end

	for _, player in pairs(players) do
		if player and not player:is_human_controlled() and player.player_unit == unit then
			return type(player.slot) == "function" and player:slot() or nil
		end
	end

	return nil
end

local function _bot_blackboard(unit)
	local behavior_extension = ScriptUnit.has_extension(unit, "behavior_system")
	local brain = behavior_extension and behavior_extension._brain

	return brain and brain._blackboard or nil
end

local function log_ability_decision(ability_template_name, fixed_t, can_activate, rule, context)
	if not can_activate then
		return
	end

	if _debug_enabled() then
		_debug_log(
			"decision:" .. ability_template_name,
			fixed_t,
			"decision "
				.. ability_template_name
				.. " -> true (rule="
				.. tostring(rule)
				.. ", nearby="
				.. tostring(context.num_nearby)
				.. ", challenge="
				.. string.format("%.2f", context.challenge_rating_sum or 0)
				.. ", hp="
				.. fmt_percent(context.health_pct)
				.. ", tough="
				.. fmt_percent(context.toughness_pct)
				.. ", peril="
				.. fmt_percent(context.peril_pct)
				.. ", target_dist="
				.. fmt_percent(context.target_enemy_distance)
				.. ")"
		)
	end
end

local function register_commands()
	_mod:command("bb_state", "Dump BetterBots bot ability + fallback state", function()
		local bots, error_message = _collect_alive_bots()
		if error_message then
			_mod:echo("BetterBots: /bb_state unavailable (" .. error_message .. ")")
			return
		end
		bots = bots or {}
		if #bots == 0 then
			_mod:echo("BetterBots: /bb_state found no alive bots")
			return
		end

		local fixed_t = _fixed_time()
		_mod:echo("BetterBots: /bb_state bots=" .. tostring(#bots) .. " fixed_t=" .. fmt_seconds(fixed_t))

		for i, bot_entry in ipairs(bots) do
			local player = bot_entry.player
			local unit = bot_entry.unit
			local label = _player_debug_label(player)
			local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
			local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
			local ability_action_component = unit_data_extension
				and unit_data_extension:read_component("combat_ability_action")
			local combat_ability_component = unit_data_extension
				and unit_data_extension:read_component("combat_ability")
			local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
			local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action")
			local template_name = ability_action_component and ability_action_component.template_name or "none"
			local ability_name = _equipped_combat_ability_name(unit)
			local charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability") or nil
			local max_charges = ability_extension and ability_extension:max_ability_charges("combat_ability") or nil
			local cooldown = ability_extension and ability_extension:remaining_ability_cooldown("combat_ability") or nil
			local max_cooldown = ability_extension and ability_extension:max_ability_cooldown("combat_ability") or nil
			local can_use = ability_extension and ability_extension:can_use_ability("combat_ability") or false
			local fb_state = fallback_state_snapshot(_fallback_state_by_unit[unit], fixed_t)
			local last_charge = _last_charge_event_by_unit[unit]
			local last_charge_age_s = last_charge and (fixed_t - last_charge.fixed_t) or nil

			_mod:echo(
				"BetterBots: ["
					.. tostring(i)
					.. "] "
					.. label
					.. " ability="
					.. tostring(ability_name)
					.. " template="
					.. tostring(template_name)
					.. " charges="
					.. tostring(charges)
					.. "/"
					.. tostring(max_charges)
					.. " cd="
					.. fmt_seconds(cooldown)
					.. "/"
					.. fmt_seconds(max_cooldown)
					.. " can_use="
					.. tostring(can_use)
					.. " active="
					.. tostring(combat_ability_component and combat_ability_component.active == true)
					.. " slot="
					.. tostring(inventory_component and inventory_component.wielded_slot or "none")
					.. " weapon_template="
					.. tostring(weapon_action_component and weapon_action_component.template_name or "none")
					.. " stage="
					.. tostring(fb_state.item_stage)
					.. " next_try_in_s="
					.. fmt_seconds(fb_state.next_try_in_s)
					.. " last_charge_age_s="
					.. fmt_seconds(last_charge_age_s)
			)
		end
	end)

	_mod:command("bb_brain", "Dump BetterBots bot brain/blackboard snapshots", function()
		local bots, error_message = _collect_alive_bots()
		if error_message then
			_mod:echo("BetterBots: /bb_brain unavailable (" .. error_message .. ")")
			return
		end
		bots = bots or {}
		if #bots == 0 then
			_mod:echo("BetterBots: /bb_brain found no alive bots")
			return
		end

		local fixed_t = _fixed_time()
		for i, bot_entry in ipairs(bots) do
			local player = bot_entry.player
			local unit = bot_entry.unit
			local blackboard = _bot_blackboard(unit)
			local context = _build_context(unit, blackboard)
			local player_slot = type(player.slot) == "function" and player:slot() or "?"
			local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
			local ability_action_component = unit_data_extension
				and unit_data_extension:read_component("combat_ability_action")
			local inventory_component = unit_data_extension and unit_data_extension:read_component("inventory")
			local weapon_action_component = unit_data_extension and unit_data_extension:read_component("weapon_action")
			local ability_name = _equipped_combat_ability_name(unit)
			local perception = blackboard and blackboard.perception or nil
			local dump_name = "bb_brain_"
				.. tostring(i)
				.. "_"
				.. _sanitize_dump_name_fragment(ability_name)
				.. "_"
				.. _sanitize_dump_name_fragment(player_slot)
			local dump_payload = {
				fixed_t = fixed_t,
				bot = _player_debug_label(player),
				unit = tostring(unit),
				ability = {
					name = ability_name,
					template_name = ability_action_component and ability_action_component.template_name or "none",
					wielded_slot = inventory_component and inventory_component.wielded_slot or "none",
					weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none",
				},
				fallback_state = fallback_state_snapshot(_fallback_state_by_unit[unit], fixed_t),
				context = context_snapshot(context),
				perception = {
					target_enemy = enemy_unit_label(perception and perception.target_enemy),
					target_enemy_distance = perception and perception.target_enemy_distance or nil,
					target_enemy_type = perception and perception.target_enemy_type or nil,
					priority_target_enemy = enemy_unit_label(perception and perception.priority_target_enemy),
					opportunity_target_enemy = enemy_unit_label(perception and perception.opportunity_target_enemy),
					urgent_target_enemy = enemy_unit_label(perception and perception.urgent_target_enemy),
					target_ally_needs_aid = perception and perception.target_ally_needs_aid == true or false,
					target_ally_distance = perception and perception.target_ally_distance or nil,
				},
			}

			_mod:echo("BetterBots: /bb_brain dump " .. tostring(i) .. " -> " .. dump_name)
			_mod:dump(dump_payload, dump_name, 3)
		end
	end)

	_mod:command("bb_decide", "Evaluate BetterBots heuristics without queuing input", function()
		local bots, error_message = _collect_alive_bots()
		if error_message then
			_mod:echo("BetterBots: /bb_decide unavailable (" .. error_message .. ")")
			return
		end
		bots = bots or {}
		if #bots == 0 then
			_mod:echo("BetterBots: /bb_decide found no alive bots")
			return
		end

		local fixed_t = _fixed_time()
		_mod:echo("BetterBots: /bb_decide bots=" .. tostring(#bots) .. " fixed_t=" .. fmt_seconds(fixed_t))

		for i, bot_entry in ipairs(bots) do
			local player = bot_entry.player
			local unit = bot_entry.unit
			local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
			local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
			if not ability_extension or not unit_data_extension then
				_mod:echo(
					"BetterBots: ["
						.. tostring(i)
						.. "] "
						.. _player_debug_label(player)
						.. " ability=unknown template=none decide=nil rule=missing_extensions"
				)
			else
				local ability_component = unit_data_extension:read_component("combat_ability_action")
				local ability_template_name = ability_component and ability_component.template_name or "none"
				local ability_name = _equipped_combat_ability_name(unit)
				local blackboard = _bot_blackboard(unit)

				local can_activate, rule, context
				if ability_template_name == "none" then
					can_activate, rule = _can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
					rule = rule or (can_activate and "item_fallback_ready" or "item_fallback_blocked")
					context = _build_context(unit, blackboard)
				else
					local conditions =
						require("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")
					can_activate, rule, context = _resolve_decision(
						ability_template_name,
						conditions,
						unit,
						blackboard,
						nil,
						nil,
						nil,
						false,
						ability_extension
					)
				end

				_mod:echo(
					"BetterBots: ["
						.. tostring(i)
						.. "] "
						.. _player_debug_label(player)
						.. " ability="
						.. tostring(ability_name)
						.. " template="
						.. tostring(ability_template_name)
						.. " decide="
						.. tostring(can_activate)
						.. " rule="
						.. tostring(rule)
						.. " nearby="
						.. tostring(context and context.num_nearby or "n/a")
						.. " tough="
						.. fmt_percent(context and context.toughness_pct or nil)
						.. " peril="
						.. fmt_percent(context and context.peril_pct or nil)
						.. " dist="
						.. fmt_percent(context and context.target_enemy_distance or nil)
				)
			end
		end
	end)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
		_equipped_combat_ability_name = deps.equipped_combat_ability_name
		_fallback_state_by_unit = deps.fallback_state_by_unit
		_last_charge_event_by_unit = deps.last_charge_event_by_unit
	end,
	wire = function(refs)
		_build_context = refs.build_context
		_resolve_decision = refs.resolve_decision
		_enemy_breed = refs.enemy_breed
		_can_use_item_fallback = refs.can_use_item_fallback
	end,
	register_commands = register_commands,
	log_ability_decision = log_ability_decision,
	context_snapshot = context_snapshot,
	fallback_state_snapshot = fallback_state_snapshot,
	fmt_percent = fmt_percent,
	fmt_seconds = fmt_seconds,
	enemy_unit_label = enemy_unit_label,
	bot_blackboard = _bot_blackboard,
	bot_slot_for_unit = bot_slot_for_unit,
	collect_alive_bots = _collect_alive_bots,
}
