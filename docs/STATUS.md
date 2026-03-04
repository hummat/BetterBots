# Status Snapshot (March 4, 2026)

## Evidence Source

- Latest analyzed log:
  `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/console-2026-03-04-18.58.17-f7236365-a8e7-4c7d-a032-82c6d493b567.log`
- This file contains multiple play segments and hot-reloads.
- Note: Darktide console log timestamps are UTC, not local timezone.

## Confirmed Working In This Log

1. Startup patching is active across reloads.
   - `BetterBots loaded`
   - `patched bt_bot_conditions.can_activate_ability`
   - `patched bt_conditions.can_activate_ability`

2. Zealot relic item path is repeatedly successful.
   - Repeated `charge consumed for zealot_relic` entries are present through the run.

3. Psyker force-field can succeed, but only intermittently.
   - `charge consumed for psyker_force_field` appears a few times.
   - The same file also contains many failed no-charge sequences.

## Partial / Experimental

1. Psyker force-field remains unstable in sustained combat.
   - Frequent pattern:
     - `fallback item queued ... aim/place...`
     - `fallback item continuing charge confirmation ... lost combat-ability wield ...`
     - `fallback item finished without charge consume ...`
   - Overall in this file, no-charge outcomes still dominate.

2. New protection hooks are loaded but not yet validated with post-reload combat evidence.
   - Around `20:13:20` UTC this file shows hook install lines for:
     - `ActionCharacterStateChange.finish` fast-retry hook
     - `PlayerUnitActionInputExtension.bot_queue_action_input` weapon-switch lock
   - After that reload, the file ends around `20:13:43` UTC and does not contain enough new combat events to confirm impact.

## Known Log Noise

1. Frequent `fallback blocked ... invalid action_input=...` appears during combat.
   - This is expected when inputs are transiently invalid (cooldown/state windows), but it is noisy.

2. Non-mod engine/nav errors can coexist in the same file:
   - `ERROR [BotNavigationExtension] Can't path, AStar was cancelled...`
   - These are not BetterBots Lua tracebacks.

## Current Conclusion

1. Zealot relic behavior is substantially better than earlier sessions (repeat charge-consume evidence).
2. Psyker force-field is still the primary instability hotspot.
3. Latest code hooks are in place, but a fresh post-reload combat log is still needed to validate:
   - weapon-switch lock effect (`blocked weapon switch while keeping ...`)
   - state-transition fast retry effect (`state_fail_retry ...`).
