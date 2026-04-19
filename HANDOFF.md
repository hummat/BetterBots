# Handoff

**From:** Codex (GPT-5, OpenAI API)
**Date:** 2026-04-19

## Task
Finish **in-game validation** for the still-open `dev/v1.0.0` `needs-testing` issues and update GitHub issue state/comments accordingly.

Open validation targets:
- `#13` Navmesh validation for charge/dash abilities
- `#17` Daemonhost avoidance
- `#92` Per-breed weakspot aim override
- `#103` Chain-family toggle_special melee weapons
- `#104` Additional keystone/build-aware heuristics
- `#105` More explicit close-range ranged weapon families

## In-Flight Work
- Review-fix batch is complete locally and awaiting commit.
- Branch: `dev/v1.0.0`
- Branch state from latest user shell output: ahead of `origin/dev/v1.0.0` by **5 commits**.

## Session Context
- The previous `HANDOFF.md` was stale. In particular, its `gh auth` note is now wrong.
- `gh` on `github.com` works **when escalated outside sandbox**. Earlier “invalid token” failures were sandbox false negatives.
- The real DMF warning root cause was fixed and committed as `cd9e60b`:
  - BetterBots was mixing `_mod:hook(...)` and `_mod:hook_safe(...)` on `BtBotShootAction.enter`
  - fix removed the redundant `weakspot_aim` `enter` hook and moved the scratchpad stash into `weapon_action.lua`
  - live cold run confirmed the warning is gone: latest run had `BB warnings: 0` and `Error lines: 0`

- Current built-in shipped **validation-first** lineup was swapped already:
  - Veteran: `Focus Target + boltgun + power sword`
  - Zealot: `Fury + Martyrdom + heavy eviscerator + autopistol`
  - Psyker: `Scrier's Gaze + Brain Rupture + forcestaff_p3_m1 + force sword`
  - Ogryn: `Point-Blank Barrage + armor-pen + rippergun`

- This session also fixed the latest review findings around startup safety, hook diagnostics, and regression coverage:
  - `BetterBots.lua`
    - `_fixed_time()` now logs a one-shot bootstrap breadcrumb when `Managers.state.extension.latest_fixed_t` is unavailable
    - removed the trailing `or 0` from the `FixedFrame.get_latest_fixed_time()` path so future engine-contract drift is not silently masked
  - `weapon_action.lua`
    - explicit warning if `BtBotShootAction` resolves nil in the `hook_require` callback
    - documented that `scratchpad.__bb_weakspot_self_unit` is captured post-`enter` and is only safe for logging context on the first aim-target pass
  - `bot_profiles.lua`
    - stripped dated/task-log comments while keeping the durable build-rationale comments
  - tests/docs
    - strengthened startup regression coverage for `_fixed_time()`
    - added reload-survival + weakspot handoff coverage for shoot-action hooks
    - added blacklist/override regression coverage for the shipped validation lineup
    - updated logging/debugging docs and downgraded log-only validation-tracker entries from PASS to PARTIAL PASS

- Latest local verification for the review-fix batch:
  - `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua tests/weapon_action_spec.lua tests/bot_profiles_spec.lua`
    - `117 successes / 0 failures / 0 errors`
  - `make check-ci`
    - `1265 successes / 0 failures / 0 errors`
    - `doc-check: all checks passed`

- Latest validated run used log:
  - `console-2026-04-19-13.47.30-9f74e98d-a19e-4398-b3bf-93c243233c93.log`
  - high-level result:
    - warnings/errors clean
    - Zealot dash exercised
    - Scrier build-aware rules exercised
    - Gunlugger exercised, but not all positive branches
    - chain and powered melee specials exercised
    - autopistol close-range hipfire rule exercised
    - no convincing weakspot/rippergun/forcestaff_p3_m1 positive confirmation

- There are **no console logs from 2026-04-18**. User asked to “check yesterday’s logs”; actual filesystem check found none.
  - nearest previous gameplay log was `console-2026-04-17-13.37.34-85c41df2-003b-47e0-9968-bb5549610d5f.log`
  - that older log was useful only for older shout/relic/charge evidence, not for closing the new post-`v0.11.3` follow-ups

