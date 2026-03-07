# BetterBots

[![CI](https://github.com/hummat/BetterBots/actions/workflows/ci.yml/badge.svg)](https://github.com/hummat/BetterBots/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![Nexus Mods](https://img.shields.io/badge/Nexus-BetterBots-orange)](https://www.nexusmods.com/warhammer40kdarktide/mods/745)

A [Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework) mod that enables bot combat abilities in Solo Play. Aims to bring VT2-level bot ability usage to Darktide.

Darktide has a complete bot ability system built into the behavior tree, but Fatshark hardcoded a whitelist that only allows two abilities. This mod removes that gate and injects missing metadata so the existing infrastructure handles the rest.

> **Solo Play only.** Darktide uses dedicated servers — mods cannot affect gameplay on Fatshark's servers. This mod only works when you host locally via the [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176) mod. It does **not** work in public matchmaking or any other online mode.

## What bots can do with this mod

**Stance abilities (reliable):**
- Veteran: Executioner's Stance / Voice of Command
- Psyker: Scrier's Gaze
- Ogryn: Point-Blank Barrage
- Arbites: Castigator's Stance
- Hive Scum: Enhanced Desperado / Rampage

**Dash / shout / stealth abilities (reliable):**
- Veteran: Infiltrate (stealth)
- Zealot: Fury of the Faithful (dash), Shroudfield (stealth)
- Ogryn: Bull Rush (charge), Loyal Protector (taunt)
- Psyker: Venting Shriek (shout)
- Arbites: Break the Line (charge)

**Item-based abilities (experimental):**
- Zealot: Bolstering Prayer (relic) — works well
- Psyker: Telekine Shield — works sometimes
- Arbites: Nuncio-Aquila — works sometimes

**Smart trigger conditions (new in v0.2.0):**
Bots use per-ability heuristics to decide when to activate — based on enemy count, threat level, health/toughness, distance, and ally state. 12 of 13 ability-specific trigger functions validated in-game.

## What doesn't work yet

- Grenades / blitz abilities (different architecture needed)
- Hive Scum: Stimm Field (item-based, same challenge as above)

See [Status Snapshot](docs/STATUS.md) and [Validation Tracker](docs/VALIDATION_TRACKER.md) for detailed evidence.

## Requirements

- [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)
- [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)
- [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176)
- [Tertium 5](https://www.nexusmods.com/warhammer40kdarktide/mods/183) or [Tertium 6](https://www.nexusmods.com/warhammer40kdarktide/mods/725) (recommended — for non-veteran bot classes)

## Install

**From Nexus (recommended):**
1. Extract `BetterBots.zip` into your Darktide `mods/` folder.
2. Add `BetterBots` in `mods/mod_load_order.txt` below `dmf`.
3. Re-patch mods with `toggle_darktide_mods.bat` (Windows) or `handle_darktide_mods.sh` (Linux).

**From source:**
1. Clone or copy this repo into your Darktide `mods/` directory as `mods/BetterBots`.
2. Add `BetterBots` in `mods/mod_load_order.txt` below `dmf`.
3. Re-patch mods.

Mods are disabled after each game update, so re-patching is required again.

## Quick verification

1. Launch Solo Play.
2. Start a mission (`/solo`).
3. Confirm in game chat:
   - `BetterBots loaded`
   - `BetterBots: injected meta_data for ...` (one line per injected template)

## Companion mod compatibility

BetterBots works standalone (vanilla bots are all veterans), but bot class diversity requires a Tertium mod.

**Tertium 5** — the original. Some versions crash when encountering Arbites/Hive Scum archetypes it doesn't recognize.

**Tertium 6 (temporary)** — a fork by KristopherPrime that supports all 6 classes and player + 5 bots. If Tertium 5's crash affects you, try Tertium 6 instead.

Both are optional/recommended, not hard-required.

## Developer tooling

This repo is configured for local Lua lint/format/type diagnostics:

- `luacheck` via `.luacheckrc`
- `stylua` via `.stylua.toml`
- `lua-language-server` diagnostics via `.luarc.json`

Commands:

| Target | Description |
|--------|-------------|
| `make deps` | Install git hooks (conventional commits) |
| `make lint` | Run luacheck |
| `make format` | Format with StyLua |
| `make format-check` | Check formatting (dry run) |
| `make lsp-check` | Run lua-language-server diagnostics |
| `make check` | Run all of the above |
| `make test` | Run busted tests (if `tests/` exists) |
| `make package` | Build Nexus-ready `BetterBots.zip` |
| `make release VERSION=X.Y.Z` | Check + package + tag + push + upload ZIP |

After cloning, run `make deps` to install the commit-msg hook.

CI runs `make check` on every push to `main` and on pull requests.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for development setup, code style, and PR process.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Status Snapshot](docs/STATUS.md)
- [Known Issues and Risks](docs/KNOWN_ISSUES.md)
- [Debugging and Testing](docs/DEBUGGING.md)
- [Logging and Diagnostics](docs/LOGGING.md)
- [Manual Test Plan](docs/TEST_PLAN.md)
- [Roadmap](docs/ROADMAP.md)
- [Validation Tracker](docs/VALIDATION_TRACKER.md)
- [Related Mods](docs/RELATED_MODS.md)
- [Meta Builds Research](docs/META_BUILDS_RESEARCH.md)

### Bot system internals (from decompiled source)

- [Behavior Tree](docs/BOT_BEHAVIOR_TREE.md) — full node hierarchy and conditions
- [Combat Actions](docs/BOT_COMBAT_ACTIONS.md) — melee, shoot, ability activation
- [Perception and Targeting](docs/BOT_PERCEPTION_TARGETING.md) — scoring, gestalt weights
- [Navigation](docs/BOT_NAVIGATION.md) — pathfinding, follow, teleport, formation
- [Input System](docs/BOT_INPUT_SYSTEM.md) — input routing, ActionInputParser
- [Profiles and Spawning](docs/BOT_PROFILES_SPAWNING.md) — loadouts, weapon templates

### Class ability references

Per-class docs with internal template names, input actions, cooldowns, talent interactions, and bot implementation notes.
Each class also has a tactics doc with community-sourced heuristics for when/how to use each ability:

- [Veteran](docs/CLASS_VETERAN.md) | [Tactics](docs/CLASS_VETERAN_TACTICS.md)
- [Zealot](docs/CLASS_ZEALOT.md) | [Tactics](docs/CLASS_ZEALOT_TACTICS.md)
- [Psyker](docs/CLASS_PSYKER.md) | [Tactics](docs/CLASS_PSYKER_TACTICS.md)
- [Ogryn](docs/CLASS_OGRYN.md) | [Tactics](docs/CLASS_OGRYN_TACTICS.md)
- [Arbites](docs/CLASS_ARBITES.md) (DLC) | [Tactics](docs/CLASS_ARBITES_TACTICS.md)
- [Hive Scum](docs/CLASS_HIVE_SCUM.md) (DLC) | [Tactics](docs/CLASS_HIVE_SCUM_TACTICS.md)

## Repository layout

```text
BetterBots.mod                    # DMF entry point
scripts/mods/BetterBots/          # Mod source
  BetterBots.lua                  #   Main: hooks, condition patch, fallback queue
  heuristics.lua                  #   13 per-ability trigger functions + context builder
  meta_data.lua                   #   ability_meta_data injection at load time
  item_fallback.lua               #   Tier 3 item wield/use/unwield state machine
  debug.lua                       #   Debug commands (/bb_state, /bb_decide, /bb_brain)
  BetterBots_data.lua             #   Mod options / widget definitions
  BetterBots_localization.lua     #   Display strings
tests/                            # Unit tests (busted)
bb-log                            # Log analysis CLI
scripts/hooks/                    # Git hooks (conventional commits)
scripts/release.sh                # Release automation
docs/                             # Architecture, class refs, status
.github/
  workflows/                      # CI, release, label sync
  ISSUE_TEMPLATE/                 # Bug report, feature request
  CONTRIBUTING.md                 # Dev setup + guidelines
  PULL_REQUEST_TEMPLATE.md
  labels.yml                      # Issue labels (auto-synced)
  dependabot.yml                  # GH Actions auto-updates
```

## License

[MIT](LICENSE)
