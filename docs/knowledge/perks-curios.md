# Weapon Perks & Curio Perks — Complete Reference

Source: decompiled v1.10.7 (`scripts/settings/equipment/`)

## Weapon Perks (Melee)

All melee weapon perks from `weapon_perks_melee.lua`:

| Perk | Stat | T1 | T2 | T3 | T4 |
|------|------|----|----|----|----|
| Damage (Unarmoured) | `unarmored_damage` | 10% | 15% | 20% | 25% |
| Damage (Flak Armoured) | `armored_damage` | 10% | 15% | 20% | 25% |
| Damage (Unyielding) | `resistant_damage` | 10% | 15% | 20% | 25% |
| Damage (Maniacs) | `berserker_damage` | 10% | 15% | 20% | 25% |
| Damage (Carapace) | `super_armor_damage` | 10% | 15% | 20% | 25% |
| Damage (Infested) | `disgustingly_resilient_damage` | 10% | 15% | 20% | 25% |
| Critical Hit Chance | `critical_strike_chance` | 2% | 3% | 4% | 5% |
| Critical Hit Damage | `critical_strike_damage` | 4% | 6% | 8% | 10% |
| Stamina | `stamina_modifier` | +1 | +1.25 | +1.5 | +2 |
| Weakspot Damage | `weakspot_damage` | 4% | 6% | 8% | 10% |
| Damage (flat) | `damage` | 1% | 2% | 3% | 4% |
| Finesse | `finesse_modifier_bonus` | 1% | 2% | 3% | 4% |
| Power Level | `power_level_modifier` | 1% | 2% | 3% | 4% |
| Impact | `impact_modifier` | 5% | 6% | 7% | 8% |
| Block Efficiency | `block_cost_multiplier` | 5% | 10% | 15% | 20% |
| Damage (Elites) | `damage_vs_elites` | 4% | 6% | 8% | 10% |
| Damage (Hordes) | `damage_vs_horde` | 4% | 6% | 8% | 10% |
| Damage (Specialists) | `damage_vs_specials` | 4% | 6% | 8% | 10% |
| Sprint Efficiency | `sprinting_cost_multiplier` | 6% | 9% | 12% | 15% |

## Weapon Perks (Ranged)

All ranged weapon perks from `weapon_perks_ranged.lua`:

| Perk | Stat | T1 | T2 | T3 | T4 |
|------|------|----|----|----|----|
| Damage (Unarmoured) | `unarmored_damage` | 10% | 15% | 20% | 25% |
| Damage (Flak Armoured) | `armored_damage` | 10% | 15% | 20% | 25% |
| Damage (Unyielding) | `resistant_damage` | 10% | 15% | 20% | 25% |
| Damage (Maniacs) | `berserker_damage` | 10% | 15% | 20% | 25% |
| Damage (Carapace) | `super_armor_damage` | 10% | 15% | 20% | 25% |
| Damage (Infested) | `disgustingly_resilient_damage` | 10% | 15% | 20% | 25% |
| Critical Hit Chance | `critical_strike_chance` | 2% | 3% | 4% | 5% |
| Critical Hit Damage | `critical_strike_damage` | 4% | 6% | 8% | 10% |
| Stamina (while active) | `stamina_modifier` | +1 | +1.25 | +1.5 | +2 |
| Weakspot Damage | `weakspot_damage` | 4% | 6% | 8% | 10% |
| Damage (flat) | `damage` | 1% | 2% | 3% | 4% |
| Finesse | `finesse_modifier_bonus` | 1% | 2% | 3% | 4% |
| Power Level | `power_level_modifier` | 1% | 2% | 3% | 4% |
| Damage (Elites) | `damage_vs_elites` | 4% | 6% | 8% | 10% |
| Damage (Hordes) | `damage_vs_horde` | 4% | 6% | 8% | 10% |
| Damage (Specialists) | `damage_vs_specials` | 4% | 6% | 8% | 10% |
| Reload Speed | `reload_speed` | 5% | 7% | 8.5% | 10% |

Note: Ranged perks lack Impact, Block Efficiency, and Sprint Efficiency. Melee perks lack Reload Speed.

## Curio Primary Stats (Blessings)

Curio blessings are the main stat. Values depend on curio item level (rating), not tiers:

| Blessing | Max Value | Notes |
|----------|-----------|-------|
| Max Toughness | +17% | Rating ≥410 |
| Max Health | +21% | Rating ≥420 |
| Max Stamina | +3 | Most common max |
| Max Wounds | +1 | Adds one health segment |

## Curio Perks (Secondary Stats)

All curio perks from `gadget_traits_common.lua`:

| Perk | T1 | T2 | T3 | T4 |
|------|----|----|----|----|
| Toughness | +2% | +3% | +4% | +5% |
| Health | +2% | +3% | +4% | +5% |
| Combat Ability Regen | 1% | 2% | 3% | 4% |
| Revive Speed | 6% | 8% | 10% | 12% |
| Stamina Regeneration | 6% | 8% | 10% | 12% |
| Block Efficiency | 6% | 8% | 10% | 12% |
| Sprint Efficiency | 6% | 9% | 12% | 15% |
| Corruption Resistance | 6% | 9% | 12% | 15% |
| Grimoire Corruption Resist | 5% | 10% | 15% | 20% |
| Toughness Regen Speed | +7.5%/−5% delay | +15%/−10% | +22.5%/−15% | +30%/−20% |
| DR vs Gunners | 5% | 10% | 15% | 20% |
| DR vs Snipers | 5% | 10% | 15% | 20% |
| DR vs Flamers | 5% | 10% | 15% | 20% |
| DR vs Bombers | 5% | 10% | 15% | 20% |
| DR vs Mutants | 5% | 10% | 15% | 20% |
| DR vs Pox Hounds | 5% | 10% | 15% | 20% |
| Experience | 2% | 4% | 6% | 10% |
| Ordo Dockets | 4% | 6% | 8% | 10% |
| Curio Drop Chance | 5% | 10% | 15% | 20% |

### Armor type mapping (perks → game categories)

The perk stat names map to game armor types as follows:
- **Unarmoured** = Poxwalkers, Dregs, basic cultists
- **Flak Armoured** (`armored`) = Scab Shooters, Scab Stalkers, most ranged enemies
- **Carapace** (`super_armor`) = Crushers, Maulers (armored head), Bulwarks (shield)
- **Unyielding** (`resistant`) = Plague Ogryns, Beasts of Nurgle, Chaos Spawn
- **Maniacs** (`berserker`) = Ragers, Poxbursters, Mutants
- **Infested** (`disgustingly_resilient`) = Plague Ogryns (body), Pox Hounds, Daemonhosts

### Source files

- Melee perks: `scripts/settings/equipment/weapon_traits/weapon_perks_melee.lua`
- Ranged perks: `scripts/settings/equipment/weapon_traits/weapon_perks_ranged.lua`
- Curio perks: `scripts/settings/equipment/gadget_traits/gadget_traits_common.lua`
- Weapon blessings (per-weapon): `scripts/settings/equipment/weapon_traits/weapon_traits_bespoke_*.lua`
- Talent values: `scripts/settings/talent/talent_settings_<class>.lua`
