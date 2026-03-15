-- Poxburster targeting (#34): bots ignore poxbursters entirely due to
-- not_bot_target on breed data. We patch the breed to re-enable targeting
-- and suppress only at close range to avoid detonation.
local POXBURSTER_SUPPRESS_DIST = 5
local POXBURSTER_HUMAN_SUPPRESS_DIST = 8
local POXBURSTER_BREED_NAME = "chaos_poxwalker_bomber"
local _poxburster_breed_patched = false

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled

-- One-shot dedup: log poxburster suppression once per bot per encounter
-- instead of every 2s frame. Weak-keyed so entries are GC'd when bots despawn.
local _pox_suppress_logged = setmetatable({}, { __mode = "k" })

local function _is_near_any_position(origin_position, positions, threshold, distance_fn)
	if not origin_position or not positions then
		return false
	end

	local compute_distance = distance_fn or Vector3.distance

	for i = 1, #positions do
		local position = positions[i]
		if position and compute_distance(origin_position, position) < threshold then
			return true
		end
	end

	return false
end

local function _should_suppress_poxburster_positions(
	poxburster_position,
	self_position,
	human_positions,
	bot_threshold,
	human_threshold,
	distance_fn
)
	if _is_near_any_position(poxburster_position, { self_position }, bot_threshold, distance_fn) then
		return true, "too_close_to_bot"
	end

	if _is_near_any_position(poxburster_position, human_positions, human_threshold, distance_fn) then
		return true, "near_human_player"
	end

	return false, nil
end

local function _suppress_reason_for_target(unit, self_position, side)
	if not unit then
		return false, nil
	end

	local data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not data_ext then
		return false, nil
	end

	local breed = data_ext:breed()
	if not breed or breed.name ~= POXBURSTER_BREED_NAME then
		return false, nil
	end

	local pos = POSITION_LOOKUP[unit]
	if not pos then
		return false, nil
	end

	local human_positions = {}
	local human_units = side and side.valid_human_units or nil

	if human_units then
		for i = 1, #human_units do
			local human_unit = human_units[i]
			local human_position = human_unit and POSITION_LOOKUP[human_unit] or nil

			if human_position then
				human_positions[#human_positions + 1] = human_position
			end
		end
	end

	return _should_suppress_poxburster_positions(
		pos,
		self_position,
		human_positions,
		POXBURSTER_SUPPRESS_DIST,
		POXBURSTER_HUMAN_SUPPRESS_DIST
	)
end

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_is_enabled = deps.is_enabled
end

function M.register_hooks()
	-- Breed patch: remove not_bot_target so bots can target poxbursters.
	_mod:hook_require("scripts/settings/breed/breeds/chaos/chaos_poxwalker_bomber_breed", function(breed_data)
		if breed_data.not_bot_target then
			breed_data.not_bot_target = nil
			_poxburster_breed_patched = true
			_debug_log("poxburster_patch", 0, "patched poxburster breed: removed not_bot_target", nil, "info")
		end
	end)

	-- Eagerly patch if breed was already loaded before our hook_require fired.
	local ok, breed = pcall(require, "scripts/settings/breed/breeds/chaos/chaos_poxwalker_bomber_breed")
	if ok and breed and breed.not_bot_target and not _poxburster_breed_patched then
		breed.not_bot_target = nil
		_poxburster_breed_patched = true -- luacheck: ignore 311 (read in hook_require callback above)
		_debug_log("poxburster_patch_eager", 0, "patched poxburster breed (eager): removed not_bot_target", nil, "info")
	end

	-- Close-range suppression: after target selection runs, if the chosen target
	-- is a poxburster within detonation range, clear it so bots don't chase or
	-- shoot at point-blank distance.
	_mod:hook_require("scripts/extension_systems/perception/bot_perception_extension", function(BotPerceptionExtension)
		_mod:hook_safe(
			BotPerceptionExtension,
			"_update_target_enemy",
			function(
				_self,
				self_unit,
				self_position,
				perception_component,
				_behavior_component,
				_enemies_in_proximity,
				side
			)
				if _is_enabled and not _is_enabled() then
					return
				end

				local perf_t0 = _perf and _perf.begin()
				local suppress, reason =
					_suppress_reason_for_target(perception_component.target_enemy, self_position, side)
				if suppress then
					perception_component.target_enemy = nil
					perception_component.target_enemy_distance = math.huge
					perception_component.target_enemy_type = "none"

					if _debug_enabled() and not _pox_suppress_logged[self_unit] then
						_pox_suppress_logged[self_unit] = true
						_debug_log(
							"poxburster_suppress:" .. tostring(self_unit),
							_fixed_time(),
							"suppressed poxburster target (" .. tostring(reason) .. ")",
							nil,
							"debug"
						)
					end
				end

				suppress, reason =
					_suppress_reason_for_target(perception_component.opportunity_target_enemy, self_position, side)
				if suppress then
					perception_component.opportunity_target_enemy = nil
					if _debug_enabled() and not _pox_suppress_logged[self_unit] then
						_pox_suppress_logged[self_unit] = true
						_debug_log(
							"poxburster_suppress_opp:" .. tostring(self_unit),
							_fixed_time(),
							"suppressed poxburster opportunity target (" .. tostring(reason) .. ")",
							nil,
							"debug"
						)
					end
				end

				suppress, reason =
					_suppress_reason_for_target(perception_component.urgent_target_enemy, self_position, side)
				if suppress then
					perception_component.urgent_target_enemy = nil
					if _debug_enabled() and not _pox_suppress_logged[self_unit] then
						_pox_suppress_logged[self_unit] = true
						_debug_log(
							"poxburster_suppress_urg:" .. tostring(self_unit),
							_fixed_time(),
							"suppressed poxburster urgent target (" .. tostring(reason) .. ")",
							nil,
							"debug"
						)
					end
				end

				suppress, reason =
					_suppress_reason_for_target(perception_component.priority_target_enemy, self_position, side)
				if suppress then
					perception_component.priority_target_enemy = nil
					if _debug_enabled() and not _pox_suppress_logged[self_unit] then
						_pox_suppress_logged[self_unit] = true
						_debug_log(
							"poxburster_suppress_pri:" .. tostring(self_unit),
							_fixed_time(),
							"suppressed poxburster priority target (" .. tostring(reason) .. ")",
							nil,
							"debug"
						)
					end
				end

				if perf_t0 then
					_perf.finish("poxburster.update_target_enemy", perf_t0)
				end
			end
		)
	end)
end

M.should_suppress_poxburster_positions = _should_suppress_poxburster_positions

return M
