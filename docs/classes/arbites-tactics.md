# Arbites — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.11.6. See bottom for links.

## Castigator's Stance (`adamant_stance`)

**Cooldown:** 50s | **Duration:** 10s | **Role:** Combat stance — toughness refill, 80% DR, melee engagement opener

### USE WHEN
- Toughness below 30% — refills toughness completely (defensive)
- Surrounded: `num_nearby >= 3 AND toughness_pct < 0.60`
- Monster engaged at close range (<8m) and bot is aggro target
- 2+ elites in proximity AND `toughness_pct < 0.50`
- **Sustained melee engagement starting**: `enemies_in_melee_range >= 2 AND target_enemy_type == "melee"` — community top play fires Castigator's Stance proactively as a combat opener, not only as a panic button. The 10s window aligns with a typical melee skirmish.

### DON'T USE WHEN
- High toughness with no enemies — wasteful on 50s CD
- Only ranged/distant enemies — DR less needed, sprint disabled hurts repositioning
- Need to reposition urgently — stance disables sprint

### PROPOSED BOT RULES
```
IF toughness_pct < 0.30 THEN activate (HIGH)
IF num_nearby >= 3 AND toughness_pct < 0.60 THEN activate (MEDIUM)
IF target has "monster" AND target_dist < 8 THEN activate (MEDIUM)
IF count_elites >= 2 AND toughness_pct < 0.50 THEN activate (MEDIUM)
IF enemies_in_melee_range >= 2 AND target_enemy_type == "melee"
   AND NOT recently_used_stance THEN activate (MEDIUM)  -- proactive opener
BLOCK IF toughness_pct > 0.70 AND num_nearby == 0
BLOCK IF sprint_required_to_reach_ally
```
**Confidence:** HIGH — combat-stance framing replaces the old "defensive panic button" rule. Community 2026 builds describe firing Castigator's Stance on any sustained melee skirmish; the 50s CD comfortably covers two engagements per minute when CDR from Execution Order is active.

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

## Talent tree archetypes — Investigator vs Vanquisher

Source: `talent_settings_adamant.lua` + `adamant_talents.lua` (1.11.6). The community names "Investigator" and "Vanquisher" do not appear in the decompiled source — the engine identifies the two trees by keystone name. Detect via `talent_extension:has_talent("…")` against the keystone slot.

### Terminus Warrant tree (community: "Investigator")

| Keystone / node | Effect |
|---|---|
| `adamant_terminus_warrant` | 20-stack stamping buff (15s): per stack +15% melee damage, +15% fire rate, +15% melee rending. Stacks from tagging/killing specific targets. |
| `adamant_terminus_warrant_cdr` | Sub-node: +33% ability CDR per proc, 12s window |
| `adamant_terminus_warrant_support` | Sub-node: ally toughness effect on activation |
| `adamant_forceful` | 10-stack melee impact + strength stacking buff (5s/stack); sub-nodes add ranged_attack_speed, reload_speed, toughness_regen |

**Playstyle:** sustained melee engagement, stagger-loop maintenance. Pairs with Castigator's Stance (Castigator's CDR comes from this tree when `_cdr` sub-node is taken).

**Bot implication:** if profile has `adamant_terminus_warrant`, raise melee-engagement priority — the stack pool drops without sustained hits. If `_cdr` sub-node is also present, expect ~33s effective Castigator's Stance CD; the proactive-opener rule above becomes more important.

### Exterminator tree (community: "Vanquisher")

| Keystone / node | Effect |
|---|---|
| `adamant_exterminator` | 10-stack ramping buff (12s): per stack +4% damage, +4% boss_damage, +4% companion_damage, +10% ammo, +10% toughness, +10% stamina. 0.25s internal cooldown. |
| `adamant_execution_order` | Sub-node: 8s stacking buff with +10% crit chance, +10% rending, +10% damage, +15% toughness, +10% attack speed; 50% CDR per proc |
| `adamant_execution_order_cdr` | Sub-node: +50% CDR for 3s on Execution Order proc |
| `adamant_execution_order_monster_debuff` | Sub-node: tagged monster takes 25% less damage on incoming (a debuff) |

**Playstyle:** elite-density burst, tag-prioritized targeting, ability spam via Execution Order CDR loop.

**Bot implication:** if profile has `adamant_exterminator` + `adamant_execution_order`, the **condemned/tagged elite** is the highest-priority target — attacking it feeds the CDR loop. Break the Line CD effectively drops below 10s with active Execution Order. The bot's existing tag-priority logic already prefers tagged enemies, so no new module needed; just verify the existing priority survives sub-node detection.

### Shared (both trees)

- Break the Line passive: `cooldown_elite = 1` per elite hit + `cooldown_reduction = 0.5` aggregate (engagement-rich fights run BtL at 10-15s real CD)
- Castigator's Stance has both `_elite_kills_stack_damage` and `_ammo_from_reserve` sub-nodes accessible from either tree

### Cyber-Mastiff (`adamant_companion`)

Source-level: `adamant_companion` talent activates the Cyber-Mastiff. It does NOT appear in `adamant_lone_wolf` builds (Lone Wolf is the alternate top-of-tree pick). Detect via `has_talent("adamant_lone_wolf")` to skip drone activation logic for that subset of builds.

---

## Blitz (Tier 3 — not yet implemented)

| Blitz | USE WHEN | Key note | Confidence |
|-------|----------|----------|------------|
| Whistle | Special/elite visible, companion alive — direct dog to target | Only blitz with `ability_template`. Community top pick for Execution Order builds; AI reliability is the ceiling. | MEDIUM |
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
