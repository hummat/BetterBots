# Structured Event Logging (JSONL) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a parallel JSONL event log that captures decisions (true and false), queued actions, charge consumes, item stages, and periodic snapshots — with per-attempt correlation IDs and per-bot identity — for post-mission heuristic tuning.

**Architecture:** New `event_log.lua` sub-module owns a memory buffer, serializes events via `cjson.encode()`, and flushes to `./dump/betterbots_events_<timestamp>.jsonl` every 15s or 500 events. All events carry `attempt_id` (monotonic counter) and `bot` (slot index) for correlation. Existing `mod:echo` debug logging is untouched. False decisions are logged with a `skipped_since_last` count per (bot, ability) instead of raw sampling.

**Tech Stack:** Lua 5.1/LuaJIT, cjson (engine global), Mods.lua.io (DMF file I/O), busted (tests), jq (bb-log analysis)

---

## Conventions

- Worktree: `/run/media/matthias/1274B04B74B032F9/git/BetterBots-29/`
- All file paths below are relative to the worktree root.
- Run commands from the worktree root: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && <cmd>`
- Tests: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make test`
- Full check: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`

---

## Task 1: Create event_log.lua — buffer, serialize, flush

**Files:**
- Create: `scripts/mods/BetterBots/event_log.lua`
- Modify: `.luacheckrc` (add `cjson` to read_globals)
- Modify: `.luarc.json` (add `cjson` to diagnostics.globals)

**Step 1: Write event_log.lua**

This module manages a memory buffer of event tables, serializes them via `cjson.encode()`, and flushes to a JSONL file. It uses `context_snapshot()` from debug.lua for JSON-safe context serialization.

```lua
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
	local timestamp = tostring(math.floor(fixed_t or 0))
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
```

**Step 2: Add `cjson` to static analysis globals**

In `.luacheckrc`, add `"cjson"` to read_globals:
```lua
read_globals = {
	"get_mod",
	"ScriptUnit",
	"cjson",
}
```

In `.luarc.json`, add `"cjson"` to diagnostics.globals:
```json
"globals": [
	"get_mod",
	"ScriptUnit",
	"cjson"
]
```

**Step 3: Run static checks**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS (existing tests still pass, new file has no lint errors)

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/event_log.lua .luacheckrc .luarc.json
git commit -m "feat(event_log): add JSONL event buffer with cjson serialization (#29)"
```

---

## Task 2: Write event_log tests

**Files:**
- Create: `tests/event_log_spec.lua`

**Step 1: Write the test file**

Tests cover: buffer accumulation, emit_decision with true/false and skip counts, attempt_id monotonicity, enable/disable gating, flush threshold. No file I/O in tests (we test the buffer, not the file writes).

