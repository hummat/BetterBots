# Status Snapshot (April 13, 2026)

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes
- Tier 3 item-based abilities: zealot relic, force field, drone (initial implementation, later fixed to 100% in v0.3.0)
- Generic trigger: `enemies_in_proximity() > 0`
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Published on Nexus Mods

### v0.2.0 (2026-03-06)
- **Refactored** into sub-modules: thin `heuristics.lua` dispatcher + split `heuristics_context.lua` / `heuristics_*.lua`, plus `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26)
- **Per-career threat heuristics** (#2): 18 per-template heuristic functions (14 combat + 4 item)
- **Rich context**: `build_context()` reads health, toughness, peril, challenge_rating_sum, breed tags, ally state, super armor

### v0.3.0 (2026-03-07)
- **Tier 3 reliability** (#3): all testable item abilities at 100% consume rate
- **Structured event logging** (#29): opt-in JSONL event log with `bb-log events` analysis
- **Item heuristics**: per-ability rules for relic, force field, drone, stimm field
- **Safety guards**: revive/interaction protection (#20), ability suppression (#11), warp weapon peril block (#27)

### v0.4.0 (2026-03-08)
- **Poxburster targeting** (#34): removed `not_bot_target` breed flag, suppresses shots when poxburster is close to the bot (<5m) or any human player (<8m)
- **ADS fix for T5/T6 bots** (#35): inject default `bot_gestalts` (`killshot`/`linesman`) when profile omits them
- **Bot sprinting** (#36): sprint module with catch-up (>12m), rescue, traversal conditions + daemonhost safety
- **Charge/dash rescue aim** (#10): zealot dash, ogryn charge, and arbites charge aim toward disabled allies. 14 rescue activations confirmed in-game.
- **Unit tests**: 230 tests via busted (heuristics, meta_data, resolve_decision, event_log, sprint, melee_meta_data, ranged_meta_data)
- **Debug commands**: `/bb_state`, `/bb_decide`, `/bb_brain`

### v0.5.0 (2026-03-09)
- **VFX/SFX bleed fix** (#42): suppress bot ability VFX/SFX bleeding to human player
- **Smart melee attack selection** (#23): armor-aware `attack_meta_data` injection (66 templates)
- **Ranged fire fix** (#31): `attack_meta_data` injection for non-standard fire paths (36 templates patched)
- **Warp venting** (#30): `Overheat.slot_percentage` warp charge bridge + `should_vent_overheat` hysteresis fix + `reload→vent` translation
- **Staff charged fire** (#43, partial): `_may_fire()` hook + aim chain derivation. p4 trauma PASS in v0.5.0. Root cause for p2/p1: `find_aim_fire_input()` couldn't find chain-only fire actions (no `start_input`). Fix: `find_chain_target_action()` fallback scans `allowed_chain_actions` (dev/m5-batch1, commit 09e0f22). p2 flame PASS, p3/p4 PASS, p1 surge structural fix in place (no in-game evidence yet).

### v0.6.0 (2026-03-11)
- **Grenade/blitz throw** (#4): state machine for 19 grenade/blitz templates — wield→aim→throw→unwield for item-based, direct `grenade_ability_action` for ability-based (whistle). Profiles for standard/handleless/mine/knives/whistle/missile launcher.
- **Staff charged fire fix** (#43): all 4 force staves now fire charged attacks. `find_chain_target_action()` fallback for chain-only fire actions (p1 Voidstrike, p2 Purgatus).
- **Bot pinging** (#16): bots ping elites and specials for the human player.
- **Distant special penalty** (#19): melee target selection distance penalty discourages bots from chasing distant specials.
- **Daemonhost avoidance** (#17): suppress bot combat near non-aggroed daemonhosts. The current branch now has two gates: daemonhost `stage` is authoritative when available for target-based suppression, and offensive abilities plus close-range melee/ranged checks also bail out on a tight daemonhost proximity radius. Live re-validation is still pending.
- **Unit tests**: 370 tests via busted.

## Current Tier Status

| Tier | Status | Notes |
|------|--------|-------|
| 1 | PASS (5/5 testable) | Broker (Hive Scum) variants DLC-blocked; adamant (Arbites) testable |
| 2 | PASS (6/6 testable) | `adamant_shout` N/A (cut content) |
| 3 | PASS (3/3 testable) | `zealot_relic`, `force_field`, `drone` all 100%. `broker_stimm_field` Hive Scum DLC-blocked. |

## Evidence Source

- Latest analyzed log: `console-2026-03-13-13.21.23-06323070-33d6-49e5-9e07-a918eea1e556.log`
- Full evidence matrix: `docs/dev/validation-tracker.md`
- Log timestamps are UTC, not local timezone

## M5 Batch Status (dev/m5-batch1)

In-game validation: 2026-03-11, commit 8cce4bd.

| Issue | Feature | Status | Evidence |
|-------|---------|--------|----------|
| #4 | Grenade throw | **PASS** | 7 charges consumed (krak + fire), 0 forced timeouts |
| #4 | Blitz: knives | **PASS** | 8+ charges consumed; wield timeout noise (quick_throw returns to previous slot before detection) |
| #4 | Blitz: whistle | **PASS** | 3/3 charge confirmed on fresh launch; `action_aim` starts, chains to `action_order_companion`. Previous hot-reload session failed — hot-reload resets component state. |
| #4 | Blitz: shock mine | **Untested** | Profile in place, no bot equipped with it yet |
| #4 | Grenade: ogryn cluster | **PASS** | 3 charges consumed with full wield→aim→throw→unwield cycle |
| #16 | Bot pinging | **PASS** | 4 ping events for elites across multiple bots |
| #17 | Daemonhost avoidance | **Gap found three times; patched 2026-04-11 and twice on 2026-04-15** | First DH spawn in v0.10.0 validation exposed the heuristic-path gap: `grenade_fallback` → `_grenade_priority_target` bypassed the `condition_patch` BT wrappers, `psyker_smite` fired on dormant DH at 19m. Fix in commits `03ce4fd` + `ffe7c6b` added `target_is_dormant_daemonhost` and gated 5 heuristic sites. A later 2026-04-15 run still behaved incorrectly because BetterBots only consulted `aggro_state`; the next patch made daemonhost `stage` authoritative when available across combat, ping, companion-tag, player-tag boost, sprint, and debug context. The latest 2026-04-15 DH run still showed immediate aggro because offensive abilities were only target-gated; the current branch now also restores a tight proximity gate for offensive abilities plus close-range melee/ranged checks. Re-validation pending. |
| #19 | Distant special penalty | **PASS** | 30+ penalty events across 6 special breeds |
| #43 | Staff p1 Voidstrike charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=trigger_explosion` (bot=2, forcestaff_p1_m1) |
| #43 | Staff p2 Purgatus charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=trigger_charge_flame` (post-hotreload, charge=4) |
| #43 | Staff p3 Surge / p4 Equinox charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=shoot_charged` (same input for both; p4 confirmed v0.5.0, p3 structurally identical) |

