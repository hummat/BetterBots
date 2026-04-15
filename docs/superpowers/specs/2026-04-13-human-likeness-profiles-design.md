# Human-Likeness Profiles Design

Date: 2026-04-13
Follow-up to: #44

## Problem

The current human-likeness implementation is too coarse:

1. one feature gate (`enable_human_likeness`) controls two unrelated behaviors:
   - timing hesitation
   - high-pressure melee caution
2. combat-ability jitter uses one blunt `0.3-1.5s` range for almost every non-bypass case
3. the settings surface cannot tune timing and leash behavior independently

This creates two practical problems:

- the timing labels are misleading because “human-like” does not name a real, observable behavior
- pressure-based leash scaling does not fit the same `fast/medium/slow` mental model as timing

## Decision

Replace the old checkbox-only model with two separate profile dropdowns:

- `human_timing_profile`
- `pressure_leash_profile`

Each dropdown supports:

- `off`
- preset values
- `custom`

`custom` reveals hidden sliders for that axis only. No separate `enable_human_likeness` checkbox remains.

## Why Split The Setting

Timing and leash scaling are different behavioral dimensions:

- timing controls how fast bots react and how long they hesitate before non-urgent casts
- leash scaling controls how tightly melee bots stay anchored to the team under pressure

These should not share one label set because:

- `slow` timing does not imply stronger formation discipline
- stronger pressure caution does not imply slower ability use
- users can reasonably want one on and the other off

## Settings Model

### Timing Dropdown

New setting:

- `human_timing_profile`

Values:

- `off`
- `fast`
- `medium`
- `slow`
- `custom`

This dropdown controls:

- opportunity-target reaction-time patch
- combat-ability jitter bucket tuning

### Timing Buckets

Timing is split into three urgency buckets:

1. `immediate`
   - no jitter
   - for clear emergency/self-save/rescue rules
2. `defensive`
   - small jitter
   - for reactive but non-cliff-edge survival rules
3. `opportunistic`
   - larger jitter
   - for “good moment to use this” rules

### Rule Classification

#### Immediate

Rules matching obvious emergency/rescue semantics stay instant:

- contains `ally_aid`
- contains `panic`
- contains `last_stand`
- contains `hazard`
- contains `emergency`
- contains `escape`
- contains `high_peril`

#### Defensive

Rules with reactive survival pressure but not true emergency:

- contains `protect_interactor`
- contains `critical`
- contains `low_health`
- contains `self_critical`
- contains `low_toughness`
- contains `surrounded`
- contains `overwhelmed`
- contains `pressure`
- contains `high_threat`
- contains `ally_reposition`

Everything else falls into `opportunistic`.

This stays string-based because the existing rule API only exposes rule names, not typed urgency metadata. That is acceptable here as long as tests pin the classification for current rule names.

### Timing Presets

`off`

- opportunity reaction times: vanilla `10-20`
- defensive jitter: `0-0 ms`
- opportunistic jitter: `0-0 ms`

`fast`

- opportunity reaction times: `1-3`
- defensive jitter: `50-150 ms`
- opportunistic jitter: `150-450 ms`

`medium` (default)

- opportunity reaction times: `2-4`
- defensive jitter: `100-250 ms`
- opportunistic jitter: `250-700 ms`

`slow`

- opportunity reaction times: `3-6`
- defensive jitter: `150-350 ms`
- opportunistic jitter: `400-1000 ms`

### Timing Custom Sliders

Shown only when `human_timing_profile == "custom"`:

- `human_timing_reaction_min`
- `human_timing_reaction_max`
- `human_timing_defensive_jitter_min_ms`
- `human_timing_defensive_jitter_max_ms`
- `human_timing_opportunistic_jitter_min_ms`
- `human_timing_opportunistic_jitter_max_ms`

Validation rules:

- reaction min/max must be numeric and within the configured slider bounds
- defensive jitter min <= max
- opportunistic jitter min <= max
- defensive jitter range should never be negative
- opportunistic jitter range should never be negative

If invalid, settings accessors fall back to the `medium` preset values.

## Pressure-Leash Dropdown

New setting:

- `pressure_leash_profile`

Values:

- `off`
- `light`
- `medium`
- `strong`
- `custom`

This dropdown controls only challenge-pressure scaling in `human_likeness.lua` as consumed by `engagement_leash.lua`.

### Pressure-Leash Presets

`off`

- disables pressure-based leash shrink

`light`

- pressure starts at `16`
- full pressure at `36`
- full-pressure leash target = `80%` of base leash
- floor = `8 m`

`medium` (default)

- pressure starts at `12`
- full pressure at `30`
- full-pressure leash target = `65%` of base leash
- floor = `7 m`

