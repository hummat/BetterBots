# Bot Behavior Tree Reference

Comprehensive reference for the Darktide bot behavior tree, condition system, brain update loop, and blackboard structure. All source references are relative to the decompiled source at `../Darktide-Source-Code/`.

---

## Table of Contents

1. [Full Behavior Tree Structure](#1-full-behavior-tree-structure)
2. [Node Types](#2-node-types)
3. [All Conditions (bt_bot_conditions.lua)](#3-all-conditions)
4. [Shared Conditions (bt_common_conditions.lua)](#4-shared-conditions)
5. [Condition Aggregation (bt_conditions.lua)](#5-condition-aggregation)
6. [Brain Update Loop](#6-brain-update-loop)
7. [BotBehaviorExtension Update Loop](#7-botbehaviorextension-update-loop)
8. [Blackboard Structure](#8-blackboard-structure)
9. [Action Data (bot_actions.lua)](#9-action-data)
10. [Utility System](#10-utility-system)
11. [Enter/Leave/Run Hooks](#11-enterleaverun-hooks)
12. [BetterBots Hook Points](#12-betterbots-hook-points)
13. [Potential Future Hook Points](#13-potential-future-hook-points)

---

## 1. Full Behavior Tree Structure

**Source:** `scripts/extension_systems/behavior/trees/bot/bot_behavior_tree.lua`

The tree is a single file returning a Lua table. The engine compiles this into node objects. The root is a `BtSelectorNode` (priority selector) -- it evaluates children top-to-bottom and picks the first whose condition passes.

```
ROOT: BtSelectorNode "bot"
|
|-- [1] BtBotIdleAction "disabled"
|       condition: is_disabled
|       action_data: (none)
|       Priority: HIGHEST -- disabled bots do nothing
|
|-- [2] BtBotInteractAction "do_revive"                          [ALLY AID]
|       condition: can_revive
|       action_data: bot_actions.do_revive
|         interaction_type = "revive", aim_node = "j_head"
|
|-- [3] BtBotInteractAction "do_remove_net"                      [ALLY AID]
|       condition: can_remove_net
|       action_data: bot_actions.do_remove_net
|         interaction_type = "remove_net", aim_node = "j_head"
|
|-- [4] BtBotInteractAction "do_rescue_ledge_hanging"            [ALLY AID]
|       condition: can_rescue_ledge_hanging
|       action_data: bot_actions.do_rescue_ledge_hanging
|         interaction_type = "pull_up", aim_node = "j_head"
|
|-- [5] BtBotInteractAction "do_rescue_hogtied"                  [ALLY AID]
|       condition: can_rescue_hogtied
|       action_data: bot_actions.do_rescue_hogtied
|         interaction_type = "rescue", aim_node = "j_head"
|
|-- [6] BtBotInteractAction "use_healing_station"                [INTERACT]
|       condition: can_use_health_station
|       action_data: (none)
|
|-- [7] BtBotInteractAction "loot"                               [INTERACT]
|       condition: can_loot
|       action_data: (none)
|
|-- [8] BtBotActivateAbilityAction "activate_combat_ability"     [ABILITY] ***
|       condition: can_activate_ability
|       action_data: bot_actions.activate_combat_ability
|         ability_component_name = "combat_ability_action"
|
|-- [9] BtBotActivateAbilityAction "activate_grenade_ability"    [ABILITY] ***
|       condition: can_activate_ability
|       action_data: bot_actions.activate_grenade_ability
|         ability_component_name = "grenade_ability_action"
|
|-- [10] BtSelectorNode "switch_to_proper_weapon"                [WEAPON SWITCH]
|        condition: has_target
|        |
|        |-- [10a] BtBotInventorySwitchAction "switch_melee"
|        |         condition: wrong_slot_for_target_type
|        |         condition_args: { target_type = "melee" }
|        |         action_data: bot_actions.switch_melee
|        |           wanted_slot = "slot_primary"
|        |
|        |-- [10b] BtBotInventorySwitchAction "switch_ranged"
|        |         condition: wrong_slot_for_target_type
|        |         condition_args: { target_type = "ranged" }
|        |         action_data: bot_actions.switch_ranged
|                   wanted_slot = "slot_secondary"
|
|-- [11] BtSelectorNode "attack_priority_target"                 [COMBAT]
|        condition: has_priority_or_urgent_target
|        |
|        |-- [11a] BtSelectorNode "melee_priority_target"
|        |         condition: bot_in_melee_range
|        |         |
|        |         |-- BtBotMeleeAction "fight_melee_priority_target"
|        |                action_data: bot_actions.fight_melee_priority_target
|        |                  engage_range = math.huge (all ranges)
|        |
|        |-- [11b] BtSelectorNode "ranged_priority_target"
|                  condition: has_target_and_ammo_greater_than
|                  condition_args: { ammo_percentage = 0, overheat_limit = 0.9,
|                                    overheat_limit_type = "critical_threshold" }
|                  |
|                  |-- BtBotShootAction "shoot_priority_target"
|                         action_data: bot_actions.shoot_priority_target
|
|-- [12] BtBotTeleportToAllyAction "teleport_out_of_range"       [TELEPORT]
|        condition: is_too_far_from_ally
|
|-- [13] BtRandomUtilityNode "in_combat"                         [MAIN LOOP]
|        condition: (none -- always evaluates)
|        |
|        |-- BtSelectorNode "combat"                             [UTILITY CHILD]
|        |   action_data: bot_actions.combat
|        |     utility_weight = 1
|        |     considerations = bot_combat (enemy distance spline)
|        |   |
|        |   |-- BtSelectorNode "melee"
|        |   |   condition: bot_in_melee_range
|        |   |   |
|        |   |   |-- BtBotMeleeAction "fight_melee"
|        |   |         action_data: bot_actions.fight_melee
|        |   |           engage_range = 6, engage_range_near_follow = 10
|        |   |
|        |   |-- BtSelectorNode "ranged"
|        |       condition: has_target_and_ammo_greater_than
|        |       condition_args: { ammo_percentage = 0.5, overheat_limit = 0.9,
|        |                         overheat_limit_type = "low_threshold" }
|        |       |
|        |       |-- BtBotShootAction "shoot"
|        |             action_data: bot_actions.shoot
|        |
|        |-- BtSelectorNode "follow"                             [UTILITY CHILD]
|            action_data: bot_actions.follow
|              utility_weight = 1
|              considerations = bot_follow (ally distance spline)
|            |
|            |-- BtBotTeleportToAllyAction "teleport_no_path"
|            |   condition: cant_reach_ally
|            |
|            |-- BtSelectorNode "vent_overheat"
|            |   condition: should_vent_overheat
|            |   condition_args: { overheat_limit_type = "low_threshold",
|            |                     start_max_percentage = 0.99,
|            |                     start_min_percentage = 0.5,
|            |                     stop_percentage = 0.1 }
|            |   |
|            |   |-- BtBotInventorySwitchAction "switch_ranged_overheat"
|            |   |   condition: is_slot_not_wielded
|            |   |   action_data: bot_actions.switch_ranged_overheat
|            |   |     wanted_slot = "slot_secondary"
|            |   |
|            |   |-- BtBotReloadAction "vent"
|            |
|            |-- BtSelectorNode "reload"
|            |   condition: should_reload
|            |   |
|            |   |-- BtBotInventorySwitchAction "switch_ranged_reload"
|            |   |   condition: is_slot_not_wielded
|            |   |   action_data: bot_actions.switch_ranged_reload
|            |   |     wanted_slot = "slot_secondary"
|            |   |
|            |   |-- BtBotReloadAction "do_reload"
|            |
|            |-- BtBotFollowAction "successful_follow"
|
|-- [14] BtBotIdleAction "idle"
         Priority: LOWEST -- unconditional fallback
```

### Priority Order Summary

Position in the root selector determines absolute priority:

| Priority | Node Name | Purpose |
|----------|-----------|---------|
| 1 | disabled | Do nothing while incapacitated |
| 2 | do_revive | Revive knocked-down ally |
| 3 | do_remove_net | Free netted ally |
| 4 | do_rescue_ledge_hanging | Pull up ledge-hanging ally |
| 5 | do_rescue_hogtied | Rescue hogtied ally |
| 6 | use_healing_station | Use health station |
| 7 | loot | Pick up ammo/health/mule items |
| 8 | activate_combat_ability | Use combat ability |
| 9 | activate_grenade_ability | Use grenade ability |
| 10 | switch_to_proper_weapon | Switch melee/ranged for target |
| 11 | attack_priority_target | Attack specials/elites/urgent |
| 12 | teleport_out_of_range | Teleport if 40m+ from ally |
| 13 | in_combat | Utility-weighted combat/follow |
| 14 | idle | Unconditional fallback |

Key observations:
- Ally rescue has higher priority than ability activation (positions 2-5 vs 8-9).
- Ability activation is checked BEFORE weapon switching and combat. A bot will attempt to use its ability before engaging in melee/ranged combat.
- The `in_combat` node (position 13) uses utility scoring to balance between combat and following. This is the node bots spend most of their time in.

---

## 2. Node Types

### BtSelectorNode (Priority Selector)

**Source:** `scripts/extension_systems/behavior/nodes/generated/bt_bot_selector_node.lua`

The root selector is code-generated (not generic). It inlines all condition checks directly in the `evaluate()` method for performance. Each child is checked in order; the first child whose condition passes is selected.

Key behavior:
- `evaluate()` (lines 31-940): Tests each child's condition sequentially, returns the first matching leaf node.
- `run()` (lines 942-950): Delegates to the currently running child.
- Conditions are inlined as `repeat...until true` blocks (decompiled loop pattern).

### BtRandomUtilityNode (Utility Selector)

**Source:** `scripts/extension_systems/behavior/nodes/bt_random_utility_node.lua`

Used for the `in_combat` node. Selects between children probabilistically based on utility scores.

Key behavior:
- Each child has `utility_weight` and `considerations` in its `action_data`.
- `_randomize_actions()` computes utility scores via spline evaluation, then selects children with weighted random sampling.
- If the currently running child's condition still passes and utility re-evaluation is not required, it keeps the current child (lines 152-163).
- A `fail_cooldown_t` prevents rapid re-evaluation after all children fail.
- The `bot_combat` consideration scores based on `perception.target_enemy_distance` (closer = higher score).
- The `bot_follow` consideration scores based on `perception.target_ally_distance` (farther = higher score).

### BtNode (Base Node)

**Source:** `scripts/extension_systems/behavior/nodes/bt_node.lua`

All action nodes inherit from `BtNode`. Provides:
- `enter()`, `leave()`, `run()` lifecycle methods.
- Enter/leave hook support via `BtEnterHooks`/`BtLeaveHooks`.
- Parent chain traversal: when entering/leaving, propagates to parent if the parent's running child changed.

---

## 3. All Conditions (bt_bot_conditions.lua)

**Source:** `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua`

All condition functions receive `(unit, blackboard, scratchpad, condition_args, action_data, is_running)`.

### Public Conditions (used by BT nodes)

#### `can_activate_ability` (lines 59-100) -- THE WHITELIST

The central gate for bot ability activation. This is the condition BetterBots replaces.

Vanilla logic:
1. If `ability_component_name == scratchpad.ability_component_name`, return `true` (ability already running).
2. Read the ability component's `template_name`. If `"none"`, return `false`.
3. Look up the `AbilityTemplate`. If `ability_meta_data` is nil, return `false`.
4. Validate the `action_input` via `ability_extension:action_input_is_currently_valid()`.
5. **THE WHITELIST**: Only `zealot_relic` and `veteran_combat_ability` are allowed through. All other templates hit `else return false` at line 98.

This means vanilla bots can only use:
- **Zealot Relic** (zealot_relic) -- when cumulative challenge rating of nearby enemies >= 1.75
- **Veteran Combat Ability** (veteran_combat_ability) -- when target enemy has `special` or `elite` tag

#### `is_disabled` (lines 102-109)

Returns `true` when the bot is in a disabled character state (knocked down, netted, grabbed, etc.). Uses `PlayerUnitStatus.is_disabled()`.

#### `can_revive` (lines 194-209)

Returns `true` when:
- `perception.target_ally` exists
- `behavior.interaction_unit` matches the target ally
- `perception.target_ally_need_type` is `"knocked_down"`
- Bot can interact with the ally (interaction range/LOS)
- Bot has reached the ally aid destination (nav mesh proximity check)

#### `can_remove_net` (lines 211-226)

Same as `can_revive` but checks `target_ally_need_type == "netted"` and uses `"remove_net"` interaction type.

#### `can_rescue_ledge_hanging` (lines 259-277)

Same pattern but:
- Checks `target_ally_need_type == "ledge"`
- **Additional gate**: calls `_is_there_threat_to_aid()` -- will NOT rescue if enemies are targeting the bot (unless `force_aid` and enemy is not a bot_aid_threat).

#### `can_rescue_hogtied` (lines 228-243)

Same as `can_revive` but checks `target_ally_need_type == "hogtied"` and uses `"rescue"` interaction type.

#### `can_use_health_station` (lines 245-257)

Returns `true` when:
- `perception.target_level_unit` exists
- `behavior.interaction_unit` matches the target level unit
- Bot has reached the level unit destination

#### `can_loot` (lines 279-299)

Returns `true` when the bot's `behavior.interaction_unit` matches one of:
- `pickup.health_deployable` (if `allowed_to_take_health_pickup` and within 3.2m or forced)
- `pickup.ammo_pickup` (if `needs_ammo` and within 3.2m or forced)
- `pickup.mule_pickup` (within 3.2m or forced)

And the bot can interact with the unit.

#### `has_target` (lines 400-405)

Returns `true` if `perception.target_enemy ~= nil`.

#### `wrong_slot_for_target_type` (lines 310-325)

Returns `true` when:
- `condition_args.target_type` matches `perception.target_enemy_type` (i.e., "melee" or "ranged")
- But the bot is wielding the wrong slot (melee weapon for ranged target or vice versa)

#### `has_priority_or_urgent_target` (lines 327-343)

Returns `true` when:
- `perception.target_enemy` exists
- Target is either the `priority_target_enemy` or `urgent_target_enemy`
- Target distance < 25 meters

#### `bot_in_melee_range` (lines 345-398)

Returns `true` when:
- Target exists and `target_enemy_type == "melee"`
- Target is within computed melee range (varies by context):
  - Taking cover or opportunity/urgent target: 2-3m
  - Normal: 10-12m (depends on wielded slot)
- Vertical offset within -1.5 to +2.0

#### `has_target_and_ammo_greater_than` (lines 407-444)

Returns `true` when:
- Target exists and `target_enemy_type == "ranged"`
- Ammo percentage > `condition_args.ammo_percentage`
- Overheat percentage < `condition_args.overheat_limit`
- Target is not obstructed by static geometry for > 3 seconds

Used with different thresholds:
- Priority target: ammo > 0%, overheat_limit_type = "critical_threshold"
- Normal target: ammo > 50%, overheat_limit_type = "low_threshold"

#### `should_reload` (lines 446-460)

Returns `true` when:
- Not in melee combat (`target_enemy_type ~= "melee"`)
- Clip is empty (`clip_percentage <= 0`)
- Reserve ammo exists (`reserve_percentage > 0`)

#### `should_vent_overheat` (lines 462-482)

Returns `true` when:
- Not in melee combat
- Overheat in vent range:
  - If already venting (`scratchpad.reloading`): overheat >= `stop_percentage` (0.1)
  - If not venting: overheat between `start_min_percentage` (0.5) and `start_max_percentage` (0.99)

#### `cant_reach_ally` (lines 484-527)

Returns `true` for teleport when:
- Follow unit exists and bot hasn't already teleported
- Bot is not ahead of ally on main path
- Navigation has failed repeatedly (>1 or >5 failures depending on position)
- Time since last successful path > 5 seconds
- Level forced teleport flag is set

#### `is_too_far_from_ally` (lines 529-573)

Returns `true` when:
- Follow unit exists and bot hasn't teleported
- Bot is not ahead of ally on main path
- No priority target and no ally needing aid
- Distance >= 40 meters (1600 squared)

#### `is_slot_not_wielded` (lines 301-308)

Returns `true` if current wielded slot does not match `action_data.wanted_slot`.

### Private (Helper) Conditions

#### `_can_activate_zealot_relic` (lines 7-40)

Threat assessment for zealot relic activation:
- Scans enemies within 10m (100 squared)
- Sums challenge ratings (1.25x multiplier if enemy is targeting the bot)
- Returns `true` if total >= 1.75

#### `_can_activate_veteran_ranger_ability` (lines 42-57)

Returns `true` if `perception.target_enemy` has breed tags `special` or `elite`.

#### `_is_there_threat_to_aid` (lines 111-136)

Used by `can_rescue_ledge_hanging`. Returns `true` if any enemy in proximity is targeting the bot. Respects `force_aid` flag and `is_bot_aid_threat` breed property.

#### `_has_reached_ally_aid_destination` (lines 138-164)

Navigation proximity check: returns `true` if bot has reached the computed aid position for ally. Uses flat distance + z-offset thresholds from `BotSettings`.

#### `_has_reached_level_unit_destination` (lines 166-192)

Same as above but for level unit interactions (health stations).

---

## 4. Shared Conditions (bt_common_conditions.lua)

**Source:** `scripts/extension_systems/behavior/utilities/conditions/bt_common_conditions.lua`

Contains only one condition:

#### `always_true`

Always returns `true`. Used by BT nodes that should always be eligible.

---

## 5. Condition Aggregation (bt_conditions.lua)

**Source:** `scripts/extension_systems/behavior/utilities/bt_conditions.lua`

This file creates the master condition lookup table used by the BT evaluation system. It merges conditions from three sources:

1. `bt_bot_conditions` -- bot-specific conditions (Section 3)
2. `bt_common_conditions` -- shared conditions (Section 4)
3. `bt_minion_conditions` -- enemy AI conditions (not used by bots)

The `BtRandomUtilityNode` uses this merged `BtConditions` table to look up conditions by name. The generated `BtBotSelectorNode` inlines conditions directly and does not use this lookup.

**Implication for BetterBots:** The mod patches `can_activate_ability` in both `bt_bot_conditions` (the source table) and `bt_conditions` (the merged table) to ensure coverage regardless of which path evaluates the condition.

---

## 6. Brain Update Loop

**Source:** `scripts/extension_systems/behavior/ai_brain.lua`

### AiBrain.update (lines 91-147)

Called once per frame per bot. The full cycle:

```
1. Swap running_child_nodes buffers (old <-> new)
2. Get root node, evaluate from root:
   root_node:evaluate(unit, bb, scratchpad, dt, t, evaluate_utility, ...)
   -> Returns the leaf node that should be active
3. If leaf changed or previous leaf was done:
   a. Leave the old leaf (reason = "aborted")
   b. Enter the new leaf
4. Clear old running_child_nodes
5. Run from root:
   root_node:run(unit, bb, scratchpad, ...) -> result
6. If result ~= "running":
   - Leave the finished leaf (reason = result)
   - Clear scratchpad
7. Set evaluate_utility for next frame:
   evaluate_utility = evaluate_utility_next_frame OR leaf_done
```

### Key data flow:
- **Scratchpad:** Ephemeral per-leaf-node state. Cleared when leaf changes or completes. Each action node stores its working state here.
- **Node data:** Persistent per-node state (e.g., utility data, fail cooldown timers). Stored in `self._node_data[identifier]`.
- **Running child nodes:** Dictionary mapping `parent_identifier -> child_node`. Tracks which child is active at each level.

### Evaluate vs Run distinction:
- `evaluate()`: Traverses the tree top-down, checking conditions. Returns the leaf that should run. Pure selection -- no side effects on game state.
- `run()`: Executes the selected leaf's behavior. Returns `"running"`, `"done"`, or `"failed"`.
- `evaluate_utility`: Flag that controls whether the utility node recalculates scores. Set to `true` when the previous leaf completes, forcing utility re-evaluation.

---

## 7. BotBehaviorExtension Update Loop

**Source:** `scripts/extension_systems/behavior/bot_behavior_extension.lua`

### BotBehaviorExtension.update (lines 202-235)

Called by the extension system once per frame. The full update sequence:

```
1. Guard: if player:is_human_controlled() then return
2. Guard: if not HEALTH_ALIVE[unit] then skip
3. _update_ammo(unit)
   -> Sets pickup.needs_ammo based on ammo % and human player comparison
4. _update_health_deployables(unit)
   -> Sets pickup.needs_non_permanent_health based on healable damage
5. _update_health_stations(unit, dt, t)
   -> Sets health_station.needs_health based on damage taken vs threshold
6. _verify_target_ally_aid_destination(unit)
   -> Clears stale ally aid destinations
7. brain:update(unit, dt, t)                    <-- BT evaluation happens here
8. If disabled or on moveable platform:
   -> Teleport nav to self position (stay put)
9. Else if on ground:
   -> _handle_doors(unit)                       <-- Open doors in nav transitions
   -> _update_movement_target(unit, dt, t)      <-- Compute navigation destination
10. Clean up dead attackers from hit_by_projectile table
```

### Movement Target Priority (lines 646-777)

`_refresh_destination()` determines where the bot navigates, in priority order:

1. **Revive with urgent target** -- ally aid with `revive_with_urgent_target` flag
2. **Priority target path** -- move toward priority_target_enemy
3. **Target enemy path** -- move toward priority/urgent target
4. **Ally aid** -- move toward target_ally needing aid
5. **Mule pickup** -- move toward mule_pickup
6. **Health station** -- move toward health station if needed
7. **Health deployable** -- move toward nearby health pickup
8. **Ammo pickup** -- move toward ammo pickup
9. **Follow position** -- follow the human player (default)

---

## 8. Blackboard Structure

The blackboard is a collection of named components, each a table of fields. Initialized in `_init_blackboard_components` (lines 100-161).

### `behavior` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `current_interaction_unit` | unit/nil | Unit currently being interacted with |
| `forced_pickup_unit` | unit/nil | Forced pickup order target |
| `melee_gestalt` | string | Current melee behavior gestalt |
| `interaction_unit` | unit/nil | Target for next interaction |
| `ranged_gestalt` | string | Current ranged behavior gestalt |
| `revive_with_urgent_target` | bool | Allow revive even with urgent target |
| `target_ally_aid_destination` | Vector3Box | Nav destination for ally aid |
| `target_level_unit_destination` | Vector3Box | Nav destination for level unit |

### `follow` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `destination` | Vector3Box | Current follow destination |
| `has_teleported` | bool | Bot has teleported this cycle |
| `moving_towards_follow_position` | bool | Currently following player |
| `needs_destination_refresh` | bool | Destination needs recomputation |
| `level_forced_teleport` | bool | Level script forced teleport |
| `level_forced_teleport_position` | Vector3Box | Forced teleport target position |

### `perception` component (read-only in BT)

Populated by the perception system (not by the behavior extension). Key fields used by conditions:

| Field | Type | Used By |
|-------|------|---------|
| `target_enemy` | unit/nil | Most conditions |
| `target_enemy_type` | "melee"/"ranged"/nil | bot_in_melee_range, has_target_and_ammo |
| `target_enemy_distance` | number | has_priority_or_urgent_target, utility |
| `priority_target_enemy` | unit/nil | has_priority_or_urgent_target |
| `urgent_target_enemy` | unit/nil | has_priority_or_urgent_target, melee_range |
| `opportunity_target_enemy` | unit/nil | bot_in_melee_range |
| `target_ally` | unit/nil | can_revive, can_remove_net, etc. |
| `target_ally_needs_aid` | bool | is_too_far_from_ally, destination refresh |
| `target_ally_need_type` | string | can_revive ("knocked_down"), can_remove_net ("netted"), etc. |
| `target_ally_distance` | number | Utility scoring (bot_follow) |
| `target_level_unit` | unit/nil | can_use_health_station |
| `target_level_unit_distance` | number | Health station proximity |
| `force_aid` | bool | _is_there_threat_to_aid |

### `pickup` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `allowed_to_take_health_pickup` | bool | Permission to take health |
| `ammo_pickup` | unit/nil | Closest ammo pickup unit |
| `ammo_pickup_distance` | number | Distance to ammo pickup |
| `ammo_pickup_valid_until` | number | Expiry time for ammo pickup |
| `force_use_health_pickup` | bool | Forced health pickup |
| `health_deployable` | unit/nil | Closest health deployable unit |
| `health_deployable_distance` | number | Distance to health deployable |
| `health_deployable_valid_until` | number | Expiry time |
| `mule_pickup` | unit/nil | Closest mule pickup unit |
| `mule_pickup_distance` | number | Distance to mule pickup |
| `needs_ammo` | bool | Bot needs ammo |
| `needs_non_permanent_health` | bool | Bot has healable damage |

### `health_station` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `needs_health` | bool | Bot should use health station |
| `needs_health_queue_number` | number | Priority in queue (1 = highest) |
| `time_in_proximity` | number | Time spent near health station |

### `ranged_obstructed_by_static` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `t` | number | Time when obstruction was detected |
| `target_unit` | unit/nil | Unit that was obstructed |

### `spawn` component (writable)

| Field | Type | Description |
|-------|------|-------------|
| `physics_world` | userdata | Reference to physics world |

### `melee` component (read-only in behavior extension)

| Field | Type | Description |
|-------|------|-------------|
| `engage_position_set` | bool | Has a melee engage position |
| `engage_position` | Vector3Box | Position to move to for melee |
| `stop_at_current_position` | bool | Stop moving toward target |

---

## 9. Action Data (bot_actions.lua)

**Source:** `scripts/settings/breed/breed_actions/bot_actions.lua`

Each BT node's `action_data` is a table from this file. The data parameterizes the node's behavior without changing the node class.

| Name | Key Fields | Description |
|------|-----------|-------------|
| `activate_combat_ability` | `ability_component_name = "combat_ability_action"` | Component for combat ability |
| `activate_grenade_ability` | `ability_component_name = "grenade_ability_action"` | Component for grenade ability |
| `do_revive` | `interaction_type = "revive"`, `aim_node = "j_head"` | Revive parameters |
| `do_rescue_ledge_hanging` | `interaction_type = "pull_up"`, `aim_node = "j_head"` | Ledge rescue parameters |
| `do_rescue_hogtied` | `interaction_type = "rescue"`, `aim_node = "j_head"` | Hogtied rescue parameters |
| `do_remove_net` | `interaction_type = "remove_net"`, `aim_node = "j_head"` | Net removal parameters |
| `combat` | `utility_weight = 1`, `considerations = bot_combat` | Utility scoring for combat |
| `follow` | `utility_weight = 1`, `considerations = bot_follow` | Utility scoring for follow |
| `fight_melee` | `engage_range = 6`, various overrides | Normal melee engagement |
| `fight_melee_priority_target` | `engage_range = math.huge` | Priority target melee (no range limit) |
| `shoot` | `evaluation_duration = 2`, aim speeds, gestalts | Normal ranged attack |
| `shoot_priority_target` | `evaluation_duration = 2`, gestalts | Priority target ranged |
| `switch_melee` | `wanted_slot = "slot_primary"` | Switch to melee weapon |
| `switch_ranged` | `wanted_slot = "slot_secondary"` | Switch to ranged weapon |
| `switch_ranged_overheat` | `wanted_slot = "slot_secondary"` | Switch for venting |
| `switch_ranged_reload` | `wanted_slot = "slot_secondary"` | Switch for reloading |

---

## 10. Utility System

**Source:** `scripts/extension_systems/behavior/utility_considerations/bot_utility_considerations.lua`

The `BtRandomUtilityNode` ("in_combat") uses utility scores to probabilistically select between `combat` and `follow`.

### bot_combat consideration

```lua
distance_to_target = {
    blackboard_component = "perception",
    component_field = "target_enemy_distance",
    max_value = 40,
    spline = { 0, 1, 0.25, 0.25, 0.75, 0, 1, 0 }
}
```

Score is high when enemies are close (0m = 1.0), drops off at ~10m, reaches 0 at ~30m.

### bot_follow consideration

```lua
distance_to_target = {
    blackboard_component = "perception",
    component_field = "target_ally_distance",
    max_value = 40,
    spline = { 0, 0.1, 0.25, 0.2, 0.75, 1, 1, 1 }
}
```

Score is low when near ally (0m = 0.1), increases to 1.0 at ~30m+. This makes bots follow the player when far away, but prioritize combat when enemies are nearby.

### Selection mechanism

Both children have `utility_weight = 1`, so selection is proportional to their consideration scores. The `_randomize_actions()` function (bt_random_utility_node.lua:69) uses weighted random selection -- it does NOT always pick the highest score. This produces natural-feeling variation in bot behavior.

---

## 11. Enter/Leave/Run Hooks

### BtEnterHooks

**Source:** `scripts/extension_systems/behavior/utilities/bt_enter_hooks.lua`

None of these are used by bot BT nodes. They are for enemy AI (captain_charge_enter, poxwalker_bomber, beast_of_nurgle, etc.) and companion dog.

### BtLeaveHooks

**Source:** `scripts/extension_systems/behavior/utilities/bt_leave_hooks.lua`

Same -- enemy AI and companion only. No bot-specific leave hooks.

### BtRunHooks

**Source:** `scripts/extension_systems/behavior/utilities/bt_run_hooks.lua`

Only one hook: `store_owner_velocities` for companion dog. No bot hooks.

**Conclusion:** The bot behavior tree does not use any enter/leave/run hooks. All bot BT node behavior is self-contained in the node classes themselves.

---

## 12. BetterBots Hook Points

**Source:** `scripts/mods/BetterBots/BetterBots.lua`

### Hook 1: Condition replacement (lines 1227-1259)

**Target:** `bt_bot_conditions.can_activate_ability` AND `bt_conditions.can_activate_ability`

**What changed:** Removes the whitelist (`else return false` at vanilla line 98). The replacement:
1. Keeps the `zealot_relic` and `veteran_combat_ability` special-case heuristics.
2. For all other templates with valid `ability_meta_data`: uses `enemies_in_proximity() > 0` as the trigger.
3. Injects `TIER2_META_DATA` for templates that lack `ability_meta_data` (zealot_invisibility, zealot_dash, ogryn_charge, ogryn_taunt_shout, psyker_shout, adamant_shout, adamant_charge).
4. Overrides `META_DATA_OVERRIDES` for veteran templates that ship with wrong action_input names.

### Hook 2: Ability meta_data injection (lines 1223-1225)

**Target:** `scripts/settings/ability/ability_templates/ability_templates` (via `hook_require`)

Injects `ability_meta_data` tables into templates that exist but lack them. This is what makes Tier 2 abilities work.

### Hook 3: Debug logging on enter (lines 1261-1288)

**Target:** `BtBotActivateAbilityAction.enter` (via `hook_safe`)

Logs when a bot enters the ability activation node.

### Hook 4: Charge consumption tracking (lines 1290-1327)

**Target:** `PlayerUnitAbilityExtension.use_ability_charge` (via `hook_safe`)

Records charge consumption events per unit for item-ability fallback confirmation.

### Hook 5: State transition failure retry (lines 1329-1374)

**Target:** `ActionCharacterStateChange.finish` (via `hook`)

Detects when a combat ability's character state transition fails (e.g., bot is in a conflicting state) and schedules a fast retry (0.35s).

### Hook 6: Weapon switch lock (lines 1376-1411)

**Target:** `PlayerUnitActionInputExtension.bot_queue_action_input` (via `hook`)

Blocks weapon wield inputs while the bot is in an active ability or mid-item-sequence. Prevents the BT's `switch_to_proper_weapon` node from interrupting ability animations.

### Hook 7: Perils achievement nil guard (lines 1413-1435)

**Target:** `WeaponSystem.queue_perils_of_the_warp_elite_kills_achievement` (via `hook`)

Guards against nil `account_id` crash when bots trigger psyker perils kills.

### Hook 8: Fallback ability queuing (lines 1437-1446)

**Target:** `BotBehaviorExtension.update` (via `hook_safe`)

Runs `_fallback_try_queue_combat_ability(unit)` after every brain update. This is the Tier 3 item-ability fallback system that handles abilities with no `ability_template` field (zealot_relic, psyker_force_field, etc.) by directly wielding the combat ability slot and driving weapon action inputs.

---

## 13. Potential Future Hook Points

### Per-career threat heuristics

**Where:** The `_can_activate_ability` replacement in BetterBots (line 317-333) uses a generic `enemies_in_proximity() > 0` trigger for non-whitelisted abilities. Future work (GitHub #2) should add per-template heuristics similar to the existing `_can_activate_zealot_relic` and `_can_activate_veteran_ranger_ability`.

**Approach:** Add entries to a `TRIGGER_HEURISTICS` table keyed by template name. Each entry would be a function that receives the standard condition arguments and returns `true`/`false`. The generic fallback would remain for templates without a custom heuristic.

### Cooldown management

**Where:** The vanilla BT has no explicit cooldown between ability activations (the `action_input_is_currently_valid` check serves as the de facto cooldown). For abilities that should not be spammed (shouts, charges), adding a scratchpad-based or blackboard-based cooldown in the condition would be useful.

### Revive-with-ability

**Where:** The `do_revive` node (position 2) runs before `activate_combat_ability` (position 8). To revive with an ability (like in VT2 Bot Improvements), a new node would need to be inserted at position 2 that combines ability activation with the revive interaction, or the revive node's condition would need to trigger ability use.

### Grenade ability support

**Where:** Node [9] (`activate_grenade_ability`) uses `ability_component_name = "grenade_ability_action"`. Most grenades are item-based (Tier 3) and have `template_name = "none"`. The item-ability fallback system in Hook 8 currently only handles combat abilities. Extending it to grenade abilities would require a parallel fallback path targeting `grenade_ability_action`.

### Utility scoring for ability activation

**Where:** Currently, ability activation is in the priority selector (positions 8-9), not in the utility node. This means ability use is always prioritized over normal combat. Moving it into the `in_combat` utility node with its own consideration would allow smarter timing (e.g., save ability for high-threat situations instead of using it on 1 poxwalker).

---

## Appendix: File Reference

| File | Description |
|------|-------------|
| `scripts/extension_systems/behavior/trees/bot/bot_behavior_tree.lua` | BT definition (207 lines) |
| `scripts/extension_systems/behavior/nodes/generated/bt_bot_selector_node.lua` | Generated root selector with inlined conditions (953 lines) |
| `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` | All bot conditions (575 lines) |
| `scripts/extension_systems/behavior/utilities/conditions/bt_common_conditions.lua` | Shared conditions (9 lines) |
| `scripts/extension_systems/behavior/utilities/bt_conditions.lua` | Condition aggregation table (17 lines) |
| `scripts/extension_systems/behavior/bot_behavior_extension.lua` | Brain update + movement + blackboard init (1122 lines) |
| `scripts/extension_systems/behavior/ai_brain.lua` | BT evaluation engine (163 lines) |
| `scripts/extension_systems/behavior/nodes/bt_node.lua` | Base node class (137 lines) |
| `scripts/extension_systems/behavior/nodes/bt_random_utility_node.lua` | Utility selector node (235 lines) |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua` | Ability activation leaf node (135 lines) |
| `scripts/settings/breed/breed_actions/bot_actions.lua` | Action data for all bot BT nodes (93 lines) |
| `scripts/extension_systems/behavior/utility_considerations/bot_utility_considerations.lua` | Utility splines for combat/follow (40 lines) |
| `scripts/extension_systems/behavior/utilities/bt_enter_hooks.lua` | Enter hooks (136 lines, none for bots) |
| `scripts/extension_systems/behavior/utilities/bt_leave_hooks.lua` | Leave hooks (182 lines, none for bots) |
| `scripts/extension_systems/behavior/utilities/bt_run_hooks.lua` | Run hooks (10 lines, none for bots) |
