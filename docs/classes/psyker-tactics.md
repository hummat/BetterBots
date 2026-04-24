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
- High Peril AND `num_nearby >= 1` — primary Peril management tool
  - base shout builds: roughly `>= 75-85%` depending on preset
  - `psyker_damage_based_on_warp_charge` / `psyker_warp_glass_cannon`: hold a bit longer and prefer `>= 85-95%`
  - `psyker_shout_vent_warp_charge`: hold later again so Shriek behaves like the vent valve
- Surrounded (`num_nearby >= 3`) — AoE knockdown
- Toughness critical (<20%) AND `num_nearby >= 1` — defensive panic
- Ally being disabled (`priority_target_enemy`) within 15m — stagger goes through walls

### DON'T USE WHEN
- No enemies nearby
- Peril < 30% AND few enemies AND toughness OK — low value

### PROPOSED BOT RULES
```
IF peril_pct >= dynamic_shout_threshold AND num_nearby >= 1 THEN activate
IF num_nearby >= 3 THEN activate
IF toughness_pct < 0.20 AND num_nearby >= 1 THEN activate
IF priority_target_enemy AND dist < 15 THEN activate
BLOCK IF num_nearby == 0
BLOCK IF preserve_peril_talent AND peril_pct >= base_high_peril THEN hold
BLOCK IF peril_pct < 0.30 AND num_nearby < 3 AND toughness_pct > 0.50
```
**Confidence:** HIGH

**Current BetterBots note:** the shipped Warp Siphon / warp-charge damage path is talent-aware. BetterBots raises the high-peril trigger by `+0.10` when warp-charge damage talents are present, adds another `+0.05` with `psyker_shout_vent_warp_charge`, and caps the result at `95%` so Shriek vents later instead of spending peril early.

---

## Scrier's Gaze (`psyker_overcharge_stance`)

**Cooldown:** 25s (starts after buff expires) | **Role:** Damage burst stance

### USE WHEN
- Elite/monster visible (`opportunity_target_enemy` or `urgent_target_enemy`)
- Peril between 40-85% — activation vents 50%, too low wastes vent, too high ends stance immediately
- `challenge_rating_sum >= 6.0` — significant threat justifies stance
- Health > 25% — stance builds Peril, risky when low
- On aggressive Scrier builds (`psyker_new_mark_passive` / `psyker_overcharge_weakspot_kill_bonuses`), earlier combat windows are valid — the current bot rule lowers the threat gate by 1.0 CR and the density gate by 1 enemy
- On reduced-peril / Warp Unbound variants (`psyker_overcharge_reduced_warp_charge`, `psyker_overcharge_stance_infinite_casting`), the bot can hold stance activation deeper into the upper Peril band

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
Build-aware follow-up now shipped in BetterBots:
```
IF has(psyker_new_mark_passive) OR has(psyker_overcharge_weakspot_kill_bonuses)
   THEN threat_cr -= 1.0 (floor 2.0), combat_density -= 1 (floor 1)
IF has(psyker_overcharge_reduced_warp_charge)
   THEN target_peril_ceiling = 0.90, block_peril_ceiling = 0.95
IF has(psyker_overcharge_stance_infinite_casting)
   THEN target_peril_ceiling = 0.95, block_peril_ceiling = 0.97
```
**Confidence:** MEDIUM — build-aware first batch shipped; deeper vent/casting-state logic still remains open.

---

## Telekine Shield (`psyker_force_field`)

**Cooldown:** 45s | **Role:** Deployable shield (Tier 3 item-based, 100% reliability post-fix)

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

## Blitz (Tier 3 — implemented)

| Blitz | USE WHEN | DON'T USE WHEN | Key constraint |
|-------|----------|----------------|----------------|
| Brain Burst | Special/elite at >8m, `peril_pct < 0.75` | `peril_pct >= 0.80`, surrounded (`num_nearby >= 3`), close range (<5m) | 3s charge time = vulnerable |
| Assail | Specials / explicit priority targets at any range; crowd softening only while charge-rich | Carapace armor, low remaining shard count for crowd use | Fast burst vs horde, aimed shard vs specials |
| Chain Lightning | `num_nearby >= 4` (horde CC), `peril_pct < 0.70` | `peril_pct >= 0.85`, single target | Best AoE CC in game |

**Current BetterBots note:** all three Psyker blitzes are implemented. Brain Burst now has a dedicated long-charge rule instead of the generic priority-target dispatcher: it blocks at high Peril, blocks under close melee pressure on non-hard targets, and keeps its hard-target bias for super-armor / monsters. Its precision target is seeded from the bot perception priority slots rather than blindly inheriting `target_enemy`. When `psyker_smite_on_hit` is equipped, BetterBots also de-prioritizes manual Brain Burst on ordinary elite/special targets that the proc already covers, while preserving bombers, super-armor, monsters, and explicit long-range priority targets. Assail now uses that same precision-target ordering, favors the aimed shard path on specials, and only starts a crowd burst while the bot still has a substantial shard reserve; once committed, it rapidly spends that reserve unless Peril crosses the shared configurable warp peril stop line.

**Current staff note:** explicit close-range ranged-hold support exists for Purgatus (`forcestaff_p2_m1`) and Surge / electrokinetic (`forcestaff_p3_m1`). Voidblast (`forcestaff_p1_m1`) now also has a bot-only charged anchor on the live `action_charge` path: once the charge starts, BetterBots locks one target-root anchor plus a short flat-velocity lead, keeps that anchor through mid-charge retarget churn, and aims directly at that anchor with vanilla-style straight-look vertical aim. It also forces the charged release path through `trigger_explosion` when the p1 charge path would otherwise fall back to plain `shoot_pressed`. Trauma / voidball (`forcestaff_p4_m1`) still uses the general ranged/melee logic.

---

## Sources

- [Venting Shriek — GamesLantern](https://darktide.gameslantern.com/abilities/venting-shriek)
- [Scrier's Gaze — GamesLantern](https://darktide.gameslantern.com/abilities/scriers-gaze)
- [Telekine Shield — GamesLantern](https://darktide.gameslantern.com/abilities/telekine-shield)
- [Steam: Psyker Talents & Mechanics 1.10.x](https://steamcommunity.com/sharedfiles/filedetails/?id=3094028505)
- [Steam: How to Properly Play Psyker](https://steamcommunity.com/app/1361210/discussions/0/3716062978740663689/)
- [Fatshark Forums: Psyker Peril Management](https://forums.fatsharkgames.com/t/psykers-peril-management/78364)
- [TheGamer: Psyker Tips](https://www.thegamer.com/warhammer-40000-darktide-psyker-psykinetic-class-guide/)
