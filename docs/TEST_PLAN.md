# Manual Test Plan

## Goal

Verify template-based and item-based combat ability activation, then check bot regressions.
Use `docs/VALIDATION_TRACKER.md` as the canonical run log and matrix.

## Prerequisites

- Darktide Mod Loader + DMF installed
- SoloPlay enabled
- BetterBots loaded after `dmf`
- DMF `Echo` output set to `Log` or `Log & Chat`
- Optional: Tertium4Or5 for deterministic bot loadouts

## Acceptance criteria

1. Startup logs appear (`BetterBots loaded`, metadata patch logs).
2. At least one template-path cast occurs (`fallback queued ...` then `charge consumed for ...`).
3. At least one item-path cast occurs when using item ability bots (`fallback item queued ...` then `charge consumed for ...`).
4. No obvious regressions to revive/rescue/navigation/basic combat.

## Test matrix

1. Baseline startup
   - Launch solo mission.
   - Confirm startup patch logs.

2. Template ability validation
   - Use bots with template-based combat abilities.
   - Confirm cast chain in logs: `decision`/`fallback queued` -> `charge consumed`.

3. Item ability validation
   - Use bots with item-based combat abilities (for example relic or force-field paths).
   - Confirm cast chain in logs: `fallback item queued ...` -> `charge consumed`.
   - Record any `fallback item blocked ...` signatures.
   - If charge is not consumed, check whether fallback profile rotation happened (`fallback item finished without charge consume ... rotated=true`).

4. Regression checks
   - Revive/rescue behavior still works.
   - Navigation/combat loop remains stable.

## Result template

```text
Run ID:
Date (local):
Date (UTC):
Git commit:
Log file:
Bot lineup / abilities:
Map + difficulty:

Tier 2 evidence:
- <ability_template>: PASS/FAIL/UNKNOWN
  - visual: yes/no
  - charge consumed log: yes/no
  - key lines / timestamps:

Tier 3 evidence:
- <ability_template>: PASS/FAIL/UNKNOWN
  - visual: yes/no
  - charge consumed log: yes/no
  - blocked-switch / retry logs seen: yes/no
  - key lines / timestamps:

Regressions:
- revive/rescue: PASS/FAIL/UNKNOWN
- navigation/pathing: PASS/FAIL/UNKNOWN
- basic combat loop: PASS/FAIL/UNKNOWN
- Lua errors: yes/no (+ first traceback line if yes)

Conclusion:
- promote issue state / next fix target:
```
