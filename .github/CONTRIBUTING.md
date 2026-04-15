# Contributing to BetterBots

Thanks for your interest in contributing! This document covers development setup and guidelines.

## Development Setup

### Prerequisites

- Lua 5.1 / LuaJIT
- [luacheck](https://github.com/mpeterv/luacheck)
- [StyLua](https://github.com/JohnnyMorganz/StyLua)
- [lua-language-server](https://github.com/LuaLS/lua-language-server)
- Darktide with [DMF](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework), [SoloPlay](https://www.nexusmods.com/warhammer40kdarktide/mods/1), and [Tertium4Or5](https://www.nexusmods.com/warhammer40kdarktide/mods/24)

### Quick Start

```bash
git clone https://github.com/hummat/BetterBots.git
cd BetterBots

# Install git hooks
make deps

# Run all checks
make check
```

The repo does not edit your shell `PATH`. Use `make tool-info` to see the exact
tool paths and fallbacks the Make targets will use locally.

### Available Make Targets

| Target | Description |
|--------|-------------|
| `make deps` | Install git hooks |
| `make lint` | Run luacheck |
| `make format` | Format with StyLua |
| `make format-check` | Check formatting (dry run) |
| `make lsp-check` | Run lua-language-server diagnostics |
| `make check` | Run all of the above |
| `make test` | Run busted tests (if tests/ exists) |
| `make tool-info` | Show which tool binaries and fallbacks will run |
| `make release` | Tag and push a release |

### Tool Resolution

- `make lint` always uses `./bin/luacheck`, which keeps luacheck on a working Lua runtime.
- `make test` tries `busted`, then `lua-busted`, then Arch's packaged
  `/usr/lib/luarocks/.../busted` runner.
- `make tool-info` prints the exact paths and fallbacks used by the Makefile.

## Code Style

- Lua 5.1 / LuaJIT target
- Tabs for indentation (width 4)
- 120-character line limit
- `snake_case` for locals and filenames
- `PascalCase` for class/module names
- Run `make format` before committing

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

feat: add Zealot dash ability support
fix(ogryn): correct charge meta_data timing
docs: update class reference for Psyker
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`

The commit-msg hook validates this locally; CI also checks on PRs.

## Pull Request Process

1. **Create an issue first** for non-trivial changes
2. **Fork and branch** from `main`
3. **Make your changes** following the style guide
4. **Run `make check`** — all checks must pass
5. **Test in-game** with SoloPlay + Tertium4Or5 if changing bot behavior
6. **Submit PR** using the template
