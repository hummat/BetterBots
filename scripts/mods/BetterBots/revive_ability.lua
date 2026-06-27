-- scripts/mods/BetterBots/revive_ability.lua
-- Revive-with-ability (#7): fire a defensive ability before rescue interactions.
-- Hooks BtBotInteractAction.enter; delegates hold+release to ability_queue's
-- state machine via _fallback_state_by_unit.
local _mod

local function _hook_require_now(path, callback)
	local hook_require_now = _mod and _mod.hook_require_now
	if hook_require_now then
		return hook_require_now(_mod, path, callback, 4)
	end

	if _mod and _mod.warning and _mod._raw_hook_require then
		_mod:warning("BetterBots: hook_require_now_missing for " .. tostring(path))
	end
	return _mod["hook_require"](_mod, path, callback)
end

local _debug_log
local _debug_enabled
local _fixed_time
local _is_suppressed
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _perf
local _is_feature_enabled

local _MetaData
local _EventLog
local _Debug
local _is_combat_template_enabled
local _action_input_is_bot_queueable
local _combat_ability_identity

local INTERACT_ACTION_PATCH_SENTINEL = "__bb_revive_ability_installed"
local INTERACTION_SUCCESS_PATCH_SENTINEL = "__bb_rescue_success_installed"
local _human_revive_priority_by_bot = setmetatable({}, { __mode = "k" })
local _human_revive_need_type_by_bot = setmetatable({}, { __mode = "k" })
local _human_revive_owner_by_target = setmetatable({}, { __mode = "k" })
local _rescue_disabler_priority_by_bot = setmetatable({}, { __mode = "k" })

local RESCUE_INTERACTION_TYPES = {
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
}

local RESCUE_NEED_TYPES = {
	knocked_down = true,
	netted = true,
	ledge = true,
	hogtied = true,
}

local RESCUE_INTERACTION_BY_NEED_TYPE = {
	knocked_down = "revive",
	netted = "remove_net",
	ledge = "pull_up",
	hogtied = "rescue",
}

local RESCUE_NEED_BY_INTERACTION_TYPE = {
	revive = "knocked_down",
	remove_net = "netted",
	pull_up = "ledge",
	rescue = "hogtied",
}

local RESCUE_INTERACTION_HOOK_PATHS = {
	{
		path = "scripts/extension_systems/interaction/interactions/revive_interaction",
		interaction_type = "revive",
	},
	{
		path = "scripts/extension_systems/interaction/interactions/remove_net_interaction",
		interaction_type = "remove_net",
	},
	{
		path = "scripts/extension_systems/interaction/interactions/pull_up_interaction",
		interaction_type = "pull_up",
	},
	{
		path = "scripts/extension_systems/interaction/interactions/rescue_interaction",
		interaction_type = "rescue",
	},
}

local ATTACK_RESCUE_DISABLING_TYPES = {
	consumed = true,
	grabbed = true,
	mutant_charged = true,
	pounced = true,
	warp_grabbed = true,
}

local HUMAN_REVIVE_OWNER_LEASE = 3
local HUMAN_REVIVE_TAKEOVER_DISTANCE_MARGIN = 3
local DEFAULT_MAX_INTERACTION_DISTANCE = 2.5

local M = {}

local function _patch_priority_shoot_action_data()
	local ok, bot_actions = pcall(require, "scripts/settings/breed/breed_actions/bot_actions")
	if not ok or type(bot_actions) ~= "table" then
		return false
	end

	local shoot_action = bot_actions.shoot
	local priority_action = bot_actions.shoot_priority_target
	if
		type(shoot_action) ~= "table"
		or type(priority_action) ~= "table"
		or priority_action.aim_speed ~= nil
		or type(shoot_action.aim_speed) ~= "table"
	then
		return false
	end

	priority_action.aim_speed = shoot_action.aim_speed

	return true
end

function M.init(deps)
	assert(deps.combat_ability_identity, "revive_ability: combat_ability_identity dep required")
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_suppressed = deps.is_suppressed
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_perf = deps.perf
	_is_feature_enabled = deps.is_feature_enabled
	local shared_rules = deps.shared_rules or {}
	_action_input_is_bot_queueable = shared_rules.action_input_is_bot_queueable
	_combat_ability_identity = deps.combat_ability_identity
	_patch_priority_shoot_action_data()
end

function M.wire(deps)
	_MetaData = deps.MetaData
	_EventLog = deps.EventLog
	_Debug = deps.Debug
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

local function _resolve_revive_template(unit, ability_template_name, ability_extension)
	local identity =
		_combat_ability_identity.resolve(unit, ability_extension, { template_name = ability_template_name })
	local effective_name = _combat_ability_identity.effective_name(identity)

	if _combat_ability_identity.is_revive_defensive(identity) then
		return true, effective_name
	end

	return false, effective_name
end

-- Formats a human-readable bot identifier for log correlation. Prefers the
-- slot number (1-5) from Debug.bot_slot_for_unit so observers can match
-- candidate/skip/queue log lines against the in-game party roster; falls
-- back to the unit reference if the slot lookup isn't available.
local function _format_bot_id(unit)
	local slot = _Debug and _Debug.bot_slot_for_unit and _Debug.bot_slot_for_unit(unit)
	if slot then
		return "bot=" .. tostring(slot)
	end
	return "unit=" .. tostring(unit)
end

local function _human_revive_priority_enabled()
	return not _is_feature_enabled or _is_feature_enabled("human_revive_priority")
end

local function _unit_alive(unit)
	if rawget(_G, "HEALTH_ALIVE") then
		return HEALTH_ALIVE[unit] == true
	end
	if rawget(_G, "ALIVE") then
		return ALIVE[unit] == true
	end

	return unit ~= nil
end

local function _unit_position(unit)
	local positions = rawget(_G, "POSITION_LOOKUP")
	return positions and positions[unit] or nil
end

local function _distance(a, b)
	if not a or not b then
		return math.huge
	end
	if rawget(_G, "Vector3") and Vector3.distance then
		return Vector3.distance(a, b)
	end

	local ax, ay, az = a.x or a[1] or 0, a.y or a[2] or 0, a.z or a[3] or 0
	local bx, by, bz = b.x or b[1] or 0, b.y or b[2] or 0, b.z or b[3] or 0
	local dx, dy, dz = ax - bx, ay - by, az - bz

	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function _distance_squared(a, b)
	if not a or not b then
		return math.huge
	end
	if rawget(_G, "Vector3") and Vector3.distance_squared then
		return Vector3.distance_squared(a, b)
	end

	local ax, ay, az = a.x or a[1] or 0, a.y or a[2] or 0, a.z or a[3] or 0
	local bx, by, bz = b.x or b[1] or 0, b.y or b[2] or 0, b.z or b[3] or 0
	local dx, dy, dz = ax - bx, ay - by, az - bz

	return dx * dx + dy * dy + dz * dz
end

local function _max_interaction_distance(interactor_extension)
	if not (interactor_extension and interactor_extension._max_interaction_distance) then
		return DEFAULT_MAX_INTERACTION_DISTANCE
	end

	local ok, distance = pcall(interactor_extension._max_interaction_distance, interactor_extension)
	if ok and type(distance) == "number" and distance > 0 then
		return distance
	end

	return DEFAULT_MAX_INTERACTION_DISTANCE
end

local function _now()
	return _fixed_time and _fixed_time() or 0
end

local function _character_state(unit)
	local unit_data_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "unit_data_system")
	return unit_data_extension
		and unit_data_extension.read_component
		and unit_data_extension:read_component("character_state")
