# Manual Test Plan

## Goal

Verify template-based and item-based combat ability activation, then check bot regressions.
Use `docs/dev/validation-tracker.md` as the canonical run log and matrix.

## Prerequisites

- Darktide Mod Loader + DMF installed
- SoloPlay enabled
- BetterBots loaded after `dmf`
- DMF `Echo` output set to `Log` or `Log & Chat`
- Optional: Tertium 5 or Tertium 6 for deterministic bot loadouts

## Acceptance criteria

1. Startup logs appear (`BetterBots loaded`, metadata patch logs).
2. At least one template-path cast occurs (`fallback queued ...` then `charge consumed for ...`).
3. At least one item-path cast occurs when using item ability bots (`fallback item queued ...` then `charge consumed for ...`).
4. No obvious regressions to revive/rescue/navigation/basic combat.

## Release-Candidate Smoke Loop

Run this after every feature batch that touches hooks, fallback state, event logging, or bot input dispatch:

1. Fresh launch smoke
   - Start Darktide from a cold process.
   - Launch one Solo Play mission.
   - Confirm `BetterBots loaded` appears exactly once.
   - Confirm no startup traceback appears in the first minute.

2. Ability-path smoke
   - Observe at least one template-path activation.
   - Observe at least one item-path activation.
   - Observe at least one grenade/blitz activation if the batch touched grenade logic.

3. Session-lifecycle smoke
   - Finish the mission or return to Mourningstar.
   - Launch a second Solo Play mission without restarting the game.
   - Confirm no duplicate startup spam, no stale fallback loops, and no immediate traceback on mission start.

4. Core regression smoke
   - Revive/rescue still works.
   - Navigation/combat loop still looks normal.

## Patch-Day Preflight

Run this when Darktide ships a new patch and `../Darktide-Source-Code` has been updated:

1. Refresh the decompiled source and BetterBots' engine contract checks.
   - `make patch-check-refresh`

2. Re-run the normal local gate.
   - `make check-ci`

3. Then run the release-candidate smoke loop above.
   - Structural drift catches missing files, renamed functions, and broken hook anchors.
   - The smoke loop still catches semantic drift that kept the same names.

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

## Batch Checklist: 2026-03-13 P0/P1 Stabilization

Git target: `dev/p0-p1-stabilization` at commit `e580367` or later

1. `#50` Arbites drone crash guard
   - Lineup: 3 Arbites bots with Nuncio-Aquila if available.
   - Goal: trigger repeated drone wield/deploy sequences in live combat.
   - Pass if:
     - no Lua crash occurs during dodge / ability overlap windows
     - bot still deploys drone normally
     - log may contain `animation_guard:` entries, but no fatal traceback

2. `#61` / `#62` grenade aim + Assail smart targeting
   - Lineup: at least one grenade-throw bot and one Psyker Assail bot.
   - Goal: observe whether throws are aimed at enemies instead of empty space.
   - Pass if:
     - grenade bots visibly turn toward their target before release
     - Assail projectiles/throws are seeded off a real enemy target
     - `grenade_fallback` logs show normal aim/throw progression without repeated reset loops

3. `#51` ranged ammo dead-zone fix
   - Lineup: any ranged-focused bot that can spend reserve ammo steadily.
   - Goal: drive reserve ammo below 50% but keep it above emergency-resupply territory.
   - Pass if:
     - bot continues normal ranged engagement in the roughly 20% to 50% reserve range
     - bot does not collapse into melee-only behavior solely because reserve ammo crossed 50%

4. `#52` melee heavy-attack horde bias reduction
   - Lineup: melee bot with both light/heavy metadata available.
   - Goal: fight mixed unarmored horde packs with no armored priority target.
   - Pass if:
     - bot uses lights meaningfully into trash hordes instead of defaulting to heavy sweeps every cycle
     - armored targets still trigger heavy preference when appropriate

5. Regression sanity for the integrated batch
   - Revive/rescue still works.
   - No obvious navigation/pathing regressions.
   - No new startup/load regressions after hot start or fresh mission load.

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
