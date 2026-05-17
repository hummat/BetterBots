# Darktide Balance Patch History (Mar 2025 — May 2026)

Source: official patch notes + community analysis, compiled 2026-03-09, extended 2026-05-17 with 1.11.0–1.11.6 from the decompiled source.

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
| Patch 1.10.6 | 1.10.6 | Feb 2026 | Stimm rework, Rampage exhaust disabled |
| Patch 1.10.7 | 1.10.7 | Feb 2026 | Far range damage fix |
| Warband | 1.11.0 | Mar 2026 | New enemies (Chaos Ogryn Houndmaster, Armored Hound), profile validator, all-class rebalance |
| Hotfix 1.11.1 | 1.11.1 | Mar 2026 | Stability |
| Patch 1.11.2 | 1.11.2 | Mar 2026 | Scripts + content fixes |
| Patch 1.11.3 | 1.11.3 | Mar 2026 | Veteran/Zealot tuning |
| Patch 1.11.4 | 1.11.4 | Apr 2026 | Adamant/Broker keystone tuning |
| Patch 1.11.5 | 1.11.5 | Apr 2026 | Buff template refactor (proc_buff → server_only_proc_buff) |
| Patch 1.11.6 | 1.11.6 | May 2026 | Skulls and Guns live event |

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
- 1.11.1–1.11.5 patch descriptions in the timeline table are inferred from script diffs, not official patch notes — only 1.11.0 (Warband) and 1.11.6 (Skulls and Guns event live) have firm public labels

## Warband and after (1.11.0 — 1.11.6, Mar — May 2026)

Cutoff for the detailed entries below: decompiled commit `0f4a44b` (1.11.6, May 11 2026). All 1.11.x changes are sourced from the script diff between `f63d836` (1.11.3) and HEAD plus broader 1.11.0 baseline diffs against 1.10.7.

### New enemies and props (1.11.0)

| Breed | HP | Notable fields | Where |
|-------|----|-----------------|-------|
| `chaos_ogryn_houndmaster` | 22 000 | `is_boss = true`, `challenge_rating = 8`, `smite_stagger_immunity = true`; summons chaos hounds | `scripts/settings/breed/breeds/chaos/chaos_ogryn_houndmaster_breed.lua` |
| `chaos_armored_hound` | `_special_health_steps(1100)` | armor `resistant`, hit-mass 8, `stagger_resistance = 2`, `can_be_used_for_all_factions = true` | `scripts/settings/breed/breeds/chaos/chaos_armored_hound_breed.lua` |
| `chaos_plague_ogryn` (variant) | matches plague ogryn baseline | new breed file alongside existing plague ogryn — variant rather than wholly new | `scripts/settings/breed/breeds/chaos/chaos_plague_ogryn_breed.lua` |
| `sand_vortex` | `_roamer_health_steps(1000)` | `breed_type = living_prop`, `is_untargetable = true`, `challenge_rating = 30`, chaos faction | `scripts/settings/breed/breeds/sand_vortex_breed.lua` |
| `attack_valkyrie` | `_roamer_health_steps(1000)` | `flying = true`, `airbound = true`, `faction_name = "imperium"` (hostile despite faction string), `fly_fast_speed = 40`, `challenge_rating = 30` — expedition-specific | `scripts/settings/breed/breeds/valkyrie/attack_valkyrie_breed.lua` |

Side effects on existing entries: Poxwalker Bomber `hit_mass = 2.5 → 5` in `minion_difficulty_settings.lua`.

### Profile validation (1.11.0)

`scripts/extension_systems/unit_templates.lua` (lines 334 and 1037) and `scripts/utilities/profile_utils.lua:_convert_profile_from_lookups_to_data` now gate `TalentLayoutParser.validate_talent_layouts(...)` on `not profile.is_local_profile`. The validator strips talents that can't traverse back to a start node in the tree layout. This combined with `ProfileSynchronizerClient.set_profile` overwriting BotPlayer profiles caused the #65 P0 crash; the fix is `is_local_profile = true` on resolved bot profiles plus a one-shot `set_profile` hook. See `docs/bot/profiles-spawning.md` section 9.4.

### Veteran rebalance (1.11.0 + 1.11.3)