## Known Blockers

1. **Hive Scum DLC (broker_ archetype)**: Focus, Rage, and Stimm Field abilities are DLC-blocked for validation. Arbites (adamant_ archetype) is available and testable.
2. **#17 daemonhost avoidance**: v0.6.0 suppression first had a heuristic-path gap (grenade_fallback bypassed BT condition wrappers), then a state-model gap (`aggro_state` only was too late once the daemonhost started waking), then a scope gap (offensive abilities were still allowed near a sleeping daemonhost unless the DH had already become `target_enemy`). The current branch now uses daemonhost `stage` when available, preserves the long-range target-based carve-out, and restores a tight proximity gate for offensive abilities plus close-range melee/ranged checks. Re-validation with the new build is the next gate — watch for `*_block_dormant_daemonhost`, `ability suppressed (daemonhost_nearby)`, `melee/ranged suppressed (daemonhost nearby)`, and `dormant_daemonhost` skip lines on a DH spawn.

## v0.7.0 (2026-03-12)

| Issue | Feature | Scope | Status |
|-------|---------|-------|--------|
| #40 | Tiered debug log levels | Replace checkbox with info/debug/trace dropdown; tag `_debug_log` calls by level | Implemented, validated in-game |
| #15 | Dodge suppression audit | Research whether dodge interrupts abilities | Closed as not-a-bug |
| #34 | Poxburster targeting fix | Add human-player proximity suppression (don't shoot poxbursters near human) | Implemented, validated in-game |
| #16 | Ping system redesign | Replace 2s cooldown with target tracking + distance escalation anti-spam | Implemented, validated in-game |
| #18 | Boss engagement refinement | Add "boss targeting this bot" self-defense exception to vanilla monster weight | Implemented, validated in-game |
| #48 | Player-tag smart-target response | Add a small score bonus for enemies tagged by a human player | Implemented, validated in-game |
| #21 | Hazard-aware abilities | USE defensive abilities (relic, shout) in hazards; suppress movement-locking stances | Implemented, validated in-game |
| #39 | Healing deferral | Bots defer health stations, med-crates, pickups to human players; emergency override at <25% | Implemented, awaiting in-game trigger |
| #4 | Grenade heuristics + psyker blitz | Per-grenade heuristics (elite/horde/CC/mine/whistle); psyker Assail/Smite/Chain Lightning support | Implemented, validated in-game |

