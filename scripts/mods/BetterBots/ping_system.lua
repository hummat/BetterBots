-- luacheck: globals Unit ScriptUnit Managers
-- Bot pinging of elites and specials
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit
local _bot_targeting

local PING_FAILURE_BACKOFF_S = 2.0
local DISTANCE_ESCALATION_RATIO = 0.5
local _last_ping_failure_t_by_bot = setmetatable({}, { __mode = "k" })
local _last_tagged_by_bot = setmetatable({}, { __mode = "k" })
local _last_skip_log_key_by_bot = setmetatable({}, { __mode = "k" })
local _missing_los_method_warned = false
local _smart_tag_system_warned = false
local _ping_call_failed_warned = false

-- Fallback; overwritten from bot_targeting.PERCEPTION_SLOTS in init().
local PING_SLOTS = { "priority_target_enemy", "opportunity_target_enemy", "urgent_target_enemy", "target_enemy" }

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_bot_targeting = deps.bot_targeting
	if _bot_targeting and _bot_targeting.PERCEPTION_SLOTS then
		PING_SLOTS = _bot_targeting.PERCEPTION_SLOTS
	end
	_smart_tag_system_warned = false
end

local function _is_elite_special_monster(unit)
	if _bot_targeting then
		return _bot_targeting.is_elite_special_monster(unit)
	end
	-- Fallback when bot_targeting not wired (e.g., in tests)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	if not breed or not breed.tags then
		return false
	end
	return not not (breed.tags.elite or breed.tags.special or breed.tags.monster)
end

local function _has_live_companion(companion_spawner_extension)
	if not (companion_spawner_extension and companion_spawner_extension:should_have_companion()) then
		return false
	end

	local companion_units = companion_spawner_extension.companion_units
			and companion_spawner_extension:companion_units()
		or nil
	if not companion_units then
		return false
	end

	for i = 1, #companion_units do
		if Unit.alive(companion_units[i]) then
			return true
		end
	end

	return false
end

local function _distance_sq_between_units(unit, target_unit)
	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit] or nil
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[target_unit] or nil
	local distance_squared = Vector3 and Vector3.distance_squared or nil

	if not (unit_position and target_position and distance_squared) then
		return nil
	end

	return distance_squared(unit_position, target_position)
end

local function _is_in_any_ping_slot(perception, target_unit)
	if not (perception and target_unit) then
		return false
	end

	for i = 1, #PING_SLOTS do
		if perception[PING_SLOTS[i]] == target_unit then
			return true
		end
	end

	return false
end

local function _target_name(target_unit)
	if _bot_targeting then
		return _bot_targeting.target_name(target_unit)
	end
	local unit_data_ext = target_unit and ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = unit_data_ext and unit_data_ext:breed()
	return breed and breed.name or tostring(target_unit)
end

local function _log_skip_once(unit, fixed_t, reason, target_unit)
	if not _debug_enabled() then
		return
	end

	local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
	local skip_key
	local message

	if target_unit then
		local target_name = _target_name(target_unit)
		skip_key = reason .. ":" .. target_name
		message = string.format("bot %s skipped ping for %s (reason: %s)", tostring(bot_slot), target_name, reason)
	else
		skip_key = reason
		message = string.format("bot %s skipped pinging (reason: %s)", tostring(bot_slot), reason)
	end

	if _last_skip_log_key_by_bot[unit] == skip_key then
		return
	end

	_last_skip_log_key_by_bot[unit] = skip_key
	_debug_log("ping_system_skip:" .. skip_key, fixed_t, message)
end

local function _should_hold_last_tag(unit, perception, candidate_unit, candidate_distance_sq)
	local last_tag = _last_tagged_by_bot[unit]
	if not (last_tag and last_tag.target and Unit.alive(last_tag.target)) then
		return false
	end

	local target_extension = ScriptUnit.has_extension(last_tag.target, "smart_tag_system")
	local still_tagged = target_extension and target_extension:tag_id() or nil
	local still_perceived = _is_in_any_ping_slot(perception, last_tag.target)

	if not still_tagged then
		return false
	end

	if not still_perceived then
		return false
	end

	if
		candidate_unit
		and candidate_unit ~= last_tag.target
		and candidate_distance_sq
		and last_tag.distance_sq
		and candidate_distance_sq < last_tag.distance_sq * DISTANCE_ESCALATION_RATIO
	then
		return false
	end

	return true
