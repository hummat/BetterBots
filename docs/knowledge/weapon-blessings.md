# Weapon Blessings Catalog (v1.10.7)

Source: decompiled `weapon_traits_bespoke_*.lua`, verified 2026-03-09. All 18 S/A-tier meta weapons.
All values are the raw multipliers (0.1 = 10%). Tiers: T1/T2/T3/T4.

## File-to-Weapon Mapping

| File | Weapon | Class |
|------|--------|-------|
| plasmagun_p1 | M35 Magnacore Mk II Plasma Gun | Veteran |
| powersword_p1 | Achlys Mk VI Power Sword | Veteran/Zealot |
| combatsword_p1 | Maccabian Mk IV Duelling Sword | Veteran/Zealot |
| flamer_p1 | Artemia Mk III Purgation Flamer | Zealot |
| forcesword_p1 | Deimos Mk IV Blaze Force Sword | Psyker |
| forcestaff_p1 | Voidstrike Staff | Psyker |
| forcestaff_p2 | Inferno/Purgatus Staff | Psyker |
| forcestaff_p3 | Surge Staff (chain lightning) | Psyker |
| forcestaff_p4 | Equinox Mk III Voidblast Staff | Psyker |
| ogryn_pickaxe_2h_p1 | Delver's Pickaxe | Ogryn |
| ogryn_club_p1 | Bully Club | Ogryn |
| ogryn_heavystubber_p1 | Heavy Stubber | Ogryn |
| ogryn_thumper_p1 | Rumbler | Ogryn |
| powermaul_p1 | Shock Maul & Shield | Arbites |
| powermaul_p2 | Shock Maul (2H) | Arbites |
| shotgun_p1 | Exterminator Shotgun | Arbites |
| dual_shivs_p1 | Improvised Shivs | Hive Scum |
| dual_stubpistols_p1 | Dual Stub Pistols | Hive Scum |
| stubrevolver_p1 | Zarona Stub Revolver | Vet/Zealot/Scum |
| boltpistol_p1 | Godwyn-Branx Bolt Pistol | Zealot/Arbites |
| combatknife_p1 | Catachan Combat Blade | Vet/Zealot/Scum |

## Cross-Weapon Blessing Patterns

Blessings that appear on multiple weapons (key for understanding the system):

| Blessing | Weapons | T4 Value |
|----------|---------|----------|
| `hipfire_while_sprinting` (Run 'n' Gun) | revolver, bolt pistol, rumbler, dual stubs, staffs | -30% spread, +15% near dmg |
| `suppression_on_close_kill` | shotgun, revolver, bolt pistol, dual stubs, stubber | 30 suppression value |
| `dodge_grants_critical_strike_chance` | force sword, combat blade, shivs, dual stubs | +20% crit for 2s |
| `stacking_rending_on_weakspot` (Uncanny Strike) | force sword, combat blade, shivs | +24%/stack (blade/sword), +8%/stack (shivs) |
| `rending_on_backstab` | combat blade, shivs | +100% backstab rending |
| `bleed_on_crit` | combat blade, shivs, shotgun | 6-8 stacks |
| `targets_receive_rending_debuff` | plasma, power sword, pickaxe, bully club, shock maul | 4 stacks |
| `increase_power_on_kill` | power sword, force sword, pickaxe | +8%/stack |
| `windup_increases_power` (Thrust) | power sword, pickaxe, bully club, shock maul | +20%/stack while holding heavy |
| `power_bonus_on_continuous_fire` (Blaze Away) | plasma, flamer, stubber, rumbler, inferno staff | +8-9%/stack (5 stacks) |

## Per-Weapon Key Blessings (Meta Picks Only)

### Plasma Gun
| Blessing | T4 | Notes |
|----------|-----|-------|
| Rising Heat (`crit_chance_scaled_on_heat`) | +10% crit / +10% crit dmg | Scales with heat |
| Gets Hot! (`reduced_overheat_on_critical_strike`) | 60% less heat on crit | Synergizes with Rising Heat |
| Blaze Away (`power_bonus_on_continuous_fire`) | +8%/stack (5 stacks) | Sustained fire |
| Charge Crit (`charge_level_increases_critical_strike_chance`) | +5%/stack (max 25%) | Charged shots |

