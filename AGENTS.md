# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Darktide Mod Framework (DMF) mod that makes bots use their combat abilities in Solo Play. The game has a complete bot ability activation system (behavior tree node + condition guard + action input queue), but Fatshark hardcoded a whitelist in `bt_bot_conditions.can_activate_ability` that only allows two abilities. This mod removes that gate and injects missing metadata so the existing infrastructure handles the rest.

## Deployment

The mod lives in `$GIT_ROOT/BetterBots/` and is symlinked into the Darktide mods directory:
```
mods/BetterBots -> $GIT_ROOT/BetterBots
```
Darktide install: `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/`

After changes, re-run `toggle_darktide_mods.bat` (Windows) or `handle_darktide_mods.sh` (Linux) in the game root to re-patch. Mods are disabled after every game update.

## Testing

**Automated** (outside the game):
- `make test` — 225 unit tests via busted (heuristics, meta_data, resolve_decision, event_log, sprint, melee_meta_data, ranged_meta_data)
- `make check` — full quality gate (format + lint + lsp + test)

**In-game** (manual verification):
1. Launch with SoloPlay + Tertium5/6 mods active
2. Check for `BetterBots loaded` in game chat
3. After mission: `bb-log summary` to verify activations and hold rules
4. See `docs/dev/validation-tracker.md` for structured run entries and the heuristic validation matrix

Hot-reload with `Ctrl+Shift+R` when dev mode is enabled in DMF settings.

## Debugging

