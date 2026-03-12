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

### v0.5.0 (2026-03-09)
- VFX/SFX bleed fix (#42), smart melee attack selection (#23), ranged fire fix (#31), warp venting (#30)
- Staff charged fire (#43, partial — p4 PASS in-game, p3 untested, p1/p2 need investigation)

### v0.6.0 (2026-03-11)
- Grenade/blitz throw (#4): state machine for 19 templates, profile-driven. Standard/handleless/mine/knives/whistle/missile. Generic heuristic only; per-grenade heuristics in v0.6.1.
- Staff charged fire complete (#43): all 4 staves PASS — chain-only fire derivation fix for p1 Voidstrike + p2 Purgatus.
- Bot pinging (#16): bots ping elites/specials for human player.
- Distant special penalty (#19): melee target distance penalty for specials.
- Daemonhost avoidance (#17): suppress combat near dormant daemonhosts.
- 305 unit tests

### v0.7.0 (2026-03-12)
- Batch 2 shipped: grenade heuristics + Psyker blitz follow-up (#4), hazard-aware abilities (#21), boss engagement refinement (#18), tiered log levels (#40), healing deferral implementation (#39), player-tag smart-target response (#48), and follow-up validation/logging cleanup.

## Priority tiers

Issues are tracked on [GitHub](https://github.com/hummat/BetterBots/issues) with labels `P1: next`, `P2: later`, `P3: backlog`.

### P2: Later — Planned, not urgent

**Ability activation quality:**

| # | Issue | Notes |
|---|-------|-------|
| 12 | Stance early cancellation | Researched — complex. Stances have no release input (`transition = "stay"`). Needs template injection or `stop_action()` + buff cleanup. |
| 13 | Navmesh validation for charges | GwNav raycast before committing charge direction. |
| 37 | Objective-aware ability activation | Protect allies during revive/interaction with defensive abilities (taunt, shout, stealth). |

**Ability scope expansion:**

| # | Issue | Notes |
|---|-------|-------|
| 6 | Ability/settings control surface | Partial scope can ship earlier: `standard/testing` behavior profile + tier/grenade toggles. Remaining broader scope: per-ability toggles and calibrated multi-preset tuning. |
| 8 | Hive Scum ability support | Tier 1 (Focus/Rampage) likely works already — needs DLC for validation. Stimm Field (Tier 3) also DLC-blocked. |

**Bot weapon/equipment fixes:**

| # | Issue | Notes |
|---|-------|-------|
| 41 | Weapon/enemy-aware ADS vs hip-fire | Static `killshot` gestalt for all weapons. Need per-weapon gestalt + enemy-aware fire cadence. |

**Bot profiles:**

| # | Issue | Notes |
|---|-------|-------|
| 45 | Default class profiles for bots | Ship hardcoded Zealot/Psyker/Ogryn/Veteran profiles so players without leveled characters get class-diverse bots with abilities. Complements #28. |

**General bot behavior:**

| # | Issue | Notes |
|---|-------|-------|

### P3: Backlog — Nice to have, no timeline

| # | Issue | Notes |
|---|-------|-------|
| 7 | Revive-with-ability | Inject ability BT node before revive (stealth/taunt/shout to protect revive). |
| 14 | Ability cooldown staggering | Team-level coordination: don't stack all abilities simultaneously. |
| 22 | Utility-based ability scoring | Replace boolean conditions with spline-interpolated utility curves (90+ considerations in VT2). Architectural upgrade. |
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
4. **M4 (shipped v0.5.0):** Ability polish + weapon fixes — VFX/SFX bleed (#42), melee meta_data (#23), ranged meta_data (#31), warp venting (#30), staff charged fire (#43 partial — p4 only).
5. **M5 (shipped v0.6.0):** Scope expansion — grenade/blitz support (#4), staff charged fire complete (#43), bot pinging (#16), daemonhost avoidance (#17), distant special penalty (#19).
6. **M5-batch2 (shipped v0.7.0):** Grenade heuristics + Psyker blitz (#4), ping anti-spam (#16), poxburster human proximity (#34), hazard-aware abilities (#21), boss engagement (#18), dodge suppression audit (#15), tiered log levels (#40), healing deferral implementation (#39), player-tag smart-target response (#48).
7. **M6 (aspirational):** Utility-based scoring (#22). VT2-level bot intelligence.
