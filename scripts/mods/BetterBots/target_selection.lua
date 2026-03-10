-- Target selection hooks: issue #19 stop chasing distant specials

local M = {}

local _mod

function M.init(mod)
	_mod = mod
end

function M.register_hooks()
	_mod:hook_require("scripts/utilities/bot_target_selection", function(BotTargetSelection)
		_mod:hook(
			BotTargetSelection,
			"slot_weight",
			function(func, unit, target_unit, target_distance_sq, target_breed, target_ally)
				local score = func(unit, target_unit, target_distance_sq, target_breed, target_ally)

				-- Issue #19: Stop chasing distant specials for melee
				-- If target is special/elite at >18m and bot has ammo, massively
				-- penalize melee score. This forces the bot to either shoot it
				-- or pick a closer target for melee.
				if target_distance_sq > 324 then
					local tags = target_breed.tags
					if tags and (tags.special or tags.elite) then
						local Ammo = require("scripts/utilities/ammo")
						local ammo_percent = Ammo.current_slot_percentage(unit, "slot_secondary")
						if ammo_percent and ammo_percent > 0 then
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
