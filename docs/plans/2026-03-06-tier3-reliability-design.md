# Tier 3 Reliability + Heuristics Design (#3)

## Problem

Tier 3 item-based abilities have low reliability (force field ~13%, drone ~21%) due to timing mismatches in the item fallback state machine. Additionally, Tier 3 abilities use a coarse `enemies_in_proximity > 0` gate instead of the per-ability heuristic framework from #2.

## Scope

Two changes in one pass:

1. **Timing fix** — align `ITEM_SEQUENCE_PROFILES` delays with decompiled action durations
2. **Heuristic unification** — add per-ability heuristics for Tier 3 items, reusing the framework from #2

This is #3 reusing the heuristic framework from #2. Not a merged issue.

## Part 1: Timing Fixes

Values verified against decompiled weapon templates in `../Darktide-Source-Code/`.

### force_field (psyker_force_field variants)

Source: `force_field_weapon_template_generator.lua`

| Profile | Field | Current | Correct | Derivation |
|---------|-------|---------|---------|------------|
| `force_field_regular` | `followup_delay` | 0.12s | **1.2s** | 0.6s `buffer_time` + 0.6s `total_time` |
| `force_field_regular` | `unwield_delay` | 0.9s | **1.6s** | 1.2s action + 0.4s margin |
| `force_field_instant` | `followup_delay` | 0.12s | **0.12s** | 0.1s action, `dont_queue=true` — current is fine |
| `force_field_instant` | `unwield_delay` | 0.8s | **0.5s** | 0.1s action + 0.4s margin |

### drone (adamant_area_buff_drone)

Source: `drone_weapon_template_generator.lua`

| Profile | Field | Current | Correct | Derivation |
|---------|-------|---------|---------|------------|
| `drone_regular` | `followup_delay` | 0.24s | **1.9s** | 0.6s `buffer_time` + 1.3s `total_time` |
| `drone_regular` | `unwield_delay` | 1.0s | **2.3s** | 1.9s action + 0.4s margin |
| `drone_instant` | `followup_delay` | 0.1s | **0.1s** | `dont_queue=true`, instant — current is fine |
| `drone_instant` | `unwield_delay` | 0.9s | **1.1s** | 1.0s action + 0.1s margin |

### press_release (broker_ability_stimm_field)

Source: `broker_stimm_field.lua`

| Profile | Field | Current | Correct | Derivation |
|---------|-------|---------|---------|------------|
| `press_release` | `followup_delay` | 0.08s | **0.6s** | `place_time = 0.54s` + margin |
| `press_release` | `unwield_delay` | 0.35s | **0.7s** | 0.6s + unwield margin |

Note: stimm_field is DLC-blocked; verify in-game when available.

### channel (zealot_relic)

Already correct: `unwield_delay = 5.6s` matches `total_time = 5.5s` + margin. No changes needed.

## Part 2: Heuristic Unification

### Architecture

- Add `ITEM_HEURISTICS` table in `heuristics.lua` keyed by **ability name** (not template name)
- Unknown item abilities default to **`false`** (item abilities are expensive — no accidental activation)
- Remove zealot_relic special case from `item_fallback.lua:421` and `BetterBots.lua:211`
- Replace `enemies_in_proximity > 0` gate in `can_use_item_fallback()` with heuristic calls
- Expose a new `evaluate_item_heuristic(ability_name, unit, blackboard)` function

### New context fields in `build_context()`

| Field | Source | Notes |
|-------|--------|-------|
| `allies_in_coherency` | `ScriptUnit.extension(unit, "coherency_system"):in_coherence_units()` | Count only. Coherency range is 8m (`player_character_constants.lua:753`). Filter out Arbites dog (check breed). |
| `avg_ally_toughness_pct` | Iterate coherency allies, average `toughness_system:current_toughness_percent()` | 1.0 if no allies. |
| `corruption_pct` | `health_extension:permanent_damage_taken_percent()` or equivalent | For stimm_field. Real corruption, not a proxy. |

### Heuristic rules

#### `zealot_relic` (Bolstering Prayer)

Cooldown: 60s. Channel: 5.5s. Emits stagger pulse (talent-gated) + 50% self toughness/tick.

