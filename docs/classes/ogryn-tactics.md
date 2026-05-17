# Ogryn — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.11.6. See bottom for links.

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
IF target_ally_needs_aid AND need_type IN {knocked_down, ledge, netted, hogtied} AND ally_dist > 6 THEN activate (HIGH)
IF opportunity_target AND target_dist >= 8 AND target_dist <= 18 THEN activate (MEDIUM)  -- 18m requires ogryn_charge_increased_distance talent (base: 12m)
IF num_nearby >= 4 AND toughness_pct < 0.20 THEN activate (MEDIUM)
BLOCK IF target_dist < 4
BLOCK IF target_enemy == nil
BLOCK IF num_nearby == 0 AND priority_target == nil
```
**Confidence:** HIGH — "don't charge trash" is universal.

---

## Loyal Protector (`ogryn_taunt_shout`)

**Cooldown:** 30s | **Duration:** 15s taunt | **Role:** AoE taunt, +20% damage debuff on taunted enemies, full toughness restore on shout

### USE WHEN
- Ally needs aid AND `num_nearby >= 2 AND toughness_pct > 0.30` — protect/revive
- High density: `num_nearby >= 4 AND toughness_pct > 0.40 AND health_pct > 0.30`
- Multiple elites threatening allies: `count_elites >= 2 AND any_ally_toughness_pct < 0.30`
- `challenge_rating_sum >= 5.0 AND num_nearby >= 3`
- Self-defense: `toughness_pct < 0.30 AND num_nearby >= 2` — shout fully restores toughness (`toughness_replenish_percent = 1`)
- Just before throwing a Big Box of Hurt at an elite cluster — the +20% damage debuff amplifies the AoE

### DON'T USE WHEN
- Bot is alone or isolated — no allies to benefit
- Low toughness AND low health (`toughness_pct < 0.20 AND health_pct < 0.30`) — can't survive the aggro pull even with toughness refill
- Only 1-2 trash enemies (`num_nearby <= 2 AND challenge_rating_sum < 1.5`) — debuff has no meaningful target
- Against monstrosities alone — taunt doesn't affect them

### PROPOSED BOT RULES
```
IF target_ally_needs_aid AND num_nearby >= 2 AND toughness_pct > 0.30 THEN activate (HIGH)
IF num_nearby >= 4 AND toughness_pct > 0.40 AND health_pct > 0.30 THEN activate (MEDIUM)
IF count_elites >= 2 AND any_ally_toughness_low THEN activate (MEDIUM)
IF toughness_pct < 0.30 AND num_nearby >= 2 THEN activate (MEDIUM)  -- self-defense
IF count_elites >= 2 AND big_box_of_hurt_ready THEN activate, then throw grenade (MEDIUM)
BLOCK IF num_nearby <= 2 AND challenge_rating_sum < 1.5
BLOCK IF toughness_pct < 0.20 AND health_pct < 0.30
```
**Confidence:** HIGH — 30s CD makes Taunt an opportunity-gated tool, not an emergency-only one. Community top play uses it as a +20% team damage amp combo, with the toughness refill as a free defensive byproduct.

**Mechanics:**
- The taunted enemy gets `damage_taken_multiplier = 1.2` (+20% incoming damage) for 15s — applies to *all* damage sources, not just the Ogryn's
- The Ogryn also gets `toughness_replenish_percent = 1` on shout (100% toughness refill)
- Talents granting `damage_taken_vs_taunted` stack on top of the +20% base debuff
- Cooldown was previously documented as 50s — corrected against `talent_settings_ogryn.lua:283` (`ogryn_2.combat_ability.cooldown = 30`)

**Boss timing:**
- Against monstrosities, fire Taunt during the boss's recovery / idle phase, not mid-charge or mid-slam — the 15s debuff window aligns with the team's damage burst after the boss exits its active animation
- Bots cannot reliably read boss animation state. Practical proxy: `target_is_monster AND target_velocity < 2 AND no_recent_boss_attack` (heuristic for "boss is idling"). Without a reliable proxy, default to firing Taunt when a monstrosity *first becomes attackable* — community top play also accepts this opener as second-best timing.
- Cooldown is 30s, so a single boss fight will see 2-3 Taunt windows — no need to save the first cast for the perfect moment

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
- `ogryn_club_p2_m1/m2/m3`: queues the fist/slap special before high-health or armored targets, then paces repeat use so the bot does not replace every club swing with a hand attack.
- `ogryn_pickaxe_2h_p1_m1/m2/m3`: queues the pickaxe special before high-health or armored targets.
- `ogryn_combatblade_p1_m1/m2/m3`: queues the uppercut special before high-health or armored targets.
- `ogryn_powermaul_p1_m1/m2/m3`: activates the power maul special before high-health or armored targets.
- `ogryn_rippergun_p1_m1/m2/m3`: rewrites close-range fire into the bayonet `stab` input when the current target is inside the configured bayonet distance and worth a melee special, but target-type correction no longer keeps the bot in ranged mode against point-blank hard-armored elites just to bayonet them.
- `ogryn_heavystubber_p1_m1/m2/m3` and `ogryn_thumper_p1_m1`: rewrite close-range fire into the melee bash input when the current target is inside the configured ranged-bash distance and worth a melee special; heavy stubbers can still swap back to melee when hard-armored targets are below the anti-armor ranged policy distance. Thumper-style `shotgun_grenade` weapons use the same close-range hipfire policy as shotguns, so bots stop bracing them into nearby targets.
- `ogryn_heavystubber_p2_m1/m2/m3`: deliberately ignored; the special is a flashlight toggle, not a combat action.

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
