# Perf Micro-Opt Design

Date: 2026-04-12
Issue: #82
Branch target: `dev/v0.11.0`

## Problem

`#82` is still open, but most large low-risk wins from the original perf audit already landed:

- cooldown-ready fast path in `ability_queue.lua`
- shared `_is_suppressed` cache
- shared daemonhost scan in `sprint.lua`
- shared human ammo scan in `ammo_policy.lua`
- shared ally-interaction scan in `heuristics.lua`

Current issue state is no longer "broad low-hanging audit." It is a narrow cleanup pass on remaining cheap hot-path waste that does not change behavior and does not reopen medium-risk ideas like context-table reuse.

## Goal

Ship one final low-risk micro-optimization slice for `v0.11.0`:

- remove repeated one-shot work in `ability_queue.lua`
- reduce repeated per-target lookups in `target_selection.lua`
- optionally remove one tiny idle-path read in `grenade_fallback.lua` if it stays trivial

Target is lower steady-state cost, not a guaranteed new measured headline. No new in-game perf claim will be made without fresh `/bb_perf` data.

## Non-goals

- no `build_context()` table reuse
- no heuristic redesign
- no broad cross-bot cache additions
- no behavior tuning disguised as perf work
- no new perf API or `/bb_perf` output changes
- no "optimize everything" sweep across `item_fallback.lua` / `weapon_action.lua`

## Source context

Verified from current branch state:

1. `ability_queue.lua` still does `require("...ability_templates")` + `_MetaData.inject(AbilityTemplates)` inside `_fallback_try_queue_combat_ability()` on the per-tick path.
2. `target_selection.lua` already caches `special_chase_penalty_range^2` per frame, but still recomputes:
   - smart-tag lookup for the same `target_unit`
   - companion-pin lookup for the same `target_unit`
   - `Ammo.current_slot_percentage(unit, "slot_secondary")` for repeated distant-special checks in the same frame
3. `grenade_fallback.lua` still reads `inventory` before it knows whether it even needs slot state, but only a tiny cleanup is justified here.

## Chosen approach

Make a strict micro-opt pass in three places.

### 1. `ability_queue.lua`

Hoist `AbilityTemplates` load + `_MetaData.inject()` behind a one-shot cached accessor.

Rationale:

- `AbilityTemplates` is a singleton
- metadata injection is idempotent
- doing both inside the per-tick fallback path is unnecessary churn

Required behavior rule:

- zero semantic change to fallback ability resolution
- same missing-template / missing-meta behavior as before

### 2. `target_selection.lua`

Add per-frame caches keyed by current `fixed_t` for:

- human smart tag result by `target_unit`
- friendly companion pin result by `target_unit`
- slot ammo percentage by `unit`

Rationale:

- `slot_weight()` is hot and called per target, not per bot
- same target can be visited multiple times in one frame
- same bot ammo percentage is stable inside one frame for this call path

Required behavior rule:

- cached values must expire when `fixed_t` changes
- no stale cross-frame targeting state

### 3. `grenade_fallback.lua` (optional, tiny only)

If clean, defer `inventory` read until after the "unit data missing" and `next_try_t` gates, and only keep reads needed for current state branch.

If this needs structural churn, drop it from the patch.

## Module changes

### `scripts/mods/BetterBots/ability_queue.lua`

Add:

- a small file-local cached accessor for `AbilityTemplates`
- one-shot `_MetaData.inject()` guard

Do not:

- move unrelated fallback logic
- touch heuristic dispatch behavior

### `scripts/mods/BetterBots/target_selection.lua`

Add file-local per-frame caches and reset them in `init()`:

- `_cached_tag_results`
- `_cached_companion_pin_results`
- `_cached_slot_ammo_pct`

Caching rules:

- cache is valid only for current `fixed_t`
- refresh whole cache when `fixed_t` changes
- nil result must still cache as false / nil-equivalent so misses do not recompute every call

### `scripts/mods/BetterBots/grenade_fallback.lua`

Only touch if final diff stays obviously smaller and lower-risk than leaving it alone.

## Logging

No new logs required.

Perf work must not add new debug churn to hot paths.

## Testing

Required coverage:

1. `ability_queue_spec.lua`
   - repeated `try_queue()` calls hit `_MetaData.inject()` once, not per tick
   - fallback behavior still works after caching
2. `target_selection_spec.lua`
   - human-tag lookup is reused within same `fixed_t`
   - companion-pin lookup is reused within same `fixed_t`
   - slot ammo percentage is reused within same `fixed_t`
   - caches refresh when `fixed_t` advances
3. `grenade_fallback_spec.lua`
   - only if grenade file changes

No new standalone perf spec file needed.

## Acceptance criteria

- `ability_queue.lua` no longer requires/injects ability templates on every tick
- `target_selection.lua` reuses per-frame tag/pin/ammo results without changing scores
- `make test`, `make doc-check`, and `make check` pass
- no new documented perf claim is added without fresh in-game measurement

## Risks

- per-frame caches keyed incorrectly could leak stale results across frames; tests must explicitly advance `fixed_t`
- caching nil / false results incorrectly could cause repeated recomputation or wrong score changes
- broadening this patch beyond the three sites above would turn `#82` back into open-ended audit work; reject that scope creep

## Files expected to change

- `scripts/mods/BetterBots/ability_queue.lua`
- `scripts/mods/BetterBots/target_selection.lua`
- maybe `scripts/mods/BetterBots/grenade_fallback.lua`
- `tests/ability_queue_spec.lua`
- `tests/target_selection_spec.lua`
- maybe `tests/grenade_fallback_spec.lua`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- maybe `docs/dev/architecture.md` if perf notes change

