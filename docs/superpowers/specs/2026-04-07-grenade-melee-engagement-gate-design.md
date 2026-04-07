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

Add a shared melee-engagement gate for grenade heuristics that represent committed throw sequences, with explicit per-template opt-outs for fast or defensive special cases.

Block activation when either of these is true:

- `context.target_enemy_distance < 4`
- `context.num_nearby >= 4`

This gate applies before template-specific throw logic for committed throw profiles. It does not apply to all grenade/blitz templates indiscriminately.

## Rationale

Distance-only is insufficient. A bot can still be surrounded and decide to throw at a distant special, which matches the reported B.F. Rock failure mode.

Density-only is too blunt. Aggregate nearby count alone can suppress otherwise reasonable throws when the bot is not actually under immediate melee pressure.

The combined rule is the simplest policy that matches the real cost of these actions. In `grenade_fallback.lua`, standard swap-and-throw templates incur wield plus aim/hold delays. While that sequence runs, the bot is effectively stepping out of melee. If the bot is already in melee range or surrounded by several enemies, entering that sequence is usually wrong.

## Scope

### In scope

- Ogryn box, cluster box, frag, and rock
- Veteran frag, smoke, and krak
- Zealot fire grenade and shock grenade
- Arbites grenades that use swap-and-throw flow
- Hive Scum grenade templates that use swap-and-throw flow

### Out of scope

- Ability-based/no-swap paths such as Arbites whistle
- Fast or special-case profiles that should opt out explicitly in this change, such as zealot throwing knives
- Control/defensive blitz heuristics that are intentionally useful under pressure, unless a concrete bug is reported for them
- Re-tuning individual grenade thresholds beyond the shared melee-engagement gate

## Implementation Plan

1. Add a helper in `heuristics.lua` that answers whether grenade/blitz activation should be blocked for melee engagement.
2. Apply that helper to `_grenade_horde(...)`.
3. Apply that helper to `_grenade_priority_target(...)`, but allow explicit opt-out via `opts` so fast/special-case templates are not forced into the block.
4. Keep the rule local to grenade heuristics rather than pushing it into `grenade_fallback.lua`.
5. Use rule names that make the block visible in logs and tests.

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
- `*_block_melee_pressure`

If a single shared suffix is clearer in the implementation, use that instead, but it must distinguish this block from generic `hold`.

## Tests

Update `tests/heuristics_spec.lua` to cover:

- Ogryn box blocks when `target_enemy_distance < 4`
- Ogryn box blocks when `num_nearby >= 4` even if target distance is safe
- Ogryn rock blocks under the same melee-engagement conditions
- Veteran krak blocks under the same melee-engagement conditions
- Zealot throwing knives remain on their existing behavior if explicitly opted out
- Existing positive cases still pass when target distance and nearby count are both safe

## Docs To Update After Implementation

- `docs/dev/status.md` — mark `#71` implemented on `dev/v0.9.1`
- `docs/dev/roadmap.md` — mark `#71` implemented/pending in-game validation
- `docs/dev/known-issues.md` — move `#71` from active issue to fixed-on-branch note

## Acceptance Criteria

- Bots do not start swap-and-throw grenade/blitz sequences while already in melee range.
- Bots do not start swap-and-throw grenade/blitz sequences while surrounded by a small horde, even if the chosen target is farther away.
- Ability-based/no-swap blitz paths are unchanged.
- Fast opt-out templates keep their current behavior unless explicitly retuned.
- Unit tests cover both horde-type and priority-target grenade paths.
