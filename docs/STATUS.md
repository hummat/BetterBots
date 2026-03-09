# Status Snapshot (March 8, 2026)

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
- **Poxburster targeting** (#34): removed `not_bot_target` breed flag, close-range (<5m) suppression
- **ADS fix for T5/T6 bots** (#35): inject default `bot_gestalts` (`killshot`/`linesman`) when profile omits them
- **Bot sprinting** (#36): sprint module with catch-up (>12m), rescue, traversal conditions + daemonhost safety
- **Charge/dash rescue aim** (#10): zealot dash, ogryn charge, and arbites charge aim toward disabled allies. 14 rescue activations confirmed in-game.
- **Unit tests**: 194 tests via busted (heuristics, meta_data, resolve_decision, event_log, sprint, melee_meta_data)
- **Debug commands**: `/bb_state`, `/bb_decide`, `/bb_brain`

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
- Per-ability toggle settings (#6) — P2
- Player weapon ranged metadata (#31) — P2, medium effort
- Weapon/enemy-aware ADS (#41) — P2
- Investigate grenade/blitz approach (#4) — P2
- Hive Scum ability validation (#8) — requires DLC
- Bot warp venting (#30) — P2
- Objective-aware ability activation (#37) — P2
