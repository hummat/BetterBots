# #31 Ranged `attack_meta_data` Injection — Design

**Goal:** Auto-derive and inject `attack_meta_data` for player ranged weapons so bots can fire weapons whose action input names don't match the hardcoded fallback chain in `bt_bot_shoot_action`.

**Architecture:** New module `ranged_meta_data.lua` following `melee_meta_data.lua` pattern. Validates the vanilla fallback chain per-template, injects corrections only where it would produce invalid inputs.

## Derivation logic

1. **Resolve vanilla fallback** — simulate `bt_bot_shoot_action.enter()`:
   - `fire_action_input = actions["action_shoot"].start_input or "shoot"`
   - `aim_action_input = actions["action_zoom"].start_input or "zoom"`
   - `aim_fire_action_input = actions["action_shoot_zoomed"].start_input or "zoom_shoot"`

2. **Validate** — check if each resolved input exists in `weapon_template.action_inputs`. If all valid, skip.

3. **Derive fire input** — scan `action_inputs` for entries whose `input_sequence[1]` has `input = "action_one_pressed"` and no `hold_input`. Among candidates, keep only those with a matching action (`start_input == candidate_name`). This filters out chain-only inputs like `shoot_braced`.

4. **Derive fire action name** — if `action_shoot` exists, keep it (for projectile/range data). If not, use the action found in step 3.

5. **Derive aim input** — scan for `action_two_hold` entries. Find matching action for `aim_action_name`.

6. **Derive aim-fire input** — scan for entries with both `hold_input = "action_two_hold"` and `input = "action_one_pressed"`. Find matching action for `aim_fire_action_name`.

7. **Inject** — only the fields that differ from vanilla fallback. Idempotent via `_patched_set`.

## What this fixes

| Weapon | Problem | Derived fix |
|---|---|---|
| Plasma gun | `action_shoot.start_input = nil` → `"shoot"` (invalid) | `fire_action_input = "shoot_charge"`, `fire_action_name = "action_charge_direct"` |
| Force staff p1 | No `action_shoot` → `"shoot"` (invalid) | `fire_action_input = "shoot_pressed"`, `fire_action_name = "rapid_left"` |
| Other exotic | Same pattern | Auto-derived |
| Lasgun, autogun, bolter, flamer | Vanilla fallback valid | Skipped |

## What this does NOT do

- No charge metadata (`can_charge_shot`, `minimum_charge_time`, etc.) — the bot queues the fire input and the weapon's `running_action_state_to_action_input` handles charge-then-fire internally
- No per-weapon manual mapping — everything auto-derived
- No new per-frame hooks or engine queries

## Integration

Same as melee: `hook_require` on `weapon_templates` in `BetterBots.lua`. Could share the same hook or use a separate one.

## Testing

Unit tests with mock weapon templates covering:
- Vanilla-valid templates skipped
- Single `action_one_pressed` derivation
- Multiple candidates with disambiguation (plasma-like)
- `hold_input` filtering (aim-fire separation)
- Missing `action_shoot` (force staff pattern)
- `action_shoot` with nil `start_input` (plasma pattern)
- Idempotency / no-overwrite

## Key research findings

- `action_transitioned_with_automatic_input` early-returns for bots but this is benign — `action_handler.start_action()` fires regardless (line 687)
- Plasma gun `shoot_charge` → `action_charge_direct` → auto `charged_enough` → `action_shoot` works for bots via `running_action_state_to_action_input`
- Flamer works with vanilla fallback (`action_shoot.start_input = "shoot_pressed"`)
- `_update_buffering` runs for bots but buffer_time is sufficient for fire inputs
