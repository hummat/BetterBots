# Darktide Balance Patch History (Mar 2025 — Mar 2026)

Source: official patch notes + community analysis, compiled 2026-03-09.

## Patch Timeline

| Patch | Version | Date | Type |
|-------|---------|------|------|
| Nightmares & Visions | 1.7.x | Mar 2025 | Ogryn rework |
| Battle for Tertium | 1.8.0 | Jun 2025 | Arbites DLC, weapon balance |
| Hotfix #73 | 1.8.5 | Aug 2025 | Hot Shot blessing fix |
| Bound by Duty | 1.9.0 | Sep 2025 | Class rebalance, enemy HP |
| Hotfix #78-80 | 1.9.2-1.9.4 | Sep-Oct 2025 | Plasma Gunner nerfs, talent tuning |
| No Man's Land | 1.10.0 | Dec 2025 | Hive Scum DLC |
| Hotfix #83 | 1.10.2 | Dec 2025 | Boom Bringer buff |
| Patch 1.10.6 | 1.10.6 | Feb 2026 | Stimm rework, Rampage exhaust removed |
| Patch 1.10.7 | 1.10.7 | Feb 2026 | Far range damage fix |

## Critical Changes Affecting Build Optimization

### Enemy HP Increases (Bound by Duty 1.9.0)
Many breakpoints broke with this patch:
| Enemy | Damn HP old → new | Auric old → new |
|-------|-------------------|-----------------|
| Crusher | 3600 → 6500 | — |
| Scab Rager | 2000 → 2500 | — |
| Scab Mauler | 3000 → 3700 | — |
| Scab Gunner | 1200 → 1700 | — |
| Scab Shooter | 375 → 500 | — |
| Scab Stalker | 450 → 625 | — |
| Captains | 35-40k → 40-50k | — |

### Class Base Stat Changes
| Class | Stat | Old | New | Patch |
|-------|------|-----|-----|-------|
| Ogryn | Toughness | 50 | 75 | N&V Mar 2025 |
| Ogryn | Stamina regen | 1/s | 1.5/s | BbD Sep 2025 |
| Zealot | Toughness | 70 | 100 | BbD Sep 2025 |
| Arbites | Toughness | 100 | 80 | BbD Sep 2025 |
| Veteran | Stamina regen delay | 1s | 0.75s | BbD Sep 2025 |

### Keystone Changes
- Heavy Hitter: 5% dmg × 5 stacks → 3% × 8 stacks (24% max, was 25%, but now includes TDR + cleave + stagger)
- Martyrdom: 8% × 7 stacks → 10% × 5 stacks (50% max, was 56%)
- Execution Order: 15% → 10% damage
- Feel No Pain: toughness regen 2.5% → 3%; TDR 2.5% → 3%
- Burst Limiter Override: proc 8% → 15%

### Key Talent Nerfs
- Chorus bonus toughness: 20 → 15 per pulse (total 100 → 75)
- Dome CD: 40s → 45s
- Covering Fire: range 5 → 8m but damage 20% → 15%
- Loyal Protector CD: 45s → 50s
- Castigator's Stance CD: 45s → 50s

### Key Talent Buffs
- Shroudfield backstab: 100% → 150%
- Krak Grenade: 2 → 3 charges, fuse 2s → 1s
- Infiltrate: Surprise Attack now baseline
- Exec Stance: new 10% toughness/s regen
- Weapon Specialist ranged duration: 5s → 10s
- Ogryn Lucky Streak crit damage: 50% → 75%
- Ogryn Simple Minded corruption resist: 30% → 40%

### Hive Scum Balance (1.10.0–1.10.6)
- Rampage exhaust: **REMOVED** in 1.10.6 — no longer penalizes after ability ends
- Boom Bringer: 2 → 3 ammo, far range damage 900 → 1300
- Chem Grenade duration: 20s → 15s
- Nimble dodge bonus: +25% multiplicative → +0.15s flat
- Stimm durability track: toughness regen → toughness replenishment

### Weapon Balance Highlights
- Combat Shotguns: +20-25% damage, +15-30% ammo reserves (1.8.0)
- Helbore Lasguns: ADM buffs across board (+10-25% vs multiple armor types)
- Devil's Claw Swords: Light damage +50%, heavy unyielding ADM 0.75 → 1.25
- Ogryn Bully Clubs: light +23%, heavy +25% damage
- Heavy Eviscerators: Maniac ADM 0.5 → 0.9, Carapace ADM 0.1 → 0.25
- Shock Mauls: light +15%, heavy +14% damage, better dodges
- Relic Blade Overload impact: 25 → 62 (inner), 15 → 35 (outer)

### Scab Plasma Gunner (1.9.0–1.9.3)
- Introduced in BbD with 950 HP, 650 power, 0.5s aim, 1.5s shoot CD
- Nerfed in 1.9.2: HP 950→900, power 650→550, aim 0.5→0.75s, shoot 1.5→2.4s, wall pen removed
- Adjusted in 1.9.3: shoot 2.4→2.0s, dodge window 0.7→0.6s

### Pacing Fix (Nightmares & Visions)
- Coordinated strikes at Damnation/Auric: 90% → 30% occurrence rate
- This was a major difficulty reduction — fewer simultaneous special/elite spawns

## Known Gaps
- Hotfixes #74-77: stability only, no balance
- Some undocumented/"stealth" changes reported by community but not verified with datamined values
- Blessing tier-by-tier changes beyond Ceaseless Barrage not fully documented
