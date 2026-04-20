# Handoff

**From:** Codex (GPT-5, OpenAI API)  
**Date:** 2026-04-20

## Branch
- `dev/v1.0.0`
- Base HEAD before local wrap-up commit: `0cecb61`

## What Landed This Session
- Brain Burst is now talent-aware for `psyker_smite_on_hit`:
  - manual Brain Burst is de-prioritized on ordinary elites/specials when the proc talent is present
  - bombers, super-armor, monsters, and explicit long-range priority targets still stay eligible
  - main files: [heuristics_context.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/heuristics_context.lua), [heuristics_grenade.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/heuristics_grenade.lua)
- Melee special policy was split by real family instead of the old broad powered bucket:
  - 1H power sword
  - 2H power sword
  - 1H force sword
  - 2H force sword
  - thunder hammer
  - chain family
  - main file: [melee_attack_choice.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/melee_attack_choice.lua)
- First-pass shotgun special-shell support landed:
  - supported shotgun families rewrite fire into `special_action`
  - spend-time logs include target breed
  - main files: [ranged_special_action.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/ranged_special_action.lua), [weapon_action.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/weapon_action.lua)
- Weakspot logging bug fixed:
  - `weakspot aim selected ...` is now gated by the actual `weakspot_aim` feature setting instead of the broader ranged-improvements setting
  - main files: [BetterBots.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/BetterBots.lua), [weapon_action.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/weapon_action.lua)
- Smart-tag pickup bridge bug fixed:
  - bridge now hooks `SmartTagSystem.set_contextual_unit_tag(...)` and `SmartTagSystem.trigger_tag_interaction(...)`
  - old generic hook surface was insufficient for real item tags
  - main file: [smart_tag_orders.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/smart_tag_orders.lua)
- Stale ADS carryover bug fixed:
  - `BtBotShootAction` now suppresses stale aim/unaim inputs against the live wielded template before they hit `ActionInputParser`
  - main file: [weapon_action.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/weapon_action.lua)
- Default validation-first roster was retuned again:
  - Veteran: VoC + Focus Target + precision lasgun + chainsword
  - Zealot: Fury + Martyrdom + chainaxe + stub revolver
  - Psyker: Scrier's Gaze + Brain Rupture + electrokinetic staff + force sword
  - Ogryn: Point-Blank Barrage + armor-pen rippergun + Bully Club
  - main file: [bot_profiles.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/bot_profiles.lua)

## Verification
- `make check-ci`
  - pass
  - `1282 successes / 0 failures / 0 errors / 0 pending`
  - `doc-check: all checks passed`
- Focused red/green was also done during the session for:
  - weakspot log-gating regression
  - smart-tag routing regression
  - stale shoot aim/unaim suppression regression

## Latest In-Game Evidence
- Latest clean runtime log:
  - `console-2026-04-20-19.55.09-b1dc792b-e298-409e-9df5-47d4afa83fcf.log`
- What that log proved:
  - no BetterBots warnings
  - no Lua errors
  - no `ActionInputParser` zoom/unzoom noise of the old `#102` class
  - new stale-input containment markers fired:
    - `suppressed stale shoot aim input zoom for chainaxe_p1_m2`
    - `suppressed stale shoot aim input zoom for chainsword_p1_m1`
    - `suppressed stale shoot unaim input unzoom for ogryn_club_p2_m3`
  - smart-tag bridge is alive and reaching policy decisions:
    - `smart-tag pickup ignored for syringe_power_boost_pocketable (reason=no_eligible_bot)`
    - `smart-tag pickup ignored for medical_crate_pocketable (reason=no_eligible_bot)`
    - `smart-tag pickup ignored for syringe_corruption_pocketable (reason=unsupported_pocketable)`
- Previous useful validation logs this session:
  - `console-2026-04-20-18.30.47-c687b3e8-22d8-4beb-b875-379986fd2fd4.log`
    - Brain Burst proc-cover suppression proved live
    - `ogryn_gunlugger_armor_pen_target` confirmed live
    - melee family split confirmed for `powersword_1h`, `chain`, `forcesword_1h`
  - `console-2026-04-20-19.29.16-a83efac0-645f-4f86-a565-9f65c17a99b0.log`
    - shotgun special-shell support clearly live
    - `armed shotgun special for ...`
    - `spent shotgun special for ...`
    - good spend targets included shocktrooper, berzerker, mutant, flamer, netgunner, bomber, gunner

## GitHub State
- `#102` was closed this session with live-noise confirmation.
- `#96` got a follow-up comment explaining the hook-surface fix and the remaining live-validation gap.
- Earlier in the session, `#33` and `#104` were already updated as well.

## Remaining Validation Gaps
- `#92`
  - still missing fresh live `weakspot aim selected ...` / `weakspot override applied ...` evidence
  - current implementation is code-complete, but the desired live confirmation still did not happen in the latest runs
- `#17`
  - still needs a real daemonhost encounter
- `#96`
  - routing bug is fixed, but still no clean positive `smart-tag pickup routed ...` live line
- Broader follow-up scope intentionally still deferred:
  - power mauls
  - Ogryn melee special families
  - shield/block-charge specials
  - bash/bayonet ranged specials
  - Brain Burst proc-cooldown-state modeling beyond the current talent-aware carve-out

## Next Best Test
- One more weakspot-first run:
  - keep Veteran on `lasgun_p3_m2`
  - keep Zealot on `stubrevolver_p1_m2`
  - objective: force Mauler / Bulwark / Crusher ranged windows
  - grep after run:
    - `./bb-log raw 'weakspot aim selected|weakspot override applied|smart-tag pickup routed|dormant_daemonhost'`