**Unit tests**: 418 tests via busted.

Archived implementation plan: `docs/superpowers/plans/2026-03-12-m5-batch2.md`

## P0/P1 Stabilization (dev/p0-p1-stabilization)

In-game validation: 2026-03-13, latest analyzed log `console-2026-03-13-13.21.23-06323070-33d6-49e5-9e07-a918eea1e556.log`.

| Issue | Feature | Status | Evidence |
|-------|---------|--------|----------|
| #50 | Arbites drone crash guard | **Closed** | Extended 4-Arbites stress run, repeated drone + whistle activations, 0 Lua errors |
| #51 | Ranged ammo threshold override | **Closed** | 270 "ranged permitted with lowered ammo gate" in standard-profile mission (2026-03-14) |
| #52 | Melee heavy-bias reduction | **Closed** | 0 heavies vs unarmored in horde across 2 sessions; all heavies vs armored targets |
| #61 | Assail smart-target seeding | **Closed** | 87 queued → 92 consumed, 0 aim_target=none, both zoom and shoot paths active |
| #62 | Grenade aim direction | **Closed** | 55 aimed releases all with real targets, 0 blind throws, 0 aim unavailable aborts |

**Unit tests**: 461 tests via busted.

All P0/P1 stabilization issues closed. Released as v0.7.1 (2026-03-14).

## v0.8.0 (2026-03-16)

| Issue | Feature | Status | Evidence |
|-------|---------|--------|----------|
| #57 | Toggle safety audit | **Closed** | `is_togglable = false`, singleton mutations not revertible |
| #6 | Settings control surface | **Closed** | Category gates (stances/charges/shouts/stealth/deployables/grenades), 4 behavior presets, feature toggles, veteran semantic stance/shout gate |
| #45 | Default class profiles | **Closed** | 4-class profiles (Veteran/Zealot/Psyker/Ogryn), hadrons-blessing weapon picks, per-class cosmetics, Tertium compat, `BotSynchronizerHost.add_bot` hook + 5 per-slot dropdowns |
| #63 | Talent enrichment + weapon blessings | **Closed** | ~30 talents per class, 2 T4 blessings + 1-2 T4 perks per weapon, bot-optimized build selection |
| #60 | Heuristic dispatch refactor | **Closed** | `fn(context)` signature simplification |
| #59 | Grenade fallback logging | **Closed** | Per-stage lifecycle events (queued/stage/complete/failed) |

**Unit tests**: 518 tests via busted.

## v0.9.0 — "Combat Awareness" (2026-04-02)

| Issue | Feature | Status | Evidence |
|-------|---------|--------|----------|
| #65 | **P0: non-veteran profiles CTD on 1.11.0** | **Closed** | Profile overwrite guard: `is_local_profile` + `_bb_resolved` + `set_profile` hook. Validated on 1.11.3. |
| #54 | Push poxbursters | **Closed** | Validated 2026-04-11 (run `2026-04-11-poxburster-push`): full chain `suppressed poxburster (too_close_to_bot)` → `poxburster in push range, keeping target` → `defend gate bypassed for poxburster target` → `pushing poxburster (bypassed outnumbered gate)` at 16:33:12.312–16:33:12.531. |
| #55 | Prioritize mastiff-pounced enemies | **Closed** | Original score boost shipped in v0.9.0. **Follow-up:** friendly mastiff pins are now explicitly de-prioritized on `dev/v0.9.1` (#69). |
| #53 | Rumbler VFX timing gap | **Closed** | Pre-call hook on loadout init. |
| #47 | Combat-aware engagement leash | **Closed** | Coherency-anchored leash: stickiness-limit extension, post-charge grace, under-attack/ranged-foray overrides. 700+ override events. |
| #39 | Healing deferral | **Closed** | Validated: 80+ health station deferral events. |
| #37 | Objective-aware ability activation | Deferred to v0.10.0 (P1) | Phased design (P1 thresholds → P2 dash-toward → P3 per-type) |

**Unit tests**: 579 tests via busted.

## v0.9.1 — Hotfix

User-reported regressions, behavior issues from Nexus feedback (2026-04-05/07), and bot profile overhaul.

