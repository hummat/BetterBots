# Bot Combat Action Nodes Reference

Decompiled source reference for the BT leaf actions that drive bot combat in Darktide.
All file paths are relative to `Darktide-Source-Code/`.

---

## Table of Contents

1. [Behavior Tree Priority Structure](#behavior-tree-priority-structure)
2. [BtBotActivateAbilityAction](#btbotactivateabilityaction) (critical for BetterBots)
3. [BtBotMeleeAction](#btbotmeleeaction)
4. [BtBotShootAction](#btbotshootaction)
5. [BtBotReloadAction](#btbotreloadaction)
6. [BtBotInventorySwitchAction](#btbotinventoryswitchaction)
7. [BtBotInteractAction](#btbotinteractaction)
8. [BtBotIdleAction](#btbotidleaction)
9. [Utility Considerations](#utility-considerations)
10. [Bot Action Data](#bot-action-data)
11. [BetterBots Mod Interaction](#betterbots-mod-interaction)

---

## Behavior Tree Priority Structure

Source: `scripts/extension_systems/behavior/trees/bot/bot_behavior_tree.lua`

The bot BT is a flat `BtSelectorNode` with strict priority ordering. Children are evaluated top-to-bottom; the first passing condition wins. The full order:

| Priority | Node | Condition | Action |
|----------|------|-----------|--------|
| 1 | `disabled` | `is_disabled` | `BtBotIdleAction` |
| 2 | `do_revive` | `can_revive` | `BtBotInteractAction` |
| 3 | `do_remove_net` | `can_remove_net` | `BtBotInteractAction` |
| 4 | `do_rescue_ledge_hanging` | `can_rescue_ledge_hanging` | `BtBotInteractAction` |
| 5 | `do_rescue_hogtied` | `can_rescue_hogtied` | `BtBotInteractAction` |
| 6 | `use_healing_station` | `can_use_health_station` | `BtBotInteractAction` |
| 7 | `loot` | `can_loot` | `BtBotInteractAction` |
| 8 | `activate_combat_ability` | `can_activate_ability` | `BtBotActivateAbilityAction` |
| 9 | `activate_grenade_ability` | `can_activate_ability` | `BtBotActivateAbilityAction` |
| 10 | `switch_to_proper_weapon` | `has_target` | `BtBotInventorySwitchAction` (sub-selector) |
| 11 | `attack_priority_target` | `has_priority_or_urgent_target` | Melee/Shoot sub-selector |
| 12 | `teleport_out_of_range` | `is_too_far_from_ally` | `BtBotTeleportToAllyAction` |
| 13 | `in_combat` | (utility node) | `BtRandomUtilityNode` with combat vs follow |
| 14 | `idle` | (always) | `BtBotIdleAction` |

Key observations:
- Ability activation (priority 8-9) outranks all combat actions (priority 10-13).
- Rescue/revive (priority 2-5) outranks ability activation.
- Priority target attacks bypass the utility scoring system entirely.
- The `BtRandomUtilityNode` (priority 13) uses utility scores to choose between combat and follow sub-trees.

---

## BtBotActivateAbilityAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua`

**This is the most critical file for BetterBots.** This action node handles all bot ability activation through the standard BT path.

### Class

```lua
BtBotActivateAbilityAction = class("BtBotActivateAbilityAction", "BtNode")
```

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)

1. Reads the ability component specified by `action_data.ability_component_name` (either `"combat_ability_action"` or `"grenade_ability_action"`).
2. Looks up the `template_name` from the component, then fetches the full ability template from `AbilityTemplates`.
3. Extracts `ability_meta_data` from the template, which contains three sub-tables:
   - `activation` -- the initial input to queue
   - `wait_action` -- optional follow-up input (e.g., release after hold)
   - `end_condition` -- optional condition for when the action is "done"
4. Stores these in scratchpad along with extensions needed for input queuing.
5. If `end_condition_data` exists, also stores `locomotion_component` and `navigation_extension` (used for movement-based end conditions like charge arrival).

Key scratchpad fields set:
- `scratchpad.do_start_input = true` -- signals first frame should queue activation
- `scratchpad.started = false` -- tracks whether activation input has been fully processed
- `scratchpad.enter_time = t` -- used for hold timing calculations

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t)

Two-phase execution:

**Phase 1: Start ability** (`scratchpad.started == false`)
- Calls `_start_ability()`, which handles the activation input sequence.
- Returns `"running"` unconditionally during this phase.

**Phase 2: Wait for completion** (`scratchpad.started == true`)
- If `wait_action_data` exists, calls `_perform_wait_action()` to queue the follow-up input.
- Calls `_evaluate_end_condition()` to determine if done.

No `leave()` method is defined -- the node relies on the BT framework's default cleanup.

### Internal Methods

#### _start_ability(self, scratchpad, t) -> do_start_input, started

Handles press-and-hold activation patterns:

1. First call: queues the `activation_data.action_input` via `bot_queue_action_input()` on the ability component.
2. Subsequent calls: checks if `min_hold_time` has elapsed since `enter_time`.
3. Once hold time is satisfied, returns `false, false` (do_start_input=false, started=false).
4. The next `run()` call sees `do_start_input=false` and the else branch sets `started=true`.

The hold pattern supports:
- **Instant abilities** (`min_hold_time = 0` or nil): activate immediately, started next frame.
- **Hold abilities** (`min_hold_time > 0`): hold the input for the specified duration.

```
Frame 1: queue action_input, do_start_input=true, started=false
Frame 2..N: waiting for min_hold_time, do_start_input=true, started=false
Frame N+1: hold satisfied, do_start_input=false, started=false
Frame N+2: started=true, proceed to wait_action / end_condition
```

#### _perform_wait_action(self, wait_action_data, scratchpad, action_data)

Queues a single follow-up input (e.g., `"aim_released"` after a charge, `"shout_released"` after a shout). Only fires once per action (guarded by `scratchpad.wait_action_started`).

Uses `action_data.ability_component_name` (from the BT node's action_data, not the scratchpad) to target the correct ability component.

#### _evaluate_end_condition(self, scratchpad, t) -> "done" | "running"

Two paths:
1. **No end condition** (`end_condition_data == nil` or `done_when_arriving_at_destination` not set): returns `"done"` immediately.
2. **Movement-based end** (`done_when_arriving_at_destination = true`): waits until either `navigation_extension:destination_reached()` returns true or velocity drops below `MIN_SPEED_SQ` (0.04), with a minimum duration of `MIN_DURATION` (0.5s).

### ability_meta_data Schema

The `ability_meta_data` table consumed by this action has this structure:

```lua
ability_meta_data = {
    activation = {
        action_input = "string",     -- REQUIRED: the input to queue (e.g., "stance_pressed", "aim_pressed")
        min_hold_time = number,       -- optional: seconds to hold before proceeding (default 0)
        used_input = "string",        -- optional: passed to action_input_is_currently_valid
    },
    wait_action = {                   -- optional: follow-up input after activation
        action_input = "string",      -- the release/confirm input (e.g., "aim_released", "shout_released")
    },
    end_condition = {                 -- optional: when the action is considered done
        done_when_arriving_at_destination = bool,  -- wait for nav destination or velocity stop
    },
}
```

### Ability Activation Patterns

| Pattern | activation.action_input | wait_action.action_input | end_condition | Examples |
|---------|------------------------|--------------------------|---------------|----------|
| Instant stance | `"stance_pressed"` | nil | nil | Psyker stance, Ogryn gunlugger |
| Press-release | `"combat_ability_pressed"` | `"combat_ability_released"` | nil | Veteran stealth |
| Aim-release with movement | `"aim_pressed"` | `"aim_released"` | `done_when_arriving_at_destination` | Zealot dash, Ogryn charge |
| Shout | `"shout_pressed"` | `"shout_released"` | nil | Ogryn taunt, Psyker shout |

### Condition Gate: can_activate_ability

Source: `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua:59-100`

The vanilla condition function is the primary gate that prevents most abilities from activating:

```lua
conditions.can_activate_ability = function(unit, blackboard, scratchpad, condition_args, action_data, is_running)
    -- 1. If already running this ability component, pass through
    -- 2. Read ability_component, get template_name
    -- 3. If template_name == "none", return false
    -- 4. Look up ability_template, check ability_meta_data exists
    -- 5. Validate action_input is currently valid via ability_extension
    -- 6. WHITELIST: only "zealot_relic" and "veteran_combat_ability" pass
    -- 7. Everything else: return false  <-- THIS IS THE GATE
end
```

The vanilla code has two specialized sub-conditions:
- `_can_activate_zealot_relic`: challenge-rating threshold (1.75) within 10m radius, with 1.25x multiplier for enemies targeting the bot.
- `_can_activate_veteran_ranger_ability`: requires target enemy to have `special` or `elite` tags.

---

## BtBotMeleeAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua`

The most complex combat action node. Handles melee attacking, blocking, pushing, dodging, and engage/disengage positioning.

### Class

```lua
BtBotMeleeAction = class("BtBotMeleeAction", "BtNode")
```

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)

Extensive setup:
- Enables soft aiming via `bot_unit_input:set_aiming(true, soft_aiming)`.
- Caches weapon template, bot group, navigation, perception, stamina, and attack intensity extensions.
- Stores `weapon_action_component`, `weapon_extension`, `action_input_extension` for input queuing.
- Sets `engaging = false`, `engage_change_time = 0`.

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t) -> status, evaluate

Delegates to `_update_melee()`. Returns `"done"` if target is dead, otherwise `"running"` with an evaluation flag.

#### leave(self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)

- Disables aiming.
- Disengages if currently engaged.
- Clears all pending weapon action inputs and stops current weapon action (`weapon_extension:stop_action("bot_left_node", ...)`).

### Core Logic: _update_melee()

The main update loop runs every frame while the melee action is active:

1. **Target validation**: If target is dead, return done.
2. **Enemy count**: Queries `perception_extension:enemies_in_proximity()` for nearby enemy count.
3. **Aim**: Sets aim position to target's `bot_melee_aim_node` (default `"j_spine"`).
4. **Attack selection**: Calls `_choose_attack()` to select best `attack_meta_data` entry.
5. **Range calculation**: Computes melee range from attack metadata + target hitbox approximation.
6. **Range check**: `_is_in_melee_range()` uses velocity prediction to determine if attack will connect.
7. **Defense**: `_should_defend()` checks `num_melee_attackers() > 0`.

State machine priority (evaluated top to bottom):
```
if should_defend and not is_defending -> start block
elif is_defending -> update defend (push/release)
elif is_attacking -> continue attack sequence
elif is_in_melee_range -> start new attack if possible
elif is_in_engage_range -> wants engage
else -> may disengage
```

8. **Engage/disengage**: Updates engage position for navigation system.
9. **Dodge**: `_update_dodge()` triggers evasion based on attack intensity.

### Attack Selection: _choose_attack()

Source: lines 289-319

Iterates all entries in `weapon_template.attack_meta_data` (or `DEFAULT_ATTACK_META_DATA` if missing) and scores them:

| Condition | Utility Bonus |
|-----------|---------------|
| Outnumbered (>1 enemy) and arc == 1 | +1 |
| No-damage attack, massively outnumbered (>3), arc > 1 | +2 |
| Damaging attack: outnumbered + wide arc, or single target + arc == 0 | +4 |
| Target is not armored, OR attack is penetrating | +8 |

The highest utility attack is selected. The `+8` for armor penetration dominates, making penetrating attacks strongly preferred against armored enemies.

**DEFAULT_ATTACK_META_DATA** (used when weapon has no `attack_meta_data`):
```lua
{
    light_attack = {
        arc = 0,
        penetrating = false,
        max_range = 2.5,
        action_inputs = {
            { action_input = "start_attack", timing = 0 },
            { action_input = "light_attack", timing = 0 },
        },
    },
}
```
When `attack_meta_data` is missing, the bot falls back to light attacks only.

### attack_meta_data Schema

Each entry in `weapon_template.attack_meta_data`:

```lua
{
    arc = number,            -- 0 = single target, 1 = narrow arc, >1 = wide arc
    penetrating = bool,      -- effective against armored targets
    no_damage = bool,        -- true for push/shove attacks
    max_range = number,      -- melee reach in meters (default 2.5)
    action_inputs = {        -- sequence of inputs to execute the attack
        { action_input = "string", timing = number },  -- timing is delay from previous
        ...
    },
}
```

### Attack Execution: _start_attack() and _update_attack()

Attack execution is a multi-frame input sequence:

1. `_start_attack()` sets `is_attacking = true`, stores the chosen `attack_meta_data`, resets `next_action_input_i = 1`.
2. `_can_start_attack()` validates the first action_input via `weapon_extension:action_input_is_currently_valid()`.
3. `_update_attack()` processes the sequence:
   - Waits for previous input to be consumed (`bot_queue_request_is_consumed()`).
   - At the scheduled time, queues the next `action_input` via `bot_queue_action_input("weapon_action", ...)`.
   - When all inputs are queued, sets `is_attacking = false`.

### Defense: Block, Push, Dodge

**Blocking**: Uses `defense_meta_data` from weapon template (or `DEFAULT_DEFENSE_META_DATA`):
```lua
DEFAULT_DEFENSE_META_DATA = {
    push = "heavy",
    push_action_input = "push",
    start_action_input = "block",
    stop_action_input = "block_release",
}
```

**Push decision** (`_should_push()`):
- Requires: in melee range, outnumbered (>1 enemy), target is pushable, sufficient stamina, push action is valid.
- Non-pushable: monsters, armored targets (unless push type is `"heavy"`).

**Dodge** (`_update_dodge()`):
- Triggered when `num_melee_attackers() > 0`.
- Direction: 50% chance away from target, 50% chance left/right.
- Validates escape path via `NavQueries.ray_can_go()`.
- Cooldown: 0.5-2s normally, 0.1-0.2s when unable to push (more aggressive dodging).

### Engage/Disengage

**Engage range** (from `action_data`):
- `fight_melee`: engage_range=6, near_follow=10, override to follow=12 (challenge-scaled to 6).
- `fight_melee_priority_target`: all ranges = `math.huge` (always engage priority targets).

**Engage position** (`_update_engage_position()`):
- If target breed has `bots_should_flank`: calculates flanking position around the enemy.
- Otherwise: approaches from current direction or stops if already in melee distance.
- Position is projected onto nav mesh with fan-search pattern (7 positions checked in 180-degree arc).

**Allow engage** (`_allow_engage()`): Checks distance to follow position, path segment ordering, ally rescue priority, darkness, and `should_stay_near_player`.

### Evaluation Timers

| State | Timer (seconds) |
|-------|----------------|
| Defending | 2 |
| Attacking | infinity (no re-evaluation during attack) |
| In melee range | 2 |
| In engage range | 1 |
| Default (neither) | 3 |

---

## BtBotShootAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua`

### Class

```lua
BtBotShootAction = class("BtBotShootAction", "BtNode")
```

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)

Complex setup from `weapon_template.attack_meta_data` (ranged variant):
- Resolves action names: aim/unaim/fire/aim-fire actions from template.
- Extracts projectile templates for normal and charged shots.
- Configures aiming: `aim_data` (accuracy parameters), `aim_at_node` (target bone).
- Configures charging: `can_charge_shot`, `charge_action_input`, `charge_range_sq`, etc.
- Sets collision filter for obstruction checks.
- Enables hard aiming: `bot_unit_input:set_aiming(true, soft_aiming=false, use_rotation=true)`.

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t) -> status, evaluate

Delegates to `_update_aim()`. Never returns `"done"` -- always `"running"` with periodic evaluation.

#### leave(self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)

- Disables aiming.
- Clears all pending weapon inputs.
- Stops aiming action (unzooms).

### Core Logic: _update_aim()

Per-frame loop:

1. **Target tracking**: If target changed, calls `_set_new_aim_target()`.
2. **Aim calculation**: `_aim_position()` computes wanted rotation with velocity-based lead prediction and angular aim speed simulation.
3. **Obstruction check**: Periodic raycast (`_reevaluate_obstruction()`) to detect friendly fire or static obstacles.
4. **Charge decision**: `_should_charge()` determines if charged shot is warranted.
5. **Aim quality check**: `_aim_good_enough()` uses pseudo-random probability based on angular offset.
6. **Fire permission**: `_may_fire()` validates range, obstruction, charge state, aim time, and action input validity.
7. **Fire**: Queues the fire input.

### Aiming System

**Aim speed**: Controlled by `action_data.aim_speed` table indexed by difficulty (challenge level 1-5). Default values: `{10, 10, 12, 20, 20}`. Higher = faster tracking.

**Aim accuracy** (`_aim_good_enough()`):
- Uses pseudo-random distribution with accumulating rolls.
- `aim_data.min_radius` (pi/72 ~= 2.5 degrees): below this, uses `min_radius_pseudo_random_c` (0.0557).
- `aim_data.max_radius` (pi/16 ~= 11.25 degrees): above this, never fires.
- Between: linearly interpolated probability. Accumulates `num_aim_rolls` to increase fire chance over time.

**Projectile lead prediction**: For projectile weapons with gravity, uses `Trajectory.angle_to_hit_moving_target()` to calculate ballistic arc angle.

### Charged Shots

`_should_charge()` returns true when:
- `can_charge_shot` is set in attack_meta_data.
- Not on cooldown (`next_charge_shot_t`).
- Target is within charged range.
- Not obstructed (unless `charge_when_obstructed` is set).
- OR: `always_charge_before_firing` flag is set.
- OR: target is outside normal range but within charged range.
- OR: target is armored and `charge_against_armored_enemy` is set.

Charging queues the `charge_action_input` (default `"brace"`) and sets `charging_shot = true`.

### Fire Decision

`_may_fire()` requires all of:
1. No pending fire request.
2. Shot is not obstructed.
3. If aiming, `aim_done_t` has passed (0.2s minimum aim time).
4. If charging, minimum charge time is satisfied.
5. Target is within max range (normal or charged).
6. Fire action input is currently valid.

### Obstruction

Raycast from camera position along aim direction. Iterates all hits:
- Skips afro hitzone, allied units (if `ignore_allies`), enemy units (if `ignore_enemies`).
- If target unit is hit first: not obstructed.
- If anything else (non-ragdolled, non-self): obstructed.
- Tracks `obstructed_by_static` flag for blackboard.

**Collision filters**:
- Important targets (priority target, or enemy attacking downed ally): `"filter_player_character_shooting_raycast_statics"` (ignores all units, only checks statics).
- Otherwise: determined by `attack_meta_data.ignore_enemies_for_obstruction` and `ignore_allies_for_obstruction`.

### Gestalt Behaviors

The shoot action supports aim-down-sights via gestalt behaviors (from `action_data.gestalt_behaviors`):
- `"none"`: no aiming.
- `"killshot"`: `wants_aim = true` -- queues zoom/aim input before firing.

The ranged gestalt is read from `behavior_component.ranged_gestalt`.

### Evaluation

Re-evaluation triggers:
- After firing: `evaluation_duration` (2s).
- Without firing: `evaluation_duration_without_firing` (3s).
- Obstruction re-check: every 0.2-0.3s.

---

## BtBotReloadAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_reload_action.lua`

The simplest combat-related action.

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)
Sets `scratchpad.is_reloading = true` and caches `action_input_extension`.

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t)
- Continuously queues `"reload"` input on `"weapon_action"` component.
- Waits for previous reload request to be consumed before queuing next.
- Always returns `"running"` with `should_evaluate = true` (BT re-evaluates every frame).

#### leave(self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)
Sets `is_reloading = false`, clears pending requests.

### Notes

- Also used for venting overheat (same reload input, different BT context under `"vent_overheat"` sub-tree).
- The BT arranges weapon switch before reload if not already wielding the ranged weapon.

---

## BtBotInventorySwitchAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_inventory_switch_action.lua`

### Constants

```lua
TIME_TO_FIRST_EVALUATE = 0.3
CONSECUTIVE_EVALUATE_INTERVAL = 0.25
ACTION_INPUT_INTERVAL = 0.1
```

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)
Caches inventory component, action_input_extension, weapon_extension.

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t)

Three outcomes:
1. **Done**: `inventory_component.wielded_slot == wanted_slot` -- already holding the right weapon.
2. **Evaluate**: Past evaluation time -- returns running with evaluate flag.
3. **Queue wield**: Queues `"wield"` action input with `PlayerUnitVisualLoadout.wield_input_from_slot_name(wanted_slot)` as raw_input. Validates via `action_input_is_currently_valid()` first.

### Wield Targets (from bot_actions.lua)

| Node name | wanted_slot |
|-----------|-------------|
| `switch_melee` | `"slot_primary"` |
| `switch_ranged` | `"slot_secondary"` |
| `switch_ranged_overheat` | `"slot_secondary"` |
| `switch_ranged_reload` | `"slot_secondary"` |

---

## BtBotInteractAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action.lua`

### Lifecycle

#### enter(self, unit, breed, blackboard, scratchpad, action_data, t)
- Reads `interaction_unit` from behavior blackboard.
- Determines `interaction_type` from action_data or the interactee extension.
- Sets bot interaction unit via `interactor_extension:set_bot_interaction_unit()`.
- Enables soft aiming toward the interaction target.
- Retry timer: `try_again_time = 3` seconds.

#### run(self, unit, breed, blackboard, scratchpad, action_data, dt, t)
- If interaction unit changed (blackboard updated), returns `"failed"`.
- Calls `bot_unit_input:interact()` every frame (with reset every 3s).
- Aims at the target's `aim_node` (default bone index 1, or `action_data.aim_node`).
- Always returns `"running"`.

#### leave(self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)
- Clears `current_interaction_unit` in blackboard.
- Clears bot interaction unit in interactor extension.
- Disables aiming.

### Interaction Types (from bot_actions.lua)

| Node name | interaction_type | aim_node |
|-----------|-----------------|----------|
| `do_revive` | `"revive"` | `"j_head"` |
| `do_rescue_ledge_hanging` | `"pull_up"` | `"j_head"` |
| `do_rescue_hogtied` | `"rescue"` | `"j_head"` |
| `do_remove_net` | `"remove_net"` | `"j_head"` |
| `use_healing_station` | (from interactee) | (default) |
| `loot` | (from interactee) | (default) |

---

## BtBotIdleAction

Source: `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_idle_action.lua`

Minimal action: no enter/leave, run always returns `"running"`. Used as the disabled-state handler and fallback.

---

## Utility Considerations

Source: `scripts/extension_systems/behavior/utility_considerations/bot_utility_considerations.lua`

The `BtRandomUtilityNode` (priority 13 in the BT) uses utility scoring to decide between combat and follow sub-trees.

### bot_combat

```lua
distance_to_target = {
    blackboard_component = "perception",
    component_field = "target_enemy_distance",
    max_value = 40,
    spline = { 0, 1,  0.25, 0.25,  0.75, 0,  1, 0 },
}
```

Spline interpretation (distance normalized to 0-40m):
- 0m: utility = 1.0 (maximum)
- 10m (25%): utility = 0.25
- 30m (75%): utility = 0.0
- 40m: utility = 0.0

Combat utility drops sharply with distance and reaches zero at ~30m.

### bot_follow

```lua
distance_to_target = {
    blackboard_component = "perception",
    component_field = "target_ally_distance",
    max_value = 40,
    spline = { 0, 0.1,  0.25, 0.2,  0.75, 1,  1, 1 },
}
```

Spline interpretation (distance to ally normalized to 0-40m):
- 0m: utility = 0.1 (low -- already close)
- 10m: utility = 0.2
- 30m: utility = 1.0 (maximum -- far from ally)
- 40m: utility = 1.0

Follow utility increases with distance from ally, creating the basic "stay near ally but fight when enemies are close" behavior.

Both utility weights are `1`, so they compete equally. The crossover point is around 10m from enemy / 10m from ally.

---

## Bot Action Data

Source: `scripts/settings/breed/breed_actions/bot_actions.lua`

Configuration passed to each BT node as `action_data`:

### Ability Activation
```lua
activate_combat_ability = { ability_component_name = "combat_ability_action" }
activate_grenade_ability = { ability_component_name = "grenade_ability_action" }
```

### Melee
```lua
fight_melee = {
    engage_range = 6,
    engage_range_near_follow_position = 10,
    override_engage_range_to_follow_position = 12,
    override_engage_range_to_follow_position_challenge = 6,
}
fight_melee_priority_target = {
    engage_range = math.huge,
    engage_range_near_follow_position = math.huge,
    override_engage_range_to_follow_position = math.huge,
    override_engage_range_to_follow_position_challenge = math.huge,
}
```

### Ranged
```lua
shoot = {
    evaluation_duration = 2,
    evaluation_duration_without_firing = 3,
    maximum_obstruction_reevaluation_time = 0.3,
    minimum_obstruction_reevaluation_time = 0.2,
    aim_speed = { 10, 10, 12, 20, 20 },
    gestalt_behaviors = {
        none = {},
        killshot = { wants_aim = true },
    },
}
```

---

## BetterBots Mod Interaction

Source: `BetterBots/scripts/mods/BetterBots/BetterBots.lua`

### How BetterBots hooks into these action nodes

#### 1. Condition replacement (lines 1227-1259)

BetterBots replaces `conditions.can_activate_ability` in both `bt_bot_conditions` and `bt_conditions` via `hook_require`. The replacement (`_can_activate_ability`) removes the vanilla whitelist and instead:

- Passes any ability with valid `ability_meta_data.activation.action_input`.
- Validates the action input is currently usable via `ability_extension:action_input_is_currently_valid()`.
- Falls back to vanilla heuristics for `zealot_relic` (challenge rating threshold) and `veteran_combat_ability` (elite/special tag check).
- Uses `enemies_in_proximity() > 0` as the generic trigger for all other abilities.

#### 2. Metadata injection (lines 63-209, 1223-1225)

BetterBots injects `ability_meta_data` into ability templates that lack it (Tier 2 abilities) and overrides incorrect metadata for veteran templates. This is consumed directly by `BtBotActivateAbilityAction.enter()` when it reads `ability_template.ability_meta_data`.

Templates injected via `TIER2_META_DATA`:
- `zealot_invisibility`, `zealot_dash`, `ogryn_charge`, `ogryn_taunt_shout`, `psyker_shout`, `adamant_shout`, `adamant_charge`

Templates overridden via `META_DATA_OVERRIDES`:
- `veteran_combat_ability`, `veteran_stealth_combat_ability` (stance_pressed -> combat_ability_pressed)

#### 3. Ability enter hook (lines 1261-1288)

`hook_safe` on `BtBotActivateAbilityAction.enter` for debug logging. Does not modify behavior.

#### 4. Fallback ability activation (lines 1071-1221, 1437-1446)

`hook_safe` on `BotBehaviorExtension.update` calls `_fallback_try_queue_combat_ability()` every bot tick. This handles:

- **Standard abilities** (with `ability_meta_data`): Directly queues activation input on the ability component, manages hold timing and wait_action inputs in a simple state machine parallel to the BT path.
- **Item-based abilities** (Tier 3, no `ability_template`): Multi-stage item sequence: wield combat ability slot -> queue start input -> followup input -> unwield. Uses `ITEM_SEQUENCE_PROFILES` to match weapon template action_inputs.

This fallback runs alongside the BT path. Both can attempt activation; the game's input system handles deduplication.

#### 5. Weapon switch lock (lines 1376-1411)

`hook` on `PlayerUnitActionInputExtension.bot_queue_action_input` intercepts `"wield"` inputs on `"weapon_action"` to prevent weapon switching during item-based ability sequences (Tier 3). This prevents the BT's `switch_to_proper_weapon` node from interrupting a relic channel or force field placement.

The lock is intentionally disabled once the unit has a live interaction target. Interaction entry requests `slot_unarmed`, and overriding that request with `slot_combat_ability` can break the character-state interaction path.

#### 6. State transition failure recovery (lines 1329-1374)

`hook` on `ActionCharacterStateChange.finish` detects when a bot's combat ability activation fails due to character state transition rejection. Schedules a fast retry (0.35s) to re-attempt.

#### 7. Charge event tracking (lines 1290-1327)

`hook_safe` on `PlayerUnitAbilityExtension.use_ability_charge` tracks when a bot's combat ability charge is consumed, enabling the item sequence fallback to confirm its activation succeeded.

### Opportunities for future enhancement

1. **Per-career trigger heuristics**: The generic `enemies_in_proximity() > 0` trigger could be replaced with per-ability logic similar to the existing `_can_activate_zealot_relic` (challenge rating) and `_can_activate_veteran_ranger_ability` (elite/special check). Charge abilities should consider enemy positioning; buff abilities could factor in group health.

2. **Grenade ability support**: The BT has an `activate_grenade_ability` node (priority 9) pointing to `grenade_ability_action`. Currently blocked by the same condition gate. Grenade abilities are item-based (Tier 3) and would need an item sequence similar to the combat ability fallback.

3. **Aim position during ability activation**: `BtBotActivateAbilityAction` does not set aim direction. For charge abilities (zealot dash, ogryn charge), the bot charges toward its current navigation destination. A hook could set aim toward the highest-threat enemy cluster to improve charge targeting.

4. **Cooldown awareness**: The condition check validates `action_input_is_currently_valid` but does not consider cooldown progress or charge count. Adding cooldown-based throttling could prevent wasted activations.

5. **Utility integration**: Ability activation is hard-prioritized (priority 8-9) above all combat. This means abilities fire whenever the condition passes, regardless of whether fighting or following would be more useful. Integrating ability activation into the utility node (priority 13) with its own consideration curve would allow more nuanced decision-making.