end

local function _disabled_character_state(unit)
	local unit_data_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "unit_data_system")
	return unit_data_extension
		and unit_data_extension.read_component
		and unit_data_extension:read_component("disabled_character_state")
end

local function _rescue_need_type(unit)
	local character_state_component = _character_state(unit)
	local state_name = character_state_component and character_state_component.state_name
	if state_name == "knocked_down" then
		return "knocked_down", nil
	end

	if state_name == "ledge_hanging" then
		return "ledge", nil
	end

	local disabled_character_state_component = _disabled_character_state(unit)
	local disabling_type = disabled_character_state_component
		and disabled_character_state_component.is_disabled
		and disabled_character_state_component.disabling_type

	if state_name == "netted" or disabling_type == "netted" then
		return "netted", nil
	end

	if state_name == "hogtied" then
		return "hogtied", nil
	end

	local disabling_unit = disabled_character_state_component and disabled_character_state_component.disabling_unit
	if disabling_type and ATTACK_RESCUE_DISABLING_TYPES[disabling_type] and _unit_alive(disabling_unit) then
		return disabling_type, disabling_unit
	end

	return nil, nil
end

local function _select_rescue_from_units(units, self_unit, self_position)
	if not units then
		return nil, nil, nil, math.huge, 0
	end

	local best_unit, best_need_type, best_disabler_unit, best_distance = nil, nil, nil, math.huge
	local unit_count = #units

	for i = 1, unit_count do
		local ally_unit = units[i]
		local need_type, disabler_unit
		if ally_unit ~= self_unit and _unit_alive(ally_unit) then
			need_type, disabler_unit = _rescue_need_type(ally_unit)
		end
		if need_type then
			local distance = _distance(self_position, _unit_position(ally_unit))
			if distance < best_distance then
				best_unit, best_need_type, best_disabler_unit, best_distance =
					ally_unit, need_type, disabler_unit, distance
			end
		end
	end

	return best_unit, best_need_type, best_disabler_unit, best_distance, unit_count
