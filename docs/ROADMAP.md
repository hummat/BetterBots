# Roadmap

## Vision

Make Darktide bots as capable as VT2's modded bots (Grimalackt's Bot Improvements - Combat). Start with ability activation (already shipped), then add smart trigger heuristics, safety guards, and general behavior improvements.

## What's shipped (v0.1.0)

- Tier 1 + Tier 2 ability activation for all 6 classes (whitelist removal + meta_data injection)
- Tier 3 item-based abilities: zealot relic (stable), force field (~13%), drone (~21%)
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Generic trigger: `enemies_in_proximity() > 0`

## Priority tiers

Issues are tracked on [GitHub](https://github.com/hummat/BetterBots/issues) with labels `P1: next`, `P2: later`, `P3: backlog`.

### P1: Next — High value, unblocked

| # | Issue | Category | Status |
|---|-------|----------|--------|
| 2 | Per-career threat heuristics | ability-quality | **DONE** — 13 per-template functions, 80 tests. Needs in-game validation. Ready to implement — all tactics docs + perception APIs documented. |
| 3 | Tier 3 item-ability reliability | tier: 3 | Root cause identified — timing mismatch between `ITEM_SEQUENCE_PROFILES` and engine action durations. Fix values known (see `docs/KNOWN_ISSUES.md`). |
| 10 | Charge/dash to rescue disabled ally | ability-quality | Bull Rush / Break the Line / Dash to reach grabbed/netted allies. |
| 11 | Ability suppression / impulse control | ability-quality | Unblocked — character state APIs found (`movement_state`, `lunge_character_state`, etc.). Don't charge off ledges, don't ability during nav transitions, don't stance when retreating. |

### P2: Later — Planned, not urgent

**Ability activation quality:**

| # | Issue | Notes |
|---|-------|-------|
| 12 | Stance early cancellation | Researched — complex. Stances have no release input (`transition = "stay"`). Needs template injection or `stop_action()` + buff cleanup. |
| 13 | Navmesh validation for charges | GwNav raycast before committing charge direction. |
| 15 | Suppress dodge during ability hold | Unblocked — `movement_state.is_dodging` + `Dodge.is_dodging()` available. Prevent dodge from interrupting charge/hold phases. |
| 21 | Hazard avoidance during abilities | Don't stance in fire/gas/bomber puddles. |

**Ability scope expansion:**

| # | Issue | Notes |
|---|-------|-------|
| 4 | Blitz / grenade support | Inventory extracted — all 18 templates mapped, all need item-based fallback, no `ability_template` on any. `adamant_whistle` only blitz with `ability_template`. |
| 6 | Per-ability toggle settings | DMF widget per ability for enable/disable. |
| 8 | Hive Scum ability support | Tier 1 (Focus/Rampage) likely works already — needs validation run. Stimm Field (Tier 3) DLC-blocked for testing. |

**General bot behavior:**

| # | Issue | Notes |
|---|-------|-------|
| 16 | Bot pinging of elites/specials | Tag high-threat enemies (LOS + 2s cooldown). VT2 mod's #2 feature. |
| 17 | Daemonhost avoidance | Suppress all actions near Daemonhosts. #1 solo play rage-quit scenario. |
| 18 | Boss engagement discipline | Don't focus boss when adds are up. |
| 19 | Stop chasing distant specials | Don't walk >18m to melee a special. Still shoot at any range. |
| 20 | Don't interrupt own revive | Ready — fix is ~5 LOC: check `current_interaction_unit ~= nil` in ability condition. |

### P3: Backlog — Nice to have, no timeline

| # | Issue | Notes |
|---|-------|-------|
| 7 | Revive-with-ability | Inject ability BT node before revive (stealth/taunt/shout to protect revive). |
| 14 | Ability cooldown staggering | Team-level coordination: don't stack all abilities simultaneously. |
| 22 | Utility-based ability scoring | Replace boolean conditions with spline-interpolated utility curves (90+ considerations in VT2). Architectural upgrade. |
| 23 | Smart melee attack selection | Armor-aware attack choice (+utility for penetrating vs carapace). |
| 24 | Healing item management | Don't waste medicae, distribute healing to wounded allies, stim usage. |

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
- **Per-class tactics docs** (`docs/CLASS_*_TACTICS.md`) — community-sourced USE WHEN / DON'T USE / proposed bot rules

See `docs/RELATED_MODS.md` for detailed mod analysis and `docs/CLASS_*_TACTICS.md` for per-ability heuristics.

## Milestones

1. **M1 (shipped):** Tier 1 + Tier 2 abilities activate in solo play. v0.1.0 on Nexus.
2. **M2:** Per-career threat heuristics (#2) + ability suppression (#11). Bots use abilities intelligently instead of spamming.
3. **M3:** Tier 3 reliability improved (#3) + grenade spike (#4). Full ability coverage.
4. **M4:** General bot behavior improvements (#16-#20). Beyond abilities.
5. **M5 (aspirational):** Utility-based scoring (#22). VT2-level bot intelligence.