| Issue | Feature | Severity | Status |
|-------|---------|----------|--------|
| #67 | hook_require clobbering (melee light + poxburster push) | **Closed** | April 7 logs showed the consolidated `bt_bot_melee_action` hook install plus repeated `melee choice ...` lines, which is enough to confirm the clobbering regression itself is fixed. |
| #68 | Veteran class swap with other mods + Tertium None yield fix | **Closed** | Validated in run `0`: external real profiles with `character_id` were preserved for bot slots 1-4. `profile.name` guard replaces `character_id`/`current_level` check so Tertium "None" slots pass vanilla profiles through. |
| #73 | Exception-safe shared state mutation in hooks | **Closed** | Defensive failure-path hardening. Tests pass; no restore-after-error log fired in the April 7 runs, but keeping this open for a vanilla throw repro is unnecessary. |
| #69 | Mastiff-pinned target fixation | **Closed** | Validated in run `0`: friendly companion-pin penalties fired in both melee and ranged scoring |
| #70 | Arbites whistle ignores dog position | **Closed** | Validated in run `0`: `grenade_whistle_block_companion_far` held invalid whistles while valid whistles still consumed charges |
| #71 | Ogryn grenade mid-horde | **Closed** | April 7 event log shows `grenade_ogryn_frag_block_melee_range` below 4m and `grenade_ogryn_frag_horde` approvals only above 4m. That is the requested fix. |
| #72 | Configurable ammo policy | **Closed** | April 7 logs exercised both the lowered ranged fire gate and the pickup gate in runtime under different threshold settings. |
| — | Bot build overhaul | **Closed** | All 4 class profiles redesigned with bot-optimized builds from hadrons-blessing. Veteran: VoC + Focus Target (removed dodge/weakspot talents, fixed stat nodes). Zealot: Martyrdom keystone + Benediction aura + bleed synergy. Psyker: Voidblast p4 replaces Surge p3 + Force Greatsword m1 (fixed stat nodes). Ogryn: Indomitable charge + Heavy Hitter + Bully Club + Rumbler (complete rebuild). In-game loading confirmed; full mission validation pending. |

**Unit tests**: 632 tests via busted.

## Next Steps

- **v0.11.0 released 2026-04-15** — the tag is out, and post-release issue hygiene is mostly caught up. `#82` is closed on direct live evidence from `console-2026-04-16-15.35.10...`: same-log `resolve_decision cache hit ...` markers plus a mission-end `bb-perf:auto: 104.9 us/bot/frame total` block. `#99` is now closed as well: the recorder was already done, and the missing work was to define a credible benchmark protocol and acceptance bar. v1.0.0 now uses mission-end `bb-perf:auto:` totals from three live Solo Play runs, median-of-three as the headline metric, and **median <= `125 µs/bot/frame` with no single run > `140`** as the release bar. The old `<80` target is retired.
- **v0.10.0 released 2026-04-11** — all 6 issues validated, tagged, pushed, GitHub release + Nexus package ready.

### Later batches

