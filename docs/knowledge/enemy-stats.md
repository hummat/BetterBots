# Enemy Stats Reference (v1.10.7)

Source: `scripts/settings/difficulty/minion_difficulty_settings.lua`, breed files. Verified 2026-03-09.

## Difficulty Levels

| Index | Name | Challenge | Is Auric | Unlock |
|-------|------|-----------|----------|--------|
| 1 | Uprising | 2 | no | 1 |
| 2 | Malice | 3 | no | 3 |
| 3 | Heresy | 4 | no | 9 |
| 4 | Damnation | 5 | no | 15 |
| 5 | Auric | 5 | yes | 30 |

## Health Scaling Multipliers

| Category | Uprising | Malice | Heresy | Damnation | Auric |
|----------|----------|--------|--------|-----------|-------|
| Horde | ×1 | ×1.25 | ×1.5 | ×2 | ×2.5 |
| Roamer | ×1 | ×1.25 | ×1.5 | ×2 | ×2.5 |
| Special | ×0.85 | ×1 | ×1.25 | ×1.5 | ×2 |
| Elite | ×0.75 | ×1 | ×1.25 | ×1.5 | ×2 |
| Monster | ×1 | ×1.25 | ×1.5 | ×2 | ×3 |

## Enemy HP by Breed (Base → Damnation → Auric)

### Horde
| Breed | Armor | Base | Damn | Auric |
|-------|-------|------|------|-------|
| chaos_poxwalker | DR | 150 | 300 | 375 |
| chaos_newly_infected | DR | 120 | 240 | 300 |
| chaos_mutated_poxwalker | DR | 180 | 360 | 450 |
| chaos_armored_infected | armored (legs/arms/head=unarmored) | 250 | 500 | 625 |

### Roamer
| Breed | Armor | Base | Damn | Auric |
|-------|-------|------|------|-------|
| cultist_melee | — | 275 | 550 | 688 |
| cultist_assault | — | 200 | 400 | 500 |
| renegade_melee | — | 250 | 650 | 815 |
| renegade_rifleman | — | 150 | 400 | 500 |
| renegade_assault | — | 180 | 500 | 625 |
| renegade_gunner | armored | 450 | 1275 | 1700 |
| renegade_berzerker | armored | 850 | 1875 | 2500 |

### Special
| Breed | Armor | Base | Damn | Auric |
|-------|-------|------|------|-------|
| chaos_hound | DR | 700 | 1050 | 1400 |
| chaos_poxwalker_bomber | DR | 700 | 1050 | 1400 |
| renegade_netgunner | berserker | 450 | 675 | 900 |
| cultist_mutant | berserker | 2000 | 3000 | 4000 |
| cultist_flamer/renegade_flamer | — | 700 | 1050 | 1400 |
| cultist_grenadier | — | 500 | 750 | 1000 |
| renegade_sniper | unarmored | 250 | 375 | 500 |

### Elite
| Breed | Armor | Base | Damn | Auric |
|-------|-------|------|------|-------|
| chaos_ogryn_gunner (Reaper) | **resistant** (shoulder/arms=super_armor, torso=armored) | 2000 | 3000 | 4000 |
| chaos_ogryn_bulwark | resistant | 2400 | 3600 | 4800 |
| chaos_ogryn_executor (Crusher) | **super_armor** | 1350 | 4875 | 6500 |
| renegade_executor (Mauler) | **armored** (head=super_armor) | 1250 | 2775 | 3700 |
| renegade_plasma_gunner | **armored** (limbs=unarmored, head=super_armor) | 900 | 1350 | 1800 |
| cultist_berzerker | — | 1000 | 1500 | 2000 |
| cultist_shocktrooper | — | 500 | 750 | 1000 |
| cultist_gunner | — | 700 | 1050 | 1400 |
| renegade_shocktrooper | armored | 350 | 1125 | 1500 |

### Boss/Monster
| Breed | Armor | Base | Damn | Auric |
|-------|-------|------|------|-------|
| chaos_plague_ogryn | resistant | 20000 | 40000 | 60000 |
| chaos_beast_of_nurgle | resistant | 17500 | 35000 | 52500 |
| chaos_spawn | resistant | 15750 | 31500 | 47250 |
| chaos_daemonhost | resistant | 16000 | 32000 | 40000 |
| renegade_twin_captain | — | 24000 | 48000 | 72000 |
| cultist_captain | **armored** (toughness=void_shield) | 14000 | 40000 | 50000 |
| renegade_captain | **armored** (toughness=void_shield) | 16000 | 40000 | 50000 |

(DR = disgustingly_resilient. All armor types now source-verified.)

## Hit Mass (Cleave Weight) — Key Values

| Category | Examples | Hit Mass |
|----------|----------|----------|
| Light horde | poxwalker, newly_infected | 1.0–1.5 |
| Heavy horde | armored_infected | 1.5–2.5 |
| Roamer | rifleman, assault | 1.5–2.5 |
| Cultist elite | cultist_berzerker, cultist_gunner | 4.0 |
| Renegade elite | gunner, radio_operator | 5.0–8.0 |
| Berzerker/Executor | renegade_berzerker, renegade_executor | 10.0 |
| Ogryn elite | bulwark, gunner, executor | 12.5 |
| Monster/Captain | all bosses, captains | 20.0 |

## Cleave Budget Reference

| Preset | Attack Budget | Impact Budget |
|--------|--------------|---------------|
| no_cleave | 0.001 | 0.001 |
| single_cleave | 1–2 | 1–2 |
| double_cleave | 2–4 | 2–4 |
| light_cleave | 3–6 | 3–6 |
| medium_cleave | 4–9 | 4–9 |
| large_cleave | 5.5–10.5 | 5.5–10.5 |
| big_cleave | 8.5–12.5 | 8.5–12.5 |

## Enemy Damage Output (Power Level by Difficulty)

| Source | Uprising | Malice | Heresy | Damn | Auric |
|--------|----------|--------|--------|------|-------|
| Horde melee | 300 | 400 | 600 | 800 | 1200–1600 |
| Renegade melee | 300 | 300 | 450 | 600 | 900–1050 |
| Berzerker melee | 400 | 600 | 800 | 1000 | 1200–1400 |
| Ogryn melee | 625 | 1000 | 1250 | 1500 | 2000–2500 |
| Renegade shot | 206 | 344 | 413 | 550 | 688–963 |
| Plasma gunner | 413 | 688 | 825 | 1100 | 1375–1925 |
| Daemonhost | 350 | 600 | 800 | 1000 | 1250–1600 |