end

local function _select_rescue_target(side, self_unit, self_position)
	local target_unit, need_type, disabler_unit, distance, unit_count =
		_select_rescue_from_units(side and side.valid_human_units, self_unit, self_position)
	if target_unit then
		return target_unit, need_type, disabler_unit, distance, unit_count, "human"
	end

	return _select_rescue_from_units(side and side.valid_player_units, self_unit, self_position)
end

local function _nearest_bot_to(target_unit, bot_group, fallback_unit)
	local target_position = _unit_position(target_unit)
	local best_unit, best_distance = fallback_unit, math.huge
	local data = bot_group and bot_group.data and bot_group:data()

	if data then
		for bot_unit, _ in pairs(data) do
			if bot_unit ~= target_unit and _unit_alive(bot_unit) and not _rescue_need_type(bot_unit) then
				local distance = _distance(_unit_position(bot_unit), target_position)
				if distance < best_distance then
					best_unit, best_distance = bot_unit, distance
				end
			end
		end
	else
		best_distance = _distance(_unit_position(fallback_unit), target_position)
	end

	return best_unit, best_distance
end

local function _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
	local previous_target = _human_revive_priority_by_bot[unit]
	local previous_need_type = _human_revive_need_type_by_bot[unit]
	local previous_disabler = _rescue_disabler_priority_by_bot[unit]
	if not previous_target then
		return false
	end

	_human_revive_priority_by_bot[unit] = nil
	_human_revive_need_type_by_bot[unit] = nil
	_rescue_disabler_priority_by_bot[unit] = nil
	local lease = _human_revive_owner_by_target[previous_target]
	if lease and lease.unit == unit then
		_human_revive_owner_by_target[previous_target] = nil
	end
	if behavior_component then
		behavior_component.revive_with_urgent_target = false
		if behavior_component.interaction_unit == previous_target then
			behavior_component.interaction_unit = nil
		end
	end
	if perception_component and perception_component.target_ally == previous_target then
		perception_component.target_ally = nil
		perception_component.target_ally_distance = math.huge
		perception_component.target_ally_needs_aid = false
		perception_component.target_ally_need_type = "n/a"
		perception_component.force_aid = false
		if previous_disabler then
			if perception_component.target_enemy == previous_disabler then
				perception_component.target_enemy = nil
			end
			if perception_component.priority_target_enemy == previous_disabler then
				perception_component.priority_target_enemy = nil
			end
			if perception_component.urgent_target_enemy == previous_disabler then
				perception_component.urgent_target_enemy = nil
			end
			if perception_component.priority_target_disabled_ally == previous_target then
				perception_component.priority_target_disabled_ally = nil
			end
		end
	end
	if follow_component then
		follow_component.needs_destination_refresh = true
	end

	if previous_disabler and _debug_enabled and _debug_enabled() and not _rescue_need_type(previous_target) then
		_debug_log(
			"rescue_disabled_clear:" .. tostring(unit) .. ":" .. tostring(previous_target),
			_fixed_time(),
			"["
				.. _format_bot_id(unit)
				.. "] rescue disabled state cleared: target="
				.. tostring(previous_target)
				.. " need_type="
				.. tostring(previous_need_type)
		)
	end

	return true
