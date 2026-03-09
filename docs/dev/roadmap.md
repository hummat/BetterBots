# Roadmap

## Vision

Make Darktide bots as capable as VT2's modded bots (Grimalackt's Bot Improvements - Combat). Start with ability activation (already shipped), then add smart trigger heuristics, safety guards, and general behavior improvements.

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes (whitelist removal + meta_data injection)
- Tier 3 item-based abilities (zealot relic, force field, drone — initial implementation)
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Generic trigger: `enemies_in_proximity() > 0`

### v0.2.0 (2026-03-06)
- Sub-module refactor: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25)
- Per-career threat heuristics (#2): 18 functions (14 combat + 4 item) with per-ability activate/hold rules
- 142 unit tests via busted

### v0.3.0 (2026-03-07)
- Tier 3 reliability fix (#3): all testable item abilities at 100% consume rate
- Structured JSONL event logging (#29) with `bb-log events` analysis subcommands
- Item heuristics: per-ability rules for relic, force field, drone, stimm field

### v0.4.0 (2026-03-08)
- Poxburster targeting (#34), ADS fix (#35), bot sprinting (#36)
- Charge/dash rescue aim (#10): rescue triggers + aim correction for zealot dash, ogryn charge, arbites charge
- 198 unit tests, M3 complete

### dev/m4-batch1 (validated on branch, pending merge — 2026-03-09)
- VFX/SFX bleed fix (#42), smart melee attack selection (#23), ranged fire fix (#31), warp venting (#30)
- Staff charged fire (#43, partial — p4 PASS in-game, p3 untested, p1/p2 need investigation)
- 230 unit tests

## Priority tiers

Issues are tracked on [GitHub](https://github.com/hummat/BetterBots/issues) with labels `P1: next`, `P2: later`, `P3: backlog`.

### P2: Later — Planned, not urgent

**Ability activation quality:**

| # | Issue | Notes |
|---|-------|-------|
| 12 | Stance early cancellation | Researched — complex. Stances have no release input (`transition = "stay"`). Needs template injection or `stop_action()` + buff cleanup. |
| 13 | Navmesh validation for charges | GwNav raycast before committing charge direction. |
| 15 | Suppress dodge during ability hold | Unblocked — `movement_state.is_dodging` + `Dodge.is_dodging()` available. Prevent dodge from interrupting charge/hold phases. |
| 21 | Hazard avoidance during abilities | Don't stance in fire/gas/bomber puddles. |
| 37 | Objective-aware ability activation | Protect allies during revive/interaction with defensive abilities (taunt, shout, stealth). |

**Ability scope expansion:**

| # | Issue | Notes |
|---|-------|-------|
| 4 | Blitz / grenade support | Inventory extracted — 19 templates mapped. All except `adamant_whistle` need item-based fallback. `adamant_whistle` is the only blitz with `ability_template` (potential Tier 1/2). #3 resolved — Phase 1 unblocked. |
| 6 | Per-ability toggle settings | DMF widget per ability for enable/disable. |
| 8 | Hive Scum ability support | Tier 1 (Focus/Rampage) likely works already — needs DLC for validation. Stimm Field (Tier 3) also DLC-blocked. |
| 30 | Bot warp charge venting | Validated on dev/m4-batch1, pending merge. 3 hooks: warp charge bridge, hysteresis fix, reload→vent translation. |
| 43 | Staff charged fire | Partial on dev/m4-batch1. `_may_fire()` hook + aim chain derivation. p4 PASS in-game, p3 untested, p1/p2 need decompiled template inspection. |

**Bot weapon/equipment fixes:**

| # | Issue | Notes |
|---|-------|-------|
| 31 | Player weapon ranged `attack_meta_data` | Validated on dev/m4-batch1, pending merge. 36 templates patched with corrected fire/aim-fire inputs. |
| 41 | Weapon/enemy-aware ADS vs hip-fire | Static `killshot` gestalt for all weapons. Need per-weapon gestalt + enemy-aware fire cadence. |

**General bot behavior:**

| # | Issue | Notes |
|---|-------|-------|
| 16 | Bot pinging of elites/specials | Tag high-threat enemies (LOS + 2s cooldown). VT2 mod's #2 feature. |
| 17 | Daemonhost avoidance | Suppress all actions near Daemonhosts. #1 solo play rage-quit scenario. |
| 18 | Boss engagement discipline | Don't focus boss when adds are up. |
| 19 | Stop chasing distant specials | Don't walk >18m to melee a special. Still shoot at any range. |

### P3: Backlog — Nice to have, no timeline

| # | Issue | Notes |
|---|-------|-------|
| 7 | Revive-with-ability | Inject ability BT node before revive (stealth/taunt/shout to protect revive). |
| 14 | Ability cooldown staggering | Team-level coordination: don't stack all abilities simultaneously. |
| 22 | Utility-based ability scoring | Replace boolean conditions with spline-interpolated utility curves (90+ considerations in VT2). Architectural upgrade. |
| 23 | Smart melee attack selection | Armor-aware attack choice (+utility for penetrating vs carapace). Also covers player weapon melee `attack_meta_data` injection. |
| 24 | Healing item management | Don't waste medicae, distribute healing to wounded allies, stim usage. |
| 28 | Built-in bot profile management | Replace Tertium4Or5 dependency with integrated profile selection. |
| 32 | Mule item pickup | Set `bots_mule_pickup = true` + fix `slot_name` vs `inventory_slot_name` mismatch (`bot_group.lua:26` reads wrong field). Not a one-flag fix. |
| 33 | Weapon special actions | Parry, bayonet, etc. Input mechanism trivial; decision logic is the work. |

## Design principles

1. **Don't break what works.** Vanilla bot combat (melee, shoot, revive, rescue, follow) must remain functional. Every change is additive.
2. **Per-ability, not per-class.** Trigger heuristics are per ability template, not per archetype. A Zealot with Dash needs different rules than a Zealot with Stealth.
3. **Conservative by default.** Bots should under-use abilities rather than waste them. A missed opportunity costs nothing; a wasted 80s cooldown costs the next fight.
4. **Observable.** Debug logging traces every activation decision. If a bot does something wrong, the log should explain why.

## Research basis

Heuristics and feature ideas are sourced from:
- **VT2 Bot Improvements - Combat** (Grimalackt) — per-career threat thresholds, revive-with-ability, elite pinging, boss engagement, melee selection
- **VT2 Bot Improvements - Impulse Control** (Squatting-Bear) — ability suppression, anti-waste conditions
- **VT2 decompiled source** — 14-level BT, utility-based scoring, 90+ considerations, item management
- **Darktide community** (Fatshark forums, Steam, Reddit) — prioritized pain points
- **Darktide decompiled source** (v1.10.7) — untapped perception signals, blackboard data, cover system, formation logic
- **Per-class tactics docs** (`docs/classes/*-tactics.md`) — community-sourced USE WHEN / DON'T USE / proposed bot rules

See `docs/related-mods.md` for detailed mod analysis and `docs/classes/*-tactics.md` for per-ability heuristics.

## Milestones

1. **M1 (shipped v0.1.0):** Tier 1 + Tier 2 abilities activate in solo play. Published on Nexus.
2. **M2 (shipped v0.2.0–v0.3.0):** Per-career threat heuristics (#2, closed) + Tier 3 reliability (#3, closed) + structured event logging (#29, closed). 18 heuristic functions, all testable tiers at 100%.
3. **M3 (shipped v0.4.0):** Ability quality + bot fixes — suppression (#11), charge rescue (#10), Psyker overcharge (#27), revive protection (#20), poxburster targeting (#34), ADS fix (#35), bot sprinting (#36).
4. **M4:** Ability polish + weapon fixes — VFX/SFX bleed (#42), melee meta_data (#23), ranged meta_data (#31), warp venting (#30) validated on branch, pending merge. Staff charged fire (#43) partial — p4 PASS, p1/p2/p3 open. Remaining: stance cancellation (#12), navmesh validation (#13), suppress dodge (#15), hazard avoidance (#21), objective-aware activation (#37), per-ability toggles (#6), Hive Scum support (#8), ADS awareness (#41).
5. **M5:** Scope expansion — grenade/blitz support (#4), bot behavior (#16-#19), heal deferral (#39).
6. **M6 (aspirational):** Utility-based scoring (#22). VT2-level bot intelligence.