```
BLOCK IF allies_in_coherency == 0                              → "zealot_relic_block_no_allies"
BLOCK IF num_nearby >= 5 AND toughness_pct < 0.30              → "zealot_relic_block_overwhelmed"
ACTIVATE IF avg_ally_toughness < 0.40 AND allies >= 2
           AND num_nearby < 2                                   → "zealot_relic_team_low_toughness"
ACTIVATE IF toughness_pct < 0.25 AND num_nearby < 3             → "zealot_relic_self_critical"
HOLD                                                            → "zealot_relic_hold"
```

#### `psyker_force_field` (Telekine Shield, all 3 variants)

Cooldown: 45s (35s improved). Deployable shield. Dome: 25s duration, no aiming.

```
BLOCK IF num_nearby == 0 AND NOT target_enemy                  → "force_field_block_no_threats"
BLOCK IF toughness_pct > 0.80                                  → "force_field_block_safe"
ACTIVATE IF num_nearby >= 3 AND toughness_pct < 0.40            → "force_field_pressure"
ACTIVATE IF target_ally_needs_aid                               → "force_field_ally_aid"
ACTIVATE IF target_enemy_type == "ranged" AND toughness < 0.60  → "force_field_ranged_pressure"
HOLD                                                            → "force_field_hold"
```

Note: ranged trigger has no `num_nearby` gate — ranged threats sit outside broadphase.

#### `adamant_area_buff_drone` (Nuncio-Aquila)

Cooldown: 60s. Zone: 20s, 7.5m radius. Debuffs enemies, buffs allies.

```
BLOCK IF allies_in_coherency == 0                              → "drone_block_no_allies"
BLOCK IF num_nearby <= 2                                        → "drone_block_low_value"
ACTIVATE IF allies_in_coherency >= 2 AND num_nearby >= 4        → "drone_team_horde"
ACTIVATE IF target_is_monster AND allies_in_coherency >= 1      → "drone_monster_fight"
ACTIVATE IF num_nearby >= 5 AND toughness_pct < 0.50            → "drone_overwhelmed"
HOLD                                                            → "drone_hold"
```

#### `broker_ability_stimm_field` (Stimm Field)

Cooldown: 60s. Zone: 3m radius, 20s. Heals corruption.

```
BLOCK IF num_nearby == 0                                        → "stimm_block_no_enemies"
BLOCK IF allies_in_coherency == 0                              → "stimm_block_no_allies"
ACTIVATE IF avg_ally_corruption > 0.30 AND allies >= 1          → "stimm_corruption_heal"
ACTIVATE IF target_ally_needs_aid AND num_nearby >= 2           → "stimm_ally_aid"
HOLD                                                            → "stimm_hold"
```

Uses real corruption detection. If corruption API proves inaccessible at runtime, disable stimm heuristic entirely (return false) rather than use a fake proxy.

## Implementation Steps

1. Fix timing values in `ITEM_SEQUENCE_PROFILES` (item_fallback.lua)
2. Add `allies_in_coherency`, `avg_ally_toughness_pct`, `corruption_pct` to `build_context()` (heuristics.lua)
3. Add 4 heuristic functions + `ITEM_HEURISTICS` table (heuristics.lua)
4. Add `evaluate_item_heuristic()` API (heuristics.lua)
5. Replace `enemies_in_proximity > 0` gate in `can_use_item_fallback()` (item_fallback.lua)
6. Remove zealot_relic special case from `BetterBots.lua:211` and `item_fallback.lua:421`
7. Add unit tests for all 4 heuristic functions (heuristics_spec.lua)
8. Add unit tests for timing value correctness (new or existing spec)
9. Run `make check`
10. In-game validation run (Tier 3 + heuristics combined)
11. Update VALIDATION_TRACKER.md, KNOWN_ISSUES.md

## Risks

- Coherency extension may not be available on all bot units (nil-guard needed)
- Corruption API needs runtime verification — `permanent_damage_taken_percent()` may not exist on bots
- Timing fixes are derived from decompiled source; actual engine behavior may differ slightly
- Stimm field is DLC-blocked — can write heuristic but cannot validate
