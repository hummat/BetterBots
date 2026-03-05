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

## Current BetterBots debug pattern

```lua
-- Throttled logging gated by mod setting
_debug_log(key, fixed_t, message, min_interval_s)
```

- Gated by `enable_debug_logs` mod setting (checkbox in DMF options)
- Throttled to 2s per unique key (avoids spam)
- Outputs to chat via `mod:echo("BetterBots DEBUG: " .. message)`

### Improvements to add

1. **`mod:dump()` for table inspection** — dump ability templates, blackboard state, perception data
2. **`mod:pcall()` around risky hooks** — get stack traces instead of crashes
3. **Chat commands for runtime debugging:**
   - `/bb_state` — dump current ability state for all bots
   - `/bb_force <template>` — force-activate a specific ability
   - `/bb_cooldowns` — show all bot ability cooldowns
   - `/bb_perception` — dump perception data for nearest bot
4. **`tail -f` console log** in a terminal alongside the game

## Automated testing

### What's testable outside the game

The heuristic functions (`_can_activate_zealot_dash`, `_can_activate_ogryn_charge`, etc.) are **pure functions** that take a context table and return a boolean + rule name. They have zero engine dependencies. These can be extracted and unit tested.

### Architecture: extract to `heuristics.lua`

```
scripts/mods/BetterBots/
  BetterBots.lua           # Hooks, engine integration, state machines
  heuristics.lua           # NEW: pure decision functions + data tables
  BetterBots_data.lua
  BetterBots_localization.lua

tests/
  heuristics_spec.lua      # Decision logic tests
  meta_data_spec.lua       # Table structure tests
  helpers/
    mock_env.lua           # Shared DMF/engine mocks
```

Move to `heuristics.lua`:
- All `_can_activate_*` functions (13 functions, each with 3-7 branches)
- `TIER2_META_DATA` table
- `META_DATA_OVERRIDES` table
- `SUPER_ARMOR_BREEDS` table
- `_is_tagged()`, `_resolve_veteran_class_tag()`
- `TEMPLATE_HEURISTICS` dispatch table

### Test framework: busted

```lua
-- tests/heuristics_spec.lua
local heuristics = require("heuristics")

describe("zealot_dash", function()
    it("blocks when no target", function()
        local ctx = { target_enemy = nil, num_nearby = 5, toughness_pct = 0.5 }
        local result, rule = heuristics.can_activate_zealot_dash(ctx)
        assert.is_false(result)
        assert.equals("zealot_dash_block_no_target", rule)
    end)

    it("activates for priority target at range", function()
        local ctx = {
            target_enemy = {},
            target_enemy_distance = 8,
            target_is_super_armor = false,
            priority_target_enemy = {},
            toughness_pct = 0.5,
            num_nearby = 2,
        }
        local result, rule = heuristics.can_activate_zealot_dash(ctx)
        assert.is_true(result)
    end)
end)
```

### What to test (priority order)

| Priority | What | Why |
|----------|------|-----|
| High | All 13 `_can_activate_*` functions | Each has 3-7 branches with numeric thresholds. Boundary-value testing catches off-by-one bugs. |
| High | `TIER2_META_DATA` completeness | Every template must have required fields. |
| Medium | `_inject_missing_ability_meta_data()` | Pass mock AbilityTemplates, verify mutations. |
| Medium | `_resolve_veteran_class_tag()` | Pattern matching with fallback chain. |
| Low | Item-ability state machine | Too coupled to engine. Test in-game only. |

### CI integration

```yaml
# .github/workflows/ci.yml (add to existing)
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: leafo/gh-actions-lua@v12
        with:
          luaVersion: "luajit-2.1"
      - uses: leafo/gh-actions-luarocks@v4
      - run: luarocks install busted
      - run: busted --output=utfTerminal
```

Use `luajit-2.1` to match Darktide's runtime. `make test` already detects busted — it just needs a `tests/` directory.

### `.busted` config

```lua
return {
    default = {
        lpath = "./scripts/mods/BetterBots/?.lua;./tests/helpers/?.lua",
        ROOT = { "tests" },
        pattern = "_spec",
        output = "utfTerminal",
    },
}
```

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
