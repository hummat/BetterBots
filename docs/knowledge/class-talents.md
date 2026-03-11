# Class Talent Values — All 6 Classes (v1.10.7)

Source: decompiled `talent_settings_*.lua` + `archetype_talents/talents/*.lua`, verified 2026-03-09.

## Tree Structure

| Class | Version | Nodes | Points | Base Crit |
|-------|---------|-------|--------|-----------|
| Veteran | 29 | 91 | 30 | — |
| Zealot | — | 91 | 30 | — |
| Psyker | 24 | 87 | 30 | 7.5% |
| Ogryn | 23 | 94 | 30 | 2.5% |
| Adamant | 18 | 100 | 30 | 7.5% |
| Broker | 13 | 79 | 30 | 10% |

## VETERAN — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Volley Fire (stance) | 30s | 5s | +25% ranged, +25% weakspot, outlines elites/specials |
| Voice of Command (shout) | 30s | — | 9m AoE stagger, +50% toughness, can revive downed allies |
| Infiltrate (stealth) | 45s | 8s | +25% move speed; exit: +30% damage 5s, 50% TDR 10s, 90% threat reduction 10s |

### Blitz/Grenades
| Grenade | Max Charges | Notes |
|---------|-------------|-------|
| Frag Grenade (base) | 3 | Improved: +25% damage, +25% radius; bleed (6 stacks) |
| Krak Grenade | 3 | Improved: +75% damage |
| Smoke Grenade | 3 | Improved: +100% fog duration |
| Grenade replenishment | — | +1 grenade every 60s; OR 5% chance on elite kill (aura) |

### Keystones
| Keystone | Key Stats |
|----------|-----------|
| Sniper's Focus | 10 stacks (15 improved), +7.5% finesse/stack, +1% reload/stack, 5s decay; at 10: +15% rending; +4% toughness replenish/stack |
| Weapon Switch | Ranged: +2% atk speed + reload/stack (max 10), +33% crit first shot; Melee: +15% atk speed, +10% dodge dist; +20% stam/toughness on swap |
| Focus Target (tag) | Tag stacks every 1.5s, max 4 (6 improved), increased damage to tagged; +5% toughness on tagged kill |

### Key Passives
- Weakspot damage: +30%
- Range damage: +10% close → +25% far
- ADS-drain crit: +25% crit chance, −60% sway, costs 0.75 stamina/s + 0.1/shot
- Elite damage: +15%; Big game hunter: +20% vs Ogryn/monsters
- Crit chance: +10%; Melee crit+finesse: +10% crit, +25% finesse
- Dodge crit: +5%/stack, 8s, max 5 (=+25% crit)
- Bonus crit on high ammo: +10% ranged crit when ≥80% clip
- Elite kill CDR: −6s CD (−10s improved), +1% CDR for 3s
- Clip size: +25%; Ammo reserve: +40%
- Reload on elite kill: +30% speed for next reload
- Non-empty clip reload: +25% speed
- Wield speed: +50%; Sprint cost: −20%
- Sprint damage: +6.25%/stack, 10s, max 4 (=+25%)
- Kill→slot damage: +25% ranged on melee kill (6s) / +25% melee on ranged kill (6s)
- Flanking: +30% damage
- Rending bonus: +10%; Sniper's Focus rending: +15% at 10 stacks
- Suppression dealt: +75%
- Bleed on melee hit: 2 stacks; Crits apply rending debuff
- Toughness per ally in coherency: up to 33% TDR at max allies
- TDR above 75% toughness: 50% TDR (halves toughness damage)
- All kills toughness: 5% or 10% per kill (tier-dependent)
- Block/toughness break synergy: block broken → 33% TDR 5s; toughness broken → −50% block cost 5s
- Movement on toughness broken: +12% speed 5s; OR stun/slowdown immune + 50% stamina 6s (20s CD)
- Movement towards downed: +20% speed, revived allies get 33% DR for 5s
- Attack speed: +10% melee
- Plasma proficiency: reduced vent self-damage
- Bolter proficiency: reduced spread/recoil/sway
- Las crits: no ammo cost on critical hits

### Coherency
- Base aura: elite kills → +0.75% ammo to coherency, 5s CD
- Improved aura: your kills 0.75%, ally kills 1.0%
- Damage aura: +7.5% damage to coherency; Movement aura: +5% move speed to coherency
- Ability grants: melee + ranged damage to allies for 8s; outlines allies 5s; +50 flat toughness for 10s

