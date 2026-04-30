# BetterBots

[![CI](https://github.com/hummat/BetterBots/actions/workflows/ci.yml/badge.svg)](https://github.com/hummat/BetterBots/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Nexus Mods](https://img.shields.io/badge/Nexus-BetterBots-orange)](https://www.nexusmods.com/warhammer40kdarktide/mods/745)

A [DMF](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework) mod that enables bot combat abilities, weapon specials, and resource management in Darktide Solo Play. User-facing overview lives on [Nexus](https://www.nexusmods.com/warhammer40kdarktide/mods/745); this README is for developers, contributors, and maintainers.

> **Solo Play only.** Darktide uses dedicated servers. Gameplay mods only affect missions hosted locally through the [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176) mod. Public matchmaking is unaffected.

## Project status

- **v1.0.0 is the terminal 1.x release.** All 6 planned sprints are code-complete and shipped. See [`docs/dev/status.md`](docs/dev/status.md) for the detailed snapshot and [`docs/dev/roadmap.md`](docs/dev/roadmap.md) for the full history.
- **Primary maintainer is stepping back.** The project is stable and feature-complete against its original scope. Issues, PRs, and forks are welcome; review cadence will be best-effort.
- **Post-1.0 scope is open-ended.** Items in the "may never ship" bucket (utility scoring, user-authored profiles, Tier 3 revive cover, grenade tactical evaluator) are good entry points for new contributors who want to pick up significant work.
- **Active validation gaps** (none block v1.0.0, but they remain open):
  - [`#17`](https://github.com/hummat/BetterBots/issues/17) dormant daemonhost suppression — still needs a live log with a dormant daemonhost present before first bot action
  - Hive Scum abilities and blitzes — implemented but DLC-blocked for the maintainer; relies on community reports
  - Mission-end performance is currently above the documented v1.0 target of median ≤125 µs/bot/frame with no single run > 140. The `a24f078` diagnostic additions are the likely driver and a plausible first optimization target.

## Project orientation

BetterBots removes a hardcoded whitelist in the Darktide bot behavior tree that only allowed two abilities, then fills in the missing metadata so the rest of the vanilla infrastructure handles everything else. Most of the code is in that "fill in missing metadata + add heuristics that decide when to fire" loop.

A five-line mental model:

1. At mod load, [`meta_data.lua`](scripts/mods/BetterBots/meta_data.lua) + [`melee_meta_data.lua`](scripts/mods/BetterBots/melee_meta_data.lua) + [`ranged_meta_data.lua`](scripts/mods/BetterBots/ranged_meta_data.lua) inject `ability_meta_data` / `attack_meta_data` entries the engine expects.
2. At runtime, [`condition_patch.lua`](scripts/mods/BetterBots/condition_patch.lua) patches the BT condition evaluators so ability nodes reach the bot instead of being short-circuited by the vanilla whitelist.
3. When a BT condition fires, per-class heuristics in [`heuristics_*.lua`](scripts/mods/BetterBots/) decide whether this specific ability should trigger, given the current context (enemy count, threat, peril, allies, talents, etc.).
4. If the BT can't handle it directly (Tier 3 items, grenades, shotgun specials), a state-machine fallback drives the engine-facing inputs: [`item_fallback.lua`](scripts/mods/BetterBots/item_fallback.lua), [`grenade_fallback.lua`](scripts/mods/BetterBots/grenade_fallback.lua), [`ranged_special_action.lua`](scripts/mods/BetterBots/ranged_special_action.lua).
5. Cross-cutting policies (sprint, pinging, pickups, healing deferral, engagement leash, com-wheel response) hook BotBehaviorExtension through [`update_dispatcher.lua`](scripts/mods/BetterBots/update_dispatcher.lua).

For a full walkthrough, start with [`docs/dev/architecture.md`](docs/dev/architecture.md) and then [`docs/bot/behavior-tree.md`](docs/bot/behavior-tree.md). Both are kept up to date alongside the code.

## Quick start (development)

```bash
git clone https://github.com/hummat/BetterBots.git
cd BetterBots
make deps          # install the commit-msg hook
make check-ci      # non-mutating gate: format-check + lint + lsp + tests + doc checks
```

Typical inner loop:

```bash
# edit code, then:
make check         # auto-formats, then runs lint + lsp + tests + doc checks
make test          # tests only, faster
```

The repo does not modify your shell `PATH`. `make tool-info` prints exactly which binaries will be used (luacheck, stylua, lua-language-server, busted).

### Required tools

- Lua 5.1 / LuaJIT (or anything `busted` supports)
- `luacheck` — lint (via the repo-local `bin/luacheck` wrapper for the Lua 5.5 mismatch)
- `stylua` — format
- `lua-language-server` — static diagnostics
- `busted` (or `lua-busted`, or the Arch-packaged runner) — tests

### Required for live validation

- Darktide + [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) + [DMF](https://www.nexusmods.com/warhammer40kdarktide/mods/8)
- [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176) — required to host missions locally
- [Tertium 5](https://www.nexusmods.com/warhammer40kdarktide/mods/183) or [Tertium 6](https://www.nexusmods.com/warhammer40kdarktide/mods/725) — recommended; without one, vanilla bots are all veterans

### Installing from source

Clone into `Darktide/mods/BetterBots`, add `BetterBots` to `mods/mod_load_order.txt` below `dmf`, then re-patch mods (`toggle_darktide_mods.bat` on Windows, `handle_darktide_mods.sh` on Linux). Mods are disabled after every game update; re-patching is required each time.

Verify in-game: start a Solo Play mission and look for `BetterBots loaded` in chat, plus `BetterBots: injected meta_data for ...` lines.

## Make targets

| Target | Description |
|--------|-------------|
| `make deps` | Install git hooks (Conventional Commits) |
| `make check` | Auto-format, then run lint + lsp + tests + doc checks |
| `make check-ci` | Non-mutating CI gate: format-check + lint + lsp + tests + doc checks |
| `make test` | Run busted tests |
| `make lint` | Run luacheck (via repo-local wrapper) |
| `make format` | Format with StyLua |
| `make format-check` | Dry-run format check |
| `make lsp-check` | Run lua-language-server diagnostics |
| `make doc-check` | Validate doc invariants (see `scripts/doc-check/`) |
| `make patch-check` | Verify decompiled Darktide engine anchors against the current local checkout |
| `make patch-check-refresh` | `git pull --ff-only` the decompiled checkout, then verify anchors |
| `make package` | Build Nexus-ready `BetterBots.zip` |
| `make release VERSION=X.Y.Z` | patch-check-refresh + check + package + tag + push + upload ZIP |
| `make tool-info` | Print which tool binaries and fallbacks will run |

CI runs `make check-ci` on every push to `main` and every PR. Patch-day validation (`make patch-check-refresh`) is intentionally separate: it requires the decompiled source checkout to be present.

## Development workflow

### Editing code

- Lua 5.1 / LuaJIT target. Tabs for indentation (width 4). 120-char line limit. `snake_case` for locals and filenames. `PascalCase` for class/module names.
- Run `make format` before committing (the hook does not auto-format). StyLua diffs are the #1 repeated review finding.
- Follow Conventional Commits: `type(scope): description`. Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`. The commit-msg hook validates this locally; CI also checks on PRs.

### Tests

All new features and fixes should ship with busted coverage under `tests/`. The suite runs offline against stubbed engine globals; there is no Darktide runtime in CI.

- `tests/test_helper.lua` and per-spec `before_each` hooks set up the fake engine. Before inventing new fields on existing stubs, cross-check the decompiled source — `docs/dev/mock-api-audit.md` tracks known mock/real drift.
- Prefer one red-green cycle per behavior. The codebase has a strong TDD pattern; batching multiple changes before a green run hides bugs.

### Patch-day workflow

Darktide patches regularly break hook anchors. The repo keeps a manual link to a decompiled-source checkout (the maintainer uses `../Darktide-Source-Code`) and `make patch-check` validates that every anchor BetterBots hooks is still present with the expected surrounding context.

When a patch lands:

1. `make patch-check-refresh` — pulls the decompiled source and re-runs the anchor validator.
2. If it fails, the failing anchor will tell you which hook needs updating and where.
3. Update the hook, re-run `make check-ci`, then validate in-game before releasing.

### Live validation

The mod ships with structured diagnostics for post-mission analysis:

- **`bb-log`** (repo root) — CLI over `event_log.jsonl` and console logs. Use this first, not raw `grep`. Key commands: `./bb-log summary 0`, `./bb-log warnings 0`, `./bb-log raw <pattern> 0` where `0` is "most recent log".
- **`/bb_state`, `/bb_decide`, `/bb_brain`** — in-game chat commands that dump bot decision state.
- **`/bb_perf`** — per-hook runtime recorder. Mission-end totals are the documented benchmark metric.
- **JSONL event log** — toggle in settings; authoritative for smite/assail/chain-grenade validation because bb-log's `consumes` view is profile-dependent.

[`docs/dev/debugging.md`](docs/dev/debugging.md) and [`docs/dev/logging.md`](docs/dev/logging.md) have the full reference.

### Per-bot logging discipline

`_debug_log(key, ...)` deduplicates by key. Any log line that can fire per-bot **must** include the bot's unit in the key or multi-bot events will silently collapse to one. See grep results for existing patterns (`"foo:" .. tostring(_scratchpad_player_unit(scratchpad))`).

## Release process

Releases are cut from `main` after merging the sprint branch. `make release` automates most of it.

### Pre-release checks

1. `make check-ci` on the integration branch.
2. Run one or more Solo Play missions and confirm `bb-log summary 0` shows no new errors or warnings.
3. For features touching weapon behavior, explicitly validate both mod load orders (BetterBots-first and BetterBots-last in `mod_load_order.txt`). Some regressions only reproduce with a specific order.
4. Run `make patch-check` if any Darktide patch landed since the last release.

### Cutting the release

```bash
git checkout main
git merge --no-ff dev/vX.Y.Z -m "Merge dev/vX.Y.Z into main for vX.Y.Z release"
make release VERSION=X.Y.Z
```

`make release` runs `scripts/release.sh`, which in turn:

1. Requires a clean working tree.
2. Runs `make patch-check-refresh`.
3. Runs `make check`.
4. Fails if `make check` produced formatter diffs (commit them and re-run).
5. Builds `BetterBots.zip` via `make package`.
6. Tags `vX.Y.Z` locally and pushes the commit + tag.
7. Waits for CI to publish the GitHub release and attach the ZIP.

### Nexus upload

`make release` stops at GitHub. Nexus is manual. Every release needs **all four** of these fields updated — this is a frequent miss:

1. **Brief overview** (≤350 chars, plain text, shown in search results).
2. **File description** (≤255 chars, plain text). Format: `vX.Y.Z: <feature1>, <feature2>, ...`.
3. **Changelog** — use Nexus's "Separate text fields" form. Version column is `X.Y.Z` (no `v` prefix — Nexus natural-sorts). One change per row.
4. **Mod page description** — [`docs/nexus-description.bbcode`](docs/nexus-description.bbcode). Update the "New in vX.Y.Z" section and the "What I want to fix next" list before each release; commit to `main`, then paste the file contents into Nexus's Description tab.

### Hotfixes

Same flow from a `dev/vX.Y.Z` patch branch. Tag bumps follow semver: feature additions are minor, fixes are patch, and user-visible behavior breaks are major.

## Repository layout

```text
BetterBots.mod                    # DMF entry point
bb-log                            # Log analysis CLI (use first, not raw grep)
scripts/mods/BetterBots/          # Mod source
  BetterBots.lua                  #   Orchestrator: init, module wiring, BT hooks
  bootstrap.lua                   #   Module loading, initialization, and cross-module wiring
  condition_patch.lua             #   BT condition evaluation + vent hysteresis + DH suppression
  ability_queue.lua               #   Fallback combat ability activation (Tier 1/2)
  charge_tracker.lua              #   use_ability_charge dispatch, team cooldown, fallback completion
  combat_ability_identity.lua     #   Semantic ability identity (shout vs stance, etc.)
  heuristics.lua                  #   Thin public API + dispatcher for split heuristic modules
  heuristics_context.lua          #   Shared context builder + target/breed helpers
  heuristics_veteran.lua          #   Veteran ability heuristics
  heuristics_zealot.lua           #   Zealot ability heuristics
  heuristics_psyker.lua           #   Psyker ability heuristics
  heuristics_ogryn.lua            #   Ogryn ability heuristics
  heuristics_arbites.lua          #   Arbites ability heuristics
  heuristics_hive_scum.lua        #   Hive Scum ability heuristics
  heuristics_grenade.lua          #   Grenade/blitz tactical evaluators
  meta_data.lua                   #   ability_meta_data injection at load time
  gestalt_injector.lua            #   Default bot_gestalts injection for ADS-capable profiles
  item_fallback.lua               #   Tier 3 item wield/use/unwield state machine
  item_profiles.lua               #   Tier 3 item input profiles and profile rotation
  grenade_fallback.lua            #   Grenade throw state machine (wield/aim/throw/unwield)
  grenade_profiles.lua            #   Grenade/blitz input profiles and Assail profile selection
  grenade_aim.lua                 #   Grenade target resolution, LOS checks, and ballistic aim
  grenade_runtime.lua             #   Grenade context, state reset, locks, queueing, and events
  update_dispatcher.lua           #   BotBehaviorExtension.update dispatcher ordering and gating
  scenario_harness.lua            #   /bb_scenario scripted validation spawns + JSONL markers
  hazard_avoidance.lua            #   Fused-barrel / vanilla AoE avoidance diagnostics
  settings.lua                    #   Presets, category/feature gates, slider readers
  bot_profile_templates.lua       #   Authored bot class loadout/talent templates
  bot_profiles.lua                #   Bot-optimized class profiles per slot
  bot_targeting.lua               #   Shared perception target resolver + helpers
  charge_nav_validation.lua       #   Shared navmesh launch validation for charge/dash abilities (#13)
  sprint.lua                      #   Bot sprint injection (catch-up, rescue, traversal)
  target_selection.lua            #   Player tag boost, special chase penalty, boss engagement
  target_type_hysteresis.lua     #   Perception-layer melee/ranged type stabilization
  weakspot_aim.lua                #   Per-breed ranged aim-node override (#92)
  melee_meta_data.lua             #   Armor-aware melee attack_meta_data injection
  melee_attack_choice.lua         #   Melee attack-choice: light bias into unarmored hordes
  ranged_meta_data.lua            #   Per-family ranged attack_meta_data injection
  weapon_action.lua               #   Weapon-action hook owner: overheat, vent, peril, ADS, queue rewrites
  weapon_action_logging.lua       #   Weapon-action debug contexts and one-shot queue logging
  weapon_action_shoot.lua         #   BT shoot scratchpad normalization and stale/plasma diagnostics
  weapon_action_voidblast.lua     #   Voidblast charged-shot anchor and forced charged release helpers
  ranged_special_action.lua       #   Shotgun special-shell preload policy + arm/spend logging
  sustained_fire.lua              #   Held-input bridge for sustained-fire ranged weapons
  ping_system.lua                 #   Bot elite/special pinging
  companion_tag.lua               #   Arbites Cyber-Mastiff companion-command smart tag
  smart_targeting.lua             #   Precision blitz target seeding from perception
  poxburster.lua                  #   Poxburster targeting + close-range suppression
  human_likeness.lua              #   Tier A teammate-feel tuning
  engagement_leash.lua            #   Coherency-anchored melee engagement range
  healing_deferral.lua            #   Defer health stations/med-crates to humans
  ammo_policy.lua                 #   Bot ammo + grenade pickup policy
  com_wheel_response.lua          #   Communication-wheel aggression/resource overrides
  mule_pickup.lua                 #   Book mule pickup + grimoire opt-in guard
  pocketable_pickup.lua           #   Pocketable carry policy + stim/crate use/deploy
  smart_tag_orders.lua            #   Explicit smart-tag pickup-order bridge
  team_cooldown.lua               #   Team-level ability cooldown staggering
  revive_ability.lua              #   Pre-revive defensive ability activation + human-revive priority
  vfx_suppression.lua             #   Bot VFX/SFX bleed suppression
  animation_guard.lua             #   Animation crash guard for bot-only item paths
  airlock_guard.lua               #   Airlock teleport crash guard
  event_log.lua                   #   Structured JSONL event logging
  debug.lua                       #   Debug commands (/bb_state, /bb_decide, /bb_brain)
  log_levels.lua                  #   Tiered debug log level constants
  perf.lua                        #   Per-hook runtime recorder + /bb_perf
  shared_rules.lua                #   Shared rule tables (daemonhost breeds, rescue charges)
  BetterBots_data.lua             #   Mod options / widget definitions
  BetterBots_localization.lua     #   Display strings
tests/                            # Unit tests (busted) — offline, stubbed engine
scripts/hooks/                    # Git hooks (Conventional Commits)
scripts/release.sh                # Release automation (see "Release process")
scripts/doc-check/                # Doc-invariant validator (make doc-check)
docs/                             # Architecture, class refs, status, roadmap, validation tracker
.github/
  workflows/                      # CI, release, label sync
  ISSUE_TEMPLATE/                 # Bug report, feature request
  CONTRIBUTING.md                 # Contributor-specific guidelines (this file covers setup)
  PULL_REQUEST_TEMPLATE.md
  labels.yml                      # Issue labels (auto-synced)
  dependabot.yml                  # GH Actions auto-updates
```

## Key documents

**Start here:**
- [Architecture](docs/dev/architecture.md) — module boundaries, data flow, hook ordering
- [Status Snapshot](docs/dev/status.md) — what's shipped, what's pending, per-issue state
- [Roadmap](docs/dev/roadmap.md) — sprint history + post-1.0 backlog
- [Known Issues and Risks](docs/dev/known-issues.md)

**While working:**
- [Debugging and Testing](docs/dev/debugging.md)
- [Logging and Diagnostics](docs/dev/logging.md)
- [Manual Test Plan](docs/dev/test-plan.md)
- [Validation Tracker](docs/dev/validation-tracker.md) — per-issue live-log evidence
- [Mock API Audit](docs/dev/mock-api-audit.md) — known drift between test stubs and decompiled source

**Bot system internals (reverse-engineered from decompiled source):**
- [Behavior Tree](docs/bot/behavior-tree.md) — full node hierarchy and conditions
- [Combat Actions](docs/bot/combat-actions.md) — melee, shoot, ability activation
- [Perception and Targeting](docs/bot/perception-targeting.md) — scoring, gestalt weights
- [Navigation](docs/bot/navigation.md) — pathfinding, follow, teleport, formation
- [Input System](docs/bot/input-system.md) — input routing, ActionInputParser
- [Profiles and Spawning](docs/bot/profiles-spawning.md) — loadouts, weapon templates
- [Vanilla Capabilities](docs/bot/vanilla-capabilities.md) — what stock bots can and can't do

**Class references** (internal template names, input actions, cooldowns, talent interactions, per-class tactics):
- [Veteran](docs/classes/veteran.md) · [Tactics](docs/classes/veteran-tactics.md)
- [Zealot](docs/classes/zealot.md) · [Tactics](docs/classes/zealot-tactics.md)
- [Psyker](docs/classes/psyker.md) · [Tactics](docs/classes/psyker-tactics.md)
- [Ogryn](docs/classes/ogryn.md) · [Tactics](docs/classes/ogryn-tactics.md)
- [Arbites](docs/classes/arbites.md) (DLC) · [Tactics](docs/classes/arbites-tactics.md)
- [Hive Scum](docs/classes/hive-scum.md) (DLC) · [Tactics](docs/classes/hive-scum-tactics.md)

## Gotchas

- **Mods are disabled every patch.** Re-run the toggle/patch script after every Darktide update.
- **Tertium 5 can crash** on Arbites/Hive Scum archetypes; Tertium 6 supports all six classes. Both are optional — without either, vanilla bots are all veterans.
- **Decompiled source drift.** The decompiled-source checkout is the source of truth for engine anchors. `make patch-check-refresh` validates it; if you invent fields on existing stubs in tests, cross-check against the real source first (`docs/dev/mock-api-audit.md` tracks known drift).
- **DMF hot-reload.** Anything installed via `mod:hook`/`mod:hook_require` must be idempotent. Use sentinel guards attached to the engine class, not module-local, so state survives hot-reload.
- **`fassert` is a no-op.** Engine `fassert(...)` computes the error message then returns. Use `if <condition> then error(...) end` for actual runtime guards.
- **Per-bot log keys.** `_debug_log(key, ...)` deduplicates by key. Any per-bot event must include the bot unit in the key or multi-bot events silently collapse.
- **`grenade_fallback` parallels the BT.** BT condition wrappers do not cover the grenade/blitz fallback path. Guards must be duplicated when adding new gates.
- **Mock/real drift in tests.** `tests/test_helper.lua` stubs the engine. Before inventing new fields on a stub, verify the field exists in the decompiled source — invented fields can hide dead features.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for contributor-side process notes (PR flow, issue-first convention, review expectations). This README covers setup.

**Good entry points for new contributors:**

- Pick up a [post-1.0 issue](https://github.com/hummat/BetterBots/issues?q=is%3Aopen+label%3Apost-1.0) if you want significant work. The bucket is explicitly open-ended.
- Validate [`#17`](https://github.com/hummat/BetterBots/issues/17) (dormant daemonhost suppression) with a Solo Play log showing a pre-aggro daemonhost.
- Hive Scum validation — if you own the DLC, run a Solo Play session with a Hive Scum bot and report back.
- Performance — the v1.0 target (median ≤125 µs/bot/frame, no single run > 140) is currently missed. `ability_queue` and `grenade_fallback` are the top costs.

**Review cadence:** best-effort. Forks are fine. If activity resumes, it will show up in `docs/dev/status.md`.

## License

[MIT](LICENSE)
