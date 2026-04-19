## Current State

- Branch: `dev/v1.0.0`
- Sprint 1 and the post-`v0.11.3` follow-up batch are code-complete locally.
- `#103`, `#104`, and `#105` remain open and should stay `needs-testing` until in-game validation happens.
- GitHub auth is currently broken (`gh auth status` reports invalid tokens for both `github.com` and `rmc-github.robotic.dlr.de`), so issue/PR state cannot be updated from this workstation until re-auth.

## This Session

- Investigated the NexusMods Psyker complaint properly instead of hand-waving:
  - BetterBots already supports Brain Burst (`psyker_smite`) and already has a global grenade/blitz toggle
  - the real gaps were coarse Brain Burst arbitration, missing `psyker_smite_targeting_action_module` precision seeding, and missing explicit `forcestaff_p3_m1` close-range ranged-hold support
- Implemented the Psyker follow-up pass:
  - `bot_targeting.lua`: added `resolve_precision_target_unit()` with priority-slot ordering (`priority` → `opportunity` → `urgent` → `target`)
  - `smart_targeting.lua`: now hooks both smart-target modules, including `psyker_smite_targeting_action_module`, and seeds them from the precision resolver
  - `grenade_fallback.lua`: normalizes `psyker_smite` against the precision target before heuristic evaluation / queueing
  - `heuristics_grenade.lua`: replaced the old generic Brain Burst wrapper with a dedicated rule that blocks under close melee pressure on non-hard targets and biases hard targets explicitly (`super_armor`, monsters, explicit priority targets)
  - `ranged_meta_data.lua`: added explicit close-range ranged-hold policy for `forcestaff_p3_m1`
- Fixed review-driven regressions and harness gaps on top of the post-`v0.11.3` batch:
  - tightened zero-peril Scrier fallback, Gunlugger Armor Pen target binding, and chain super-armor scoring
  - added hidden-failure diagnostics for supported-special-without-meta and nil talent contexts
  - fixed a new smart-targeting log-key throttle bug so per-bot confirmation logs are not dropped across multiple bots
- Updated Psyker docs to remove the stale “blitz not yet implemented” claim and to document the new Brain Burst / staff behavior.

## Verification

- `make check-ci` passes
- latest local result before handoff:
  - `1251 successes / 0 failures / 0 errors / 0 pending`
  - `doc-check: all checks passed`

## Next Steps

1. Run in-game validation for the still-open follow-up issues:
   - `#103`: chain-family melee special timing and target selection
   - `#104`: Scrier/Gunlugger build-aware heuristics
   - `#105`: autopistol/rippergun/Surge-staff close-range handling and Brain Burst pressure gating
2. Once GitHub auth is fixed, make sure `#103` / `#104` / `#105` stay open with `needs-testing` until that field validation is recorded.
3. If the Psyker complaint still reproduces after this pass, the next audit target is `forcestaff_p1_m1` / `forcestaff_p4_m1`, not Brain Burst again.
