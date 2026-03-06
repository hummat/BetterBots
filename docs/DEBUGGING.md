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
| `charge consumed` | Ability charge was spent (confirmed activation) |
| `one-shot context dump` | First-time context dump for a template (debug-only) |
| `fallback item queued` | Tier 3 item-ability input sent |
| `fallback item blocked` | Tier 3 sequence failed (timeout, drift, etc.) |

**Useful grep recipes:**
```bash
LOG_DIR="/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"
LATEST=$(ls -1t "$LOG_DIR" | head -n 1)

# All BetterBots output (excluding load messages)
rg "BetterBots DEBUG:" "$LOG_DIR/$LATEST" | grep -v "patch\|logging\|loaded\|metadata\|GameplayState\|condition"

# Only combat activity (excludes nearby=0 idle traces)
rg "BetterBots DEBUG:" "$LOG_DIR/$LATEST" | grep -v "nearby=0\|patch\|logging\|loaded\|metadata\|GameplayState\|condition"

# Activations only
rg "fallback queued|charge consumed" "$LOG_DIR/$LATEST"

# Errors only
rg "Script Error|Lua Stack" "$LOG_DIR/$LATEST"
```

**Common mistake:** Do NOT grep for `"decision:"` or `"-> true"` — those patterns don't exist in the log. The actual format is `"fallback queued/held/blocked"` with rule names inline.

## Current BetterBots debug pattern

```lua
-- Throttled logging gated by mod setting
_debug_log(key, fixed_t, message, min_interval_s)
```

- Gated by `enable_debug_logs` mod setting (checkbox in DMF options)
- Throttled to 2s per unique key (avoids spam)
- Outputs to chat via `mod:echo("BetterBots DEBUG: " .. message)`

### Runtime commands in BetterBots

These are implemented and intended for targeted diagnostics, not constant spam.

1. `/bb_state`
   - Per-bot one-line state snapshot: current ability/template, charges/cooldown, `can_use`, active flag, wielded slot/template, fallback stage, retry timer, last charge age.
   - Use this first when something looks off.
2. `/bb_decide`
   - Evaluates current heuristic decision (`true/false`) and rule for each alive bot without queuing inputs.
   - Best for threshold tuning or "why didn't it cast?" questions.
   - Do **not** run after every successful cast; run around suspected misses or surprising behavior.
3. `/bb_brain`
   - Dumps deeper bot snapshot via `mod:dump()` (context + selected perception + fallback state).
   - Use only when `/bb_state` + logs are insufficient.

### Practical debug workflow

1. Observe behavior in mission.
2. If behavior looks correct, continue without commands.
3. If behavior looks wrong, run `/bb_state`.
4. If decision logic is unclear, run `/bb_decide` once around the event.
5. If still unclear, run `/bb_brain` once and inspect the dump.
6. Correlate with log lines (`fallback held/queued`, `charge consumed`, `invalid action_input`).

## Automated testing

### What's testable outside the game

The sub-module split (heuristics.lua, meta_data.lua, etc.) created clean test seams. The 13 `_can_activate_*` heuristic functions are **pure functions** — they take a context table and return `(bool, string)` with zero engine dependencies. The `evaluate_heuristic(template_name, context, opts)` public API exposes them for testing without the ugly internal 10-param dispatch signature.

### Test structure

```
tests/
  test_helper.lua           # make_context(), mock factories, engine stubs
  heuristics_spec.lua       # 80 tests: all 13 heuristic functions
  meta_data_spec.lua        # 7 tests: injection, overrides, idempotency
  resolve_decision_spec.lua # 8 tests: centralized nil→fallback paths
```

### Running tests

```bash
make test      # runs busted (auto-detected)
make check     # runs format + lint + lsp + test (full quality gate)
```

Tests are enforced by CI — `make check` depends on `test`, and CI installs busted via luarocks.

### Engine stubs

Phase 1 tests need no engine stubs for the pure heuristic functions. The `resolve_decision` tests use a minimal `ScriptUnit` stub (returns nil for all extensions, so `build_context` produces default zeros). See `test_helper.setup_engine_stubs()`.

## What CANNOT be tested outside the game

- Ability actually firing (engine input queue → ActionInputParser → ability system)
- Timing behavior (hold durations, frame-dependent sequences)
- Tier 3 item-ability state machine (weapon extension state, action transitions)
- BT node priority evaluation (full behavior tree context)
- Multiplayer state (not applicable — Solo Play only)

For these, use the existing manual verification workflow: launch game → observe → check logs → update `docs/VALIDATION_TRACKER.md`.

## Fatshark's Testify framework

Darktide has a built-in coroutine-based test framework (`scripts/foundation/utilities/testify.lua`) with bot-specific helpers (`bot_manager_testify.lua`). Features: async test execution, request/response pattern, `TestifyExpect` assertions.

**Not accessible to modders** — requires `GameParameters.testify` launch flag and an external test runner that Fatshark hasn't published. But the architecture (coroutine-based, polling between frames) could be replicated within a mod for integration tests.
