# Bot Input System and Action Data

How behavior tree decisions become game inputs that fire abilities, weapons, and interactions.

**Source version:** Darktide v1.10.7 (decompiled via Aussiemon/Darktide-Source-Code)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [BotUnitInput — The Low-Level Input Layer](#botunitinput--the-low-level-input-layer)
3. [PlayerUnitInputExtension — Input Routing](#playerunitinputextension--input-routing)
4. [Action Input Queuing — The High-Level Action Layer](#action-input-queuing--the-high-level-action-layer)
5. [ActionInputParser Internals](#actioninputparser-internals)
6. [bot_actions.lua — BT Action Data](#bot_actionslua--bt-action-data)
7. [BT Action Nodes That Queue Inputs](#bt-action-nodes-that-queue-inputs)
8. [ability_meta_data Structure](#ability_meta_data-structure)
9. [Input Buffering and Timing](#input-buffering-and-timing)
10. [Relevance to BetterBots](#relevance-to-betterbots)

---

## Architecture Overview

There are **two distinct input pathways** for bots, serving different purposes:

```
BT Node Decision
  |
  +-- LOW-LEVEL PATH (movement, aim, dodge, interact)
  |     BotUnitInput._input / ._move tables
  |       -> PlayerUnitInputExtension.get(action)
  |         -> character state machine, locomotion, etc.
  |
  +-- HIGH-LEVEL PATH (weapon attacks, abilities, reload, wield)
        action_input_extension:bot_queue_action_input(component, action_input, raw_input)
          -> ActionInputParser._bot_action_input_request_queue (ring buffer, max 5)
            -> ActionInputParser.fixed_update() drains queue
              -> ActionInputParser._queue_action_input() into input_queue
                -> Action system consumes via peek_next_input() / consume_next_input()
                  -> Ability/weapon fires
```

**Key distinction:** Movement, aiming, dodging, and interacting go through `BotUnitInput.get()` — a simple key-value lookup polled every frame. Weapon attacks and ability activations go through the `ActionInputParser` bot request queue, which handles input hierarchies, buffering, and sequencing.

---

## BotUnitInput -- The Low-Level Input Layer

**Source:** `scripts/extension_systems/input/bot_unit_input.lua`

### Lifecycle

| Method | When | Purpose |
|--------|------|---------|
| `update(unit, dt, t)` | Every frame | Clears `_input`, runs `_update_movement` + `_update_actions`, stores ephemeral inputs |
| `fixed_update(unit, dt, t, frame)` | Every fixed tick | Merges ephemeral inputs into `_input`, clears ephemeral buffer |
| `get(action)` | Polled by systems | Returns input value for given action name |

### Update Order (per frame)

1. `_input` table is **cleared** via `table.clear(input)`
2. `_update_movement(unit, input, dt, t)` — sets `move.x`/`move.y`, `input.jump`, `input.crouching`
3. `_update_actions(input)` — sets `input.interact_pressed`, `input.interact_hold`, `input.dodge`
4. `_store_ephemeral_input(input)` — copies ephemeral action values to `_ephemeral_input` for next fixed tick

### The `get(action)` Method

```lua
BotUnitInput.get = function (self, action)
    if action == "move" then
        return Vector3(self._move.x, self._move.y, 0)
    elseif self._input[action] ~= nil then
        return self._input[action]
    end
end
```

Returns `nil` for any action not currently set — callers treat `nil` as `false`/inactive.

### Input Fields Set by BotUnitInput

| Field | Type | Set By | When |
|-------|------|--------|------|
| `move` (via `get("move")`) | Vector3 | `_update_movement` | Navigation goal exists |
| `jump` | boolean | `_update_movement` | Lower obstacle detected or nav transition requires jump |
| `crouching` | boolean | `_update_movement` | Upper obstacle detected and already crouching or slow |
| `interact_pressed` | boolean | `_update_actions` | First frame of interact (edge trigger) |
| `interact_hold` | boolean | `_update_actions` | Continuous while interact active |
| `dodge` | boolean | `_update_actions` | `dodge()` was called this frame |

### Ephemeral Actions

`InputHandlerSettings.ephemeral_actions` defines one-frame pulse inputs. After each frame update, BotUnitInput copies any set ephemeral values to `_ephemeral_input`. On the next `fixed_update`, these are merged into `_input` and the ephemeral buffer is cleared.

This ensures ephemeral inputs (like `jump`, `dodge`, `combat_ability_pressed`, etc.) survive across the frame/fixed-tick boundary. The full ephemeral list includes:

- `jump`, `dodge`, `crouch`, `sprint`
- `action_one_pressed`, `action_one_release`, `action_two_pressed`, `action_two_release`
- `combat_ability_pressed`, `combat_ability_release`
- `grenade_ability_pressed`, `grenade_ability_release`
- `weapon_extra_pressed`, `weapon_extra_release`
- `weapon_reload_pressed`, `interact_pressed`
- `quick_wield`, `wield_scroll_down`, `wield_scroll_up`, `wield_1`..`wield_5`

**Important:** BotUnitInput only sets `jump`, `crouching`, `interact_pressed/hold`, and `dodge` in `_update_actions` and `_update_movement`. It does NOT set weapon/ability raw inputs (like `combat_ability_pressed`). Those go through the ActionInputParser's bot request queue instead.

**With BetterBots `#87`:** supported sustained-fire ranged paths are the exception to that last sentence. The queued `weapon_action` still enters through `ActionInputParser`, but `sustained_fire.lua` mirrors the required low-level hold inputs back into `BotUnitInput._update_actions` while the sustained path is active. That bridge currently covers `action_one_hold` full-auto/stream paths plus Purgatus's `action_two_hold` flame-charge hold.

### Setter Methods Called by BT Nodes

| Method | Called By | Effect |
|--------|-----------|--------|
| `set_aim_position(pos)` | shoot, melee | Where the bot looks |
| `set_aim_rotation(rot)` | shoot | Direct rotation aim (for precise aiming) |
| `set_aiming(aiming, soft, use_rotation)` | shoot, melee, ability | Controls `_aiming`, `_soft_aiming`, `_aim_with_rotation` — determines how `_update_movement` calculates `wanted_rotation` |
| `set_look_at_player_unit(unit, rotation_allowed)` | follow | Look at specific player |
| `interact(reset)` | rescue, revive | Sets `_interact = true` |
| `dodge()` | melee, AOE threat | Sets `_dodge = true` |

### Movement Calculation

`_update_movement` converts navigation goals into movement inputs:

1. **Rotation:** Determined by priority: ladder > aim_with_rotation > soft_aiming > hard_aiming > look_at_player > navigation goal > unit rotation
2. **Move vector:** Projects flat goal direction onto camera right/forward to get `move.x`/`move.y` (relative to facing)
3. **Jump/Crouch:** `_obstacle_check` does two box overlap tests (lower + upper) in the goal direction. Lower hit without upper = jump. Upper hit without lower = crouch.
4. **AOE threat override:** If active threat data exists, movement follows `threat_data.escape_direction` and triggers dodge

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `MOVE_SCALE_START_DIST_SQ` | 0.01 | Start slowing when near last goal |
| `MOVE_SCALE_FACTOR` | 99.995 | Scale factor for smooth deceleration |
| `STUCK_JUMP_SPEED_THRESHOLD` | 0.2 | Speed below which lower obstacle box is larger |
| `STUCK_CROUCH_SPEED_THRESHOLD` | 0.5 | Speed threshold for crouch decisions |
| `MIN_JUMP_DIRECTION_DOT` | cos(pi/16) | Must be facing goal direction to jump during transitions |

---

## PlayerUnitInputExtension -- Input Routing

**Source:** `scripts/extension_systems/input/player_unit_input_extension.lua`

This is the central switchboard that routes all input queries to either `HumanUnitInput` or `BotUnitInput`.

### The `is_human_controlled()` Gate

Every method checks `self._player:is_human_controlled()`:

```lua
PlayerUnitInputExtension.get = function (self, action)
    if self._player:is_human_controlled() then
        result = self._human_unit_input:get(action)
    else
        result = self._bot_unit_input:get(action)
    end
    return result
end
```

The same pattern applies to `fixed_update`, `update`, `get_orientation`, and `had_received_input`.

### Key Points

- **Server-only bot input:** `BotUnitInput` is only created when `is_server` is true (line 17-21). Bots only exist on the server.
- **Bot always has input:** `had_received_input()` returns `true` unconditionally for bots (no network latency to wait for).
- **Update gating:** `update()` only calls bot update when NOT human-controlled. `fixed_update()` calls whichever is active.
- **`bot_unit_input()` accessor:** Returns the `BotUnitInput` instance. BT action nodes use this to call `set_aiming()`, `set_aim_position()`, `dodge()`, `interact()`.

### Extension Registration

The extension is registered under `"input_system"`. BT nodes access it via:
```lua
local input_extension = ScriptUnit.extension(unit, "input_system")
local bot_unit_input = input_extension:bot_unit_input()
```

---

## Action Input Queuing -- The High-Level Action Layer

**Source:** `scripts/extension_systems/action_input/player_unit_action_input_extension.lua`

This extension manages **four independent ActionInputParser instances**, one per action component:

| Component Name | Parser ID | Action Input Type | Templates | Ability Component |
|---|---|---|---|---|
| `weapon_action` | `"weapon_action"` | `"weapon"` | WeaponTemplates | — |
| `combat_ability_action` | `"combat_ability_action"` | `"ability"` | AbilityTemplates | `"combat_ability"` |
| `grenade_ability_action` | `"grenade_ability_action"` | `"ability"` | AbilityTemplates | `"grenade_ability"` |
| `pocketable_ability_action` | `"pocketable_ability_action"` | `"ability"` | AbilityTemplates | `"pocketable_ability"` |

### The `bot_queue_action_input` Method

```lua
PlayerUnitActionInputExtension.bot_queue_action_input = function (self, id, action_input, raw_input)
    local parser = self._action_input_parsers[id]
    return parser:bot_queue_action_input(action_input, raw_input)
end
```

**Parameters:**
- `id` — Component name string, e.g., `"combat_ability_action"`, `"weapon_action"`
- `action_input` — The action input name, e.g., `"stance_pressed"`, `"shoot"`, `"start_attack"`, `"reload"`
- `raw_input` — Optional raw input name, e.g., `"wield_1"` for slot switches. Usually `nil` for bots.

**Returns:** `global_bot_request_id` — an incrementing integer used to track consumption.

### Related Bot Methods

| Method | Purpose |
|--------|---------|
| `bot_queue_action_input(id, action_input, raw_input)` | Queue an input for the bot |
| `bot_queue_request_is_consumed(id, global_bot_request_id)` | Check if a previously queued request has been processed |
| `bot_queue_clear_requests(id)` | Clear all pending bot requests (used on node leave) |
| `clear_input_queue_and_sequences(id)` | Clear the main input queue and all running sequences |
| `peek_next_input(id)` | Look at next queued input without consuming |
| `consume_next_input(id, t)` | Consume the next queued input (called by action system) |

### Parser-to-Ability Mapping

For ability parsers, a `_parser_by_ability_type` lookup maps `"combat_ability"` -> combat_ability_action parser, etc. This allows `clear_input_queue_and_sequences_by_ability_type(ability_type)`.

---

## ActionInputParser Internals

**Source:** `scripts/extension_systems/action_input/action_input_parser.lua`

### Bot Request Ring Buffer

The parser maintains a separate ring buffer for bot requests:

```
BOT_REQUEST_RING_BUFFER_MAX = 5
_bot_action_input_request_queue[1..5] = {
    action_input = <string>,
    raw_input = <string>,
    global_bot_request_id = <int>,
}
```

**Queuing (`bot_queue_action_input`):**
1. Checks if buffer is full (`num_requests >= 5`). If full, calls `ferror()` (crash).
2. Writes request to `buffer[global_id % 5 + 1]`
3. Increments `_global_bot_request_id` and `_num_bot_action_input_requests`
4. Returns the `global_bot_request_id` for tracking

**Consumption check (`bot_queue_request_is_consumed`):**
Checks if the entry at `buffer[global_id % 5 + 1]` still has the same `global_bot_request_id`. If not (overwritten by a newer request), it has been consumed. Returns `true` when consumed.

### Fixed Update — Bot Path

In `fixed_update`, the parser branches on `is_human_controlled()`:

```lua
if self._player:is_human_controlled() then
    self:_update_sequences(...)    -- processes raw inputs from keyboard/gamepad
else
    if num_bot_action_input_requests > 0 then
        self:_update_bot_action_input_requests(...)
    end
end
```

**`_update_bot_action_input_requests` does:**
1. Iterates over pending requests in ring buffer order
2. For each request, looks up `sequence_configs[action_input]` from the current template
3. If a matching config exists, calls `_queue_action_input()` to place it in the main input queue
4. Resets the request entry
5. Sets `_num_bot_action_input_requests = 0` (all consumed in one tick)

**Critical: If `sequence_configs[action_input]` is nil (action_input doesn't exist in template), the request is silently dropped with a log warning.** This is why ability templates must have the correct `action_input` names in their `action_input_sequences`.

### Input Sequence Configs

Each action template defines `action_input_sequences` that the `ActionInputFormatter` processes into `_ACTION_INPUT_SEQUENCE_CONFIGS`. For human input, these configs define multi-element sequences (e.g., "press, hold for 0.2s, release"). For bots, the parser skips sequence evaluation entirely and directly queues the action_input.

### The Main Input Queue

A ring-buffered array of entries:
```lua
entry = {
    [ACTION_INPUT] = <action_input_name>,  -- e.g., "stance_pressed"
    [RAW_INPUT] = <raw_input_name>,        -- e.g., NO_RAW_INPUT
    [HIERARCHY_POSITION] = { ... },         -- hierarchy state when queued
}
```

The action system calls `peek_next_input()` to see what's queued, then `consume_next_input(t)` to process it. This is how the action state machine advances through action chains.

### Hierarchy System

Action inputs form a tree (hierarchy). Example for a weapon:
```
base level:
  start_attack -> { light_attack, heavy_attack, ... }
  block -> { push, block_release, ... }
  zoom -> { zoom_shoot, unzoom, ... }
```

The hierarchy tracks which "level" of the action tree the parser is at. When a bot queues `"stance_pressed"`, the parser:
1. Finds the sequence_config for `"stance_pressed"` in the current template
2. Calls `_queue_action_input()` which places it in the queue with the current hierarchy position
3. When the action system consumes it, the hierarchy transitions accordingly

For bots, this is mostly transparent. The parser handles it.

### Input Buffering

The `_update_buffering` method runs before bot request processing. It handles:
- Sprint lockout: While sprinting or in sprint cooldown, the buffer time is reset to prevent stale inputs from triggering
- Buffer timeout: If the first queued entry has been waiting longer than its `buffer_time`, the hierarchy jumps to that entry's position and the queue is cleared (timeout behavior)

Buffer time per input is defined in the sequence config. Default varies by template.

---

## bot_actions.lua -- BT Action Data

**Source:** `scripts/settings/breed/breed_actions/bot_actions.lua`

This table provides `action_data` to each BT node. When a BT node runs, it receives this as a parameter.

### Full Table

```lua
action_data = {
    name = "bot",

    -- Ability activation
    activate_combat_ability = {
        ability_component_name = "combat_ability_action",
    },
    activate_grenade_ability = {
        ability_component_name = "grenade_ability_action",
    },

    -- Combat utility
    combat = {
        utility_weight = 1,
        considerations = UtilityConsiderations.bot_combat,
    },

    -- Interactions
    do_rescue_ledge_hanging = { aim_node = "j_head", interaction_type = "pull_up" },
    do_revive              = { aim_node = "j_head", interaction_type = "revive" },
    do_rescue_hogtied      = { aim_node = "j_head", interaction_type = "rescue" },
    do_remove_net          = { aim_node = "j_head", interaction_type = "remove_net" },

    -- Melee
    fight_melee = {
        engage_range = 6,
        engage_range_near_follow_position = 10,
        override_engage_range_to_follow_position = 12,
        override_engage_range_to_follow_position_challenge = 6,
    },
    fight_melee_priority_target = {
        engage_range = math.huge,
        engage_range_near_follow_position = math.huge,
        override_engage_range_to_follow_position = math.huge,
        override_engage_range_to_follow_position_challenge = math.huge,
    },

    -- Movement
    follow = {
        utility_weight = 1,
        considerations = UtilityConsiderations.bot_follow,
    },

    -- Ranged
    shoot = {
        evaluation_duration = 2,
        evaluation_duration_without_firing = 3,
        maximum_obstruction_reevaluation_time = 0.3,
        minimum_obstruction_reevaluation_time = 0.2,
        aim_speed = { 10, 10, 12, 20, 20 },  -- per difficulty level
        gestalt_behaviors = {
            none = {},
            killshot = { wants_aim = true },
        },
    },
    shoot_priority_target = {
        evaluation_duration = 2,
        evaluation_duration_without_firing = 3,
        maximum_obstruction_reevaluation_time = 0.3,
        minimum_obstruction_reevaluation_time = 0.2,
        gestalt_behaviors = {
            none = {},
            killshot = { wants_aim = true },
        },
    },

    -- Weapon switching
    switch_melee         = { wanted_slot = "slot_primary" },
    switch_ranged        = { wanted_slot = "slot_secondary" },
    switch_ranged_overheat = { wanted_slot = "slot_secondary" },
    switch_ranged_reload   = { wanted_slot = "slot_secondary" },
}
```

### Key Observations

- **Ability action_data is minimal:** Only `ability_component_name` is provided. All activation logic (action_input, hold times, wait actions) comes from `ability_meta_data` on the template.
- **No `activate_pocketable_ability`:** There is no BT node or action_data for pocketable abilities (zealot relic, grenades). This is the Tier 3 gap.
- **Melee engage ranges** are asymmetric: normal targets have limited range (6-12), priority targets have `math.huge`.
- **Aim speed** is a 5-element table indexed by difficulty level.

---

## BT Action Nodes That Queue Inputs

### BtBotActivateAbilityAction

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua`

The only BT node for abilities. Handles stance, charge, shout, and any template with `ability_meta_data`.

**Enter phase:**
1. Reads `action_data.ability_component_name` (e.g., `"combat_ability_action"`)
2. Reads the ability component to get `template_name`
3. Looks up `AbilityTemplates[template_name].ability_meta_data`
4. Extracts `activation`, `wait_action`, `end_condition` from the metadata
5. Gets `action_input_extension` and `bot_unit_input`

**Run phase — Three stages:**

**Stage 1 — `_start_ability` (scratchpad.started == false):**
- Queues `activation_data.action_input` via `action_input_extension:bot_queue_action_input(ability_component_name, activate_action_input, raw_input)`
- Holds until `t >= enter_time + min_hold_time` (default 0)
- Then transitions to started

**Stage 2 — `_perform_wait_action` (if wait_action_data exists):**
- Queues `wait_action_data.action_input` (e.g., `"aim_released"`, `"shout_released"`)
- Only queued once (`scratchpad.wait_action_started` flag)

**Stage 3 — `_evaluate_end_condition`:**
- If `end_condition_data.done_when_arriving_at_destination`: waits for `elapsed > 0.5s AND (destination_reached OR speed <= 0.2)`
- Otherwise: returns `"done"` immediately

### BtBotMeleeAction

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua`

Uses both input pathways:
- **Low-level:** `bot_unit_input:set_aiming(true, soft)` for aim direction, `bot_unit_input:set_aim_position(pos)` for target tracking
- **High-level:** `action_input_extension:bot_queue_action_input("weapon_action", ...)` for attacks, blocks, pushes

**Attack sequence:** Uses `attack_meta_data.action_inputs` — an ordered array of `{action_input, timing}` pairs. Queues them one at a time, waiting for each to be consumed before queuing the next. Example (default light attack):
```lua
action_inputs = {
    { action_input = "start_attack", timing = 0 },
    { action_input = "light_attack", timing = 0 },
}
```

**Defend sequence:** `block` -> wait -> `push` or `block_release`. Uses `defense_meta_data` from weapon template.

**Request tracking:** Stores `attack_action_input_request_id` and checks `bot_queue_request_is_consumed()` before queuing next input in chain.

**Cleanup on leave:** Calls `bot_queue_clear_requests("weapon_action")`, `clear_input_queue_and_sequences("weapon_action")`, and `weapon_extension:stop_action("bot_left_node", ...)`.

### BtBotShootAction

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua`

- **Aim direction:** `bot_unit_input:set_aim_rotation(actual_aim_rotation)` with `set_aiming(true, false, true)` (hard aim with rotation)
- **Aim/zoom:** Queues `aim_action_input` (default `"zoom"`) via `action_input_extension:bot_queue_action_input("weapon_action", ...)`
- **Fire:** Queues `fire_action_input` (default `"shoot"` or `"zoom_shoot"`)
- **Charge:** Queues `charge_action_input` (default `"brace"`) for charged weapons

**Action input validation:** Before queuing fire or charge, calls `weapon_extension:action_input_is_currently_valid("weapon_action", action_input, raw_input, fixed_t)` to check the input is valid in the current weapon action state.

### BtBotReloadAction

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_reload_action.lua`

Simple: queues `"reload"` to `"weapon_action"` every frame until consumed.

### BtBotInventorySwitchAction

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_inventory_switch_action.lua`

Queues `"wield"` with `raw_input = wield_input_from_slot_name(wanted_slot)` to `"weapon_action"`. Validates with `action_input_is_currently_valid` first. Retries every 0.1s.

---

## ability_meta_data Structure

### Vanilla Templates (Tier 1 — Already Have Meta Data)

All vanilla `ability_meta_data` use the simplest form — stance activation:

```lua
ability_meta_data = {
    activation = {
        action_input = "stance_pressed",
    },
}
```

Templates with this: `veteran_combat_ability`, `veteran_stealth_combat_ability`, `ogryn_gunlugger_stance`, `psyker_overcharge_stance`, `adamant_stance`, `broker_focus`, `broker_punk_rage`.

### BetterBots Injected Meta Data (Tier 2)

BetterBots injects `ability_meta_data` for templates that lack it. Full structure:

```lua
ability_meta_data = {
    activation = {
        action_input = <string>,      -- REQUIRED. Queued first.
        min_hold_time = <number>,     -- Optional. Seconds to wait before proceeding.
    },
    wait_action = {                   -- Optional. Second input after hold time expires.
        action_input = <string>,
    },
    end_condition = {                 -- Optional. How to determine node completion.
        done_when_arriving_at_destination = <boolean>,
    },
}
```

### Meta Data by Ability Type

| Template | activation.action_input | min_hold_time | wait_action | end_condition |
|----------|------------------------|---------------|-------------|---------------|
| **Stances** | | | | |
| ogryn_gunlugger_stance | `stance_pressed` | — | — | — |
| psyker_overcharge_stance | `stance_pressed` | — | — | — |
| adamant_stance | `stance_pressed` | — | — | — |
| broker_focus | `stance_pressed` | — | — | — |
| broker_punk_rage | `stance_pressed` | — | — | — |
| zealot_invisibility | `stance_pressed` | — | — | — |
| **Vet Focus (overridden)** | | | | |
| veteran_combat_ability | `combat_ability_pressed` | 0.075 | `combat_ability_released` | — |
| veteran_stealth_combat_ability | `combat_ability_pressed` | 0.075 | `combat_ability_released` | — |
| **Dashes/Charges** | | | | |
| zealot_dash | `aim_pressed` | 0.075 | `aim_released` | arrive_at_dest |
| ogryn_charge | `aim_pressed` | 0.01 | `aim_released` | arrive_at_dest |
| adamant_charge | `aim_pressed` | 0.01 | `aim_released` | arrive_at_dest |
| **Shouts** | | | | |
| ogryn_taunt_shout | `shout_pressed` | 0.075 | `shout_released` | — |
| psyker_shout | `shout_pressed` | 0.075 | `shout_released` | — |
| adamant_shout | `shout_pressed` | 0.075 | `shout_released` | — |

---

## Input Buffering and Timing

### Frame Timing

1. **Frame update:** `BotUnitInput.update()` calculates movement and sets `_input`
2. **Fixed update:** `BotUnitInput.fixed_update()` merges ephemeral inputs
3. **Fixed update:** `ActionInputParser.fixed_update()` drains bot request queue into main input queue
4. **Action system:** Calls `peek_next_input()` and `consume_next_input()` during action processing

Bot requests queued in a BT node's `enter()` or `run()` are processed on the **next fixed tick**. This means there is always a minimum one-tick delay between queuing and execution.

### Buffer Overflow Protection

- Bot request ring buffer max: **5 entries**. Exceeding this calls `ferror()` (hard crash).
- Main input queue size: Template-dependent (`MAX_ACTION_INPUT_QUEUE` from formatter).
- Queue overflow: If the main queue is full, `_manipulate_queue_by_no_space` tries to find and overwrite an entry with matching hierarchy position. If it cannot, it logs a Crashify exception and returns `nil`.

### Sprint Lockout

While sprinting or during sprint cooldown, `_update_buffering` resets `_input_queue_first_entry_became_first_entry_t = t`. This prevents queued inputs from timing out and being consumed during sprint, effectively blocking ability activation while sprinting.

### Request Consumption Tracking

BT nodes that need to sequence multiple inputs (melee attack chains, shoot-then-charge) use the `global_bot_request_id` returned by `bot_queue_action_input()`:

```lua
-- Queue first input
scratchpad.request_id = action_input_extension:bot_queue_action_input("weapon_action", "start_attack", nil)

-- Next frame: check if consumed before queuing next
if action_input_extension:bot_queue_request_is_consumed("weapon_action", scratchpad.request_id) then
    -- Safe to queue next input in chain
    action_input_extension:bot_queue_action_input("weapon_action", "light_attack", nil)
end
```

---

## Relevance to BetterBots

### How Ability Activation Works End-to-End

1. **Condition check:** `bt_bot_conditions.can_activate_ability` evaluates whether to activate. BetterBots hooks this to remove the vanilla whitelist and add `enemies_in_proximity > 0` as generic trigger.

2. **BT node enter:** `BtBotActivateAbilityAction.enter()` reads `action_data.ability_component_name` (from `bot_actions.lua`) to know which parser to target. It reads `ability_meta_data` from the ability template for activation parameters.

3. **Queue activation input:** Calls `action_input_extension:bot_queue_action_input("combat_ability_action", "stance_pressed", nil)`. This places the request in the ActionInputParser's bot request ring buffer.

4. **Fixed tick processing:** `ActionInputParser.fixed_update()` sees the request, looks up `sequence_configs["stance_pressed"]` in the ability template's action input sequences, and calls `_queue_action_input()` to place it in the main input queue.

5. **Action system consumption:** The ability action system calls `peek_next_input("combat_ability_action")`, sees `"stance_pressed"`, calls `consume_next_input()`, and begins the ability action chain.

6. **Ability fires:** The ability action handler processes the consumed input, triggers the ability effect (stance change, dash, shout, etc.).

### Why `action_input` Names Must Match Template Sequences

When `_update_bot_action_input_requests` processes a bot request, it does:
```lua
local sequence_config = sequence_configs[action_input]
if not sequence_config then
    Log.info("ActionInputParser", "Could not find matching input_sequence for queued action_input %q in template %q", action_input, template_name)
end
```

If the `action_input` in `ability_meta_data.activation` doesn't match any `action_input_sequences` entry in the ability template, the request is silently dropped. This is the most common failure mode for incorrectly configured Tier 2 abilities.

### The `combat_ability_action` vs `grenade_ability_action` Split

`bot_actions.lua` defines two ability nodes:
- `activate_combat_ability` targets `"combat_ability_action"` parser
- `activate_grenade_ability` targets `"grenade_ability_action"` parser

The BT has separate condition checks and nodes for each. The condition reads the appropriate ability component to get `template_name`, then checks `ability_meta_data`.

For **Tier 3 grenades**, the problem is that many grenade templates have no `ability_template` field — `template_name` stays `"none"` — so the parser has no sequence configs to match against. Even if we inject `ability_meta_data`, the ActionInputParser cannot process the request because there are no `action_input_sequences` defined for `template_name == "none"`.

### The Hold/Release Pattern (Charges and Shouts)

For abilities like Zealot Dash (`aim_pressed` -> hold -> `aim_released`):

1. `_start_ability` queues `"aim_pressed"` and waits `min_hold_time` (0.075s)
2. After hold time expires, `scratchpad.started = true`
3. `_perform_wait_action` queues `"aim_released"` — this transitions the ability from aiming/charging to executing
4. `_evaluate_end_condition` checks `done_when_arriving_at_destination` for movement abilities

The `min_hold_time` is critical: queuing press and release on the same tick would be processed together in `_update_bot_action_input_requests`, but the ability action state machine needs the hold duration to register the ability. The BT node enforces this gap.

### BetterBots Fallback System

BetterBots also implements a fallback path that hooks into the BT condition check directly (bypassing `BtBotActivateAbilityAction`). This fallback:
1. Queues `activation_data.action_input` via `action_input_extension:bot_queue_action_input()`
2. Tracks `hold_until = fixed_t + min_hold_time`
3. On subsequent ticks, when hold expires, queues `wait_action.action_input`
4. Manages its own state machine with `state.active`, `state.wait_sent`, `state.next_try_t`

This duplicates the BT node's logic but runs outside the BT, providing a safety net when the normal BT path fails.

### BetterBots Sustained-Fire Bridge

Held-fire ranged weapons split across both bot input pathways:

1. high-level `weapon_action` queue selects the action input (`shoot`, `zoom_shoot`, `shoot_braced`, `trigger_charge_flame`, etc.)
2. low-level raw hold input must stay true across frames for the action state to keep streaming

Vanilla bots do step 1 but not step 2, so full-auto / stream weapons degrade into taps. BetterBots `#87` fixes this by:

1. observing successful `weapon_action` requests on `PlayerUnitActionInputExtension.bot_queue_action_input`
2. arming short-lived per-unit sustained state for supported template/action-input pairs
3. injecting the required raw hold inputs during `BotUnitInput._update_actions`
4. clearing the state on explicit stop inputs, template changes, or staleness

This is intentionally narrower than `#41`: it does not decide whether the bot should ADS, brace, or hipfire. It only keeps the already-chosen sustained path alive.

---

## Source File Reference

| File | Role |
|------|------|
| `scripts/extension_systems/input/bot_unit_input.lua` | Low-level bot input (movement, aim, dodge, interact) |
| `scripts/extension_systems/input/player_unit_input_extension.lua` | Routes input queries to human or bot input |
| `scripts/extension_systems/input/human_unit_input.lua` | Human keyboard/gamepad input (not covered here) |
| `scripts/managers/player/player_game_states/input_handler_settings.lua` | Input action definitions (ephemeral_actions, actions) |
| `scripts/extension_systems/action_input/player_unit_action_input_extension.lua` | Manages ActionInputParser instances per component |
| `scripts/extension_systems/action_input/action_input_parser.lua` | Core input parsing, bot request queue, hierarchy, buffering |
| `scripts/extension_systems/action_input/action_input_formatter.lua` | Formats template action_input_sequences into parser configs |
| `scripts/utilities/action/action_input_hierarchy.lua` | Hierarchy tree traversal utilities |
| `scripts/settings/breed/breed_actions/bot_actions.lua` | BT action_data for all bot nodes |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua` | BT node: ability activation |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua` | BT node: melee combat (attack, block, push, dodge) |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua` | BT node: ranged combat (aim, fire, charge) |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_reload_action.lua` | BT node: weapon reload |
| `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_inventory_switch_action.lua` | BT node: weapon slot switching |
| `scripts/extension_systems/weapon/player_unit_weapon_extension.lua` | `action_input_is_currently_valid()` for weapons |
| `scripts/extension_systems/ability/player_unit_ability_extension.lua` | `action_input_is_currently_valid()` for abilities |
