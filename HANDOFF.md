# Handoff

## Current Task
M5 batch testing: #4 + #17 merged to `dev/m5-batch1`. Next: implement #19, then in-game test the full batch.

## Agent
Claude Opus 4.6 (Claude Code)

## Branch
`dev/m5-batch1` — integration branch for M5 batch 1

## Current state
- `main` is clean at `fea78b4`
- `dev/m5-batch1` has #4 + #17 merged — 266 passing tests, `make check` green
- `feat/4-grenade-fallback` — merged, can be deleted
- `feat/17-daemonhost-avoidance` — merged, can be deleted

## Features on dev/m5-batch1

### #4 grenade support — Phase 1 done
- 12 standard/handleless grenade templates supported via aim_hold/aim_released throw pattern
- New module `grenade_fallback.lua` — 5-stage state machine (idle→wield→wait_aim→wait_throw→wait_unwield)
- Generic heuristic (`num_nearby > 0`) — per-grenade tuning deferred
- Suppression + interaction guards, debug logging for all state transitions
- Template allowlist blocks unsupported blitz templates (knives, mine, whistle, smite, etc.)
- 19 new tests (3 heuristic + 16 state machine)

#### Deferred from #4
- `adamant_whistle` (Remote Detonation) — needs BT ability path + `ability_meta_data` injection
- Psyker blitz (`psyker_smite`, `psyker_chain_lightning`, `psyker_throwing_knives`) — bespoke action hierarchies
- `zealot_throwing_knives` — different input pattern (single-press)
- `shock_mine` — place mechanic
- EventLog integration (TODO comments in place)
- Per-grenade heuristic tuning

### #17 daemonhost avoidance — done
- Three-layer suppression near non-aggroed daemonhosts:
  - **Sprint** (20m proximity): `_is_near_daemonhost(unit)` blocks sprinting
  - **Abilities** (20m proximity): `_is_suppressed` returns `"daemonhost_nearby"`
  - **Melee/ranged combat** (target-specific): `_is_dormant_daemonhost_target` only blocks when `target_enemy` IS a dormant DH
- Per-frame caching: `_nearest_dh_dist_sq(unit)` scans once per unit per frame
- Aggro detection: skips aggroed DH via `BLACKBOARDS[enemy_unit].perception.aggro_state`
- Supports both `chaos_daemonhost` and `chaos_mutator_daemonhost`
- 35 new tests (23 sprint + 12 condition_patch)

## Decisions Made
- 2026-03-10: Grenade fallback uses weapon_action parser (not BT ability path) because `slot_grenade_ability` has no `wield_inputs`
- 2026-03-10: New module `grenade_fallback.lua` rather than extending `item_fallback.lua` — zero regression risk
- 2026-03-10: `adamant_whistle` confirmed as live content (Remote Detonation for Arbites Cyber-Mastiff) — deferred
- 2026-03-10: DH combat suppression is target-specific (not proximity-based) so bots fight hordes near sleeping DH
- 2026-03-10: Sprint/ability suppression remains proximity-based (20m) — these are ambient behaviors that could provoke any nearby DH
- 2026-03-10: Conservative DH aggro default — if no blackboard/perception data, treat as non-aggroed

## Open Questions
- Generic grenade heuristic (`num_nearby > 0`) may waste grenades on single trash mobs
- `record_charge_event` stores grenade charge data but nothing reads it yet
- Does `RETRY_COOLDOWN_S` (2s) need to differ between grenade success and failure paths?

## M5 scope (remaining)
- **#19**: Stop chasing distant specials for melee — next to implement
- **#16**: Bot pinging
- **#18**: Boss discipline
- **#39**: Heal deferral
- **#4 Phase 2+**: Remaining blitz templates

## Next Steps
1. Implement #19 on `feat/19-stop-chasing-specials` from `main`
2. Merge #19 into `dev/m5-batch1`
3. In-game test full batch (#4 + #17 + #19)
4. Merge `dev/m5-batch1` to `main` after validation

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 – 2026-03-09 | GPT-5 + Claude Opus 4.6 | v0.1.0 – v0.5.0 shipped (see `docs/dev/roadmap.md` for details) |
| 2026-03-10 | Claude Opus 4.6 (Claude Code) | M5 started: #4 Phase 1 grenade fallback — design, plan, TDD implementation, 4-agent PR review, review fixes. |
| 2026-03-10 | Claude Opus 4.6 (Claude Code) | #17 daemonhost avoidance — 3-layer suppression (sprint/ability/combat), per-frame caching, aggro detection, target-specific combat guards. Two external reviews (ChatGPT) caught proximity-vs-target bug and missing caching — both fixed. 266 tests green. |
