# BetterBots

[![CI](https://github.com/hummat/BetterBots/actions/workflows/ci.yml/badge.svg)](https://github.com/hummat/BetterBots/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework) mod that enables bot combat abilities in Solo Play by patching the vanilla whitelist, injecting missing bot metadata, and adding an item-based fallback path.

## Current status (March 4, 2026)

- Template-path casts are confirmed in live logs for Veteran, Ogryn, and Zealot.
- Tier 2 templates use template-specific metadata (`aim_pressed`/`shout_pressed`, `wait_action`, `min_hold_time`).
- Item fallback is implemented and works for some cases, but remains experimental (Psyker force-field is mixed post-reload in the newest run).
- Grenade abilities are still out of scope.

See [Status Snapshot](docs/STATUS.md) for exact evidence from the latest log.

## Requirements

- [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)
- [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)
- [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176)
- [Tertium 5](https://www.nexusmods.com/warhammer40kdarktide/mods/183) (recommended)

## Install

1. Clone or copy this repo to your Darktide mods directory as `mods/BetterBots`.
2. Add `BetterBots` in `mods/mod_load_order.txt` below `dmf`.
3. Re-patch mods with `toggle_darktide_mods.bat` (Windows) or `handle_darktide_mods.sh` (Linux).

Mods are disabled after each game update, so re-patching is required again.

## Quick verification

1. Launch Solo Play.
2. Start a mission (`/solo`).
3. Confirm startup output:
   - `BetterBots loaded`
   - `BetterBots: injected meta_data for ...` (for each injected template)
4. Confirm runtime debug output includes either:
   - template path logs (`decision ...`, `fallback queued ...`), or
   - item path logs (`fallback item queued ...`).
5. Confirm at least one `charge consumed for ...` line during combat.

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
| `make release VERSION=X.Y.Z` | Tag and push a release |

After cloning, run `make deps` to install the commit-msg hook.

CI runs `make check` on every push to `main` and on pull requests.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for development setup, code style, and PR process.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Status Snapshot](docs/STATUS.md)
- [Known Issues and Risks](docs/KNOWN_ISSUES.md)
- [Logging and Diagnostics](docs/LOGGING.md)
- [Manual Test Plan](docs/TEST_PLAN.md)
- [Roadmap](docs/ROADMAP.md)

### Class ability references

Per-class docs with internal template names, input actions, cooldowns, talent interactions, and bot implementation notes:

- [Veteran](docs/CLASS_VETERAN.md)
- [Zealot](docs/CLASS_ZEALOT.md)
- [Psyker](docs/CLASS_PSYKER.md)
- [Ogryn](docs/CLASS_OGRYN.md)
- [Arbites](docs/CLASS_ARBITES.md) (DLC)
- [Hive Scum](docs/CLASS_HIVE_SCUM.md) (DLC)

## Repository layout

```text
BetterBots.mod                    # DMF entry point
scripts/mods/BetterBots/          # Mod source
  BetterBots.lua
  BetterBots_data.lua
  BetterBots_localization.lua
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