## ZEALOT — Key Values

### Combat Abilities
| Ability | CD | Duration | Key Bonus |
|---------|-----|----------|-----------|
| Chastise the Wicked (dash) | 30s | 3s buff | 7m dash, +25% melee, +100% rending, +50% toughness, 100% crit during dash |
| Chastise (upgraded) | 30s | 3s + 10s | Same + +20% attack speed for 10s; OR 2 charges |
| Zealot Stealth | 30s | 3s (20s improved) | +20% move, +100% crit/rending, +150% finesse/backstab/flanking; exit: 30% DR 8s |
| Bolstering Prayer (relic) | 60s | channel | +20% toughness/tick (0.8s) to team, +50% self toughness, +15 flat toughness/stack (×5=75 max) |

### Blitz/Grenades
| Grenade | Max Charges | Notes |
|---------|-------------|-------|
| Shock Grenade | 3 | Stun AoE; upgradable: +radius |
| Flame Grenade | 3 | Fire liquid AoE |
| Throwing Knives | 12 | Melee kill refills 1; ammo pickups refill; bleed kills can generate knives |

### Keystones
| Keystone | Key Stats |
|----------|-----------|
| Martyrdom | +10% damage per missing health segment (15% HP/step), max 5 stacks; +6% attack speed/stack; +7.5% TDR/stack; +10% CDR/stack |
| Fanatic Rage | Enemy deaths within 25m + crits grant fury, max 25, 8s; at max: +15% crit, +50% toughness, −25% TDR, +2%/s regen |
| Quickness | Movement builds stacks (max 20); per stack: +1% atk speed, +1% damage, +0.5% dodge; 6s (10s improved); dodge grants 3 |

### Key Passives
- Resist Death (Until Death): survive lethal hit, 5s immunity, 120s CD; melee ×3 leech during, up to 25% HP; can trigger ability instantly
- Melee attack speed: +10%
- Crit → bleed + crit chance: +10% crit for 3s on crit (2 stacks)
- Kill stacking: +10%/kill melee damage, max 5 stacks, 5s
- Hit stacking: +4%/hit melee damage, max 5, 5s (= +20%)
- Heavy → damage: +15% damage 5s
- Post-push cleave: +25% cleave + impact, 5s
- Weakspot kills: +5%/stack weakspot power, max 5, 5s (= +25%)
- Weakspot stagger: +50% melee weakspot impact
- Damage vs elites: +15%
- Bleed → damage: bled enemies take +15% more
- Crits rend: +15% rending per crit
- Close ranged damage: +25%
- Cleave: +50% max hit mass impact; Impact: +30%
- Backstab damage: +25% backstab + flanking; Flanking: +30%
- Finesse after dodge: +50% finesse, 3s
- Uninterruptible heavies: 100% movement speed during heavies
- Dodge improvements: +1 dodge, +25% dodge distance
- Sprint: +10% speed, −10% cost, 1s slowdown immunity; separate nodes: −20% cost, +5% speed
- Weapon handling after dodge: −75% spread, −50% recoil, 3s
- Melee after empty clip: +30% impact, +10% attack speed, 5s
- Reload on melee kills: +6%/stack reload + wield speed, max 5 stacks
- Toughness on heavy kill: 10%; on dodge: 15% (0.5s CD); on ranged kill: 4%
- Toughness in melee: +2.5% base/s, +1%/s per nearby enemy (5m), cap 7.5%/s
- Corruption resistance: ×0.5 (50% reduction)
- Extra wounds: +2 health segments
- Heal 20% of damage taken over 4s
- Segment break DR: 40% on segment-breaking hit
- Stealth CDR: monster 50%, Ogryn 30%, other 15% per kill
- Stealth more CD more damage: −5s CD flat, +50% finesse/backstab during stealth, perfect block window on exit
- Backstab kills: −75% threat for 5s
- Backstab toughness: +10% ally toughness + 10% TDR for 5s

### Coherency
- Base aura: −7.5% TDR for allies (always ≥2 stacks active)
- Improved aura: −15% TDR
- Alt aura: −15% stamina cost
- Corruption healing aura: 0.5/s (×1.5 improved)

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