### Power Sword
| Blessing | T4 | Notes |
|----------|-----|-------|
| Slaughterer (`increased_melee_damage_on_multiple_hits`) | +36% power | After cleaving |
| Cycler (`extended_activation_duration_on_chained_attacks`) | +10% impact, +2 extra hits | Extends activation |
| Headtaker (`infinite_melee_cleave_on_weakspot_kill`) | +15% weakspot, infinite cleave | Elite killer |
| Thrust (`windup_increases_power`) | +20%/stack | Heavy charge power |

### Duelling Sword (combatsword_p1)
| Blessing | T4 | Notes |
|----------|-----|-------|
| Uncanny Strike (`stacking_rending_on_weakspot`) | — | NOT on this weapon! See force sword/blade |
| Riposte (`staggered_targets_receive_increased_damage_debuff`) | 4 stacks | Damage debuff on staggered |
| Shred (`increased_melee_damage_on_multiple_hits`) | +36% power | Same as power sword |
| Headtaker (`infinite_melee_cleave_on_crit`) | +80% cleave | On crit |

### Purgation Flamer
| Blessing | T4 | Notes |
|----------|-----|-------|
| Blaze Away (`power_bonus_on_continuous_fire`) | +8%/stack | Core sustained damage |
| Penetrating Flame (`burned_targets_receive_rending_debuff`) | 4 rending stacks | On burning targets |
| Charmed Reload (`faster_reload_on_empty_clip`) | +36% reload speed | After emptying tank |
| Soulfire (`chance_to_explode_elites_on_kill`) | 20% proc chance | Elite explosions |

### Blaze Force Sword
| Blessing | T4 | Notes |
|----------|-----|-------|
| Blazing Spirit (`warp_charge_power_bonus`) | +5%/warp charge (max 20%) | Core damage scaling |
| Uncanny Strike (`stacking_rending_on_weakspot`) | +24%/stack (5 stacks) | Armor penetration |
| Riposte (`can_block_ranged`) | -30% block cost | Enables ranged blocking |
| Shred (`increase_power_on_kill`) | +8%/stack | Kill momentum |

### Pickaxe
| Blessing | T4 | Notes |
|----------|-----|-------|
| Haymaker (`power_bonus_on_first_attack`) | +60%, 3.5s CD | Huge first-strike |
| Thunderous (`windup_increases_power`) | +20%/stack | Heavy charge power |
| Headtaker (`increase_power_on_kill`) | +8%/stack | Kill stacking |

### Shivs
| Blessing | T4 | Notes |
|----------|-----|-------|
| Uncanny Strike (`stacking_rending_on_weakspot`) | +8%/stack (5 stacks, lower than blade) | Armor pen |
| Precognition (`dodge_grants_critical_strike_chance`) | +20% crit for 2s | Dodge-crit loop |
| Lacerate (`bleed_on_non_weakspot_hit`) | 4 bleed stacks | Body-hit bleed |
| Flesh Tearer (`increased_weakspot_damage_against_bleeding`) | +60% weakspot vs bleeding | Bleed synergy |

### Dual Stub Pistols
| Blessing | T4 | Notes |
|----------|-----|-------|
| Run 'n' Gun (`hipfire_while_sprinting`) | -30% spread, +15% near dmg | Sprint fire |
| Speedload (`reload_speed_on_slide`) | +10%/stack | Slide reload |
| Flanking Fire (`allow_flanking_and_increased_damage_when_flanking`) | +40% flanking dmg | Positional damage |

### Stub Revolver
| Blessing | T4 | Notes |
|----------|-----|-------|
| Hand-Cannon (`rending_on_crit`) | +60% rending on crit | Armor penetration |
| Surgical (`crit_chance_based_on_aim_time`) | +10%/stack, 0.3s/stack | ADS crit buildup |
| Gloryhunter (`toughness_on_elite_kills`) | 30% toughness on elite kill | Sustain |

### Bolt Pistol
| Blessing | T4 | Notes |
|----------|-----|-------|
| Puncture (`rending_on_crit`) | +60% crit rending | Same as revolver |
| Lethal Proximity (`crit_weakspot_finesse`) | +100% crit weakspot | Massive headshot bonus |
| Pinning Fire (`stagger_bonus_damage`) | +20% vs staggered | Stagger synergy |

## Blessing Tier Value Scaling Pattern

Most blessings follow predictable T1→T4 scaling:
- Percentage buffs: typically T1 = ~70% of T4, linear steps
- Stack counts: 1/2/3/4 (rending debuffs, bleed)
- Proc chances: 14%/16%/18%/20%
- Duration/cooldown: small increments (0.5s steps typically)

T4 is always worth it — the jump from T3→T4 is usually the same as T1→T2.
