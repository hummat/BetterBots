-- luacheck: globals Unit ScriptUnit Managers
-- Bot pinging of elites and specials
local M = {}

local _mod
local _debug_log
local _fixed_time
local _bot_slot_for_unit

local PING_COOLDOWN_S = 2.0
local _last_ping_t_by_bot = setmetatable({}, { __mode = "k" })
local _missing_los_method_warned = false

function M.init(deps)
	_mod = deps.mod
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

	return not not (tags.elite or tags.special or tags.monster)
end

-- Priority order for ping slots.
local PING_SLOTS = {
	"priority_target_enemy",
	"opportunity_target_enemy",
	"urgent_target_enemy",
	"target_enemy",
}

function M.update(unit, blackboard)
	if not _fixed_time then
		return
	end
	local fixed_t = _fixed_time()
	local last_ping_t = _last_ping_t_by_bot[unit] or -PING_COOLDOWN_S

	if fixed_t - last_ping_t < PING_COOLDOWN_S then
		return
	end

	local perception = blackboard and blackboard.perception
	if not perception then
		return
	end

	local target_unit
	local reason

	for i = 1, #PING_SLOTS do
		local slot_name = PING_SLOTS[i]
		local candidate = perception[slot_name]
		if candidate and Unit.alive(candidate) and _is_elite_special_monster(candidate) then
			-- Candidate found, check if valid for pinging
			local target_extension = ScriptUnit.has_extension(candidate, "smart_tag_system")
			local already_tagged = target_extension and target_extension:tag_id()

			if target_extension and not already_tagged then
				-- Check LOS
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
					break
				end
			end
		end
	end

	if not target_unit then
		return
	end

	-- Robust guard for Managers.state.extension (matching sprint.lua:25 pattern)
	local extension_manager = Managers and Managers.state and Managers.state.extension
	if not extension_manager then
		return
	end

	local ok, smart_tag_system = pcall(extension_manager.system, extension_manager, "smart_tag_system")
	if not ok or not smart_tag_system then
		return
	end

	-- Use the contextual tag logic (which naturally resolves to "enemy_over_here")
	-- Wrap in pcall to prevent crash loops if the engine call fails.
	local success, err = pcall(smart_tag_system.set_contextual_unit_tag, smart_tag_system, unit, target_unit)

	-- Update cooldown timestamp unconditionally to prevent retry-on-crash loops.
	_last_ping_t_by_bot[unit] = fixed_t

	if _debug_log then
		local bot_slot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or "unknown"
		local unit_data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
		local breed = unit_data_ext and unit_data_ext:breed()
		local target_name = breed and breed.name or tostring(target_unit)

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
