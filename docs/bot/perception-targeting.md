# Bot Perception and Target Selection Reference

> Source: Aussiemon/Darktide-Source-Code (decompiled, v1.10.7)
> Date: 2026-03-05

This document describes how Darktide bots perceive enemies and select targets. All values come from the decompiled source unless noted otherwise.

---

## 1. Perception Update Loop

**Source:** `scripts/extension_systems/perception/bot_perception_extension.lua`

### Update Cadence

The perception system has two update phases per tick:

1. **`pre_update`** -- Forces priority perception updates for enemies within **0.75m** (`FORCED_PRIO_UPDATE_RANGE`) of the bot. If an enemy is this close and moving (`velocity > 0`), it gets registered for immediate perception + slot updates. This ensures melee-range enemies are never stale.

2. **`update`** -- Runs every tick but only for bot-controlled units (skipped if `player:is_human_controlled()`). Calls three sub-updates:
   - `_update_target_enemy` -- target scoring and selection
   - `_update_target_ally` -- ally aid/follow selection
   - `_update_target_level_unit` -- health station tracking

### Target Enemy Reevaluation

Full target reevaluation (scoring all valid targets) happens only when:
- The current target is dead/nil, **OR**
- The reevaluation timer has expired: `t > target_enemy_reevaluation_t`

The reevaluation timer is set to **t + 0.3s** after each full evaluation (source: `bot_target_selection_template.lua:85`). Between reevaluations, the bot rescores only its current target (to update melee/ranged preference).

### What Gets Tracked

