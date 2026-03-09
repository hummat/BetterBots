# Batch Test Checklist: dev/m4-batch1

## Included features

| Issue | Branch | Description | Status |
|-------|--------|-------------|--------|
| #42 | `feat/42-vfx-sfx-bleed-fix` | Suppress bot VFX/SFX bleed to human player | needs-testing |

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

Regressions: PASS/FAIL
  - notes:

Verdict: SHIP / FIX / REVERT
```
