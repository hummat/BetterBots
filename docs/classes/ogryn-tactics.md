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
- Fire Shots variant can also justify activation on medium-range crowd pressure, not just elite packs
- Armor Pen variant is worth spending on hard ranged targets (super armor / monster / priority ranged pressure) even when the generic CR gate is not met yet
- Toughness Regen variant can justify activation at low toughness when the bot has a ranged target and room to stand off

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
Build-aware follow-up now shipped in BetterBots:
```
IF has(ogryn_special_ammo_fire_shots) AND target_dist > 5
   AND num_nearby >= 2 AND challenge_rating_sum >= 2.0 THEN activate
IF has(ogryn_special_ammo_armor_pen) AND target_dist > 5
   AND (target_is_super_armor OR target_is_monster OR priority_target_enemy) THEN activate
IF has(ogryn_ranged_stance_toughness_regen) AND target_dist > 5
   AND toughness_pct < 0.60 AND target_enemy_type == "ranged" THEN activate
IF has(ogryn_special_ammo_movement) THEN allow slightly closer commits
   (block melee pressure threshold +1, minimum target distance 3m, commit distance 3m)
```
**Confidence:** MEDIUM — first build-aware batch shipped; longer-horizon weapon/loadout coupling is still open.

---

## Grenades (Tier 3 — implemented)

| Grenade | USE WHEN | Key constraint | Confidence |
|---------|----------|----------------|------------|
| B.F. Rock | Special at >6m — spam freely (4 charges, 45s regen) | Most bot-friendly blitz | MEDIUM |
| Big Box of Hurt | Dense horde, or mixed elite/special pressure at safe range | Impact profile is stronger than a generic horde grenade, but still worse than Rock for lone picks | MEDIUM |
| Demolition Frag | Monster, or clustered elite/special pressure at safe range | Single charge, no regen — not a generic horde grenade | MEDIUM |

---

## Weapon Specials

BetterBots now covers the shipped Ogryn default special actions that matter most for validation:

- `ogryn_club_p1_m1`: queues the uppercut special before a melee attack only against high-health or armored targets.
- `ogryn_club_p1_m2/m3`: folds the latrine shovel before high-health or armored targets, with heavy follow-up bias for the hardest targets.
- `ogryn_powermaul_p1_m1/m2/m3`: activates the power maul special before high-health or armored targets.
- `ogryn_rippergun_p1_m1/m2/m3`: rewrites close-range fire into the bayonet `stab` input when the current target is inside the configured bayonet distance and worth a melee special.

These are all gated by the existing `melee_improvements` or `ranged_improvements` settings, not by new Ogryn-only toggles.

---

## Sources

- [Steam: When and what to Bull Rush?](https://steamcommunity.com/app/1361210/discussions/0/3829789016663229955/)
- [Steam: Rush vs Taunt endgame](https://steamcommunity.com/app/1361210/discussions/0/4040357419297549585/)
- [Steam: Is Taunt Ogryn worth it?](https://steamcommunity.com/app/1361210/discussions/0/3878220223850988598/)
- [Steam: Ogryn Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3094034467)
- [Complete Post-Rework Ogryn Guide — GamesLantern](https://darktide.gameslantern.com/user/nrgaa/guide/complete-post-rework-ogryn-guide)
- [Point-Blank Barrage — GamesLantern](https://darktide.gameslantern.com/abilities/point-blank-barrage)
- [Fatshark Forums: Best Ogryn Grenades](https://forums.fatsharkgames.com/t/best-ogryn-grenades/108855)
