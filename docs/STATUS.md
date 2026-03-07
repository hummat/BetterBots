# Status Snapshot (March 6, 2026)

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes
- Tier 3 item-based abilities: zealot relic (stable), force field (~13%), drone (~21%)
- Generic trigger: `enemies_in_proximity() > 0`
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Published on Nexus Mods

### Post-v0.1.0 (unreleased)
- **Refactored** into sub-modules: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26)
- **Per-career threat heuristics** (#2): 13 per-template heuristic functions replacing generic `enemies_in_proximity() > 0`
  - Veteran: VoC (squad_leader) + Executioner's Stance (ranger) branching via `class_tag` + Stealth
  - Zealot: Dash (distance/super_armor/priority gates) + Invisibility (emergency/overwhelm/ally)
  - Psyker: Shout (peril-gated) + Stance (peril window + threat)
  - Ogryn: Charge (gap-close/ally rescue) + Taunt (survivability-gated) + Gunlugger (ranged focus)
  - Arbites: Stance (toughness/monster) + Charge (density/elite) + Shout (emergency)
  - Hive Scum: Focus + Rage (toughness-reactive)
- **Rich context**: `build_context()` reads health, toughness, peril, challenge_rating_sum, breed tags, ally state, super armor
- **Structured event logging** (#28): opt-in JSONL event log (`event_log.lua`) with decision/queued/consumed/snapshot events, `attempt_id` correlation, buffered flush, hot-reload recovery
- **Unit tests**: 142 tests via busted (heuristics, meta_data, resolve_decision, event_log)
- **Debug commands**: `/bb_state`, `/bb_decide`, `/bb_brain`
- **Log analysis**: `bb-log events` subcommands for JSONL analysis (summary, rules, trace, holds, items, raw)

## Current Tier Status

| Tier | Status | Notes |
|------|--------|-------|
| 1 | PASS (5/5 testable) | Broker variants DLC-blocked |
| 2 | PASS (6/6 testable) | `adamant_shout` N/A (cut content) |
| 3 | PARTIAL | `zealot_relic` PASS, `force_field` ~13%, `drone` ~21% |

## Evidence Source

- Latest analyzed log: `console-2026-03-05-14.57.34-...`
- Full evidence matrix: `docs/VALIDATION_TRACKER.md`
- Log timestamps are UTC, not local timezone

## Known Blockers

1. **Tier 3 reliability** (#3): Force field and drone consume ratios remain low
2. **Heuristic validation**: Per-career heuristics implemented but not yet validated in-game — thresholds may need tuning

## Next Steps
- Close issue #2 on GitHub
- Validate heuristic thresholds in-game (all classes)
- Ability suppression / impulse control (#11)
- Stabilize Tier 3 item sequences (#3)
- Per-ability toggle settings (#6)
- Investigate grenade/blitz approach (#4)
