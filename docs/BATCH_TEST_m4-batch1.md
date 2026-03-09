# Batch Test Checklist: dev/m4-batch1

## Included features

| Issue | Branch | Description | Status |
|-------|--------|-------------|--------|
| #42 | `feat/42-vfx-sfx-bleed-fix` | Suppress bot VFX/SFX bleed to human player | needs-testing |
| #23 | `feat/23-melee-attack-meta-data` | Smart melee attack selection (armor-aware) | needs-testing |

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

Regressions: PASS/FAIL
  - notes:

Verdict: SHIP / FIX / REVERT
```
