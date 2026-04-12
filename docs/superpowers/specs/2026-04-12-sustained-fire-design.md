# `#87` Sustained Fire For Held-Fire Weapons

## Goal

Fix bot tap-firing on weapons whose real fire path expects a held raw input. Scope is strictly execution: once BetterBots or vanilla metadata has already selected a fire path, keep the corresponding hold signal alive until that action should stop.

This is not `#41`. No new ADS-vs-hipfire policy is introduced here. `#87` only makes already-chosen sustained fire paths behave correctly.

## Problem

Vanilla bot shoot flow queues one weapon action input per frame through `bt_bot_shoot_action._fire`, but `BotUnitInput._input` never keeps `action_one_hold` alive across frames for ranged sustained-fire weapons. Result: bots tap-fire weapons that humans stream or hose.

This breaks two distinct classes:

1. True stream/charge-stream weapons:
   - `flamer_p1_m1` secondary braced stream
   - `forcestaff_p2_m1` secondary flame stream
2. Full-auto sustained-fire weapons:
   - recon lasguns
   - infantry autoguns
   - braced autoguns
   - autopistol
   - dual autopistols
   - bolter
   - Ogryn heavy stubbers
   - Ogryn ripperguns secondary braced full-auto mode

## Scope

### Included weapon templates

- `flamer_p1_m1`
- `forcestaff_p2_m1`
- `lasgun_p3_m1`
- `lasgun_p3_m2`
- `lasgun_p3_m3`
- `autogun_p1_m1`
- `autogun_p1_m2`
- `autogun_p1_m3`
- `autogun_p2_m1`
- `autogun_p2_m2`
- `autogun_p2_m3`
- `autopistol_p1_m1`
- `dual_autopistols_p1_m1`
- `bolter_p1_m2`
- `ogryn_heavystubber_p1_m1`
- `ogryn_heavystubber_p1_m2`
- `ogryn_heavystubber_p1_m3`
- `ogryn_heavystubber_p2_m1`
- `ogryn_heavystubber_p2_m2`
- `ogryn_heavystubber_p2_m3`
- `ogryn_rippergun_p1_m1`
- `ogryn_rippergun_p1_m2`

### Explicit exclusions

- Plasma guns
- Semi-auto lasguns and other non-full-auto tap weapons
- Shotguns, thumpers, rumblers
- Non-Purgatus force staffs
- Any target-persistence logic beyond current target-selection behavior
- Any new ADS / brace / hipfire decision rules (`#41`)

## Design

### Module

Add new module: `scripts/mods/BetterBots/sustained_fire.lua`

Responsibilities:

- detect whether a queued weapon action input maps to a sustained raw hold path
- track per-unit active sustained-fire state
- inject matching raw hold input during `BotUnitInput._update_actions`
- clear sustained-fire state on release, weapon switch, reload, unwield, invalid action, or explicit stop conditions

This keeps sustained-fire state isolated from `weapon_action.lua`, which already owns unrelated queue translation and diagnostics.

### Detection model

Detection is template-driven and narrow.

For each currently wielded ranged template, resolve whether the queued action input corresponds to a sustained path. Supported patterns:

1. **Held primary fire**
   - action input sequence starts `action_one_hold = true`
   - example: recon lasguns, heavy stubbers, bolter hipfire
2. **Held secondary stream**
   - action input ultimately enters a sustained action whose raw input must remain held
   - example: flamer `shoot_braced`, Purgatus `trigger_charge_flame`, rippergun braced fire

The module should not infer sustained behavior from vibes like weapon family names alone. It may use an allowlist of supported templates, but actual hold input mapping must come from live weapon template action data.

### Runtime behavior

When BetterBots queues a weapon action input that resolves to a supported sustained-fire path:

1. store per-unit sustained-fire state:
   - weapon template name
   - queued action input
   - raw hold input to maintain (`action_one_hold`)
   - optional paired release input if needed for that weapon path
2. on subsequent `BotUnitInput._update_actions` calls:
   - inject `input.action_one_hold = true`
3. stop injecting when:
   - bot leaves firing state
   - another weapon action supersedes it (`reload`, `wield`, `vent`, etc.)
   - weapon template changes
   - explicit release path is queued
   - tracked state is invalid or stale

### Interaction with `#41`

`#87` does not choose whether a bot should hipfire, ADS, or brace.

Instead:

- existing `attack_meta_data` continues to choose the action input
- future `#41` may change which fire path gets chosen
- `#87` simply makes any already-chosen sustained path hold correctly

This keeps both issues composable:

- `#87` fixes execution
- `#41` fixes path selection

### Edge cases

#### Bolter

Bolter primary is declared `full_auto`. It should be included in `#87`, but only on whatever path current metadata selected. No special ADS policy here.

#### Ripperguns

Ripperguns are mixed-mode:

- hipfire primary is burst
- braced secondary is sustained full-auto

`#87` should only sustain the braced path. Hipfire burst stays untouched.

#### Purgatus

Purgatus does not use generic `shoot_pressed` full-auto semantics. Its sustained path is `trigger_charge_flame` -> `action_charge_flame`. The module must support this explicitly rather than pretending it is just another full-auto gun.

## Hook points

1. `PlayerUnitActionInputExtension:bot_queue_action_input`
   - observe weapon action inputs as they are queued
   - arm or clear sustained-fire state
2. `BotUnitInput._update_actions`
   - inject raw hold state each frame while sustained-fire state is active

No behavior-tree hook is required for MVP.

## Logging

Permanent debug logging required. Log only meaningful state transitions, not every held frame.

Keys:

- `sustained_fire_arm:<unit>`
- `sustained_fire_hold:<unit>:<template>`
- `sustained_fire_clear:<unit>`
- `sustained_fire_skip:<unit>:<reason>`

Log payload should identify:

- bot slot / unit
- weapon template
- queued action input
- sustained mode chosen
- clear reason

`hold` log should be deduped or one-shot per armed sustained window, not emitted every frame.

## Tests

### New spec

Add `tests/sustained_fire_spec.lua`

Cover:

1. arm sustained state for full-auto held primary weapon
2. arm sustained state for flamer / Purgatus stream path
3. rippergun burst hipfire does not arm sustained state
4. rippergun braced full-auto does arm sustained state
5. `BotUnitInput._update_actions` injects `action_one_hold`
6. reload / wield / explicit stop clears sustained state
7. template change clears stale sustained state

### Existing spec extension

Extend `tests/weapon_action_spec.lua` only if queue-observation glue stays there. If all tracking lives in new module, keep tests in the new spec file and only add light startup regression coverage if needed.

## Docs to update

- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- `docs/bot/input-system.md`
- `docs/bot/vanilla-capabilities.md`
- `README.md`
- `AGENTS.md`

Update test/module count claims if a new module and spec file are added.

## Acceptance criteria

1. Supported sustained-fire templates stop tap-firing and maintain held raw input while their sustained fire path is active.
2. Bots do not start sustaining unsupported tap/burst paths.
3. `#87` does not change ADS-vs-hipfire selection policy; it only executes the chosen sustained path correctly.
