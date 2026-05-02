# Arbites — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## Castigator's Stance (`adamant_stance`)

**Cooldown:** 50s | **Role:** Defensive panic button (toughness refill + 80% DR)

### USE WHEN
- Toughness below 30% — refills toughness completely
- Surrounded: `num_nearby >= 3 AND toughness_pct < 0.60`
- Monster engaged at close range (<8m) and bot is aggro target
- 2+ elites in proximity AND `toughness_pct < 0.50`

### DON'T USE WHEN
- High toughness with few enemies — wasteful on 50s CD
- Only ranged/distant enemies — DR less needed, disables sprint
- Need to reposition urgently — stance disables sprint

### PROPOSED BOT RULES
```
IF toughness_pct < 0.30 THEN activate (HIGH)
IF num_nearby >= 3 AND toughness_pct < 0.60 THEN activate (MEDIUM)
IF target has "monster" AND target_dist < 8 THEN activate (MEDIUM)
IF count_elites >= 2 AND toughness_pct < 0.50 THEN activate (MEDIUM)
BLOCK IF toughness_pct > 0.70 AND num_nearby <= 1
```
**Confidence:** HIGH — universally described as defensive panic button.

---

## Break the Line (`adamant_charge`)

**Cooldown:** 20s | **Role:** Gap-closer + AoE CC + damage buff

### USE WHEN
- 2+ enemies at 3-10m — stagger everything in path
- Special at 3-10m — gap close
- Ally being disabled (`priority_target_enemy`) and target > 3m, or hard ally aid (`knocked_down`, `ledge`, `netted`, `hogtied`) with ally > 3m away
- Freely — 20s CD is the shortest combat ability cooldown in the game

### DON'T USE WHEN
- No enemies in charge path
- Already in melee range of priority target
- Would charge off a ledge or away from team

### PROPOSED BOT RULES
```
IF num_nearby >= 2 AND target_dist > 3 AND target_dist < 10 THEN activate
IF target has "special" AND target_dist > 3 AND target_dist < 10 THEN activate
IF priority_target_enemy AND target_dist > 3 THEN activate
IF target_ally_needs_aid AND need_type IN {knocked_down, ledge, netted, hogtied} AND ally_dist > 3 THEN activate
BLOCK IF target_dist < 3
BLOCK IF num_nearby == 0
```
**Confidence:** HIGH — "use liberally" is universal. Short CD forgives mistakes.

---

## Nuncio-Aquila Drone (`adamant_area_buff_drone`)

**Cooldown:** 60s | **Role:** Stationary team buff zone (Tier 3 item-based, ~21% reliability)

### USE WHEN
- Team grouped (`allies_within_8m >= 2`) AND `num_nearby >= 4` — maximize buff value
- Monster fight with team nearby
- Holding a position (defense events, elevators)

### DON'T USE WHEN
- Team is moving — drone is stationary, team walks out of range
- Bot is alone
- Few enemies — 60s CD too expensive

### PROPOSED BOT RULES
```
IF allies_within_8m >= 2 AND num_nearby >= 4 THEN activate
IF target has "monster" AND allies_within_8m >= 1 THEN activate
BLOCK IF allies_within_8m == 0
BLOCK IF num_nearby <= 2
```
**Confidence:** MEDIUM — positioning-dependent, bot can only deploy at feet.

---

## Shout (`adamant_shout`)

**Cooldown:** 60s | **Status:** Likely cut content (not in talent tree)

Rules included defensively in case it becomes available:
```
IF toughness_pct < 0.25 AND num_nearby >= 2 THEN activate
IF num_nearby >= 5 AND toughness_pct < 0.50 THEN activate
```
**Confidence:** LOW

---

## Blitz (Tier 3 — not yet implemented)

| Blitz | USE WHEN | Key note | Confidence |
|-------|----------|----------|------------|
| Whistle | Special/elite visible, companion alive — direct dog to target | Only blitz with `ability_template`! Potential quick win. | MEDIUM |
| Frag Grenade | `num_nearby >= 4` or monster stagger | 3-4 charges, liberal use | MEDIUM |
| Shock Mine | Holding position AND `num_nearby >= 5` or 3+ elites | Positionally demanding — drop at feet | LOW |

---

## Sources

- [Full Arbites Guide — GamesLantern](https://darktide.gameslantern.com/user/nrgaa/guide/full-arbites-guide)
- [Break the Line — GamesLantern](https://darktide.gameslantern.com/abilities/break-the-line)
- [Castigator's Stance — GamesLantern](https://darktide.gameslantern.com/abilities/castigators-stance)
- [Nuncio-Aquila — GamesLantern](https://darktide.gameslantern.com/abilities/nuncio-aquila)
- [Steam: Arbitrator Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3472722314)
- [Fatshark Dev Blog: Arbites Talent Tree](https://www.playdarktide.com/news/dev-blog-arbites-talent-tree)
- [PC Gamer: Best Arbites Build](https://www.pcgamer.com/games/fps/warhammer-40k-darktide-arbites-build-best/)
