# Mule Pickup Design

Date: 2026-04-12
Issue: #32
Branch target: `dev/v0.11.0`

## Problem

Vanilla bot mule pickup already exists end-to-end:

- `BotGroup` scans pickup templates flagged with `bots_mule_pickup`
- `BotGroup._update_mule_pickups` assigns `pickup_component.mule_pickup`
- BT `can_loot` accepts `pickup_component.mule_pickup`
- `BotBehaviorExtension` paths to and interacts with the assigned pickup

But the path is dead in stock Darktide for two separate reasons:

1. side-mission book pickups never set `bots_mule_pickup = true`
2. mule pickup code still reads `pickup_settings.slot_name`, while the actual pocketable pickup templates expose `inventory_slot_name = "slot_pocketable"`

Because of that mismatch, the candidate pool is empty and player pickup orders for pocketables also miss the same slot key.

## Goals

- Enable vanilla mule pickup flow for side-mission books.
- Let bots auto-pick scriptures / tomes.
- Gate grimoire carrying behind a BetterBots setting.
- Keep the implementation tight: no BT rewrite, no generalized pocketable framework, no crate/stim carry scope creep.

## Non-goals

- No deployable crate carry or deploy (`#88`).
- No healing-item or stim pickup management (`#24`).
- No generalized support for arbitrary `interaction_type = "pocketable"` items.
- No new destination priority or interaction behavior.

## Source constraints

Verified in decompiled source:

1. `scripts/extension_systems/group/bot_group.lua` builds `_available_mule_pickups` only from pickup templates with `bots_mule_pickup == true`, keyed by `pickup_settings.slot_name`.
2. `scripts/extension_systems/group/bot_group.lua` later inserts live pickup units into `available_mule_pickups[slot_name]`, again reading `pickup_data.slot_name`.
3. `scripts/utilities/bot_order.lua` also routes pickup and drop orders through `pickup_settings.slot_name`.
4. `scripts/settings/pickup/pickups/side_mission/grimoire_pickup.lua` and `tome_pickup.lua` expose `inventory_slot_name = "slot_pocketable"` and do not define `slot_name` or `bots_mule_pickup`.
5. Bot loot logic already consumes `pickup_component.mule_pickup` in `bt_bot_conditions.can_loot`.

These constraints strongly favor template mutation over deep runtime hook surgery.

## Chosen approach

Add a new `mule_pickup.lua` module that mutates the two side-mission pickup templates at load time:

- mirror `inventory_slot_name` into `slot_name`
- set `bots_mule_pickup = true` for tome/scripture pickup
- set `bots_mule_pickup` for grimoire pickup according to a BetterBots checkbox, default `false`

Also add a narrow runtime guard for the grimoire-off case so stale mule targets or ordered pickups cannot survive after settings changes or hot reload:

- clear `pickup_component.mule_pickup` when it points at a grimoire while the setting is off
- ignore pickup/drop orders targeting grimoires while the setting is off

This keeps the change local and source-aligned:

- vanilla scanning, assignment, pathing, and interaction remain intact
- BetterBots only populates the missing metadata and enforces the grimoire policy

## Policy

### Tomes / scriptures

- always mule-pickup enabled
- no user toggle for v0.11.0

### Grimoires

- controlled by new setting `enable_bot_grimoire_pickup`
- default `false`
- when `false`, bots must neither auto-pick nor obey player pickup orders for grimoires
- when `true`, grimoires use the same vanilla mule path as scriptures

This is intentionally conservative because grimoires are high-risk and permanent-corruption items.

## Module changes

### `scripts/mods/BetterBots/mule_pickup.lua`

New module.

Responsibilities:

- patch the side-mission pickup templates on load
- expose helper to test whether a pickup unit is a grimoire
- hook the minimal live paths needed for the grimoire toggle:
  - mule target cleanup
  - pickup order suppression
  - optional drop-order suppression if needed for slot-key safety

Implementation rules:

- do not rewrite `BotGroup._update_mule_pickups`
- do not clone vanilla functions just to inject one condition
- mutate pickup templates once and let the engine do the rest

### `scripts/mods/BetterBots/settings.lua`

Add:

- `enable_bot_grimoire_pickup` default getter / setting support

### `scripts/mods/BetterBots/BetterBots_data.lua`

Expose one new checkbox in the existing feature/tuning surface:

- `enable_bot_grimoire_pickup`

### `scripts/mods/BetterBots/BetterBots_localization.lua`

Add title + description strings for the grimoire toggle.

### `scripts/mods/BetterBots/BetterBots.lua`

Load and wire the new module.

## Logging

Permanent debug-gated logs:

- `mule_pickup_patch:<pickup_name>` when template mutation is applied
- `mule_pickup_block_grim:<unit>` when a live grimoire mule target is cleared
- `mule_pickup_order_block:<unit>` when a grimoire pickup order is refused

No per-frame idle logging.

## Testing

Add new `tests/mule_pickup_spec.lua`.

Required coverage:

1. tome template gains `slot_name = "slot_pocketable"` and `bots_mule_pickup = true`
2. grimoire template gains `slot_name = "slot_pocketable"`
3. grimoire template `bots_mule_pickup` follows setting default and enabled state
4. live mule pickup pointing at a grimoire is cleared when the setting is off
5. non-grimoire mule pickup is preserved
6. grimoire pickup order is blocked when the setting is off
7. grimoire pickup order is allowed when the setting is on

Extend `tests/settings_spec.lua` for the new default only if needed.

Add startup regression coverage for module wiring.

## Acceptance criteria

- Bots can carry scriptures / tomes through the vanilla mule path.
- Grimoires remain bot-ignored by default.
- Enabling the grimoire toggle allows bots to carry grimoires through the same vanilla mule path.
- Player pickup orders for grimoires are rejected while the toggle is off.
- No crate/stim/pocketable feature creep is introduced.
- `make test` and `make doc-check` pass after the change.

## Risks

- The same `slot_name` mismatch affects `BotOrder`. Fixing template metadata is correct, but the spec must explicitly cover both scan and order paths.
- Live setting flips can leave stale mule targets in the pickup component. The runtime cleanup hook must handle that narrow case instead of assuming load-time patching is enough.
- This feature depends on engine-side pocketable interaction remaining valid for bot units. The code path exists in source, but in-game validation is still needed after implementation.

## Files expected to change

- `scripts/mods/BetterBots/mule_pickup.lua`
- `scripts/mods/BetterBots/BetterBots.lua`
- `scripts/mods/BetterBots/settings.lua`
- `scripts/mods/BetterBots/BetterBots_data.lua`
- `scripts/mods/BetterBots/BetterBots_localization.lua`
- `tests/mule_pickup_spec.lua`
- `tests/settings_spec.lua` (maybe)
- `tests/startup_regressions_spec.lua`
- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- `docs/bot/vanilla-capabilities.md`
- `README.md`
- `AGENTS.md`

## References

- `scripts/extension_systems/group/bot_group.lua`
- `scripts/utilities/bot_order.lua`
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua`
- `scripts/settings/pickup/pickups/side_mission/grimoire_pickup.lua`
- `scripts/settings/pickup/pickups/side_mission/tome_pickup.lua`
