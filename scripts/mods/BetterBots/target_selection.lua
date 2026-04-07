-- Target selection hooks: #19 distant special penalty, #48 player tag boost,
-- #69 companion-pin de-prioritization

local M = {}

local _mod
local _breed_utils
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled
local _logged_companion_pin_melee = {}
local _logged_companion_pin_ranged = {}
local CHASE_RANGE_SQ = 324
local DEFAULT_MONSTER_WEIGHT = 2
local FRIENDLY_COMPANION_PIN_PENALTY = 100
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

-- Friendly cyber-mastiff pins mark the enemy disable component as:
-- is_disabled=true, type="pounced", attacker_unit=<companion unit>.
local function _is_friendly_companion_pin(target_unit)
	local bb = BLACKBOARDS and BLACKBOARDS[target_unit]
	if not bb or not bb.disable then
		return false
	end

	local dc = bb.disable
	if dc.is_disabled ~= true or dc.type ~= "pounced" or dc.attacker_unit == nil then
		return false
	end

	local attacker_unit = dc.attacker_unit
	local unit_data_extension = ScriptUnit
		and ScriptUnit.has_extension
		and ScriptUnit.has_extension(attacker_unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local attacker_breed = unit_data_extension:breed()

	return _breed_utils and _breed_utils.is_companion(attacker_breed) or false
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
	_is_enabled = deps.is_enabled
	_logged_companion_pin_melee = {}
	_logged_companion_pin_ranged = {}
end

function M.register_hooks()
	local ok, Ammo = pcall(require, "scripts/utilities/ammo")
	local breed_ok, Breed = pcall(require, "scripts/utilities/breed")
	if not (ok and Ammo) then
		_debug_log("target_selection", _fixed_time(), "Failed to require target selection dependencies")
		return
	end
	_breed_utils = breed_ok and Breed
		or {
			is_companion = function(breed)
				return breed and (breed.breed_type == "companion" or (breed.tags and breed.tags.companion))
			end,
		}

	_mod:hook_require("scripts/utilities/bot_target_selection", function(BotTargetSelection)
		_mod:hook(
			BotTargetSelection,
			"slot_weight",
			function(func, unit, target_unit, target_distance_sq, target_breed, target_ally)
				local perf_t0 = _perf and _perf.begin()
				local score = func(unit, target_unit, target_distance_sq, target_breed, target_ally)

				if not _is_enabled or _is_enabled() then
					if target_unit and _is_friendly_companion_pin(target_unit) then
						score = score - FRIENDLY_COMPANION_PIN_PENALTY
						if _debug_enabled() then
							local log_key = "target_sel_companion_pin:"
								.. tostring(target_unit)
								.. ":"
								.. tostring(unit)
							if not _logged_companion_pin_melee[log_key] then
								_logged_companion_pin_melee[log_key] = true
								_debug_log(
									log_key,
									_fixed_time(),
									"penalizing friendly companion pin "
										.. tostring(target_breed.name)
										.. " -"
										.. FRIENDLY_COMPANION_PIN_PENALTY
								)
							end
						end
					-- Issue #48: Boost score for player-tagged enemies
					elseif score > 0 and _has_human_player_tag(target_unit) then
						score = score + PLAYER_TAG_BONUS
						if _debug_enabled() then
							_debug_log(
								"target_sel_tag_boost:" .. tostring(target_unit) .. ":" .. tostring(unit),
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
					local tags = target_breed.tags
					local ammo_percent = nil
					if target_distance_sq > CHASE_RANGE_SQ and tags and tags.special then
						ammo_percent = Ammo.current_slot_percentage(unit, "slot_secondary")
					end

					if ammo_percent and ammo_percent > 0.5 then
						if _debug_enabled() then
							_debug_log(
								"target_sel_penalty:" .. tostring(unit),
								_fixed_time(),
								"penalizing melee score for distant special "
									.. tostring(target_breed.name)
									.. " dist_sq="
									.. target_distance_sq
									.. " ammo="
									.. ammo_percent
							)
						end
						score = score - 100
					end
				end

				if perf_t0 then
					_perf.finish("target_selection.slot_weight", perf_t0)
				end
				return score
			end
		)

		_mod:hook(BotTargetSelection, "line_of_sight_weight", function(func, unit, target_unit)
			local score = func(unit, target_unit)

			if (not _is_enabled or _is_enabled()) and target_unit and _is_friendly_companion_pin(target_unit) then
				score = score - FRIENDLY_COMPANION_PIN_PENALTY
				if _debug_enabled() then
					local log_key = "target_sel_companion_pin_ranged:" .. tostring(target_unit) .. ":" .. tostring(unit)
					if not _logged_companion_pin_ranged[log_key] then
						_logged_companion_pin_ranged[log_key] = true
						_debug_log(
							log_key,
							_fixed_time(),
							"penalizing ranged target for friendly companion pin -" .. FRIENDLY_COMPANION_PIN_PENALTY
						)
					end
				end
			end

			return score
		end)

		_mod:hook(BotTargetSelection, "monster_weight", function(func, unit, target_unit, target_breed, t)
			local perf_t0 = _perf and _perf.begin()
			local weight, override = func(unit, target_unit, target_breed, t)

			if not _is_enabled or _is_enabled() then
				local tags = target_breed and target_breed.tags or nil

				if
					tags
					and tags.monster
					and (not weight or weight <= 0)
					and _is_monster_targeting_unit(target_unit, unit)
				then
					if _debug_enabled() then
						_debug_log(
							"boss_targeting_bot:" .. tostring(unit),
							_fixed_time(),
							"restoring monster weight for boss targeting bot " .. tostring(target_breed.name)
						)
					end
					weight = DEFAULT_MONSTER_WEIGHT
					override = false
				end
			end

			if perf_t0 then
				_perf.finish("target_selection.monster_weight", perf_t0)
			end
			return weight, override
		end)
	end)
end

M.is_monster_targeting_unit = _is_monster_targeting_unit
M.has_human_player_tag = _has_human_player_tag
M.is_friendly_companion_pin = _is_friendly_companion_pin

return M