- Important conclusion from the weakspot logging audit:
  - logging for `#92` is **adequate**
  - latest run was **not a valid `#92` validation run**
  - reason: `#92` is **ranged-only**, implemented in `weakspot_aim.lua` on `BtBotShootAction`; it does not affect melee
  - current lineup only has one weakspot-aim-eligible ranged bot weapon in that run: the Veteran **bolter**
  - Maulers/Bulwarks did spawn, but the log shows they were mostly being engaged/tagged while bots were on melee weapons, autopistol, rippergun, or force staff
  - absence of `weakspot aim selected` / `weakspot override applied` in the latest run therefore indicates **coverage miss**, not a logging blind spot

- User stated a new design intent verbally:
  - they want **melee/ranged parity** for breed-aware handling such as Mauler/Bulwark/Crusher logic
  - no design/spec was written yet
  - current conclusion from discussion: literal implementation parity is wrong because ranged and melee use different control surfaces; the sane future direction is likely a **shared breed-aware combat policy** consumed by different ranged/melee mechanisms

## GitHub State
- I already added smoke-run comments to:
  - `#103`
  - `#104`
  - `#105`
  - `#13`
  - `#92`
- I deliberately did **not** add a fresh comment to `#17` because the latest run had no daemonhost encounter and would only have repeated “still unvalidated”.
- None of the `needs-testing` issues were closed.

## Remaining Validation Gaps
- `#13`
  - Partial live evidence exists from the 2026-04-19 run for **Zealot** only:
    - blocked and clear `charge_nav` cases were seen
  - still missing: non-Zealot charge variant live evidence (Ogryn and/or Arbites)

- `#17`
  - still missing a real daemonhost encounter in the current build
  - no fresh evidence from the latest run

- `#92`
  - still missing:
    - `weakspot aim selected ...`
    - and ideally `weakspot override applied (breed=renegade_executor|chaos_ogryn_bulwark|chaos_ogryn_executor, ...)`
  - latest run had Bulwarks/Maulers present, but not on an eligible ranged path

- `#103`
  - chain-family path exercised, but not all desired subfamilies cleanly proven in separate live contexts
  - current Zealot uses 2H chain/eviscerator only

- `#104`
  - partial:
    - Scrier fired on build-aware branches
    - Gunlugger fired, but not the full target branch set
  - still missing a clean positive `ogryn_gunlugger_armor_pen_target`
  - Brain Burst arbitration logs showed holds/aborts, but not a clean positive hard-target execution proof

- `#105`
  - autopistol validated
  - still missing positive:
    - `close-range ranged family kept ranged target type (family=rippergun`
    - `close-range ranged family kept ranged target type (family=forcestaff_p3_m1`

## Next Steps
1. Run the **minimal remaining validation checklist**:
   - **Run 1: current validation lineup**
     - goals: top up `#103/#104/#105`
     - require positive markers for:
       - `ogryn_gunlugger_armor_pen_target`
       - `close-range ranged family kept ranged target type (family=rippergun`
       - `close-range ranged family kept ranged target type (family=forcestaff_p3_m1`
       - a clean positive Brain Burst hard-target use, not just `grenade_smite_block_*` / revalidation aborts
   - **Run 2: weakspot + non-Zealot charge**
     - swap Ogryn to a charge build
     - keep a precision ranged Veteran on `lasgun` / `autogun` / `bolter` / `stub revolver`
     - if possible, also cover missing chain families (`chainsword`, `chainaxe`) here
     - require:
       - `weakspot aim selected`
       - ideally `weakspot override applied (...)`
       - non-Zealot `charge_nav=clear` plus at least one blocked nav case
   - **Run 3: daemonhost**
     - stable lineup is fine
     - require a real daemonhost encounter and positive dormant-avoidance evidence

2. After each run, use:
   - `./bb-log summary`
   - `./bb-log warnings`
   - `./bb-log raw '<pattern>'`

3. If evidence is good enough, update GitHub:
   - add comments with exact log evidence
   - close only the issues that now have credible live validation
   - leave the rest open with `needs-testing`

4. If the user wants to pursue the new parity idea, treat it as a **new design task**, not as an incremental validation edit. No spec exists yet.

## Why Switching
- User explicitly asked to hand off the remaining validation work for the next session.