`strong`

- pressure starts at `8`
- full pressure at `24`
- full-pressure leash target = `50%` of base leash
- floor = `6 m`

### Pressure-Leash Custom Sliders

Shown only when `pressure_leash_profile == "custom"`:

- `pressure_leash_start_rating`
- `pressure_leash_full_rating`
- `pressure_leash_scale_percent`
- `pressure_leash_floor_m`

Validation rules:

- start rating >= 0
- full rating > start rating
- scale percent within a bounded slider range such as `25-100`
- floor meters within a sane melee leash range such as `4-12`

If invalid, settings accessors fall back to the `medium` preset values.

## Architecture

### `settings.lua`

Responsibilities:

- remove `enable_human_likeness` from `FEATURE_GATES` and defaults
- add the two dropdown settings plus hidden custom-slider defaults
- expose typed accessors for:
  - current timing profile
  - current pressure-leash profile
  - resolved timing config
  - resolved pressure-leash config
- provide legacy migration behavior from `enable_human_likeness`

### `BetterBots_data.lua`

Responsibilities:

- replace the old checkbox widget with two dropdown widgets
- attach hidden `sub_widgets` to each dropdown for `custom`
- keep timing and leash controls in the same behavior/settings group

### `BetterBots_localization.lua`

Responsibilities:

- new labels and tooltips for:
  - the two dropdowns
  - each preset label
  - all custom sliders
- remove stale checkbox copy that implies one merged “less robotic timing” toggle

### `human_likeness.lua`

Responsibilities:

- stop owning fixed compile-time constants for one timing range and one leash curve
- read resolved timing/leash configs via injected accessors
- patch `BotSettings.opportunity_target_reaction_times.normal` according to the resolved timing profile
- classify rules into `immediate`, `defensive`, or `opportunistic`
- return jitter delays based on urgency bucket
- scale engage leash based on the resolved pressure-leash profile

### `ability_queue.lua`

Responsibilities:

- keep existing pending-jitter state machine
- change the call from one global random delay to bucket-aware random delay
- leave emergency/immediate rules instant

### `engagement_leash.lua`

Responsibilities:

- keep current call path
- consume the updated leash-scaling function from `human_likeness.lua`
- no direct setting reads here

### `BetterBots.lua`

Responsibilities:

- keep eager `BotSettings` patching
- update setting-change handling to refresh `BotSettings` when the timing dropdown or timing custom sliders change
- no special runtime refresh is required for leash profile changes because leash reads live settings on each call

## Migration

Legacy setting:

- `enable_human_likeness`

Migration behavior:

- if the new dropdown settings are unset and legacy `enable_human_likeness == false`, resolve both new profiles to `off`
- otherwise default both new profiles to `medium`

This avoids breaking existing users who explicitly turned the old feature off while letting everyone else inherit the new split defaults.

## Out Of Scope

- per-bot personality variation
- grenade/blitz timing profiles
- dodge timing changes
- aim realism or input latency simulation
- typed urgency metadata refactor in `heuristics.lua`

## Tests

### `tests/settings_spec.lua`

Add coverage for:

- new dropdown defaults
- legacy migration from `enable_human_likeness = false`
- resolved timing config for each preset
- resolved leash config for each preset
- custom slider parsing and invalid-value fallback

### `tests/human_likeness_spec.lua`

Add coverage for:

- timing profile patch values applied to `BotSettings`
- timing `off` restores vanilla `10-20`
- rule bucket classification for current emergency, defensive, and opportunistic examples
- jitter delay ranges by bucket/preset
- pressure-leash scaling by preset
- custom leash/timing fallback behavior on invalid configs

### `tests/ability_queue_spec.lua`

Add coverage for:

- defensive rules use the defensive jitter range
- opportunistic rules use the opportunistic jitter range
- immediate rules still bypass jitter

### `tests/startup_regressions_spec.lua`

Add coverage for:

- new dropdown names are wired in `BetterBots.lua`
- old checkbox references are removed from the settings-surface assertions

## Docs To Update After Implementation

- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `README.md`
- `AGENTS.md` if the settings/testing text still references the old checkbox

## Risks

1. String-based defensive/opportunistic classification can drift if rule names change.
   Mitigation: pin explicit examples in tests and keep classification logic in one function.

2. DMF `show_widgets` indexing can become fragile if the custom sub-widget order changes.
   Mitigation: keep each dropdown’s custom sliders local to that dropdown and test the widget structure by source scan.

3. Re-patching `BotSettings` on multiple slider changes may accidentally preserve stale “original” values if patch bookkeeping is wrong.
   Mitigation: preserve the current original-value cache semantics and add tests for switching between profiles repeatedly.