See `docs/dev/debugging.md` for full debug tool reference. Key tools:
- **`bb-log`** (project root) — primary log analysis tool. Use `bb-log summary` for overview, `bb-log activations` for raw events, `bb-log rules` for counts, `bb-log events summary` for JSONL event analysis. **Always use this instead of raw rg/grep on log files.**
- `mod:echo(msg)` — print to chat + log (current approach)
- `mod:dump(table, name, depth)` — recursively dump tables to log
- `mod:dtf(table, name, depth)` — export table as JSON to `./dump/`
- `mod:pcall(func)` — safe call with stack trace via `Script.callstack()`
- `mod:command(name, desc, func)` — register `/name` chat commands for runtime debugging
- In-game: `/bb_state`, `/bb_decide`, `/bb_brain` for live bot diagnostics
- Hot-reload: `Ctrl+Shift+R` (requires DMF Developer Mode)
- Console logs: `tail -f` on `console_logs/console-*.log` — **read `docs/dev/debugging.md` for log patterns and grep recipes before searching logs** (the log format is non-obvious and easy to miss with wrong patterns)
- **Modding Tools** (Nexus #312): table inspector + variable watcher (recommended for development)

## Local static checks

Use project-local tooling configs before handing off changes:

- `make deps` → install git hooks (conventional commits)
- `make lint` → `luacheck` with `.luacheckrc`
- `make format-check` / `make format` → `stylua` with `.stylua.toml`
- `make lsp-check` → `lua-language-server --check` with `.luarc.json`
- `make doc-check` → verify doc claims against code (function counts, test counts, issue states)
- `make check` → runs all of the above
- `make package` → build Nexus-ready `BetterBots.zip`
- `make release VERSION=X.Y.Z` → check + package + tag + push + upload ZIP (CI also attaches ZIP)
  - **Post-release:** prepare a Nexus changelog entry (version + summary of user-facing changes) and add it via the Nexus "Add new changelog" form

Notes:

- `make test` auto-detects a busted runner (`busted`, `lua-busted`, or Arch's packaged luarocks path).
- `make test` is a no-op unless a `tests/` directory exists.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`, `revert`, `style`, `build`

Enforced by local `commit-msg` hook (install via `make deps`) and CI commit-lint on PRs.

## Branching workflow

### Single feature
1. `git checkout -b feat/<issue-number>-<short-name>` from `main`
2. Implement, commit, `make check`
3. Test in-game (new mission, not hot-reload)
4. Merge to `main`

### Batch testing (2–4 features)
In-game testing requires launching Darktide + Solo Play + running a mission (~5 min setup). When multiple features are ready, batch them into a single test session:

1. Implement each feature in its own `feat/*` branch off `main`
2. Create `dev/<batch-name>` from `main`
3. Merge each `feat/*` into `dev/<batch-name>`
4. Write a test checklist before testing (what to verify per feature)
5. Test `dev/<batch-name>` in one in-game session
6. If all pass: merge `dev/<batch-name>` to `main` — ships the exact tested tree
7. If one fails: revert the broken feature from `dev/*`, retest, then ship

Rules:
- Keep batches small (2–4 features). Larger batches lose causal traceability.
- Write the test checklist before coding, not after.
- Ship what you tested — never merge individual `feat/*` branches after testing the integration branch.
- `dev/*` branches are disposable — delete after merge to `main`.

### Branch naming
- `feat/<N>-<name>` — new features (N = GitHub issue number)
- `fix/<N>-<name>` — bug fixes
- `dev/<batch-name>` — disposable integration branch for batch testing
- `docs/<name>` — documentation only

## Architecture

### How vanilla bot abilities work (the call chain)

```
BotBehaviorExtension.update()
  → AiBrain → BT evaluates priority selector
    → can_activate_ability condition (bt_bot_conditions.lua)
      → BtBotActivateAbilityAction.enter/run()
        → action_input_extension:bot_queue_action_input(component, action_input, raw_input)
          → ActionInputParser drains queue next frame → ability fires
```

The BT already has nodes for `activate_combat_ability` and `activate_grenade_ability`. The ability system (`PlayerUnitAbilityExtension`) has zero `is_human_controlled` gates — once input is queued, abilities process identically for bots and humans.

### What this mod does

1. **Tier 1 (whitelist removal):** Templates that already have `ability_meta_data` — just need the `else return false` removed. These work end-to-end with no other changes.
2. **Tier 2 (meta_data injection):** Templates that exist but lack `ability_meta_data`. We inject it at load time (same pattern Tertium4Or5 uses for `attack_meta_data`).
3. **Condition hook:** Replaces `bt_bot_conditions.can_activate_ability` with per-template heuristics (18 functions in `heuristics.lua`). Each ability has specific activate/block conditions based on health, toughness, peril, enemy composition, distance, and ally state. Unknown templates fall back to `enemies_in_proximity() > 0`.

### Ability tiers

| Tier | Status | Examples | What's needed |
|------|--------|----------|---------------|
| 1 | Validated | Veteran Stance/Stealth, Psyker Stance, Ogryn Gunlugger, Arbites Stance | Whitelist removal only |
| 1 | Untested (DLC) | Broker Focus/Rage | Whitelist removal only — DLC-blocked for validation |
| 2 | Validated | Zealot Dash/Invisibility, Ogryn Charge/Taunt, Psyker Shout, Arbites Charge | Meta_data injection + whitelist removal |
| 3 | Validated | Zealot Relic, Psyker Force Field, Arbites Drone | Item-based fallback (wield/use/unwield sequence) |
| 3 | Blocked (DLC) | Hive Scum Stimm Field | Item-based, DLC-blocked for validation |
| 3 | Not addressed | All grenades, Psyker Smite/Assail/Chain Lightning | No `ability_template` field → needs different approach |

### Decompiled source repo (Aussiemon/Darktide-Source-Code)

Local clone: `../Darktide-Source-Code/`

**Repo structure:**
- `scripts/extension_systems/` — runtime systems (ability, behavior, weapon, input, UI)
- `scripts/managers/` — orchestration and stateful managers
- `scripts/settings/` — data-driven templates and tuning (ability templates, breed actions, weapons)
- `scripts/tests/` and `*_testify.lua` — in-engine test scenarios (Testify framework)
- `content/` — game assets and level content
- `core/` — shared engine/core Lua

**Lua style conventions (match when reading/referencing):**
- Tabs for indentation, `snake_case` for filenames/locals, `PascalCase` for class/module names
- `local ... = require(...)` blocks at file top
- Method pattern: `Class.method = function (self, ...) ... end`

**Key files for bot abilities:**
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` — the whitelist (lines 59-100)
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua` — BT leaf that queues ability input
- `scripts/settings/breed/breed_actions/bot_actions.lua` — action_data for BT nodes
- `scripts/extension_systems/ability/player_unit_ability_extension.lua` — ability system internals
- `scripts/extension_systems/behavior/trees/bot/bot_behavior_tree.lua` — BT structure
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua` — melee action (falls back to light-only when `attack_meta_data` missing)
- `scripts/extension_systems/input/bot_unit_input.lua` — bot input class (`get()` method)
- `scripts/extension_systems/input/player_unit_input_extension.lua` — switches between human/bot input
- `scripts/extension_systems/behavior/bot_behavior_extension.lua` — brain update tick (gated on `is_human_controlled`)

## DMF Conventions

- `mod:hook(obj, method, handler)` — intercept function, handler receives `(func, self, ...)`, must call `func` to chain
- `mod:hook_safe(obj, method, handler)` — callback after original, no control over execution
- `mod:hook_origin(obj, method, handler)` — full replacement, one per function
- For condition tables loaded via `require()`, directly replace the function on the table (not via `mod:hook`)
- `mod:echo(msg)` — print to game chat (useful for debug)
- `require()` returns cached singletons — mutating the returned table affects the game globally

## MANDATORY: Read relevant docs before acting, update them after

**Read first:** Before performing ANY task in this project — implementation, debugging, log analysis, validation, planning — check the doc index below and read the relevant docs first. Do not guess from memory. The docs are the ground truth for game internals, log formats, mod conventions, and validation status. This applies to all tasks, not just code changes.

**GitHub issues:** When asked to work on a GitHub issue (e.g. "implement #X", "fix #X"), always read the full issue including ALL comments before starting — not just the issue body. Comments accumulate design decisions, code review feedback, and implementation notes over time.

**Update after:** When your code change affects a documented fact, update the docs in the same commit. `make doc-check` catches stale function counts and test counts automatically, but semantic claims (tier status, capability descriptions, template names) require manual updates. Common triggers:

| You just... | Update |
|---|---|
| Added/removed a `_can_activate_*` function | Function count in this file + `docs/dev/debugging.md` |
| Added/removed/moved tests | Per-file test counts in this file + `docs/dev/debugging.md` |
| Changed tier status or validation result | Tier table in this file + `docs/dev/validation-tracker.md` + `docs/dev/status.md` |
| Closed a GitHub issue | Remove from active tables in `docs/dev/roadmap.md` + `docs/dev/status.md` |
| Added a new hook or module | `docs/dev/architecture.md` |
| Changed debug commands or log patterns | `docs/dev/debugging.md` |
| Released a new version (`make release`) | Add changelog entry on Nexus (version + user-facing summary) |

### Doc index by activity

| You're about to... | Read first |
|---------------------|------------|
| Write or modify ability heuristics | `docs/classes/<name>.md` + `docs/classes/<name>-tactics.md` for the class |
| Analyze game logs | `docs/dev/debugging.md` (log patterns, grep recipes, file locations) |
| Analyze logging code | `docs/dev/logging.md` (log format, throttle keys, output levels, JSONL event log) |
| Understand what vanilla bots can/cannot do | `docs/bot/vanilla-capabilities.md` |
| Modify bot behavior (targeting, movement, weapons) | Relevant `docs/bot/*.md` file(s) |
| Modify input queueing or action sequences | `docs/bot/input-system.md` |
| Assess what works / what's broken | `docs/dev/validation-tracker.md` + `docs/dev/known-issues.md` |
| Work on Tier 3 item abilities | `docs/bot/input-system.md` + `docs/related-mods.md` |
| Work on grenade/blitz support | `docs/classes/grenade-inventory.md` + `docs/bot/input-system.md` |
| Gate ability activation on bot state | `docs/classes/character-state-api.md` |
| Integrate with or reference other mods | `docs/related-mods.md` |
| Implement or fix a GitHub issue | Full issue + all comments (`gh issue view <N> --comments`) |
| Plan work or prioritize issues | `docs/dev/roadmap.md` + `docs/dev/status.md` |
| Understand meta builds, weapon/ability popularity | `docs/classes/meta-builds-research.md` |
| Update Nexus mod page or release text | `docs/nexus-description.bbcode` |
| Verify a change in-game | `docs/dev/debugging.md` (debug commands, verification workflow) |
| Understand the module architecture | `docs/dev/architecture.md` |
| Create branches, batch test, or merge | Branching workflow section (this file) |
| Add per-frame logic, hooks, or engine queries | `docs/dev/architecture.md` (Performance section) |
| Write or modify tests | `docs/dev/debugging.md` (automated testing section) |
| Understand backend/progression/economy systems | `docs/backend-progression.md` |
| Explore local co-op / LAN / multiplayer modding | `docs/local-multiplayer.md` |

### Required reading order for ability work

1. This file (architecture overview)
2. The relevant `docs/classes/<name>.md` (template names, input patterns, tiers)
3. The relevant `docs/classes/<name>-tactics.md` (when/how to use each ability, proposed bot rules)
4. The relevant `docs/bot/*.md` files (system internals)
5. Decompiled source in `../Darktide-Source-Code/` for field-level verification

Do not write trigger heuristics without first reading the tactics doc for that class.

### Full doc listing

**Per-class ability references** (template names, input patterns, cooldowns, tiers):
`docs/classes/veteran.md`, `docs/classes/zealot.md`, `docs/classes/psyker.md`, `docs/classes/ogryn.md`, `docs/classes/arbites.md`, `docs/classes/hive-scum.md`

**Per-class tactical heuristics** (community-sourced USE WHEN / DON'T USE / proposed bot rules):
`docs/classes/veteran-tactics.md`, `docs/classes/zealot-tactics.md`, `docs/classes/psyker-tactics.md`, `docs/classes/ogryn-tactics.md`, `docs/classes/arbites-tactics.md`, `docs/classes/hive-scum-tactics.md`

**Bot system internals** (from decompiled source):
- `docs/bot/vanilla-capabilities.md` — exhaustive inventory of what vanilla bots can/cannot do, with source references
- `docs/bot/behavior-tree.md` — full BT node hierarchy, all conditions, blackboard schema
- `docs/bot/combat-actions.md` — melee/shoot/ability action node lifecycles, utility scoring
- `docs/bot/perception-targeting.md` — target selection scoring formula, gestalt weights, proximity
- `docs/bot/navigation.md` — pathfinding, follow behavior, teleport triggers, formation
- `docs/bot/input-system.md` — two-pathway input architecture, ActionInputParser, bot_actions.lua
- `docs/bot/profiles-spawning.md` — all vanilla bots are veterans, zero talents, weapon templates

**API references** (from decompiled source):
- `docs/classes/grenade-inventory.md` — all 19 grenade/blitz templates, input patterns, implementation approach
- `docs/classes/character-state-api.md` — character state detection components, fields, access patterns
- `docs/classes/meta-builds-research.md` — endgame meta builds per class, weapon/ability rankings, community build database
- `docs/backend-progression.md` — backend API architecture, progression systems, local backend feasibility
- `docs/local-multiplayer.md` — local co-op feasibility, engine networking, VT2 comparison

**Project management:**
`docs/dev/debugging.md`, `docs/dev/logging.md`, `docs/dev/architecture.md`, `docs/dev/validation-tracker.md`, `docs/dev/known-issues.md`, `docs/related-mods.md`, `docs/dev/roadmap.md`, `docs/dev/status.md`, `docs/dev/test-plan.md`

**Release:**
- `docs/nexus-description.bbcode` — Nexus mod page description (BBCode format, copy to Nexus when releasing)

## Mod file structure

```
BetterBots.mod                              # DMF entry point
bb-log                                      # Log analysis CLI (bash)
scripts/mods/BetterBots/
  BetterBots.lua                            # Main: hooks, condition patch, fallback queue
  heuristics.lua                            # 18 per-template heuristic functions + build_context()
  meta_data.lua                             # ability_meta_data injection
  item_fallback.lua                         # Tier 3 item wield/use/unwield state machine
  event_log.lua                             # Structured JSONL event logging (decision/queued/consumed)
  sprint.lua                                # Bot sprint injection (catch-up, rescue, traversal, daemonhost safety)
  melee_meta_data.lua                        # Melee attack_meta_data injection (arc/penetrating classification)
  ranged_meta_data.lua                      # Ranged attack_meta_data injection (fire/aim input derivation)
  debug.lua                                 # Debug commands + context/state snapshots
  BetterBots_data.lua                       # Mod options / widget definitions
  BetterBots_localization.lua               # Display strings
tests/
  test_helper.lua                           # make_context(), mock factories, engine stubs
  heuristics_spec.lua                       # 122 tests for all 18 heuristic functions
  meta_data_spec.lua                        # 7 tests for injection/overrides/idempotency
  resolve_decision_spec.lua                 # 8 tests for nil→fallback paths
  event_log_spec.lua                        # 10 tests for event buffering/flush/lifecycle
  sprint_spec.lua                           # 18 tests for sprint conditions + daemonhost safety
  melee_meta_data_spec.lua                  # 33 tests for melee meta_data classification + injection
  ranged_meta_data_spec.lua                 # 27 tests for ranged fallback, input derivation + injection
```
