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
- `decision ... -> true/false`
- `enter ability node ...`
- `fallback queued ...` (template fallback queued)
- `fallback blocked ...` (template fallback rejected)
- `fallback item queued ...` (item fallback queued wield/cast/unwield input)
- `fallback item blocked ...` (unsupported template, no wield input, timeout, etc.)
- `charge consumed for ...` (ability charge spent, strongest success signal)
- `state_fail_retry ...` (combat ability state transition failed; fast retry scheduled)
- `blocked weapon switch while keeping ...` (bot `wield` request suppressed during protected relic/force-field stages)

## Interpreting failures

- `decision -> true` without `charge consumed`:
  - condition passed, but activation pipeline failed later.
- repeated `fallback skipped ... template_name=none`:
  - bot is on item-based combat ability path.
- repeated `fallback item blocked ... unsupported weapon template`:
  - add a new item sequence mapping in `BetterBots.lua`.
- repeated `fallback item continuing charge confirmation ... lost combat-ability wield ...`:
  - another behavior node is switching away during cast/channel; verify whether lock lines (`blocked weapon switch while keeping ...`) are present.