```lua
-- Stub cjson for test environment
_G.cjson = _G.cjson or {
	encode = function(t)
		-- Minimal JSON-like serialization for test assertions
		return tostring(t)
	end,
}

local EventLog = dofile("scripts/mods/BetterBots/event_log.lua")

describe("event_log", function()
	before_each(function()
		EventLog._reset()
		EventLog.init({
			mod = { warning = function() end },
			context_snapshot = function(ctx)
				return { num_nearby = ctx and ctx.num_nearby or 0 }
			end,
		})
	end)

	describe("emit", function()
		it("does not buffer when disabled", function()
			EventLog.set_enabled(false)
			EventLog.emit({ event = "test" })
			assert.are.equal(0, #EventLog._get_buffer())
		end)

		it("buffers when enabled", function()
			EventLog.set_enabled(true)
			EventLog.emit({ event = "test" })
			assert.are.equal(1, #EventLog._get_buffer())
		end)

		it("accumulates multiple events", function()
			EventLog.set_enabled(true)
			EventLog.emit({ event = "a" })
			EventLog.emit({ event = "b" })
			EventLog.emit({ event = "c" })
			assert.are.equal(3, #EventLog._get_buffer())
		end)
	end)

	describe("emit_decision", function()
		it("logs true decisions with context snapshot", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", true, "some_rule", "bt", { num_nearby = 5 })
			local buf = EventLog._get_buffer()
			assert.are.equal(1, #buf)
			assert.are.equal("decision", buf[1].event)
			assert.is_true(buf[1].result)
			assert.are.equal("some_rule", buf[1].rule)
			assert.are.equal(1, buf[1].bot)
			assert.are.equal("bt", buf[1].source)
			assert.are.equal(5, buf[1].ctx.num_nearby)
		end)

		it("logs false decisions with skipped_since_last", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", false, "hold_a", "fallback", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(1, #buf)
			assert.is_false(buf[1].result)
			assert.are.equal(1, buf[1].skipped_since_last)
		end)

		it("increments skip count across false decisions then resets", function()
			EventLog.set_enabled(true)
			-- First false
			EventLog.emit_decision(100, 2, "ogryn_charge", "ogryn_charge", false, "hold", "fallback", {})
			-- Second false
			EventLog.emit_decision(101, 2, "ogryn_charge", "ogryn_charge", false, "hold", "fallback", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(2, #buf)
			assert.are.equal(1, buf[1].skipped_since_last)
			assert.are.equal(1, buf[2].skipped_since_last) -- reset after each emit
		end)

		it("tracks skip counts per bot+ability independently", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", false, "hold", "bt", {})
			EventLog.emit_decision(100, 2, "ogryn_charge", "ogryn_charge", false, "hold", "bt", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(1, buf[1].skipped_since_last)
			assert.are.equal(1, buf[2].skipped_since_last)
		end)
	end)

	describe("next_attempt_id", function()
		it("returns monotonically increasing IDs", function()
			local id1 = EventLog.next_attempt_id()
			local id2 = EventLog.next_attempt_id()
			local id3 = EventLog.next_attempt_id()
			assert.are.equal(1, id1)
			assert.are.equal(2, id2)
			assert.are.equal(3, id3)
		end)

		it("resets on start_session", function()
			EventLog.set_enabled(true)
			EventLog.next_attempt_id()
			EventLog.next_attempt_id()
			EventLog.start_session(0)
			local id = EventLog.next_attempt_id()
			assert.are.equal(1, id)
		end)
	end)

	describe("is_enabled", function()
		it("reflects set_enabled state", function()
			assert.is_false(EventLog.is_enabled())
			EventLog.set_enabled(true)
			assert.is_true(EventLog.is_enabled())
			EventLog.set_enabled(false)
			assert.is_false(EventLog.is_enabled())
		end)
	end)
end)
```

**Step 2: Run tests**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make test`
Expected: All tests pass (existing + new event_log tests)

**Step 3: Commit**

```bash
git add tests/event_log_spec.lua
git commit -m "test(event_log): add buffer, emit_decision, attempt_id tests (#29)"
```

---

## Task 3: Add mod setting and wire event_log into BetterBots.lua

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua` (load module, init, wire, enable/disable)

**Step 1: Add the setting widget**

In `BetterBots_data.lua`, add after the `enable_debug_logs` widget:
```lua
{
	setting_id = "enable_event_log",
	type = "checkbox",
	default_value = false,
},
```

**Step 2: Add localization strings**

In `BetterBots_localization.lua`, add:
```lua
enable_event_log = {
	en = "Enable event log (JSONL)",
},
```

**Step 3: Wire event_log into BetterBots.lua**

After the `Debug` module load (around line 77), add:
```lua
local EventLog = mod:io_dofile("BetterBots/scripts/mods/BetterBots/event_log")
assert(EventLog, "BetterBots: failed to load event_log module")
```

After `Debug.init(...)` (around line 115), add:
```lua
EventLog.init({
	mod = mod,
	context_snapshot = Debug.context_snapshot,
})
```

Add a constant near top of file (after `DEBUG_FORCE_ENABLED`):
```lua
local EVENT_LOG_SETTING_ID = "enable_event_log"
```

In `mod.on_game_state_changed` (the `GameplayStateRun` enter block), add after the existing cache clears:
```lua
EventLog.set_enabled(mod:get(EVENT_LOG_SETTING_ID) == true)
EventLog.start_session(_fixed_time())
```

