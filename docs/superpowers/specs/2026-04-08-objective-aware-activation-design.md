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

A **new loop** in `build_context()` over `side.valid_player_units` (all teammates on the same side). Separate from the existing coherency loop — wider range catches allies outside coherency (~8m). The loop **must skip `ally_unit == unit`** (self-exclusion) since `valid_player_units` includes the bot itself.

Three detection paths in the same loop, checked in order:

### 1. Minigame state (terminal decode phase)

```lua
local ally_char_state = ally_data:read_component("character_state")
if ally_char_state.state_name == "minigame" then
    -- shield profile (terminal hacking)
end
```

**Why this is needed:** `decoding` has `duration = 0` in `interaction_templates.lua` — it's an instant interaction that immediately transitions to `player_character_state_minigame`. The minigame state explicitly clears `interaction.state = none` on entry (line 77 of `player_character_state_minigame.lua`). Without this check, the entire terminal-hacking phase — the most important objective interaction — would be invisible to the scan.

### 2. Sustained interaction (hold interactions)

```lua
if ally_char_state.state_name == "interacting" then
    local interacting_state = ally_data:read_component("interacting_character_state")
    local interaction_type = interacting_state.interaction_template
    -- classify interaction_type into profile via SHIELD_INTERACTION_TYPES lookup
end
```

Uses `character_state.state_name` as the primary signal (catches all sustained interactions), then reads `interacting_character_state.interaction_template` for type classification. This is more reliable than reading the `interaction` component directly, which can be stale.

### 3. Escort profile (luggable carrying)

```lua
local ally_inventory = ally_data:read_component("inventory")
if ally_inventory.wielded_slot == "slot_luggable" then
    -- escort profile
end
```

**Why a separate path:** `luggable` and `luggable_socket` have `duration = 0` in `interaction_templates.lua` — they are instant pickup/deposit events, not sustained interactions. Carrying a battery is tracked via the inventory system (`wielded_slot`), not the interaction or character state system.

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

| Profile | Detected via | Types / condition |
|---------|-------------|-------------------|
| **shield** | `character_state.state_name == "minigame"` | Terminal decode phase (always shield) |
| **shield** | `character_state.state_name == "interacting"` + `interacting_character_state.interaction_template` lookup | `scanning`, `setup_decoding`, `setup_breach_charge`, `revive`, `rescue`, `pull_up`, `remove_net`, `health_station`, `servo_skull`, `servo_skull_activator` |
| **escort** | `inventory.wielded_slot == "slot_luggable"` | Carrying a battery / power cell |

Interaction types not in the shield lookup are ignored (instant pickups, hub interactions, etc.). `decoding` is intentionally absent from the interaction lookup — it has `duration = 0` and immediately transitions to the minigame character state, which is caught by the first detection path.

**Note:** The issue body uses `"scanning_interaction"` — this string does not exist in the engine. The correct template key is `"scanning"` (verified in `interaction_templates.lua`).

## Per-Heuristic Behavior

### Defensive abilities — lower activation thresholds

Each rule is an early-return branch added before existing rules in the heuristic function. All require `context.ally_interacting == true`.

| Ability | Rule | Rationale |
|---------|------|-----------|
| Ogryn Taunt | `num_nearby >= 1 AND toughness > 0.30` → activate | Pull aggro from fewer enemies than normal when ally vulnerable |
| Veteran VoC (Shout) | `num_nearby >= 1` → activate | Stagger/suppress near interacting ally. **Note:** VoC is dispatched via the special `veteran_combat_ability` path (class_tag `"squad_leader"`), not a standalone template function. The interaction branch goes inside `_can_activate_veteran_combat_ability`. |
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

One log in `build_context()` per detected interacting ally, per bot:
- Key: `"interaction_scan:" .. tostring(unit)`
- Content: ally unit, type/state, profile, distance
- Throttled (one-shot per unique ally interaction)
- **Wiring:** `_debug_log` and `_debug_enabled` must be added as module-local dependencies in `heuristics.lua` via `init(deps)`. Currently `heuristics.lua` has no debug logging — this is the first addition.

### Per-heuristic logs

Heuristic functions do not log directly — they return `(can_activate, rule)` and the caller (`condition_patch._can_activate_ability` → `_Debug.log_ability_decision`) handles logging. The new interaction-specific rule names (e.g., `"ogryn_taunt_protect_interactor"`, `"zealot_dash_block_protecting_interactor"`) will be captured automatically by the existing logging infrastructure. No per-heuristic debug log calls needed.

## TeamCooldown Interaction

Objective protection activations **respect TeamCooldown** — no bypass. Rationale: if two bots both want to taunt to protect the same interactor, staggering is still valuable. TeamCooldown already has emergency overrides (ally-aid bypass) that will fire for truly critical situations.

## Testing

Unit tests extending existing `heuristics_spec.lua` structure:

- **Context construction**: verify `ally_interacting` fields populate from mock side data
- **Shield detection (interacting)**: mock `character_state.state_name = "interacting"` + `interacting_character_state.interaction_template` with various types
- **Shield detection (minigame)**: mock `character_state.state_name = "minigame"` → shield profile
- **Escort detection**: mock `inventory.wielded_slot = "slot_luggable"`
- **Self-exclusion**: bot's own unit is skipped in the scan
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
- No hold-the-zone / survive-event phase awareness — those are mission-objective-system states, not ally interaction states. Out of scope.
- No `health_station` scope distinction — `health_station` is included as a vulnerability signal (player is locked in a 3s hold animation), not because it's a mission objective. The feature is "protect vulnerable allies," not strictly "protect objective-performing allies."
- Revive/rescue/pull_up/remove_net overlap with existing `target_ally_needs_aid` is intentional — `ally_needs_aid` triggers charge-toward, while `ally_interacting` triggers defensive-stay. Complementary signals, not redundant.

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
