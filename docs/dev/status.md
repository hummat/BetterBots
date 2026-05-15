# Status Snapshot (May 6, 2026)

## Current work

### Unreleased (after v1.1.1)
- **Hotfix pending**: smart-tag pickup routing and BetterBots pickup-order policy hooks now exit outside local SoloPlay before touching bot pickup state. The local-session guard consumes SoloPlay's `is_soloplay()` helper and Darktide's `Managers.multiplayer_session:host_type()` (`singleplay` / `singleplay_backend_session`), with `host_singleplay` only as a fallback because real SoloPlay mission logs can leave that game-mode flag false. This fixes a Nexus report where marking ammo in public/Havoc could call `Ammo.reserve_ammo_is_full` on a dedicated-server client husk visual-loadout extension that lacks `slot_configuration_by_type`, and also hardens the adjacent `BotOrder.pickup` hook against the same public-match leakage class.
- **Defense-in-depth**: `target_selection.slot_weight` now skips its `Ammo.current_slot_percentage("slot_secondary")` lookup when the unit lacks a player-side `visual_loadout_system` extension. The hook is unreachable for husks today (BotPerceptionExtension is `local_init`-only) but the guard removes the latent crash class so a future engine change cannot resurface it.

## What's shipped

### v1.1.1 (2026-05-03)
- **Hotfix**: hazard-prop hook crashed on dedicated-server clients (public/Havoc games) where `GroupSystem._bot_groups` is nil. Added `_is_server`/`_bot_groups` guard. Also fixed `healing_deferral` reading nonexistent `Side.valid_bot_units` — health station bot-priority deferral was dead code. Mock fidelity rule broadened to cover engine object fields and server-only initialization.

