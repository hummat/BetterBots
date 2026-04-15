# Mule Pickup Implementation Plan

Goal: activate vanilla mule pickup for side-mission books by patching missing pickup metadata, while keeping grimoires behind a BetterBots toggle that defaults off.

Architecture: add a small `mule_pickup.lua` module. It should patch the two book pickup templates once, expose a narrow grimoire classifier/helper layer, and register only the minimal live guards needed so grimoires stay blocked when the toggle is off. Do not rewrite `BotGroup` or duplicate vanilla mule assignment logic.

Tech stack: Lua, DMF hooks, busted tests, existing BetterBots settings/UI/docs flow

## File map

- Create: `scripts/mods/BetterBots/mule_pickup.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Modify: `scripts/mods/BetterBots/settings.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
- Create: `tests/mule_pickup_spec.lua`
- Modify: `tests/startup_regressions_spec.lua`
- Modify: `tests/settings_spec.lua` (only if needed for explicit default coverage)
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/bot/vanilla-capabilities.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

## Task 1: Add failing mule pickup tests

Files:
- create `tests/mule_pickup_spec.lua`
- maybe extend `tests/settings_spec.lua`

Steps:
- write focused red tests for:
  - tome template patch (`slot_name`, `bots_mule_pickup`)
  - grimoire template patch default-off
  - grimoire template patch enabled-on
  - clearing live grimoire mule target when setting off
  - preserving non-grimoire mule target
  - blocking grimoire pickup order when setting off
  - allowing grimoire pickup order when setting on
- run `make test TESTS=tests/mule_pickup_spec.lua`
- if settings default test is missing, add one in `tests/settings_spec.lua` and run that file too

Acceptance for task:
- tests fail for the expected missing-module / missing-behavior reason, not for broken scaffolding

## Task 2: Implement `mule_pickup.lua`

Files:
- create `scripts/mods/BetterBots/mule_pickup.lua`

Steps:
- add late-bound deps:
  - `mod`
  - `debug_log`
  - `debug_enabled`
  - `is_grimoire_pickup_enabled`
- load pickup tables via vanilla pickup registry
- patch side-mission book templates once:
  - mirror `inventory_slot_name` into `slot_name` if needed
  - set tome/scripture `bots_mule_pickup = true`
  - set grimoire `bots_mule_pickup` from setting
- expose tiny pure helpers for tests:
  - `patch_pickups()`
  - `is_grimoire_pickup_unit(unit)`
  - `sanitize_mule_pickup(pickup_component)`
  - `should_block_pickup_order(pickup_unit)`
- add hook registration:
  - clear stale grimoire mule targets when disabled
  - suppress pickup orders targeting grimoires when disabled
- keep order/path hooks narrow; do not fork whole vanilla functions unless exact hook point is impossible

Acceptance for task:
- focused mule spec passes

## Task 3: Wire module + setting/UI

Files:
- `scripts/mods/BetterBots/BetterBots.lua`
- `scripts/mods/BetterBots/settings.lua`
- `scripts/mods/BetterBots/BetterBots_data.lua`
- `scripts/mods/BetterBots/BetterBots_localization.lua`
- `tests/startup_regressions_spec.lua`
- maybe `tests/settings_spec.lua`

Steps:
- add default `enable_bot_grimoire_pickup = false`
- add getter in `settings.lua`
- add checkbox widget + localization strings
- load/init/register `MulePickup` in `BetterBots.lua`
- extend startup regression to assert module wiring
- run:
  - `make test TESTS=tests/mule_pickup_spec.lua`
  - `make test TESTS=tests/startup_regressions_spec.lua`
  - `make test TESTS=tests/settings_spec.lua` if touched

Acceptance for task:
- new module is wired and toggle default is explicit

## Task 4: Docs and full verification

Files:
- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- `docs/bot/vanilla-capabilities.md`
- `README.md`
- `AGENTS.md`

Steps:
- document that BetterBots now activates book mule pickup, with grimoire opt-in
- update module count / test count / file inventory claims
- correct vanilla-vs-modded capability wording where `#32` changes it
- run:
  - `make test`
  - `make doc-check`
  - `make check`

Acceptance for task:
- suite green
- doc parity green
- branch clean except intended changes

## Notes

- no separate failing-test commit spam on `dev/v0.11.0`
- if the cleanest grimoire-order suppression requires touching `BotOrder.pickup`, keep the hook tiny and policy-only
- if in-source “tome” naming is actually scripture-equivalent in Darktide UI, preserve source names in code/docs and mention the player-facing term once in docs if needed
