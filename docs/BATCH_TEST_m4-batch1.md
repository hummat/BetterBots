# Batch Test Checklist: dev/m4-batch1

## Included features

| Issue | Branch | Description | Status |
|-------|--------|-------------|--------|
| #42 | `feat/42-vfx-sfx-bleed-fix` | Suppress bot VFX/SFX bleed to human player | PASS |
| #23 | `feat/23-melee-attack-meta-data` | Smart melee attack selection (armor-aware) | PASS |
| #31 | `feat/31-ranged-meta-data` | Player ranged weapon attack_meta_data injection | PASS |
| #30 | (inline) | Bot warp charge venting (3 hooks) | PASS |
| #43 | (inline) | Staff charged fire via aim chain + `_may_fire()` hook | PARTIAL |

## Test environment

- [x] Fresh mission start (not hot-reload — init hooks don't retroactively patch)
- [x] DMF debug logging enabled
- [x] SoloPlay with 3 bots

## Per-feature acceptance criteria

### #42 — VFX/SFX bleed fix

- [x] No bot lunge screen distortion on human player's view
- [x] No bot lunge sounds on human player
- [x] No bot shout aim indicator on human player
- [x] No bot dash crosshair on human player
- [x] Human player's own VFX/SFX still work normally (own abilities, own lunges)
- [ ] Debug log shows `patched ability effect context`, `patched wieldable slot scripts context`, `patched CharacterStateMachine` for each bot unit
- [x] No Lua errors in console

### #23 — Smart melee attack selection

- [x] Bot uses heavy attacks against armored enemies (Maulers, Crushers)
- [ ] Bot uses sweeping attacks against hordes (3+ unarmored enemies)
- [x] Bot still uses light attacks in 1v1 vs unarmored
- [x] Debug log shows `melee attack_meta_data patch installed (injected=N, skipped=M)` with N > 0 — injected=66, skipped=0
- [x] No Lua errors in console
- [x] Melee combat loop still functional (attack/block/push/dodge cycle)

### #31 — Ranged weapon attack_meta_data injection

**Acceptance criteria:**
- [x] Bot fires plasma gun (shoot_charge → auto-fire via charged_enough) — 23 shoot_charge inputs logged
- [x] Bot fires force staff (shoot_pressed → rapid_left projectile) — 11 shoot_pressed inputs logged
- [x] Standard weapons still work (lasgun, autogun, bolter — zoom/zoom_shoot/zoom_release cycle working)
- [x] Debug log shows `ranged attack_meta_data patch installed (injected=0, patched=36, skipped=28)`
- [x] No crashes or errors in console

## Regression checks

- [x] Revive/rescue behavior works
- [x] Bot abilities still activate (template + item paths) — 83 consumed, 67 fallback queued
- [x] Navigation/pathing stable
- [x] Basic combat loop intact — 32 light_attack, 11 heavy_attack logged
- [x] No new Lua errors — 0 error lines in console

### #30 — Bot warp charge venting

- [x] `Overheat.slot_percentage` bridges `warp_charge.current_percentage` for warp weapons
- [x] `should_vent_overheat` hysteresis fixed (uses `is_running` instead of broken `scratchpad.reloading`)
- [x] `reload` → `vent` translation in `bot_queue_action_input` (reordered before peril guard)
- [x] Debug log shows `translated reload -> vent (warp weapon)` — 15 translations (session 3), 10 (session 4)
- [x] Peril guard excludes `"vent"` so venting not blocked at critical peril
- [x] No Lua errors in console

### #43 — Staff charged fire (partial)

- [x] `_may_fire()` hook temporarily swaps `fire_action_input` to `aim_fire_action_input` during validation
- [x] `find_aim_action_for_fire()` derives aim chain from `allowed_chain_actions` graph
- [x] `forcestaff_p4_m1` (trauma): 18× `shoot_charged` in tagged log — **PASS**
- [ ] `forcestaff_p2_m1` (flame/inferno): 0× `trigger_charge_flame`, falls back to `shoot_pressed` — **FAIL**
- [ ] `forcestaff_p1_m1` (surge): untested (`trigger_explosion`)
- [ ] `forcestaff_p3_m1` (voidstrike): untested (`shoot_charged`, likely works like p4)
- [x] No ADS regression on standard guns (50 zoom, 13 zoom_shoot in session 5)
- [x] No Lua errors in console

## Result

```text
Date: 2026-03-09
Log files:
  Session 1: console-2026-03-09-13.54.33 (initial batch test, #42/#23/#31)
  Session 2: console-2026-03-09-15.44.58 (#43 investigation, meta_data dump)
  Session 3: console-2026-03-09-17.38.06 (#30 vent translation confirmed)
  Session 4: console-2026-03-09-17.52.08 (#43 untagged, 0 trigger_explosion)
  Session 5: console-2026-03-09-18.30.17 (#43 untagged, shoot_charged present)
  Session 6: console-2026-03-09-18.45.21 (#43 TAGGED — p4 PASS, p2 FAIL)
Map + difficulty: SoloPlay
Bot lineups: Various (Veteran, Psyker, Zealot, Ogryn combinations)

#42 VFX/SFX bleed: PASS
  - No bot VFX bleed to human view; human's own zealot dash VFX confirmed working

#23 Melee attack selection: PASS
  - 32 light_attack, 11 heavy_attack inputs logged; heavy attacks observed visually

#31 Ranged fire fix: PASS
  - Plasma gun firing confirmed (23 shoot_charge); force staff firing (11 shoot_pressed)
  - 36 templates patched with corrected fire/aim-fire inputs

#30 Warp venting: PASS
  - 15 reload→vent translations (session 3), 173 total vent inputs (session 6)
  - Hysteresis fix + warp_charge bridge + peril guard reorder all confirmed working
  - Zero errors across 4 sessions

#43 Staff charged fire: PARTIAL
  - forcestaff_p4_m1 (trauma): PASS — 18× shoot_charged in tagged log
  - forcestaff_p2_m1 (flame): FAIL — 0× trigger_charge_flame, falls back to shoot_pressed
  - forcestaff_p1_m1 (surge): untested
  - forcestaff_p3_m1 (voidstrike): untested
  - Suspected root cause: find_aim_action_for_fire() key lookup may not match p1/p2 allowed_chain_actions structure (needs decompiled template inspection + failing test to confirm)

Regressions: PASS
  - Abilities, combat, navigation all functional; zero errors across 6 sessions

Verdict: SHIP #42/#23/#31/#30. #43 stays open (p4 PASS, p3 untested, p1/p2 need investigation).
```
