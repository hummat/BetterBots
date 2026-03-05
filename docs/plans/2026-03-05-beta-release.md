# Beta Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship BetterBots v0.1.0-beta.1 to Nexus Mods as a first public beta.

**Architecture:** Commit all pending work, add a `make package` target that builds a Nexus-ready ZIP containing only mod runtime files, close resolved issues, tag, and release.

**Tech Stack:** Make, zip, git, gh CLI, git-cliff

---

### Task 1: Add `make package` target

**Files:**
- Modify: `Makefile`

**Step 1: Add the target**

Append to `Makefile`:

```makefile
PACKAGE_NAME := BetterBots
PACKAGE_FILES := BetterBots.mod scripts/mods/BetterBots/BetterBots.lua \
	scripts/mods/BetterBots/BetterBots_data.lua \
	scripts/mods/BetterBots/BetterBots_localization.lua

package:
	@rm -f $(PACKAGE_NAME).zip
	zip -j9 $(PACKAGE_NAME).zip $(PACKAGE_FILES)
	@echo "Created $(PACKAGE_NAME).zip"
	@unzip -l $(PACKAGE_NAME).zip
```

Wait -- Nexus Darktide mods expect the folder structure preserved inside the ZIP:
```
BetterBots/
  BetterBots.mod
  scripts/mods/BetterBots/*.lua
```

Users extract into `mods/` so the folder must be `BetterBots/`. Since the git repo root IS the BetterBots directory (symlinked as `mods/BetterBots`), the ZIP must recreate that nesting.

Correct target:

```makefile
package:
	@rm -f BetterBots.zip
	@cd .. && zip -9 BetterBots/BetterBots.zip \
		BetterBots/BetterBots.mod \
		BetterBots/scripts/mods/BetterBots/BetterBots.lua \
		BetterBots/scripts/mods/BetterBots/BetterBots_data.lua \
		BetterBots/scripts/mods/BetterBots/BetterBots_localization.lua
	@echo "Created BetterBots.zip"
	@unzip -l BetterBots.zip
```

**Step 2: Test it**

Run: `make package && unzip -l BetterBots.zip`
Expected: ZIP contains 4 files under `BetterBots/` prefix.

---

### Task 2: Close issue #5

**Step 1: Verify flag is false**

Run: `grep DEBUG_FORCE_ENABLED scripts/mods/BetterBots/BetterBots.lua`
Expected: `local DEBUG_FORCE_ENABLED = false`

**Step 2: Close issue**

Run: `gh issue close 5 --comment "DEBUG_FORCE_ENABLED is already false in current code."`

---

### Task 3: Run static checks

Run: `make check`
Expected: All pass (luacheck, stylua, lua-language-server).

If stylua fails on agent-written doc files, those are .md not .lua — should be fine. If luacheck/lsp fails on BetterBots.lua edits from GPT-5, fix before committing.

---

### Task 4: Commit all pending changes

Three logical commits:

**Commit 1: Code + validation changes (from GPT-5 session)**
```
feat: tier 3 item-ability fallback and runtime hardening

- adamant_area_buff_drone sequence switch-lock
- force-field instant place followup
- timing/timeout tuning for item abilities
- validation tracker with ratio-based reliability metrics
```
Files: `scripts/mods/BetterBots/BetterBots.lua`, `docs/VALIDATION_TRACKER.md`, `docs/STATUS.md`, `docs/TEST_PLAN.md`, `README.md`, `HANDOFF.md`

**Commit 2: Class doc audit**
```
docs: audit class profiles against decompiled source v1.10.7

- Fix Ogryn swapped display names (Indomitable/Loyal Protector)
- Fix Arbites cut content misclassification (shout not in talent tree)
- Fix Zealot stealth-revive interaction (does break stealth)
- Fix Psyker Chain Lightning cooldown (Peril-gated, not 1s)
- Add missing talents, correct numerical values across all 6 classes
```
Files: `docs/CLASS_*.md`

**Commit 3: Bot system documentation**
```
docs: add bot system reference docs from decompiled source

- Behavior tree structure and conditions
- Combat action nodes (melee, shoot, ability activation)
- Perception and target selection scoring
- Navigation, movement, and formation
- Input system and action data pipeline
- Bot profiles, spawning, and group coordination
```
Files: `docs/BOT_*.md`

