# Veteran — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.11.6. See bottom for links.

## Executioner's Stance (`veteran_ranger_stance`)

**Cooldown:** 30s | **Duration:** 6s base / 9s with Big Game Hunter (1.11) | **Role:** Ranged DPS burst vs elites/specials

> 1.11 shortened the Volley Fire window from the pre-Warband duration to 6s base. Big Game Hunter (talent: `veteran_combat_ability_outlined_kills_extends_duration`) extends to 9s when activated while an outlined target is present, AND re-extends on each outlined-kill via `add_internally_controlled_buff` (so chain kills keep refreshing the 9s window). Buff also grants `stun_immune`, `slowdown_immune`, `suppression_immune`, `uninterruptible` — fire freely without worrying about being staggered.

### USE WHEN
- Elite or special is current target AND `target_dist > 6` (vanilla Fatshark heuristic — proven for the 6s window)
- 2+ elites/specials visible — first kill must land within ~3s for the window to be worthwhile
- Monster visible with no melee pressure (`urgent_target_enemy` set, `num_nearby <= 2`)
- **Big Game Hunter detected** AND any single outlined target present — first kill extends to 9s, lower bar than base activation

### DON'T USE WHEN
- Surrounded by melee (`num_nearby > 5` and `target_enemy_type == "melee"`)
- No elite/special/monster visible — 6s is too short to wait for spawns
- Already in melee range of all threats — ranged buffs wasted
- Outlined target list is empty AND build has Big Game Hunter — wastes the 9s extension path; fire only when chain-kill is feasible

### PROPOSED BOT RULES
```
IF target has tag "special" or "elite" AND target_dist > 6 THEN activate (HIGH)
IF urgent_target_enemy AND num_nearby <= 2 THEN activate (HIGH)
IF has_special_rule("veteran_combat_ability_outlined_kills_extends_duration")
   AND outlined_targets_visible >= 1 THEN activate (MEDIUM)  -- BGH first-kill extends window
BLOCK IF num_nearby > 5 AND target_enemy_type == "melee"
BLOCK IF outlined_targets_visible == 0 AND target_kill_time_estimate > 3  -- 6s window will close before first kill
```
**Confidence:** HIGH for base activation; the BGH extension path is a new threshold and needs in-game validation.

### COOLDOWN MANAGEMENT
Aggressive — 30s is short. Use whenever elites present and a kill is achievable inside the 6s base window. The 9s BGH window changes this math: with chain-kill maintenance, a single activation can extend through 2-3 elite kills.

### Detection
- `has_special_rule("veteran_combat_ability_outlined_kills_extends_duration")` — Big Game Hunter present
- Outline visibility: query the perception system for `keywords.is_outlined` on visible enemies (the keyword Volley Fire applies in the stance prefab)

---

## Voice of Command (`veteran_squad_leader_stance`)

**Cooldown:** 40s (60s with revive talent) | **Role:** AoE stagger + toughness recovery

**Note:** Shares `veteran_combat_ability` template with Executioner's Stance. Needs `class_tag == "squad_leader"` detection to branch.

### USE WHEN
- Surrounded (`num_nearby >= 4`) — 2.5s heavy stagger in 9m radius
- Toughness below 50% with enemies nearby — instant full recovery
- Toughness below 25% with any enemies — emergency
- Ally downed within 9m (revive talent), or ally aid with enemies nearby

### DON'T USE WHEN
- No enemies within 9m — stagger hits nothing
- Full toughness, few enemies — save cooldown
- Enemies already staggered (shout doesn't re-stagger)

### PROPOSED BOT RULES
```
IF num_nearby >= 4 THEN activate
IF toughness_pct < 0.50 AND num_nearby >= 2 THEN activate
IF toughness_pct < 0.25 AND num_nearby >= 1 THEN activate
IF target_ally_needs_aid AND need_type == "knocked_down" AND ally_distance <= 9 THEN activate
IF target_ally_needs_aid AND ally_distance <= 9 AND num_nearby >= 1 THEN activate
BLOCK IF toughness_pct > 0.80 AND num_nearby <= 2
```
**Confidence:** HIGH — community consensus is "spam it." CD bumped to 40s in 1.11.0, so the tempo is slightly slower than the old guidance but the playstyle is the same.

**Current BetterBots note:** the shipped Voice of Command + Focus Target path also cares about tag ownership, not just whether an enemy is already tagged. BetterBots now allows one narrow override on an already-tagged elite/special so the Veteran can still claim `enemy_over_here_veteran` and apply the Focus Target debuff instead of silently yielding the tag forever.

---

## Infiltrate (`veteran_invisibility`)

**Cooldown:** 40s | **Role:** Emergency escape / clutch revive

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

## Grenades (Tier 3 — implemented)

| Grenade | USE WHEN | DON'T USE WHEN | Confidence |
|---------|----------|----------------|------------|
| Frag | Dense horde, or clustered elite/special pressure at safe throw range. Bleed lowers the commit threshold but is not the main reason to throw it. | Few scattered enemies, or target already inside close melee range | MEDIUM |
| Krak | Elite/monster visible at safe throw range | Only chaff, or target already inside close melee range | HIGH |
| Smoke | Ranged pressure or ally-aid window | Pure melee blobs, or bad sightline denial | MEDIUM |

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
