# Roadmap

## Goal

Move BetterBots from working prototype to reliable baseline with explicit scope.

## Priority 0: Correctness

1. Tier 2 metadata/input mapping.
   - Status: implemented.

2. Runtime diagnostics.
   - Status: implemented (`decision`, `enter`, `fallback`, `charge consumed`, item fallback logs).

3. Item-based combat fallback.
   - Status: implemented (profile-based matching + per-stage guards + charge-confirm feedback loop).
   - Next: expand profile catalog and add explicit per-template overrides where needed.

4. Toggle-safe restore behavior.
   - Status: not implemented.

See `CLASS_*.md` docs for per-class ability details, implementation tiers, and bot usage heuristics.

## Priority 1: Behavior quality

1. Ability-specific trigger heuristics.
   - Keep veteran elite/special logic.
   - Add threat/toughness-aware triggers where useful.

2. Anti-spam controls.
   - Per-ability post-cooldown delay.
   - Optional gating by nearby enemy count.

3. Per-class/per-ability mod options.
   - Keep global toggle.
   - Add granular enable/disable switches.

## Priority 2: Scope expansion

1. Grenade support spike.
   - Investigate explicit wield + throw flow for bot grenades.

2. Hardening item templates.
   - Cover additional item-based combat templates beyond relic/force-field style flows.

## Milestones

1. M1: Tier 1 + Tier 2 + known item abilities cast in manual solo tests.
2. M2: No obvious regressions (revive/rescue/navigation/basic combat).
3. M3: Stable fallback behavior with low false casts/spam.
4. M4: Optional grenade decision documented (implement vs non-goal).

## Tracking checklist

```text
[x] P0.1 Tier 2 metadata/input mapping
[x] P0.2 Runtime diagnostics
[x] P0.3 Item fallback baseline (profile-based)
[ ] P0.4 Toggle-safe restore behavior
[ ] P1.1 Ability-specific triggers
[ ] P1.2 Anti-spam controls
[ ] P1.3 Per-ability mod options
[ ] P2.1 Grenade support technical spike
[ ] P2.2 Item fallback hardening (explicit mapping)
```
