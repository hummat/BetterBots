# Configurable Ammo Policy Design

Date: 2026-04-07
Issue: #72

## Problem

BetterBots currently hardcodes one half of bot ammo behavior and inherits the rest from vanilla:

- opportunistic ranged fire is lowered from vanilla `50%` to `20%` in `condition_patch.lua`
- priority-target ranged fire still works down to `0%`
- ammo pickup intent is still driven by vanilla `BotBehaviorExtension._update_ammo()`

That creates two problems:

1. The original `#72` dead band: BetterBots stops opportunistic ranged fire at `20%`, but vanilla only flips `needs_ammo` below `10%` in combat.
2. The broader policy mismatch: even outside that dead band, vanilla ammo pickup logic is not the policy desired for this mod. Vanilla also requires the bot to have the least ammo among valid humans and uses a much higher out-of-combat pickup threshold.

The requested behavior is simpler and more explicit:

- one configurable threshold `X` controls both opportunistic ranged fire floor and ammo pickup onset
- one configurable threshold `Z` blocks bot ammo pickup unless all eligible humans are already above that reserve

## Decision

Replace the hardcoded BetterBots ammo threshold with a configurable ammo policy:

- `X`: bot ranged ammo threshold, default `20%`
- `Z`: human ammo reserve threshold, default `80%`

Rules:

- opportunistic ranged fire may continue while the bot is above `X`
- ammo pickup intent starts when the bot is at or below `X`
- ammo pickup intent is allowed only when every eligible human is above `Z`
- priority-target ranged fire remains unchanged and still works down to `0%`

Both settings are exposed as real DMF sliders with `5%` step size.

## Eligible Humans

"All humans have enough ammo" means:

- alive human player units only
- humans whose current loadout actually uses ammo, as determined by `Ammo.uses_ammo(human_unit)`

This intentionally excludes dead players, spectators, and non-ammo loadouts such as staff/peril-driven ranged weapons from blocking bot ammo pickup.

## Rationale

The dead-band-only fix is too narrow. It would paper over the `10-20%` idle hole, but it would still leave ammo behavior partly owned by BetterBots and partly owned by unrelated vanilla rules.

The requested policy is coherent because it separates two concerns cleanly:

- bot reserve discipline: "stop casual ranged fire below `X`"
- team resource fairness: "don't take ammo unless humans are already comfortable above `Z`"

Locking pickup onset to the same threshold as opportunistic fire avoids another split-brain policy where one slider changes shooting behavior and a second slider changes pickup timing in a different way.

Leaving priority-target fire alone avoids a bad failure mode where raising `X` would make bots stop answering specials and elites with ranged weapons just because the user wants more conservative horde ammo use.

## Scope

### In scope

- Opportunistic ranged fire threshold override in `condition_patch.lua`
- Ammo pickup policy in `BotBehaviorExtension._update_ammo()`
- Two new user-facing bot behavior settings
- Tests for threshold parsing, human eligibility, and pickup/fire behavior

### Out of scope

- Rewriting general loot behavior beyond ammo
- Mule item pickup (`#32`)
- Healing item / stim distribution (`#24`)
- Changing the priority-target `0%` ranged path
- Class-specific ammo exceptions

## Architecture

Add a new `ammo_policy.lua` module instead of extending `condition_patch.lua`.

Responsibilities:

- `condition_patch.lua`
  - remains the BT condition layer
  - reads configured threshold `X`
  - overrides only the vanilla opportunistic ranged threshold (`0.5`)
  - does not touch priority-target ranged conditions (`0`)

- `ammo_policy.lua`
  - owns ammo pickup policy
  - hooks `BotBehaviorExtension._update_ammo`
  - reads configured thresholds `X` and `Z`
  - rewrites `pickup_component.needs_ammo` after vanilla runs
  - preserves explicit ammo pickup orders

- `settings.lua`
  - exposes typed accessors for `X` and `Z`
  - centralizes slider value normalization so other modules read numbers, not raw UI strings

