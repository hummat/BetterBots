-- luacheck: globals Unit ScriptUnit Managers
-- Bot pinging of elites and specials
local M = {}

local _debug_log
local _fixed_time
local _bot_slot_for_unit

local PING_COOLDOWN_S = 2.0
local _last_ping_t_by_bot = setmetatable({}, { __mode = "k" })

function M.init(deps)
	_debug_log = deps.debug_log
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
end

local function _is_elite_special_monster(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	if not breed then
		return false
	end

	local tags = breed.tags
	if not tags then
		return false
	end

	return tags.elite or tags.special or tags.monster
end

local function _get_ping_candidate(blackboard)
	local perception = blackboard and blackboard.perception
	if not perception then
		return nil
	end

	if perception.priority_target_enemy and Unit.alive(perception.priority_target_enemy) then
		return perception.priority_target_enemy, "priority"
	end
	if perception.opportunity_target_enemy and Unit.alive(perception.opportunity_target_enemy) then
		return perception.opportunity_target_enemy, "opportunity"
	end
	if perception.urgent_target_enemy and Unit.alive(perception.urgent_target_enemy) then
		return perception.urgent_target_enemy, "urgent"
	end
	if
		perception.target_enemy
		and Unit.alive(perception.target_enemy)
		and _is_elite_special_monster(perception.target_enemy)
	then
		return perception.target_enemy, "target"
	end

	return nil
end

function M.update(unit, blackboard)
	local fixed_t = _fixed_time()
	local last_ping_t = _last_ping_t_by_bot[unit] or -PING_COOLDOWN_S

	if fixed_t - last_ping_t < PING_COOLDOWN_S then
		return
	end

	local target_unit, reason = _get_ping_candidate(blackboard)
	if not target_unit then
		return
	end

	local target_extension = ScriptUnit.has_extension(target_unit, "smart_tag_system")
	if not target_extension then
		return
	end

	-- Check if already tagged
	local current_tag_id = target_extension:tag_id()
	if current_tag_id then
		return
	end

	-- Check line of sight using the enemy's perception system (standard pattern)
	local target_perception_extension = ScriptUnit.has_extension(target_unit, "perception_system")
	if target_perception_extension and target_perception_extension.has_line_of_sight then
		if not target_perception_extension:has_line_of_sight(unit) then
			return
		end
	end

	local smart_tag_system = Managers.state.extension:system("smart_tag_system")
	if not smart_tag_system then
		return
	end

	-- Use the contextual tag logic (which naturally resolves to "enemy_over_here")
	smart_tag_system:set_contextual_unit_tag(unit, target_unit)

	_last_ping_t_by_bot[unit] = fixed_t

	if _debug_log then
		local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
		local breed = ScriptUnit.has_extension(target_unit, "unit_data_system")
			and ScriptUnit.has_extension(target_unit, "unit_data_system"):breed()
		local target_name = breed and breed.name or tostring(target_unit)
		_debug_log(
			"ping_system",
			fixed_t,
			string.format("bot %s pinged %s (reason: %s)", tostring(bot_slot), target_name, reason)
		)
	end
end

return M
