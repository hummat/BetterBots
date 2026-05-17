# Zealot — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.11.6. See bottom for links.

## Fury of the Faithful (`zealot_dash`)

**Cooldown:** 30s | **Role:** Gap-closer + toughness recovery + burst damage

### USE WHEN
- Toughness below 30% with enemies nearby and target at 3-20m — dash restores 50% toughness
- Elite/special at 5-20m — guaranteed crit + 100% rending on first post-dash hit
- Ally being disabled (`priority_target_enemy`) and target > 4m away, or hard ally aid (`knocked_down`, `ledge`, `netted`, `hogtied`) with ally > 3m away
- 3+ enemies in path — AoE impact damage in 3m radius during lunge

### DON'T USE WHEN
- Target has super armor (Crushers, Bulwarks) — dash STOPS on super armor contact
- Already in melee range (<3m) — wastes the distance traversal and crit window
- No enemies visible

### PROPOSED BOT RULES
```
IF toughness_pct < 0.30 AND num_nearby > 0 AND target_dist > 3 AND target_dist < 20
   AND NOT target_has_super_armor THEN activate (HIGH)
IF (target has "special" or "elite") AND target_dist > 5 AND target_dist < 20
   AND NOT target_has_super_armor THEN activate (MEDIUM)
IF priority_target_enemy AND target_dist > 4 THEN activate (HIGH)
IF target_ally_needs_aid AND need_type IN {knocked_down, ledge, netted, hogtied} AND ally_dist > 3 THEN activate (HIGH)
BLOCK IF target_dist < 3
BLOCK IF target_breed IN {chaos_ogryn_bulwark, chaos_ogryn_executor, chaos_plague_ogryn}
```
**Confidence:** HIGH

---

## Shroudfield (`zealot_invisibility`)

**Cooldown:** 30s (with kill-based reduction) | **Role:** Defensive escape / aggro shed

**Bot note:** Offensive backstab value is limited since bots can't pathfind behind enemies. Primary bot value is **defensive** (shed aggro, toughness recovery on exit, repositioning).

### USE WHEN
- Emergency survival: `toughness_pct < 0.20 AND num_nearby >= 3`
- Low health alone only on non-Martyrdom builds: `health_pct < 0.25`
- Overwhelmed: `num_nearby >= 5 AND toughness_pct < 0.50`
- Elite/monster present and toughness OK (offensive use, lower priority)

### DON'T USE WHEN
- No enemies nearby — pure waste
- Bot is only frontliner and allies are nearby — dumps aggro on team
- About to throw grenade — breaks stealth

### PROPOSED BOT RULES
```
IF toughness_pct < 0.20 AND num_nearby >= 3 THEN activate (CRITICAL)
IF health_pct < 0.25 AND NOT talent(zealot_martyrdom) THEN activate (CRITICAL)
IF num_nearby >= 5 AND toughness_pct < 0.50 THEN activate (HIGH)
IF (target has "elite" or "monster") AND num_nearby >= 1 AND toughness_pct > 0.20 THEN activate (MEDIUM)
BLOCK IF num_nearby == 0
BLOCK IF allies_in_coherency == 0 AND num_nearby > 2  -- don't dump aggro if team isn't nearby
```
**Confidence:** HIGH

**Current BetterBots note:** the shipped Martyrdom carve-out keeps Shroudfield pressure-based, not health-based. Low health alone is not a panic trigger when the bot has `zealot_martyrdom`, because the keystone pays for staying wounded.

---

## Chorus of Spiritual Fortitude / Relic (`zealot_relic`)

**Cooldown:** 60s | **Channel duration:** 5.5s, uninterruptible | **Buff radius:** 10m | **Stagger radius:** 4m / 2s stagger | **Role:** Team toughness support + boss/elite stagger (Tier 3 item-based)

> Renamed from "Bolstering Prayer" — `zealot_bolstering_prayer` is the talent name; in-game UI calls it Chorus of Spiritual Fortitude. The `_relic` suffix matches the inventory item.