**Commit 4: Package target**
```
chore: add make package target for Nexus release ZIP
```
Files: `Makefile`

---

### Task 5: Fix git-cliff skip_tags for beta

**Files:**
- Modify: `cliff.toml`

The current config has `skip_tags = "beta|alpha"` which means a `v0.1.0-beta.1` tag would be skipped in changelog generation. Two options:

**Option A:** Tag as `v0.1.0` (no beta suffix), mark as pre-release on GitHub. Simpler.
**Option B:** Remove `skip_tags` line. Allows beta tags in changelog.

Recommend Option A — tag `v0.1.0`, set `--prerelease` flag on the GitHub release.

---

### Task 6: Tag and release

**Step 1: Run checks**
```bash
make check
```

**Step 2: Build package**
```bash
make package
```

**Step 3: Tag**
```bash
make release VERSION=0.1.0
```

This runs `make check`, creates annotated tag `v0.1.0`, pushes commit + tag. CI creates GitHub release with git-cliff changelog.

**Step 4: Attach ZIP to GitHub release**
```bash
gh release upload v0.1.0 BetterBots.zip
```

**Step 5: Mark as pre-release**
```bash
gh release edit v0.1.0 --prerelease --title "v0.1.0-beta — First public beta"
```

---

### Task 7: Nexus Mods page (manual)

Cannot be automated — web UI only for initial page creation.

1. Go to https://www.nexusmods.com/warhammer40kdarktide/mods/ → Add Mod
2. Category: Gameplay
3. Upload `BetterBots.zip`
4. Use release description (see below)

---

## Nexus Release Description (draft)

```markdown
# BetterBots — Bot Combat Abilities for Solo Play

Makes bots use their combat abilities (F key) in Solo Play. Darktide has a complete bot ability system built into the behavior tree, but Fatshark hardcoded a whitelist that only allows two abilities. This mod removes that gate and injects the missing metadata so the existing infrastructure handles the rest.

## What works

**Tier 1 — Stance abilities (reliable):**
- Veteran: Executioner's Stance / Voice of Command
- Psyker: Scrier's Gaze
- Ogryn: Point-Blank Barrage
- Arbites: Castigator's Stance
- Hive Scum: Enhanced Desperado / Rampage

**Tier 2 — Dash/shout/stealth abilities (reliable):**
- Veteran: Infiltrate (stealth)
- Zealot: Fury of the Faithful (dash), Shroudfield (stealth)
- Ogryn: Bull Rush (charge), Loyal Protector (taunt)
- Psyker: Venting Shriek (shout)
- Arbites: Break the Line (charge)

**Tier 3 — Item-based abilities (experimental):**
- Zealot: Bolstering Prayer (relic) — works well
- Psyker: Telekine Shield — works sometimes (~13% reliability)
- Arbites: Nuncio-Aquila — works sometimes (~21% reliability)

## What doesn't work yet

- Grenades / blitz abilities (different architecture needed)
- Hive Scum: Stimm Field (item-based, same Tier 3 challenge)
- Smart trigger conditions (bots currently use abilities whenever enemies are nearby and cooldown is ready)

## Requirements

- [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)
- [Darktide Mod Framework (DMF)](https://www.nexusmods.com/warhammer40kdarktide/mods/8)
- [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176)
- [Tertium 5](https://www.nexusmods.com/warhammer40kdarktide/mods/183) — recommended for non-veteran bot classes

## Install

1. Extract `BetterBots.zip` into your Darktide `mods/` folder
2. Add `BetterBots` to `mods/mod_load_order.txt` (below `dmf`)
3. Re-patch mods

## Verify

Look for `BetterBots loaded` and `injected meta_data for ...` in game chat on mission start.

## Known limitations

- Abilities fire whenever enemies are nearby — no per-career smart heuristics yet
- Tier 3 item abilities (force field, drone) have low success rates in sustained combat
- Mods are disabled after every Darktide update — re-patch required
- Hive Scum abilities are untested (DLC required)

## Source

[GitHub](https://github.com/hummat/BetterBots) — MIT License
```
