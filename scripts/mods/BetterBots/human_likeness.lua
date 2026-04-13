local M = {}

local _original_bot_settings = setmetatable({}, { __mode = "k" })
local _patched_bot_settings = setmetatable({}, { __mode = "k" })

local _debug_log
local _debug_enabled
local _get_timing_config
local _get_pressure_leash_config

local DEFAULT_TIMING_CONFIG = {
	enabled = true,
	reaction_min = 2,
	reaction_max = 4,
	defensive_jitter_min_s = 0.10,
	defensive_jitter_max_s = 0.25,
	opportunistic_jitter_min_s = 0.25,
	opportunistic_jitter_max_s = 0.70,
}

local DEFAULT_PRESSURE_LEASH_CONFIG = {
	enabled = true,
	start_rating = 12,
	full_rating = 30,
	scale_multiplier = 0.65,
	floor_m = 7,
}

local function _contains(haystack, needle)
	return haystack and string.find(haystack, needle, 1, true) ~= nil
end

local function _lerp(a, b, t)
	return a + (b - a) * t
end

function M.init(deps)
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_get_timing_config = deps.get_timing_config
	_get_pressure_leash_config = deps.get_pressure_leash_config
end

local function _timing_config()
	if _get_timing_config then
		return _get_timing_config()
	end

	return DEFAULT_TIMING_CONFIG
end

local function _pressure_leash_config()
	if _get_pressure_leash_config then
		return _get_pressure_leash_config()
	end

	return DEFAULT_PRESSURE_LEASH_CONFIG
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

	local config = _timing_config()
	if not config.enabled then
		local original = _original_bot_settings[bot_settings]
		if _restore_original_bot_settings(bot_settings, normal) and _debug_enabled and _debug_enabled() then
			_debug_log(
				"human_likeness_restore",
				0,
				"restored opportunity reaction times (min="
					.. tostring(original.min)
					.. ", max="
					.. tostring(original.max)
					.. ")"
			)
		end
		return
	end

	normal.min = config.reaction_min
	normal.max = config.reaction_max
	_patched_bot_settings[bot_settings] = true

	if _debug_enabled and _debug_enabled() then
		_debug_log(
			"human_likeness_patch",
			0,
			"patched opportunity reaction times (min="
				.. tostring(config.reaction_min)
				.. ", max="
				.. tostring(config.reaction_max)
				.. ")"
		)
	end
end

function M.jitter_bucket_for_rule(rule)
	if not rule then
		return "opportunistic"
	end

	if
		_contains(rule, "ally_aid")
		or _contains(rule, "panic")
		or _contains(rule, "last_stand")
		or _contains(rule, "hazard")
		or _contains(rule, "emergency")
		or _contains(rule, "escape")
		or _contains(rule, "high_peril")
	then
		return "immediate"
	end

	if
		_contains(rule, "protect_interactor")
		or _contains(rule, "critical")
		or _contains(rule, "low_health")
		or _contains(rule, "self_critical")
		or _contains(rule, "low_toughness")
		or _contains(rule, "surrounded")
		or _contains(rule, "overwhelmed")
		or _contains(rule, "pressure")
		or _contains(rule, "high_threat")
		or _contains(rule, "ally_reposition")
	then
		return "defensive"
	end

	return "opportunistic"
end

function M.should_bypass_ability_jitter(rule)
	local config = _timing_config()
	if not config.enabled then
		return true
	end

	return M.jitter_bucket_for_rule(rule) == "immediate"
end

function M.random_ability_jitter_delay(rule)
	local config = _timing_config()
	local bucket = M.jitter_bucket_for_rule(rule)
	local min_s
	local max_s

	if bucket == "defensive" then
		min_s = config.defensive_jitter_min_s
		max_s = config.defensive_jitter_max_s
	else
		min_s = config.opportunistic_jitter_min_s
		max_s = config.opportunistic_jitter_max_s
	end

	return _lerp(min_s, max_s, math.random())
end

function M.scale_engage_leash(effective_leash, challenge_rating_sum)
	local config = _pressure_leash_config()
	if not config.enabled then
		return effective_leash
	end

	local lerp_t = (challenge_rating_sum - config.start_rating) / (config.full_rating - config.start_rating)

	if lerp_t <= 0 then
		return effective_leash
	end

	local challenge_leash = math.max(config.floor_m, effective_leash * config.scale_multiplier)
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