### Mechanics (decompiled source, `zealot_relic.lua:L134-L175`)
- Channel is **uninterruptible** (`uninterruptible = true`) for the full 5.5s
- Self toughness restore on activation: 100% (`toughness_restored = 1`)
- Self bonus toughness during channel: +400 flat (`toughness_bonus_flat = 400`)
- 40% TDR during channel (`toughness_damage_taken_multiplier = 0.6`)
- Per-tick ally buff (0.8s tick): +25% flat toughness to allies / +50% flat to self, +15 flat toughness stacking buff (up to 5 stacks = +75 flat at full duration)
- 20% toughness-regen-rate buff to allies in coherency
- 4m stagger radius around the channeling zealot — staggered enemies pinned for 2s on channel start
- The 10m buff radius applies separately to allies; the 4m stagger radius is enemy-only

### USE WHEN
- **Monstrosity spawn or entry** — community top play deploys the Relic as the monstrosity appears, using the 4m stagger to cancel its first slam/grab. Treat as the dominant trigger, not as a panic button.
- Corruption modifier active (Maelstrom mutators) AND allies in coherency >= 2 — even at full toughness, channel cleanses some corruption (verify against current corruption-cleanse buff template before relying on this)
- Average ally toughness < 40% AND allies in coherency >= 2 AND `num_nearby < 2`
- Self toughness < 25% AND `num_nearby < 3`
- Ally downed within 10m AND `num_nearby < 3` — the channel buff helps the reviver, the stagger buys time

### DON'T USE WHEN
- `allies_in_coherency == 0` — no allies inside the 10m buff radius
- `num_nearby >= 3 AND no_monstrosity` — vulnerable during 5.5s commit; only acceptable if a monstrosity threat justifies the trade
- About to engage at melee range — bot will be locked into the relic for 5.5s; ranged enemies at >10m will continue firing freely

### PROPOSED BOT RULES
```
IF enemy_monstrosity_in_proximity AND distance < 20 THEN activate (HIGH)  -- dominant trigger
IF corruption_modifier_active AND allies_in_coherency >= 2 THEN activate (HIGH)
IF avg_ally_toughness_pct < 0.40 AND allies_in_coherency >= 2 AND num_nearby < 2 THEN activate (HIGH)
IF toughness_pct < 0.25 AND num_nearby < 3 THEN activate (MEDIUM)
IF target_ally_needs_aid AND ally_dist < 10 AND num_nearby < 3 THEN activate (MEDIUM)
BLOCK IF num_nearby >= 3 AND NOT enemy_monstrosity_in_proximity
BLOCK IF allies_in_coherency == 0
```
**Confidence:** HIGH on monstrosity trigger; existing `cumulative_challenge_rating >= 1.75` proxy in code roughly captures this but doesn't explicitly identify monstrosities. A future refinement: gate the threshold on `boss_monstrosity_active` flag for a cleaner trigger.

**Commit warning:** the bot must hold the relic for the full 5.5s channel. If a higher-priority decision flips mid-channel (e.g., ally suddenly downed), the bot cannot abort — the channel is `uninterruptible`. Bot-level heuristics that try to cancel the relic mid-cast will silently fail.

---

## Grenades (Tier 3 — implemented)

| Grenade | USE WHEN | DON'T USE WHEN | Confidence |
|---------|----------|----------------|------------|
| Stun | Clustered elite/special pressure, or dense crowds that need an interrupt window | Scattered enemies, or point-blank panic throws | HIGH |
| Flame | Chokepoint / horde incoming at >5m | At bot's feet, melee range, or immediately after another control grenade | MEDIUM |
| Throwing Knives | Special/elite at 5-20m — use aggressively (12 charges, refill on melee kills) | Hordes, point-blank, monsters, hard-armored elites (Maulers, Bulwarks, Reapers) | HIGH |

---

## Sources

- [Zealot Infodump (No Stealth) — GamesLantern](https://darktide.gameslantern.com/builds/9a4fa304-0b88-4cf8-827a-d0435327a8c3/zealot-infodump-no-stealth-auric)
- [Zealot Infodump (Stealth) — GamesLantern](https://darktide.gameslantern.com/builds/9a7a817d-6ef9-49b6-9e1e-c6f1d03b3fec/zealot-infodump-stealth-auric)
- [Steam: Zealot Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3088553235)
- [Perfected Relic Warrior — GamesLantern](https://darktide.gameslantern.com/builds/9da39b45-5a0a-4ed1-9b0e-670f8ad96e33/perfected-relic-warrior-with-explanation-and-tips)
- [TheGamer: Zealot Tips](https://www.thegamer.com/warhammer-40000-darktide-zealot-preacher-class-guide/)
