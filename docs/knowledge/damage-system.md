# Darktide Damage System (v1.10.7)

Source: decompiled Lua, verified 2026-03-09. Full pipeline in `scripts/utilities/attack/damage_calculation.lua`.

## Pipeline Summary (13 stages)

1. **Power Level → Base Damage**: `power_level * power_distribution[attack]` → clamped to 0–10000 → maps to 0–20 base damage. Default PL=500, default attack=100.
2. **Buff Multiplier Stack**: 40+ additive terms (damage, melee_damage, damage_vs_elites, etc.) summed into `damage_stat_buffs`, then × multiplicative terms. Target-side multipliers applied separately.
3. **Armor Damage Modifier (ADM)**: per armor type scalar. Ranged weapons lerp near/far ADM by √(dropoff).
4. **Rending**: partially negates armor DR. Clamped [0,1]. Overdamage past ADM=1.0 has only 25% efficiency.
5. **Finesse Boost**: weakspot OR crit adds bonus damage. Default boost=0.5 per source, runs through curve `{0, 0.3, 0.6, 0.8, 1}`.
6. **Positional**: backstab_damage + flanking_damage (additive to damage).
7. **Hitzone Multiplier**: per-breed per-body-part per-attack-type multiplier.
8. **Armor-Type Stat Buffs**: `unarmored_damage`, `armored_damage`, etc. from attacker+target.
9. **Diminishing Returns**: only if breed sets `diminishing_returns_damage`, easeInCubic of health%.
10. **Force Field Short-Circuit**: force field targets → base damage only, no multipliers.
11. **Damage Efficiency**: UI classification (negated/reduced/full) based on ADM thresholds.
12. **Toughness/Health Split**: shield gate → toughness absorption → health damage + corruption.
13. **Final Application**: leech, resist_death, death/knockdown resolution.

## Default Armor Damage Modifiers (attack power type)

| Armor | ADM | Enemies |
|-------|-----|---------|
| unarmored | 1.0 | snipers, basic cultists |
| armored | 0.5 | traitor guard, gunners, renegade berzerkers |
| resistant | 1.0 | bulwarks, chaos spawn, plague ogryn, beast of nurgle, daemonhost |
| berserker | 0.75 | mutants, netgunners |
| super_armor | 0.0 | chaos ogryn gunner, chaos ogryn executor |
| disgustingly_resilient | 0.8 | poxwalkers, chaos hound |
| void_shield | 0.8 | void shield generators |

## Rending Mechanics

- 16 additive sources (rending_multiplier, critical_strike_rending_multiplier, melee_rending_multiplier, etc.)
- Only affects armored/super_armor/resistant/berserker (rending_armor_type_multiplier=1 for these, 0 for others)
- Overdamage rending multiplier: **0.25** — rending past ADM=1.0 gives only 25% bonus
- Rending also doubles stagger strength contribution (rending_stagger_strength_modifier=2)

## Finesse Boost (Weakspot/Crit)

- Default weakspot boost: 0.5 (all armor types)
- Default crit boost: 0.5
- Combined max finesse_boost_amount: 1.0 → curve output ≈1.0
- Protected weakspot zones: ×0.25 boost. Shield zones: 0 boost.
- Crit ADM bonus: default 0, but weapon-specific presets add +0.3–0.5 to armored/super_armor
- Minimum crit ADM: 0.25 (crits always do at least 25% ADM even vs super_armor)

## Toughness Damage Absorption

Toughness damage ≠ raw damage. Formula:
```
toughness_damage = raw_damage × state_modifier × toughness_multiplier × weapon_modifier × buff_multipliers
```
- State modifiers: dodge (zealot/psyker/adamant: 0.5, vet/ogryn: 1.0), sprint (zealot: 0.5)
- Melee bleedthrough ALWAYS active: `bleedthrough = lerp(damage, 0, toughness_percent × spillover_mod)`
- Ranged: full spill-over when toughness breaks

## Key Constants

| Setting | Value |
|---------|-------|
| Default power level | 500 |
| Power output range | 0–20 |
| Default attack power distribution | 100 |
| Default impact power distribution | 5 |
| Default crit/weakspot boost | 0.5 each |
| Min crit ADM | 0.25 |
| Overdamage rending multiplier | 0.25 |
| Close range threshold | 12.5m |
| Far range threshold | 30m |
| Max stagger count bonus | 2.5× |
| Bleed max stacks | 16, tick 0.5s, max PL 500 (smoothstep) |
| Rending stagger modifier | 2× |

## Breakpoint Methodology

To check if weapon X can kill enemy Y in N hits at difficulty D:
1. Get weapon's `power_distribution.attack` → base damage
2. Apply ADM for enemy's armor type
3. Apply rending if any (from blessings/talents/crit)
4. Apply finesse if weakspot/crit
5. Apply all relevant buff multipliers (talents + blessings + perks)
6. Compare total per-hit damage to enemy HP at difficulty D
7. `hits_to_kill = ceil(enemy_hp / damage_per_hit)`

Critical breakpoints players optimize:
- One-shot Ragers (renegade_berzerker) on Damnation
- Two-hit Crushers (chaos_ogryn_executor) on Auric
- One-shot specials (hound, bomber, netgunner) at range
- Horde cleave efficiency (damage × targets per swing)
