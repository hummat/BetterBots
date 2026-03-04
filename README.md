# BetterBots

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

- `make lint`
- `make format`
- `make format-check`
- `make lsp-check`
- `make check`

Notes:

- `make test` auto-detects a busted runner (`busted`, `lua-busted`, or Arch's packaged luarocks path).
- `make test` runs only if a `tests/` directory exists.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Status Snapshot](docs/STATUS.md)
- [Known Issues and Risks](docs/KNOWN_ISSUES.md)
- [Logging and Diagnostics](docs/LOGGING.md)
- [Manual Test Plan](docs/TEST_PLAN.md)
- [Roadmap](docs/ROADMAP.md)

## Repository layout

```text
BetterBots.mod
scripts/mods/BetterBots/
  BetterBots.lua
  BetterBots_data.lua
  BetterBots_localization.lua
docs/
  ARCHITECTURE.md
  STATUS.md
  LOGGING.md
  KNOWN_ISSUES.md
  ROADMAP.md
  TEST_PLAN.md
```
