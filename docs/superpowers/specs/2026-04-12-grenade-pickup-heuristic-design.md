# Bot Grenade Pickup Heuristic Design

Date: 2026-04-12
Issue: #89
Branch target: `dev/v0.11.0`

## Problem

Vanilla bots never notice `small_grenade` pickups because the bot pickup scan only routes `pickup_data.group == "ammo"` into `pickup_component.ammo_pickup`. `small_grenade` is an `ability` pickup, so bots stand next to grenade refills and ignore them.

BetterBots already patches post-scan ammo behavior in `ammo_policy.lua`. That is the correct insertion point for `#89` because the engine exposes only one pickup lane for bots: `pickup_component.ammo_pickup`.

## Goals

- Let charge-based grenade bots pick up `small_grenade` refills.
- Defer grenade refills to humans when any eligible human is below the configured grenade reserve threshold.
- Preserve existing ammo pickup behavior when grenade pickup is deferred.
- Keep blast radius small: no new BT hooks, no new engine-side pickup component fields.

## Non-goals

- No support for other `ability` pickups.
- No deployable crate carry/deploy logic (`#88`).
- No healing-item management (`#24`).
- No generalized pickup framework in v0.11.0.
- No bot desperation override for grenade pickups.

## Source constraints

Verified in decompiled source:

1. `small_grenade_pickup.lua` declares pickup `group = "ability"`, not `"ammo"`.
2. `BotGroup._update_pickups_and_deployables_near_player` only seeds `pickup_component.ammo_pickup` for pickups where `pickup_data.group == "ammo"`.
3. Bot pickup state exposes only `ammo_pickup`, `ammo_pickup_distance`, and `ammo_pickup_valid_until`.
4. Live ability state already exposes the needed grenade charge API via `ability_extension:remaining_ability_charges("grenade_ability")` and `ability_extension:max_ability_charges("grenade_ability")`.

These constraints rule out a clean engine-native `grenade_pickup` slot. The implementation must piggyback the ammo pickup slot.

## Chosen approach

Extend `ammo_policy.lua` to perform a second, mod-side search for nearby `small_grenade` pickups after the existing ammo policy runs. If grenade pickup is allowed for the bot, overwrite `pickup_component.ammo_pickup` with the grenade pickup unit. If grenade pickup must be deferred to humans, leave the ammo result untouched.

This keeps all pickup arbitration in one place:

- vanilla bot scan seeds ammo candidates
- existing BetterBots ammo policy decides whether ammo should be taken
- new grenade policy may override that slot only when grenade pickup is valid and permitted

## Decision rules

### Bot eligibility

A bot is eligible to seek grenade refills only when:

- it has an ability extension
- `max_ability_charges("grenade_ability") > 0`
- its current grenade charges are at or below the configured bot grenade threshold

This excludes cooldown-only blitz users such as Psyker blitzes with `max_charges == 0`.

### Human eligibility

Only humans with `max_ability_charges("grenade_ability") > 0` participate in grenade-reserve deferral. Humans with cooldown-only blitzes do not block bot grenade pickup.

### Human-first rule

If any eligible human is below the configured human grenade reserve threshold, bot grenade pickup is always deferred. There is no desperation override in this feature.

### Ammo vs grenade arbitration

When both an ammo pickup and a grenade pickup are near the bot:

- grenade wins only if grenade pickup is allowed by the grenade rules
- if grenade pickup is deferred to humans, ammo policy result remains intact

This matches the intended behavior:

- grenade is treated as higher-value than ammo when bot is allowed to take it
- low human grenade reserves do not block bots from taking ammo instead

## Settings

Add grenade-specific settings parallel to ammo policy:

- `bot_grenade_charges_threshold`
- `bot_human_grenade_reserve_threshold`

Recommended defaults for v0.11.0:

- bot grenade threshold: `0` charges
- human grenade reserve threshold: `100%`

Effect of defaults:

- bots only seek grenade refills when empty
- any eligible human missing even one grenade charge gets priority

This is intentionally conservative because grenade pickups are rarer and more valuable than ammo pickups.

## Module changes

### `scripts/mods/BetterBots/ammo_policy.lua`

Keep this feature in the existing pickup-policy module rather than creating a separate `grenade_pickup.lua`.

Add:

- human grenade reserve cache, parallel to existing human ammo cache
- helper to read grenade charge state from live ability extension
- helper to classify units as grenade-pickup eligible (`max_charges > 0`)
- helper to locate the best nearby `small_grenade` pickup for one bot using the same vanilla distance envelope:
  - direct distance under 5m, or
  - within 15m of follow position
- post-ammo arbitration step that may replace `pickup_component.ammo_pickup` with grenade pickup when allowed

Preserve:

- explicit ammo pickup orders
- existing ammo defer/allow behavior
- current perf guard style and debug gating style

### `scripts/mods/BetterBots/settings.lua`

Add getters for the two grenade threshold settings.

### `scripts/mods/BetterBots/BetterBots_data.lua`

Expose the two grenade threshold settings in the existing pickup settings area, mirroring ammo-policy UI style.

## Logging

Add permanent, debug-gated confirmation logs:

- `grenade_pickup_allow:<unit>`
- `grenade_pickup_defer:<unit>`
- `grenade_pickup_bind:<unit>`
- `grenade_pickup_skip_ineligible:<unit>`

Logs should fire on meaningful decisions only. Do not log idle/no-candidate paths every tick.

## Testing

Extend `tests/ammo_policy_spec.lua` instead of creating a new test file. The code lives in `ammo_policy.lua`, so the tests should stay there.

Required coverage:

1. Charge-based bot with 0 grenade charges binds nearby `small_grenade` when all eligible humans are above reserve.
2. Low human grenade reserve defers grenade pickup.
3. Deferred grenade pickup does not suppress otherwise-allowed ammo pickup.
4. Ineligible bot (`max_charges == 0`) ignores grenade pickup.
5. Allowed grenade pickup overrides ammo slot when both ammo and grenade are present.
6. Explicit ammo pickup order still wins and is preserved.

## Acceptance criteria

- Bot walks to and consumes a `small_grenade` pickup when empty and no eligible human is below the grenade reserve threshold.
- Bot defers grenade pickup when any eligible human is below the grenade reserve threshold.
- Deferred grenade pickup does not prevent bot from taking ammo under the existing ammo rules.
- Cooldown-only blitz users do not participate in grenade pickup competition.
- Existing ammo pickup behavior does not regress.
- `make test` and `make doc-check` pass after the change.

## Risks

- Shared-slot design means grenade pickup and ammo pickup compete for one engine field. The policy must be explicit and deterministic to avoid flip-flop.
- Nearby pickup search must stay cheap; expensive reads and logging must remain debug-gated on the hot path.
- Human grenade reserve threshold of 100% is intentionally strict. That is desired for this feature, but the default will make bots very conservative around partially spent human grenade users.

## Files expected to change

- `scripts/mods/BetterBots/ammo_policy.lua`
- `scripts/mods/BetterBots/settings.lua`
- `scripts/mods/BetterBots/BetterBots_data.lua`
- `tests/ammo_policy_spec.lua`
- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- `README.md`
- `AGENTS.md`

## References

- `scripts/mods/BetterBots/ammo_policy.lua`
- `scripts/mods/BetterBots/BetterBots.lua` (`_equipped_grenade_ability` helper pattern)
- `scripts/extension_systems/group/bot_group.lua`
- `scripts/extension_systems/ability/player_unit_ability_extension.lua`
- `scripts/settings/pickup/pickups/consumable/small_grenade_pickup.lua`