end

local function _active_human_revive_owner(target_human)
	local lease = _human_revive_owner_by_target[target_human]
	if not lease then
		return nil
	end

	if not (_unit_alive(target_human) and _rescue_need_type(target_human)) then
		_human_revive_owner_by_target[target_human] = nil
		return nil
	end

	if not _unit_alive(lease.unit) then
		_human_revive_owner_by_target[target_human] = nil
		return nil
	end

	if _now() > lease.expires_at then
		_human_revive_owner_by_target[target_human] = nil
		return nil
	end

	return lease.unit
end

local function _claim_human_revive_owner(unit, target_human)
	_human_revive_owner_by_target[target_human] = {
		unit = unit,
		expires_at = _now() + HUMAN_REVIVE_OWNER_LEASE,
	}
end

local function _suppress_combat_targets_for_rescue(perception_component)
	perception_component.target_enemy = nil
	perception_component.target_enemy_distance = math.huge
	perception_component.opportunity_target_enemy = nil
	perception_component.priority_target_enemy = nil
	perception_component.urgent_target_enemy = nil
end

local function _open_reachable_rescue_interaction(unit, behavior_component, target_ally, need_type)
	if not (unit and behavior_component and target_ally and RESCUE_NEED_TYPES[need_type]) then
		return false
	end

	local interaction_type = RESCUE_INTERACTION_BY_NEED_TYPE[need_type]
	local interactor_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(unit, "interactor_system")
	if not (interaction_type and interactor_extension and interactor_extension.can_interact) then
		return false
	end

	local ok, can_interact =
		pcall(interactor_extension.can_interact, interactor_extension, target_ally, interaction_type)
	if not ok or not can_interact then
		return false
	end

	local distance_squared = _distance_squared(_unit_position(unit), _unit_position(target_ally))
	local max_interaction_distance = _max_interaction_distance(interactor_extension)
	if distance_squared > max_interaction_distance * max_interaction_distance then
		return false
	end

	local target_ally_aid_destination = behavior_component.target_ally_aid_destination
	local self_position = _unit_position(unit)
	if not (target_ally_aid_destination and target_ally_aid_destination.store and self_position) then
		return false
	end

	behavior_component.interaction_unit = target_ally
	target_ally_aid_destination:store(self_position)

	if _debug_enabled and _debug_enabled() then
		_debug_log(
			"human_revive_interact_ready:" .. tostring(unit) .. ":" .. tostring(target_ally),
			_fixed_time(),
			"["
				.. _format_bot_id(unit)
				.. "] rescue interaction opened: target="
				.. tostring(target_ally)
				.. " need_type="
				.. tostring(need_type)
				.. " interaction="
				.. tostring(interaction_type)
		)
	end

	return true
end

