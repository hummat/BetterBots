local M = {}

local OPPORTUNITY_REACTION_MIN = 2
local OPPORTUNITY_REACTION_MAX = 5
local ABILITY_JITTER_MIN_S = 0.3
local ABILITY_JITTER_MAX_S = 1.5
local START_CHALLENGE_VALUE = 10
local MAX_CHALLENGE_VALUE = 30
local MIN_LEASH_FLOOR = 6

local _patched_bot_settings = setmetatable({}, { __mode = "k" })

local function _contains(haystack, needle)
	return haystack and string.find(haystack, needle, 1, true) ~= nil
end

local function _lerp(a, b, t)
	return a + (b - a) * t
end

function M.init(_) end

function M.patch_bot_settings(bot_settings)
	if not bot_settings or _patched_bot_settings[bot_settings] then
		return
	end

	local times = bot_settings.opportunity_target_reaction_times
	local normal = times and times.normal
	if normal then
		normal.min = OPPORTUNITY_REACTION_MIN
		normal.max = OPPORTUNITY_REACTION_MAX
	end

	_patched_bot_settings[bot_settings] = true
end

function M.should_bypass_ability_jitter(rule)
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
	local lerp_t = (challenge_rating_sum - START_CHALLENGE_VALUE) / (MAX_CHALLENGE_VALUE - START_CHALLENGE_VALUE)

	if lerp_t <= 0 then
		return effective_leash
	end

	local challenge_leash = math.max(MIN_LEASH_FLOOR, effective_leash * 0.5)
	if lerp_t >= 1 then
		return challenge_leash
	end

	return _lerp(effective_leash, challenge_leash, lerp_t * lerp_t)
end

return M
