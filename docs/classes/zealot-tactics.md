# Zealot — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## Fury of the Faithful (`zealot_dash`)

**Cooldown:** 30s | **Role:** Gap-closer + toughness recovery + burst damage

### USE WHEN
- Toughness below 30% with enemies nearby and target at 3-20m — dash restores 50% toughness
- Elite/special at 5-20m — guaranteed crit + 100% rending on first post-dash hit
- Ally being disabled (`priority_target_enemy`) and target > 4m away
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

## Bolstering Prayer / Relic (`zealot_relic`)

**Cooldown:** 60s | **Role:** Team toughness support (Tier 3 item-based)

### USE WHEN
- Average ally toughness < 40% AND allies in coherency >= 2 AND `num_nearby < 2`
- Self toughness < 25% AND `num_nearby < 3`

### DON'T USE WHEN
- `num_nearby >= 3` — vulnerable while channeling
- Elite engaged at close range
- No allies in coherency

### PROPOSED BOT RULES
```
IF avg_ally_toughness_pct < 0.40 AND allies_in_coherency >= 2 AND num_nearby < 2 THEN activate (HIGH)
IF toughness_pct < 0.25 AND num_nearby < 3 THEN activate (MEDIUM)
BLOCK IF num_nearby >= 3
BLOCK IF allies_in_coherency == 0
```
**Confidence:** HIGH — existing `cumulative_challenge_rating >= 1.75` threshold in code is a reasonable proxy.

---

## Grenades (Tier 3 — implemented)

| Grenade | USE WHEN | DON'T USE WHEN | Confidence |
|---------|----------|----------------|------------|
| Stun | Clustered elite/special pressure, or dense crowds that need an interrupt window | Scattered enemies, or point-blank panic throws | HIGH |
| Flame | Chokepoint / horde incoming at >5m | At bot's feet or melee range | MEDIUM |
| Throwing Knives | Special/elite at 5-20m — use aggressively (12 charges, refill on melee kills) | Hordes, point-blank | HIGH |

---

## Sources

- [Zealot Infodump (No Stealth) — GamesLantern](https://darktide.gameslantern.com/builds/9a4fa304-0b88-4cf8-827a-d0435327a8c3/zealot-infodump-no-stealth-auric)
- [Zealot Infodump (Stealth) — GamesLantern](https://darktide.gameslantern.com/builds/9a7a817d-6ef9-49b6-9e1e-c6f1d03b3fec/zealot-infodump-stealth-auric)
- [Steam: Zealot Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3088553235)
- [Perfected Relic Warrior — GamesLantern](https://darktide.gameslantern.com/builds/9da39b45-5a0a-4ed1-9b0e-670f8ad96e33/perfected-relic-warrior-with-explanation-and-tips)
- [TheGamer: Zealot Tips](https://www.thegamer.com/warhammer-40000-darktide-zealot-preacher-class-guide/)
