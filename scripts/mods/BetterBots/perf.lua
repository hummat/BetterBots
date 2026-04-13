local M = {}

local _get_setting
local _setting_id
local _enabled = false
local _total_s = 0
local _total_calls = 0
local _bot_frames = 0
local _tag_stats = {}

local function _sorted_rows(tags)
	local rows = {}
	for tag, stats in pairs(tags or {}) do
		rows[#rows + 1] = {
			tag = tag,
			total_us = stats.total_us,
			calls = stats.calls,
			avg_us_per_call = stats.avg_us_per_call,
		}
	end

	table.sort(rows, function(a, b)
		if a.total_us == b.total_us then
			return a.tag < b.tag
		end

		return a.total_us > b.total_us
	end)

	return rows
end

local function _reset_counters()
	_total_s = 0
	_total_calls = 0
	_bot_frames = 0
	_tag_stats = {}
end

local function _setting_enabled()
	return _get_setting and _get_setting(_setting_id) == true or false
end

function M.init(deps)
	_get_setting = deps.get_setting
	_setting_id = deps.setting_id
	_enabled = false
	_reset_counters()
end

function M.enter_run()
	_enabled = _setting_enabled()
	_reset_counters()
end

function M.sync_setting()
	local enabled = _setting_enabled()

	if enabled == _enabled then
		return _enabled
	end

	if enabled then
		_reset_counters()
	end

	_enabled = enabled

	return _enabled
end

function M.is_enabled()
	return _enabled
end

function M.begin()
	if not _enabled then
		return nil
	end

	return os.clock()
end

function M.finish(tag, start_clock, elapsed_s, opts)
	if not (tag and start_clock) then
		return
	end

	local duration_s = elapsed_s or (os.clock() - start_clock)
	local stats = _tag_stats[tag]

	if not stats then
		stats = {
			total_s = 0,
			calls = 0,
		}
		_tag_stats[tag] = stats
	end

	stats.total_s = stats.total_s + duration_s
	stats.calls = stats.calls + 1

	if not (opts and opts.include_total == false) then
		_total_s = _total_s + duration_s
		_total_calls = _total_calls + 1
	end
end

function M.mark_bot_frame()
	if not _enabled then
		return
	end

	_bot_frames = _bot_frames + 1
end

function M.report_and_reset()
	if _total_calls == 0 then
		return nil
	end

	local tags = {}
	for tag, stats in pairs(_tag_stats) do
		tags[tag] = {
			total_us = stats.total_s * 1e6,
			calls = stats.calls,
			avg_us_per_call = stats.total_s / stats.calls * 1e6,
		}
	end

	local report = {
		total_calls = _total_calls,
		total_us = _total_s * 1e6,
		bot_frames = _bot_frames,
		total_us_per_bot_frame = _bot_frames > 0 and (_total_s / _bot_frames * 1e6) or nil,
		tags = tags,
	}

	_reset_counters()

	return report
end

function M.format_report_lines(report, prefix)
	if not report then
		return nil
	end

	local resolved_prefix = prefix or "bb-perf:"
	local lines = {
		string.format(
			"%s %.1f µs/bot/frame total (%d bot frames, %d calls, %.3f ms total)",
			resolved_prefix,
			report.total_us_per_bot_frame or 0,
			report.bot_frames,
			report.total_calls,
			report.total_us / 1000
		),
	}

	local rows = _sorted_rows(report.tags)
	for i = 1, #rows do
		local row = rows[i]
		lines[#lines + 1] = string.format(
			"%s %s %.3f ms total (%d calls, %.1f µs/call)",
			resolved_prefix,
			row.tag,
			row.total_us / 1000,
			row.calls,
			row.avg_us_per_call
		)
	end

	return lines
end

return M
