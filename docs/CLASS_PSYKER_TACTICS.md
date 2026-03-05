# Psyker — Bot Tactical Heuristics

> Sources: community guides, Steam discussions, decompiled source v1.10.7. See bottom for links.

## CRITICAL: Peril Awareness

Psyker is unique: all warp abilities share a Peril resource. **Without Peril tracking, bots WILL explode.**

**Access:** `unit_data_extension:read_component("warp_charge").current_percentage` (0.0-1.0, critical at 0.97)

### Global Peril Budget

| Peril Range | Bot Behavior |
|-------------|-------------|
| 0-30% | Free to use any warp ability. Low value for Venting Shriek. |
| 30-50% | Normal. All abilities available. Optimal Scrier's Gaze activation. |
| 50-75% | Moderate caution. Brain Burst/Chain Lightning OK if threat justifies. |
| 75-85% | Shriek-only zone (maximizes vent value). No other warp abilities. |
| 85-97% | Danger. ONLY Venting Shriek or melee. |
| 97%+ | Critical. NO warp abilities. Vent or wait. |

---

## Venting Shriek (`psyker_shout`)

**Cooldown:** 30s | **Role:** AoE stagger + Peril vent

### USE WHEN
- High Peril (>= 80%) AND `num_nearby >= 1` — primary Peril management tool
- Surrounded (`num_nearby >= 3`) — AoE knockdown
- Toughness critical (<20%) AND `num_nearby >= 1` — defensive panic
- Ally being disabled (`priority_target_enemy`) within 15m — stagger goes through walls

### DON'T USE WHEN
- No enemies nearby
- Peril < 30% AND few enemies AND toughness OK — low value

### PROPOSED BOT RULES
```
IF peril_pct >= 0.80 AND num_nearby >= 1 THEN activate
IF num_nearby >= 3 THEN activate
IF toughness_pct < 0.20 AND num_nearby >= 1 THEN activate
IF priority_target_enemy AND dist < 15 THEN activate
BLOCK IF num_nearby == 0
BLOCK IF peril_pct < 0.30 AND num_nearby < 3 AND toughness_pct > 0.50
```
**Confidence:** HIGH

---

## Scrier's Gaze (`psyker_stance`)

**Cooldown:** 25s (starts after buff expires) | **Role:** Damage burst stance

### USE WHEN
- Elite/monster visible (`opportunity_target_enemy` or `urgent_target_enemy`)
- Peril between 40-85% — activation vents 50%, too low wastes vent, too high ends stance immediately
- `challenge_rating_sum >= 6.0` — significant threat justifies stance
- Health > 25% — stance builds Peril, risky when low

### DON'T USE WHEN
- Peril < 20% — wastes the 50% vent
- Peril > 90% — stance will end almost immediately (100% terminates it)
- No enemies — wasted duration
- Health < 25% — explosion risk

### PROPOSED BOT RULES
```
IF (opportunity_target OR urgent_target) AND peril_pct >= 0.40 AND peril_pct <= 0.85
   AND health_pct > 0.25 THEN activate
IF challenge_rating_sum >= 6.0 AND peril_pct >= 0.40 AND peril_pct <= 0.85 THEN activate
BLOCK IF peril_pct < 0.20 OR peril_pct > 0.90
BLOCK IF num_nearby == 0
BLOCK IF health_pct < 0.25
```
**Confidence:** MEDIUM — Peril boundaries are build-dependent.

---

## Telekine Shield (`psyker_force_field`)

**Cooldown:** 45s | **Role:** Deployable shield (Tier 3 item-based, ~13% reliability)

### USE WHEN
- `num_nearby >= 3 AND toughness_pct < 0.40` — under pressure
- Ally needs aid AND `num_nearby >= 2` — protect downed ally
- `target_enemy_type == "ranged" AND num_nearby >= 2` — ranged fire

### DON'T USE WHEN
- No enemies
- Toughness > 80% — not needed

**Note:** Dome variant simpler for bots (no aiming). Low implementation priority given Tier 3 reliability.

**Confidence:** LOW (implementation), HIGH (tactical use cases)

---

## Blitz (Tier 3 — not yet implemented)

| Blitz | USE WHEN | DON'T USE WHEN | Key constraint |
|-------|----------|----------------|----------------|
| Brain Burst | Special/elite at >8m, `peril_pct < 0.75` | `peril_pct >= 0.80`, surrounded (`num_nearby >= 3`), close range (<5m) | 3s charge time = vulnerable |
| Assail | Freely — 10 charges, 3s regen. Special at any range. | Charges < 2, carapace armor | Most forgiving blitz |
| Chain Lightning | `num_nearby >= 4` (horde CC), `peril_pct < 0.70` | `peril_pct >= 0.85`, single target | Best AoE CC in game |

---

## Sources

- [Venting Shriek — GamesLantern](https://darktide.gameslantern.com/abilities/venting-shriek)
- [Scrier's Gaze — GamesLantern](https://darktide.gameslantern.com/abilities/scriers-gaze)
- [Telekine Shield — GamesLantern](https://darktide.gameslantern.com/abilities/telekine-shield)
- [Steam: Psyker Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3094028505)
- [Steam: How to Properly Play Psyker](https://steamcommunity.com/app/1361210/discussions/0/3716062978740663689/)
- [Fatshark Forums: Psyker Peril Management](https://forums.fatsharkgames.com/t/psykers-peril-management/78364)
- [TheGamer: Psyker Tips](https://www.thegamer.com/warhammer-40000-darktide-psyker-psykinetic-class-guide/)
