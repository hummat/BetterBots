# Batch Test Checklist: dev/m4-batch1

## Included features

| Issue | Branch | Description | Status |
|-------|--------|-------------|--------|
| #42 | `feat/42-vfx-sfx-bleed-fix` | Suppress bot VFX/SFX bleed to human player | needs-testing |
| #23 | `feat/23-melee-attack-meta-data` | Smart melee attack selection (armor-aware) | needs-testing |
| #31 | `feat/31-ranged-meta-data` | Player ranged weapon attack_meta_data injection | needs-testing |

## Test environment

- [ ] Fresh mission start (not hot-reload — init hooks don't retroactively patch)
- [ ] DMF debug logging enabled
- [ ] SoloPlay with 3 bots

## Per-feature acceptance criteria

### #42 — VFX/SFX bleed fix

- [ ] No bot lunge screen distortion on human player's view
- [ ] No bot lunge sounds on human player
- [ ] No bot shout aim indicator on human player
- [ ] No bot dash crosshair on human player
- [ ] Human player's own VFX/SFX still work normally (own abilities, own lunges)
- [ ] Debug log shows `patched ability effect context`, `patched wieldable slot scripts context`, `patched CharacterStateMachine` for each bot unit
- [ ] No Lua errors in console

### #23 — Smart melee attack selection

- [ ] Bot uses heavy attacks against armored enemies (Maulers, Crushers)
- [ ] Bot uses sweeping attacks against hordes (3+ unarmored enemies)
- [ ] Bot still uses light attacks in 1v1 vs unarmored
- [ ] Debug log shows `melee attack_meta_data patch installed (injected=N, skipped=M)` with N > 0
- [ ] No Lua errors in console
- [ ] Melee combat loop still functional (attack/block/push/dodge cycle)

### #31 — Ranged weapon attack_meta_data injection

**Acceptance criteria:**
- [ ] Bot fires plasma gun (shoot_charge → auto-fire via charged_enough)
- [ ] Bot fires force staff (shoot_pressed → rapid_left projectile)
- [ ] Standard weapons still work (lasgun, autogun, bolter — no regression)
- [ ] Debug log shows "ranged attack_meta_data patch installed (injected=N, skipped=M)"
- [ ] No crashes or errors in console

## Regression checks

- [ ] Revive/rescue behavior works
- [ ] Bot abilities still activate (template + item paths)
- [ ] Navigation/pathing stable
- [ ] Basic combat loop intact
- [ ] No new Lua errors

## Result

```text
Date:
Git commit:
Log file:
Map + difficulty:
Bot lineup:

#42 VFX/SFX bleed: PASS/FAIL
  - evidence:

#23 Melee attack selection: PASS/FAIL
  - evidence:

#31 Ranged fire fix: PASS/FAIL
  - evidence:

Regressions: PASS/FAIL
  - notes:

Verdict: SHIP / FIX / REVERT
```