In `mod.on_game_state_changed`, add a new block for state exit:
```lua
if status == "exit" and state == "GameplayStateRun" then
	EventLog.end_session()
end
```

In the `BotBehaviorExtension.update` hook_safe (line 688-698), add after `_fallback_try_queue_combat_ability(unit, blackboard)`:
```lua
EventLog.try_flush(_fixed_time())
```

**Step 4: Run checks**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots_data.lua scripts/mods/BetterBots/BetterBots_localization.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(event_log): add mod setting and wire lifecycle into main (#29)"
```

---

## Task 4: Emit decision events from BT condition hook and fallback loop

This is the core wiring — adding `emit_decision` calls at both decision points, plus `attempt_id` on queued/consumed events.

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Modify: `scripts/mods/BetterBots/debug.lua` (expose `_collect_alive_bots` + add `bot_slot_for_unit`)

**Step 1: Add bot slot lookup helper to debug.lua**

Add a function to resolve a unit's player slot (needed for bot identification in events). After `_collect_alive_bots()` (around line 149), add:

```lua
local function bot_slot_for_unit(unit)
	local manager_table = rawget(_G, "Managers")
	local player_manager = manager_table and manager_table.player
	if not player_manager then
		return nil
	end

	local players = player_manager:players()
	if not players then
		return nil
	end

	for _, player in pairs(players) do
		if player and not player:is_human_controlled() and player.player_unit == unit then
			return type(player.slot) == "function" and player:slot() or nil
		end
	end

	return nil
end
```

Export it in the return table:
```lua
bot_slot_for_unit = bot_slot_for_unit,
```

**Step 2: Wire EventLog into Debug.wire() so it's available cross-module**

No change needed — EventLog is accessed directly from BetterBots.lua where both decision points live.

**Step 3: Emit decision events in _can_activate_ability (BT condition hook)**

In `_can_activate_ability`, after the `Heuristics.resolve_decision` call and `Debug.log_ability_decision` (around line 236), add:

```lua
if EventLog.is_enabled() then
	local bot_slot = Debug.bot_slot_for_unit(unit)
	EventLog.emit_decision(
		fixed_t,
		bot_slot,
		_equipped_combat_ability_name(unit),
		ability_template_name,
		can_activate,
		rule,
		"bt",
		context
	)
end
```

Also handle the zealot_relic special case (around line 221):
```lua
if EventLog.is_enabled() then
	local bot_slot = Debug.bot_slot_for_unit(unit)
	EventLog.emit_decision(
		fixed_t,
		bot_slot,
		"zealot_relic",
		ability_template_name,
		can_activate,
		"zealot_relic_vanilla",
		"bt",
		Heuristics.build_context(unit, blackboard)
	)
end
```

**Step 4: Emit decision events in _fallback_try_queue_combat_ability**

After `Heuristics.resolve_decision` in the fallback loop (around line 393), emit for both true and false:

```lua
if EventLog.is_enabled() then
	local bot_slot = Debug.bot_slot_for_unit(unit)
	EventLog.emit_decision(
		fixed_t,
		bot_slot,
		_equipped_combat_ability_name(unit),
		ability_template_name,
		can_activate,
		rule,
		"fallback",
		context
	)
end
```

**Step 5: Emit queued event with attempt_id when fallback queues input**

After `action_input_extension:bot_queue_action_input(...)` in the fallback success path (around line 412), add:

```lua
local attempt_id = EventLog.next_attempt_id()
if EventLog.is_enabled() then
	local bot_slot = Debug.bot_slot_for_unit(unit)
	EventLog.emit({
		t = fixed_t,
		event = "queued",
		bot = bot_slot,
		ability = _equipped_combat_ability_name(unit),
		template = ability_template_name,
		input = action_input,
		source = "fallback",
		rule = rule,
		attempt_id = attempt_id,
	})
end
```

Store `attempt_id` in fallback state for correlation:
```lua
state.attempt_id = attempt_id
```

**Step 6: Emit consumed event with attempt_id**

In the `use_ability_charge` hook_safe (around line 566), add after `_last_charge_event_by_unit[unit]` is set:

```lua
if EventLog.is_enabled() then
	local bot_slot = Debug.bot_slot_for_unit(unit)
	local fb_state = _fallback_state_by_unit[unit]
	EventLog.emit({
		t = fixed_t,
		event = "consumed",
		bot = bot_slot,
		ability = ability_name,
		charges = optional_num_charges or 1,
		attempt_id = fb_state and fb_state.attempt_id or nil,
	})
end
```

**Step 7: Run checks**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS

**Step 8: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua scripts/mods/BetterBots/debug.lua
git commit -m "feat(event_log): emit decision, queued, consumed events with attempt_id (#29)"
```

---

## Task 5: Emit item_stage and blocked events from item_fallback.lua

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua` (pass EventLog + Debug to ItemFallback.init)

**Step 1: Pass EventLog and bot_slot_for_unit to ItemFallback**

In `BetterBots.lua`, update `ItemFallback.init(...)` to include:
```lua
event_log = EventLog,
bot_slot_for_unit = Debug.bot_slot_for_unit,
```

**Step 2: Store references in item_fallback.lua**

Add module-level locals:
```lua
local _event_log
local _bot_slot_for_unit
```

In `init()`, capture them:
```lua
_event_log = deps.event_log
_bot_slot_for_unit = deps.bot_slot_for_unit
```

**Step 3: Emit item_stage events at stage transitions**

Add a helper at the top of item_fallback.lua (after the module locals):

```lua
local function _emit_item_event(event_type, unit, ability_name, state, fixed_t, extra)
	if not _event_log or not _event_log.is_enabled() then
		return
	end

	local ev = {
		t = fixed_t,
		event = event_type,
		bot = _bot_slot_for_unit and _bot_slot_for_unit(unit) or nil,
		ability = ability_name,
		stage = state.item_stage,
		profile = state.item_profile_name,
		attempt_id = state.attempt_id,
	}

	if extra then
		for k, v in pairs(extra) do
			ev[k] = v
		end
	end

	_event_log.emit(ev)
end
```

Add `_emit_item_event("item_stage", ...)` calls at each stage transition in `try_queue_item()`:

1. After `state.item_stage = "waiting_wield"` (wield queued, around line 769):
   ```lua
   _emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = "combat_ability" })
   ```

2. After `state.item_stage = "waiting_start"` (profile selected, around line 519):
   ```lua
   _emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_start_input })
   ```

3. In `_queue_item_start_input`, after setting `state.item_stage` (around line 366-372):
   ```lua
   _emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_start_input })
   ```

4. After `state.item_stage = "waiting_unwield"` (around line 650):
   ```lua
   _emit_item_event("item_stage", unit, ability_name, state, fixed_t, { input = state.item_followup_input })
   ```

5. After `_transition_to_charge_confirmation` calls (around lines 667, 711):
   ```lua
   _emit_item_event("item_stage", unit, ability_name, state, fixed_t)
   ```

**Step 4: Emit blocked events at failure points**

At each `_schedule_item_sequence_retry` or `_reset_item_sequence_state` failure call, emit:
```lua
_emit_item_event("blocked", unit, ability_name, state, fixed_t, { reason = "<specific_reason>" })
```

Key failure points (6 total):
- Wield timeout (line ~486): `reason = "wield_timeout"`
- Unsupported weapon template (line ~506): `reason = "unsupported_template"`
- Lost wield before start (line ~555): `reason = "lost_wield_before_start"`
- Start input drift (line ~580): `reason = "start_input_drift"`
- Lost wield before followup (line ~605): `reason = "lost_wield_before_followup"`
- Followup input drift (line ~630): `reason = "followup_input_drift"`

**Step 5: Emit item queued events**

In `_queue_item_start_input` (around line 355), after the `_queue_weapon_action_input` call, emit:
```lua
if _event_log and _event_log.is_enabled() then
	state.attempt_id = _event_log.next_attempt_id()
	_emit_item_event("queued", unit, ability_name, state, fixed_t, {
		input = state.item_start_input,
		source = "item",
		rule = "item_fallback",
	})
