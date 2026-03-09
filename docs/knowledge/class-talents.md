# Class Talent Values — All 6 Classes (v1.10.7)

Source: decompiled `talent_settings_*.lua`, verified 2026-03-09.
Veteran/Zealot details in `build_knowledge.md`. This file covers Psyker, Ogryn, Adamant, Broker + cross-class summary.

## Tree Structure

| Class | Version | Nodes | Points | Base Crit |
|-------|---------|-------|--------|-----------|
| Veteran | 29 | 91 | 30 | — |
| Zealot | — | 91 | 30 | — |
| Psyker | 24 | 87 | 30 | 7.5% |
| Ogryn | 23 | 94 | 30 | 2.5% |
| Adamant | 18 | 100 | 30 | 7.5% |
| Broker | 13 | 79 | 30 | 10% |

## PSYKER — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Venting Shriek (psyker_2) | 30s | — | 500 PL, 30m range, 10% warp vent (50% improved) |
| Telekine Shield/Dome (psyker_3) | 45s (35s reduced) | 17.5–25s | 50% TDR, 10% toughness for allies, 20-30 HP |
| Scrier's Gaze (overcharge_stance) | — | — | +10% base dmg, +1%/stack (30 max), +20% crit, 10s post-duration |

### Keystones
| Keystone | Key Stats |
|----------|-----------|
| Warp Siphon (passive_1) | 4 souls (6 improved), 24% damage, 25s duration |
| Empowered Psionics (passive_3) | 15% proc chance, chain lightning +2 damage |
| Disrupt Destiny (mark_passive) | 3 weakspot stacks |

### Key Passives
- Glass cannon: toughness replenish ×0.7, warp charge generation ×0.6
- Warp attacks rending: +20% at ≥75% peril
- Kinetic Deflection: 25% damage→peril conversion
- DR + stun immunity: 10% DR for 4s on proc
- Soulblaze DR: toughness_damage_taken ×0.67 near soulblaze
- Melee toughness: 2.5% instant + 15% over 3s
- Crit toughness: 10% toughness + 5% move speed, 3 stacks, 4s

### Coherency
- psyker_2: +10% damage vs elites
- psyker_3: -7.5% ability CD (-10% improved)

## OGRYN — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Point-Blank Barrage (ogryn_1) | 80s | 5s resistance | +25% ammo, fire rate stacking, 15% free ammo chance |
| Bull Rush (ogryn_2) | 30s | 5s active | 12m distance, +25% melee attack speed, +25% move speed, 2m AoE |
| Loyal Protector/Taunt | 50s | 15s | 12m range (from main ability settings) |

### Base Passives (always active)
- Tank: **-20% damage taken, -25% TDR** (massive!)
- Revive/assist speed: +25% each
- Stagger cleave on 3rd hit: +25% hit mass + impact
- Corruption resistance: ×0.6 (40% reduction)

### Heavy Hitter Keystone
- 1 stack per light, 2 per heavy, max 8 stacks
- Per stack: +3% melee damage, +1.25% TDR, +7.5% stagger, +12.5% cleave
- At 8 stacks: +24% damage, +10% TDR, +60% stagger, +100% cleave
- +15% toughness melee replenish

### Other Key Values
- Crit damage increase: +75% (highest single crit modifier)
- Block all attacks: 5s, +20% melee damage
- Far damage: +15% ranged far damage
- Ranged damage immunity: 2.5s, ×0.8 ranged taken, 4s CD
- Melee→ranged: +3%/stack (5 stacks, 10s) = +15% ranged after melee
- Taunt toughness restore: 10% instant + 0.5%/hit taken (max 20 stacks, 3.25s)
- Push applies brittleness: 4 stacks

### Coherency
- ogryn_1: +20% damage vs suppressed (30% improved)
- ogryn_2: +7.5% melee damage (10% improved)

## ADAMANT (Arbites) — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Shout | 60s | — | 6m (12m far, 16m improved), +30% toughness improved |
| Charge | 20s | 6s | 3.75m range, +25% damage, +50% impact, +20% toughness |
| Stance | 50s | 10s (+2s linger) | +25% damage, ×0.2 damage taken, +15% move speed, +75% companion damage |

### Keystones
| Keystone | Key Stats |
|----------|-----------|
| Forceful | +5% impact/stack, +0.5% toughness/stack, ×0.975 DR/stack, 10 stacks, 5s |
| Execution Order | +10% damage, +10% crit chance, +25% crit damage, +10% rending, 8s, 50% CDR on kill (3s) |
| Terminus Warrant | 30 max stacks, +15% melee/ranged dmg, +25% weakspot/crit dmg, +15% rending |
| Stance Dance | +15% melee/ranged dmg, +10% crit chance, +25% crit/weakspot dmg, 5s window after 3 hits |
| Exterminator | +4%/stack damage (10 stacks), 12s, +10% ammo/stamina/toughness |
| Bullet Rain | +25% fire rate, +15% ranged damage, 30 stacks, 50% TDR, 75% toughness replenish |
| Pinning Dog | +2.5%/stack permanent damage (30 stacks!), +15% elite damage 8s, CDR 50% |

