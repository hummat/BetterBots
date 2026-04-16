# Debugging and Testing

## Debug tools available

### DMF built-in (already available)

| Tool | Usage | Notes |
|------|-------|-------|
| `mod:echo(msg, ...)` | Print to chat + log file | What we use now. Configurable output modes (0-7). |
| `mod:error(msg, ...)` | Red alert + log | For serious errors. Plays notification sound. |
| `mod:warning(msg, ...)` | Warning level | For unexpected but non-fatal conditions. |
| `mod:debug(msg, ...)` | Debug level | Disabled by default in DMF. We use our own `_debug_log()` instead. |
| `mod:dump(table, name, depth)` | Dump table to log | Recursively prints table with depth limit. Handles circular refs. |
| `mod:dtf(table, name, depth)` | Dump table to JSON file | Exports to `./dump/table_name.json`. Alias: `mod:dump_to_file()`. |
| `mod:pcall(func, ...)` | Safe call with stack trace | Wraps in `xpcall` + `Script.callstack()`. Errors logged, no crash. |
| `mod:command(name, desc, func)` | Register `/name` chat command | Runtime debugging commands. Per-mod namespace. |
| `mod:persistent_table(id, default)` | Table survives hot reload | For debug state across `Ctrl+Shift+R` reloads. |

### Community tools