- **v0.10.0 "Team Coordination"**: ALL CLOSED — ~~#7~~, ~~#14~~, ~~#37~~, ~~#49~~, ~~#81~~, ~~#83~~. 813 tests. **Released 2026-04-11.**
- **v0.11.0 "Combat Execution" (final polish batch)**: released on `2026-04-15`, and the issue cleanup is effectively complete. `#32`, `#44`, `#82`, `#87`, `#89`, `#90`, `#91`, and `#93` are closed. `#32` is closed on authoritative runtime evidence from `console-2026-04-15-18.01.55...` (`mule pickup success: tome (bot=4)`). `#82` is closed on direct 2026-04-16 runtime proof that the final same-frame `resolve_decision(...)` reuse landed, with the same log also showing a mission-end `104.9 us/bot/frame` sample; any deeper perf work is now tracked separately in `#99`. `#90` is closed on direct 2026-04-16 runtime proof from `console-2026-04-16-17.51.56...`: the fixed `BotPerceptionExtension._update_target_enemy` hook produced `32` `type flip ...` lines, `46` `type hold ...` lines, `4` `suppressed opposite-type switch ...` lines, and the mission-end row `target_type_hysteresis.post_process 143.000 ms total (11473 calls, 12.5 us/call)`. The only notable live-validation holdout from this era is now `#17` daemonhost avoidance. |
- **Closed 2026-04-13**: #44 (human-likeness Tier A — closed from current branch code + tests + live runtime markers for reaction-time patching and pressure-leash scaling; jitter remains test-covered but not separately logged), #93 (grenade ballistic arc fix — closed from live ballistic aim/wield/consume evidence plus manual gameplay confirmation that the remaining short-throw concern was gone)
- **v1.0.0 "Bot Identity" (terminal release)**: staggered 6-sprint plan (see `docs/dev/roadmap.md` v1.0.0 section). Sprint 1 is code-complete: F1 talent context landed, `#13` landed as a shared charge/dash nav validator that checks the actual launch endpoint (`NavQueries.ray_can_go(...)` against explicit rescue aim, Zealot targeted-dash enemy position, or nav destination as fallback), wired in both BT enter and fallback with a 0.5 s same-endpoint negative cache, `#92` is code-complete for the current scope (Scab Mauler spine override, Bulwark exposed-head routing, plus a **provisional** Crusher rear-arc head proxy documented as assumption rather than verified rig fact), and `#86` is **done 2026-04-17** (`BtBotInteractAction.enter` hook confirmed unusable, Tier 3 implementation moved to Post-1.0). Sprint 2 is code-complete on the branch: `#38` landed as a narrow shipped-roster MVP on 2026-04-18, with Martyrdom live-healing suppression + low-HP Shroudfield panic disable, Psyker Venting Shriek peril preservation keyed off the shipped warp-charge damage talents, and a Focus Target Veteran ping override so already-tagged priority targets can still become `enemy_over_here_veteran`. Sprint 3 is now code-complete on the branch as well: `#41` landed as a narrow close-range family policy for flamer / Purgatus / shotgun / heavy-stubber weapons, keeping ranged target type under close pressure and suppressing ADS in the hipfire window; `#33` landed as a narrow powered-melee identity pass, prepending `special_action` for force swords, power swords, and thunder hammers when engaging elite/specialist targets. Sprint 4 is now mostly code-complete on the branch too: the old "missing pocketable primitive" assumption turned out to be wrong, so BetterBots now patches supported pocketables into the existing vanilla mule path, lands `#24a` medicae discipline, lands `#24b` stim self-use on high-threat entry, and lands `#88` ammo/medical crate carry + conservative auto-deploy. The broad `#24c` give-to-ally / wound-cure distribution path stays post-1.0. Sprint 5 is now code-complete on the branch: `#101` landed shared slot-lock fast-retries for grenade/item fallbacks, `#96` landed a narrow smart-tag interaction bridge that routes explicit ammo/book/supported-pocketable item tags back into the existing `BotOrder.pickup(...)` path through the existing BetterBots policy gates, `#56` landed a narrow Solo Play com-wheel bridge that turns `com_cheer` into a short aggressive preset override while treating `com_need_ammo` / `com_need_health` as temporary human-priority deferral signals, and `#97` finished the remaining non-book arbitration gap by promoting health-station demand for any damaged non-Martyrdom bot once humans are above reserve while leaving the existing ammo/grenade any-missing-once-safe behavior intact. Sprint 6 is now fully code/doc-complete on the branch: `#98` hardened the engine-facing metadata boundaries so truthy non-table `attack_meta_data` values are treated as invalid rather than being indexed directly; `#102` stopped inventing `zoom` / `zoom_shoot` fallback inputs, clears stale scratchpad aim fields on non-aim weapons, and drops parser-proven unsupported queued `zoom` / `unzoom` actions before they reach `ActionInputParser`; `#99` closed by defining the mission-end perf benchmark protocol and retiring the under-specified `<80` target; and `#85` is closed because the combat-ability identity split already landed and has both regression coverage and later live-path validation through revive/team-cooldown behavior. What remains is integrated in-game validation and release soak, not more planned implementation.
- **Post-1.0 "Intelligence Architecture" (may never ship)**: #22 (utility scoring), #28 (profile management), #80 (grenade tactical evaluator), #84 (user-authored profiles), #86 (Tier 3 revive cover — moved 2026-04-17 after enter-hook scope-exit; approach-phase architecture via `on_refresh_destination` + gated `can_revive` documented on the issue). Broad-scope cuts from v1.0.0 issues (broad #24, broad #33, broad #41, replacing the provisional Crusher proxy in #92 with rig-verified routing, keystone extensions beyond shipped roster) formally scope-exited under the parent issues.
- **Validation-gated**: #8 (Hive Scum, DLC), #17 (daemonhost — heuristic carve-out staged 2026-04-11, stage-aware dormant detection and tight proximity suppression added 2026-04-15, re-validation pending)
- **Closed 2026-04-11**: #54 (poxburster push validated in run `2026-04-11-poxburster-push`), #74 (per-bot throttle discriminator shipped v0.9.1 + exercised in same run)

Planning artifacts for `#80`:

- Spec: `docs/superpowers/specs/2026-04-08-grenade-blitz-tactical-evaluator-design.md`
- Plan: `docs/superpowers/plans/2026-04-08-grenade-blitz-tactical-evaluator.md`

See `docs/dev/roadmap.md` for full batch details.
