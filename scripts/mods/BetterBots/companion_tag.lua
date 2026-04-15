-- luacheck: globals Unit ScriptUnit Managers
-- Arbites Cyber-Mastiff companion-command smart tag (#49).
-- Places "enemy_companion_target" tags on high-priority enemies so the
-- dog uses them as its override target (unit_threat_adamant marker).
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit
local _bot_targeting
local _is_daemonhost_avoidance_enabled
local _daemonhost_breed_names
local _is_non_aggroed_daemonhost

local TAG_FAILURE_BACKOFF_S = 2.0
local MIN_TAG_HOLD_S = 2.0
local TAG_TEMPLATE = "enemy_companion_target"
-- Fallback; overwritten from bot_targeting.PERCEPTION_SLOTS in init().
local TAG_SLOTS = { "priority_target_enemy", "opportunity_target_enemy", "urgent_target_enemy", "target_enemy" }
local _last_tag_failure_t_by_bot = setmetatable({}, { __mode = "k" })
local _last_tagged_target_by_bot = setmetatable({}, { __mode = "k" })
local _last_skip_log_key_by_bot = setmetatable({}, { __mode = "k" })
local _smart_tag_system_warned = false
local _tag_call_failed_warned = false
local _missing_los_method_warned = false
local DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_bot_targeting = deps.bot_targeting
	_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled
	local shared_rules = deps.shared_rules
	_daemonhost_breed_names = shared_rules and shared_rules.DAEMONHOST_BREED_NAMES or DAEMONHOST_BREED_NAMES
	_is_non_aggroed_daemonhost = shared_rules and shared_rules.is_non_aggroed_daemonhost or nil
	if _bot_targeting and _bot_targeting.PERCEPTION_SLOTS then
		TAG_SLOTS = _bot_targeting.PERCEPTION_SLOTS
	end
	_smart_tag_system_warned = false
	_tag_call_failed_warned = false
	_missing_los_method_warned = false
end

local function _is_elite_special_monster(unit)
	if _bot_targeting then
		return _bot_targeting.is_elite_special_monster(unit)
	end
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	if not breed or not breed.tags then
		return false
	end
	return not not (breed.tags.elite or breed.tags.special or breed.tags.monster)
end

local function _target_name(target_unit)
	if _bot_targeting then
		return _bot_targeting.target_name(target_unit)
	end
	local unit_data_ext = target_unit and ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = unit_data_ext and unit_data_ext:breed()
	return breed and breed.name or tostring(target_unit)
end

local function _has_live_companion(companion_ext)
	if not (companion_ext and companion_ext:should_have_companion()) then
		return false
	end

	local companion_units = companion_ext.companion_units and companion_ext:companion_units() or nil
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

local function _is_dormant_daemonhost(target_unit)
	local dh_avoidance = not _is_daemonhost_avoidance_enabled or _is_daemonhost_avoidance_enabled()
	if not (dh_avoidance and target_unit) then
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	if not (breed and _daemonhost_breed_names and _daemonhost_breed_names[breed.name]) then
		return false
	end

	if _is_non_aggroed_daemonhost then
		return _is_non_aggroed_daemonhost(target_unit)
	end

	local target_bb = BLACKBOARDS and BLACKBOARDS[target_unit]
	local target_perception = target_bb and target_bb.perception
	return not (target_perception and target_perception.aggro_state == "aggroed")
end

local function _log_skip_once(unit, fixed_t, reason, target_unit)
	if not _debug_enabled() then
		return
	end

	local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
	local target_name = _target_name(target_unit)
	local skip_key = reason .. ":" .. target_name

	if _last_skip_log_key_by_bot[unit] == skip_key then
		return
	end

	_last_skip_log_key_by_bot[unit] = skip_key
	_debug_log(
		"companion_tag_skip:" .. skip_key,
		fixed_t,
		string.format("bot %s skipped companion tag for %s (reason: %s)", tostring(bot_slot), target_name, reason)
	)
end

local function _has_line_of_sight_to_candidate(unit, target_unit)
	local target_perception_extension = ScriptUnit.has_extension(target_unit, "perception_system")
	if not target_perception_extension then
		return true
	end

	if target_perception_extension.has_line_of_sight then
		return target_perception_extension:has_line_of_sight(unit)
	end

	if not _missing_los_method_warned and _mod and _mod.warning then
		_missing_los_method_warned = true
		_mod:warning("BetterBots: perception_system missing has_line_of_sight method for companion tagging")
	end

	return true
end

-- Check if target already has a companion-command tag from any Arbites bot.
-- Engine API: tag:template() returns a table with .name field.
local function _has_companion_tag(smart_tag_system, target_unit)
	if not smart_tag_system.unit_tag then
		return false
	end

	local tag = smart_tag_system:unit_tag(target_unit)
	if not tag then
		return false
	end

	local template = tag.template and tag:template() or nil
	return template and template.name == TAG_TEMPLATE or false
end

local function _slot_index_for_target(perception, target_unit)
	if not (perception and target_unit) then
		return nil
	end

	for i = 1, #TAG_SLOTS do
		if perception[TAG_SLOTS[i]] == target_unit then
			return i
		end
	end

	return nil
end

local function _current_tag_hold_state(unit, perception, smart_tag_system)
	local last_tagged = _last_tagged_target_by_bot[unit]
	if not (last_tagged and last_tagged.target and Unit.alive(last_tagged.target)) then
		return nil
	end

	if not _has_companion_tag(smart_tag_system, last_tagged.target) then
		return nil
	end

	local slot_index = _slot_index_for_target(perception, last_tagged.target)
	if not slot_index then
		return nil
	end

	return {
		target = last_tagged.target,
		tagged_t = last_tagged.tagged_t or 0,
		slot_index = slot_index,
	}
end

function M.update(unit, blackboard)
	if not _fixed_time then
		return
	end

	-- Guard: bot must have companion_spawner_system (Arbites archetype)
	local companion_ext = ScriptUnit.has_extension(unit, "companion_spawner_system")
	if not companion_ext then
		return
	end

	-- Guard: Arbites bot must currently have a live companion unit
	if not _has_live_companion(companion_ext) then
		return
	end

	local fixed_t = _fixed_time()

	-- Backoff after previous failure
	local last_failure_t = _last_tag_failure_t_by_bot[unit]
	if last_failure_t and fixed_t - last_failure_t < TAG_FAILURE_BACKOFF_S then
		return
	end

	local perception = blackboard and blackboard.perception
	if not perception then
		return
	end

	-- Get smart_tag_system
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager then
		return
	end

	local ok, smart_tag_system = pcall(extension_manager.system, extension_manager, "smart_tag_system")
	if not ok or not smart_tag_system then
		if not _smart_tag_system_warned and _mod and _mod.warning then
			_smart_tag_system_warned = true
			_mod:warning("BetterBots: failed to get smart_tag_system for companion tagging")
		end
		return
	end

	local current_tag = _current_tag_hold_state(unit, perception, smart_tag_system)
	local hold_active = current_tag and fixed_t - current_tag.tagged_t < MIN_TAG_HOLD_S or false
	local held_target = current_tag and current_tag.target or nil
	local held_slot_index = current_tag and current_tag.slot_index or nil

	-- Find highest-priority taggable target not already companion-tagged
	local target_unit
	local reason
	local hold_reason

	for i = 1, #TAG_SLOTS do
		local slot_name = TAG_SLOTS[i]
		local candidate = perception[slot_name]
		if candidate and Unit.alive(candidate) and _is_elite_special_monster(candidate) then
			if _is_dormant_daemonhost(candidate) then
				_log_skip_once(unit, fixed_t, "dormant_daemonhost", candidate)
				goto continue
			end

			if not _has_line_of_sight_to_candidate(unit, candidate) then
				_log_skip_once(unit, fixed_t, "no_los", candidate)
				goto continue
			end

			if hold_active and held_target and candidate == held_target then
				hold_reason = slot_name
				break
			end

			if not _has_companion_tag(smart_tag_system, candidate) then
				if hold_active and held_slot_index and i >= held_slot_index then
					goto continue
				end

				target_unit = candidate
				reason = slot_name
				break
			end
		end

		::continue::
	end

	if hold_active and not target_unit then
		if _debug_enabled() then
			_debug_log(
				"companion_tag_hold:" .. tostring(unit),
				fixed_t,
				"holding existing companion tag on "
					.. _target_name(held_target)
					.. " (reason: "
					.. tostring(hold_reason)
					.. ")"
			)
		end
		return
	end

	if not target_unit then
		return
	end

	-- Don't re-tag if we already tagged this target and it's still alive
	local last_tagged = _last_tagged_target_by_bot[unit]
	if last_tagged and last_tagged.target == target_unit and _has_companion_tag(smart_tag_system, target_unit) then
		if _debug_enabled() then
			_debug_log(
				"companion_tag_hold:" .. tostring(unit),
				fixed_t,
				"holding existing companion tag on " .. _target_name(target_unit)
			)
		end
		return
	end

	-- Place the companion-command tag
	local success, err = pcall(smart_tag_system.set_tag, smart_tag_system, TAG_TEMPLATE, unit, target_unit, nil)

	if success then
		_last_tagged_target_by_bot[unit] = {
			target = target_unit,
			tagged_t = fixed_t,
		}
		_last_tag_failure_t_by_bot[unit] = nil
		_last_skip_log_key_by_bot[unit] = nil
	else
		_last_tag_failure_t_by_bot[unit] = fixed_t
		if not _tag_call_failed_warned and _mod and _mod.warning then
			_tag_call_failed_warned = true
			_mod:warning("BetterBots: companion tag call failed (" .. tostring(err) .. ")")
		end
	end

	if _debug_enabled() then
		local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
		local target_name = _target_name(target_unit)

		if success then
			_debug_log(
				"companion_tag:" .. tostring(unit),
				fixed_t,
				string.format("bot %s companion-tagged %s (reason: %s)", tostring(bot_slot), target_name, reason)
			)
		else
			_debug_log(
				"companion_tag_fail:" .. tostring(unit),
				fixed_t,
				string.format("bot %s companion tag fail for %s: %s", tostring(bot_slot), target_name, tostring(err))
			)
		end
	end
end

return M
