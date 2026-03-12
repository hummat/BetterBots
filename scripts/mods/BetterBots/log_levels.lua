local M = {}

local LEVELS = {
	info = 1,
	debug = 2,
	trace = 3,
}

function M.resolve_setting(setting_value)
	if setting_value == true then
		return LEVELS.debug
	end

	if setting_value == "info" then
		return LEVELS.info
	end

	if setting_value == "debug" then
		return LEVELS.debug
	end

	if setting_value == "trace" then
		return LEVELS.trace
	end

	return 0
end

function M.should_log(active_level, call_level)
	if not active_level or active_level <= 0 then
		return false
	end

	local normalized_call_level = LEVELS[call_level or "debug"] or LEVELS.debug

	return normalized_call_level <= active_level
end

function M.level_name(active_level)
	if active_level == LEVELS.info then
		return "info"
	end

	if active_level == LEVELS.debug then
		return "debug"
	end

	if active_level == LEVELS.trace then
		return "trace"
	end

	return "off"
end

M.levels = LEVELS

return M
