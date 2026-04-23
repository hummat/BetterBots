# Handoff

**From:** Codex (GPT-5, OpenAI API)  
**Date:** 2026-04-20

## Session Update — 2026-04-23 grenade/staff/smart-tag follow-up

- Assail / grenade fallback was tightened and revalidated:
  - Assail crowd bursts now fail closed when shard count cannot be read
  - precision throws reject stale/dead targets and now distinguish `grenade aim lost dead target ...` from generic no-target failure
  - non-explosive grenade pacing is covered across aggressive / balanced / conservative presets and the previously uncovered shock / flash / mine wrappers
  - grenade charge reads are now wrapped in `pcall` with one-shot `grenade charge query failed ...` logging
- Voidblast (`forcestaff_p1_m1`) is still **not** revalidated live, but the branch now follows the actual live charge path:
  - the old `scratchpad.charging_shot`-only assumption was wrong for p1
  - current code keys the fix stack off `weapon_action.current_action_name == "action_charge"` as well
  - `_update_aim` anchor lock and `_fire` `trigger_explosion` override both have regression coverage for the live path
  - `#43` was reopened because the old “PASS” evidence only proved `_may_fire` validation, not the real charged release
- Smart-tag pickup bridge:
  - April 22 logs showed the bridge firing but falsely rejecting all bots as `bot_dead`
  - current branch fixes the bot-liveness check to trust `ALIVE[unit]`, then `Unit.alive(unit)`, before `player:unit_is_alive()`
  - `#96` now has a follow-up comment documenting that fix

## Verification — 2026-04-23

- Passed:
  - `make check`
    - `1379 successes / 0 failures / 0 errors / 0 pending`
    - `luacheck: 0 warnings / 0 errors`
    - `lua-language-server: Diagnosis completed, no problems found`
    - `doc-check: all checks passed`

## Current priority gaps

- `#43`
  - reopened
  - still needs fresh in-game proof for p1 Voidblast:
    - `voidblast anchor locked`
    - `voidblast charged fire override` or a real `trigger_explosion` action for `forcestaff_p1_m1`
- `#96`
  - code-side false-`bot_dead` rejection is fixed
  - still needs a new positive `smart-tag pickup routed ...` live line
- Assail
  - current logs prove aimed/special use again
  - still missing a fresh live confirmation of the crowd-burst path after the recent reserve/depletion/peril changes

## Session Update — 2026-04-22 default roster refresh

- Shipped BetterBots default profiles were retuned to the requested curated lineup sourced from hadrons-blessing canonical builds:
  - Veteran: Voice of Command + Focus Target with power sword + plasma gun
  - Zealot: Chorus + Blazing Piety with heavy eviscerator + boltgun
  - Psyker: Venting Shriek + Warp Siphon with duelling sword + voidstrike staff
  - Ogryn: Indomitable + Heavy Hitter with latrine shovel + ripper gun
- Main files:
  - [scripts/mods/BetterBots/bot_profiles.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/bot_profiles.lua)
  - [scripts/mods/BetterBots/BetterBots_localization.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/scripts/mods/BetterBots/BetterBots_localization.lua)
  - [tests/bot_profiles_spec.lua](/run/media/matthias/1274B04B74B032F9/git/BetterBots/tests/bot_profiles_spec.lua)
- One authored Veteran stat node key was invalid against the actual tree manifest. It was corrected from `base_melee_damage_node_buff_medium_1` to `base_melee_damage_node_buff_high_1`.
- Arbites / Hive Scum were intentionally not added to the shipped profile surface yet. They remain comment-only backlog placeholders because the built-in profile UI and hadrons-blessing sync/export contract still target the core 4 classes.

## Verification — 2026-04-22

- Passed:
  - `make test`
    - `1331 successes / 0 failures / 0 errors / 0 pending`

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

## Next Log Watchlist
- Psyker Assail misuse:
  - shards thrown with no enemies around
  - shards launched without actually targeting enemies
- Grenade misuse in general:
  - grenades thrown with no clear trigger / no visible tactical reason
- Psyker vs double Crusher:
  - does not commit to heavy melee into two Crushers
  - observed failure mode to confirm/refute: blocks / dashes instead of attacking at all
- Zealot fire grenade pacing:
  - two incendiary grenades thrown in quick succession

## Session Update — 2026-04-22 profile naming audit follow-up

- Psyker shipped-profile naming drift was corrected:
  - `forcestaff_p1_m1` is now labeled `Voidblast` consistently in:
    - `scripts/mods/BetterBots/bot_profiles.lua`
    - `scripts/mods/BetterBots/BetterBots_localization.lua`
    - `docs/knowledge/weapon-blessings.md`
    - `docs/dev/status.md`
    - `docs/dev/validation-tracker.md`
- Root cause of the miss:
  - the test harness pinned profile loadout IDs but did not pin the human-readable shipped profile labels, so a stale `Voidstrike` string survived while the underlying `forcestaff_p1_m1` template was already correct.
- Harness fix shipped with the content fix:
  - `tests/bot_profiles_spec.lua` now asserts all four shipped dropdown/profile labels, including `Psyker - Voidblast Staff + Duelling Sword`.

## Verification — 2026-04-22 naming fix

- Passed:
  - `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/bot_profiles_spec.lua`
    - `34 successes / 0 failures / 0 errors / 0 pending`
  - `make doc-check`
    - `doc-check: all checks passed`
  - user-ran `make check`
    - `1332 successes / 0 failures / 0 errors / 0 pending`
