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
- Grenade/blitz throw (#4): state machine for 19 templates, profile-driven. Standard/handleless/mine/knives/whistle/missile. Initial support only.
- Staff charged fire complete (#43): all 4 staves PASS — chain-only fire derivation fix for p1 Voidstrike + p2 Purgatus.
- Bot pinging (#16): bots ping elites/specials for human player.
- Distant special penalty (#19): melee target distance penalty for specials.
- Daemonhost avoidance (#17): suppress combat near dormant daemonhosts.
- 305 unit tests

### v0.7.0 (2026-03-12)
- Batch 2 shipped: grenade heuristics + Psyker blitz follow-up (#4), hazard-aware abilities (#21), boss engagement refinement (#18), tiered log levels (#40), healing deferral implementation (#39), player-tag smart-target response (#48), and follow-up validation/logging cleanup.

### v0.7.1 (2026-03-14)
- P0/P1 stabilization: animation crash guard (#50), ammo threshold (#51), melee horde bias (#52), Assail void throws (#61), grenade misaim (#62), unarmed defer, smart blitz targeting, ADS fire fix. Repo cleanup (scrapers migrated to hadrons-blessing). 461 tests.

### v0.8.0 (2026-03-16)
- Default class-diverse bot profiles (#45): 4-class loadouts with per-slot settings, Tertium compat, cosmetic overrides.
- Full talent enrichment (#63): ~30 talents per class from hadrons-blessing builds, including abilities, keystones, and stat nodes. Bot-optimized build selection (Voice of Command veteran, Electro Shriek psyker, Gun-Lugger ogryn).
- Weapon blessings and perks (#63 phase 2): 2 T4 blessings + 1-2 T4 perks per weapon via synthetic `get_item_instance` overrides. First mod to construct blessed weapons without player backend profiles.
- Settings control surface (#6): category checkboxes, 4 behavior presets, feature gates, veteran dual-category gate.
- Heuristic dispatch refactor (#60), grenade fallback logging (#59), toggle safety audit (#57).
- Log throttle collision fix: 19 per-bot debug log keys were silently dropping multi-bot messages. Convention updated in AGENTS.md + logging.md.
- 518 unit tests.

## Planned batches

Issues are tracked on [GitHub](https://github.com/hummat/BetterBots/issues).

### v0.9.0 — "Combat Awareness"

*Theme: bots perceive and react to combat situations better.*

| # | Issue | Notes |
|---|-------|-------|
| 65 | **P0: non-veteran profiles CTD on 1.11.0** | Native crash on Zealot/Psyker/Ogryn bot profiles in Darktide 1.11.0 (Warband). Workaround: Veteran or None. Blocked on 1.11.0 decompiled source. |
| 54 | Push poxbursters | **Done.** Bypass `_should_push` outnumbered gate for poxburster breed + push logging. |
| 55 | Prioritize mastiff-pounced enemies | **Done.** Score boost for immobilized targets in target_selection.lua. |
| 53 | Rumbler VFX timing gap | **Done.** Pre-call hook on loadout init restored (crash was from profiles, not VFX). |
| 47 | Combat-aware engagement leash | Hook `_allow_engage()` for context-aware range extension: stickiness, post-charge grace, under-attack override. Root cause analyzed, 4-layer fix proposed. |
| 37 | Objective-aware ability activation | Protect interacting allies. Shield/Escort profiles, distance-dependent response, ~8 heuristic threshold adjustments. Phased (P1 thresholds → P2 dash-toward → P3 per-type). |

### v0.10.0 — "Team Coordination"

*Theme: bots coordinate with each other and fight smarter per-weapon.*

| # | Issue | Notes |
|---|-------|-------|
| 14 | Ability cooldown staggering | Post-activation category cooldown (~100-150 LOC). Emergency overrides for critical abilities. Feasibility analysis complete. |
| 7 | Revive-with-ability | Inject defensive ability (taunt/stealth/shout) before revive interact node. Requires BT injection research. |
| 13 | Navmesh validation for charges | GwNav raycast before committing charge direction. VT2 reference values available. Darktide uses navigation destination vector, not `aim_position`. |
| 41 | Weapon-aware ADS vs hip-fire | Dynamic `ranged_gestalt` per weapon family. Per-weapon aim data alongside `attack_meta_data`. |
| 58 | ScriptUnit.extension guard | 2-line `has_extension` guard on 2 hot paths. Defensive fix. |

### v1.0.0 — "Bot Identity"

*Theme: bots feel like teammates, not automatons. VT2 Bot Improvements parity.*

| # | Issue | Notes |
|---|-------|-------|
| 38 | Talent-aware behavior | Zealot Martyrdom PoC: suppress healing, adjust heuristic thresholds. Framework for future keystones (Scrier's Gaze peril, Carapace Armor stacks). Detection via `talent_extension:talents()`. |
| 44 | Human-likeness tuning (Tier A) | Activation jitter (0.3-1.5s), opportunity target reaction times (2-5s vs vanilla 10-20s), unlock difficulty-aware engage range (dead code fix). High impact, low effort. |
| 24 | Healing item management | Medicae discipline, healing item distribution, stim usage. Three independent subsystems. |
| 32 | Mule item pickup | Set `bots_mule_pickup = true` + fix `slot_name` vs `inventory_slot_name` mismatch. Settings toggle for grimoire carrying. |
| 33 | Weapon special actions | Parry, heavy sweep, racking slide. Input mechanism trivial; decision logic (when to parry) is the work. |

### Post-1.0 — "Intelligence Architecture"

| # | Issue | Notes |
|---|-------|-------|
| 22 | Utility-based ability scoring | Replace boolean heuristics with spline-interpolated utility curves. Darktide has native `utility.lua` + `bot_utility_considerations.lua` — framework exists, needs wiring. Architectural upgrade. |
| 28 | Built-in bot profile management | Absorb Tertium4Or5 functionality. Profile selection + loadout preset support. Only pursue if upstream remains unpatched. |
| 56 | Communication wheel response | React to com wheel commands (battle cry → aggression boost, need help → converge). `Vo.on_demand_vo_event` hook for detection. ForTheEmperor compat. |

### Validation-gated — slot into any batch when testable

| # | Issue | Blocker |
|---|-------|---------|
| 8 | Hive Scum ability support | DLC-blocked (Hive Scum / `broker` archetype not owned) |
| 17 | Daemonhost avoidance | Code + tests shipped v0.6.0. Needs in-game daemonhost encounter to verify. |
| 39 | Healing deferral | Implemented v0.7.0. Needs in-game trigger to validate deferral path. |
| 49 | Arbites companion-command smart tag | Direct mastiff via `enemy_companion_target` tag. Arbites DLC available. |

## Design principles

1. **Don't break what works.** Vanilla bot combat (melee, shoot, revive, rescue, follow) must remain functional. Every change is additive.
2. **Per-ability, not per-class.** Trigger heuristics are per ability template, not per archetype. A Zealot with Dash needs different rules than a Zealot with Stealth.
3. **Precise triggers, eager usage.** Bots should use abilities frequently but only when the trigger conditions genuinely apply. Community consensus (VT2 and Darktide) strongly favors maximizing ability uptime — conservation frustrates players more than occasional misfires. Heuristics should be confident, not rare.
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

## Milestone history

1. **M1 (v0.1.0):** Tier 1 + Tier 2 abilities activate in solo play. Published on Nexus.
2. **M2 (v0.2.0–v0.3.0):** Per-career threat heuristics + Tier 3 reliability + structured event logging.
3. **M3 (v0.4.0):** Ability quality + bot fixes — suppression, charge rescue, Psyker overcharge, revive protection, poxburster targeting, ADS fix, bot sprinting.
4. **M4 (v0.5.0):** Ability polish + weapon fixes — VFX/SFX bleed, melee/ranged meta_data, warp venting, staff charged fire (partial).
5. **M5 (v0.6.0):** Scope expansion — grenade/blitz, staff charged fire complete, bot pinging, daemonhost avoidance, distant special penalty.
6. **M5-batch2 (v0.7.0):** Grenade heuristics + Psyker blitz, ping anti-spam, hazard-aware abilities, boss engagement, healing deferral, player-tag response.
7. **v0.7.1:** P0/P1 stabilization — animation crash guard, ammo threshold, melee horde bias, Assail void throws, grenade misaim. 461 tests.
