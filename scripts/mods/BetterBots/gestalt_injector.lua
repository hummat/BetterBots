local M = {}

local _default_ranged_gestalt
local _default_melee_gestalt
local _injected_units

function M.init(deps)
	_default_ranged_gestalt = deps.default_ranged_gestalt
	_default_melee_gestalt = deps.default_melee_gestalt
	_injected_units = deps.injected_units
end

function M.inject(gestalts_or_nil, unit)
	if gestalts_or_nil and gestalts_or_nil.ranged then
		return gestalts_or_nil, false
	end

	gestalts_or_nil = gestalts_or_nil or {}
	gestalts_or_nil.ranged = gestalts_or_nil.ranged or _default_ranged_gestalt
	gestalts_or_nil.melee = gestalts_or_nil.melee or _default_melee_gestalt

	if unit and not _injected_units[unit] then
		_injected_units[unit] = true
		return gestalts_or_nil, true
	end

	return gestalts_or_nil, false
end

return M
