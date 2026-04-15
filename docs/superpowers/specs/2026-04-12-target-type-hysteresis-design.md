# Target Type Hysteresis Design

Date: 2026-04-12
Issue: #90

## Problem

Vanilla `bot_target_selection_template.bot_default` decides `perception.target_enemy_type` with a hard greater-than comparison between `best_melee_score` and `best_ranged_score` on full reevaluation, and again between `melee_score` and `ranged_score` when only rescoring the current target.

That creates three problems:

1. no margin requirement
2. no momentum bias toward the currently active type
3. reevaluation every `0.3s`, so tiny score swings become rapid type flips

Because `target_enemy_type` directly drives BT branch selection and inventory switching, close-score cases produce visible `switch_melee` / `switch_ranged` thrash and lost uptime.

## Decision

Implement `#90` as a **perception-layer type stabilizer only**:

- add hysteresis at the exact target-type comparison site
- apply it on both full reevaluation and current-target-only rescoring
- do not add BT-layer switch cooldowns
- do not freeze target unit selection across reevaluations

## Why Not BT Debounce

BT debounce is a downstream band-aid. It can hide genuine scenario changes and creates a second state machine that disagrees with the blackboard.

The real bug is that `target_enemy_type` itself flips too easily. Fixing it there is cleaner and lower risk.

## Architecture

Add a new `target_type_hysteresis.lua` module.

Responsibilities:

- hold hysteresis constants
- decide stabilized type from melee/ranged scores and current type
- expose a small pure function for unit tests
- install the hook on `bot_target_selection_template.bot_default`

This stays separate from `target_selection.lua` because that module adjusts score primitives on `BotTargetSelection`, while `#90` is about the **final type comparison** in the target-selection template.

## Stabilization Rule

Inputs:

- `current_type`
- `melee_score`
- `ranged_score`

Constants:

- margin factor: `0.10`
- momentum bonus: `0.05`

Algorithm:

1. compute raw winner from unmodified scores
2. if there is no current type (`nil` / `"none"`), accept raw winner
3. otherwise apply momentum bonus to the current type score
4. compute `margin = 0.10 * max(abs(melee_score), abs(ranged_score), 1)`
5. only flip to the other type if its stabilized score exceeds the current type score by more than `margin`
6. otherwise keep current type

This gives small score leads no power to flip the classification, while still allowing clear winner changes to go through immediately.

## Full Reevaluation vs Current-Target Rescore

Apply the same hysteresis policy in both paths:

- full reevaluation (`best_melee_score` vs `best_ranged_score`)
- current-target-only rescore (`melee_score` vs `ranged_score`)

That keeps the policy coherent. There should not be one stability rule when picking a fresh target and another when updating the same one.

## Important Scope Limit

Hysteresis stabilizes **type only**, not target unit.

On full reevaluation:

- if stabilized type is `"melee"`, use `best_melee_target`
- if stabilized type is `"ranged"`, use `best_ranged_target`

We explicitly do **not** freeze the previously chosen target unit if the preferred type remains the same. That is a separate behavior question and carries more stale-target risk than this issue needs.

## Hook Strategy

Use `mod:hook_require("scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template", ...)`.

Inside the hook:

- wrap `target_selection_template.bot_default`
- let vanilla compute scores/targets as usual
- replace only the two type-comparison decisions with the hysteresis helper
- preserve all other target-selection logic untouched

No changes to:

- `BotTargetSelection` primitive score functions
- BT condition logic
- inventory switch action logic

## Logging

Add debug logs only when the stabilized type actually flips.

Log payload should include:

- old type
- new type
- melee score
- ranged score
- margin

Key format must include `tostring(unit)` so multi-bot flips are not throttled into one log line.

No per-frame “held current type” spam.

## Scope

### In scope

- new hysteresis module
- perception-template hook
- pure hysteresis chooser
- debug log on actual flips
- unit tests for the chooser

### Out of scope

- BT debounce / inventory switch cooldown
- target unit freezing
- score primitive changes
- weapon-family ADS tuning
- full utility scoring rewrite

## Tests

Create `tests/target_type_hysteresis_spec.lua` covering:

1. no current type → raw winner used
2. close scores keep current melee type
3. close scores keep current ranged type
4. clear melee lead flips from ranged to melee
5. clear ranged lead flips from melee to ranged
6. momentum bonus preserves current type on near tie
7. margin scales with larger scores rather than using a flat threshold

This module should be testable as a pure function without engine stubs.

## Docs To Update After Implementation

- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- likely `docs/bot/perception-targeting.md` because it currently describes vanilla’s immediate type pick without hysteresis

## Acceptance Criteria

- close-score melee/ranged decisions no longer flip every `0.3s`
- clear winner changes still flip promptly
- no BT-layer cooldown is required
- debug logs exist for actual type flips only
- unit tests cover both margin and momentum behavior
