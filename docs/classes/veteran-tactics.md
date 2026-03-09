# Veteran — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## Executioner's Stance (`veteran_ranger_stance`)

**Cooldown:** 30s | **Role:** Ranged DPS burst vs elites/specials

### USE WHEN
- Elite or special is current target (vanilla Fatshark heuristic — proven)
- 2+ elites/specials visible (chain kills extend stance)
- Monster visible with no melee pressure (`urgent_target_enemy` set, `num_nearby <= 2`)
- Target at medium+ range (>6m) where ranged bonuses matter

### DON'T USE WHEN
- Surrounded by melee (`num_nearby > 5` and `target_enemy_type == "melee"`)
- No elite/special/monster visible — wasting it on poxwalkers
- Already in melee range of all threats

### PROPOSED BOT RULES
```
IF target has tag "special" or "elite" THEN activate
IF urgent_target_enemy AND num_nearby <= 2 THEN activate
BLOCK IF num_nearby > 5 AND target_enemy_type == "melee"
```
**Confidence:** HIGH

### COOLDOWN MANAGEMENT
Aggressive — 30s is short. Use whenever elites present.

---

## Voice of Command (`veteran_squad_leader_stance`)

**Cooldown:** 30s (45s with revive talent) | **Role:** AoE stagger + toughness recovery

**Note:** Shares `veteran_combat_ability` template with Executioner's Stance. Needs `class_tag == "squad_leader"` detection to branch.

### USE WHEN
- Surrounded (`num_nearby >= 4`) — 2.5s heavy stagger in 9m radius
- Toughness below 50% with enemies nearby — instant full recovery
- Toughness below 25% with any enemies — emergency
- Ally downed within 9m (revive talent)

### DON'T USE WHEN
- No enemies within 9m — stagger hits nothing
- Full toughness, few enemies — save cooldown
- Enemies already staggered (shout doesn't re-stagger)

### PROPOSED BOT RULES
```
IF num_nearby >= 4 THEN activate
IF toughness_pct < 0.50 AND num_nearby >= 2 THEN activate
IF toughness_pct < 0.25 AND num_nearby >= 1 THEN activate
IF target_ally_needs_aid AND ally_distance <= 9 THEN activate
BLOCK IF toughness_pct > 0.80 AND num_nearby <= 2
```
**Confidence:** HIGH — community consensus: "spam it, 30s CD."

---

## Infiltrate (`veteran_invisibility`)

**Cooldown:** 45s | **Role:** Emergency escape / clutch revive

### USE WHEN
- Toughness critical (<15%) AND `num_nearby >= 3` — about to die
- Health low (<35%) AND `num_nearby >= 2`
- Ally downed (`target_ally_needs_aid`, `need_type == "knocked_down"`, distance < 20m, `num_nearby >= 2`)
- Overwhelmed (`num_nearby >= 7` AND `toughness_pct < 0.40`)

### DON'T USE WHEN
- No immediate danger (toughness > 60%, few enemies)
- Ally downed too far (>20m) — stealth expires en route
- Teammates already overwhelmed and bot can't resolve the situation — dumps aggro on team

### PROPOSED BOT RULES
```
IF toughness_pct < 0.15 AND num_nearby >= 3 THEN activate (CRITICAL)
IF health_pct < 0.35 AND num_nearby >= 2 THEN activate (HIGH)
IF target_ally_needs_aid AND ally_distance < 20 AND num_nearby >= 2 THEN activate (HIGH)
IF num_nearby >= 7 AND toughness_pct < 0.40 THEN activate (MEDIUM)
DEFAULT: do not activate
```
**Confidence:** HIGH — community: "save for emergencies."

---

## Grenades (Tier 3 — not yet implemented)

| Grenade | USE WHEN | DON'T USE WHEN | Confidence |
|---------|----------|----------------|------------|
| Frag | `num_nearby >= 6` (horde) | Few scattered enemies | MEDIUM |
| Krak | Elite/monster visible | Only chaff | MEDIUM |
| Smoke | **Do not implement** — placement AI too hard, bad smoke is harmful | — | LOW |

---

## Implementation Notes

- VoC and Executioner's Stance share `veteran_combat_ability` template — need `class_tag` detection
- Infiltrate uses separate `veteran_stealth_combat_ability` template — can have its own branch
- Vanilla already has `_can_activate_veteran_ranger_ability` (elite/special check) — correct for Executioner's only

## Sources

- [Executioner's Stance — GamesLantern](https://darktide.gameslantern.com/abilities/executioners-stance)
- [Voice of Command — GamesLantern](https://darktide.gameslantern.com/abilities/voice-of-command)
- [Infiltrate — GamesLantern](https://darktide.gameslantern.com/abilities/infiltrate)
- [Steam: Veteran Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3094038976)
- [Steam: How to Build Executioner's Stance](https://steamcommunity.com/app/1361210/discussions/0/4633734182370048057/)
- [Steam: Frag or Krak?](https://steamcommunity.com/app/1361210/discussions/0/3878219832281403900/)
- [Steam: State of Smoke Grenades](https://steamcommunity.com/app/1361210/discussions/0/3877095200007486037/)
- [Fatshark Forums: VoC with Duty and Honor](https://forums.fatsharkgames.com/t/veterans-voice-of-command-with-duty-and-honor-upgrade-is-overpowered-as-all-hell-and-breaks-the-game/85311)
