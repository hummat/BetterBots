# Human-Likeness Tier A Design

Date: 2026-04-12
Issue: #44

## Problem

BetterBots improves competence but still feels robotic in three obvious ways:

1. combat abilities fire the instant a heuristic flips true
2. vanilla opportunity-target reaction times are absurdly slow (`10-20`)
3. vanilla challenge-aware melee engage scaling is dead because `_allow_engage()` hardcodes `challenge_rating = 0`

The issue text describes these as Tier A because they are high-impact and low-effort. That is correct, but one implementation detail in the issue body is wrong for this repo: activation jitter should **not** live in `heuristics.lua`.

`heuristics.lua` is currently a pure decision layer used by both BT and fallback paths. Putting time/stateful jitter there would contaminate rule evaluation with queueing concerns and make the code harder to test. Timing belongs in the activation path that already owns retries, cooldown suppression, and queue sequencing.

## Decision

Implement strict Tier A only:

- combat-ability activation jitter only
- opportunity-target reaction times reduced from `10-20` to `2-5`
- challenge-aware engage-range scaling restored in BetterBots' melee leash path

Out of scope:

- grenade/blitz jitter
- weapon aim tuning
- dodge timing
- personality variance
- LOS/perception realism

## Architecture

Add a new `human_likeness.lua` module and keep the behavior split by responsibility:

- `human_likeness.lua`
  - owns Tier A tuning constants
  - patches `BotSettings.opportunity_target_reaction_times.normal`
  - decides whether a combat-ability decision should be delayed
  - computes delay window and emergency bypass
  - computes challenge-pressure leash scaling

- `ability_queue.lua`
  - stores pending jitter state in existing fallback per-unit state
  - schedules delayed combat-ability activation after a positive decision
  - clears pending jitter when decision/template becomes invalid
  - immediately bypasses jitter for emergency cases

- `engagement_leash.lua`
  - asks `human_likeness.lua` for challenge-pressure scaling
  - applies scaling to BetterBots' existing effective leash instead of restoring vanilla wholesale

- `BetterBots.lua`
  - loads and wires `human_likeness.lua`
  - patches `BotSettings` singleton on load

## Opportunity Reaction Times

Patch vanilla `BotSettings.opportunity_target_reaction_times.normal` from:

```lua
{ min = 10, max = 20 }
```

to:

```lua
{ min = 2, max = 5 }
```

This should be done by mutating the loaded singleton table, not by replacing `BotTargetSelection`.

Reason:

- smallest possible change
- affects exactly the existing opportunity-target gate
- keeps monster reaction timing untouched

## Combat Ability Jitter

Apply jitter only to fallback-queued combat abilities in `ability_queue.lua`.

Why fallback only:

- BetterBots already notes that virtually all solo-play activations come through fallback
- fallback path already owns activation state, retries, team cooldown suppression, rescue aim, and queue timing
- no need to push state into BT condition functions

### Delay Window

Use randomized delay:

- minimum: `0.3s`
- maximum: `1.5s`

### Emergency Bypass

Do **not** delay when the rule indicates immediate self-save or ally-save behavior.

Initial bypass class:

- any rule in `SharedRules.RESCUE_CHARGE_RULES`
- any rule whose name clearly denotes aid/emergency/self-save behavior:
  - contains `ally_aid`
  - contains `panic`
  - contains `last_stand`
  - contains `hazard`

This is intentionally conservative. The purpose is to avoid making bots feel dumber during obvious emergency casts.

### State Machine

Extend existing fallback state with:

- `pending_rule`
- `pending_template_name`
- `pending_action_input`
- `pending_ready_t`

Behavior:

1. positive decision + no pending jitter + no emergency bypass:
   - schedule `pending_ready_t = fixed_t + random_delay`
   - return without queueing

2. same decision while `fixed_t < pending_ready_t`:
   - keep waiting

3. decision disappears or template/input changes before maturity:
   - clear pending jitter state

4. same decision when `fixed_t >= pending_ready_t`:
   - queue once and clear pending state

This keeps the change local to queue timing and does not alter heuristic truthiness.

## Engage Range Dead-Code Fix

Vanilla `_allow_engage()` lerps between:

- `override_engage_range_to_follow_position = 12`
- `override_engage_range_to_follow_position_challenge = 6`

across challenge rating `10 -> 30`, but `challenge_rating` is hardcoded to `0`, so the challenge branch never runs.

BetterBots already replaces this behavior in `engagement_leash.lua` by writing both override values to the same effective leash. That means the dead-code fix belongs in BetterBots' hook, not in vanilla `_allow_engage()`.

### Scaling Rule

Use `Heuristics.build_context(unit, blackboard).challenge_rating_sum` as the pressure signal.

Then apply the same vanilla threshold range:

- `<= 10`: no shrink
- `>= 30`: full shrink
- between: quadratic lerp, same shape as vanilla

Instead of replacing BetterBots leash with vanilla `6-12m`, scale the computed BetterBots leash toward a more conservative pressure leash:

```text
scaled_leash = lerp(effective_leash, challenge_leash, quadratic_t)
challenge_leash = max(6, effective_leash * 0.5)
```

This preserves BetterBots' coherency-aware extensions while finally making high-pressure situations pull melee bots tighter at higher threat density.

## Scope

### In scope

- new `human_likeness.lua`
- combat-ability jitter in fallback queue
- opportunity-target reaction-time patch
- challenge-aware leash shrink in `engagement_leash.lua`
- tests and docs for all three

### Out of scope

- BT-path activation jitter
- grenade/blitz timing changes
- ranged aim-speed/spread tuning
- dodge timing changes
- per-bot personalities

## Tests

### New `tests/human_likeness_spec.lua`

Cover:

- `patch_bot_settings()` changes opportunity reaction times to `2-5`
- patch is idempotent
- emergency bypass classification works for rescue/panic/hazard style rules
- challenge-pressure scaling returns:
  - unchanged leash at low pressure
  - partial shrink in mid band
  - max shrink at high pressure

### Extend `tests/ability_queue_spec.lua`

Cover:

- positive decision schedules jitter instead of immediate queue
- pending jitter queues after ready time
- pending jitter clears when decision turns false
- emergency rule bypasses jitter and queues immediately

### Extend `tests/engagement_leash_spec.lua`

Cover:

- no pressure keeps current leash
- mid pressure shrinks leash
- high pressure shrinks leash more aggressively but does not go below floor

## Docs To Update After Implementation

- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`

If behavior wording in bot-system docs needs it, update:

- `docs/bot/perception-targeting.md`
- `docs/bot/vanilla-capabilities.md`

## Acceptance Criteria

- bots react to opportunity targets in `2-5` time units instead of `10-20`
- fallback-queued combat abilities no longer fire on the exact threshold frame unless emergency-bypassed
- emergency combat abilities still fire immediately
- melee engage leash becomes more conservative under high local challenge pressure
- no grenade/blitz timing changes are introduced
- automated tests cover timing, patching, and leash scaling behavior
