# Handoff

## Current Task
M5 development: #4 grenade Phase 1 complete, merged to `dev/m5-batch1`. Ready for next M5 feature or in-game testing.

## Agent
Claude Opus 4.6

## Branch
`dev/m5-batch1` at `e86078f` (includes `feat/4-grenade-fallback` merge)

## What shipped since last handoff
- v0.5.0 released: #42 VFX/SFX bleed, #23 melee meta_data, #31 ranged meta_data, #30 warp venting, #43 partial staff charged fire
- Major refactor: extracted 5 modules from BetterBots.lua (1455 -> 625 LOC)
- Design doc for #45 (default bot profiles)

## Current state
- `main` is clean at `fea78b4`
- `dev/m5-batch1` has #4 Phase 1 (grenade fallback) — 244 passing tests, `make check` green
- `feat/4-grenade-fallback` merged into `dev/m5-batch1` (fast-forward)

## #4 grenade support — Phase 1 done
- New module: `grenade_fallback.lua` (211 LOC) — 5-stage state machine (idle→wield→wait_aim→wait_throw→wait_unwield→idle)
- 12 standard/handleless grenade templates supported via weapon_action parser
- `evaluate_grenade_heuristic` in heuristics.lua — generic enemies>0 fallback
- Integrated into BetterBots.lua: update tick, charge tracking hook, session cleanup
- 14 new tests (3 heuristic + 11 state machine)

### Deferred from #4
- `adamant_whistle` (Remote Detonation) — needs BT ability path + `ability_meta_data` injection
- Psyker blitz (`psyker_smite`, `psyker_chain_lightning`, `psyker_throwing_knives`) — bespoke action hierarchies
- `zealot_throwing_knives` — different input pattern (single-press)
- `shock_mine` — place mechanic

## M5 scope (remaining)
- **#16-#19**: General bot behavior (pinging, daemonhost, boss discipline, special chasing)
- **#39**: Heal deferral
- **#4 Phase 2+**: Remaining blitz templates (see deferred list above)

## Key Files
- `scripts/mods/BetterBots/grenade_fallback.lua` — grenade throw state machine
- `scripts/mods/BetterBots/heuristics.lua` — per-template heuristic functions (incl. grenade)
- `docs/superpowers/specs/2026-03-10-grenade-fallback-design.md` — design spec
- `docs/superpowers/plans/2026-03-10-grenade-fallback.md` — implementation plan

## Next steps
1. In-game testing of grenade fallback on `dev/m5-batch1`
2. Pick next M5 feature (e.g., #16 bot pinging, #17 daemonhost avoidance)
3. Merge `dev/m5-batch1` to `main` after in-game validation

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 – 2026-03-09 | GPT-5 + Claude Opus 4.6 | v0.1.0 – v0.5.0 shipped (see `docs/dev/roadmap.md` for details) |
| 2026-03-10 | Claude Opus 4.6 | M5 started: #4 Phase 1 grenade fallback implemented (design → plan → TDD → integration → merge to batch) |
