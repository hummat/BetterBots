# Tier 3 Reliability + Heuristics Design (#3)

## Problem

Tier 3 item-based abilities have low reliability (force field ~13%, drone ~21%) due to timing mismatches in the item fallback state machine. Additionally, Tier 3 abilities use a coarse `enemies_in_proximity > 0` gate instead of the per-ability heuristic framework from #2.

## Scope

Two changes, validated **separately**:

1. **Timing fix** — align `ITEM_SEQUENCE_PROFILES` delays with decompiled action durations. Validate first (measure consume-rate improvement).
2. **Heuristic unification** — add per-ability heuristics for Tier 3 items, reusing the framework from #2. Validate second (measure decision quality).

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
- Expose a new `evaluate_item_heuristic(ability_name, context)` function
- Update `can_use_item_fallback()` signature to accept `blackboard` parameter
- Update `debug.lua` `/bb_decide` to pass `blackboard` and display heuristic rule names

### New context fields in `build_context()`

All computed in a single coherency iteration pass.

| Field | Source | Notes |
|-------|--------|-------|
| `allies_in_coherency` | `ScriptUnit.extension(unit, "coherency_system"):in_coherence_units()` | Count only. Coherency range is 8m (`player_character_constants.lua:753`). Filter out Arbites dog (check breed). |
| `avg_ally_toughness_pct` | Iterate coherency allies, average `toughness_system:current_toughness_percent()` | 1.0 if no allies. |
| `max_ally_corruption_pct` | Iterate coherency allies, max `health_system:permanent_damage_taken_percent()` | 0 if no allies. Max is the right aggregator for a 3m cleanse field — triggers when *any* ally needs cleansing. |

### Heuristic rules

#### `zealot_relic` (Bolstering Prayer)

Cooldown: 60s. Channel: 5.5s. Emits stagger pulse (talent-gated) + 50% self toughness/tick.

Self-cast is valid even without allies (emergency self-heal).

```
BLOCK IF num_nearby >= 5 AND toughness_pct < 0.30              → "zealot_relic_block_overwhelmed"
ACTIVATE IF avg_ally_toughness < 0.40 AND allies >= 2
           AND num_nearby < 2                                   → "zealot_relic_team_low_toughness"
ACTIVATE IF toughness_pct < 0.25 AND num_nearby < 3             → "zealot_relic_self_critical"
BLOCK IF allies_in_coherency == 0 AND toughness_pct >= 0.25     → "zealot_relic_block_no_allies"
HOLD                                                            → "zealot_relic_hold"
```

Note: `no_allies` block is ordered AFTER `self_critical` so solo self-heal is reachable. When the bot has no allies AND toughness is fine, there's no reason to channel.

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
ACTIVATE IF max_ally_corruption_pct > 0.30 AND allies >= 1      → "stimm_corruption_heal"
ACTIVATE IF target_ally_needs_aid AND num_nearby >= 2           → "stimm_ally_aid"
HOLD                                                            → "stimm_hold"
```

Uses `max_ally_corruption_pct` (not avg) — triggers when any single ally needs cleansing. If corruption API proves inaccessible at runtime, disable stimm heuristic entirely (return false) rather than use a fake proxy.

## Plumbing changes

### `can_use_item_fallback()` signature change

Current: `can_use_item_fallback(unit, ability_extension, ability_name)`
New: `can_use_item_fallback(unit, ability_extension, ability_name, blackboard)`

Call sites to update:
- `item_fallback.lua:451` (`try_queue_item` — already has `blackboard` in scope)
- `debug.lua:357` (`/bb_decide` — has `blackboard` from `_bot_blackboard(unit)` at line 353)

### `/bb_decide` debug output

Current (debug.lua:357-359):
```lua
can_activate = _can_use_item_fallback(unit, ability_extension, ability_name)
rule = can_activate and "item_fallback_ready" or "item_fallback_blocked"
context = _build_context(unit, blackboard)
```

New: call with blackboard, capture rule from heuristic, display it:
```lua
can_activate, rule = _can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
rule = rule or (can_activate and "item_fallback_ready" or "item_fallback_blocked")
context = _build_context(unit, blackboard)
```

## Implementation Steps

1. Fix timing values in `ITEM_SEQUENCE_PROFILES` (item_fallback.lua)
2. **Validate timing fix in-game** (measure consume-rate improvement before changing gating)
3. Add `allies_in_coherency`, `avg_ally_toughness_pct`, `max_ally_corruption_pct` to `build_context()` and `make_context()` (heuristics.lua, test_helper.lua)
4. Add 4 heuristic functions + `ITEM_HEURISTICS` table + `evaluate_item_heuristic()` (heuristics.lua)
5. Replace `enemies_in_proximity > 0` gate in `can_use_item_fallback()` (item_fallback.lua)
6. Update `can_use_item_fallback()` signature — add `blackboard` param, update call sites in `try_queue_item` and `debug.lua` `/bb_decide`
7. Remove zealot_relic special case from `BetterBots.lua:211`
8. Add unit tests for all 4 heuristic functions (heuristics_spec.lua)
9. Run `make check`
10. **Validate heuristics in-game** (separate run from timing validation)
11. Update VALIDATION_TRACKER.md, KNOWN_ISSUES.md

## Risks

- Coherency extension may not be available on all bot units (nil-guard needed)
- Corruption API needs runtime verification — `permanent_damage_taken_percent()` may not exist on bots
- Timing fixes are derived from decompiled source; actual engine behavior may differ slightly
- Stimm field is DLC-blocked — can write heuristic but cannot validate
