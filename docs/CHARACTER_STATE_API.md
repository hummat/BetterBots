# Character State Detection API Reference

> Source version: Darktide v1.10.7 (decompiled source at `../Darktide-Source-Code/`)
> Last updated: 2026-03-06

## Purpose

APIs for detecting bot character states (dodging, sprinting, lunging, knocked down, etc.) to gate ability activation. BetterBots needs these to avoid firing abilities during states that would cancel them, waste cooldowns, or cause desyncs.

**Source directory:** `../Darktide-Source-Code/scripts/extension_systems/character_state_machine/`

---

## Primary API: `character_state_machine_extension`

The main entry point for state queries. Obtained via:

```lua
local csm_ext = ScriptUnit.extension(unit, "character_state_machine_system")
local current_state = csm_ext:current_state_name()
```

Returns the string name of the active state from the state machine.

---

## Core Component: `character_state`

Accessed via `unit_data_extension:read_component("character_state")`.

| Field | Type | Description |
|---|---|---|
| `state_name` | string | Current state name |
| `previous_state_name` | string | State before current |
| `entered_t` | number | Timestamp when current state was entered |

---

## Complete State Name List

30+ character states in the state machine:

`catapulted`, `consumed`, `dead`, `dodging`, `exploding`, `falling`, `grabbed`, `hogtied`, `hub_companion_interaction`, `hub_emote`, `hub_jog`, `interacting`, `jumping`, `knocked_down`, `ladder_climbing`, `ladder_top_entering`, `ladder_top_leaving`, `ledge_hanging`, `ledge_hanging_falling`, `ledge_hanging_pull_up`, `ledge_vaulting`, `lunging`, `minigame`, `mutant_charged`, `netted`, `pounced`, `sliding`, `sprinting`, `stunned`, `walking`, `warp_grabbed`

---

## Detection Patterns by State

The `character_state` component gives the top-level state, but many states expose richer data through dedicated components. Use the specific component when you need detailed state information.

| State | Component | Field / Method | Access pattern |
|---|---|---|---|
| Jumping | `movement_state` | `method == "jumping"` | `read_component` |
| Falling | `movement_state` | `method == "falling"` | `read_component` |
| Lunging (active) | `lunge_character_state` | `is_lunging` (bool) | `read_component` |
| Lunging (aim phase) | `lunge_character_state` | `is_aiming` (bool) | `read_component` |
| Dodging (active) | `movement_state` | `is_dodging` (bool) | `read_component` |
| Dodging (effective) | `movement_state` | `is_effective_dodge` (bool) | `read_component` |
| Dodging (with type) | *(utility fn)* | `Dodge.is_dodging(unit)` | `require` utility |
| Sprinting | `sprint_character_state` | `is_sprinting` (bool) | `read_component` |
| Sliding | `movement_state` | `method == "sliding"` | `read_component` |
| Crouching | `movement_state` | `is_crouching` (bool) | `read_component` |
| Interacting (revive) | `character_state` | `state_name == "interacting"` | `read_component` |
| Knocked down | `character_state` | `state_name == "knocked_down"` | `read_component` |

---

## Detailed Component References

### `dodge_character_state`

Granular dodge state beyond the `movement_state.is_dodging` bool.

| Field | Type | Description |
|---|---|---|
| `dodge_time` | number | Time into current dodge |
| `cooldown` | number | Remaining cooldown before next dodge |
| `consecutive_dodges` | number | Chain dodge count (affects efficiency) |
| `dodge_direction` | Vector3 | Direction of current dodge |
| `distance_left` | number | Remaining dodge travel distance |
| `started_from_crouch` | bool | Whether dodge began from crouching |

### `lunge_character_state`

Used by charge/dash abilities (Zealot Dash, Ogryn Charge, Arbites Charge).

| Field | Type | Description |
|---|---|---|
| `is_lunging` | bool | Currently in lunge movement |
| `is_aiming` | bool | In aim/windup phase before lunge |
| `lunge_template` | string | Name of the lunge template driving this lunge |
| `lunge_target` | Unit | Target unit (if targeted lunge) |
| `distance_left` | number | Remaining lunge travel distance |
| `direction` | Vector3 | Current lunge direction |

### `sprint_character_state`

| Field | Type | Description |
|---|---|---|
| `is_sprinting` | bool | Currently sprinting |
| `sprint_overtime` | number | Accumulated sprint time (affects stamina) |
| `is_sprint_jumping` | bool | Currently in a sprint-jump |

---

## Revive Detection

Three distinct checks for revive-related states:

| What | How | Notes |
|---|---|---|
| Bot is performing a revive | `blackboard.behavior.current_interaction_unit ~= nil` | Set by BT interaction node |
| Target is disabled | `PlayerUnitStatus.is_disabled(character_state_component)` | Covers knocked down, hogtied, netted, pounced, etc. |
| Target is being actively assisted | `assisted_state_input.in_progress` | Another player already reviving |

**Utility functions:**
- `PlayerUnitStatus.is_disabled(character_state_component)` -- true for any disabled state
- `PlayerUnitStatus.is_knocked_down(character_state_component)` -- true specifically for knocked down

---

## Utility Functions

| Function | Source | Purpose |
|---|---|---|
| `PlayerUnitStatus.is_disabled(cs_component)` | `player_unit_status.lua` | Any disabled state (knocked down, hogtied, netted, pounced, etc.) |
| `PlayerUnitStatus.is_knocked_down(cs_component)` | `player_unit_status.lua` | Specifically knocked down |
| `Dodge.is_dodging(unit)` | `dodge.lua` | Returns dodge state with dodge type info |

---

## Access Pattern Example

Reading component data from a bot unit in a BetterBots hook or heuristic:

```lua
local unit_data_ext = ScriptUnit.extension(bot_unit, "unit_data_system")

-- Top-level state
local cs_component = unit_data_ext:read_component("character_state")
local state_name = cs_component.state_name

-- Dodge details
local dodge_component = unit_data_ext:read_component("dodge_character_state")
local is_dodging = dodge_component.is_dodging

-- Lunge details (charge/dash)
local lunge_component = unit_data_ext:read_component("lunge_character_state")
local is_lunging = lunge_component.is_lunging
local is_aiming = lunge_component.is_aiming

-- Sprint details
local sprint_component = unit_data_ext:read_component("sprint_character_state")
local is_sprinting = sprint_component.is_sprinting

-- Movement method (jumping, falling, sliding)
local movement_component = unit_data_ext:read_component("movement_state")
local movement_method = movement_component.method
```

---

## Relevance to BetterBots

Key uses for ability gating:

1. **Suppress abilities during dodge** (issue #15) -- check `movement_state.is_dodging` or `dodge_character_state` before queuing ability input
2. **Suppress abilities during lunge** (issue #11) -- check `lunge_character_state.is_lunging` to avoid interrupting an active charge
3. **Revive-with-ability** (issue #7) -- detect `interacting` state and nearby disabled allies via `PlayerUnitStatus.is_disabled()`
4. **Charge to rescue** (issue #10) -- detect disabled ally, check `lunge_character_state.is_lunging == false`, fire charge toward ally position
5. **Hazard avoidance** (issue #21) -- detect `lunging`/`sprinting` states to suppress abilities near environmental hazards

---

## Related

- `docs/BOT_INPUT_SYSTEM.md` -- How inputs are queued and consumed
- `docs/BOT_BEHAVIOR_TREE.md` -- BT conditions that check character state
- `docs/BOT_COMBAT_ACTIONS.md` -- Action node lifecycles and state interactions
