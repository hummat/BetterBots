# Objective-Aware Ability Activation — Design Spec

**Issue:** [#37](https://github.com/hummat/BetterBots/issues/37)
**Date:** 2026-04-08
**Phase:** P1 (threshold adjustments + charge suppression)

## Problem

Vanilla bots have zero awareness of allies performing objective interactions (scanning terminals, carrying batteries, reviving). The perception system only classifies allies by disabled state (knocked_down, netted, hogtied, ledge) and healing. A human player would use defensive abilities to protect a vulnerable teammate — bots never do this.

## Approach

Context-only with inline heuristic branching (Approach A). Each heuristic checks `context.ally_interaction_profile` and adjusts its own thresholds. Same pattern as existing `target_ally_needs_aid` checks. No new abstractions, no BT modifications.

## Context Fields

Add to the context table in `build_context()`:

```lua
ally_interacting = false,          -- any teammate is in an objective interaction
ally_interaction_type = nil,       -- raw template string: "scanning", "revive", etc.
ally_interacting_unit = nil,       -- unit reference
ally_interacting_distance = nil,   -- distance from bot to interacting ally
ally_interaction_profile = nil,    -- "shield" or "escort"
```

## Detection

A **new loop** in `build_context()` over `side.valid_player_units` (all alive teammates, max 3). Separate from the existing coherency loop — wider range catches allies outside coherency (~8m).

Two detection paths in the same loop:

### Shield profile (interaction component)

```lua
local interaction_component = ally_data:read_component("interaction")
if interaction_component.state == INTERACTION_STATE_IS_INTERACTING then
    -- classify interaction_component.type into profile
end
```

### Escort profile (inventory component)

```lua
local inventory_component = ally_data:read_component("inventory")
if inventory_component.wielded_slot == "slot_luggable" then
    -- escort profile
end
```

**Why two paths:** `luggable` and `luggable_socket` have `duration = 0` in `interaction_templates.lua` — they are instant pickup/deposit events, not sustained interactions. Carrying a battery is tracked via the inventory system (`wielded_slot`), not the interaction system. All Shield-profile interactions are sustained holds (1-4s duration) and are visible in the interaction component.

### Priority

If multiple allies are interacting simultaneously, pick the closest one. Rare (2+ simultaneous interactions) but deterministic.

### Side system access

`build_context()` needs the bot's side to iterate teammates. Access path:

```lua
local side_system = Managers.state.extension:system("side_system")
local side = side_system.side_by_unit[unit]
local player_units = side.valid_player_units
```

Cache the `side_system` reference as a module-local via `init(deps)` (same pattern as `_fixed_time`, `_resolve_preset`, etc.) to avoid per-frame system lookup.

## Profile Classification

| Profile | Interaction types | Detection |
|---------|-------------------|-----------|
| **shield** | `scanning`, `setup_decoding`, `decoding`, `setup_breach_charge`, `revive`, `rescue`, `pull_up`, `remove_net`, `health_station`, `servo_skull`, `servo_skull_activator` | `read_component("interaction")` — `.state == is_interacting` + `.type` lookup |
| **escort** | Carrying a luggable (battery, power cell) | `read_component("inventory")` — `.wielded_slot == "slot_luggable"` |

Types not in either table are ignored (instant pickups, hub interactions, etc.).

**Note:** The issue body uses `"scanning_interaction"` — this string does not exist in the engine. The correct template key is `"scanning"` (verified in `interaction_templates.lua`).

## Per-Heuristic Behavior

### Defensive abilities — lower activation thresholds

Each rule is an early-return branch added before existing rules in the heuristic function. All require `context.ally_interacting == true`.

| Ability | Rule | Rationale |
|---------|------|-----------|
| Ogryn Taunt | `num_nearby >= 1 AND toughness > 0.30` → activate | Pull aggro from fewer enemies than normal when ally vulnerable |
| Veteran VoC (Shout) | `num_nearby >= 1` → activate | Stagger/suppress near interacting ally |
| Psyker Force Field | `ranged_count >= 1 OR num_nearby >= 2` → activate | Dome provides ranged cover for stationary ally |
| Zealot Relic | `allies_in_coherency >= 1` → activate | Toughness regen aura protects the group during interaction |
| Arbites Drone | Lower `team_horde_nearby` threshold by 1 | Earlier drone deployment near vulnerable ally |
| Arbites Shout | `num_nearby >= 1` → activate | Same pattern as VoC |
| Stimm Field | `ally_interacting` → activate (unconditional) | Team buff during vulnerability window |

### Mobility abilities — suppress charges near interacting ally

Charges are gap-closers. Dashing away from an interacting ally leaves them unprotected for no benefit (especially during revive — the downed player is already being helped).

| Ability | Rule |
|---------|------|
| Zealot Dash | Block when `ally_interacting AND ally_interacting_distance <= 12` |
| Ogryn Charge | Same |
| Arbites Charge | Same |

12m = engagement leash base distance. Ensures bot stays within protective range.

**Interaction suppression overrides `_ally_aid` charge rules.** If an ally is actively interacting (e.g., reviving), `_ally_aid` is already being handled. The bot protects the interactor rather than dashing toward the downed player.

Rule ordering in each charge heuristic:
1. Existing close-range block (`target_too_close`)
2. **New: interaction suppression block** (before `_ally_aid`)
3. Existing `_ally_aid` rule
4. Remaining rules unchanged

### Grenades/blitzes — lower thresholds for AoE/stun types

| Type | Change |
|------|--------|
| Horde grenades (frag, fire bomb, ogryn frag/nails) | Lower `min_nearby` by 1 |
| Chain Lightning | Lower `crowd` threshold by 1 |
| Stun grenade (Arbites) | Lower density threshold by 1 |
| Mines (ogryn) | Lower density threshold by 1 |
| Single-target blitzes (knives, krak, brain burst, Assail, Smite) | No change — already priority-target driven |

### No change

- **Stances** (Gunlugger, Psyker, Adamant, Veteran Ranger): already reactive/self-buff
- **Stealth** (Veteran, Zealot Invisibility): already defensive
- **Broker abilities**: DLC-blocked, untestable

## Debug Logging

### Interaction scan log

One log per detected interacting ally, per bot:
- Key: `"interaction_scan:" .. tostring(unit)`
- Content: ally unit, type, profile, distance
- Throttled (one-shot per unique ally interaction)

### Per-heuristic logs

Each new interaction branch gets a `_debug_log` call:
- Key format: `"<ability>_protect_interactor:" .. tostring(unit)`
- Content: profile, interaction type, distance, resulting rule
- Per-bot discriminator in key (mandatory per CLAUDE.md logging rules)

## Testing

Unit tests extending existing `heuristics_spec.lua` structure:

- **Context construction**: verify `ally_interacting` fields populate from mock side/interaction data
- **Shield detection**: mock `interaction` component with various types and states
- **Escort detection**: mock `inventory` component with `wielded_slot = "slot_luggable"`
- **Per-heuristic branches**: each defensive ability activates at lowered thresholds when `ally_interacting`
- **Charge suppression**: verify interaction block fires before and overrides `_ally_aid`
- **Grenade thresholds**: verify lowered thresholds for AoE types, unchanged for single-target
- **Priority**: closest interacting ally wins when multiple interact
- **Edge cases**: bot itself excluded from scan, dead ally ignored, non-objective types ignored, no interacting ally returns defaults
- **Profile distinction**: shield vs escort context fields correct for each type

Estimated ~35-45 new test cases.

## Scope Boundaries (P1 excludes)

- No dash-toward interacting ally (P2 — shares logic with #10)
- No per-interaction-type tuning beyond shield/escort split (P3)
- No dedicated settings toggle — gated by per-ability toggles from #6
- No BT modifications — pure heuristic-layer changes
- No escort-specific heuristic branching — both profiles produce identical behavior in P1; the distinction is carried in context fields for P2

## Files Modified

| File | Change |
|------|--------|
| `heuristics.lua` | New context fields in `build_context()`, interaction scan loop, ~12 heuristic branches |
| `heuristics_spec.lua` | ~35-45 new test cases |
| `BetterBots.lua` | Wire `side_system` reference into heuristics init |

## Dependencies

- Requires `side_system` access in `build_context()` — wired through `init()` deps
- `InteractionSettings` cached as module-local (single `require` at load time)
- No dependency on #7 (revive-with-ability) — #7 depends on these context fields
