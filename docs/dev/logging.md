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
- `BetterBots DEBUG: logging enabled (force=...)`
- `patched bt_bot_conditions.can_activate_ability`
- `entered GameplayStateRun`
- `decision ... -> true` (BT condition path activation — only `true` results are logged)
- `enter ability node ...`
- `fallback queued ...` (template fallback queued)
- `fallback held ...` (heuristic withheld ability — only logged when `num_nearby > 0`)
- `fallback blocked ...` (template fallback rejected)
- `fallback item queued ...` (item fallback queued wield/cast/unwield input)
- `fallback item blocked ...` (unsupported template, no wield input, timeout, etc.)
- `charge consumed for ...` (ability charge spent, strongest success signal)
- `state_fail_retry ...` (combat ability state transition failed; fast retry scheduled)
- `blocked weapon switch while keeping ...` (bot `wield` request suppressed during protected relic/force-field stages)
- `bot weapon: bot=<slot> slot=<slot> weapon_template=<template> warp_template=<template> action=<input> raw_input=<raw>` (temporary `#43` diagnostic; template-tagged queued weapon input)

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

### Analysis

```bash
bb-log events summary    # counts + approval rate + per-bot consumes
bb-log events rules      # hit rates per ability+rule
bb-log events trace N    # timeline for bot slot N
bb-log events holds      # false decision distribution
bb-log events items      # item sequence success/fail
bb-log events raw FILTER # passthrough to jq
```