function M.apply_human_revive_priority(self, unit)
	local behavior_component = self and self._behavior_component
	local perception_component = self and self._perception_component
	local follow_component = self and self._follow_component
	if not unit or not behavior_component or not perception_component then
		return false
	end

	if not _human_revive_priority_enabled() then
		return _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
	end

	if _rescue_need_type(unit) then
		return _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
	end

	local self_position = _unit_position(unit)
	local target_ally, need_type, disabler_unit, distance, ally_count, target_kind =
		_select_rescue_target(self and self._side, unit, self_position)
	if not target_ally then
		return _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
	end

	local owner = _active_human_revive_owner(target_ally)
	if owner and owner ~= unit then
		return _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
	end

	local nearest_bot, nearest_distance = _nearest_bot_to(target_ally, self and self._bot_group, unit)
	if nearest_bot ~= unit then
		local should_release_to_nearer_bot = owner == unit
			and nearest_distance + HUMAN_REVIVE_TAKEOVER_DISTANCE_MARGIN < distance
		if not owner or should_release_to_nearer_bot then
			return _clear_human_revive_priority(unit, behavior_component, perception_component, follow_component)
		end
	end

	perception_component.target_ally = target_ally
	perception_component.target_ally_distance = distance
	perception_component.target_ally_need_type = need_type
	if disabler_unit then
		perception_component.target_ally_needs_aid = false
		perception_component.target_enemy = disabler_unit
		perception_component.priority_target_enemy = disabler_unit
		perception_component.urgent_target_enemy = disabler_unit
		perception_component.priority_target_disabled_ally = target_ally
		behavior_component.revive_with_urgent_target = false
	else
		perception_component.target_ally_needs_aid = true
		perception_component.force_aid = true
		_suppress_combat_targets_for_rescue(perception_component)
		behavior_component.revive_with_urgent_target = true
		if follow_component then
			follow_component.needs_destination_refresh = true
		end

		local bot_group = self and self._bot_group
		if bot_group and bot_group.register_ally_needs_aid_priority then
			bot_group:register_ally_needs_aid_priority(unit, target_ally)
		end

		_open_reachable_rescue_interaction(unit, behavior_component, target_ally, need_type)
	end

	_human_revive_priority_by_bot[unit] = target_ally
	_human_revive_need_type_by_bot[unit] = need_type
	_rescue_disabler_priority_by_bot[unit] = disabler_unit
	_claim_human_revive_owner(unit, target_ally)

	if _debug_enabled and _debug_enabled() then
		local reason = target_kind == "human" and ally_count == 1 and "mission_critical" or "ally_rescue"
		local mode = disabler_unit and "disabler" or "interaction"
		_debug_log(
			"human_revive_priority:" .. tostring(unit) .. ":" .. tostring(target_ally),
			_fixed_time(),
			"["
				.. _format_bot_id(unit)
				.. "] rescue priority assigned: target="
				.. tostring(target_ally)
				.. " reason="
				.. reason
				.. " need_type="
				.. tostring(need_type)
				.. " mode="
				.. mode
				.. " target_kind="
				.. tostring(target_kind)
				.. " distance="
				.. tostring(distance)
				.. (disabler_unit and " disabler=" .. tostring(disabler_unit) or "")
		)
	end

	return true
end

function M.log_revive_candidate(unit, behavior_component, perception_component)
	if not (_debug_enabled and _debug_enabled()) then
		return false
	end

	local target_ally = perception_component and perception_component.target_ally
	local need_type = perception_component and perception_component.target_ally_need_type
	if not target_ally or behavior_component.interaction_unit ~= target_ally or not RESCUE_NEED_TYPES[need_type] then
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not unit_data_extension or not ability_extension then
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	local is_defensive, effective_ability_name =
		_resolve_revive_template(unit, ability_template_name, ability_extension)
	if not is_defensive then
		return false
	end

	local log_name = effective_ability_name or ability_template_name or "unknown"
	_debug_log(
		"revive_candidate:" .. log_name .. ":" .. tostring(unit),
		_fixed_time(),
		"["
			.. _format_bot_id(unit)
			.. "] revive candidate observed: "
			.. tostring(log_name)
			.. " (template="
			.. tostring(ability_template_name)
			.. ", need_type="
			.. tostring(need_type)
			.. ")",
		5
	)

	return true
end

