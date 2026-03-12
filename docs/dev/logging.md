# Logging and Diagnostics

## Output channels

BetterBots logs with `mod:echo(...)`. DMF controls where those lines go:

- chat only
- log only
- chat + log
- disabled

Use DMF `Logging Mode = Custom` and set `Echo` to `Log` or `Log & Chat`.

## Log file locations

### Windows

`C:\Users\<your-user>\AppData\Roaming\Fatshark\Darktide\console_logs\console-*.log`

### Linux (Steam Proton, this setup)

`/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/console-*.log`

## Timestamp timezone

Darktide console logs use **UTC timestamps** (`UTC time stamps` header in the log file).

If your system clock is local time (for example `CET`/`CEST`), log times will be offset by your current timezone difference:
- `CET` (winter): local = log + 1h
- `CEST` (summer): local = log + 2h

When comparing in-game events with system time, convert to UTC or account for the offset first.

## Practical workflow (learned during debugging)

1. You can read logs while still in mission; quitting game is not required.
2. Always confirm you are reading the newest `console-*.log`.
3. Toggling a DMF setting only affects runtime after reload.
4. `Ctrl+Shift+R` hot reload requires DMF dev mode enabled.
5. If `DEBUG_FORCE_ENABLED = true` in `BetterBots.lua`, debug lines appear regardless mod setting.

## Useful commands

```bash
LOG_DIR="/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"
LATEST=$(ls -1t "$LOG_DIR" | head -n 1)
rg -n "BetterBots|\\[MOD\\]\\[BetterBots\\]" "$LOG_DIR/$LATEST"
```

Follow live updates for the active file:

```bash
tail -f "$LOG_DIR/$LATEST" | rg --line-buffered "BetterBots|\\[MOD\\]\\[BetterBots\\]"
```

## Key BetterBots log lines

