-- luacheck: globals ScriptUnit
-- bot_targeting.lua — shared bot perception target resolver and helpers.
-- Keeps grenade aim, smart-target seeding, pinging, and companion tagging
-- on the same target-priority order.

local M = {}

-- Priority order for perception slot scanning.
M.PERCEPTION_SLOTS = {
	"priority_target_enemy",
	"opportunity_target_enemy",
	"urgent_target_enemy",
	"target_enemy",
}

function M.resolve_bot_target_unit(target_source)
	if not target_source then
		return nil
	end

	return target_source.target_enemy
		or target_source.priority_target_enemy
		or target_source.opportunity_target_enemy
		or target_source.urgent_target_enemy
end

function M.is_elite_special_monster(unit)
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

function M.target_name(unit)
	local unit_data_ext = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = unit_data_ext and unit_data_ext:breed()
	return breed and breed.name or tostring(unit)
end

return M