The bot iterates over `side.ai_target_units` -- all enemy units registered as targetable on the opposing side. A target is valid if:
- `breed.not_bot_target` is **false** (vanilla: only `chaos_poxwalker_bomber` sets this true; **BetterBots #34 patches this to nil** and suppresses unsafe poxburster targets near the bot/human players instead)
- The enemy is in `aggroed_minion_target_units` (has been aggroed/alerted), **OR** is a player breed (PvP-relevant, not typical gameplay)

### Blackboard Output

The perception system writes to the blackboard `perception` component:

| Field | Type | Description |
|-------|------|-------------|
| `target_enemy` | Unit | Best overall target (melee or ranged, whichever scored higher) |
| `target_enemy_distance` | number | Distance to `target_enemy` in meters |
| `target_enemy_type` | string | `"melee"`, `"ranged"`, or `"none"` |
| `target_enemy_reevaluation_t` | number | Next time full scoring runs |
| `urgent_target_enemy` | Unit | Best target with monster tag (if no enemies in proximity) |
| `priority_target_enemy` | Unit | Enemy disabling an ally (pouncer/trapper/etc.) |
| `opportunity_target_enemy` | Unit | Best special/player target |
| `target_ally` | Unit | Ally to follow or aid |
| `target_ally_distance` | number | Distance to target ally |
| `target_ally_needs_aid` | boolean | Ally needs rescue/healing |
| `target_ally_need_type` | string | `"knocked_down"`, `"ledge"`, `"netted"`, `"hogtied"`, `"in_need_of_heal"`, etc. |
| `aggressive_mode` | boolean | If true, bot prefers engaging over following |
| `aggro_target_enemy` | Unit | Currently unused beyond init (reserved) |
| `force_aid` | boolean | Overrides threat check for ally aid |

---

## 2. Target Selection Scoring

**Source:** `scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template.lua`, `scripts/utilities/bot_target_selection.lua`

### Overview

Each valid target gets two scores: **melee** and **ranged**. The higher score wins and determines both the target and the engagement type.

```
total_score = common_score + mode_specific_score
```

### Common Score (applied to both melee and ranged)

| Component | Max Weight | Condition | Source |
|-----------|-----------|-----------|--------|
| **Opportunity** | 1.0 | Target has `special` tag or is a player breed. Subject to reaction time delay. | `DEFAULT_OPPORTUNITY_WEIGHT = 1` |
| **Priority** | 4.0 | Target is disabling an ally (pouncer/netgunner/etc.). Ramps from 0 to `4.0` over 2 seconds. | `DEFAULT_PRIORITY_WEIGHT = 4`, `TIME_UNTIL_MAX_PRIORITY_WEIGHT = 2` |
| **Monster** | 2.0 | Target has `monster` tag **AND** bot has 0 enemies in proximity. Subject to reaction time (0.2-0.65s). | `DEFAULT_MONSTER_WEIGHT = 2` |
| **Current target** | 0.2 | Target is the bot's existing `target_enemy` (stickiness bonus). | `DEFAULT_CURRENT_TARGET_WEIGHT = 0.2` |

### Melee-Specific Score

| Component | Max Weight | Formula | Notes |
|-----------|-----------|---------|-------|
| **Gestalt** | 5.0 (default) | Breed-specific weight from gestalt table | See [Gestalt Weights](#3-gestalt-weights). Overrides for `killshot` gestalt penalize heavy armor. |
| **Slot** | 1.0 | `1.0` if enemy has a slot targeting this bot; `0.8` if slot targets the bot's ally | Only applies to breeds with `slot_template` |
| **Distance** | 3.0 | `3.0 * ilerp(64, 9, dist_sq)` | Max at 3m, zero at 8m. Strongly prefers close enemies. |

**Melee distance formula detail:**
- `MELEE_DISTANCE_MAX_WEIGHT = 3` (distance for max weight, i.e., 3m)
- `MELEE_DISTANCE_NO_WEIGHT = 8` (distance for zero weight, i.e., 8m)
- Weight = `3.0 * ilerp(8^2, 3^2, distance_sq)` -- linear interpolation, 0 at 8m+, max at 3m-

### Ranged-Specific Score

| Component | Max Weight | Formula | Notes |
|-----------|-----------|---------|-------|
| **Gestalt** | 5.0 (default) | Breed-specific weight from gestalt table | Same system as melee. `killshot` penalizes heavy armor (-5). |
| **Distance** | 1.0 | `1.0 * ilerp(16, 36, dist_sq)` | Max at 6m, zero at 4m. Prefers targets at medium range. |
| **Line of sight** | 1.0 | `1.0` if bot has LoS to target, else `0` | Checked via minion perception extension |

**Ranged distance formula detail:**
- `RANGED_DISTANCE_MAX_WEIGHT = 6` (6m for max weight)
- `RANGED_DISTANCE_NO_WEIGHT = 4` (4m for zero weight)
- Weight = `1.0 * ilerp(4^2, 6^2, distance_sq)` -- prefers 6m+, zero below 4m

### Melee vs Ranged Decision

The bot picks whichever mode has the higher final score. The `target_enemy_type` blackboard field records `"melee"` or `"ranged"`. This drives downstream behavior (weapon switching, BT node selection).

Key implication: melee scoring heavily favors close targets (up to 3.0 distance weight) while ranged only gets 1.0 for distance, so **close enemies almost always trigger melee preference**. Ranged wins when targets are at medium distance with LoS and the gestalt doesn't penalize them.

### Target Classification Flags

During scoring, targets are also classified:

| Flag | Condition | Effect |
|------|-----------|--------|
| `is_opportunity_target` | `special` tag or player breed | Written to `opportunity_target_enemy` |
| `is_priority_target` | In bot_group's priority targets (disabling an ally) | Written to `priority_target_enemy` |
| `is_urgent_target` | `monster` tag (from `monster_weight`) | Written to `urgent_target_enemy` |

---

## 3. Gestalt Weights

**Source:** `scripts/settings/bot/bot_gestalt_target_selection_weights.lua`

Gestalts are combat stances assigned per-bot at spawn. They affect breed-specific target prioritization.

### Available Gestalts

Defined in `bot_settings.behavior_gestalts`: `"none"`, `"killshot"`, `"linesman"`

### Weight Tables

Default breed weight (for any breed not explicitly listed): **5.0** (`DEFAULT_BREED_WEIGHT`)

**Note:** The `settings()` function is a pass-through in the decompiled source. The engine likely sets up `__index` metatables so unlisted breeds fall back to `DEFAULT_BREED_WEIGHT = 5`. This is confirmed by the code exporting `DEFAULT_BREED_WEIGHT` and the `killshot` table only containing overrides.

| Gestalt | Breed Overrides | Effect |
|---------|----------------|--------|
| `none` | (empty table) | All breeds weighted at 5.0 (default) |
| `killshot` | `chaos_ogryn_bulwark = -5`, `chaos_ogryn_executor = -5`, `renegade_executor = -5` | Avoids heavily armored melee elites. All other breeds at 5.0. |
| `linesman` | (defined in enum but no weight table in decompiled source) | Likely defaults to 5.0 for all |

### Gestalt Assignment

Set in `BotBehaviorExtension._init_blackboard_components` from `extension_init_data.optional_gestalts`. Default is `none` for both melee and ranged if no gestalts are provided.

### Ranged Target Filtering

`BotTargetSelection.allowed_ranged_target` checks if the ranged gestalt weight for a breed is `-math.huge`. If so, the target is completely disallowed for ranged engagement. This is a hard filter applied by the shoot action.

---

## 4. Threat Assessment

### Threat Accumulation

**Source:** `scripts/utilities/threat.lua`, `bot_perception_extension.lua`

Threat is generated when enemies take damage:

```
Threat.add_threat(attacked_unit, attacking_unit, damage_dealt, damage_absorbed, damage_profile, attack_type)
```

The formula:
```lua
damage_threat = damage_dealt * (damage_profile.threat_multiplier or 1)
absorbed_threat = damage_absorbed * (damage_profile.absorbed_damage_threat_multiplier or 1)
total_threat_to_add = damage_threat + absorbed_threat
```

On the bot's perception extension, threat is accumulated per-unit:
```lua
new_threat = (current_threat or 0) + threat_to_add * breed.threat_config.threat_multiplier
threat = min(new_threat, breed.threat_config.max_threat)
```

### Threat Config (per-breed)

From `human_breed.lua` (the bot's breed):

| Parameter | Value | Description |
|-----------|-------|-------------|
| `max_threat` | 50 | Cap on accumulated threat per enemy |
| `threat_decay_per_second` | 5 | Threat decays linearly each tick |
| `threat_multiplier` | (not set, defaults to 1.0) | Multiplier on incoming threat |

Example from `renegade_melee_breed.lua` (enemy breed):

| Parameter | Value |
|-----------|-------|
| `max_threat` | 50 |
| `threat_decay_per_second` | 5 |
| `threat_multiplier` | 0.1 |

Note: The `threat_multiplier` on the bot's breed config (human_breed) is what matters for bot target selection. The enemy's threat_config governs how enemies accumulate threat *from the bot*, not the other way around.

### Threat Decay

Each tick, all threat values decay:
```lua
threat_units[unit] = max(threat - threat_decay_per_second * dt, 0)
-- Entries at 0 are removed next tick
```

If `threat_config.decay_disabled` is true, decay is skipped entirely.

### Threat Weight in Scoring

`BotTargetSelection.threat_weight` returns the raw accumulated threat value for a target (multiplied by `DEFAULT_THREAT_WEIGHT_MULTIPLIER = 1`). This contributes to the **ranged** score only (see `_calculate_ranged_score`).

**Wait -- correction:** Looking at the code again, `threat_units` is passed to `_calculate_ranged_score` but the actual `threat_weight` function is not called in the ranged score calculation in the decompiled template. The threat_units are passed through but the ranged score only uses gestalt + distance + LoS. Threat weight appears to be infrastructure that isn't wired into the current bot scoring template.

### AoE Threat Detection

**Source:** `scripts/utilities/attack/bot_aoe_threat.lua`

Provides geometric intersection tests for bots to detect and escape AoE danger zones. Three shapes:

| Shape | Function | Escape Logic |
|-------|----------|-------------|
| **Sphere** | `detect_sphere(...)` | Computes flat distance from center. If inside (dist < radius + bot_radius), calculates radial escape direction. Verifies escape path via nav mesh raycast. |
| **Cylinder** | `detect_cylinder(...)` | Uses `max(size.x, size.y)` as radius, `size.z` as half-height. Same radial escape as sphere. |
| **OOBB** | `detect_oobb(...)` | Oriented bounding box. Projects bot position into box-local space. Escapes perpendicular to the longest overlap axis (sideways from the box). Tries both directions, prefers one not in liquid. |

All escape paths are validated with `NavQueries.ray_can_go` (nav mesh raycasting) with `THREAT_NAV_MESH_ABOVE = 2`, `THREAT_NAV_MESH_BELOW = 2` tolerance.

These functions return an **escape direction vector** or `nil` if escape is impossible / not needed. They are called by the bot behavior tree's threat avoidance nodes (not directly by the perception system).

---

## 5. Bot Settings (Tuning Constants)

**Source:** `scripts/settings/bot/bot_settings.lua`

### Movement Epsilons

| Constant | Value | Description |
|----------|-------|-------------|
| `flat_move_to_epsilon` | 0.05 | Horizontal arrival threshold (meters) |
| `flat_move_to_previous_pos_epsilon` | 0.25 | Threshold for "moved from previous position" |
| `z_move_to_epsilon` | 0.3 | Vertical arrival threshold (meters) |

### Reaction Times

| Setting | Min | Max | Context |
|---------|-----|-----|---------|
| `opportunity_target_reaction_times.normal` | 10 | 20 | Frames/ticks before bot reacts to a special enemy. **These are very high values** suggesting seconds-scale delay (10-20s at 1Hz perception). |

Monster reaction time (hardcoded in `bot_target_selection.lua`):
- Min: **0.2s**, Max: **0.65s**

### Behavior Gestalts

Enum: `"none"`, `"killshot"`, `"linesman"`

### Blackboard Component Schema

The `blackboard_component_config` defines all typed fields for:
- `behavior` -- interaction units, gestalts, revive flags, destinations
- `follow` -- destination, teleport state, refresh flags
- `health_station` -- needs_health, queue position, proximity timer
- `melee` -- engage position, stop flag
- `perception` -- all target/ally fields (see blackboard table above)
- `pickup` -- ammo/health/mule pickup tracking with validity timers
- `ranged_obstructed_by_static` -- obstruction tracking
- `spawn` -- physics world reference

---

## 6. Proximity Counts (`enemies_in_proximity`)

**Source:** `bot_perception_extension.lua:94-96, 149-198`

### How It Works

`enemies_in_proximity()` returns a list of nearby aggroed enemies and their count. This is the data BetterBots uses as the generic ability trigger.

### Update Cadence

Updated inside `_update_target_enemy`, gated by a timer:
```lua
self._enemies_in_proximity_update_timer = t + 0.5 + 0.5 * math.random()
```
So it updates every **0.5 to 1.0 seconds** (randomized to prevent all bots updating simultaneously).

### Query Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `IN_PROXIMITY_DISTANCE` | **5** (meters) | Broadphase query radius |
| `MAX_PROXIMITY_ENEMIES` | **10** | Hard cap on tracked proximity enemies |

### Filtering

After the broadphase query, results are filtered:
1. **Must be in `ai_target_units`** -- registered as a valid enemy
2. **Must not have `breed.not_bot_target`** -- excludes poxwalker bombers
3. **Must be in `aggroed_minion_target_units`** -- must be aggroed (alerted)

Between update cycles, stale entries are removed if their unit leaves `aggroed_minion_target_units` (deaggro/death).

### Consumers

| System | Usage |
|--------|-------|
| `bt_bot_conditions.can_activate_ability` (vanilla) | Iterates proximity list, sums `challenge_rating` to decide if zealot_relic should activate (threshold: 1.75) |
| `bt_bot_conditions._is_there_threat_to_aid` | Checks if any proximity enemy is targeting the bot (decides if bot should abandon ally aid) |
| `bt_bot_melee_action` | Stores `num_enemies_in_proximity` in scratchpad. Used for: attack selection (outnumbered at >1, massively at >3), push decision, dodge decision |
| `BotTargetSelection.monster_weight` | If `num_enemies_in_proximity > 0`, monster weight returns 0 (bot won't chase monsters while surrounded) |
| `_calculate_ally_need_type` | If bot has `>= 1` enemy in proximity, it won't aid other bots (`MAX_ENEMIES_IN_PROXIMITY_TO_AID_BOT = 1`) |
| **BetterBots** | Uses `num_nearby > 0` as the generic ability trigger heuristic |

### Challenge Rating Reference

The `can_activate_ability` condition for `zealot_relic` sums challenge ratings within the proximity list (5m radius) and activates when `total >= 1.75`. Targeting multiplier: `1.25x` if the enemy is targeting the bot.

| Breed | Challenge Rating | Category |
|-------|-----------------|----------|
| chaos_poxwalker | 0.4 | Trash |
| chaos_newly_infected | 0.4 | Trash |
| chaos_mutated_poxwalker | 0.4 | Trash |
| chaos_lesser_mutated_poxwalker | 0.4 | Trash |
| chaos_armored_infected | 0.4 | Trash |
| chaos_mutator_ritualist | 0.5 | Trash |
| cultist_ritualist | 0.5 | Trash |
| cultist_melee | 0.75 | Horde |
| cultist_assault | 0.75 | Horde |
| renegade_melee | 1.0 | Horde |
| renegade_assault | 1.0 | Horde |
| renegade_flamer | 1.0 | Specialist |
| renegade_flamer_mutator | 1.0 | Specialist |
| cultist_flamer | 1.0 | Specialist |
| renegade_sniper | 1.0 | Specialist |
| renegade_captain | 1.0 | Captain |
| cultist_captain | 1.0 | Captain |
| chaos_hound_mutator | 1.0 | Special (mutator) |
| cultist_grenadier | 2.0 | Specialist |
| renegade_grenadier | 2.0 | Specialist |
| chaos_poxwalker_bomber | 2.0 | Special |
| renegade_twin_captain | 2.0 | Boss |
| renegade_twin_captain_two | 2.0 | Boss |
| cultist_mutant_mutator | 2.0 | Special (mutator) |
| cultist_shocktrooper | 3.0 | Elite |
| renegade_shocktrooper | 3.0 | Elite |
| renegade_plasma_gunner | 3.0 | Elite |
| renegade_netgunner | 3.0 | Special |
| renegade_rifleman | 1.0 | Ranged |
| renegade_radio_operator | 4.0 | Elite |
| renegade_executor | 4.0 | Elite |
| renegade_berzerker | 4.0 | Elite |
| renegade_gunner | 4.0 | Elite |
| cultist_berzerker | 4.0 | Elite |
| cultist_gunner | 4.0 | Elite |
| cultist_mutant | 6.0 | Special |
| chaos_hound | 6.0 | Special |
| chaos_ogryn_bulwark | 8.0 | Elite |
| chaos_ogryn_executor | 8.0 | Elite |
| chaos_ogryn_gunner | 8.0 | Elite |
| chaos_daemonhost | 20.0 | Boss |
| chaos_mutator_daemonhost | 20.0 | Boss |
| chaos_plague_ogryn | 30.0 | Monster |
| chaos_spawn | 30.0 | Monster |
| chaos_beast_of_nurgle | 30.0 | Monster |

---

## 7. Relevance to BetterBots

### Current Heuristic

BetterBots uses `enemies_in_proximity() > 0` as the universal ability trigger. This means any single aggroed enemy within 5m causes ability activation. This is simple but has significant limitations:

1. **Too aggressive for expensive abilities** -- A single poxwalker (challenge 0.4) triggers the same as 5 Crushers
2. **Range mismatch** -- The 5m proximity radius is appropriate for melee/shout abilities but too narrow for ranged abilities like Veteran Stealth (which should consider threats at 15-20m)
3. **No health/toughness awareness** -- Defensive abilities (stealth, invisibility) should consider the bot's own state
4. **No ability-specific tuning** -- All abilities fire under identical conditions

### Available Perception Data for Smarter Triggers

The perception system exposes everything needed for per-ability heuristics:

#### Proximity-based (already available)
```lua
local _, num_nearby = perception_extension:enemies_in_proximity()
-- Available: list of enemy units within 5m, their breeds, challenge_ratings
```

#### Target-based (from blackboard)
```lua
local perception = blackboard.perception
-- perception.target_enemy            -- current target
-- perception.target_enemy_distance   -- distance to target
-- perception.target_enemy_type       -- "melee" / "ranged"
-- perception.urgent_target_enemy     -- monster target
-- perception.priority_target_enemy   -- enemy disabling ally
-- perception.opportunity_target_enemy -- special/elite target
```

#### Health/toughness (from extensions)
```lua
local health_ext = ScriptUnit.extension(unit, "health_system")
local health_pct = health_ext:current_health_percent()
local toughness_ext = ScriptUnit.extension(unit, "toughness_system")
local toughness_pct = toughness_ext:current_toughness_percent()
```

### Proposed Per-Ability Trigger Heuristics

Based on the available data, here are concrete heuristic suggestions:

| Ability | Trigger Condition | Rationale |
|---------|-------------------|-----------|
| **Veteran Stealth** (`veteran_combat_ability`) | `opportunity_target_enemy ~= nil` OR `(num_nearby > 0 AND target_enemy_type == "ranged")` | Vanilla condition: special/elite target exists. Extend to cover ranged engagements. |
| **Psyker Venting Shriek** (`psyker_shout`) | `num_nearby >= 3` OR `(num_nearby >= 1 AND toughness_pct < 0.3)` | AoE stagger -- most useful when surrounded or in danger. |
| **Psyker Stance** (`psyker_combat_ability`) | `target_enemy ~= nil AND target_enemy_distance < 25` | Buff ability, useful whenever fighting. |
| **Zealot Dash** (`zealot_dash`) | `target_enemy ~= nil AND target_enemy_distance > 8 AND target_enemy_distance < 25` | Gap closer -- useless in melee, useful to reach distant targets. |
| **Zealot Invisibility** (`zealot_invisibility`) | `toughness_pct < 0.2 AND num_nearby >= 2` | Defensive escape when overwhelmed. |
| **Zealot Relic** (`zealot_relic`) | `sum(challenge_rating) >= 1.75` (vanilla logic) | Already has a good heuristic using challenge_rating. Vanilla threshold works. |
| **Ogryn Charge** (`ogryn_charge`) | `target_enemy ~= nil AND target_enemy_distance > 6 AND num_nearby == 0` | Gap closer, avoid charging when already in melee. |
| **Ogryn Taunt** (`ogryn_taunt`) | `num_nearby >= 3 AND any_ally_needs_aid` | Tank ability -- useful when allies are pressured. |
| **Ogryn Gunlugger** (`ogryn_combat_ability`) | `target_enemy ~= nil AND target_enemy_distance > 5` | Ranged buff, want some distance. |

### Key Implementation Notes

1. **Challenge rating summation** can be done by iterating the `enemies_in_proximity` list and looking up `breed.challenge_rating` per enemy, exactly as the vanilla `_can_activate_zealot_relic` does.

2. **The 0.5-1.0s update jitter** on proximity counts means ability activation checks should tolerate brief stale data. This is already fine since the BT itself runs at behavior-tick rate.

3. **The `target_enemy` fields** are updated every 0.3s (reevaluation timer), so they're always reasonably fresh.

4. **Priority/urgent/opportunity targets** are particularly useful signals -- if `priority_target_enemy` is set, an ally is being disabled and the bot should prioritize accordingly (e.g., use charge to reach them, use shout to stagger the disabler).

5. **Monster weight goes to zero when `num_enemies_in_proximity > 0`** -- this means bots won't target monsters while surrounded by trash. Ability triggers should mirror this logic for offensive abilities (don't waste a dash charging a monster when surrounded).

---

## Source File Index

| File | Role |
|------|------|
| `scripts/extension_systems/perception/bot_perception_extension.lua` | Bot perception system: proximity queries, threat decay, target/ally/level-unit updates |
| `scripts/utilities/bot_target_selection.lua` | Scoring primitives: gestalt, slot, threat, opportunity, priority, monster, distance, LoS weights |
| `scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template.lua` | Main scoring loop: iterates targets, computes melee+ranged scores, writes blackboard |
| `scripts/settings/bot/bot_gestalt_target_selection_weights.lua` | Per-gestalt breed weight overrides (killshot penalizes heavy armor) |
| `scripts/settings/bot/bot_settings.lua` | Tuning constants: movement epsilons, reaction times, blackboard schema |
| `scripts/utilities/attack/bot_aoe_threat.lua` | Geometric AoE threat detection: sphere, cylinder, OOBB escape direction calculation |
| `scripts/utilities/threat.lua` | Threat accumulation from damage events |
| `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` | BT conditions consuming perception data (ability activation, threat-to-aid) |
| `scripts/extension_systems/group/bot_group.lua` | Priority target tracking (ally-disabling enemies), group coordination |