- Volley Fire / Executioner's Stance: duration **5s → 6s**; with Big Game Hunter, **8s → 9s** (`talent_settings_veteran.lua:74-75`).
- Voice of Command cooldown **30s → 40s** (`talent_settings_veteran.lua:189`). Revive-talent variant scales accordingly.
- Infiltrate cooldown **45s → 40s** (`talent_settings_veteran.lua:7`).
- Grenade replenishment: single 60s timer replaced with per-grenade-type timers — Krak 90s, Frag 60s, Smoke 60s, with a 75s global fallback (`talent_settings_veteran.lua:136`, fields `krak_time`, `frag_time`, `smoke_time`, `grenade_replenishment_cooldown`).
- Several Veteran `proc_buff` templates reclassified to `server_only_proc_buff` (1.11.5). BetterBots is host-side in Solo Play so the change is transparent; mods that read these buff states on dedicated-server clients lose authoritative access.

### Zealot rebalance (1.11.0)

- `zealot_stealth_cooldown_regeneration` implementation moved from a `passive` buff template to a `special_rule` (`zealot_invisibility_refund_cooldown`).
- `on_dodge_block_cost_multiplier` **0.75 → 0.5**.
- Several keystone proc events tightened — Fervent Fury proc chain refactored into `specific_check_proc_funcs` / `specific_proc_func` split with a new `on_bleeding_minion_death` event.

### Hive Scum (Broker) rebalance (1.11.0 + 1.11.4)

`broker_talents.lua` is the largest single 1.11.x diff (+563 lines).

- Adrenaline Junkie keystone: base stack grant changed from `on_hit` to `on_kill`. The on-hit proc is kept as a sub-proc rather than the primary trigger.
- New passive nodes: `broker_passive_increased_dodges` (+1 consecutive dodge), `broker_passive_longer_dodges` (+50% dodge distance), `broker_passive_replenish_toughness_while_toxined_enemies_in_proximity` (15m, 0.2s check, +1%/s toughness per tick, tracks up to 10 enemies).
- Flash grenade max charges **3 → 2 (default)** and **5 → 2 (improved)** — both variants now identical at 2 charges (`talent_settings_broker.lua:200,204`).
- Rampage Exhaust template was never deleted in 1.10.6 as the older entry above claims — `broker_punk_rage_exhaustion` still exists in `broker_buff_templates.lua:745` and `talent_settings_broker.lua:143-169`. The actual change is `use_exhaust = false` (1.10.6+), which disables it without removing the data.

### Arbites (Adamant) rebalance (1.11.4)

Companion keystone retuning across `talent_settings_adamant.lua`:

- damage `0.25 → 0.20`
- damage_taken_multiplier `0.20 → 0.30`
- damage_talent_damage `0.05 → 0.075`
- damage_talent_duration `10s → 12s`
- damage_talent_stacks `10 → 6`
- coherency toughness `0.10 → 0.075`
- keystone max_stacks `30 → 20`
- weapon swap stacks `15 → 1`
- new tuning fields: CDR `33%/12s`, crit_chance `10%`, ranged power level modifier, toughness_damage_taken_multiplier `0.8`

### Ogryn (1.11.x)

- `ShoutAbilityImplementation` module renamed to `ShoutAbility`. Both `action_ogryn_shout.lua` and `action_adamant_shout.lua` were touched. No BetterBots hook surfaces reference the old name (verified `rg ShoutAbilityImplementation` in `scripts/mods/BetterBots/`), so this is a doc-only concern.

### Havoc corruption fallback (1.11.x)

`havoc_buff_templates.lua` now exposes `CORRUPTION_FALLBACK_RANKS_PER_CHALLENGE = {5, 10, 15, 20, 25}`. When the Havoc extension is absent, the Corruption mutator scales by difficulty rank instead of Havoc rank — letting Corruption work outside Havoc mode.

### Skulls and Guns live event (1.11.6)

New coherency-driven team buff system: `scripts/settings/buff/live_event_buff_templates/live_event_skulls_guns_buff_templates.lua`. Placing a Skull in the world grants stacking buffs per additional player in coherency range:

- +12.5% damage per extra player (multiplicative)
- +5% toughness damage reduction per extra player
- +5% attack speed per extra player
- +10% movement speed per extra player

Max 5 stacks, smoothed by a 2.5s decay rate. Bots benefit from the buff if a player places a Skull near them; BetterBots has no module that picks up Skulls itself.

### Net effect on BetterBots heuristics

None of the above breaks the mod at runtime. Heuristics read live ability state via `combat_ability:remaining_cooldown()` and similar, so the numeric drift above only matters for human-facing tuning thresholds. The only soft gotcha is the new Chaos Ogryn Houndmaster — bots engage it generically via `is_boss`, but there is no "kill the summoner first" tactic; reports of bots ignoring summoned hounds in favour of the boss are expected.