This mirrors the existing pattern used by `healing_deferral.lua`: a dedicated post-process policy hook layered on top of vanilla `BotBehaviorExtension`.

## Settings UI

Add two new controls under the Bot Behavior group:

1. `bot_ranged_ammo_threshold`
   - slider
   - default `20`
   - min `5`
   - max `30`
   - step `5`
   - semantic meaning: opportunistic ranged fire floor and ammo pickup onset

2. `bot_human_ammo_reserve_threshold`
   - slider
   - default `80`
   - min `50`
   - max `100`
   - step `5`
   - semantic meaning: minimum ammo reserve every eligible human must have before bots may claim ammo

These should render as percentage sliders, not dropdowns.

## Pickup Policy Details

`ammo_policy.lua` should implement this order:

1. Run vanilla `_update_ammo()` first.
2. If the bot has an explicit ammo pickup order, keep `pickup_component.needs_ammo = true`.
3. Otherwise, compute bot ammo percentage.
4. If bot ammo is above `X`, force `pickup_component.needs_ammo = false`.
5. If bot ammo is at or below `X`, evaluate eligible humans:
   - if any eligible human is at or below `Z`, force `pickup_component.needs_ammo = false`
   - if all eligible humans are above `Z`, set `pickup_component.needs_ammo = true`

The mod should not preserve vanilla's "bot must have the least ammo among humans" rule. That rule conflicts directly with the requested policy and would create hard-to-explain edge cases where bots remain ammo-starved even though all humans are comfortably above reserve.

If there are no eligible humans, the human-reserve guard is vacuously satisfied and the bot may claim ammo when at or below `X`.

## Logging

No new spammy per-frame logs.

If debug logging is enabled, log only policy changes or noteworthy decisions:

- opportunistic ranged threshold override uses configured `X`
- ammo pickup suppressed because an eligible human is below `Z`
- ammo pickup permitted because all eligible humans are above `Z`

Keys must follow the existing throttling conventions and include `tostring(unit)` for per-bot paths.

## Tests

### `tests/condition_patch_spec.lua`

Add coverage for:

- configured `X` overrides vanilla opportunistic ranged threshold `0.5`
- priority-target threshold `0` remains untouched
- non-default condition args remain untouched
- debug logging reflects the configured threshold

### New `tests/ammo_policy_spec.lua`

Add coverage for:

- settings parsing defaults to `X = 0.20`, `Z = 0.80`
- bot above `X` does not request ammo
- bot at or below `X` requests ammo when all eligible humans are above `Z`
- bot at or below `X` does not request ammo when any eligible human is at or below `Z`
- humans without ammo-using loadouts are ignored
- explicit ammo pickup orders are preserved
- stale `needs_ammo` is cleared when the bot rises above `X` or a human drops below `Z`
- no eligible humans means the reserve guard passes

### `tests/settings_spec.lua`

Add coverage for:

- slider values are normalized into percentages correctly
- invalid or missing values fall back to defaults

## Docs To Update After Implementation

- `docs/dev/architecture.md` — add `ammo_policy.lua` and the new hook behavior
- `docs/dev/status.md` — mark `#72` implemented on branch once landed
- `docs/dev/roadmap.md` — update `#72` notes from dead-band fix to configurable ammo policy
- `docs/dev/known-issues.md` — remove or restate the old dead-band issue
- `docs/nexus-description.bbcode` — document the new ammo sliders and bot ammo-sharing policy

## Acceptance Criteria

- With defaults, bots continue opportunistic ranged fire down to `20%`.
- With defaults, bots may seek ammo at `20%` or below.
- Bots do not seek ammo if any eligible human ammo user is at or below `80%`.
- Priority-target ranged attacks still work down to `0%`.
- Changing `X` changes both opportunistic ranged fire floor and ammo pickup onset together.
- Changing `Z` changes only the human reserve guard for ammo pickup.
- The implementation does not depend on the bot having less ammo than humans.
- Unit tests cover both BT threshold override and pickup-policy behavior.