end

function M.update(unit, blackboard)
	if not _fixed_time then
		return
	end
	local fixed_t = _fixed_time()
	local last_failure_t = _last_ping_failure_t_by_bot[unit]
	if last_failure_t and fixed_t - last_failure_t < PING_FAILURE_BACKOFF_S then
		_log_skip_once(unit, fixed_t, "failure_backoff")
		return
	end

	local perception = blackboard and blackboard.perception
	if not perception then
		return
	end

	local companion_spawner_extension = ScriptUnit.has_extension(unit, "companion_spawner_system")
	local has_live_companion = _has_live_companion(companion_spawner_extension)

	local target_unit
	local reason
	local target_distance_sq

	for i = 1, #PING_SLOTS do
		local slot_name = PING_SLOTS[i]
		local candidate = perception[slot_name]
		if candidate and Unit.alive(candidate) and _is_elite_special_monster(candidate) then
			if has_live_companion then
				_log_skip_once(unit, fixed_t, "companion_tag", candidate)
				return
			end

			-- Candidate found, check if valid for pinging
			local target_extension = ScriptUnit.has_extension(candidate, "smart_tag_system")
			local already_tagged = target_extension and target_extension:tag_id()

			if target_extension and already_tagged then
				_log_skip_once(unit, fixed_t, "already_tagged", candidate)
			elseif target_extension and not already_tagged then
				-- Check LOS via enemy's perception (BotPerceptionExtension has no has_line_of_sight).
				-- This asks "can the enemy see the bot?" — asymmetric (ignores bot facing), but
				-- wall occlusion is symmetric and perception slots already filter awareness.
				local has_los = true
				local target_perception_extension = ScriptUnit.has_extension(candidate, "perception_system")
				if target_perception_extension then
					if target_perception_extension.has_line_of_sight then
						has_los = target_perception_extension:has_line_of_sight(unit)
					elseif not _missing_los_method_warned then
						_missing_los_method_warned = true
						if _mod then
							_mod:warning("BetterBots: perception_system missing has_line_of_sight method")
						end
					end
				end

				if has_los then
					target_unit = candidate
					reason = slot_name
					target_distance_sq = _distance_sq_between_units(unit, candidate)
					break
				else
					_log_skip_once(unit, fixed_t, "no_los", candidate)
				end
			end
		end
	end

	if not target_unit then
		return
	end

	if _should_hold_last_tag(unit, perception, target_unit, target_distance_sq) then
		_log_skip_once(unit, fixed_t, "hold_last_tag", target_unit)
		return
	end

	-- Robust guard for Managers.state.extension (matching sprint.lua:25 pattern)
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager then
		return
	end

	local ok, smart_tag_system = pcall(extension_manager.system, extension_manager, "smart_tag_system")
	if not ok or not smart_tag_system then
		if not _smart_tag_system_warned and _mod and _mod.warning then
			_smart_tag_system_warned = true
			_mod:warning("BetterBots: failed to get smart_tag_system for bot pinging")
		end
		return
	end

	-- Use the contextual tag logic (which naturally resolves to "enemy_over_here")
	-- Wrap in pcall to prevent crash loops if the engine call fails.
	local success, err = pcall(smart_tag_system.set_contextual_unit_tag, smart_tag_system, unit, target_unit)

	if success then
		_last_tagged_by_bot[unit] = {
			target = target_unit,
			distance_sq = target_distance_sq,
		}
		_last_ping_failure_t_by_bot[unit] = nil
		_last_skip_log_key_by_bot[unit] = nil
	else
		_last_ping_failure_t_by_bot[unit] = fixed_t
		if not _ping_call_failed_warned and _mod and _mod.warning then
			_ping_call_failed_warned = true
			_mod:warning("BetterBots: bot ping call failed (" .. tostring(err) .. "). Pinging may be impaired.")
		end
	end

	if _debug_enabled() then
		local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
		local target_name = _target_name(target_unit)

		if success then
			_debug_log(
				"ping_system",
				fixed_t,
				string.format("bot %s pinged %s (reason: %s)", tostring(bot_slot), target_name, reason)
			)
		else
			_debug_log(
				"ping_system_fail",
				fixed_t,
				string.format("bot %s ping fail for %s: %s", tostring(bot_slot), target_name, tostring(err))
			)
		end
	end
end

return M
