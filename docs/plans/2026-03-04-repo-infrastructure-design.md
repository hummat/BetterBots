# Repo Infrastructure Design

Date: 2026-03-04

## Goal

Add CI/CD, conventional commits, release automation, issue/PR templates, and repo hygiene files to BetterBots, adapted from the pytemplate reference.

## Components

### GitHub Actions CI (`.github/workflows/ci.yml`)

Triggers: push to `main`, pull requests.

Jobs:
- **commit-lint**: Validate PR commits against Conventional Commits (`feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`, `revert`, `style`, `build`).
- **check**: Install luacheck, stylua, lua-language-server on Ubuntu runner. Run `make check`.

Tool installation: luacheck via luarocks, stylua and lua-language-server from GitHub releases (pinned versions).

### Release workflow (`.github/workflows/release.yml`)

Trigger: tag push matching `v[0-9]+.*`.
Steps: generate changelog via git-cliff, create GitHub Release with changelog body.

### Label sync (`.github/workflows/sync-labels.yml`)

Auto-sync `.github/labels.yml` on changes to that file. Labels include standard triage labels plus mod-specific ones (`class:veteran`, `class:zealot`, etc.).

### Conventional Commits

- Local `scripts/hooks/commit-msg` validates commit messages before commit.
- `make deps` sets `core.hooksPath` to `scripts/hooks`.
- CI commit-lint provides redundant server-side validation.

### Makefile additions

- `deps`: Install git hooks (tooling assumed pre-installed locally).
- `release`: Delegate to `scripts/release.sh` (validate clean tree, run `make check`, tag, push).

Existing targets unchanged.

### Issue & PR templates

- Bug report (`ISSUE_TEMPLATE/bug_report.yml`): game version, class, steps, expected/actual, logs.
- Feature request (`ISSUE_TEMPLATE/feature_request.yml`): class/ability, description, alternatives.
- PR template: summary, changes, testing checklist.

### Other files

- `LICENSE` (MIT)
- `.editorconfig` (tabs, Lua conventions)
- `.github/dependabot.yml` (monthly GH Actions updates)
- `cliff.toml` (git-cliff changelog config)
- `.github/CONTRIBUTING.md` (lightweight guide)

## Out of scope

- Automated game tests (engine-only runtime)
- Build/dist artifacts
- Package publishing
- Changes to existing linting configs
