# Team Cooldown Staggering (#14)

**Date:** 2026-04-08
**Status:** Approved
**Scope:** ~100-150 LOC new module + ~20 LOC integration

## Problem

When multiple bots face the same threat, they all evaluate heuristics in the same frame and often all return `true` simultaneously — burning 2-3 defensive cooldowns or grenades on one wave, leaving nothing for the next threat 30s later.

Concrete scenarios:
- 2x Ogryn taunt on same wave — 50s cooldown each wasted
- 2x Psyker shout on same horde — 30s each wasted
- 2x Zealot/Arbites dash to rescue same ally — ~15s each wasted
- 2x grenade throw at same cluster — permanent consumable loss

Root cause: `BehaviorSystem.update` iterates bots via `pairs()` over a hash table (non-deterministic order). All bots update in the same frame, sequentially. By the time bot B evaluates, bot A's heuristic returned `true` but the ability hasn't fired yet — no signal exists that the threat is already being handled.

## Solution

A new `team_cooldown.lua` module that acts as a pure state tracker + query. It records activations at `use_ability_charge` time and suppresses same-category activations from other bots within a time window.

### Why post-activation, not pre-activation

A pre-activation "claim" lock is unreliable because `pairs()` hash order is non-deterministic across sessions — bot A may or may not evaluate before bot B. A post-activation cooldown (written at `use_ability_charge` time) is robust: by the next frame, the first bot's activation is visible to all others.

## Module API

```lua
team_cooldown.record(unit, template_name, fixed_t)
team_cooldown.is_suppressed(unit, template_name, fixed_t, rule) → bool, reason
team_cooldown.reset()  -- for hot-reload / game state changes
```

- `record` maps template_name → category, then writes `{unit, fixed_t}` into the category slot
- `is_suppressed` returns `true` if a **different** bot activated the same category within the suppression window. Never suppresses the bot that recorded the activation itself. The `rule` parameter enables emergency override checks.
- Templates not in the category map pass through unsuppressed.

## Category Map

Abilities that serve the same tactical purpose share a category. Two bots taunting the same wave is waste; one taunting and one charging is fine.

| Category | Templates |
|----------|-----------|
| `taunt` | `ogryn_taunt_shout`, `adamant_shout` |
| `aoe_shout` | `psyker_shout` |
| `dash` | `zealot_dash`, `zealot_targeted_dash`, `zealot_targeted_dash_improved`, `zealot_targeted_dash_improved_double`, `ogryn_charge`, `ogryn_charge_increased_distance`, `adamant_charge` |
| `stance` | `veteran_stealth_combat_ability`, `psyker_overcharge_stance`, `ogryn_gunlugger_stance`, `adamant_stance`, `broker_focus`, `broker_punk_rage` |
| `grenade` | All grenade/blitz templates (single category — consumable, any double-throw is waste) |

Stances are self-buffs where stacking is fine in theory, but in practice two bots popping stances simultaneously on the same threat wastes one — the threat dies to the first. A short 2s window prevents the reflex double-pop without meaningfully delaying the second bot.

## Suppression Windows

Roughly half the ability cooldown. Grenades get a shorter window since they're discrete fast actions.

| Category | Window (seconds) |
|----------|-----------------|
| `taunt` | 8 |
| `aoe_shout` | 6 |
| `dash` | 4 |
| `stance` | 2 |
| `grenade` | 3 |

## Emergency Overrides

These heuristic rules **bypass suppression entirely** — the bot is in genuine danger and must act regardless of team state:

- `psyker_shout_high_peril` — bot must vent or die
- `veteran_stealth_critical_toughness` — about to go down
- `zealot_stealth_emergency` — health/toughness critical
- `ogryn_charge_escape` — surrounded and low toughness
- Any rule containing `_rescue` — ally is downed/disabled

Implementation: `is_suppressed` receives the heuristic rule string. If it matches an emergency pattern, return `false` (not suppressed) regardless of team state.

## Integration Points

### Write (record activation)

In the existing `use_ability_charge` hook in `BetterBots.lua`:
- Line ~781 (combat ability): `TeamCooldown.record(unit, ability_name, fixed_t)`
- Line ~754 (grenade ability): `TeamCooldown.record(unit, grenade_name, fixed_t)`

One-line additions at each site.

### Read (check suppression)

1. **`condition_patch._can_activate_ability`** — after `resolve_decision` returns `can_activate=true`, check `TeamCooldown.is_suppressed(unit, template_name, fixed_t, rule)`. If suppressed, return `false` with rule `"team_cooldown_suppressed"`.

2. **`grenade_fallback`** — in the idle→wield transition guard, same pattern: check `is_suppressed` before entering the throw state machine.

### Reset

In the existing `on_game_state_changed` handler — call `TeamCooldown.reset()` on game exit and hot-reload.

## Debug Logging

One `_debug_log` call when suppression fires:
- Key: `"team_cd:" .. template_name .. ":" .. tostring(unit)` (per-bot discriminator per CLAUDE.md rules)
- Message: which bot's prior activation caused suppression, remaining window

## Settings

No user-facing setting for v0.10.0. Always-on behavior that makes bots smarter. If users report over-suppression, a toggle can be added later.

## Testing

Unit tests in `tests/team_cooldown_spec.lua`:

- `record` + `is_suppressed`: same-bot activation is never suppressed
- Different-bot, same-category: suppressed within window
- Different-bot, different-category: not suppressed
- Window expiry: suppression lifts after window elapses
- Emergency override: matching rules bypass suppression
- `_rescue` pattern: any rule containing `_rescue` bypasses
- `reset()` clears all state
- Unknown templates (not in category map) pass through unsuppressed
- Grenade category: any grenade template maps to `grenade` category

## Data Structures

```lua
-- Module-level state (weak keys for GC safety)
local _last_activation_by_category = {}  -- category_string → {unit=, fixed_t=}

-- Static maps (plain tables, no weak keys needed)
local CATEGORY_MAP = { template_name → category_string }
local SUPPRESSION_WINDOW = { category_string → seconds }
local EMERGENCY_RULES = { rule_string → true }  -- set for O(1) lookup
```

`_last_activation_by_category` uses string keys (category names), not unit keys, so weak-key tables aren't needed for the outer table. The `unit` value stored inside will be garbage-collected naturally when the bot despawns — the table only holds the most recent activation per category, so stale entries are overwritten.

## Risks

- **Over-suppression**: Mitigated by emergency overrides, per-category (not global) suppression, and short windows
- **Deadlock (no bot activates)**: Impossible — table only suppresses after a confirmed `use_ability_charge` event
- **False suppression from wasted ability**: Acceptable — the charge was consumed regardless
- **Hot-reload state**: `reset()` in `on_game_state_changed` prevents stale suppression across sessions
