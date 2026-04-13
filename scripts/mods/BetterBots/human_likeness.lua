local M = {}

local OPPORTUNITY_REACTION_MIN = 2 -- Seconds before reacting to opportunity targets (min)
local OPPORTUNITY_REACTION_MAX = 5 -- Seconds before reacting to opportunity targets (max)
local ABILITY_JITTER_MIN_S = 0.3 -- Random delay before ability activation (min)
local ABILITY_JITTER_MAX_S = 1.5 -- Random delay before ability activation (max)
local START_CHALLENGE_VALUE = 10 -- Challenge rating sum where leash scaling begins
local MAX_CHALLENGE_VALUE = 30 -- Challenge rating sum where leash is fully tightened
local MIN_LEASH_FLOOR = 6 -- Minimum effective leash distance (meters)

local _original_bot_settings = setmetatable({}, { __mode = "k" })
local _patched_bot_settings = setmetatable({}, { __mode = "k" })

local _debug_log
local _debug_enabled
local _is_enabled

local function _contains(haystack, needle)
	return haystack and string.find(haystack, needle, 1, true) ~= nil
end

local function _lerp(a, b, t)
	return a + (b - a) * t
end

function M.init(deps)
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_enabled = deps.is_enabled
end

local function _restore_original_bot_settings(bot_settings, normal)
	local original = _original_bot_settings[bot_settings]
	if not original then
		return false
	end

	normal.min = original.min
	normal.max = original.max
	_patched_bot_settings[bot_settings] = nil

	return true
end

function M.patch_bot_settings(bot_settings)
	if not bot_settings then
		return
	end

	local times = bot_settings.opportunity_target_reaction_times
	local normal = times and times.normal
	if not normal then
		return
	end

	if not _original_bot_settings[bot_settings] then
		_original_bot_settings[bot_settings] = {
			min = normal.min,
			max = normal.max,
		}
	end

	if _is_enabled and not _is_enabled() then
		if _restore_original_bot_settings(bot_settings, normal) and _debug_enabled and _debug_enabled() then
			_debug_log(
				"human_likeness_restore",
				0,
				"restored opportunity reaction times (min="
					.. tostring(_original_bot_settings[bot_settings].min)
					.. ", max="
					.. tostring(_original_bot_settings[bot_settings].max)
					.. ")"
			)
		end
		return
	end

	if _patched_bot_settings[bot_settings] then
		return
	end

	normal.min = OPPORTUNITY_REACTION_MIN
	normal.max = OPPORTUNITY_REACTION_MAX
	_patched_bot_settings[bot_settings] = true

	if _debug_enabled and _debug_enabled() then
		_debug_log(
			"human_likeness_patch",
			0,
			"patched opportunity reaction times (min="
				.. OPPORTUNITY_REACTION_MIN
				.. ", max="
				.. OPPORTUNITY_REACTION_MAX
				.. ")"
		)
	end
end

function M.should_bypass_ability_jitter(rule)
	if _is_enabled and not _is_enabled() then
		return true
	end

	if not rule then
		return false
	end

	return _contains(rule, "ally_aid")
		or _contains(rule, "panic")
		or _contains(rule, "last_stand")
		or _contains(rule, "hazard")
end

function M.random_ability_jitter_delay()
	return _lerp(ABILITY_JITTER_MIN_S, ABILITY_JITTER_MAX_S, math.random())
end

function M.scale_engage_leash(effective_leash, challenge_rating_sum)
	if _is_enabled and not _is_enabled() then
		return effective_leash
	end

	local lerp_t = (challenge_rating_sum - START_CHALLENGE_VALUE) / (MAX_CHALLENGE_VALUE - START_CHALLENGE_VALUE)

	if lerp_t <= 0 then
		return effective_leash
	end

	local challenge_leash = math.max(MIN_LEASH_FLOOR, effective_leash * 0.5)
	local result
	if lerp_t >= 1 then
		result = challenge_leash
	else
		-- Quadratic ease-in: tightens slowly at low pressure, rapidly at high
		result = _lerp(effective_leash, challenge_leash, lerp_t * lerp_t)
	end

	if _debug_enabled and _debug_enabled() then
		_debug_log(
			"human_likeness_leash_scale",
			0,
			"leash scaled "
				.. tostring(effective_leash)
				.. " -> "
				.. string.format("%.1f", result)
				.. " (pressure="
				.. tostring(challenge_rating_sum)
				.. ")"
		)
	end

	return result
end

return M
