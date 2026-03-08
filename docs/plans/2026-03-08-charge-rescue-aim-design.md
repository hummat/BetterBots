# Charge-to-Rescue Aim Direction (#10)

## Problem

When a bot activates a charge/dash to rescue a disabled ally, the lunge fires in whatever direction the bot is currently facing — not toward the ally. Only ogryn self-corrects mid-lunge (`allow_steering = true` in `ogryn_lunge_templates.lua:15`). Zealot dash and Arbites charge do not steer.

## Lunge direction mechanics (from decompiled source)

- `player_character_state_lunging.on_enter()` reads `first_person_component.rotation` forward vector as lunge direction
- `directional_lunge = false` for all three charge abilities (zealot, ogryn, adamant)
- `allow_steering = true` only on ogryn — updates direction from `locomotion_steering_component.target_rotation` each tick
- Zealot/Arbites charges are fire-and-forget in the initial facing direction
- `BtBotActivateAbilityAction` never calls `set_aim_position()` — no aim correction exists

## Current state

- `ogryn_charge` has a rescue trigger (heuristics.lua:426): `target_ally_needs_aid AND distance > 6`
- `zealot_targeted_dash` and `adamant_charge` have NO rescue triggers
- No aim direction correction for any charge ability

## Design

### 1. Enrich `build_context()` (heuristics.lua)

Add `context.target_ally_unit` — the unit handle from `perception_component.target_ally`. Needed for `POSITION_LOOKUP[unit]` at aim time.

### 2. Add rescue triggers (heuristics.lua)

- `_can_activate_zealot_targeted_dash`: `target_ally_needs_aid` check with distance gate → `"zealot_dash_ally_aid"`
- `_can_activate_adamant_charge`: `target_ally_needs_aid` check with distance gate → `"adamant_charge_ally_aid"`

### 3. Rescue intent tracking (BetterBots.lua)

- Module-local `_rescue_intent = {}` keyed by bot unit
- In `can_activate_ability` condition hook: when heuristic returns a rescue-charge rule, store `{ally_unit = target_ally_unit}` for that bot
- Known rescue-charge rules: `ogryn_charge_ally_aid`, `zealot_dash_ally_aid`, `adamant_charge_ally_aid`

### 4. Aim hook (BetterBots.lua)

- `mod:hook(BtBotActivateAbilityAction, "enter", ...)` — check `_rescue_intent[unit]`, call `bot_unit_input:set_aim_position(POSITION_LOOKUP[ally_unit])`, clear entry

### 5. Tests (tests/heuristics_spec.lua)

- New rescue trigger tests for zealot dash and adamant charge
- `build_context` test for `target_ally_unit` population

## Not in scope

- Navmesh validation (#13) — separate M4 issue
- Non-charge rescue abilities (VoC, stealth, taunt, force field) — AoE/self-buffs, facing irrelevant

## Files touched

- `scripts/mods/BetterBots/heuristics.lua`
- `scripts/mods/BetterBots/BetterBots.lua`
- `tests/heuristics_spec.lua`
