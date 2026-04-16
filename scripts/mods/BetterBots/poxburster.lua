-- Poxburster targeting (#34) and push counterplay (#54).
-- #34: bots ignore poxbursters due to not_bot_target on breed data. We patch the
-- breed to re-enable targeting and suppress at close range to avoid detonation.
-- #54: within push range, bots enter melee and push instead of ignoring. The
-- poxburster's approach action has explicit push counter-kill logic (power=2000
-- counter-hit when a player pushes during lunge within 5m).
local POXBURSTER_SUPPRESS_DIST = 5
local POXBURSTER_HUMAN_SUPPRESS_DIST = 8
local POXBURSTER_PUSH_DIST = 3
local POXBURSTER_BREED_NAME = "chaos_poxwalker_bomber"
local _poxburster_breed_patched = false
local POXBURSTER_BOT_PERCEPTION_PATCH_SENTINEL = "__bb_poxburster_installed"

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled

-- One-shot dedup: log poxburster suppression once per bot lifetime (weak-keyed,
-- cleared on GC). Entries are never explicitly reset.
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

local function _is_poxburster_in_push_range(unit, self_position)
	if not unit then
		return false
	end

	local data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not data_ext then
		return false
	end

	local breed = data_ext:breed()
	if not breed or breed.name ~= POXBURSTER_BREED_NAME then
		return false
	end

	local pos = POSITION_LOOKUP[unit]
	if not pos then
		return false
	end

	return Vector3.distance(self_position, pos) < POXBURSTER_PUSH_DIST
end

local function _try_suppress_target(perception_component, field_name, log_suffix, self_position, side, self_unit)
	local suppress, reason = _suppress_reason_for_target(perception_component[field_name], self_position, side)
	if not suppress then
		return
	end

	perception_component[field_name] = nil
	if field_name == "target_enemy" then
		perception_component.target_enemy_distance = math.huge
		perception_component.target_enemy_type = "none"
	end

	if _debug_enabled() and not _pox_suppress_logged[self_unit] then
		_pox_suppress_logged[self_unit] = true
		_debug_log(
			"poxburster_suppress" .. log_suffix .. ":" .. tostring(self_unit),
			_fixed_time(),
			"suppressed poxburster " .. field_name .. " (" .. tostring(reason) .. ")",
			nil,
			"debug"
		)
	end
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
end

-- Close-range suppression: after target selection runs, if the chosen target
-- is a poxburster within detonation range, clear it so bots don't chase or
-- shoot at point-blank distance.
function M.install_bot_perception_hooks(BotPerceptionExtension)
	if not BotPerceptionExtension or rawget(BotPerceptionExtension, POXBURSTER_BOT_PERCEPTION_PATCH_SENTINEL) then
		return
	end

	local original = BotPerceptionExtension and BotPerceptionExtension._update_target_enemy
	if type(original) ~= "function" then
		return
	end

	BotPerceptionExtension[POXBURSTER_BOT_PERCEPTION_PATCH_SENTINEL] = true

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

			-- #54: skip target_enemy suppression when poxburster is in push range
			-- so the bot enters melee and pushes instead of ignoring
			local in_push_range = _is_poxburster_in_push_range(perception_component.target_enemy, self_position)
			if not in_push_range then
				_try_suppress_target(perception_component, "target_enemy", "", self_position, side, self_unit)
			elseif _debug_enabled() then
				_debug_log(
					"poxburster_push_range:" .. tostring(self_unit),
					_fixed_time(),
					"poxburster in push range, keeping target for melee push",
					2
				)
			end
			_try_suppress_target(
				perception_component,
				"opportunity_target_enemy",
				"_opp",
				self_position,
				side,
				self_unit
			)
			_try_suppress_target(perception_component, "urgent_target_enemy", "_urg", self_position, side, self_unit)
			_try_suppress_target(perception_component, "priority_target_enemy", "_pri", self_position, side, self_unit)

			if perf_t0 then
				_perf.finish("poxburster.update_target_enemy", perf_t0)
			end
		end
	)
end

-- Called from the consolidated bt_bot_melee_action hook_require in BetterBots.lua (#67).
-- #54: hook melee action to make bots push poxbursters.
-- The approach action has explicit push counter-kill logic: when a player
-- pushes during lunge within 5m, a power=2000 counter-hit triggers
-- staggered_during_lunge → instakill → attributed explosion.
function M.install_melee_hooks(BtBotMeleeAction)
	-- Defend gate: vanilla requires num_melee_attackers > 0, but an
	-- approaching poxburster hasn't attacked yet. Override so the bot
	-- enters the block → push flow.
	_mod:hook(BtBotMeleeAction, "_should_defend", function(func, self, unit, target_unit, scratchpad)
		if _is_enabled and not _is_enabled() then
			return func(self, unit, target_unit, scratchpad)
		end

		local result = func(self, unit, target_unit, scratchpad)
		scratchpad._bb_bot_unit = unit
		if result then
			return result
		end

		local data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
		local target_breed = data_ext and data_ext:breed()
		if target_breed and target_breed.name == POXBURSTER_BREED_NAME then
			if _debug_enabled() then
				_debug_log(
					"poxburster_defend:" .. tostring(unit),
					_fixed_time(),
					"defend gate bypassed for poxburster target",
					2
				)
			end
			return true
		end

		return false
	end)

	-- Push gate: vanilla requires outnumbered (num_enemies > 1). A lone
	-- poxburster fails this. Bypass — pushing is life-or-death here.
	_mod:hook(
		BtBotMeleeAction,
		"_should_push",
		function(func, self, defense_meta_data, scratchpad, in_melee_range, target_unit, target_breed, fixed_t)
			if _is_enabled and not _is_enabled() then
				return func(self, defense_meta_data, scratchpad, in_melee_range, target_unit, target_breed, fixed_t)
			end

			if target_breed and target_breed.name == POXBURSTER_BREED_NAME and in_melee_range then
				local push_action_input = defense_meta_data.push_action_input
				local weapon_extension = scratchpad.weapon_extension
				local push_available =
					weapon_extension:action_input_is_currently_valid("weapon_action", push_action_input, nil, fixed_t)

				if push_available then
					if _debug_enabled() then
						_debug_log(
							"poxburster_push:" .. tostring(target_unit) .. ":" .. tostring(scratchpad._bb_bot_unit),
							fixed_t,
							"pushing poxburster (bypassed outnumbered gate)",
							1
						)
					end
					return true, push_action_input
				else
					if _debug_enabled() then
						_debug_log(
							"poxburster_push_blocked:"
								.. tostring(target_unit)
								.. ":"
								.. tostring(scratchpad._bb_bot_unit),
							fixed_t,
							"poxburster push unavailable (action not valid)",
							2
						)
					end
				end
			end

			return func(self, defense_meta_data, scratchpad, in_melee_range, target_unit, target_breed, fixed_t)
		end
	)
end

M.should_suppress_poxburster_positions = _should_suppress_poxburster_positions
M.is_poxburster_in_push_range = _is_poxburster_in_push_range
M.POXBURSTER_PUSH_DIST = POXBURSTER_PUSH_DIST

return M
