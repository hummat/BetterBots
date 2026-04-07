# Grenade/Blitz Melee-Engagement Gate Design

Date: 2026-04-07
Issue: #71

## Problem

Bots can interrupt active melee combat to swap into grenade/blitz throw sequences. The original issue was reported on Ogryn grenades, but the underlying failure mode is broader: the bad behavior comes from entering a slow swap-aim-throw sequence while already under melee pressure, not from one specific grenade template.

The current logic splits grenade decisions by heuristic family:

- `_grenade_horde(...)` for horde-clearing throws such as Ogryn box/frag
- `_grenade_priority_target(...)` for single-target throws such as Ogryn rock and Veteran krak

This means a fix only in `_grenade_horde(...)` would still leave B.F. Rock and other priority-target grenades able to trigger while the bot is tied up in melee.

## Decision

Add a shared close-melee gate for grenade heuristics that represent committed throw sequences, plus a separate crowd-pressure block only for single-target throw heuristics.

Block activation when either of these is true:

- shared committed-throw block: `context.target_enemy_distance < 4`
- single-target throw block only: `context.num_nearby >= 4`

The close-melee gate applies before template-specific throw logic for committed throw profiles. The crowd-pressure block applies only to `_grenade_priority_target(...)` callers such as rock, krak, and missile launcher. It does not apply to crowd-control or area-denial heuristics such as smoke, shock, fire, or mines.

## Rationale

Distance-only is insufficient for single-target throws. A bot can still be surrounded and decide to throw at a distant special, which matches the reported B.F. Rock failure mode.

Density-only is too blunt as a shared rule. Crowd-control and area-denial grenades are often useful precisely because enemy density is high.

The split rule is the simplest policy that matches actual grenade roles. In `grenade_fallback.lua`, standard swap-and-throw templates incur wield plus aim/hold delays, so entering that sequence while an enemy is already inside melee range is usually wrong for any committed throw. But high density alone should not suppress smoke, shock, fire, or mine placement, because those grenades are designed for pressure situations. High density should only be used as an extra block for single-target throws that pull the bot out of melee to answer one distant target.

## Scope

### In scope

- Grenade heuristics that lead to committed swap-and-throw or swap-and-place sequences
- Ogryn box, cluster box, frag, and rock
- Veteran frag, smoke, and krak
- Zealot fire grenade and shock grenade
- Arbites grenades and shock mine
- Hive Scum grenade templates and missile launcher

### Out of scope

- Ability-based/no-swap paths such as Arbites whistle
- Fast or special-case profiles that should opt out explicitly in this change, such as zealot throwing knives
- Re-tuning individual grenade thresholds beyond the shared melee-engagement gate

## Implementation Plan

1. Add a helper in `heuristics.lua` that answers whether grenade/blitz activation should be blocked for melee engagement.
2. Apply the shared close-melee helper to `_grenade_horde(...)`, `_grenade_defensive(...)`, and `_grenade_mine(...)`.
3. Apply the shared close-melee helper to `_grenade_priority_target(...)`, and add a priority-only crowd-pressure block there for distant single-target throws.
4. Allow explicit opt-out via `opts` so fast/special-case templates are not forced into either block.
5. Keep the rule local to grenade heuristics rather than pushing it into `grenade_fallback.lua`.
6. Use rule names that make the block visible in logs and tests.

## Why Not Put This In `grenade_fallback.lua`

`grenade_fallback.lua` is the execution layer. It should handle sequencing, aim setup, state cleanup, and action-queue timing. It should not become the policy layer for which grenade templates are safe under melee pressure.

Keeping the gate in `heuristics.lua` preserves the existing separation:

- heuristics decide whether a throw is appropriate
- fallback executes the throw sequence once approved

That also keeps per-template exceptions straightforward. In practice, `_grenade_priority_target(...)` is shared by both heavy throwers and fast special cases, so the exception hook belongs there rather than in the fallback state machine.

## Logging and Rules

The new block should produce deterministic rule text so regressions are obvious in unit tests and live logs.

Preferred rule names:

- `*_block_melee_range`
- `*_block_priority_melee_pressure`

If a single shared suffix is clearer in the implementation, use that instead, but it must distinguish this block from generic `hold`.

## Tests

Update `tests/heuristics_spec.lua` to cover:

- Ogryn box blocks when `target_enemy_distance < 4`
- Ogryn box still activates for valid horde conditions when the target is not in melee range
- Ogryn rock blocks when `target_enemy_distance < 4`
- Ogryn rock blocks when `num_nearby >= 4` even if target distance is safe
- Veteran krak blocks under the same priority-target conditions
- Veteran smoke, zealot shock, and Arbites shock mine are not blocked by nearby-count pressure alone
- Zealot throwing knives remain on their existing behavior if explicitly opted out
- Existing positive cases still pass when target distance and nearby count are both safe

## Docs To Update After Implementation

- `docs/dev/status.md` — mark `#71` implemented on `dev/v0.9.1`
- `docs/dev/roadmap.md` — mark `#71` implemented/pending in-game validation
- `docs/dev/known-issues.md` — move `#71` from active issue to fixed-on-branch note

## Acceptance Criteria

- Bots do not start swap-and-throw grenade/blitz sequences while already in melee range.
- Single-target grenade throws do not start while the bot is surrounded by melee pressure, even if the chosen target is farther away.
- Ability-based/no-swap blitz paths are unchanged.
- Fast opt-out templates keep their current behavior unless explicitly retuned.
- Crowd-control and area-denial grenade paths are not suppressed just because enemy density is high.
- Unit tests cover both crowd and single-target grenade paths.