### v1.1.0 (2026-05-02)
- **Post-1.0 hardening**: daemonhost avoidance now detects passive and awake-but-not-aggroed daemonhosts through side lists plus the minion-spawn fallback, suppresses ranged/grenade/blitz/ability paths near them, and uses softer keepout steering so narrow passages remain usable.
- **Hazard movement safety**: fused barrels emit buffered AoE threats, AoE threat consumption is logged, and ledge safety blocks only dodge endpoints instead of ordinary stair/downhill movement.
- **Pickup and healing repairs**: explicit smart-tag pickup orders are materialized into mule pickup state, stale pickup refs are cleared before vanilla update, scarce healing stations prefer the bot/human that actually needs the charge most while preserving Martyrdom wounds, and an optional ping-only mode blocks bot health-station use until a human tags the station.
- **Release regression surface**: scenario library expansion, core regression checklist, and log cleanup for repeated daemonhost/charge-path diagnostics.
- **Validation**: latest release-candidate log `console-2026-05-02-16.44.02...` has zero BetterBots warnings/errors and shows daemonhost detection, soft/medium steering, ranged/grenade/ability suppression while passive, and normal combat only after aggro.

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
- **Daemonhost avoidance** (#17/#107): suppress bot combat and risky movement near non-aggroed daemonhosts. The current branch has several gates: daemonhost `stage` is authoritative when available for target-based suppression, offensive abilities plus close-range ranged checks bail out on daemonhost proximity, the central `weapon_action` queue blocks direct ranged/melee/grenade inputs when the current `target_enemy` is a non-aggroed daemonhost, charge/dash endpoint validation rejects launches into keepout, and movement safety softly biases bots away only inside a tighter movement radius capped below the action keepout. Mixed-target melee remains available so bots can defend themselves. The daemonhost proximity scan now uses the bot side's known enemy relation list plus the minion spawn manager's live minion list, with a minion-spawn fallback even when side lookup is missing, so passive/awake-but-not-aggroed daemonhosts can still suppress sprint, abilities, blitzes, charge/dash launches, and ranged fire into their keepout zone.
- **Unit tests**: 370 tests via busted.

## Current Tier Status

| Tier | Status | Notes |
|------|--------|-------|
| 1 | PASS (5/5 testable) | Broker (Hive Scum) variants DLC-blocked; adamant (Arbites) testable |
| 2 | PASS (6/6 testable) | `adamant_shout` N/A (cut content) |
| 3 | PASS (3/3 testable) | `zealot_relic`, `force_field`, `drone` all 100%. `broker_stimm_field` Hive Scum DLC-blocked. |

## Evidence Source

- Latest analyzed log: `console-2026-05-02-14.33.58` (v1.1.0 post-release validation — daemonhost, hazards, smart-tag, pickups)
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
| #17 | Daemonhost avoidance | **Closed** | Closed from `console-2026-05-02-14.33.58...`: BetterBots detected a passive `chaos_daemonhost` at `stage=1`, then awake-but-not-aggroed `stage=2`/`stage=4`, steered bots away inside the close movement radius, logged Mauler-to-DH range buckets, suppressed ranged fire at non-DH targets inside keepout, and held grenades/blitzes/abilities with `daemonhost_nearby_target`. |
| #19 | Distant special penalty | **PASS** | 30+ penalty events across 6 special breeds |
| #43 | Staff p1 Voidblast charged fire | **Re-validation pending** | Older `_may_fire swap` evidence proved only the validation seam, not the live release. The 2026-04-23 log still showed `forcestaff_p1_m1` entering `action_charge` and later falling back to plain `shoot_pressed` / `vent` with no `voidblast ...` confirmation. Current branch now keys the p1 fix stack off the live `weapon_action.current_action_name == "action_charge"` path; in-game proof is still pending. |
| #43 | Staff p2 Purgatus charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=trigger_charge_flame` (post-hotreload, charge=4) |
| #43 | Staff p3 Surge / p4 Equinox charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=shoot_charged` (same input for both; p4 confirmed v0.5.0, p3 structurally identical) |

## Known Blockers

1. **Hive Scum DLC (broker_ archetype)**: Focus, Rage, and Stimm Field abilities are DLC-blocked for validation. Arbites (adamant_ archetype) is available and testable.

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
| #39 | Healing deferral | Bots defer health stations, med-crates, pickups to human players; emergency override at <25%; optional ping-only health-station use | Implemented, awaiting in-game trigger |
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
| — | Bot build overhaul | **Closed** | All 4 class profiles were redesigned and then retuned again from live `/build_dump` exports. Current defaults: Veteran = VoC + Focus Target + power sword + plasma gun; Zealot = Redoubled Zeal + Martyrdom + thunder hammer + boltgun; Psyker = Scrier's Gaze + Disrupt Destiny + force greatsword + recon lasgun; Ogryn = Loyal Protector + Heavy Hitter + latrine shovel + kickback. The shipped profile source authors runtime weapon perks/blessings and dumped curio packages for both downstream consumers and runtime equip. In-game loading of the older lineup was confirmed; the 2026-05-02 dump-based non-veteran lineup still needs a full mission validation pass. |

**Unit tests**: 632 tests via busted.

### v1.0.0 (2026-04-24)
- **Terminal release**: 6-sprint plan covering talent-aware heuristics, navmesh charge validation, melee/ranged weapon specials, pocketable carry/deploy, com-wheel response, smart-tag item pickup, team coordination, and metadata hardening.
- All Sprint 1-6 issues closed. 1324 tests via busted.
- Perf benchmark protocol: median <= 125 us/bot/frame, no single run > 140.
- See `docs/dev/roadmap.md` v1.0.0 section for the full sprint-by-sprint history.

## Post-v1.0 validation (closed 2026-05-02)

All post-v1.0 validation items are closed with live evidence:

- `#108` rescue priority — closed from `console-2026-04-29-17.10.48...`; later hardened so the forced nearest-bot path covers netted bot allies and disabler-target rescues while keeping humans ahead of bots.
- `#17` daemonhost avoidance — closed from `console-2026-05-02-14.33.58...`
- `#106` perf cap — closed from April 29 runs (median 95.7 us/bot/frame)
- `#100` scenario harness — closed from April 29 live scenario rows
- `#107` barrel/hazard avoidance — closed from `console-2026-05-02-14.33.58...`
- `#96` smart-tag item bridge — closed from `console-2026-05-02-14.33.58...`

## Open post-1.0 issues

- **Post-1.0 "Intelligence Architecture" (may never ship)**: #22 (utility scoring), #28 (profile management), #80 (grenade tactical evaluator), #84 (user-authored profiles), #86 (Tier 3 revive cover).
- **Broad-scope cuts** (scope-exited under parent issues): broad #24, remaining broad #33, remaining broad #41, Crusher rig verification (#92), deeper keystone/build extensions.
- **Validation-gated**: #8 (Hive Scum, DLC).
- **`needs-testing`**: #8, #13, #43 (p1 voidblast), #56, #88, #92, #97, #101 — implemented but awaiting further in-game proof.
- **`#97` partial evidence**: May 2-3 logs validate tiny ammo top-off, world grenade pickups, and practical medicae use; keep open for med-crate / health-deployable use completion and clearer ammo-driven grenade refill evidence.
- **Closed from focused non-game evidence**: #98 sparse metadata hardening, because the acceptance criteria are boundary guards plus sparse-shape regressions rather than a naturally reproducible gameplay trigger.

See `docs/dev/roadmap.md` for full batch details.
