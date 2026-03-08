# Status Snapshot (March 8, 2026)

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes
- Tier 3 item-based abilities: zealot relic, force field, drone (initial implementation, later fixed to 100% in v0.3.0)
- Generic trigger: `enemies_in_proximity() > 0`
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Published on Nexus Mods

### Post-v0.1.0 (unreleased)
- **Refactored** into sub-modules: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26)
- **Per-career threat heuristics** (#2): 18 per-template heuristic functions (14 combat + 4 item) replacing generic `enemies_in_proximity() > 0`
  - Veteran: VoC (squad_leader) + Executioner's Stance (ranger) branching via `class_tag` + Stealth
  - Zealot: Dash (distance/super_armor/priority gates) + Invisibility (emergency/overwhelm/ally)
  - Psyker: Shout (peril-gated) + Stance (peril window + threat)
  - Ogryn: Charge (gap-close/ally rescue) + Taunt (survivability-gated) + Gunlugger (ranged focus)
  - Arbites: Stance (toughness/monster) + Charge (density/elite) + Shout (emergency)
  - Hive Scum: Focus + Rage (toughness-reactive)
- **Rich context**: `build_context()` reads health, toughness, peril, challenge_rating_sum, breed tags, ally state, super armor
- **Structured event logging** (#29): opt-in JSONL event log (`event_log.lua`) with decision/queued/consumed/snapshot events, `attempt_id` correlation, buffered flush, hot-reload recovery
- **Unit tests**: 160 tests via busted (heuristics, meta_data, resolve_decision, event_log, sprint)
- **Debug commands**: `/bb_state`, `/bb_decide`, `/bb_brain`
- **Log analysis**: `bb-log events` subcommands for JSONL analysis (summary, rules, trace, holds, items, raw)
- **Safety guards**: revive/interaction protection (#20), ability suppression during dodging/falling/lunging/jumping/ladder (#11), warp weapon peril block at ≥97% preventing Scrier's Gaze explosions (#27)
- **Poxburster targeting** (#34): removed `not_bot_target` breed flag, added close-range (<5m) suppression
- **ADS fix for T5/T6 bots** (#35): inject default `bot_gestalts` (`killshot`/`linesman`) when profile omits them
- **Bot sprinting** (#36): sprint module with catch-up (>12m), rescue, traversal conditions + daemonhost safety

## Current Tier Status

| Tier | Status | Notes |
|------|--------|-------|
| 1 | PASS (5/5 testable) | Broker variants DLC-blocked |
| 2 | PASS (6/6 testable) | `adamant_shout` N/A (cut content) |
| 3 | PASS (3/3 testable) | `zealot_relic`, `force_field`, `drone` all 100%. `broker_stimm_field` DLC-blocked. |

## Evidence Source

- Latest analyzed log: `console-2026-03-05-14.57.34-...`
- Full evidence matrix: `docs/VALIDATION_TRACKER.md`
- Log timestamps are UTC, not local timezone

## Known Blockers

1. **Hive Scum / Broker DLC**: Focus, Rage, and Stimm Field abilities are DLC-blocked for validation.

## Next Steps
- Charge/dash to rescue disabled ally (#10) — P1, closes M3
- Per-ability toggle settings (#6) — P2
- Player weapon ranged metadata (#31) — P2, medium effort
- Investigate grenade/blitz approach (#4) — P2
- Hive Scum ability validation (#8) — requires DLC
- Bot warp venting (#30) — P2
- Objective-aware ability activation (#37) — P2
