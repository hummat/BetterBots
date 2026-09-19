-- suppression_guard.lua — guard a vanilla suppression LOS bookkeeping crash
-- when a suppressing attacker lacks the minion-style enemy aim node.
-- luacheck: globals Unit
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _wrap_engine_field
local _wrap_fallback_warned = false

-- Raw field replacement, so DMF's hooks_unload never restores it on reload and
-- the live field still holds the previous load's wrapper. The registry behind
-- this dep unwraps back to what we originally wrapped (#116).
local function _wrap(target, key, make_wrapper)
	if _wrap_engine_field then
		return _wrap_engine_field(target, key, make_wrapper)
	end

	if not _wrap_fallback_warned then
		_wrap_fallback_warned = true
		if _mod and _mod.warning then
			_mod:warning("BetterBots: suppression_guard missing wrap_engine_field dep; reload safety disabled")
		end
	end

	local original = target[key]
	if original == nil then
		return nil
	end

	local wrapper = make_wrapper(original)
	if type(wrapper) == "function" then
		target[key] = wrapper
	end

	return original
end

local SUPPRESSION_PATH = "scripts/utilities/attack/suppression"
local SUPPRESSION_SENTINEL = "__bb_suppression_guard_installed"
local _logged_missing_node_by_attacker = setmetatable({}, { __mode = "k" })
local _logged_missing_node_by_label = {}
local unpack_results = unpack
if table and table.unpack then -- luacheck: ignore 143
	unpack_results = table.unpack -- luacheck: ignore 143
end

local function _hook_require_now(path, callback)
	local hook_require_now = _mod and _mod.hook_require_now
	if hook_require_now then
		return hook_require_now(_mod, path, callback, 4)
	end

	if _mod and _mod.warning and _mod._raw_hook_require then
		_mod:warning("BetterBots: hook_require_now_missing for " .. tostring(path))
	end
	return _mod["hook_require"](_mod, path, callback)
end

local function _is_guarded_missing_node_error(err)
	local message = tostring(err)

	return message:find(SUPPRESSION_PATH .. ".lua", 1, true) ~= nil
		and message:find("UnitApi node failed", 1, true) ~= nil
		and message:find("was not found in unit", 1, true) ~= nil
end

local function _log_dedup_state(attacking_unit)
	local unit_type = type(attacking_unit)
	if unit_type == "table" or unit_type == "userdata" then
		return _logged_missing_node_by_attacker, attacking_unit
	end

	return _logged_missing_node_by_label, tostring(attacking_unit)
end

local function _log_guard(attacking_unit, err)
	if not (_debug_enabled and _debug_enabled() and _debug_log) then
		return
	end

	local key = "suppression_guard:" .. tostring(attacking_unit)
	local logged_by_unit, log_key = _log_dedup_state(attacking_unit)
	if logged_by_unit[log_key] then
		return
	end

	logged_by_unit[log_key] = true
	_debug_log(
		key,
		_fixed_time and _fixed_time() or 0,
		"guarded vanilla suppression missing-node crash (attacker="
			.. tostring(attacking_unit)
			.. ", err="
			.. tostring(err)
			.. ")",
		nil,
		"warning"
	)
end

local function _call_guarded(original, attacking_unit, ...)
	local results = { pcall(original, ...) }
	local ok = results[1]
	if ok then
		return unpack_results(results, 2)
	end

	local err = results[2]
	if _is_guarded_missing_node_error(err) then
		-- Vanilla has already applied suppression, aggro, and alert side effects here;
		-- swallowing only skips the LOS-position bookkeeping write that crashed.
		_log_guard(attacking_unit, err)
		return nil
	end

	error(err, 0)
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_wrap_engine_field = deps.wrap_engine_field
end

function M.install(Suppression)
	if not Suppression or rawget(Suppression, SUPPRESSION_SENTINEL) == M then
		return
	end

	if
		type(Suppression.apply_suppression) ~= "function"
		or type(Suppression.apply_area_minion_suppression) ~= "function"
	then
		return
	end

	Suppression[SUPPRESSION_SENTINEL] = M

	_wrap(Suppression, "apply_suppression", function(original)
		return function(hit_unit, attacking_unit, ...)
			return _call_guarded(original, attacking_unit, hit_unit, attacking_unit, ...)
		end
	end)

	_wrap(Suppression, "apply_area_minion_suppression", function(original)
		return function(attacking_unit, ...)
			return _call_guarded(original, attacking_unit, attacking_unit, ...)
		end
	end)
end

function M.register_hooks()
	_hook_require_now(SUPPRESSION_PATH, M.install)
end

return M