### Companion (Cyber-Mastiff)
- Whistle: 50s CD, 2 charges, +50% damage, 8s duration, +25% move speed
- Electrocute: 5s, 500 PL
- Pounce bleed: 6 stacks
- Brittleness: 6 stacks
- Dog damage after ability: +50% for 12s

### Drone (Nuncio-Aquila)
- 60s CD, 20s duration, 7.5m range
- 30% TDR, 5% toughness (7.5% improved)
- -25% enemy melee attack speed and damage
- +10% attack speed, +30% revive speed
- -25% recoil

### Key Passives
- Disable companion: +10% damage, +10% attack speed, -15% TDR, +1 grenade, faster blitz regen
- Limit damage per hit: 50 HP cap
- Perfect block: +15% damage, +15% attack speed, -15% block cost, 8s
- Stagger DR: ×0.97/stack, 5 stacks, 8s
- Flat toughness: +25 (armor) or +25 (plasteel_plates)
- Monster hunter: +20% damage vs monsters

## BROKER (Hive Scum) — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Enhanced Desperado (focus) | 45s | 10s (max 20s) | +1s/kill extend, 10% ammo refill, +50% reload, +20% sprint, 0 sprint cost |
| Frenzied Rampage (punk_rage) | 30s | 10s (max 20-40s) | +50% melee power, +20% attack speed, 25% DR, +0.3s/kill extend |
| Stimm Supply (stimm_field) | 60s | 20s | 3m radius, 50% corruption heal, 0.25s tick |

### Rampage Exhaust — REMOVED in 1.10.6
- ~~7s exhaustion after Rampage ends~~ — removed in Feb 2026 patch
- Rampage is now pure upside with no exhaust penalty
- This makes Rampage significantly more viable vs Desperado

### Keystones
| Keystone | Key Stats |
|----------|-----------|
| Vulture's Mark | +5%/stack ranged dmg, crit, move speed (3 stacks, 8-12s), +15% toughness |
| Chemical Dependency | +5%/stack crit (3 stacks), +10% ability CD regen, 90s duration, 50% toughness grant |
| Adrenaline Junkie | 30 hit stacks → Frenzy: +25% melee damage, +10% attack speed, 10-20s |

### Key Passives
- Base crit: 10% (highest of all classes)
- Close range damage: +25% near, +10% far
- Ninja crit: +20% crit for 3s (multiple trigger sources: backstab, parry, ninja)
- Dodge improvements: +25% dodge speed, dodge cooldown -40% at ≥75% stamina
- Toughness on close kill: 8% (15% on elite)
- Toughness on toughness broken: 50% toughness + 6s stun immunity, 10s CD
- Ramping backstabs: +10%/stack melee power, 5 stacks
- Punk grit: +10% ranged damage, ×0.9 TDR
- Extended mag: +15% clip size
- Reload on crit: 15% ammo replenish
- Push on damage taken: 10% DR, 3 stacks

### Stimm Lab System
4 tracks, each with 5 tiers and branching at tier 5:
- **Celerity**: +4% attack speed/tier, +25% wield speed, stamina reduction → T5: stun immune OR +30% reload OR +10% move speed
- **Combat**: +4% power/tier → T5: +25% finesse OR +10% rending OR +10% crit chance
- **Durability**: 6.25% toughness + 5% replenish + 4% DR per tier → T5: +30% replenish OR toughness over time
- **Concentration**: 6.25% ability CD regen/tier → T5: +25% CD regen OR melee kill CDR OR ranged kill CDR

### Coherency
- Gunslinger: +10% melee damage
- Anarchist: +5% crit chance

## Cross-Class Combat Ability Summary

| Class | Ability | CD | Key Offensive | Key Defensive |
|-------|---------|-----|---------------|---------------|
| Veteran | Volley Fire | 30s | +25% ranged, +25% weakspot | AoE stagger |
| Veteran | Exec Stance | 30s | +25% ranged, +25% weakspot | — |
| Zealot | Chastise | 30s | +25% melee, +100% rending | +50% toughness |
| Zealot | Chorus | — | push enemies | +100 toughness overheal |
| Psyker | Venting Shriek | 30s | 500 PL AoE, 50% vent | — |
| Psyker | Dome | 45s | — | 50% TDR, 10% team toughness |
| Ogryn | Taunt | 50s | — | Redirects aggro 15s |
| Ogryn | Bull Rush | 30s | +25% attack speed | Dodge-state during charge |
| Ogryn | PBB | 80s | Fire rate stacking | 5s resistance |
| Arbites | Charge | 20s | +25% damage, +50% impact | +20% toughness |
| Arbites | Stance | 50s | +25% damage | ×0.2 damage taken (!!) |
| Hive Scum | Desperado | 45s | Infinite ammo, +50% reload | Ranged immunity |
| Hive Scum | Rampage | 30s | +50% melee power, +20% speed | 25% DR (but 25% more taken after) |
