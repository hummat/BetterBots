# Hive Scum — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## Key Class Trait: Glass Cannon

Lowest base toughness (75) and HP (150) of any class. Both Desperado and Rampage refill toughness on activation. **Toughness-based triggers should be weighted heavily.**

---

## Enhanced Desperado (`broker_focus`)

**Cooldown:** 45s (paused during stance) | **Role:** Ranged burst + toughness recovery + ammo sustain

### USE WHEN
- Toughness below 40% — instant toughness refill is critical for this fragile class
- 2+ ranged enemies in LoS — 100% ranged damage immunity during stance
- Ammo clip low (<20%) AND `num_nearby >= 3` — free reloads
- 5+ enemies at close-mid range — kill extension mechanic rewards sustained engagement

### DON'T USE WHEN
- No enemies in engagement range — wastes 10s duration window
- Full toughness, full ammo, <3 enemies — low value
- Purely melee engagement with no ranged threats — ranged immunity wasted

### PROPOSED BOT RULES
```
IF toughness_pct < 0.40 AND num_nearby >= 1 THEN activate (HIGH)
IF ranged_enemies_in_los >= 2 THEN activate (MEDIUM)
IF num_nearby >= 5 THEN activate (MEDIUM)
BLOCK IF num_nearby == 0
BLOCK IF active_stance_already_on
```
**Confidence:** HIGH

---

## Rampage (`broker_punk_rage`)

**Cooldown:** 30s (paused during stance) | **Role:** Melee burst + toughness recovery + stun immunity

### USE WHEN
- Toughness below 40% — instant toughness refill
- 3+ melee enemies within 5m — stun immunity + 50% melee power + 25% DR
- Elite/monster in melee range — +50% power shreds armored targets
- Horde wave incoming — natural frontliner role

### DON'T USE WHEN
- No melee targets nearby — forces melee equip, wastes buff
- Enemies are primarily ranged and distant — Desperado is better
- Just used Stimm — redundant overkill per community

### PROPOSED BOT RULES
```
IF toughness_pct < 0.40 AND num_nearby >= 1 THEN activate (HIGH)
IF melee_enemies_within_5m >= 3 THEN activate (MEDIUM)
IF (elite_or_monster_within_8m >= 1) AND melee_enemies >= 1 THEN activate (MEDIUM)
IF num_nearby >= 6 THEN activate (MEDIUM)
BLOCK IF num_nearby == 0
BLOCK IF all_enemies_ranged_and_distant
BLOCK IF active_stance_already_on
```
**Confidence:** HIGH

---

## Stimm Field (`broker_area_buff`)

**Cooldown:** 60s (paused while active) | **Role:** Team corruption healing + area buff (Tier 3 item-based)

### USE WHEN
- Any ally has >30% corruption AND 2+ allies within 8m
- Team is stationary / defending a position
- Before major event pushes

### DON'T USE WHEN
- Team is mobile/kiting — 3m radius is tiny
- No corruption on team — primary value wasted
- Bot is solo/separated — team support ability

### PROPOSED BOT RULES
```
IF team_corruption_pct > 0.30 AND allies_within_8m >= 2 AND team_stationary THEN activate
BLOCK IF allies_within_8m == 0
BLOCK IF team_actively_retreating
```
**Confidence:** MEDIUM — Tier 3 item-based, limited reliability.

---

## Blitz (Tier 3 — implemented)

| Blitz | USE WHEN | DON'T USE WHEN | Confidence |
|-------|----------|----------------|------------|
| Flash Grenade | Clustered specials/elites that need an interrupt, dense clusters, or emergency breathing room | Single isolated target in a calm fight | MEDIUM |
| Tox Grenade | Chokepoint hordes, monsters, or high-challenge mixed packs that will stay inside the cloud | Open areas the pack will instantly walk around, or single small targets | MEDIUM |
| Missile Launcher | Monster/boss at >8m, 3+ armored elites clustered at >8m | Allies in blast radius, close range (<8m, self-damage), scattered trash | MEDIUM |

**Missile Launcher:** Always hold 1 charge if monster alive on map. Never fire at <8m (self-damage).

---

## Weapon Type Awareness

Desperado requires/auto-wields ranged. Rampage requires/auto-wields melee. The bot needs to check `required_weapon_type` or current wielded weapon. Since bots have one combat ability (determined by loadout), this is spawn-time, not runtime.

---

## Sources

- [Steam: Hive Scum Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3586590987)
- [Complete Hive Scum Guide — GamesLantern](https://darktide.gameslantern.com/user/br1ckst0n/guide/the-complete-hive-scum-operative-guide)
- [PC Gamer: Best Hive Scum Build](https://www.pcgamer.com/games/fps/warhammer-40k-darktide-hive-scum-build-best/)
- [Gamesear: Hive Scum Beginner's Guide](https://www.gamesear.com/tips-and-guides/hive-scum-beginners-guide-fun-powerful-builds-for-the-endgame-warhammer-40000-darktide)
- [Fatshark Dev Blog: Hive Scum Class Design](https://www.playdarktide.com/news/dev-blog-hive-scum-class-design-talents)