function M.try_pre_revive(unit, _blackboard, action_data) -- luacheck: ignore 212/_blackboard
	local interaction_type = action_data and action_data.interaction_type
	if not RESCUE_INTERACTION_TYPES[interaction_type] then
		return false
	end

	-- From here on, this IS a rescue interaction — log skip reasons.
	-- Throttle keys still use the stringified unit for uniqueness; the
	-- visible log message uses the slot-aware identifier so operators can
	-- correlate candidate/skip/queue lines against the party roster.
	local bot_id = tostring(unit)
	local bot_tag = "[" .. _format_bot_id(unit) .. "] "

	local perception_extension = ScriptUnit.has_extension(unit, "perception_system")
	local enemies_nearby = 0
	if perception_extension then
		local _, num = perception_extension:enemies_in_proximity()
		enemies_nearby = num or 0
	end
	if enemies_nearby < 1 then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_enemies:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no enemies nearby)"
			)
		end
		return false
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:suppressed:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (suppressed: " .. tostring(suppress_reason) .. ")"
			)
		end
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_unit_data:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no unit_data_system extension)"
			)
		end
		return false
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_ability_ext:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no ability_system extension)"
			)
		end
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	local is_defensive, effective_ability_name =
		_resolve_revive_template(unit, ability_template_name, ability_extension)
	if not ability_template_name or not is_defensive then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:not_whitelisted:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped (ability "
					.. tostring(ability_template_name)
					.. ", equipped="
					.. tostring(effective_ability_name)
					.. " not in defensive whitelist)"
			)
		end
		return false
	end

	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:disabled:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " disabled by setting)"
			)
		end
		return false
	end

	if not ability_extension:can_use_ability("combat_ability") then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:cant_use:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " can_use_ability=false)"
			)
		end
		return false
	end

	local charges = ability_extension:remaining_ability_charges("combat_ability")
	if not charges or charges < 1 then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_charges:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (" .. ability_template_name .. " charges=0)"
			)
		end
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data or not ability_meta_data.activation then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_meta:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped ("
					.. tostring(ability_template_name)
					.. " missing ability_meta_data.activation)"
			)
		end
		return false
	end

	local activation_data = ability_meta_data.activation
	local action_input = activation_data.action_input
	if not action_input then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_input:" .. bot_id,
				_fixed_time(),
				bot_tag
					.. "revive ability skipped ("
					.. tostring(ability_template_name)
					.. " activation has no action_input)"
			)
		end
		return false
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_skip:no_input_ext:" .. bot_id,
				_fixed_time(),
				bot_tag .. "revive ability skipped (no action_input_system extension)"
			)
		end
		return false
	end

	if _action_input_is_bot_queueable then
		local is_valid = _action_input_is_bot_queueable(
			action_input_extension,
			ability_extension,
			"combat_ability_action",
			ability_template_name,
			action_input,
			activation_data.used_input,
			_fixed_time()
		)
		if not is_valid then
			if _debug_enabled() then
				_debug_log(
					"revive_ability_skip:not_queueable:" .. bot_id,
					_fixed_time(),
					bot_tag
						.. "revive ability skipped ("
						.. tostring(ability_template_name)
						.. " action_input "
						.. tostring(action_input)
						.. " not bot-queueable)"
				)
			end
			return false
		end
	end

	local fixed_t = _fixed_time()
	action_input_extension:bot_queue_action_input("combat_ability_action", action_input, nil)

	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end
	state.active = true
	state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
	state.wait_action_input = ability_meta_data.wait_action and ability_meta_data.wait_action.action_input or nil
	state.wait_sent = false
	state.action_input_extension = action_input_extension

	if _debug_enabled() then
		_debug_log(
			"revive_ability:" .. tostring(effective_ability_name or ability_template_name) .. ":" .. tostring(unit),
			fixed_t,
			bot_tag
				.. "revive ability queued: "
				.. tostring(effective_ability_name or ability_template_name)
				.. " (interaction="
				.. tostring(interaction_type)
				.. ", enemies="
				.. tostring(enemies_nearby)
				.. ")"
		)
	end

	if _EventLog and _EventLog.is_enabled() then
		local bot_slot = _Debug and _Debug.bot_slot_for_unit and _Debug.bot_slot_for_unit(unit) or nil
		_EventLog.emit({
			t = fixed_t,
			event = "revive_ability",
			bot = bot_slot,
			ability = effective_ability_name or _equipped_combat_ability_name(unit),
			template = ability_template_name,
			equipped_ability_name = effective_ability_name,
			interaction = interaction_type,
			enemies = enemies_nearby,
		})
	end

	return true
