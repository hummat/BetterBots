# Ogryn — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## Bull Rush / Indomitable (`ogryn_charge`)

**Cooldown:** 30s | **Role:** Gap-closer, rescue, escape

### USE WHEN
- Ally being disabled (`priority_target_enemy`) and target > 4m — **#1 use case**
- Ally downed (`target_ally_needs_aid`, `need_type == "knocked_down"`, distance > 6m)
- Special at 8-18m (`opportunity_target_enemy`) — gap close
- Emergency escape: `num_nearby >= 4 AND toughness_pct < 0.20`

### DON'T USE WHEN
- Already in melee range (<4m) — scatters enemies, wastes ability
- No target — charging into empty space
- Target is super armor without talent — charge stops on impact
- Team is fine and no specials visible (`num_nearby <= 2 AND priority_target == nil AND opportunity_target == nil`)

### PROPOSED BOT RULES
```
IF priority_target_enemy AND target_dist > 4 THEN activate (HIGH)
IF target_ally_needs_aid AND ally_dist > 6 THEN activate (HIGH)
IF opportunity_target AND target_dist >= 8 AND target_dist <= 18 THEN activate (MEDIUM)  -- 18m requires ogryn_charge_increased_distance talent (base: 12m)
IF num_nearby >= 4 AND toughness_pct < 0.20 THEN activate (MEDIUM)
BLOCK IF target_dist < 4
BLOCK IF target_enemy == nil
BLOCK IF num_nearby == 0 AND priority_target == nil
```
**Confidence:** HIGH — "don't charge trash" is universal.

---

## Loyal Protector (`ogryn_taunt_shout`)

**Cooldown:** 50s | **Role:** AoE taunt, draw aggro to protect team

### USE WHEN
- Ally needs aid AND `num_nearby >= 2 AND toughness_pct > 0.30` — protect/revive
- High density: `num_nearby >= 4 AND toughness_pct > 0.40 AND health_pct > 0.30`
- Multiple elites threatening allies: `count_elites >= 2 AND any_ally_toughness_pct < 0.30`
- `challenge_rating_sum >= 5.0 AND num_nearby >= 3`

### DON'T USE WHEN
- Bot is alone or isolated — no allies to benefit
- Low toughness AND low health (`toughness_pct < 0.20 AND health_pct < 0.30`) — can't survive aggro
- Only 1-2 trash enemies (`num_nearby <= 2 AND challenge_rating_sum < 1.5`) — 50s CD too expensive
- Against monstrosities alone — taunt doesn't affect them

### PROPOSED BOT RULES
```
IF target_ally_needs_aid AND num_nearby >= 2 AND toughness_pct > 0.30 THEN activate (HIGH)
IF num_nearby >= 4 AND toughness_pct > 0.40 AND health_pct > 0.30 THEN activate (MEDIUM)
IF count_elites >= 2 AND any_ally_toughness_low THEN activate (MEDIUM)
BLOCK IF num_nearby <= 2 AND challenge_rating_sum < 1.5
BLOCK IF toughness_pct < 0.20 AND health_pct < 0.30
```
**Confidence:** HIGH — "50s CD is unforgiving, save for emergencies."

---

## Point-Blank Barrage (`ogryn_gunlugger_stance`)

**Cooldown:** 80s | **Role:** Ranged DPS stance

### USE WHEN
- Monster visible with no melee pressure (`urgent_target AND num_nearby <= 1 AND target_dist > 5`)
- 2+ elites/specials at range (`target_dist > 5 AND count_elites_or_specials >= 2`)
- `challenge_rating_sum >= 6.0 AND target_dist > 5 AND num_nearby <= 2`

### DON'T USE WHEN
- In melee (`num_nearby >= 3` or `target_dist < 4`) — locked into ranged weapon
- Only trash enemies (`challenge_rating_sum < 2.0`) — 80s too expensive
- No target

### PROPOSED BOT RULES
```
IF urgent_target AND num_nearby <= 1 AND target_dist > 5 THEN activate (HIGH)
IF target_enemy_type == "ranged" AND target_dist > 5 AND count_elites_or_specials >= 2 THEN activate (MEDIUM)
BLOCK IF num_nearby >= 3
BLOCK IF target_dist < 4
BLOCK IF challenge_rating_sum < 2.0
```
**Confidence:** MEDIUM — 80s CD demands very conservative use.

---

## Grenades (Tier 3 — not yet implemented)

| Grenade | USE WHEN | Key constraint | Confidence |
|---------|----------|----------------|------------|
| B.F. Rock | Special at >6m — spam freely (4 charges, 45s regen) | Most bot-friendly blitz | MEDIUM |
| Big Box of Hurt | `num_nearby >= 5 AND challenge_rating_sum >= 3.0` | Keep 1 charge reserve | MEDIUM |
| Demolition Frag | Monster OR `challenge_rating_sum >= 8.0` — panic button | Single charge, no regen | MEDIUM |

---

## Sources

- [Steam: When and what to Bull Rush?](https://steamcommunity.com/app/1361210/discussions/0/3829789016663229955/)
- [Steam: Rush vs Taunt endgame](https://steamcommunity.com/app/1361210/discussions/0/4040357419297549585/)
- [Steam: Is Taunt Ogryn worth it?](https://steamcommunity.com/app/1361210/discussions/0/3878220223850988598/)
- [Steam: Ogryn Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3094034467)
- [Complete Post-Rework Ogryn Guide — GamesLantern](https://darktide.gameslantern.com/user/nrgaa/guide/complete-post-rework-ogryn-guide)
- [Point-Blank Barrage — GamesLantern](https://darktide.gameslantern.com/abilities/point-blank-barrage)
- [Fatshark Forums: Best Ogryn Grenades](https://forums.fatsharkgames.com/t/best-ogryn-grenades/108855)
