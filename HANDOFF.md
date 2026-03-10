# Handoff

## Current Task
M5 development: #4 grenade Phase 1 complete + review fixes applied, merged to `dev/m5-batch1`. Ready for in-game testing or next M5 feature.

## Agent
Claude Opus 4.6 (Claude Code)

## Branch
`dev/m5-batch1` (includes `feat/4-grenade-fallback` merge + review fix merge)

## What shipped since last handoff
- v0.5.0 released: #42 VFX/SFX bleed, #23 melee meta_data, #31 ranged meta_data, #30 warp venting, #43 partial staff charged fire
- Major refactor: extracted 5 modules from BetterBots.lua (1455 -> 625 LOC)
- Design doc for #45 (default bot profiles)

## Current state
- `main` is clean at `fea78b4`
- `dev/m5-batch1` has #4 Phase 1 (grenade fallback) — 248 passing tests, `make check` green
- `feat/4-grenade-fallback` merged into `dev/m5-batch1`

## Decisions Made
- 2026-03-10: Grenade fallback uses weapon_action parser (not BT ability path) because `slot_grenade_ability` has no `wield_inputs`
- 2026-03-10: New module `grenade_fallback.lua` rather than extending `item_fallback.lua` — zero regression risk
- 2026-03-10: Generic heuristic (`num_nearby > 0`) for Phase 1 — per-grenade tuning deferred
- 2026-03-10: `adamant_whistle` confirmed as live content (Remote Detonation for Arbites Cyber-Mastiff), not cut — deferred to separate work item
- 2026-03-10: EventLog integration deferred to follow-up — TODO comments in place
- 2026-03-10: No mutual exclusion between grenade and combat ability state machines — documented gap, cooldown+heuristic gates make collision rare

## Changes
- `scripts/mods/BetterBots/grenade_fallback.lua` — new 5-stage state machine (idle→wield→wait_aim→wait_throw→wait_unwield→idle), ~240 LOC
- `scripts/mods/BetterBots/heuristics.lua` — added `GRENADE_HEURISTICS` table + `evaluate_grenade_heuristic` export
- `scripts/mods/BetterBots/BetterBots.lua` — load/init/wire GrenadeFallback, update tick call, grenade charge tracking in `use_ability_charge` hook, session cleanup, `_is_suppressed` wired
- `tests/grenade_fallback_spec.lua` — 15 tests (state transitions, timeouts, lost-wield, suppression, interaction)
- `tests/heuristics_spec.lua` — 3 tests for `evaluate_grenade_heuristic`
- `AGENTS.md` — test counts updated (248 total, 15 grenade_fallback, 125 heuristics), file listing updated
- `docs/dev/roadmap.md` — #4 status updated to "Phase 1 done"
- `docs/superpowers/specs/2026-03-10-grenade-fallback-design.md` — design spec (new)
- `docs/superpowers/plans/2026-03-10-grenade-fallback.md` — implementation plan (new)

## #4 grenade support — Phase 1 done
- 12 standard/handleless grenade templates supported via uniform aim_hold/aim_released throw pattern
- Suppression + interaction guards matching ability_queue.lua
- Unknown-stage catch-all, nil-path debug logging, timing constant documentation
- 18 new tests total (3 heuristic + 15 state machine)

### Deferred from #4
- `adamant_whistle` (Remote Detonation) — needs BT ability path + `ability_meta_data` injection
- Psyker blitz (`psyker_smite`, `psyker_chain_lightning`, `psyker_throwing_knives`) — bespoke action hierarchies
- `zealot_throwing_knives` — different input pattern (single-press)
- `shock_mine` — place mechanic
- EventLog integration (TODO comments in place on `_event_log`, `_bot_slot_for_unit`)
- Mutual exclusion with AbilityQueue (NOTE comment documenting gap)
- Per-grenade heuristic tuning (generic `num_nearby > 0` may be too aggressive for charge-limited resource)

## Open Questions
- Generic heuristic (`num_nearby > 0`) may waste grenades on single trash mobs — should threshold be higher (e.g., `>= 3`) or use `challenge_rating_sum`?
- `record_charge_event` stores data but nothing reads it yet — add charge confirmation check or remove dead infrastructure?
- Does the 2s `RETRY_COOLDOWN_S` need to differ between success and failure paths?

## M5 scope (remaining)
- **#16-#19**: General bot behavior (pinging, daemonhost, boss discipline, special chasing)
- **#39**: Heal deferral
- **#4 Phase 2+**: Remaining blitz templates (see deferred list above)

## Key Files
- `scripts/mods/BetterBots/grenade_fallback.lua` — grenade throw state machine
- `scripts/mods/BetterBots/heuristics.lua` — per-template heuristic functions (incl. grenade)
- `scripts/mods/BetterBots/item_fallback.lua` — reference pattern for state machine modules
- `docs/superpowers/specs/2026-03-10-grenade-fallback-design.md` — design spec
- `docs/superpowers/plans/2026-03-10-grenade-fallback.md` — implementation plan

## Next Steps
1. In-game testing of grenade fallback on `dev/m5-batch1`
2. Tune grenade heuristic threshold if bots waste grenades on trash
3. Pick next M5 feature (e.g., #16 bot pinging, #17 daemonhost avoidance)
4. Merge `dev/m5-batch1` to `main` after in-game validation

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 – 2026-03-09 | GPT-5 + Claude Opus 4.6 | v0.1.0 – v0.5.0 shipped (see `docs/dev/roadmap.md` for details) |
| 2026-03-10 | Claude Opus 4.6 (Claude Code) | M5 started: #4 Phase 1 grenade fallback — design, plan, TDD implementation (6 tasks), 4-agent PR review, review fixes (suppression/interaction guards, error handling, +4 tests). 248 tests green. |
