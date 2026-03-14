-- bot_targeting.lua — shared bot perception target resolver.
-- Keeps grenade aim and smart-target seeding on the same target-priority order.

local M = {}

function M.resolve_bot_target_unit(target_source)
	if not target_source then
		return nil
	end

	return target_source.target_enemy
		or target_source.priority_target_enemy
		or target_source.opportunity_target_enemy
		or target_source.urgent_target_enemy
end

return M