end

function M.install_interaction_success_hooks(Interaction, interaction_type)
	if not Interaction or rawget(Interaction, INTERACTION_SUCCESS_PATCH_SENTINEL) then
		return
	end

	Interaction[INTERACTION_SUCCESS_PATCH_SENTINEL] = true

	_mod:hook(
		Interaction,
		"stop",
		function(func, self, world, interactor_unit, unit_data_component, t, result, is_server)
			local target_unit = unit_data_component and unit_data_component.target_unit or nil
			local stop_result = func(self, world, interactor_unit, unit_data_component, t, result, is_server)

			if _debug_enabled and _debug_enabled() and is_server and result == "success" then
				local bot_slot = _Debug and _Debug.bot_slot_for_unit and _Debug.bot_slot_for_unit(interactor_unit)
				if not bot_slot then
					return stop_result
				end

				_debug_log(
					"rescue_interaction_success:"
						.. tostring(interactor_unit)
						.. ":"
						.. tostring(target_unit)
						.. ":"
						.. tostring(interaction_type),
					_fixed_time(),
					"["
						.. _format_bot_id(interactor_unit)
						.. "] rescue interaction succeeded: target="
						.. tostring(target_unit)
						.. " need_type="
						.. tostring(RESCUE_NEED_BY_INTERACTION_TYPE[interaction_type])
						.. " interaction="
						.. tostring(interaction_type)
				)
			end

			return stop_result
		end
	)
end

function M.register_hooks()
	_hook_require_now(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action",
		function(BtBotInteractAction)
			if not BtBotInteractAction or rawget(BtBotInteractAction, INTERACT_ACTION_PATCH_SENTINEL) then
				return
			end
			BtBotInteractAction[INTERACT_ACTION_PATCH_SENTINEL] = true

			local orig_enter = BtBotInteractAction.enter
			BtBotInteractAction.enter = function(self, unit, breed, blackboard, scratchpad, action_data, t)
				local perf_t0 = _perf and _perf.begin()
				local ok, err = pcall(M.try_pre_revive, unit, blackboard, action_data)
				if not ok and _debug_enabled and _debug_enabled() then
					_debug_log(
						"revive_ability_error:" .. tostring(unit),
						_fixed_time(),
						"try_pre_revive error: " .. tostring(err)
					)
				end
				if perf_t0 and _perf then
					_perf.finish("revive_ability", perf_t0)
				end
				return orig_enter(self, unit, breed, blackboard, scratchpad, action_data, t)
			end

			if _debug_enabled and _debug_enabled() then
				_debug_log("revive_ability:hook_installed", 0, "installed BtBotInteractAction.enter hook")
			end
		end
	)

	for i = 1, #RESCUE_INTERACTION_HOOK_PATHS do
		local hook = RESCUE_INTERACTION_HOOK_PATHS[i]
		local path = hook.path
		local interaction_type = hook.interaction_type
		_hook_require_now(path, function(Interaction)
			M.install_interaction_success_hooks(Interaction, interaction_type)
		end)
	end
end

-- Called from the consolidated _refresh_destination hook_safe in BetterBots.lua.
-- See mule_pickup.on_refresh_destination for rationale.
function M.on_refresh_destination(
	self,
	_t,
	_self_position,
	_previous_destination,
	_hold_position,
	_hold_position_max_distance_sq,
	_bot_group_data,
	_navigation_extension,
	_follow_component,
	perception_component
)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	local unit = self and self._unit
	local behavior_component = self and self._behavior_component
	if not unit or not behavior_component or not perception_component then
		return
	end

	M.log_revive_candidate(unit, behavior_component, perception_component)
end

M.RESCUE_INTERACTION_TYPES = RESCUE_INTERACTION_TYPES

return M
