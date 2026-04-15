# Grenade Ballistic Aim Design

Date: 2026-04-12
Issue: #93
Branch: `dev/v0.11.0`

## Goal

Fix BetterBots grenade/blitz aiming for gravity-affected manual-physics projectiles. Current `grenade_fallback._set_bot_aim()` points flat at `POSITION_LOOKUP[target]`, which means bots throw at feet with zero gravity compensation and zero target lead. At medium range this drops standard grenades short and makes zealot knives less accurate than they should be.

Scope is intentionally narrow: patch the BetterBots grenade fallback aim helper only. Do not change heuristics, queue timing, BT behavior, or unrelated projectile systems.

## Current Problem

`grenade_fallback.lua` currently does this:

1. resolve target unit
2. read `POSITION_LOOKUP[target]`
3. `bot_unit_input:set_aiming(true, false, false)`
4. `bot_unit_input:set_aim_position(aim_position)`

That is adequate for flat/true-flight/non-ballistic projectiles, but wrong for vanilla grenade locomotion templates that use manual physics with real gravity:

- standard grenade family: `gravity = 12.5`, `speed_initial = 15`, `speed_maximal = 30`
- Ogryn box/friend rock: manual physics with gravity 10.5 and high throw speeds
- zealot throwing knives: manual physics with `gravity = 17.5`, `initial_speed = 75`

Vanilla ranged bots already solve this in `BtBotShootAction._wanted_aim_rotation()` using `Trajectory.angle_to_hit_moving_target(...)` plus target-velocity lead. BetterBots grenade fallback should mirror that solver for the supported projectile families instead of using flat aim.

## Non-Goals

- No BT-layer changes
- No grenade heuristic changes
- No queue/state-machine refactor
- No per-template smart-target logic changes
- No support expansion for mines, whistle, smite, or chain lightning
- No attempt to generalize into a shared projectile helper module yet

## Supported vs Excluded Families

### Included in #93

Apply ballistic aim only to projectile families where BetterBots currently aims flat but the projectile follows a gravity arc:

- standard grenades using `ProjectileLocomotionTemplates.grenade`
- handleless grenades using grenade-style manual physics
- Ogryn grenade box / cluster / frag / friend rock
- zealot throwing knives

### Explicitly excluded

- `broker_missile`: near-flat (`gravity = 0.05`, `speed_initial = 76`), not worth touching in #93
- psyker throwing knives: true-flight, not flat ballistic arc
- `adamant_whistle`: ability target finder, not projectile arc math
- `psyker_smite`, `psyker_chain_lightning`: not ballistic throw arcs
- `adamant_shock_mine`: placement path, not throw arc

## Design

### 1. Keep patch local to `grenade_fallback.lua`

Do not add a new module. `#93` is a correction to the mod-owned grenade fallback path, so the fix belongs there.

Add local helpers inside `grenade_fallback.lua` to:

- resolve the equipped grenade weapon template
- resolve projectile locomotion/integrator data for the active grenade profile
- identify whether a projectile should use ballistic aim
- compute wanted aim rotation using vanilla-style trajectory solving

### 2. Introduce projectile-aware aim selection

Replace the current all-or-nothing flat aim helper with:

- ballistic solver path for supported gravity projectiles
- fallback flat aim path for unsupported or unavailable projectile data

Decision rule:

1. If no target unit, fail as today.
2. If no projectile template / locomotion data for current grenade, use flat aim.
3. If projectile is excluded (`broker_missile`, psyker knives, whistle path, etc.), use flat aim.
4. If projectile has supported manual-physics gravity data, compute rotation via trajectory solver and use rotation aiming.
5. If solver fails, log once and fall back to flat aim.

### 3. Reuse vanilla solver shape

Mirror the essential behavior of `BtBotShootAction._wanted_aim_rotation()`:

- target point = target world position for grenade fallback target
- get target velocity
- call `Trajectory.angle_to_hit_moving_target(current_position, target_position, projectile_speed, target_velocity, projectile_gravity, acceptable_accuracy, false)`
- build rotation from returned target position + launch angle

Use `bot_unit_input:set_aiming(true, false, true)` and `bot_unit_input:set_aim_rotation(wanted_rotation)` for the ballistic path.

Do not copy unrelated vanilla aim-speed smoothing or obstruction logic. Grenade fallback only needs the solved rotation.

### 4. Projectile parameter source

Projectile data must come from the equipped grenade weapon template, not hardcoded BetterBots tables.

For each supported grenade:

- read equipped grenade template / projectile template reference
- read locomotion template referenced by projectile template
- read trajectory/integrator fields needed for solving:
  - launch speed
  - gravity
  - locomotion state / family

Use template data robustly enough to support:

- standard grenade `throw`
- Ogryn heavier throws
- zealot knife spawn projectile values

If the template shape differs and cannot be resolved confidently, do not guess. Fall back to flat aim.

### 5. Target velocity source

Match vanilla source split:

- player targets: `unit_data_system` locomotion component velocity
- non-player targets: `locomotion_system:current_velocity()`
- otherwise zero vector

This keeps the solver honest for moving elites/specials without introducing a wider dependency surface.

### 6. Logging

Add narrow permanent debug logs:

- `grenade_aim_ballistic:<unit>` when ballistic rotation path is used
- `grenade_aim_flat_fallback:<unit>` when projectile path is unsupported/unavailable
- `grenade_aim_solver_fail:<unit>` when solver fails and flat fallback is used

These logs must stay cheap:

- no extra component reads unless debug enabled
- include unit discriminator in key
- log confirmation event, not every intermediate calculation

## Testing

Extend `tests/grenade_fallback_spec.lua`.

Required cases:

1. supported ballistic projectile uses `set_aim_rotation` with `use_rotation = true`
2. unsupported projectile falls back to `set_aim_position`
3. solver failure falls back to flat aim without aborting queue flow
4. zealot throwing knives are treated as supported ballistic projectiles
5. broker missile is treated as excluded / flat path

The tests should stay pure Lua by stubbing trajectory/projectile helpers rather than loading full engine projectile tables.

## Acceptance Criteria

1. Supported gravity-arc grenade fallback paths aim via solved rotation instead of flat position aim.
2. Unsupported or unresolvable projectile paths continue to work via flat fallback.
3. Zealot throwing knives are included; broker missile and psyker knives are not.
4. Existing grenade state machine timing/queue behavior is unchanged.
5. `make test` and `make doc-check` pass.

## Docs To Update

- `docs/classes/grenade-inventory.md`
- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`
- README / AGENTS parity only if module/test counts change

Also correct the stale grenade inventory claim that all knives are unaffected; zealot knives are affected and included in this fix.
