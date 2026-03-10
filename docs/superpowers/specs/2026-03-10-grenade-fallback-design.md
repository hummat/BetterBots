# Design: Standard Grenade Bot Support (#4 Phase 1)

## Summary

Add bot grenade throwing for the 12 standard/handleless grenade templates via a new `grenade_fallback.lua` module. Bots will wield their grenade item, aim, throw, and return to their previous weapon using the existing weapon action input parser.

## Scope

### In scope (12 templates)

| Type | Wield time | Templates |
|------|-----------|-----------|
| Standard (9) | ~1.5s | `frag_grenade`, `fire_grenade`, `smoke_grenade`, `adamant_grenade`, `ogryn_grenade_box`, `ogryn_grenade_box_cluster`, `ogryn_grenade_frag`, `ogryn_grenade_friend_rock`, `tox_grenade` |
| Handleless (3) | ~0.3s | `krak_grenade`, `shock_grenade`, `quick_flash_grenade` |

All share one throw pattern: `aim_hold` (action_one_pressed) -> hold -> `aim_released` (action_one_hold release).

### Deferred

- `adamant_whistle` (Remote Detonation) — has `ability_template`, needs BT ability path + `ability_meta_data` injection. Separate work item.
- Psyker blitz (`psyker_smite`, `psyker_chain_lightning`, `psyker_throwing_knives`) — bespoke action hierarchies, warp charge gating.
- `zealot_throwing_knives` — single-press `spawn_projectile`, different pattern.
- `shock_mine` — place mechanic, not throw.
- `broker_missile_launcher` — unique item.

## Key findings from decompiled source

1. **Wield path**: Every weapon template inherits a `"grenade_ability"` action input from `base_template_settings` that does `unwield_to_specific` -> `slot_grenade_ability`. The slot has no `wield_inputs`, so `BtBotInventorySwitchAction` cannot switch to it — must go through the weapon action parser.
2. **Throw inputs**: Grenade weapon templates define `aim_hold` (action_one_pressed) and `aim_released` (action_one_hold=false). Both standard and handleless use the same inputs; they differ only in wield animation time.
3. **Charge API**: `can_use_ability("grenade_ability")` and `use_ability_charge("grenade_ability")` both work. Grenade charges use the same component model as combat abilities. `use_ability_charge("grenade_ability")` additionally fires `on_grenade_thrown` proc event.
4. **Unwield**: Grenade templates define `unwield_to_previous` (kind `"unwield_to_previous"`, `unwield_to_weapon = true`). Auto-transition may also occur after throw completes.

## Architecture

### New module: `grenade_fallback.lua`

Follows the same module pattern as `item_fallback.lua` (init/wire, local state, exported functions). Estimated ~200-300 LOC.

### State machine

```
idle -> wield -> wait_aim -> wait_throw -> wait_unwield -> idle
```

| Stage | Action | Transition condition |
|-------|--------|---------------------|
| idle | Check `can_use_ability("grenade_ability")` + heuristic. If pass, queue `"grenade_ability"` on `"weapon_action"`. | Charges available AND heuristic passes |
| wield | Wait for `wielded_slot == "slot_grenade_ability"`. | Slot matches, or timeout -> retry |
| wait_aim | Queue `"aim_hold"` on `"weapon_action"`. Wait for start delay. | Delay elapsed |
| wait_throw | Queue `"aim_released"` on `"weapon_action"`. | Input queued |
| wait_unwield | Wait for `wielded_slot != "slot_grenade_ability"` (auto-transition or explicit `"unwield_to_previous"`). | Slot changed, or timeout -> force unwield |

Timeouts at each stage reset to idle with a retry delay (same pattern as `item_fallback.lua`).

### Heuristics

Initial implementation: generic `enemies_in_proximity > 0` fallback (same as unknown combat abilities). A `GRENADE_HEURISTICS` table in `heuristics.lua` will be empty initially, with `evaluate_grenade_heuristic` falling through to the generic check.

Per-grenade heuristics (elite density, disabler rescue, ammo conservation) are a follow-up.

### Charge tracking

Hook `PlayerUnitAbilityExtension.use_ability_charge` for `ability_type == "grenade_ability"` to confirm successful throws. Separate state dict from combat ability tracking (`_last_grenade_charge_event_by_unit`).

### Integration points

| File | Change type | Description |
|------|------------|-------------|
| `grenade_fallback.lua` | New | State machine module |
| `BetterBots.lua` | Modify | Load/init/wire module, add `try_queue` call in update tick, add grenade charge tracking hook |
| `heuristics.lua` | Modify | Add `GRENADE_HEURISTICS` table + `evaluate_grenade_heuristic` export |
| `grenade_fallback_spec.lua` | New | Unit tests |
| `AGENTS.md` | Modify | Update test counts |
| `docs/dev/roadmap.md` | Modify | Update #4 status |

### Files NOT modified

`item_fallback.lua`, `condition_patch.lua`, `ability_queue.lua`, `meta_data.lua`, `event_log.lua`, `sprint.lua`, `melee_meta_data.lua`, `ranged_meta_data.lua`, `debug.lua`, `poxburster.lua`, `vfx_suppression.lua`, `weapon_action.lua` — zero regression risk to existing functionality.

## Branching

- Feature branch: `feat/4-grenade-fallback` off `main`
- Batch branch: `dev/m5-batch1` (created from `main`, feature branches merge into it)
- Merge to `main` only after full batch is tested in-game

## Testing

### Automated

Unit tests in `tests/grenade_fallback_spec.lua`:
- State machine transitions (idle -> wield -> aim -> throw -> unwield -> idle)
- Charge gating (no throw when charges depleted)
- Timeout/retry at each stage
- Heuristic gate (blocked when no enemies)
- Wield slot detection

### In-game validation

- Fresh mission with debug logging enabled
- Verify bots throw grenades via `bot weapon:` template-tagged log lines
- Verify bots return to previous weapon after throw
- Verify no Lua errors
- Verify existing functionality unaffected (combat abilities, item abilities, melee, ranged)
