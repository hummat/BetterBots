# Repo Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add CI/CD, conventional commits, release automation, issue/PR templates, and repo hygiene to BetterBots.

**Architecture:** Adapt pytemplate's GitHub-centric infrastructure for a Lua game mod. CI runs luacheck/stylua/lua-language-server. Releases via git-cliff changelog on tag push. Conventional commits enforced locally and in CI.

**Tech Stack:** GitHub Actions, luacheck, stylua, lua-language-server, git-cliff, shell scripts

---

### Task 1: LICENSE file

**Files:**
- Create: `LICENSE`

**Step 1:** Write MIT license with copyright holder `Matthias Humt`.

**Step 2:** Commit: `docs: add MIT license`

---

### Task 2: .editorconfig

**Files:**
- Create: `.editorconfig`

**Step 1:** Write editorconfig matching existing conventions: tabs, indent_size=4, 120 char line length, LF line endings, UTF-8, trim trailing whitespace, final newline. Lua and Makefile sections.

**Step 2:** Commit: `chore: add .editorconfig`

---

### Task 3: Conventional commit hook

**Files:**
- Create: `scripts/hooks/commit-msg`
- Modify: `Makefile`

**Step 1:** Copy pytemplate's `scripts/hooks/commit-msg` (works as-is — shell-only, no Python dependency).

**Step 2:** Add `deps` target to Makefile: `git config core.hooksPath scripts/hooks`.

**Step 3:** Commit: `chore: add conventional commit hook and deps target`

---

### Task 4: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1:** Write CI workflow with two jobs:
- `commit-lint`: Same as pytemplate (PR-only, validate conventional commits).
- `check`: Install luacheck via luarocks, stylua via GitHub release, lua-language-server via GitHub release. Run `make check`.

**Step 2:** Commit: `ci: add CI workflow with linting and commit validation`

---

### Task 5: Release workflow + cliff.toml

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `cliff.toml`

**Step 1:** Write release workflow (same as pytemplate — tag trigger, git-cliff changelog, GitHub release).

**Step 2:** Write `cliff.toml` adapted for `hummat/BetterBots`.

**Step 3:** Commit: `ci: add release workflow with git-cliff changelog`

---

### Task 6: Release script

**Files:**
- Create: `scripts/release.sh`
- Modify: `Makefile`

**Step 1:** Write `scripts/release.sh` adapted for BetterBots. No pyproject.toml — version comes from BetterBots.mod or a VERSION file. Runs `make check`, tags, pushes.

**Step 2:** Add `release` target to Makefile.

**Step 3:** Commit: `chore: add release script and Makefile target`

---

### Task 7: Labels + sync workflow

**Files:**
- Create: `.github/labels.yml`
- Create: `.github/workflows/sync-labels.yml`

**Step 1:** Write labels.yml with standard labels plus mod-specific: `class:veteran`, `class:zealot`, `class:psyker`, `class:ogryn`, `class:arbites`, `class:hive-scum`, `tier:1`, `tier:2`, `tier:3`.

**Step 2:** Write sync-labels workflow (same as pytemplate).

**Step 3:** Commit: `ci: add label definitions and sync workflow`

---

### Task 8: Issue templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`

**Step 1:** Write bug report template: description, reproduction steps, game version, class played, OS, logs, duplicate check.

**Step 2:** Write feature request template: class/ability, description, alternatives, contribution willingness.

**Step 3:** Write config.yml pointing to Discussions.

**Step 4:** Commit: `docs: add issue templates`

---

### Task 9: PR template + contributing guide

**Files:**
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `.github/CONTRIBUTING.md`

**Step 1:** Write PR template adapted for mod development: summary, changes, type of change, testing (make check + in-game verification), checklist.

**Step 2:** Write CONTRIBUTING.md: prerequisites (Lua 5.1, luacheck, stylua, lua-language-server), quick start, code style, commit conventions, PR process.

**Step 3:** Commit: `docs: add PR template and contributing guide`

---

### Task 10: Dependabot

**Files:**
- Create: `.github/dependabot.yml`

**Step 1:** Write dependabot config for monthly GitHub Actions updates (same as pytemplate).

**Step 2:** Commit: `ci: add dependabot for GitHub Actions`

---

### Task 11: Update .gitignore

**Files:**
- Modify: `.gitignore`

**Step 1:** Add common entries: `/tmp/`, `*.log`, agent symlinks pattern.

**Step 2:** Commit: `chore: update .gitignore`