end
```

**Step 6: Run checks**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS

**Step 7: Commit**

```bash
git add scripts/mods/BetterBots/item_fallback.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(event_log): emit item_stage, blocked, queued events from item fallback (#29)"
```

---

## Task 6: Emit session_start and snapshot events

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

**Step 1: Emit session_start with bot lineup**

The session_start event should be deferred to the first `BotBehaviorExtension.update` tick where bots are present, not at `GameplayStateRun` enter (bots may not be spawned yet).

Add a flag near the fallback state tables:
```lua
local _session_start_emitted = false
```

In `mod.on_game_state_changed` (GameplayStateRun enter), add:
```lua
_session_start_emitted = false
```

In the `BotBehaviorExtension.update` hook_safe, before `_fallback_try_queue_combat_ability`, add:
```lua
if EventLog.is_enabled() and not _session_start_emitted then
	local bots = Debug.collect_alive_bots()
	if bots and #bots > 0 then
		_session_start_emitted = true
		local bot_info = {}
		for i, bot_entry in ipairs(bots) do
			local p = bot_entry.player
			bot_info[i] = {
				slot = type(p.slot) == "function" and p:slot() or nil,
				archetype = type(p.archetype_name) == "function" and p:archetype_name() or nil,
				ability = _equipped_combat_ability_name(bot_entry.unit),
			}
		end
		EventLog.emit({
			t = _fixed_time(),
			event = "session_start",
			version = META_PATCH_VERSION,
			bots = bot_info,
		})
	end
end
```

Export `_collect_alive_bots` from debug.lua as `collect_alive_bots` (it's currently local). In debug.lua's return table, add:
```lua
collect_alive_bots = _collect_alive_bots,
```

**Step 2: Emit periodic snapshot events**

Add a snapshot interval constant and per-unit tracking:
```lua
local _SNAPSHOT_INTERVAL_S = 30
local _last_snapshot_t_by_unit = setmetatable({}, { __mode = "k" })
```

In `mod.on_game_state_changed` (GameplayStateRun enter):
```lua
for unit in pairs(_last_snapshot_t_by_unit) do
	_last_snapshot_t_by_unit[unit] = nil
end
```

In the `BotBehaviorExtension.update` hook_safe, after the `_fallback_try_queue_combat_ability` call:
```lua
if EventLog.is_enabled() then
	local fixed_t = _fixed_time()
	local last_snap = _last_snapshot_t_by_unit[unit]
	if not last_snap or fixed_t - last_snap >= _SNAPSHOT_INTERVAL_S then
		_last_snapshot_t_by_unit[unit] = fixed_t
		local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
		local bot_slot = Debug.bot_slot_for_unit(unit)
		local fb_state = _fallback_state_by_unit[unit]
		EventLog.emit({
			t = fixed_t,
			event = "snapshot",
			bot = bot_slot,
			ability = _equipped_combat_ability_name(unit),
			cooldown_ready = ability_extension and ability_extension:can_use_ability("combat_ability") or false,
			charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability") or nil,
			ctx = Debug.context_snapshot(Heuristics.build_context(unit, blackboard)),
			item_stage = fb_state and fb_state.item_stage or nil,
		})
	end
end
```

**Step 3: Run checks**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua scripts/mods/BetterBots/debug.lua
git commit -m "feat(event_log): emit session_start (deferred) and periodic snapshot events (#29)"
```

---

## Task 7: Add bb-log events subcommands

**Files:**
- Modify: `bb-log`

**Step 1: Add jq dependency check and events subcommands**

Add near the top of `bb-log`, after `set -euo pipefail`:
```bash
require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for 'events' subcommands. Install with your package manager." >&2
        exit 1
    fi
}
```

Add JSONL file discovery helper:
```bash
EVENTS_DIR="./dump"

get_events_file() {
    local idx="${1:-0}"
    local file
    file=$(find "$EVENTS_DIR" -maxdepth 1 -type f -name 'betterbots_events_*.jsonl' -printf '%T@ %p\n' \
        | sort -rn \
        | cut -d' ' -f2- \
        | sed -n "$((idx + 1))p")
    if [[ -z "$file" ]]; then
        echo "No events file found at index $idx" >&2
        exit 1
    fi
    echo "$file"
}
```

Add new case blocks before the `*)` fallthrough in the main case statement:

```bash
    events|events\ *)
        require_jq
        events_cmd="${2:-summary}"
        events_idx="${3:-0}"
        events_file=$(get_events_file "$events_idx")
        echo "Events: $(basename "$events_file")"
        echo "Lines: $(wc -l < "$events_file")"
        echo ""

        case "$events_cmd" in
            summary)
                echo "=== Event counts ==="
                jq -r '.event' "$events_file" | sort | uniq -c | sort -rn
                echo ""
                echo "=== Decision approval rate ==="
                jq -r 'select(.event=="decision") | .result' "$events_file" \
                    | sort | uniq -c | sort -rn
                echo ""
                echo "=== Consumes per bot ==="
                jq -r 'select(.event=="consumed") | "bot=\(.bot) ability=\(.ability)"' "$events_file" \
                    | sort | uniq -c | sort -rn
                ;;
            rules)
                echo "=== True decisions by rule ==="
                jq -r 'select(.event=="decision" and .result==true) | "\(.ability) \(.rule)"' "$events_file" \
                    | sort | uniq -c | sort -rn
                echo ""
                echo "=== False decisions by rule ==="
                jq -r 'select(.event=="decision" and .result==false) | "\(.ability) \(.rule)"' "$events_file" \
                    | sort | uniq -c | sort -rn
                ;;
            trace)
                bot_slot="${3:?Usage: bb-log events trace <bot-slot> [file-index]}"
                events_idx="${4:-0}"
                events_file=$(get_events_file "$events_idx")
                jq -c "select(.bot==$bot_slot)" "$events_file"
                ;;
            holds)
                echo "=== False decision distribution ==="
                jq -r 'select(.event=="decision" and .result==false) | "\(.ability) \(.rule) (bot=\(.bot))"' "$events_file" \
                    | sort | uniq -c | sort -rn | head -20
                ;;
            items)
                echo "=== Item stage transitions ==="
                jq -r 'select(.event=="item_stage") | "\(.ability) \(.stage) profile=\(.profile)"' "$events_file" \
                    | sort | uniq -c | sort -rn
                echo ""
                echo "=== Item blocks ==="
                jq -r 'select(.event=="blocked") | "\(.ability) \(.reason) profile=\(.profile)"' "$events_file" \
                    | sort | uniq -c | sort -rn
                ;;
            raw)
                filter="${3:-.}"
                events_idx="${4:-0}"
                events_file=$(get_events_file "$events_idx")
                jq -c "$filter" "$events_file"
                ;;
            *)
                echo "Unknown events subcommand: $events_cmd"
                echo "Usage: bb-log events [summary|rules|trace|holds|items|raw] [index]"
                exit 1
                ;;
        esac
        ;;
```

Also update the usage/help text in the `*)` fallthrough:
```bash
    *)
        echo "Unknown command: $cmd"
        echo "Usage: bb-log [activations|rules|holds|summary|errors|tail|list|raw|events] [log-index]"
        echo "       bb-log raw <pattern> [log-index]"
        echo "       bb-log events [summary|rules|trace|holds|items|raw] [file-index]"
        exit 1
        ;;
```

**Step 2: Validate syntax**

Run: `bash -n /run/media/matthias/1274B04B74B032F9/git/BetterBots-29/bb-log`
Expected: No errors

**Step 3: Commit**

```bash
git add bb-log
git commit -m "feat(bb-log): add events subcommands for JSONL analysis via jq (#29)"
```

---

## Task 8: Update docs and run final checks

**Files:**
- Modify: `docs/LOGGING.md` (add event log section)
- Modify: `docs/DEBUGGING.md` (add event log reference)

**Step 1: Add event log section to LOGGING.md**

Append a new section:

```markdown
## Structured event log (JSONL)

Parallel to debug text logging. Enable via mod setting `Enable event log (JSONL)`.

### Output

`./dump/betterbots_events_<timestamp>.jsonl` — one JSON object per line.

### Event types

| Event | When | Key fields |
|-------|------|-----------|
| `session_start` | First bot update tick | version, bots[] |
| `decision` | Every heuristic eval | result, rule, source, bot, ctx, skipped_since_last |
| `queued` | Action input sent | input, source, rule, attempt_id |
| `item_stage` | Item state transition | stage, profile, input, attempt_id |
| `consumed` | Charge spent | charges, attempt_id |
| `blocked` | Item sequence failure | reason, stage, profile, attempt_id |
| `snapshot` | Every 30s per bot | cooldown_ready, charges, ctx, item_stage |

### Correlation

Events carry `attempt_id` (monotonic per session) to link decision → queued → consumed chains. `bot` field is the player slot index.

### Analysis

```bash
bb-log events summary    # counts + approval rate + per-bot consumes
bb-log events rules      # hit rates per ability+rule
bb-log events trace N    # timeline for bot slot N
bb-log events holds      # false decision distribution
bb-log events items      # item sequence success/fail
bb-log events raw FILTER # passthrough to jq
```
```

**Step 2: Add reference in DEBUGGING.md**

In the "Key log markers" or "Preferred: use `bb-log`" section, add:
```markdown
- `bb-log events [summary|rules|trace|holds|items|raw]` — JSONL event log analysis (requires `jq`, enable via mod setting)
```

**Step 3: Run full quality gate**

Run: `cd /run/media/matthias/1274B04B74B032F9/git/BetterBots-29 && make check`
Expected: PASS

**Step 4: Commit**

```bash
git add docs/LOGGING.md docs/DEBUGGING.md
git commit -m "docs: add structured event log reference to LOGGING.md and DEBUGGING.md (#29)"
```

---

## Summary of deliverables

| File | Action | LOC (est) |
|------|--------|-----------|
| `scripts/mods/BetterBots/event_log.lua` | Create | ~150 |
| `tests/event_log_spec.lua` | Create | ~100 |
| `scripts/mods/BetterBots/BetterBots.lua` | Modify | ~80 added |
| `scripts/mods/BetterBots/item_fallback.lua` | Modify | ~40 added |
| `scripts/mods/BetterBots/debug.lua` | Modify | ~20 added |
| `scripts/mods/BetterBots/BetterBots_data.lua` | Modify | ~4 added |
| `scripts/mods/BetterBots/BetterBots_localization.lua` | Modify | ~3 added |
| `.luacheckrc` | Modify | ~1 added |
| `.luarc.json` | Modify | ~1 added |
| `bb-log` | Modify | ~80 added |
| `docs/LOGGING.md` | Modify | ~30 added |
| `docs/DEBUGGING.md` | Modify | ~2 added |

## Key design decisions baked into this plan

1. **No raw sampling** — every false decision that reaches the emit call is logged, with a `skipped_since_last` counter per (bot, ability). This avoids metric distortion while keeping volume manageable because the call sites already throttle via `_debug_log` intervals. The JSONL emit points are at the same granularity as the text debug log calls.
2. **attempt_id** — monotonic counter from `EventLog.next_attempt_id()`, stored in `state.attempt_id` for fallback/item paths. BT-path decisions don't get attempt_id on the decision event itself (no state to carry it), but the queued event from `bot_queue_action_input` hook will.
3. **context_snapshot()** — all context goes through `Debug.context_snapshot()` before serialization, which converts unit userdata to breed name strings.
4. **Deferred session_start** — emitted on first `BotBehaviorExtension.update` tick with alive bots, not at `GameplayStateRun` enter.
5. **Flush at 15s OR 500 events** — prevents memory buildup during dense combat.
