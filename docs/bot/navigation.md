# Bot Navigation and Movement Reference

Internal reference for how Darktide bots navigate the world. All source references are
relative to the decompiled source at `../Darktide-Source-Code/`.

---

## Table of Contents

1. [Navigation System](#1-navigation-system)
2. [Follow Behavior](#2-follow-behavior)
3. [Teleport Conditions](#3-teleport-conditions)
4. [Nav Transitions (Jumps, Drops, Ladders)](#4-nav-transitions)
5. [AoE Threat Avoidance](#5-aoe-threat-avoidance)
6. [Bot Group Formation](#6-bot-group-formation)
7. [Movement During Combat](#7-movement-during-combat)
8. [Relevance to BetterBots](#8-relevance-to-betterbots)

---

## 1. Navigation System

**Source:** `scripts/extension_systems/navigation/bot_navigation_extension.lua`

### Navmesh and Pathfinding

Darktide uses the **Gameware Navigation** (GwNav) middleware for navmesh-based pathfinding.
Each bot gets its own `BotNavigationExtension` instance with:

- **`GwNavAStar`** -- A* pathfinder with live path support
- **`GwNavTraverseLogic`** -- determines which nav tag layers the bot can traverse
- **`GwNavTagLayerCostTable`** -- per-layer cost multipliers for path cost calculation
- **`GwNavCostMapMultiplierTable`** -- dynamic cost map multipliers (fire, daemonhost, etc.)

### Path Request Flow

```
BotBehaviorExtension._update_movement_target()
  -> BotNavigationExtension.move_to(target_position, callback)
     -> GwNavAStar.start_with_propagation_box(astar, nav_world, from, to, extent, traverse_logic)
        [async -- processed over frames]
     -> _update_astar() polls GwNavAStar.processing_finished()
        -> on success: stores path nodes as Vector3Box array, inits live_path
        -> on failure: increments _num_successive_failed_paths, fires callback(false)
  -> _update_path() advances along path nodes each frame
```

### Key Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `PROPAGATION_BOX_EXTENT` | 40 | A* search radius |
| `NAV_MESH_CHECK_ABOVE` | 0.75 | Height above position to find navmesh |
| `NAV_MESH_CHECK_BELOW` | 0.5 | Height below position to find navmesh |
| `NAV_MESH_POSITION_ABOVE` | 1.1 | Position update navmesh check above |
| `NAV_MESH_POSITION_BELOW` | 0.5 | Position update navmesh check below |
| `SAME_DIRECTION_THRESHOLD` | cos(pi/8) ~= 0.924 | Reuse old path if new target is roughly same direction |

### Goal Reached Detection

`_goal_reached()` uses a combined check:
- **Passed goal:** dot product of (unit-to-goal) and (previous-to-goal) < 0
- **At goal:** flat distance < threshold AND z offset within [-0.35, 0.5]

The flat threshold starts at **0.05m** and ramps up to **0.2m** over 0.25s if the bot
stays close but cannot reach the exact point (prevents getting stuck on geometry).

| Threshold | Value |
|-----------|-------|
| `FLAT_THRESHOLD_DEFAULT` | 0.05 |
| `MAX_FLAT_THRESHOLD` | 0.2 |
| `TIME_UNTIL_RAMP_THRESHOLD` | 0.25s |
| `RAMP_TIME` | 0.25s |

### Live Path Invalidation

Paths are validated each frame via `GwNavAStar.is_valid(live_path, astar)`. If the path
becomes invalid (e.g., navmesh changed), `move_to()` is called again with the current
destination to re-request a path.

### Path Queuing

If `move_to()` is called while an A* search is already running, the new target is queued
(`_has_queued_target = true`). When the current search finishes, the queued target is
automatically dispatched.

---

## 2. Follow Behavior

**Sources:**
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_follow_action.lua`
- `scripts/extension_systems/behavior/bot_behavior_extension.lua` (lines 419-777)

### BtBotFollowAction (BT Leaf)

The follow action itself is minimal -- it sets `needs_destination_refresh = true` on enter
and returns `"running"` with `should_evaluate = true` every tick. The actual movement logic
lives in `BotBehaviorExtension._update_movement_target()`.

### Destination Priority (in `_refresh_destination`)

When refreshing the follow destination, the bot evaluates targets in priority order:

1. **Revive with urgent target** -- ally needs aid AND bot has urgent target (revive-while-fighting)
2. **Priority target enemy** -- pounced/netted ally's attacker, path toward it
3. **Urgent/priority target enemy** -- direct threat, path toward it
4. **Ally needing aid** -- downed/netted/ledge ally, path toward them
5. **Mule pickup** -- grimoire/scripture to carry
6. **Health station** -- if bot needs health and station has charges (max distance: 400 sq = 20m)
7. **Health deployable** -- medical crate within range (max 10m direct, 15m from follow position)
8. **Ammo pickup** -- if bot needs ammo and pickup is valid (max 5m direct, 15m from follow)
9. **Follow position** -- formation position from BotGroup (default fallback)

### Follow Timer

Destination refresh is gated by a timer randomized between **1.0s and 1.5s**
(`FOLLOW_TIMER_LOWER_BOUND`, `FOLLOW_TIMER_UPPER_BOUND`). The timer resets on each
successful refresh.

### Movement Target Override Hierarchy

In `_update_movement_target()`, destinations are evaluated in this order:

1. **Hold position** -- if set and current destination is outside radius, force nav to hold position
2. **Cover position** -- if in line of fire from ranged enemies, move to cover
3. **Melee engage position** -- if melee component has an engage position set
4. **Standard follow** -- timer-based refresh of the follow destination (described above)

### Sprint Behavior

**Bots do not sprint.** There is no sprint input in `BotUnitInput`. Movement speed is
controlled purely by the magnitude of the `move` vector (x, y), which is always 0 or 1
(with slight scaling near the final goal). The engine applies the character's walk speed.

### Movement Scaling Near Goal

When following the last path node (not in a transition), movement input is scaled down
as the bot approaches to prevent overshooting:

```lua
MOVE_SCALE_START_DIST_SQ = 0.01  -- start scaling at ~0.1m
MOVE_SCALE_FACTOR = 99.995
MOVE_SCALE_MIN = 0.00005
move_scale = MOVE_SCALE_FACTOR * goal_dist_sq + MOVE_SCALE_MIN
```

### Distance Thresholds for Path Refresh

| Constant | Value | Purpose |
|----------|-------|---------|
| `FLAT_MOVE_TO_EPSILON` | 0.05m | Min flat distance to issue new path |
| `FLAT_MOVE_TO_PREVIOUS_POS_EPSILON` | 0.25m | Min movement from last reached destination |
| `Z_MOVE_TO_EPSILON` | 0.3m | Min vertical distance to issue new path |

---

## 3. Teleport Conditions

**Sources:**
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_teleport_to_ally_action.lua`
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` (lines 484-573)

### When Bots Teleport

There are two teleport triggers in the behavior tree, evaluated at different priority levels:

#### 1. `is_too_far_from_ally` (Higher Priority -- BT index ~11)

Checked **before** the combat/follow selector. Triggers when:

- Bot has a follow unit assigned
- Bot has NOT already teleported this follow cycle
- Bot is NOT ahead of ally on the main path
- Bot has NO ally needing aid and NO priority target
- Both bot and ally have valid navmesh positions
- **Distance >= 40m** (1600 squared) between their navmesh positions

#### 2. `cant_reach_ally` (Lower Priority -- Inside follow selector)

Checked inside the follow subtree. Triggers when:

- Bot has a follow unit assigned
- Bot has NOT already teleported this follow cycle
- Bot is NOT ahead of ally on the main path
- Bot is moving toward follow position
- **>1 successive failed paths** (if behind ally) or **>5 successive failed paths** (otherwise)
- **>5 seconds** since last successful path
- OR: `level_forced_teleport` flag is set (scripted teleport)

### Teleport Destination

The teleport places the bot **behind the follow unit**, using the follow unit's facing
direction negated as the check direction:

```lua
local check_direction = -Quaternion.forward(follow_unit_rotation)
teleport_position = NavQueries.position_near_nav_position(from_position, check_direction, ...)
```

If `level_forced_teleport` is set, the bot teleports to the scripted position instead.

### Post-Teleport State

After teleporting:
- `has_teleported = true` -- prevents repeated teleports until follow is re-entered
- `needs_destination_refresh = true` -- forces immediate path recalculation
- Navigation extension is reset via `teleport()` which clears path, A*, and all state

---

## 4. Nav Transitions

**Sources:**
- `scripts/managers/bot_nav_transition/bot_nav_transition_manager.lua`
- `scripts/managers/bot_nav_transition/utilities/bot_nav_transition.lua`
- `scripts/managers/bot_nav_transition/utilities/ladder_nav_transition.lua`
- `scripts/extension_systems/navigation/player_nav_transition_generator.lua`
- `scripts/components/bot_jump_assist.lua`

### How Transitions Are Created

Bot nav transitions bridge gaps in the navmesh (drops, jumps, ledges) that bots cannot
traverse normally. They are created in two ways:

#### 1. Player-Generated Transitions (Dynamic)

`PlayerNavTransitionGenerator` watches every player unit (including bots) for state changes:

- **Jump/Fall:** When the character enters `jumping` or `falling` state, records the
  `from_position` (on navmesh). When they land (`on_ground`), creates a transition from
  `from` to landing position.
- **Ledge Vault:** Same pattern but records the midpoint of the ledge as the waypoint.

The generator calls `BotNavTransitionManager.create_transition(from, via, to, jumped)`.

#### 2. Level-Placed Transitions (Permanent)

`BotJumpAssist` components are placed by level designers at specific locations. These
create permanent transitions on `gameplay_post_init` with three nodes:

- Unit origin = `from` position
- `waypoint` node = intermediate position
- `destination` node = target position
- `should_jump` flag = whether bots should jump at the waypoint

### Transition Types (Nav Tag Layers)

`BotNavTransition.calculate_nav_tag_layer()` classifies transitions by height difference:

| Layer Name | Height Condition | Nav Cost |
|------------|------------------|----------|
| `bot_jumps` | to.z - from.z > 0.3m | 1 |
| `bot_drops` | to.z - from.z < -0.5m | 1 |
| `bot_damage_drops` | height < -min_fall_damage_height | 10 |
| `bot_leap_of_faith` | player jumped (regardless of height) | 3 |
| `bot_ladders` | ladder transitions | 5 |

Fatal drops (> min_fall_damage_height + max_health*0.5/140) return `nil` and are not
created, preventing bots from taking lethal fall damage.

### Nav Cost Settings

From `scripts/settings/navigation/navigation_cost_settings.lua`, bot-specific costs:

| Layer | Bot Cost | Minion Cost |
|-------|----------|-------------|
| `bot_drops` | 1 | 0 (forbidden) |
| `bot_jumps` | 1 | 0 (forbidden) |
| `bot_damage_drops` | 10 | 0 (forbidden) |
| `bot_leap_of_faith` | 3 | 0 (forbidden) |
| `bot_ladders` | 5 | 0 (forbidden) |
| `doors` | 1.5 | 1.5 |
| `ledges` | 0 (forbidden) | 10 |
| `teleporters` | 0 (forbidden) | 5 |

Bots **cannot** use ledges, cover_ledges, cover_vaults, jumps, or teleporters that minions
use. They rely entirely on the bot-specific transition system.

### Transition Execution During Pathfinding

When following a path, `_reevaluate_current_nav_transition()` checks if the current path
node crosses a nav graph (smart object). If it does:

1. Look up the smart object ID in the path's `nav_graphs` data
2. Determine the layer name (transition type)
3. If the smart object has a unit (e.g., door or ladder), store it
4. Otherwise, look up the transition data from `BotNavTransitionManager` for waypoint/destination

### Transition Timeouts

| Constant | Value | Action |
|----------|-------|--------|
| `MAX_TIME_IN_TRANSITION` | 10s | Re-request path if stuck in non-teleportable transition |
| `MAX_TIME_IN_TELEPORT_FRIENDLY_TRANSITION` | 5s | Force-teleport to transition end for jumps/drops/leaps |

Teleport-friendly transitions (`bot_jumps`, `bot_drops`, `bot_leap_of_faith`) will
force-teleport the bot to the transition endpoint after 5 seconds, preventing permanent
stalls.

### Ladder Handling

`LadderNavTransition` creates bidirectional nav graphs for ladders:

1. Find ground position by raycasting down from top + backward offset
2. Find navmesh positions near both top and bottom
3. Determine bidirectionality: ground position must be within 1.5m below ladder bottom
4. Create GwNavGraph between top and ground navmesh positions

| Constant | Value |
|----------|-------|
| `CLIMBING_OFFSET` | 0.25m |
| `MAX_DISTANCE_FROM_GROUND` | 10m |
| `NAV_MESH_STEP_SIZE` | 0.2m |
| `NAV_MESH_MAX_STEPS` | 7 (1.4m max search distance) |
| `CLIMBABLE_HEIGHT` | 1.5m |

On ladders, `BotUnitInput` sets `move.y = 1` (always forward) and looks up or down based
on goal Z relative to bot Z. If there is no current goal while on a ladder, the bot jumps
off (`input.jump = true`).

### Jump and Obstacle Detection

`BotUnitInput._obstacle_check()` uses physics overlap tests to detect obstacles in the
bot's path:

- **Lower box:** Checks at knee-to-waist height. If hit (and upper is clear), triggers jump.
- **Upper box:** Checks at head height. If hit (and lower is clear), triggers crouch.

Jump during transitions: `transition_requires_jump()` returns true for `bot_leap_of_faith`
transitions when the bot is within **1m** of the waypoint and not currently following it.

Transition jumps require the bot's movement direction to be within **cos(pi/16) ~= 0.981**
of the goal direction to prevent misfires.

---

## 5. AoE Threat Avoidance

**Sources:**
- `scripts/utilities/attack/bot_aoe_threat.lua`
- `scripts/extension_systems/group/bot_group.lua` (lines 138-171)
- `scripts/extension_systems/input/bot_unit_input.lua` (lines 261-298)

### Threat Detection

`BotGroup.aoe_threat_created()` is called when an AoE hazard spawns. It tests each bot
against the threat shape and computes an escape direction.

Three shape types are supported:

| Shape | Detection | Escape Direction |
|-------|-----------|------------------|
| **Sphere** | Flat distance < radius + bot_radius, Z within range | Radially outward from center |
| **Cylinder** | Same as sphere but uses max(size.x, size.y) as radius, size.z as half-height | Radially outward from center |
| **OOBB** | Oriented box test with bot_radius padding | Perpendicular to longest escape axis (left or right) |

All escape directions are validated against the navmesh via `NavQueries.ray_can_go()` with
generous vertical tolerances (2m above and below).

### Threat Response

Each bot stores a single `aoe_threat` entry with:
- `expires` -- when the threat ends
- `escape_direction` -- pre-computed escape vector
- `dodge_t` -- randomized time to dodge: `min(t + random()*0.5, expires)`

In `BotUnitInput._update_movement()`:

1. If `t < threat_data.expires` and `t > threat_data.dodge_t`:
   - Fires `self:dodge()` (sets dodge input for next frame)
   - Sets movement direction to the escape direction
   - Sets `_avoiding_aoe_threat = true`
2. When `t >= threat_data.expires` and bot was avoiding:
   - If destination was reached, calls `navigation_extension:stop()`
   - Clears `_avoiding_aoe_threat`

**Key limitation:** Only one AoE threat is tracked per bot at a time. A new threat only
overwrites the existing one if its expiration is later.

### Bot Physical Parameters

| Constant | Value |
|----------|-------|
| `BOT_RADIUS` | 0.75m |
| `BOT_HEIGHT` | 1.8m |

---

## 6. Bot Group Formation

**Source:** `scripts/extension_systems/group/bot_group.lua`

### Follow Target Selection

`_update_move_targets()` selects which human player the bots should follow:

| Scenario | Selection Method |
|----------|-----------------|
| 0 human units | No follow target |
| 1 human unit | Follow that player (closest to avg bot position with stickiness) |
| 2 humans + 2 bots + carry event | Each bot follows a different human |
| 3+ humans | Follow the **least lonely** player (minimum sum of distances to others) |
| 3+ humans + carry event | Follow the **most lonely** player (reverse logic) |

**Stickiness values:**
- `LONELINESS_PREVIOUS_TARGET_STICKINESS` = 25 (sq meters bias for current target)
- `CLOSEST_TARGET_PREVIOUS_TARGET_STICKINESS` = 3m (distance bias for current target)
- `LONELINESS_FAR_AWAY_DISTANCE_SQ` = 900 (30m -- penalty for most-lonely if too far)

If bots are on a moveable platform (`block_bot_movement`), follow is disabled entirely.

### Cluster Position

The follow point is not the player's position directly. `_find_cluster_position()` projects
the player's position forward along their velocity:

1. Find navmesh position near the selected player
2. Raycast forward along the player's velocity (up to 5m, or 1m near daemonhost)
3. Place the cluster position at **60% interpolation** between the player's navmesh
   position and the raycast endpoint
4. If player is stopped (velocity < 0.1 sq), use their current position

The rotation/facing for the cluster is derived from:
1. Daemonhost direction (if near unaggroed daemonhost)
2. Player velocity direction (if moving)
3. Cached last rotation (if previously set)
4. Player's first-person look direction (fallback)

### Formation Point Distribution

`_find_destination_points()` distributes bots in a fan pattern around the cluster position:

- **Range:** 3m from cluster center
- **Spacing:** 1m per bot
- **Pattern:** Alternating left/right vectors at 22.5-degree increments (pi/8 steps)

The search uses navmesh raycasts from the origin along each direction. Points are placed
at intervals along the ray, stopping at walls. A minimum gap of **0.25m** from walls is
maintained.

### Point Assignment (Utility Optimization)

Bot-to-point assignment uses a brute-force permutation search to maximize total utility:

```
utility[bot][point] = 1 / sqrt(max(0.001, distance(bot, point)))
```

This assigns each bot to the closest available point while minimizing total travel. If a
bot has a hold position, it uses that instead of the assigned point.

### Disallowed Nav Tag Volume Handling

If the followed player enters a disallowed nav tag volume (e.g., hazard zone), bots find
positions **outside** the volume instead:

1. Identify the volume and its boundary points
2. Calculate volume center and radius
3. Search for valid navmesh points outside the volume along radiating directions
4. Assign bots to those exterior points

---

## 7. Movement During Combat

### Cover System

`BotBehaviorExtension._update_cover()` detects when the bot is in a ranged enemy's line
of fire and seeks cover:

**Line of fire check parameters:**
- `LINE_OF_FIRE_CHECK_LENGTH` = 40m
- `LINE_OF_FIRE_CHECK_WIDTH` = 2.5m (initial), 6m (sticky, once already in cover from this enemy)

Cover positions come from the main path's `nav_spawn_points`, filtered to positions
occluded from the threat. Bots avoid sharing cover positions (`set_in_cover`/`in_cover`
tracking per bot group).

Cover overrides the normal follow destination but respects hold position constraints.

### Melee Engage Position

When the melee BT action sets `melee_component.engage_position_set = true`, the movement
system overrides the follow destination with the engage position. If
`melee_component.stop_at_current_position` is set, the bot calls `navigation_extension:stop()`
instead of navigating.

### Combat-Movement Interaction

The movement system only updates when the bot is **alive, on the ground, not disabled,
and not on a moveable platform** (from `BotBehaviorExtension.update()`):

```lua
if is_disabled or is_on_moveable_platform then
    navigation_extension:teleport(self_position)  -- freeze in place
elseif in_air_state_component.on_ground then
    self:_handle_doors(unit)
    self:_update_movement_target(unit, dt, t)
end
```

During combat, the BT uses a `BtRandomUtilityNode` to weigh combat vs follow:
- Combat subtree: melee and ranged actions
- Follow subtree: reload, vent, and follow actions

Both subtrees run with `should_evaluate = true`, meaning the BT re-evaluates priority
every tick.

### Door Handling

When the navigation extension reports being in a `"doors"` transition, the bot
automatically opens the door via `door_extension:open(nil, unit)`.

### Dodging (AoE Only)

Bots only dodge in response to AoE threats (not melee attacks). The dodge input fires once
at `dodge_t` (randomized delay 0-0.5s), and movement is overridden with the escape direction
until the threat expires.

---

## 8. Relevance to BetterBots

### Movement State and Ability Activation

The `can_activate_ability` condition in the BT is evaluated **above** the combat/follow
selector (source lines 47-57 in `bot_behavior_tree.lua`), meaning it runs before any movement decisions. There are no
navigation-state gates in the ability condition -- it does not check whether the bot is in
a transition, moving, or stationary.

However, the BT node priority matters:
- Ability activation (index ~8-9) is higher priority than teleport (index ~11) and combat/follow
- If the ability condition passes, the bot will stop following and enter the ability action
- The follow destination refresh (1-1.5s timer) continues independently in `_update_movement_target()`

### Charge/Dash Abilities and Navigation

For Tier 2 charge abilities (Zealot Dash, Ogryn Charge), the ability action queues
`aim_pressed` followed by `aim_released`. During the charge:

- The bot's character state changes (e.g., `lunging`, `sprinting`)
- `PlayerNavTransitionGenerator` does NOT track these states -- only `jumping`, `falling`,
  and `ledge_vaulting` trigger transition creation
- The navigation extension continues updating normally
- If the charge moves the bot off the navmesh, `is_on_nav_mesh` becomes false
- When the charge ends and the bot lands, navmesh position is recalculated

**Potential issue:** A charge ability could move the bot to a position far from its
navigation path, causing the path to become invalid. The live path check will detect this
and trigger a re-path on the next `_update_path()` call.

### Teleport Interaction

Bots can teleport **during ability use** if the `is_too_far_from_ally` condition fires
(40m threshold), since that node is higher priority than combat actions. However, the
ability action's `enter()`/`run()` cycle would be interrupted by the teleport action
taking over.

The `cant_reach_ally` teleport (inside follow) is lower priority than abilities and will
not interrupt an active ability.

### Hold Position and Stay Near Player

`set_hold_position()` and `set_stay_near_player()` constrain bot movement:
- `hold_position`: bot cannot path to destinations outside the hold radius
- `stay_near_player`: range limit (default 5m) for straying from the player

These do not affect ability activation directly, but ability movement (charges, dashes)
could push the bot outside these boundaries. The movement system will attempt to return
the bot to the constrained area on the next tick.

### Moveable Platforms

When on a moveable platform (`locomotion_component.parent_unit ~= nil`), the bot's
navigation is frozen -- `navigation_extension:teleport(self_position)` is called every
frame, preventing path following. Ability activation is still possible since it is
evaluated before the movement update, but any movement-based ability would conflict with
the platform freeze.

### Key Constants Summary

| Constant | Value | Relevance |
|----------|-------|-----------|
| Teleport distance threshold | 40m (sq: 1600) | Bots teleport when this far from ally |
| Failed path threshold (behind) | >1 fail + 5s | Triggers cant_reach_ally teleport |
| Failed path threshold (other) | >5 fails + 5s | Triggers cant_reach_ally teleport |
| Follow refresh timer | 1.0-1.5s | How often bot recalculates destination |
| Transition timeout (general) | 10s | Re-paths after 10s stuck in transition |
| Transition timeout (jump/drop) | 5s | Force-teleports after 5s stuck |
| Formation range | 3m | Bot spread distance from cluster center |
| Formation spacing | 1m per bot | Distance between formation points |
| Cover line-of-fire width | 2.5m (6m sticky) | Detection cone for ranged threats |
| AoE dodge delay | 0-0.5s random | Response time to AoE threats |
