# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Darktide Mod Framework (DMF) mod that makes bots use their combat abilities in Solo Play. The game has a complete bot ability activation system (behavior tree node + condition guard + action input queue), but Fatshark hardcoded a whitelist in `bt_bot_conditions.can_activate_ability` that only allows two abilities. This mod removes that gate and injects missing metadata so the existing infrastructure handles the rest.

**Scope — critical:** BetterBots is client-side and only affects bots in locally-hosted sessions (`game_mode_settings.host_singleplay = true`). Darktide uses Fatshark dedicated servers for all public and matched play, so this mod has zero effect on bots there. In practice, the Solo Play mod is the only context where BetterBots runs. When answering "does the mod work in [Havoc / public / matched / Penances / X]" questions, the answer is **no** unless X is locally hosted — verify against `host_singleplay` before investigating engine capabilities. Do not pattern-match from Vermintide 2's P2P/listen-server model; Darktide's architecture is different.

## Deployment

The mod lives in `$GIT_ROOT/BetterBots/` and is symlinked into the Darktide mods directory:
```
mods/BetterBots -> $GIT_ROOT/BetterBots
```
Darktide install: `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/`

After changes, re-run `toggle_darktide_mods.bat` (Windows) or `handle_darktide_mods.sh` (Linux) in the game root to re-patch. Mods are disabled after every game update.

## Testing

**Automated** (outside the game):
- `make test` — unit tests via busted (see `tests/*_spec.lua` for the full list; inventory enforced by `make doc-check`)
- `make patch-check` — verify BetterBots' engine anchor contracts against the current `../Darktide-Source-Code` checkout
- `make patch-check-refresh` — `git pull --ff-only` the decompiled source, then rerun the engine anchor checks
- `make check` — local quality gate: auto-format, then lint + lsp + test + doc-check
- `make check-ci` — CI quality gate: format-check + lint + lsp + test + doc-check

**In-game** (manual verification):
1. Launch with SoloPlay + Tertium5/6 mods active
2. Check for `BetterBots loaded` in game chat
3. After mission: `bb-log summary` to verify activations and hold rules
4. See `docs/dev/validation-tracker.md` for structured run entries and the heuristic validation matrix

Hot-reload with `Ctrl+Shift+R` when dev mode is enabled in DMF settings.

