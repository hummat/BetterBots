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

No automated tests — this is a Lua mod running inside Darktide's engine. Verify by:
1. Launching the game with SoloPlay + Tertium4Or5 mods active
2. Checking for `BetterBots loaded` and `injected meta_data for ...` in the game chat
3. Observing bot behavior during combat encounters

Hot-reload with `Ctrl+Shift+R` when dev mode is enabled in DMF settings.

## Local static checks

Use project-local tooling configs before handing off changes:

- `make deps` → install git hooks (conventional commits)
- `make lint` → `luacheck` with `.luacheckrc`
- `make format-check` / `make format` → `stylua` with `.stylua.toml`
- `make lsp-check` → `lua-language-server --check` with `.luarc.json`
- `make check` → runs all of the above
- `make release VERSION=X.Y.Z` → tag + push (CI creates GitHub release with changelog)

Notes:

- `make test` auto-detects a busted runner (`busted`, `lua-busted`, or Arch's packaged luarocks path).
- `make test` is a no-op unless a `tests/` directory exists.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`, `revert`, `style`, `build`

Enforced by local `commit-msg` hook (install via `make deps`) and CI commit-lint on PRs.

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
3. **Condition hook:** Replaces `bt_bot_conditions.can_activate_ability` to pass all templates with valid `ability_meta_data` through, using `enemies_in_proximity() > 0` as the generic trigger.

### Ability tiers

| Tier | Status | Examples | What's needed |
|------|--------|----------|---------------|
| 1 | Implemented | Veteran Stealth, Psyker Stance, Ogryn Gunlugger, Broker Focus/Rage | Whitelist removal only |
| 2 | Implemented (untested) | Zealot Dash/Invisibility, Ogryn Charge/Taunt, Psyker Shout | Meta_data injection + whitelist removal |
| 3 | Not addressed | All grenades, Zealot Relic, Psyker Force Field, Smite | No `ability_template` field → needs different approach (custom BT node or item wield) |

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

## Class ability references

Per-class docs with internal template names, input patterns, cooldowns, and bot implementation tiers:
- `docs/CLASS_VETERAN.md`, `docs/CLASS_ZEALOT.md`, `docs/CLASS_PSYKER.md`, `docs/CLASS_OGRYN.md`, `docs/CLASS_ARBITES.md`, `docs/CLASS_HIVE_SCUM.md`

Consult these when working on class-specific ability logic, adding new ability support, or tuning bot trigger heuristics.

## Mod file structure

```
BetterBots.mod                              # DMF entry point
scripts/mods/BetterBots/
  BetterBots.lua                            # Core logic
  BetterBots_data.lua                       # Mod options / widget definitions
  BetterBots_localization.lua               # Display strings
```
