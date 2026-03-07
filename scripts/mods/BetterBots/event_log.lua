local _mod
local _context_snapshot
local _io -- Mods.lua.io backup
local _os -- Mods.lua.os backup

local _buffer = {}
local _file_path = nil
local _enabled = false
local _attempt_counter = 0
local _flush_interval_s = 15
local _flush_max_events = 500
local _last_flush_t = 0

-- Per (bot_slot, ability_name) tracking for false-decision skip counts
local _false_skip_counts = {}

local function _false_skip_key(bot_slot, ability_name)
	return tostring(bot_slot) .. ":" .. tostring(ability_name)
end

local function next_attempt_id()
	_attempt_counter = _attempt_counter + 1
	return _attempt_counter
end

local function _ensure_dump_dir()
	if _os then
		_os.execute("mkdir dump 2>nul")
	end
end

local function _open_file(fixed_t)
	_ensure_dump_dir()
	-- Use wall-clock time for unique filenames; fixed_t is sim time that resets each mission
	local timestamp = _os and tostring(_os.time()) or tostring(math.floor(fixed_t or 0))
	_file_path = "./dump/betterbots_events_" .. timestamp .. ".jsonl"
end

local function _flush()
	if #_buffer == 0 or not _file_path then
		return
	end

	local ok, err = pcall(function()
		local f = _io.open(_file_path, "a")
		if not f then
			return
		end

		for i = 1, #_buffer do
			local success, line = pcall(cjson.encode, _buffer[i])
			if success then
				f:write(line .. "\n")
			end
		end

		f:close()
	end)

	if not ok and _mod then
		_mod:warning("BetterBots: event_log flush failed: " .. tostring(err))
	end

	_buffer = {}
end

local function emit(event)
	if not _enabled then
		return
	end

	_buffer[#_buffer + 1] = event

	if #_buffer >= _flush_max_events then
		_flush()
	end
end

local function emit_decision(fixed_t, bot_slot, ability_name, template_name, result, rule, source, context)
	if not _enabled then
		return
	end

	local ctx_snap = _context_snapshot and _context_snapshot(context) or {}

	if result then
		-- All true decisions logged
		emit({
			t = fixed_t,
			event = "decision",
			bot = bot_slot,
			ability = ability_name,
			template = template_name,
			result = true,
			rule = rule,
			source = source,
			ctx = ctx_snap,
		})
	else
		-- False decisions: track skip count, emit with count
		local key = _false_skip_key(bot_slot, ability_name)
		local entry = _false_skip_counts[key]
		if not entry then
			entry = { count = 0, last_rule = nil }
			_false_skip_counts[key] = entry
		end

		entry.count = entry.count + 1
		entry.last_rule = rule

		-- Emit every false decision but with skip count for weighting
		-- This keeps volume manageable because _debug_log already throttles
		-- the call sites; event_log just records what reaches it
		emit({
			t = fixed_t,
			event = "decision",
			bot = bot_slot,
			ability = ability_name,
			template = template_name,
			result = false,
			rule = rule,
			source = source,
			skipped_since_last = entry.count,
			ctx = ctx_snap,
		})
		entry.count = 0
	end
end

local function try_flush(fixed_t)
	if not _enabled then
		return
	end

	if fixed_t - _last_flush_t >= _flush_interval_s then
		_flush()
		_last_flush_t = fixed_t
	end
end

local function start_session(fixed_t)
	if not _enabled then
		return
	end

	_attempt_counter = 0
	_false_skip_counts = {}
	_buffer = {}
	_open_file(fixed_t)
	_last_flush_t = fixed_t
end

local function end_session()
	if not _enabled then
		return
	end

	_flush()
	_file_path = nil
end

local function is_enabled()
	return _enabled
end

return {
	init = function(deps)
		_mod = deps.mod
		_context_snapshot = deps.context_snapshot

		local mods_lua = rawget(_G, "Mods")
		_io = mods_lua and mods_lua.lua and mods_lua.lua.io
		_os = mods_lua and mods_lua.lua and mods_lua.lua.os

		if not _io then
			if _mod then
				_mod:warning("BetterBots: event_log disabled (Mods.lua.io unavailable)")
			end
			return
		end

		if not rawget(_G, "cjson") then
			if _mod then
				_mod:warning("BetterBots: event_log disabled (cjson unavailable)")
			end
			return
		end
	end,
	set_enabled = function(enabled)
		_enabled = enabled == true
	end,
	emit = emit,
	emit_decision = emit_decision,
	next_attempt_id = next_attempt_id,
	try_flush = try_flush,
	start_session = start_session,
	end_session = end_session,
	is_enabled = is_enabled,
	-- Test-only accessors
	_get_buffer = function()
		return _buffer
	end,
	_reset = function()
		_buffer = {}
		_file_path = nil
		_enabled = false
		_attempt_counter = 0
		_false_skip_counts = {}
		_last_flush_t = 0
	end,
}
