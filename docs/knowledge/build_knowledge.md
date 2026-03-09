# Build Optimization Knowledge (v1.10.7)

Source: decompiled source + web research, compiled 2026-03-09.
Full meta builds: `../META_BUILDS_RESEARCH.md`.

## Class Base Stats

| Archetype | HP | Toughness | Stamina (base+weapon) | Wounds (Damn) | Dodge TDR |
|-----------|----|-----------|----------------------|----------------|-----------|
| veteran | 150 | 100 | 2+4=6 | 2 | 1.0 (none) |
| zealot | 200 | 100 | 3+4=7 | 2 | 0.5 |
| psyker | 150 | 75 | 1+4=5 | 2 | 0.5 |
| ogryn | 300 | 75 | 4+4=8 | 3 | 1.0 (none) |
| adamant | 200 | 80 | 3+4=7 | 2 | 0.5 |
| broker | 150 | 75 | 3+4=7 | 2 | 1.0 (none) |

## Coherency — Critical for Survivability

- Radius: 8m, stickiness 20m/2s. Daisy-chains.
- **0 allies = 0 toughness regen**. 1 ally = 50% rate. 3 allies = 100% rate (5 pts/sec).
- Melee kill recovery: 5% max toughness for all classes.
- Zealot talents can override minimum coherency stacks (solo play viable).

## Talent System Architecture

- DAG-based tree, 30 points, ~91 selectable nodes per class
- Nodes: `start` (0 cost, base ability), `default` (1 pt), `stat` (1 pt, generic stats)
- `base_talents` auto-applied on class load regardless of player choices
- Talents apply as buff templates via `buff_extension:add_externally_controlled_buff()`

## Key Talent Values (build-relevant)

### Veteran
- Volley Fire: 30s CD, 5s duration (8s improved), +25% ranged damage, +25% weakspot
- Coherency aura: 0.75% ammo/tick (1%/tick improved), 5s CD
- ADS-drain crit: +25% crit chance while draining stamina
- Sniper's Focus: 10 stacks (15 improved), 5s duration per stack
- Tag damage: +5%/stack, max 4 (6 with talent)
- Clip size: +25%

### Zealot
- Chastise: 30s CD, 7m dash, +25% melee damage, +100% rending, +50% toughness, 3s
- Martyrdom: +10%/stack × 5 stacks, -7.5% TDR/stack
- Dodge damage stacking: +3%/stack, max 5, 8s
- Kill stacking: +10%/stack (5 stacks), 5s
- Stealth CDR: monster 50%, ogryn 30%, other 15%
- Sprint: +10% speed, -10% cost

### Psyker
- Smite: 30s CD, 30 range, 500 PL
- Overcharge: +1%/stack, max 30 stacks
- Glass cannon: toughness replenish ×0.7, warp charge ×0.6

### Ogryn
- Tank passives: -20% damage taken, -25% TDR
- Block power stacking: +10% impact/stack (8 stacks, 6s)
- Attack speed stacking: +2.5%/stack (5 stacks, 5s)

## Perk System (Universal, T1→T4)

| Perk | T1 | T4 |
|------|----|----|
| Armor-type damage (+unarmored/armored/etc.) | +10% | +25% |
| Crit chance | +2% | +5% |
| Crit damage | +4% | +10% |
| Weakspot damage | +4% | +10% |
| Flat damage | +1% | +4% |
| Damage vs elites/hordes/specials | +4% | +10% |
| Stamina | +1 | +2 |
| Reload speed (ranged) | +5% | +10% |
| Block cost reduction (melee) | -5% | -20% |

## Current Meta (Havoc 40, March 2026)

### Tier list
S: Hive Scum (mobility, DPS, ranged immunity), Psyker (versatile, dome shield)
A: Veteran (team support), Ogryn (taunt, boss damage)
B: Arbites (stagger/tank, selfish)
C: Zealot (contested by Hive Scum for melee slot)

### Standard comp
1. Veteran — Voice of Command, Plasma Gun (sniper + ammo gen)
2. Zealot — Chorus, Relic Blade/Duelling Sword + Flamer (frontline + team toughness)
3. Psyker — Telekine Shield (Dome), Inferno Staff (support + horde clear)
4. Ogryn — Loyal Protector (Taunt), Pickaxe + Heavy Stubber (tank + boss)

### Key balance changes (2025-2026)
- March 2025: Full Ogryn rework (+14 talents), Psyker buffs
- Sept 2025: Vet/Zealot/Psyker tree reworks, Power Falchion, Scab Plasma Gunner
- Dec 2025: Hive Scum launch
- Feb 2026: Stimm Lab rework, talent adjustments (current patch 1.10.7)

## Community Resources

- **Build planner**: GamesLantern Build Editor
- **Breakpoint calc**: Wartide breakpoint calculator
- **Survivability calc**: Desmos calculator (community-made)
- **Datamined stats**: Steam enemy stats guide, curio/stimm mechanics guide
- **YouTube optimizers**: Reginald, Mister E., Ryken XIV, cashcrop_, Hank
- **Steam class guides**: Ogrynomicon, Psyker's Atheneum (8 comprehensive guides)
- **Community hubs**: Official Discord (~130k), r/DarkTide, Fatshark Forums

## Curio Meta (Universal)

- 3× Blessed Bullet (Combat Ability Regen > Toughness Regen Speed > Gunner DR)
- Defense always trumps offense at Havoc/Auric
- Toughness regen speed stacks multiplicatively with coherency modifier

## Weapon Damage Profile Pattern

Each weapon attack has:
- `power_distribution.attack` — base power budget (e.g., lasgun killshot: 50–350 depending on mark)
- `armor_damage_modifier` — per armor type, often near/far lerp for ranged
- `cleave_distribution` — hit mass budget (single_cleave through big_cleave)
- `crit_boost` — additional crit ADM bonus
- Mark variants override power_distribution and select armor mods

Example breakpoint check: Kantrael MG XIIa headshot vs Damnation Rifleman (400 HP):
- Power: 175–350, ADM unarmored: ~0.8, finesse boost (headshot): ~0.5
- Approximate: 20 base × (buff stack) × 0.8 ADM × (1 + finesse) — needs full calc with actual buff values