| Tool | What it does | Install |
|------|-------------|---------|
| **Modding Tools** (Nexus #312) | Table inspector, variable watcher, enhanced console | Recommended for development |
| **Power DI** (Nexus #281) | Data collection framework, auto-saves to disk | For statistical analysis of bot behavior over time |

### Log file workflow

**Location (Linux/Proton):**
```
/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/
```

**Real-time monitoring:**
```bash
tail -f "<path>/console_logs/console-*.log" | grep --line-buffered "BetterBots\|Script Error\|Lua Stack"
```

**Key log markers to grep:**
- `[MOD][BetterBots]` — our mod's output
- `<<Script Error>>` — Lua errors
- `<<Lua Stack>>` — stack traces
- `<<Crash>>` — engine crashes

**BetterBots-specific log patterns (for grep/rg):**

| Pattern | What it means |
|---------|---------------|
| `fallback queued` | Ability input was sent to the action queue (activation attempt) |
| `fallback held` | Heuristic decided NOT to activate (with rule name + nearby count) |
| `fallback blocked` | Ability on cooldown or action_input invalid (post-activation spam) |
| `blocked lossy network-sync profile overwrite` | `BotPlayer.set_profile` one-shot guard blocked the lossy 1.11+ sync overwrite for a resolved bot profile (#65) |
| `allowed profile update` | `BotPlayer.set_profile` hook passed a later legitimate profile update through after the one-shot guard |
| `charge consumed` | Ability charge was spent (confirmed activation) |
| `post-charge grace started` | Engagement leash recorded a movement-ability charge and started the temporary grace window (#47) |
| `one-shot context dump` | First-time context dump for a template (debug-only) |
| `fallback item queued` | Tier 3 item-ability input sent |
| `fallback item blocked` | Tier 3 sequence failed (timeout, drift, etc.) |
| `unsupported grenade template` | Grenade/blitz heuristic approved a template with no mapped throw profile |
| `patched poxburster breed` | Poxburster `not_bot_target` flag removed (#34) |
| `suppressed poxburster target_enemy (` | Bot cleared `target_enemy` when a poxburster was unsafe to shoot (#34) |
| `suppressed poxburster opportunity_target_enemy (` / `suppressed poxburster urgent_target_enemy (` / `suppressed poxburster priority_target_enemy (` | Bot cleared unsafe poxbursters from the secondary perception slots (#34) |
| `pushing poxburster (bypassed outnumbered gate)` | Bot forced the melee push path against a poxburster; key is per-bot via `scratchpad.unit` to avoid throttle collisions (#54) |
| `injected default bot_gestalts` | T5/T6 bot received killshot/linesman gestalts (#35) |
| `bot ADS confirmed (ranged_gestalt=` | Bot entered aim-down-sights with injected gestalt (#35) |
| `bot weapon: bot=` | Template-tagged queued weapon input for `#43` diagnosis; includes bot slot, wielded slot, weapon template, warp template, action, raw_input |
| `stream action queued for` | Direct confirmation that a stream-specific queue input (`shoot_braced`, `trigger_charge_flame`, etc.) actually reached `bot_queue_action_input` successfully (#87) |
| `patched opportunity reaction times` | Human-likeness timing patch applied live (#44) |
| `HumanLikeness: BotSettings.opportunity_target_reaction_times is nil or missing .normal` | Human-likeness timing patch could not bind because the engine settings shape changed |
| `leash scaled` | Human-likeness pressure leash scaling fired in combat (#44) |
| `type flip ` | Target-type hysteresis allowed a real melee/ranged transition at the perception/math layer (#90) |
| `type hold ` | Target-type hysteresis actively suppressed a raw type flip at the perception/math layer (#90) |
| `suppressed opposite-type switch ` | BT-side debounce suppressed an immediate melee↔ranged reswitch after `wrong_slot_for_target_type` fired (#90) |
| `weakspot aim selected` | Bot actually used the weakspot head/spine aim path at runtime (#91) |
| `shoot scratchpad normalization skipped` | Bot shoot-action enter hook could not see `unit_data_system` or `visual_loadout_system`; #43 diagnostics are incomplete for that unit |
| `shoot scratchpad normalization skipped for` | One-shot warning counterpart to the debug line above; emitted even with debug logs off so operators can still see why `#43` diagnostics were incomplete |
| `ammo utility unavailable; dead-zone ranged fire detection disabled` | `scripts/utilities/ammo` failed to load, so the dead-zone ranged-fire confirmation log for `#51` is unavailable in this session |
| `ammo pickup success` | Actual pickup interaction completed and bot ammo reserve increased; stronger than `ammo pickup permitted` |
| `grenade pickup permitted: all eligible humans above reserve` | BetterBots reserved a world grenade pickup for the bot because no eligible human grenade user was below reserve; one-shot per bot+pickup reservation episode |
| `grenade pickup bound into ammo slot` | BetterBots attached the reserved world grenade pickup to the ammo-pickup fields so vanilla interaction code can collect it; one-shot per bot+pickup reservation episode |
| `grenade pickup deferred to human reserve` | Bot yielded a nearby world grenade pickup because at least one eligible human grenade user was below reserve; one-shot per bot+pickup defer episode |
| `grenade pickup skipped: ability does not use grenade pickups` | Equipped blitz replenishes via cooldown/passive logic instead of world grenade pickups; one-shot per bot+equipped ability state |
| `grenade pickup skipped: cooldown-based blitz` | Blitz has no grenade charges at all, so world grenade pickup logic does not apply; one-shot per bot+equipped ability state |
| `grenade pickup skipped: no ability extension` | Grenade refill logic could not resolve the bot's `ability_system`; grenade reserve policy did not run |
| `ammo policy skipped: no pickup_component` | `_update_ammo` ran on a bot without a pickup component; ammo/grenade pickup policy did not run for that tick |
| `grenade pickup success` | Actual pickup interaction completed and bot grenade charges increased |
| `blackboard utility unavailable; mule pickup destination refresh skipped` | Mule live-destination refresh could not load the blackboard helper; reservation metadata patching still ran, but destination refresh became a no-op for that session |
| `sprint START/STOP` | Bot sprint state change — only logged for catch_up, ally_rescue, daemonhost_nearby (#36) |
| `skipped ping for <target> (reason: recent_companion_tag)` | Generic pinging backed off because an Arbites bot had just issued a mastiff smart-tag on the same target; use this when checking remaining tag-spam reports |
| `melee suppressed (daemonhost nearby)` / `ranged suppressed (daemonhost nearby)` | Close-range daemonhost safety gate fired; bot was inside the tight daemonhost combat radius and refused the attack (`#17`) |
| `melee suppressed (target is dormant daemonhost)` / `ranged suppressed (target is dormant daemonhost)` | Non-aggroed daemonhost target suppression fired outside the proximity gate; stage-aware when daemonhost `stage` is available, otherwise falls back to `aggro_state` (`#17`) |
| `skipped ping for chaos_daemonhost (reason: dormant_daemonhost)` / `skipped companion tag for chaos_daemonhost (reason: dormant_daemonhost)` / `skipped player-tag boost for chaos_daemonhost (reason: dormant_daemonhost)` | Stage-aware daemonhost avoidance suppressed pinging, mastiff smart-tagging, or human-tag score boosts on a non-aggroed daemonhost (#17) |
| `shield (` / `escort (` | Ally detected in objective interaction — the full line is `<profile> (<interaction_type>) dist=<N>`. Key: `interaction_scan:<unit>`, 5s throttle (#37) |
| `revive candidate observed: <ability> (template=<template>, need_type=<type>)` | Bot selected a rescue destination while carrying a defensive revive ability, before `BtBotInteractAction.enter`. Use this to tell selector/path misses from interact-hook misses. Key: `revive_candidate:<ability>:<unit>` (#7) |
| `revive ability queued: <ability> (interaction=<type>, enemies=<N>)` | Bot fired a defensive ability before starting a rescue interaction. Key: `revive_ability:<ability>:<unit>` (#7) |
| `revive ability skipped (` | Rescue-interaction diagnostics. The throttle key encodes the reason, but the emitted line is always a human-readable `[Bot <slot>] revive ability skipped (...)`. |
| `cleared stale mule pickup ref` | Deleted mule/grimoire pickup ref was sanitized without crashing; source path in message shows which cache/blackboard field was cleaned |

**Preferred: use `bb-log`** (project root):
```bash
bb-log summary        # one-shot overview: counts + top rules + top holds
bb-log activations    # raw fallback queued + charge consumed lines
bb-log rules          # activation counts by rule + consume counts by ability
bb-log holds          # non-idle hold rules (nearby > 0)
bb-log errors         # Script Error / Lua Stack / Crash lines
bb-log tail           # real-time monitoring (grep BetterBots + errors)
bb-log list           # show 10 most recent log files with indices
bb-log raw <pattern>  # arbitrary rg pattern against log
bb-log <cmd> 1        # use second-latest log (0=latest, default)
bb-log events summary # JSONL: event counts + approval rate + per-bot consumes
bb-log events rules   # JSONL: true/false decision counts by ability+rule
bb-log events trace N # JSONL: timeline for bot slot N
bb-log events holds   # JSONL: false decision distribution
bb-log events items   # JSONL: item stage transitions + blocks
bb-log events raw 'jq-filter'  # JSONL: raw jq passthrough
```

**Manual grep recipes** (if bb-log unavailable):
```bash
LOG_DIR="/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"
LATEST=$(ls -1t "$LOG_DIR"/console-*.log | head -n 1)

# Activations only
rg "fallback queued|charge consumed" "$LATEST"

# Active holds (combat, not idle)
rg "fallback held" "$LATEST" | grep -v "nearby=0)"

# Errors only
rg "Script Error|Lua Stack" "$LATEST"
```

**Common mistakes:**
- Do **not** grep `_debug_log` throttle keys like `target_type_flip:<unit>` or `human_likeness_patch`. `_debug_log` prints only the human-readable message, not the key.
- Do **not** grep for `"decision:"` — that pattern doesn't exist in the log. The `"-> true"` pattern does appear in debug decision lines (e.g. `decision veteran_combat_ability -> true (rule=...)`). For activation evidence, prefer `"fallback queued"` / `"charge consumed"` which are unambiguous.

## Current BetterBots debug pattern

```lua
-- Throttled logging gated by mod setting
_debug_log(key, fixed_t, message, min_interval_s, level)
```

- Gated by `enable_debug_logs` mod setting (dropdown: Off / Info / Debug / Trace)
- Omitted `level` defaults to `debug`
- Throttled to 2s per unique key (avoids spam)
- Outputs to chat via `mod:echo("BetterBots DEBUG: " .. message)`

### Runtime commands in BetterBots

These are implemented and intended for targeted diagnostics, not constant spam.

1. `/bb_state`
   - Shows each bot's current ability, cooldown, and fallback state on one line.
   - Includes current template, charges, cooldown, active flag, wielded slot, fallback stage, retry timer, and last charge age.
   - Use this first when something looks off.
2. `/bb_decide`
   - Shows whether each alive bot would use its ability right now, without actually triggering it.
   - Includes the current decision (`true/false`) and rule for each bot.
   - Best for threshold tuning or "why didn't it cast?" questions.
   - Do **not** run after every successful cast; run around suspected misses or surprising behavior.
3. `/bb_brain`
   - Writes a deeper bot snapshot to the log via `mod:dump()` (context + selected perception + fallback state).
   - Use only when `/bb_state` + logs are insufficient.
4. `/bb_perf`
   - Shows and resets the current runtime timing window when `Performance timings` is on.
   - Reports total `µs/bot/frame` plus a per-hook breakdown for instrumented BetterBots callbacks.
   - `GameplayStateRun` exit also auto-emits the same report to the console log with `bb-perf:auto:` prefixes, but only when the recording window contains at least one sampled bot frame. Hub-only `GameplayStateRun` transitions are intentionally suppressed so starting a mission does not produce meaningless `0 bot frames` dumps.
   - `ability_queue` now exposes breakdown-only rows for `item_fallback`, `template_setup`, `input_validation`, `decision`, and `queue`; `grenade_fallback` now exposes `stage_machine`, `profile_resolution`, and `launch` in addition to the existing `build_context` and `heuristic` rows.
   - `grenade_fallback` has two breakdown-only sub-tags that partition its idle-path cost: `grenade_fallback.build_context` (the `heuristics.build_context` call in `grenade_fallback.lua`) and `grenade_fallback.heuristic` (the subsequent `evaluate_grenade_heuristic` call). They appear as rows in the tag breakdown but do not contribute to the headline `µs/bot/frame` total because the parent `grenade_fallback` timer already includes them.
   - `target_type_hysteresis.post_process` now appears as a breakdown-only row for the post-vanilla melee/ranged stabilization pass.
5. `/bb_reset`
   - Resets all BetterBots settings to their defaults and saves them when the DMF save hook is available.
   - Each `mod:set` is `pcall`-wrapped, so a failure on one setting does not abort the loop. On any failure the echo reads `"BetterBots: reset partially failed: <id (err), ...>"`; clean success echoes `"BetterBots: all settings reset to defaults"`.
   - Reopen the mod settings menu if the UI does not immediately redraw after the reset.

### Practical debug workflow

1. Observe behavior in mission.
2. If behavior looks correct, continue without commands.
3. If behavior looks wrong, run `/bb_state`.
4. If decision logic is unclear, run `/bb_decide` once around the event.
5. If still unclear, run `/bb_brain` once and inspect the dump.
6. Correlate with log lines (`fallback held/queued`, `charge consumed`, `invalid action_input`).

### Grenade regression shortcut

For item-based grenade regressions, check the grenade state-machine phases before blaming aim, gravity, or heuristics:

1. `grenade queued wield for <grenade>` appears:
   - sequence started, but nothing is proven yet.
2. `grenade wield confirmed, waiting for aim` appears:
   - grenade slot swap succeeded; only **after this** is it reasonable to suspect aim/ballistic logic.
3. `grenade queued <aim_input>` / `grenade releasing toward ...` appears:
   - aim/release phase actually ran.
4. `grenade charge consumed for <grenade>` appears:
   - authoritative success for item-based grenades.

If you instead see repeated `grenade queued wield for <grenade>` plus `blocked foreign weapon action grenade_ability while keeping <grenade> wield`, with no `grenade wield confirmed, waiting for aim`, the blocker is killing the initial `grenade_ability` queue during the grenade `wield` stage. That is a sequence-allowlist bug, not an aim bug.

### Reading context dumps (deep verification)

When debug logging is enabled, BetterBots emits a **one-shot context dump** the first time each ability template is activated in a session. These are written via `mod:dump()` (table → log) and contain the full decision context at the moment of activation.

**What to look for in a dump:**

| Field | Meaning | Trust level |
|-------|---------|-------------|
| `rule` | Which heuristic branch fired (e.g. `ogryn_gunlugger_high_threat`) | High — directly from code |
| `activation_input` | The action_input queued (e.g. `stance_pressed`) | High |
| `challenge_rating_sum` | Aggregate threat score from perception | High — use for tuning |
| `num_nearby` / `elite_count` / `special_count` | Threat composition | High |
| `target_enemy_distance` | Distance to selected target | High |
| `health_pct` / `toughness_pct` / `peril_pct` | Bot survival state | High |
| `target_enemy` | Breed name of selected target | **Medium** — can disagree with aggregates (see below) |
| `target_enemy_type` | `melee` or `ranged` classification | **Medium** — same caveat |

**Perception field inconsistency:** `target_enemy` and `target_enemy_type` reflect the bot's *selected* target (single unit from the BT targeting system), while `challenge_rating_sum`, `num_nearby`, and type counts reflect the *broadphase proximity scan* (all enemies within range). These two sources can disagree — e.g. a poxwalker may be the selected target while the aggregate CR and type counts reflect a nearby Chaos Ogryn. When tuning heuristics, **trust the aggregate fields over the single-target label**.

**Verification workflow with dumps:**

1. Enable debug logging in mod settings.
2. Play through combat encounters.
3. After the session, grep for `one-shot context dump` to find dump entries.
4. For each dump, find the matching `fallback queued` (activation) and `charge consumed` (confirmation) lines nearby in the log.
5. Check whether the `rule` and context fields match what you'd expect for that combat situation.
6. If they don't match, the heuristic thresholds may need tuning — the dump gives you the exact values to adjust against.

## Automated testing

### What's testable outside the game

The sub-module split (`heuristics.lua` dispatcher, `heuristics_context.lua`, the career-specific `heuristics_*.lua` files, `meta_data.lua`, `event_log.lua`, etc.) created clean test seams. The 18 `_can_activate_*` heuristic functions (14 combat + 4 item) are **pure functions** — they take a context table and return `(bool, string)` with zero engine dependencies. The `evaluate_heuristic(template_name, context, opts)` public API exposes them for testing without the ugly internal 10-param dispatch signature. The `event_log` module is independently testable (buffer, flush, lifecycle, false-decision compression).

### Test structure

```
tests/
  test_helper.lua           # make_context(), mock factories, engine stubs
  heuristics_spec.lua       # all 18 heuristic functions (14 combat + 4 item)
  meta_data_spec.lua        # injection, overrides, idempotency
  resolve_decision_spec.lua # centralized nil→fallback paths
  event_log_spec.lua        # buffer, flush, lifecycle, false-decision compression
  sprint_spec.lua           # sprint conditions + daemonhost safety
  target_selection_spec.lua # melee target distance penalty
```

### Running tests

```bash
make tool-info # shows the exact wrappers/binaries this repo will use
make test      # runs busted, lua-busted, or Arch's luarocks path
make check     # auto-formats, then runs lint + lsp + test + doc-check
make check-ci  # non-mutating CI gate: format-check + lint + lsp + test + doc-check
```

`make lint` uses the repo-local `bin/luacheck` wrapper. `make test` does not
depend on shell `PATH` mutation; it falls back to Arch's packaged luarocks
runner when `busted` is not installed globally.

Tests are enforced by CI — `make check-ci` depends on `test`, and CI installs
busted via luarocks.

### Engine stubs

Phase 1 tests need no engine stubs for the pure heuristic functions. The `resolve_decision` tests use a minimal `ScriptUnit` stub (returns nil for all extensions, so `build_context` produces default zeros). See `test_helper.setup_engine_stubs()`.

### Mock fidelity rule

`ScriptUnit.has_extension()` / `ScriptUnit.extension()` test doubles must match the real engine extension class for the unit type under test. Do not give minion/enemy units player-only methods just because the code path is convenient to test.

Verified from decompiled source:

| Extension system | Player API used by BetterBots | Minion API used by BetterBots | Gotcha |
|---|---|---|---|
| `unit_data_system` | `PlayerUnitDataExtension:read_component()` | `MinionUnitDataExtension:breed()`, `faction_name()`, `is_companion()`, `breed_name()`, `breed_size_variation()` | Minions do **not** have `read_component()` |
| `locomotion_system` | `PlayerUnitLocomotionExtension` (player movement internals) | `MinionLocomotionExtension:current_velocity()` | Prefer the exact method the production code calls; do not invent shared component access |

Practical rule:

- Player/bot self units: use player-style `unit_data_system` mocks with `read_component()`.
- Enemy/minion targets: use minion-style `unit_data_system` mocks with `breed()` and no `read_component()`.
- If a code path can handle both, test both paths explicitly.
- Prefer shared builders in `tests/test_helper.lua` over ad-hoc extension tables so impossible method combinations stay impossible in tests too.
- `scripts/doc-check.sh` now fails CI if audited `ScriptUnit` extension families reappear as raw table literals in specs.
- Full audited surface and source-line evidence live in `docs/dev/mock-api-audit.md`.

## What CANNOT be tested outside the game

- Ability actually firing (engine input queue → ActionInputParser → ability system)
- Timing behavior (hold durations, frame-dependent sequences)
- Tier 3 item-ability state machine (weapon extension state, action transitions)
- BT node priority evaluation (full behavior tree context)
- Multiplayer state (not applicable — Solo Play only)

For these, use the existing manual verification workflow: launch game → observe → check logs → update `docs/dev/validation-tracker.md`.

## Fatshark's Testify framework

Darktide has a built-in coroutine-based test framework (`scripts/foundation/utilities/testify.lua`) with bot-specific helpers (`bot_manager_testify.lua`). Features: async test execution, request/response pattern, `TestifyExpect` assertions.

**Not accessible to modders** — requires `GameParameters.testify` launch flag and an external test runner that Fatshark hasn't published. But the architecture (coroutine-based, polling between frames) could be replicated within a mod for integration tests.
