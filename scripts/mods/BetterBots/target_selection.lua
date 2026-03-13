-- Target selection hooks: issue #19 stop chasing distant specials, #48 player tag boost

local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local CHASE_RANGE_SQ = 324
local DEFAULT_MONSTER_WEIGHT = 2
local PLAYER_TAG_BONUS = 3.0

-- Returns true if target_unit is currently tagged by a human player (not a bot ping).
local function _has_human_player_tag(target_unit)
	local state_ext = Managers and Managers.state and Managers.state.extension
	if not state_ext then
		return false
	end

	local smart_tag_system = state_ext:system("smart_tag_system")
	if not smart_tag_system then
		return false
	end

	local tag = smart_tag_system:unit_tag(target_unit)
	if not tag then
		return false
	end

	local tagger_player = tag:tagger_player()

	return tagger_player ~= nil and tagger_player:is_human_controlled()
end

local function _is_monster_targeting_unit(target_unit, unit)
	local enemy_blackboard = BLACKBOARDS and BLACKBOARDS[target_unit] or nil
	local enemy_perception = enemy_blackboard and enemy_blackboard.perception or nil

	return enemy_perception and enemy_perception.aggro_state == "aggroed" and enemy_perception.target_unit == unit
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
end

function M.register_hooks()
	local ok, Ammo = pcall(require, "scripts/utilities/ammo")
	if not (ok and Ammo) then
		_debug_log("target_selection", _fixed_time(), "Failed to require scripts/utilities/ammo")
		return
	end

	_mod:hook_require("scripts/utilities/bot_target_selection", function(BotTargetSelection)
		_mod:hook(
			BotTargetSelection,
			"slot_weight",
			function(func, unit, target_unit, target_distance_sq, target_breed, target_ally)
				local perf_t0 = _perf and _perf.begin()
				local score = func(unit, target_unit, target_distance_sq, target_breed, target_ally)

				-- Issue #48: Boost score for player-tagged enemies
				if score > 0 and target_unit and _has_human_player_tag(target_unit) then
					score = score + PLAYER_TAG_BONUS
					if _debug_enabled() then
						_debug_log(
							"target_sel_tag_boost:" .. tostring(target_unit),
							_fixed_time(),
							"boosting score for player-tagged "
								.. tostring(target_breed.name)
								.. " +"
								.. PLAYER_TAG_BONUS
						)
					end
				end

				-- Issue #19: Stop chasing distant specials for melee
				-- If target is a special at >18m and bot has sufficient ammo (>50%),
				-- massively penalize melee score. This forces the bot to either shoot it
				-- or pick a closer target for melee.
				if target_distance_sq <= CHASE_RANGE_SQ then
					if perf_t0 then
						_perf.finish("target_selection.slot_weight", perf_t0)
					end
					return score
				end

				local tags = target_breed.tags
				if not (tags and tags.special) then
					if perf_t0 then
						_perf.finish("target_selection.slot_weight", perf_t0)
					end
					return score
				end

				local ammo_percent = Ammo.current_slot_percentage(unit, "slot_secondary")
				if not (ammo_percent and ammo_percent > 0.5) then
					if perf_t0 then
						_perf.finish("target_selection.slot_weight", perf_t0)
					end
					return score
				end

				if _debug_enabled() then
					_debug_log(
						"target_sel_penalty",
						_fixed_time(),
						"penalizing melee score for distant special "
							.. tostring(target_breed.name)
							.. " dist_sq="
							.. target_distance_sq
							.. " ammo="
							.. ammo_percent
					)
				end
				-- Massive penalty to ensure melee_score loses to ranged_score
				if perf_t0 then
					_perf.finish("target_selection.slot_weight", perf_t0)
				end
				return score - 100
			end
		)

		_mod:hook(BotTargetSelection, "monster_weight", function(func, unit, target_unit, target_breed, t)
			local perf_t0 = _perf and _perf.begin()
			local weight, override = func(unit, target_unit, target_breed, t)
			local tags = target_breed and target_breed.tags or nil

			if not (tags and tags.monster) or (weight and weight > 0) then
				if perf_t0 then
					_perf.finish("target_selection.monster_weight", perf_t0)
				end
				return weight, override
			end

			if not _is_monster_targeting_unit(target_unit, unit) then
				if perf_t0 then
					_perf.finish("target_selection.monster_weight", perf_t0)
				end
				return weight, override
			end

			if _debug_enabled() then
				_debug_log(
					"boss_targeting_bot",
					_fixed_time(),
					"restoring monster weight for boss targeting bot " .. tostring(target_breed.name)
				)
			end

			if perf_t0 then
				_perf.finish("target_selection.monster_weight", perf_t0)
			end
			return DEFAULT_MONSTER_WEIGHT, false
		end)
	end)
end

M.is_monster_targeting_unit = _is_monster_targeting_unit
M.has_human_player_tag = _has_human_player_tag

return M