- `BetterBots loaded`
- `BetterBots DEBUG: logging enabled (level=<off|info|debug|trace>)`
- `patched bt_bot_conditions.can_activate_ability`
- `entered GameplayStateRun`
- `decision ... -> true` (BT condition path activation — includes `hazard=<true|false>` in the debug line)
- `enter ability node ...`
- `fallback queued ...` (template fallback queued)
- `fallback held ...` (heuristic withheld ability — only logged when `num_nearby > 0`)
- `fallback blocked ...` (template fallback rejected)
- `fallback item queued ... (rule=...)` (item fallback queued wield/cast/unwield input with triggering rule)
- `fallback item blocked ...` (unsupported template, no wield input, timeout, etc.)
- `charge consumed for ...` (ability charge spent, strongest success signal)
- `grenade queued wield for <grenade> (rule=<rule>)` (grenade fallback started a throw sequence)
- `grenade held <grenade> (rule=<rule>, nearby=<N>, peril=<N|nil>)` (grenade/blitz heuristic withheld use for an actionable reason)
- `grenade queued aim_hold` / `grenade queued aim_released` (grenade fallback advanced through the throw inputs)
- `grenade queued <input>` for staged custom blitz chains such as `charge_heavy`, `shoot_heavy_hold`, `shoot_heavy_hold_release`
- `grenade charge consumed for <grenade> (charges=<N>)` (grenade actually spent a charge; strongest throw confirmation)
- `grenade queued unwield_to_previous after charge confirmation` (BetterBots started explicit post-throw cleanup for bots)
- `grenade throw complete, slot returned to <slot>` (grenade sequence fully completed)
- `grenade forced unwield_to_previous on timeout` (cleanup fallback; indicates normal post-throw unwind did not complete)
- `grenade released cleanup lock without explicit unwield (charge confirmed|timeout)` (templates such as Psyker blitz unwind via normal `wield`, not `unwield_to_previous`)
- `grenade released cleanup lock without explicit unwield (action confirmed)` (external cleanup templates saw their target action, so BetterBots ends the protected sequence immediately)
- `grenade released cleanup lock without explicit unwield (slot changed)` (external cleanup templates left grenade slot through the engine's normal unwind; BetterBots treats that as success)
- `grenade external action confirmed for <grenade> (action=<action_name>)` (non-charge blitz confirmation; useful for Psyker Chain Lightning charged-path validation)
- `state_fail_retry ...` (combat ability state transition failed; fast retry scheduled)
- `blocked weapon switch while keeping ...` (bot `wield` request suppressed during protected relic/force-field stages)
- `_may_fire swap: fire=<input> -> aim_fire=<input>` (`#43` validation; `_may_fire()` swapped fire input for ADS/charge weapon — one-shot per scratchpad)
- `bot weapon: bot=<slot> slot=<slot> weapon_template=<template> warp_template=<template> action=<input> raw_input=<raw>` (`#43` validation; template-tagged queued weapon input — one-shot per unique combo)
- `penalizing melee score for distant special <breed> dist_sq=<N> ammo=<N>` (target selection penalty applied — bot will prefer ranged over chasing)
- `bot <slot> pinged <target> (reason: <reason>)` (ping system — bot pinged an elite/special)
- `bot <slot> ping fail for <target>: <err>` (ping system — ping attempt failed)

## Intentionally suppressed (noise reduction)

The following were removed/throttled to reduce chat spam during testing:

- **`bt gate evaluated`** — removed entirely; redundant with decision log
- **`decision -> false`** — suppressed; BT-path false decisions are no longer logged
- **`fallback held` with `nearby=0`** — suppressed; idle holds produce no log output
- **`blocked (template_name=none)` in BT path** — throttled to 20s (was 2s); expected for item abilities

**Observability impact:** Idle-state bot decisions (no enemies nearby) are completely invisible in new logs. `bb-log summary` `held_idle` counter will show 0 for runs after this change. This is acceptable for combat-focused heuristic tuning but means idle behavior issues won't appear in logs. Re-enable by reverting the guards in `debug.lua:log_ability_decision` and `BetterBots.lua:_fallback_try_queue_combat_ability` if needed.

## Interpreting failures

- `decision -> true` without `charge consumed`:
  - condition passed, but activation pipeline failed later.
- repeated `fallback skipped ... template_name=none`:
  - bot is on item-based combat ability path.
- repeated `fallback item blocked ... unsupported weapon template`:
  - add a new item sequence mapping in `BetterBots.lua`.
- repeated `fallback item continuing charge confirmation ... lost combat-ability wield ...`:
  - another behavior node is switching away during cast/channel; verify whether lock lines (`blocked weapon switch while keeping ...`) are present.

## Writing debug logging for new features

Debug logging is **permanent infrastructure**, not throwaway diagnostics. Every feature's logs must survive across releases to catch regressions and validate working state. Never mark logs as "remove after validation."

### Log levels

`enable_debug_logs` is a dropdown in DMF options:

- `Off` — no `_debug_log` output
- `Info` — one-shot patches and confirmations only
- `Debug` — default diagnostic level for ability decisions and state changes
- `Trace` — includes per-frame diagnostics such as sprint traces

Poxburster suppression confirmations are logged at `Debug`, not `Trace`, so normal validation runs can confirm that path.

### Rules

1. **Gate expensive reads behind `_debug_enabled()`**. `read_component()`, `has_extension()`, and string concatenation run on the hot path (multiple bots, every frame). Only pay that cost when debug mode is on.

2. **One-shot dedup for repeated events**. Most bot actions repeat every frame. Use one of two patterns:
   - **Weak-keyed set** for object-keyed dedup (scratchpad, unit): `local _logged = setmetatable({}, { __mode = "k" })`. Entries auto-clear when the key is GC'd (e.g. scratchpad recycled between missions).
   - **String-keyed set** for combo dedup: `local _logged_combos = {}`. Build a key like `bot_slot .. ":" .. template .. ":" .. action` and skip if already seen. Use this when the discriminator is a value, not an object reference.

3. **Throttle key convention**. The first argument to `_debug_log(key, t, msg, interval, level)` is `"feature_tag:" .. discriminator` — e.g. `"may_fire_swap:shoot_charged"`, `"grenade_state:wait_aim"`, `"peril_block:shoot_pressed"`. This enables `rg "may_fire_swap"` filtering in `bb-log` output.

4. **Log the confirmation signal**. Each feature should log the event that proves it fired correctly:
   - State machine transition → log the new state and trigger
   - Input swap/translation → log what was swapped and why
   - Suppression/block → log what was blocked and the reason
   - Injection/patch → log once at load time that the patch applied

5. **Don't log no-ops**. Idle paths, false conditions, and expected skips produce no output. If a bot has no enemies nearby and the heuristic returns false, that's not interesting. Only log when something happened.

### Example: one-shot scratchpad logging

```lua
local _logged = setmetatable({}, { __mode = "k" })

-- Inside a hook:
if not _logged[scratchpad] and _debug_enabled() then
    _logged[scratchpad] = true
    _debug_log(
        "feature_tag:" .. tostring(discriminator),
        _fixed_time(),
        "human-readable message with key values"
    )
end
```

### Example: combo-key logging

```lua
local _logged_combos = {}

-- Inside a per-frame hook:
if _debug_enabled() then
    local key = bot_slot .. ":" .. template .. ":" .. action
    if not _logged_combos[key] then
        _logged_combos[key] = true
        _debug_log("feature:" .. key, _fixed_time(), "descriptive message")
    end
end
```

### Updating the log line catalog

When adding new `_debug_log` calls, add the corresponding log line to the "Key BetterBots log lines" section above. Include the prefix pattern and a brief description of when it appears.

## Structured event log (JSONL)

Parallel to debug text logging. Enable via mod setting `Enable event log (JSONL)` (`enable_event_log` in code).

### Output

`./dump/betterbots_events_<timestamp>.jsonl` — one JSON object per line.

**Filename timestamp** uses wall-clock `os.time()` (epoch seconds), not simulation `fixed_t` which resets each mission. This prevents filename collisions across runs.

**Working directory caveat:** Darktide's CWD is `binaries/`, so files land in `<game-root>/binaries/dump/`. The `bb-log events` command expects `EVENTS_DIR=./dump` relative to CWD — run it from the `binaries/` directory or adjust the path.

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

### Hot-reload behavior

`Ctrl+Shift+R` resets all module-local state (buffer, file path, enabled flag). DMF does **not** re-fire `on_game_state_changed` for the current state, so the normal `start_session` path doesn't trigger.

**Recovery:** At load time, BetterBots checks if the event log setting is enabled and bots are alive. If so, it re-enables logging and starts a new session file. This means a hot-reload mid-mission produces a new JSONL file (previous buffer is lost if not yet flushed).

### Correlation

Events carry `attempt_id` (monotonic per session) to link decision → queued → consumed chains. `bot` field is the player slot index.

`ctx` is the `Debug.context_snapshot(...)` payload. It includes the combat signals used by heuristics, including `in_hazard` for hazard-aware validation.

### Analysis

```bash
bb-log events summary    # counts + approval rate + per-bot consumes
bb-log events rules      # hit rates per ability+rule
bb-log events trace N    # timeline for bot slot N
bb-log events holds      # false decision distribution
bb-log events items      # item sequence success/fail
bb-log events raw FILTER # passthrough to jq
```
