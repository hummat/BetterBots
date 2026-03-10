-- Target selection hooks: issue #19 stop chasing distant specials

local M = {}

local _mod
local _debug_log
local CHASE_RANGE_SQ = 324

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
end

function M.register_hooks()
	local ok, Ammo = pcall(require, "scripts/utilities/ammo")
	if not (ok and Ammo) then
		_debug_log("target_selection", 1, "Failed to require scripts/utilities/ammo")
		return
	end

	_mod:hook_require("scripts/utilities/bot_target_selection", function(BotTargetSelection)
		_mod:hook(
			BotTargetSelection,
			"slot_weight",
			function(func, unit, target_unit, target_distance_sq, target_breed, target_ally)
				local score = func(unit, target_unit, target_distance_sq, target_breed, target_ally)

				-- Issue #19: Stop chasing distant specials for melee
				-- If target is a special at >18m and bot has sufficient ammo (>50%),
				-- massively penalize melee score. This forces the bot to either shoot it
				-- or pick a closer target for melee.
				if target_distance_sq > CHASE_RANGE_SQ then
					local tags = target_breed.tags
					if tags and tags.special then
						local ammo_percent = Ammo.current_slot_percentage(unit, "slot_secondary")
						if ammo_percent and ammo_percent > 0.5 then
							_debug_log(
								"target_selection",
								3,
								"Penalizing melee score for distant special",
								target_breed.name,
								"dist_sq:",
								target_distance_sq,
								"ammo:",
								ammo_percent
							)
							-- Massive penalty to ensure melee_score loses to ranged_score
							return score - 100
						end
					end
				end

				return score
			end
		)
	end)
end

return M
