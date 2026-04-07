# Status Snapshot (March 18, 2026)

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes
- Tier 3 item-based abilities: zealot relic, force field, drone (initial implementation, later fixed to 100% in v0.3.0)
- Generic trigger: `enemies_in_proximity() > 0`
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Published on Nexus Mods

### v0.2.0 (2026-03-06)
- **Refactored** into sub-modules: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26)
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
- **Daemonhost avoidance** (#17): suppress bot combat near dormant daemonhosts (code + tests, unverifiable in-game — no DH spawn).
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
| #17 | Daemonhost avoidance | **Unverifiable** | No daemonhost spawned in 5 sessions |
| #19 | Distant special penalty | **PASS** | 30+ penalty events across 6 special breeds |
| #43 | Staff p1 Voidstrike charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=trigger_explosion` (bot=2, forcestaff_p1_m1) |
| #43 | Staff p2 Purgatus charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=trigger_charge_flame` (post-hotreload, charge=4) |
| #43 | Staff p3 Surge / p4 Equinox charged fire | **PASS** | `_may_fire swap: fire=shoot_pressed -> aim_fire=shoot_charged` (same input for both; p4 confirmed v0.5.0, p3 structurally identical) |

## Known Blockers

1. **Hive Scum DLC (broker_ archetype)**: Focus, Rage, and Stimm Field abilities are DLC-blocked for validation. Arbites (adamant_ archetype) is available and testable.
2. **#17 daemonhost avoidance**: Code + tests in place, needs a daemonhost encounter to verify in-game.
3. **#4 whistle hot-reload**: whistle works on fresh launch but fails after hot-reload (component template_name likely reset). Not a shipping blocker — hot-reload is dev-only.

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
| #6 | Settings control surface | **Closed** | Category gates (stances/charges/shouts/stealth/deployables/grenades), 4 behavior presets, feature toggles, veteran dual-category gate |
| #45 | Default class profiles | **Closed** | 4-class profiles (Veteran/Zealot/Psyker/Ogryn), hadrons-blessing weapon picks, per-class cosmetics, Tertium compat, `BotSynchronizerHost.add_bot` hook + 5 per-slot dropdowns |
| #63 | Talent enrichment + weapon blessings | **Closed** | ~30 talents per class, 2 T4 blessings + 1-2 T4 perks per weapon, bot-optimized build selection |
| #60 | Heuristic dispatch refactor | **Closed** | `fn(context)` signature simplification |
| #59 | Grenade fallback logging | **Closed** | Per-stage lifecycle events (queued/stage/complete/failed) |

**Unit tests**: 518 tests via busted.

## v0.9.0 — "Combat Awareness" (2026-04-02)

| Issue | Feature | Status | Evidence |
|-------|---------|--------|----------|
| #65 | **P0: non-veteran profiles CTD on 1.11.0** | **Closed** | Profile overwrite guard: `is_local_profile` + `_bb_resolved` + `set_profile` hook. Validated on 1.11.3. |
| #54 | Push poxbursters | **Closed** | `_should_push` outnumbered gate bypassed for poxburster breed. **Note:** hook silently broken by #67 (hook_require clobbering). |
| #55 | Prioritize mastiff-pounced enemies | **Closed** | Score boost for immobilized targets. **Note:** also boosts friendly mastiff pins (#69). |
| #53 | Rumbler VFX timing gap | **Closed** | Pre-call hook on loadout init. |
| #47 | Combat-aware engagement leash | **Closed** | Coherency-anchored leash: stickiness-limit extension, post-charge grace, under-attack/ranged-foray overrides. 700+ override events. |
| #39 | Healing deferral | **Closed** | Validated: 80+ health station deferral events. |
| #37 | Objective-aware ability activation | Deferred to v1.0.0 | Phased design (P1 thresholds → P2 dash-toward → P3 per-type) |

**Unit tests**: 579 tests via busted.

## v0.9.1 — Hotfix (planned)

User-reported regressions and behavior issues from Nexus feedback (2026-04-05/07).

| Issue | Feature | Severity | Status |
|-------|---------|----------|--------|
| #67 | hook_require clobbering (melee light + poxburster push) | **P0** | Open — root cause confirmed |
| #68 | Veteran class swap with other mods | **P1** | Open — root cause confirmed |
| #69 | Mastiff-pinned target fixation | P2 | Open |
| #70 | Arbites whistle ignores dog position | P2 | Open |
| #71 | Ogryn grenade mid-horde | P2 | Open |
| #72 | Ammo threshold dead band (10-20%) | P3 | Open |

## Next Steps

### Later batches

- **v0.10.0 "Team Coordination"**: #14 (cooldown staggering), #7 (revive-with-ability), #13 (navmesh charges), #41 (weapon-aware ADS), #58 (ScriptUnit guard)
- **v1.0.0 "Bot Identity"**: #37 (objective-aware), #38 (talent-aware), #44 (human-likeness Tier A), #24 (healing items), #32 (mule pickup), #33 (weapon specials)
- **Post-1.0**: #22 (utility scoring), #28 (profile management), #56 (com wheel response)
- **Validation-gated**: #8 (Hive Scum, DLC), #17 (daemonhost), #49 (Arbites companion tag, DLC)

See `docs/dev/roadmap.md` for full batch details.