**Pre-release cold-boot test (mandatory before `make release` → Nexus push).** Static checks pass for code that still crashes on real bootstrap (v0.11.0 shipped clean tests but CTD'd on cold launch). Hot-reload skips the Lua state reset that exposes `hook_require` sentinel bugs. Before pushing a release:
1. Fully quit Darktide, relaunch, load into a mission — no hot-reload, state must reset.
2. Run `bb-log summary` AND `bb-log warnings` — expect zero rehook / install-failure lines.
3. Grep the raw console log: `grep -cE "rehook active|\[ERROR\]|lua error|CRASH" <newest-console-log>` — expect 0.
4. Repeat the launch with BetterBots loaded **first** and **last** in the mod order. Some crashes only reproduce under one ordering (v0.11.0 regression was BetterBots-first-only).

**Mock fidelity rule:** Test mocks for `ScriptUnit.has_extension` / `ScriptUnit.extension` must only expose methods verified to exist on the real engine extension class — via decompiled source (`../Darktide-Source-Code/`) or in-game dump. Darktide has extension subtype splits where the same `system_name` returns different classes for players vs minions (e.g. `unit_data_system` → `PlayerUnitDataExtension` with `read_component` for players, `MinionUnitDataExtension` with only `breed()` for enemies). Mocks that give minion units player-only methods create false test confidence — tests pass, production crashes. When code can receive both player and minion units, test both paths. See #95. Current audited surface + source-line evidence: `docs/dev/mock-api-audit.md`.

**Bug-catch audit (mandatory for every bug fix).** Every time a bug surfaces — Codex/Claude review finding, runtime crash, Nexus report, in-game regression, DMF warning — the fix is not complete until you have asked *"should the harness have caught this?"* and acted on the answer.

Required steps before closing the task:

1. **Reproduce the miss.** Temporarily restore the buggy code on a scratch branch or via `git stash`, run the relevant subset of `make check` (or the spec in question), and confirm it still passes. Silence proves the gap is real.
2. **Classify the gap.** Is it (a) a test that never existed, (b) a test that exists but has a blind spot (regex only matches literals, fake bypasses real runtime guard, mock exposes methods the real class lacks, patch-check missing an anchor), or (c) a test that runs but asserts nothing meaningful? All three count.
3. **Close it for the class, not the instance.** A stronger regex that handles the specific variable name is not the fix; a resolver that handles any indirection is. Ask whether the next bug of the same shape would be caught.
4. **Drive the change with TDD.** New/strengthened test goes red against the original bug, green with the fix. This is non-negotiable — a harness improvement that was not seen to fail has the same credibility as untested production code.
5. **Ship harness + code together.** Same commit, same PR. Never merge the fix and defer the harness. The next commit will always be "more urgent."

Historical worked examples (keep for pattern-matching):

- *Duplicate `hook_require` path (#92 Sprint 1, 2026-04-18):* the bootstrap `rejects duplicate hook_require targets` check missed a case where one of the two registrations used a module-local constant instead of a string literal — regex only matched `hook_require("…"`. Strengthened by resolving `local IDENT = "…"` declarations per-file and mapping `hook_require(IDENT, …)` calls through that table. `tests/startup_regressions_spec.lua` ~line 1119.
- *Mock fidelity (#95):* see the rule above. The fix was an audit doc (`docs/dev/mock-api-audit.md`) + per-spec discipline, not just a per-crash mock patch.

If the bug cannot be caught by a static check or spec — for example, an engine-side rename that a unit test could never see — escalate it to `scripts/patch-check.sh` as an anchor instead. That is still "strengthening the harness," just at the contract layer.

## Debugging

Every new feature must include enough `_debug_log` calls to verify correctness from a single in-game session. Not exhaustive or verbose — just sufficient to confirm each code path fires when expected. This logging is **permanent** — it exists to catch regressions and validate working state across releases, not just during initial development. Before marking a feature complete, audit: can you grep `bb-log` output and tell with certainty that it works?

**Writing `_debug_log` calls — mandatory rules:**
- **Gate expensive reads**: never call `read_component()`, `has_extension()`, or build context strings unless `_debug_enabled()` is true. These run on the hot path every frame.
- **One-shot dedup for repeated events**: use a weak-keyed set (`setmetatable({}, { __mode = "k" })`) keyed on scratchpad/unit, or a string-keyed set for `combo_key` patterns. Log each unique occurrence once per load, not per frame.
- **Throttle key convention**: first arg to `_debug_log` is `"feature_tag:" .. discriminator` (e.g. `"may_fire_swap:" .. input_name`). This enables grep-based filtering. **Per-bot code paths must include `.. ":" .. tostring(unit)` in the key** — otherwise `_debug_log`'s time-based throttle silently drops all but the first bot's message when multiple bots fire the same key in the same frame.
- **Log the confirmation signal**: the event that proves the feature fired correctly (e.g. "input was swapped", "grenade state transitioned", "target was penalized"), not intermediate state.
- **Don't log no-ops**: idle paths, false conditions, and expected skips produce no output. Only log when something interesting happened.

See `docs/dev/logging.md` for the full logging architecture, output channels, log line catalog, and analysis tools. See `docs/dev/debugging.md` for debug tool reference. Key tools:
- **`bb-log`** (project root) — primary log analysis tool. Use `bb-log summary` for overview (includes DMF warning counter), `bb-log activations` for raw events, `bb-log rules` for counts, `bb-log warnings` for the full BetterBots warning breakdown (rehook attempts, hook install failures), `bb-log events summary` for JSONL event analysis. **Always use this instead of raw rg/grep on log files.**
- `mod:echo(msg)` — print to chat + log (current approach)
- `mod:dump(table, name, depth)` — recursively dump tables to log
- `mod:dtf(table, name, depth)` — export table as JSON to `./dump/`
- `mod:pcall(func)` — safe call with stack trace via `Script.callstack()`
- `mod:command(name, desc, func)` — register `/name` chat commands for runtime debugging
- In-game: `/bb_state`, `/bb_decide`, `/bb_brain` for live bot diagnostics
- Hot-reload: `Ctrl+Shift+R` (requires DMF Developer Mode)
- Console logs: `tail -f` on `console_logs/console-*.log` — **read `docs/dev/debugging.md` for log patterns and grep recipes before searching logs** (the log format is non-obvious and easy to miss with wrong patterns)
- **Modding Tools** (Nexus #312): table inspector + variable watcher (recommended for development)

## Settings surface

Every BetterBots addition must be adjustable or toggleable via the mod settings UI, with one exception: vanilla bug fixes (guards against engine crashes, nil-safety patches, etc.) that restore correct behavior may be unconditionally active.

**What "adjustable" means per feature type:**
- **New behavior** (ability activation, targeting changes, pickup policies): a boolean toggle under the appropriate settings category, defaulting to `true` (on)
- **Tuning parameters** (distances, thresholds, timers): a numeric slider or dropdown with sensible defaults and min/max bounds
- **Risky or opinionated behavior** (grimoire pickup, aggressive presets): default to `false` (off) — opt-in, not opt-out

**Implementation checklist for new settings:**
1. Add default to `M.DEFAULTS` in `settings.lua`
2. Add `FEATURE_GATES` entry (for boolean toggles) or accessor function (for numeric values)
3. Add widget definition in `BetterBots_data.lua`
4. Add localized label + description in `BetterBots_localization.lua`
5. Wire `is_enabled` / getter through the module's `init()` deps
6. Gate the module's hooks/behavior behind the setting at runtime

**Why:** Solo Play users have wildly different preferences and hardware. A feature that helps one player may annoy another. Settings cost almost nothing to add but are impossible to retrofit without breaking saved configs. The mod's value proposition is "bots that actually use abilities" — not "bots that behave exactly how the developer thinks they should."

## Local static checks

Use project-local tooling configs before handing off changes:

- `make tool-info` → show the exact tool binaries and fallback paths that `make` will use
- `make deps` → install git hooks (conventional commits + StyLua pre-commit)
- `make lint` → `luacheck` with `.luacheckrc`
- `make format-check` / `make format` → `stylua` with `.stylua.toml`
- `make lsp-check` → `lua-language-server --check` with `.luarc.json`
- `make patch-check` / `make patch-check-refresh` → verify BetterBots' engine contract anchors against `../Darktide-Source-Code`
- `make doc-check` → verify doc claims against code (heuristic function counts, closed issue state)
- `make check` → auto-formats, then runs lint + lsp + test + doc-check
- `make check-ci` → non-mutating CI gate
- `make package` → build Nexus-ready `BetterBots.zip`
- `make release VERSION=X.Y.Z` → patch-check-refresh + check + package + tag + push + upload ZIP (CI also attaches ZIP)
  - **Post-release (all 4 Nexus fields required):**
    1. Update `docs/nexus-description.bbcode` — remove fixed bugs from "Known issues", update "New in vX.Y.Z", move shipped features to ✓ in roadmap. Commit + push.
    2. Brief overview (≤350 chars, plain text) for the Nexus "Summary" field.
    3. File description (≤255 chars, plain text) for the upload's "File description" field.
    4. Changelog row (version + summary of user-facing changes) via the Nexus "Add new changelog" form.

Notes:

- `make test` tries `busted`, `lua-busted`, then Arch's packaged luarocks path.
- `make test` is a no-op unless a `tests/` directory exists.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`, `revert`, `style`, `build`

Enforced by local `commit-msg` hook (install via `make deps`) and CI commit-lint on PRs.

## Outward-facing writing

Before drafting any text aimed at users or external communities, invoke **both** of these skills:

1. **`human-writing`** skill — strips AI-generated patterns (over-enthusiastic openings, buzzword soup, vague claims, unnecessary hedging, robotic feature lists). Mandates specifics, honest limitations, active voice.
2. **`style`** skill with **`blog:`** register — applies Matthias's voice (first person singular, "turns out" signature, short payoff sentences alternating with longer ones, fragments OK, honest opinions, no banned vocab like "delve"/"showcase"/"underscore"/"utilize").

Order: detect the surface is outward-facing → invoke `human-writing` → invoke `style` with `blog:` prefix → draft → self-check against both skills' red flags before presenting.

**Surfaces this applies to:**
- Nexus description (`docs/nexus-description.bbcode`)
- Nexus changelog text (when preparing a release entry)
- README highlights / user-visible blocks
- Reddit / Fatshark forum / Discord / Steam Community Hub posts
- Promotion drafts in memory (`promotion_drafts.md`)
- Any DM/PM to a mod author, creator, or community member
- Any text copied out of this repo into an external channel

**Exempt:**
- CLAUDE.md, AGENTS.md, internal docs under `docs/dev/`
- Source code + code comments
- Commit messages (use the `/commit` skill instead)
- Test specs
- Conversational replies inside a session

**Register calibration.** Outward-facing is not one register. The two skills strip AI patterns and apply Matthias-blog voice, but that voice is not always the right tone. Pick the register before drafting:

- **Blog / showcase register** — Nexus description, Reddit/forum post, Steam Guide, README highlights, changelog, Modders Discord `#creation-showcase` (compressed to link + 1 player-facing sentence; no dev-speak). Explanatory, opinionated, first-person, problem → fix → honest limits. Default when writing *about* the mod for a broad audience. Even the Modders Discord channel reaches mod-using gamers, not just mod authors — frame around what the mod does for players, not internals.
- **Peer / insider register** — mod-author DMs once contact is established, technical PR comments, GitHub issue threads with other mod authors. Skip the problem setup — they know vanilla bots are broken. Lead with what you built mechanically. Concise.
- **Favor-ask / cold-PM register** — first DM to a stranger (other mod authors, creators, Fatshark staff). Warm, deferential, low-pressure. Name the recipient. Lead with the ask, not the feature list. Keep the feature paragraph short. Close with genuine thanks.

All three still invoke `human-writing` + `style:blog` for pattern-stripping, but the **framing and cadence** differ. A cold-email pitch written in blog-showcase register reads transactional and templated. See `memory/promotion_plan.md` "Positioning principles" and `memory/promotion_drafts.md` for worked examples.

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
3. **Condition hook:** Replaces `bt_bot_conditions.can_activate_ability` with 18 per-template heuristics split across `heuristics_context.lua`, career-specific `heuristics_*.lua` modules, and `heuristics_grenade.lua`, with `heuristics.lua` as the thin public dispatcher. Each ability has specific activate/block conditions based on health, toughness, peril, enemy composition, distance, and ally state. Unknown templates fall back to `enemies_in_proximity() > 0`.

### Ability tiers

| Tier | Status | Examples | What's needed |
|------|--------|----------|---------------|
| 1 | Validated | Veteran Stance/Stealth, Psyker Stance, Ogryn Gunlugger, Arbites Stance | Whitelist removal only |
| 1 | Untested (Hive Scum DLC) | Broker Focus/Rage | Whitelist removal only — Hive Scum DLC not owned |
| 2 | Validated | Zealot Dash/Invisibility, Ogryn Charge/Taunt, Psyker Shout, Arbites Charge | Meta_data injection + whitelist removal |
| 3 | Validated | Zealot Relic, Psyker Force Field, Arbites Drone | Item-based fallback (wield/use/unwield sequence). Drone crash guard for #50 validated in a 2026-03-13 Arbites stress run. |
| 3 | Blocked (Hive Scum DLC) | Hive Scum Stimm Field | Item-based, Hive Scum DLC not owned |
| 3 | Validated | Standard grenades, Psyker Smite/Assail/Chain Lightning, knives, whistle, mines | Grenade/blitz fallback + per-grenade heuristics |

### Decompiled source repo (Aussiemon/Darktide-Source-Code)

Local clone: `../Darktide-Source-Code/`

**Before starting any new feature work, or answering any Darktide patch/"latest"/"did Fatshark change X" question, pull the latest decompiled source first. Do this before any web search or browsing.** The local decompiled repo is the first source of truth for mechanics and patch impact in this project; online sources are fallback only when the local clone is missing or confirmed not yet updated.

Required command:
```bash
cd ../Darktide-Source-Code && git pull && cd -
```
If the clone doesn't exist, create it:
```bash
gh repo clone Aussiemon/Darktide-Source-Code ../Darktide-Source-Code -- --depth 1
```

**Hard rule for patch analysis:** if the user mentions a version number (for example `1.11.4`), "Warband", "new path", patch notes, or asks whether a game change has implications for BetterBots, first:
1. Check that `../Darktide-Source-Code/` exists
2. Run `git pull`
3. Inspect the local repo's latest commit/version
4. Run `make patch-check` (or `make patch-check-refresh` if you want the pull + contract gate in one step)
5. Only then decide whether external browsing is still necessary

Do not jump to web search first for Darktide mechanics or patch-impact questions.

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
- BetterBots-local modules must be loaded in `scripts/mods/BetterBots/BetterBots.lua` via `mod:io_dofile("BetterBots/scripts/mods/BetterBots/<name>")`
- Leaf modules must not `require("scripts/mods/BetterBots/...")` or `dofile("scripts/mods/BetterBots/...")` other BetterBots files; pass shared helpers through `init({...})` / `wire({...})` instead

## MANDATORY: Read relevant docs before acting, update them after

**Read first:** Before performing ANY task in this project — implementation, debugging, log analysis, validation, planning — check the doc index below and read the relevant docs first. Do not guess from memory. The docs are the ground truth for game internals, log formats, mod conventions, and validation status. This applies to all tasks, not just code changes.

**GitHub issues:** When asked to work on a GitHub issue (e.g. "implement #X", "fix #X"), always read the full issue including ALL comments before starting — not just the issue body. Comments accumulate design decisions, code review feedback, and implementation notes over time.

**CLI failure handling:** If a critical CLI command fails in a way that looks like sandbox/network/auth-context breakage, retry it once with escalation before declaring the tool unavailable. This especially applies to `gh`: a sandboxed auth failure or API connection error is not evidence that GitHub is actually unreachable from the host.

**Update after:** When your code change affects a documented fact, update the docs in the same commit. `make doc-check` catches stale heuristic function counts, module/spec inventory parity, and closed-issue references automatically, but semantic claims (tier status, capability descriptions, template names) require manual updates. Common triggers:

| You just... | Update |
|---|---|
| Added/removed a `_can_activate_*` function | Function count in this file + `docs/dev/debugging.md` |
| Changed tier status or validation result | Tier table in this file + `docs/dev/validation-tracker.md` + `docs/dev/status.md` + `docs/nexus-description.bbcode` ("What works" + "Known issues") |
| Closed a GitHub issue | Remove from active tables in `docs/dev/roadmap.md` + `docs/dev/status.md` |
| Added a new module under `scripts/mods/BetterBots/` | `docs/dev/architecture.md` + README.md repo layout block + AGENTS.md "Mod file structure" block. `make doc-check` will fail until the file inventories are restored. |
| Added a new hook (no new module) | `docs/dev/architecture.md` |
| Added a new `tests/*_spec.lua` file | AGENTS.md test list. `make doc-check` will fail until the spec inventory is restored. |
| Changed debug commands or log patterns | `docs/dev/debugging.md` |
| Fixed a user-reported bug or known issue | `docs/nexus-description.bbcode` ("Known issues") + relevant GitHub issue |
| Added/changed user-visible behavior | README.md highlights + `docs/nexus-description.bbcode` (roadmap, "What works", version notes) |
| Released a new version (`make release`) | Update `docs/nexus-description.bbcode` + post all 4 Nexus fields (brief overview, file description, changelog row, mod page description) |

### Doc index by activity

| You're about to... | Read first |
|---------------------|------------|
| Write or modify ability heuristics | `docs/classes/<name>.md` + `docs/classes/<name>-tactics.md` for the class |
| Analyze game logs | `docs/dev/debugging.md` (log patterns, grep recipes, file locations) |
| Analyze logging code | `docs/dev/logging.md` (log format, throttle keys, output levels, JSONL event log) |
| Understand what vanilla bots can/cannot do | `docs/bot/vanilla-capabilities.md` |
| Modify bot behavior (targeting, movement, weapons) | Relevant `docs/bot/*.md` file(s) |
| Modify input queueing or action sequences | `docs/bot/input-system.md` |
| Assess what works / what's broken | `docs/dev/validation-tracker.md` + `docs/dev/known-issues.md` + `docs/nexus-description.bbcode` ("Known issues") |
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

### No unsourced game knowledge claims

Every factual claim about Darktide mechanics — talent effects, ability interactions, buff values, tree structure, weapon behavior, bot capabilities — must be sourced from a specific file before you state it. If you haven't read the source, you don't know the answer. Say so and go read it.

**Verification chain (in priority order):**
1. Decompiled source (`../Darktide-Source-Code/`) — ground truth for mechanics, tree structure, buff values
2. In-repo docs (`docs/knowledge/`, `docs/classes/`) — curated summaries, cross-reference with (1) when uncertain
3. Mod source (`scripts/mods/BetterBots/`) — ground truth for what BetterBots actually does
4. Online sources (Games Lantern, wiki, Reddit) — community knowledge, may be wrong or outdated

**Concrete rules:**
- When analyzing a build: read the class doc, tactics doc, and relevant `buff_templates.md` / `class-talents.md` entries BEFORE writing any assessment. Not after. Not "I'll verify later." Before.
- When a label or classification comes from scraped/generated data: cross-check it against decompiled source. Scraper heuristics have bugs. Generated labels are hypotheses, not facts.
- When claiming what BetterBots can or cannot do: read the actual module source. The validation tracker and CLAUDE.md tier table exist for this purpose.
- When stating a talent is a keystone, modifier, or regular node: verify against the decompiled tree layout file (node `type` field), not against display names or frame shapes.
- If you haven't verified a claim and can't verify it right now, mark it explicitly: "(unverified)" or "I haven't read the source for this." Never present an unverified guess as fact.

**Why this matters:** Wrong game knowledge propagates. It gets written into docs, shapes heuristic design, and wastes hours of debugging when the assumed behavior doesn't match reality. Reading one file takes seconds. Correcting a cascade of wrong assumptions takes sessions.

### Full doc listing

Per-class ability references and tactical heuristics live under `docs/classes/` (one `<class>.md` + `<class>-tactics.md` per class). Bot system internals live under `docs/bot/`. Project management lives under `docs/dev/`. Below are the non-obvious entries that filename alone doesn't explain.

**API references:**
- `docs/classes/grenade-inventory.md` — all 19 grenade/blitz templates, input patterns, implementation approach
- `docs/classes/character-state-api.md` — character state detection components, fields, access patterns
- `docs/classes/meta-builds-research.md` — endgame meta builds per class, weapon/ability rankings, community build database
- `docs/backend-progression.md` — backend API architecture, progression systems, local backend feasibility
- `docs/local-multiplayer.md` — local co-op feasibility, engine networking, VT2 comparison

**Game knowledge base** (`docs/knowledge/`):
- `class-talents.md` — all 6 classes: abilities, keystones, key passives, coherency (from decompiled source)
- `talent-system.md` — engine internals: profile.talents format, stat node naming, add_archetype_base_talents behavior, ability template dispatch, hadrons-blessing entity ID mapping
- `perks-curios.md` — weapon perk + curio perk T1→T4 tables (from decompiled source)
- `buff-templates.md` — exhaustive buff template stat values for all 6 classes (from decompiled source)
- `damage-system.md` — 13-stage damage pipeline, ADM, rending, finesse, toughness absorption
- `enemy-stats.md` — enemy HP/armor tables by breed and difficulty
- `build-knowledge.md` — class base stats, coherency, talent architecture, meta overview
- `weapon-blessings.md` — blessing catalog for 18 S/A-tier weapons
- `research.md` — ability patterns, bot system docs, API gotchas, healing architecture
- `patch-history.md` — balance changes Mar 2025–Mar 2026

**Release:** `docs/nexus-description.bbcode` — Nexus mod page description (BBCode format, copy to Nexus when releasing).

## Mod file structure

For per-module descriptions see the repo layout block in `README.md`; for architecture and hook wiring see `docs/dev/architecture.md`. The inventories below are what `make doc-check` cross-checks against the filesystem — keep them in lockstep with `scripts/mods/BetterBots/` and `tests/`.

**Modules** (`scripts/mods/BetterBots/`): `BetterBots.lua`, `BetterBots_data.lua`, `BetterBots_localization.lua`, `ability_queue.lua`, `airlock_guard.lua`, `ammo_policy.lua`, `animation_guard.lua`, `bot_profile_templates.lua`, `bot_profiles.lua`, `bot_targeting.lua`, `bootstrap.lua`, `charge_nav_validation.lua`, `charge_tracker.lua`, `combat_ability_identity.lua`, `com_wheel_response.lua`, `companion_tag.lua`, `condition_patch.lua`, `debug.lua`, `engagement_leash.lua`, `event_log.lua`, `gestalt_injector.lua`, `grenade_aim.lua`, `grenade_fallback.lua`, `grenade_profiles.lua`, `grenade_runtime.lua`, `healing_deferral.lua`, `heuristics.lua`, `heuristics_arbites.lua`, `heuristics_context.lua`, `heuristics_grenade.lua`, `heuristics_hive_scum.lua`, `heuristics_ogryn.lua`, `heuristics_psyker.lua`, `heuristics_veteran.lua`, `heuristics_zealot.lua`, `human_likeness.lua`, `item_fallback.lua`, `item_profiles.lua`, `log_levels.lua`, `melee_attack_choice.lua`, `melee_meta_data.lua`, `meta_data.lua`, `mule_pickup.lua`, `perf.lua`, `ping_system.lua`, `pocketable_pickup.lua`, `poxburster.lua`, `ranged_meta_data.lua`, `ranged_special_action.lua`, `revive_ability.lua`, `settings.lua`, `shared_rules.lua`, `smart_tag_orders.lua`, `smart_targeting.lua`, `sprint.lua`, `sustained_fire.lua`, `target_selection.lua`, `target_type_hysteresis.lua`, `team_cooldown.lua`, `update_dispatcher.lua`, `vfx_suppression.lua`, `weakspot_aim.lua`, `weapon_action.lua`, `weapon_action_logging.lua`, `weapon_action_shoot.lua`, `weapon_action_voidblast.lua`.

**Test specs** (`tests/`): `ability_queue_spec.lua`, `airlock_guard_spec.lua`, `ammo_policy_spec.lua`, `animation_guard_spec.lua`, `boss_engagement_spec.lua`, `bot_profiles_spec.lua`, `bot_targeting_spec.lua`, `charge_nav_validation_spec.lua`, `charge_tracker_spec.lua`, `com_wheel_response_spec.lua`, `combat_ability_identity_spec.lua`, `companion_tag_spec.lua`, `condition_patch_spec.lua`, `debug_spec.lua`, `engagement_leash_spec.lua`, `event_log_spec.lua`, `gestalt_injector_spec.lua`, `grenade_fallback_spec.lua`, `healing_deferral_spec.lua`, `heuristics_spec.lua`, `human_likeness_spec.lua`, `item_fallback_spec.lua`, `log_levels_spec.lua`, `melee_attack_choice_spec.lua`, `melee_meta_data_spec.lua`, `meta_data_spec.lua`, `mule_pickup_spec.lua`, `perf_spec.lua`, `ping_system_spec.lua`, `pocketable_pickup_spec.lua`, `poxburster_spec.lua`, `ranged_meta_data_spec.lua`, `ranged_special_action_spec.lua`, `resolve_decision_spec.lua`, `revive_ability_spec.lua`, `runtime_contracts_spec.lua`, `settings_spec.lua`, `shared_rules_spec.lua`, `smart_tag_orders_spec.lua`, `smart_targeting_spec.lua`, `sprint_spec.lua`, `startup_regressions_spec.lua`, `sustained_fire_spec.lua`, `target_selection_spec.lua`, `target_type_hysteresis_spec.lua`, `team_cooldown_spec.lua`, `test_helper_spec.lua`, `update_dispatcher_spec.lua`, `vfx_suppression_spec.lua`, `weakspot_aim_spec.lua`, `weapon_action_spec.lua`.
