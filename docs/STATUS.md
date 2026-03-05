# Status Snapshot (March 5, 2026)

## Evidence Source

- Latest analyzed log:
  `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log`
- Newer validation logs are tracked in `docs/VALIDATION_TRACKER.md`:
  - `console-2026-03-05-14.44.43-...` (Tier 1 evidence + crash before nil-account guard)
  - `console-2026-03-05-14.57.34-...` (Tier 2 completion evidence, no new crash signature observed)
- This file contains multiple play segments and hot-reloads.
- Note: Darktide console log timestamps are UTC, not local timezone.
- Ongoing manual run evidence and PASS/PARTIAL/UNKNOWN matrix now live in `docs/VALIDATION_TRACKER.md`.

## Confirmed Working In This Log

1. Startup patching is active across reloads.
   - `BetterBots loaded`
   - `patched bt_bot_conditions.can_activate_ability`
   - `patched bt_conditions.can_activate_ability`

2. Zealot relic item path is repeatedly successful.
   - In latest extraction: 5 consumes, 0 no-charge completions.

3. Psyker force-field and Arbites Nuncio-Aquila can both succeed, but are still intermittent.
   - `psyker_force_field_dome`: 9 consumes vs 60 no-charge completions (current rolling-log snapshot).
   - `adamant_area_buff_drone`: 10 consumes vs 66 no-charge completions (current rolling-log snapshot).
   - Post-timing-patch window also shows new consumes for both, confirming runtime patch activation.

## Partial / Experimental

1. Psyker force-field and Nuncio-Aquila remain unstable in sustained combat.
   - Frequent pattern:
     - `fallback item queued ... aim/place...`
     - `fallback item continuing charge confirmation ... lost combat-ability wield ...`
     - `fallback item finished without charge consume ...`
   - Overall in this file, no-charge outcomes still dominate.

2. Weapon-switch lock hook behavior is validated in latest runs.
   - Repeated lock evidence exists for relic, force-field, and Nuncio-Aquila (`blocked weapon switch while keeping ...`).
   - Locking helps prevent immediate cancel but does not by itself solve item ability reliability.

## Known Log Noise

1. Frequent `fallback blocked ... invalid action_input=...` appears during combat.
   - This is expected when inputs are transiently invalid (cooldown/state windows), but it is noisy.

2. Non-mod engine/nav errors can coexist in the same file:
   - `ERROR [BotNavigationExtension] Can't path, AStar was cancelled...`
   - These are not BetterBots Lua tracebacks.

## Current Conclusion

1. Tier 1 and Tier 2 validation are complete for currently testable abilities (see `docs/VALIDATION_TRACKER.md` matrix).
2. Tier 3 remains the active blocker: relic is strong, force-field is still the primary instability hotspot, and Nuncio-Aquila is still unreliable despite multiple confirmed consumes.
3. Remaining work is reliability hardening for item abilities, not broad Tier 2 activation coverage.
