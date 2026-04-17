# v1.0.0 Test Harness & Release-Safety Fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementation should be delegated to Codex via `mcp__codex__codex` with `approval-policy: "never"` and `sandbox: "workspace-write"`.

**Goal:** Close the nine converged blockers from the 3-way audit (Claude 4-agent synthesis + Codex reviewer + Codex independent) so v1.0.0 can tag with confidence that CI/release gates actually gate, the mod's own entry points are behaviorally tested, and the mock audit is enforced for every audited engine family.

**Architecture:** Three sequenced phases, each landing in its own commit:
1. **Tooling & release-safety** — dead doc-check paths, unsafe release ordering, missing CI gate on release workflow, non-hermetic lsp-check.
2. **Entrypoint + critical-path behavioral tests** — the `BetterBots.lua` inline hook bodies (`use_ability_charge`, `ActionCharacterStateChange.finish`, gestalt injection, behavior update dispatcher), `condition_patch.should_vent_overheat`, and `sprint.on_update_movement` input mutations.
3. **Suite hygiene** — `_G` teardown for 5 contaminating specs, fix the one player/minion hybrid mock, extend mock audit + doc-check regex to cover audited families currently bypassed (`input_system`, `behavior_system`, `side_system`, `liquid_area_system`) plus the `BotUnitInput` surface.

**Tech stack:** Lua 5.4, busted, luacheck, stylua, lua-language-server, bash. All tests run via `make test`; full CI gate via `make check-ci`.

**Execution order (revised after Codex plan audit):** T1 → T2 → T3 → T4 → **T11** (global teardown first) → T5 → T6 → **T7a + T7b** → **T8** → T9 → **T10a + T10b** → T12 → **T13a + T13b**. T11 moves ahead of Phase 2 so the specs Phase 2 extends are no longer contaminating globals by the time new tests land. T7 and T10 split into "pure extraction, no behavior change" commits followed by "tests" commits. T13 splits into ScriptUnit-family regex enforcement vs. manager-system enforcement.

**Hard invariants — enforced across all extract-and-test tasks:**
- **Hook registration stays in `BetterBots.lua`.** The `mod:hook_require` / `mod:hook_safe` / `mod:hook` calls MUST remain in `BetterBots.lua`. New modules expose a plain function that the thin inline hook wrapper calls. This preserves DMF dedupe semantics and the existing class-sentinel pattern (`BetterBots.lua:1273-1279`, tested in `tests/startup_regressions_spec.lua:852-899, 1049-1065`).
- **Class-level sentinels stay on the engine class**, not in module-local state. Do not relocate `BEHAVIOR_DISPATCHER_SENTINEL` or equivalents.
- **Byte-for-byte semantic preservation.** Any extraction task's first commit is pure mechanical move — diff must read as a refactor, not a change. Tests go in the second commit.

**Ground rules for every task:**
- **TDD**: for test-adding tasks, write the failing spec first, run to confirm it fails (for the right reason), then make it green. Commit after each task.
- **No scope creep**: do not refactor adjacent code. If you discover an additional bug, note it in the task summary — do not fix it as part of the current task.
- **Mock fidelity**: every new mock must route through `tests/test_helper.lua` builders. Every new private-field or method read on an engine class must be added to `docs/dev/mock-api-audit.md` with a `../Darktide-Source-Code/` file:line citation.
- **Verification**: every task ends with `make check` passing locally (or the documented failure if the task is about exposing an existing check).
- **Conventional commits**: `fix(scope):`, `test(scope):`, `chore(scope):`. No Claude/Codex attribution trailers.

---

## Phase 1 — Tooling & release-safety

### Task 1: Fix doc-check.sh closed-issue-scan paths

The scan at `scripts/doc-check.sh:41` loops over `docs/ROADMAP.md` and `docs/STATUS.md`, but those files were renamed to `docs/dev/roadmap.md` / `docs/dev/status.md` in commit `5d2f9da`. The `[ -f "$doc" ] || continue` guard silently skips — the gate has been dead for weeks. The secondary Next-Steps scan at `:59` has the same bug.

**Files:**
- Modify: `scripts/doc-check.sh:41, 59`

- [ ] **Step 1: Reproduce the silent skip**

Run: `rg -n 'ROADMAP|STATUS' scripts/doc-check.sh`
Expected output: two matches on lines 41 and 59 referencing uppercase paths.
Then: `ls docs/dev/roadmap.md docs/dev/status.md` — confirms real paths exist.

- [ ] **Step 2: Update paths**

```bash
# scripts/doc-check.sh line 41
for doc in docs/dev/roadmap.md docs/dev/status.md; do
```

```bash
# scripts/doc-check.sh line 59
doc="docs/dev/status.md"
```

- [ ] **Step 3: Verify the check now runs**

Run: `make doc-check`
Expected: output contains `ok:  GitHub issue state cross-check done` (when `gh` is authenticated) or the `info: gh CLI not available` fallback. No silent skip. Run passes or fails based on real doc state — if it fails, the closed-issue warnings are legitimate and must be resolved as a follow-up (note them in the commit body but do not fix here).

- [ ] **Step 4: Commit**

```bash
git add scripts/doc-check.sh
git commit -m "fix(doc-check): scan docs/dev/{roadmap,status}.md, not old uppercase paths"
```

---

### Task 2: Reorder release.sh clean-tree check

`scripts/release.sh:45` runs `require_clean_git` then `:51` runs `make check` which calls `format` (mutating). Formatter output is never re-verified — if it changes anything, `make package` zips post-format files while the tag points at the pre-format commit. A release ships with local/remote divergence.

**Files:**
- Modify: `scripts/release.sh:45-54`

- [ ] **Step 1: Add a second clean-tree check after `make check`**

Replace `scripts/release.sh:45-54` (the block from `require_clean_git` through `make package`):

```bash
require_clean_git

TAG="v$VERSION_ARG"

echo "Release: $TAG"
echo "Running checks..."
make check

# make check runs format (mutating); re-verify the tree is still clean before
# tagging, otherwise the tag would point at a commit that no longer matches
# the files being packaged.
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "make check produced formatter changes. Commit them, then re-run release." >&2
	git --no-pager diff --stat >&2
	exit 2
fi

echo "Building package..."
make package
```

- [ ] **Step 2: Smoke-test the guard**

Introduce a deliberate formatting drift (insert tab indentation into a Lua file's table literal), then run `scripts/release.sh 0.0.0-test`. It must exit with the new error before tagging.

Revert the test edit.

- [ ] **Step 3: Verify clean path still works**

From a clean tree: `scripts/release.sh --help` still prints usage. Do not actually cut a release.

- [ ] **Step 4: Commit**

```bash
git add scripts/release.sh
git commit -m "fix(release): re-verify clean tree after make check format-fixups"
```

---

### Task 3: Add `make check-ci` gate to release.yml

`.github/workflows/release.yml:20` triggers on tag push and runs `make package` immediately — no linting, no tests, no format check. A tag pushed from a dirty workspace, or a tag landed via the GitHub UI without going through `scripts/release.sh`, ships a ZIP that could fail CI.

**Files:**
- Modify: `.github/workflows/release.yml:19-21` (insert a gate step before the existing `Build mod package`)
- Modify: `.github/workflows/release.yml` top (add the Lua tooling install step, mirroring `ci.yml`)

- [ ] **Step 1: Add Lua tooling install + gate before packaging**

Replace the `steps:` block in `.github/workflows/release.yml` with:

```yaml
    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Install Lua tooling
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq lua5.4 liblua5.4-dev luarocks
          sudo luarocks --lua-version=5.4 install luacheck
          sudo luarocks --lua-version=5.4 install busted
          STYLUA_VERSION="2.0.2"
          curl -fsSL "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-x86_64.zip" -o /tmp/stylua.zip
          unzip -o /tmp/stylua.zip -d /usr/local/bin
          chmod +x /usr/local/bin/stylua
          LLS_VERSION="3.13.6"
          curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LLS_VERSION}/lua-language-server-${LLS_VERSION}-linux-x64.tar.gz" -o /tmp/lls.tar.gz
          mkdir -p /opt/lua-language-server
          tar -xzf /tmp/lls.tar.gz -C /opt/lua-language-server
          ln -sf /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server

      - name: Run checks
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: make check-ci

      - name: Build mod package
        run: make package

      - name: Generate changelog
        uses: orhun/git-cliff-action@v4
        id: changelog
        with:
          config: cliff.toml
          args: --latest --strip header

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          body: ${{ steps.changelog.outputs.content }}
          files: BetterBots.zip
          token: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Lint the workflow YAML**

Run: `yamllint .github/workflows/release.yml` if `yamllint` is available; otherwise `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/release.yml"))'`.
Expected: no parse errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): gate tag-release packaging on make check-ci"
```

Note: this increases tag-release latency (~2 min install + check). Acceptable trade-off for correctness.

---

### Task 4: Make `lsp-check` hermetic

`Makefile:21-22` writes LLS logs to `/tmp/luals-betterbots`. On machines where `/tmp` cleanup or permissions differ, the check can fail non-deterministically. Independent audit reported a failure in exactly this way.

**Files:**
- Modify: `Makefile:21-22`
- Modify: `.gitignore` (add `build/`)

- [ ] **Step 1: Repoint logpath to repo-local build dir**

```make
lsp-check:
	@mkdir -p build/luals-log
	lua-language-server --configpath=.luarc.json --check=. --check_format=pretty --logpath=build/luals-log
```

- [ ] **Step 2: Ignore the log dir**

Append to `.gitignore` if not already present:

```
build/
```

- [ ] **Step 3: Verify**

Run: `make lsp-check`
Expected: exits clean; `build/luals-log/` is created but not tracked (`git status` shows no changes inside it).

- [ ] **Step 4: Commit**

```bash
git add Makefile .gitignore
git commit -m "fix(make): make lsp-check hermetic with repo-local logpath"
```

---

## Phase 2 — Entrypoint + critical-path behavioral tests

### Task 5: Tests for `condition_patch.should_vent_overheat`

`condition_patch.lua:404-427` replaces the vanilla `should_vent_overheat` with a correct version (issue #30 — vanilla reads `scratchpad.reloading` which is never set; fix uses `is_running`). Zero spec coverage. Regression silently re-breaks the vanilla bug.

**Files:**
- Modify: `tests/condition_patch_spec.lua` (add a new `describe("should_vent_overheat", ...)` block)

**Note:** `_install_condition_patch` is already exported as `M._install_condition_patch` at `scripts/mods/BetterBots/condition_patch.lua:659`. No production-code export change needed.

- [ ] **Step 1: Read the code you're testing**

Read `scripts/mods/BetterBots/condition_patch.lua:400-427` to confirm the three branches: melee target → false; `is_running=true` → `>= stop_percentage`; `is_running=false` → `>= start_min_percentage AND <= start_max_percentage`.

Read the current shape of `tests/condition_patch_spec.lua` to understand existing mock conventions (how `_G.ScriptUnit`, the conditions table, and the `require("scripts/utilities/overheat")` stub are set up).

- [ ] **Step 2: Write the failing test block**

Append to `tests/condition_patch_spec.lua` (before the final `end)` of the top-level `describe`). The Overheat utility is loaded via `require` inside the patch installer — you must stub it. Use the existing `_G.package.loaded["scripts/utilities/overheat"]` mechanism already in the spec, or install a fresh stub at the top of the `describe` block and tear it down in `after_each`.

```lua
describe("should_vent_overheat", function()
	local conditions
	local overheat_percentage

	before_each(function()
		overheat_percentage = 0
		package.loaded["scripts/utilities/overheat"] = {
			slot_percentage = function(_unit, _slot, _limit_type)
				return overheat_percentage
			end,
		}
		conditions = {
			should_vent_overheat = function() return false end,
			can_activate_ability = function() return false end,
		}
		ConditionPatch._install_condition_patch(conditions, {}, "test")
	end)

	after_each(function()
		package.loaded["scripts/utilities/overheat"] = nil
	end)

	local function call(is_running, target_type, args)
		local blackboard = { perception = { target_enemy_type = target_type or "ranged" } }
		return conditions.should_vent_overheat(
			"unit_stub",
			blackboard,
			{},
			args or { overheat_limit_type = "standard", start_min_percentage = 0.5, start_max_percentage = 0.9, stop_percentage = 0.2 },
			{},
			is_running
		)
	end

	it("returns false for melee target regardless of overheat", function()
		overheat_percentage = 0.95
		assert.is_false(call(false, "melee"))
		assert.is_false(call(true, "melee"))
	end)

	it("when is_running uses stop_percentage lower bound", function()
		overheat_percentage = 0.19
		assert.is_false(call(true))
		overheat_percentage = 0.2
		assert.is_true(call(true))
	end)

	it("when not is_running requires start range window", function()
		overheat_percentage = 0.49
		assert.is_false(call(false))
		overheat_percentage = 0.5
		assert.is_true(call(false))
		overheat_percentage = 0.9
		assert.is_true(call(false))
		overheat_percentage = 0.91
		assert.is_false(call(false))
	end)
end)
```

- [ ] **Step 3: Run the spec and confirm it fails**

Run: `busted tests/condition_patch_spec.lua`
Expected: all three new cases fail (install_condition_patch not exported yet, or the wiring differs). Read the error, fix the wiring, and re-run — **do not** modify the production logic.

- [ ] **Step 4: Green**

Once the wiring is correct the tests pass without changing `condition_patch.lua:404-427`. If they still fail, the bug you've found is legitimate; report it before proceeding.

- [ ] **Step 5: `make check` + commit**

```bash
make check
git add tests/condition_patch_spec.lua scripts/mods/BetterBots/condition_patch.lua
git commit -m "test(condition_patch): cover should_vent_overheat three-branch logic (#30)"
```

---

### Task 6: Tests for `sprint.on_update_movement` hook input mutations

`sprint.lua:235-287` — the hook body's actual effect (`input.hold_to_sprint = true`, `input.sprinting = should`) is never asserted. The existing spec only tests `_should_sprint` as a pure predicate.

**Files:**
- Modify: `tests/sprint_spec.lua` (add a new `describe("on_update_movement hook", ...)` block)
- Possibly modify: `scripts/mods/BetterBots/sprint.lua` (export `on_update_movement` for test — check first if already exported as e.g. `Sprint._on_update_movement`)

- [ ] **Step 1: Check export status**

Run: `rg -n 'on_update_movement' scripts/mods/BetterBots/sprint.lua`
If only the local function exists, add at module end: `Sprint._on_update_movement = on_update_movement` (leading underscore marks it test-only).

- [ ] **Step 2: Write the failing test block**

Follow the existing `sprint_spec.lua` style — it already wires up deps via `Sprint.init({...})` and stubs `ScriptUnit`. Assert on the `input` table after calling the hook.

```lua
describe("on_update_movement hook", function()
	local Sprint, input, next_should, next_reason

	before_each(function()
		Sprint = dofile("scripts/mods/BetterBots/sprint.lua")
		Sprint.init({
			mod = { echo = function() end },
			debug_log = function() end,
			debug_enabled = function() return false end,
			fixed_time = function() return 0 end,
			sprint_follow_distance = function() return 5 end,
			is_daemonhost_avoidance_enabled = function() return true end,
			shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
		})
		-- Monkeypatch _should_sprint via the module-local test hook:
		Sprint._set_should_sprint_for_test(function() return next_should, next_reason end)
		input = {}
		next_should, next_reason = false, "enemies_nearby"
	end)

	local function call()
		Sprint._on_update_movement(function() end, {}, "unit_stub", input, 0.016, 1.0)
	end

	it("always sets hold_to_sprint = true when enabled", function()
		call()
		assert.is_true(input.hold_to_sprint)
	end)

	it("sets input.sprinting to _should_sprint result", function()
		next_should = true
		call()
		assert.is_true(input.sprinting)
		next_should = false
		call()
		assert.is_false(input.sprinting)
	end)

	it("short-circuits and does not mutate input when follow_distance = 0", function()
		Sprint.init({
			mod = { echo = function() end },
			debug_log = function() end,
			debug_enabled = function() return false end,
			fixed_time = function() return 0 end,
			sprint_follow_distance = function() return 0 end,
			is_daemonhost_avoidance_enabled = function() return true end,
			shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
		})
		call()
		assert.is_nil(input.hold_to_sprint)
		assert.is_nil(input.sprinting)
	end)

	it("chains original func and completes perf span on both paths", function()
		local func_calls = 0
		local wrapped = function(self, unit, input_arg, dt, t)
			func_calls = func_calls + 1
		end
		Sprint._on_update_movement(wrapped, {}, "unit_stub", input, 0.016, 1.0)
		assert.equals(1, func_calls)

		-- Short-circuit path must also call func before returning.
		Sprint.init({
			mod = { echo = function() end },
			debug_log = function() end,
			debug_enabled = function() return false end,
			fixed_time = function() return 0 end,
			sprint_follow_distance = function() return 0 end,
			is_daemonhost_avoidance_enabled = function() return true end,
			shared_rules = dofile("scripts/mods/BetterBots/shared_rules.lua"),
		})
		Sprint._on_update_movement(wrapped, {}, "unit_stub", {}, 0.016, 1.0)
		assert.equals(2, func_calls)
	end)
end)
```

`_set_should_sprint_for_test` is a new test seam: at module end of `sprint.lua` add:

```lua
function Sprint._set_should_sprint_for_test(fn)
	_should_sprint = fn
end
```

(replacing the file-local `_should_sprint` reference with one the init can swap.)

- [ ] **Step 3: Run → fail → green**

Run: `busted tests/sprint_spec.lua`. First run fails because the test seam is absent. Add it. Re-run until green.

- [ ] **Step 4: `make check` + commit**

```bash
git add scripts/mods/BetterBots/sprint.lua tests/sprint_spec.lua
git commit -m "test(sprint): cover on_update_movement input mutations and follow_distance=0 short-circuit"
```

---

### Task 7a: Extract `use_ability_charge` body into `charge_tracker.lua` (refactor, no behavior change)

`BetterBots.lua:1126-1217`. Hot path — every charge consumption goes through this. Zero coverage.

**This task produces one commit that is pure code movement.** The `mod:hook_safe` call stays in `BetterBots.lua`. A new `scripts/mods/BetterBots/charge_tracker.lua` exposes `ChargeTracker.handle(self, ability_type, optional_num_charges)` containing the exact body of the current inline callback. All helpers the body depends on (`_fixed_time`, `_debug_log`, `_debug_enabled`, `_equipped_combat_ability_name`, `_last_charge_event_by_unit`, `_fallback_state_by_unit`) are either threaded through `ChargeTracker.init({...})` deps or passed by reference (the `_*_by_unit` tables are shared mutable state — keep them in `BetterBots.lua` and pass the tables into `init` so `ChargeTracker` reads/writes the same objects).

**Files:**
- Create: `scripts/mods/BetterBots/charge_tracker.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua` — load via `mod:io_dofile` at the same site where sibling modules are loaded (find the existing block around `BetterBots.lua:244-304` or wherever `AbilityQueue`, `ItemFallback`, `GrenadeFallback` are loaded and place `ChargeTracker` in the same alphabetic/functional order); call `ChargeTracker.init({...})` with the shared mutable tables alongside the other module inits (~`BetterBots.lua:703-747`); replace inline callback body at `:1127-1217` with a single-line delegation.
- Modify: `AGENTS.md` (inventory: module file structure + no spec yet, will add in 7b)
- Modify: `README.md` (repo layout)
- Modify: `CLAUDE.md` "Mod file structure" block

- [ ] **Step 1: Load site + init site**

Verify the load-order constraint: `ChargeTracker` must be `io_dofile`d BEFORE the `hook_require("scripts/extension_systems/ability/player_unit_ability_extension", ...)` block at `BetterBots.lua:1121`. Current sibling modules (`GrenadeFallback`, `ItemFallback`, `TeamCooldown`, `CombatAbilityIdentity`, `EventLog`, `Debug`, `Settings`) are loaded well before line 1121 — so place `ChargeTracker` in the same block to keep the ordering obvious.

- [ ] **Step 2: Extract handler**

`scripts/mods/BetterBots/charge_tracker.lua`:

```lua
local M = {}

local _deps

function M.init(deps)
	_deps = deps
end

function M.handle(self, ability_type, optional_num_charges)
	if ability_type ~= "combat_ability" and ability_type ~= "grenade_ability" then
		return
	end

	local player = self._player
	if not player or player:is_human_controlled() then
		return
	end

	-- Remainder is the exact body from BetterBots.lua:1136-1217 with
	-- `_fixed_time`, `_debug_log`, etc. replaced by `_deps.fixed_time`,
	-- `_deps.debug_log`, etc. The shared tables (`_last_charge_event_by_unit`,
	-- `_fallback_state_by_unit`) are in `_deps.last_charge_event_by_unit` and
	-- `_deps.fallback_state_by_unit`.
	-- Copy verbatim, make mechanical replacements, keep all branches.
end

return M
```

- [ ] **Step 3: Replace inline callback body**

```lua
mod:hook_safe(PlayerUnitAbilityExtension, "use_ability_charge", function(self, ability_type, optional_num_charges)
	ChargeTracker.handle(self, ability_type, optional_num_charges)
end)
```

- [ ] **Step 4: Verify existing suite still green**

Run: `make check`
Expected: all existing tests pass. This commit changes no behavior.

- [ ] **Step 5: Doc updates**

- README.md repo layout: add `charge_tracker.lua`
- AGENTS.md mod file structure: add `charge_tracker.lua`
- CLAUDE.md mod file structure: add `charge_tracker.lua`

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/{charge_tracker,BetterBots}.lua README.md AGENTS.md CLAUDE.md
git commit -m "refactor(charge_tracker): extract use_ability_charge body for testability"
```

---

### Task 7b: Test coverage for `charge_tracker.handle`

Behavioral tests run against the extracted module. No further production changes.

**Files:**
- Create: `tests/charge_tracker_spec.lua`
- Modify: `AGENTS.md` (add spec to test list — required by `scripts/doc-check.sh:117-125`)

- [ ] **Step 1: Write failing spec**

`tests/charge_tracker_spec.lua` — cover six cases:

```lua
describe("charge_tracker.handle", function()
	local ChargeTracker, recorded
	-- See existing spec style e.g. tests/team_cooldown_spec.lua for wiring pattern.

	before_each(function()
		recorded = { team_cooldown = {}, event_log = {}, grenade = {} }
		ChargeTracker = dofile("scripts/mods/BetterBots/charge_tracker.lua")
		ChargeTracker.init({
			grenade_fallback = {
				record_charge_event = function(unit, name, t)
					table.insert(recorded.grenade, { unit = unit, name = name, t = t })
				end,
			},
			settings = { is_feature_enabled = function() return true end },
			team_cooldown = { record = function(u, k, t) table.insert(recorded.team_cooldown, { u, k, t }) end },
			combat_ability_identity = { resolve = function() return { semantic_key = "psyker_shout" } end },
			event_log = {
				is_enabled = function() return true end,
				emit = function(e) table.insert(recorded.event_log, e) end,
			},
			debug = { bot_slot_for_unit = function() return 1 end },
			fixed_time = function() return 10 end,
			debug_log = function() end,
			debug_enabled = function() return false end,
			fallback_state_lookup = function() return nil end,
			last_charge_event_table = {},
		})
	end)

	local function make_self(equipped, is_human)
		return {
			_unit = "unit_stub",
			_player = { is_human_controlled = function() return is_human == true end },
			_equipped_abilities = equipped,
		}
	end

	it("returns early for non-combat non-grenade ability types", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "x" } }), "weapon_ability", 1)
		assert.equals(0, #recorded.team_cooldown)
		assert.equals(0, #recorded.event_log)
	end)

	it("returns early for human-controlled players", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "x" } }, true), "combat_ability", 1)
		assert.equals(0, #recorded.team_cooldown)
	end)

	it("grenade charges route to GrenadeFallback.record_charge_event", function()
		ChargeTracker.handle(make_self({ grenade_ability = { name = "frag" } }), "grenade_ability", 1)
		assert.equals(1, #recorded.grenade)
		assert.equals("frag", recorded.grenade[1].name)
		assert.equals(0, #recorded.team_cooldown)
	end)

	it("combat charges record team cooldown with semantic key", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "psyker_discharge_shout_improved" } }), "combat_ability", 1)
		assert.equals(1, #recorded.team_cooldown)
		assert.equals("psyker_shout", recorded.team_cooldown[1][2])
	end)

	it("combat charges emit consumed event", function()
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 2)
		assert.equals(1, #recorded.event_log)
		assert.equals("consumed", recorded.event_log[1].event)
		assert.equals(2, recorded.event_log[1].charges)
	end)

	it("combat charges record _last_charge_event_by_unit entry with name and fixed_t", function()
		local table_ref = {}
		ChargeTracker.init({ -- repeat base init, override last_charge_event_by_unit table
			-- (use a make_deps helper in the spec)
			last_charge_event_by_unit = table_ref,
			-- ... rest of deps
		})
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)
		assert.is_not_nil(table_ref["unit_stub"])
		assert.equals("veteran_stance", table_ref["unit_stub"].ability_name)
		assert.equals(10, table_ref["unit_stub"].fixed_t)  -- fixed_time() stub returns 10
	end)

	it("consumed event carries rule and attempt_id from _fallback_state_by_unit when present", function()
		local fallback_state = { unit_stub = { item_rule = "retry_wield", attempt_id = "abc123" } }
		ChargeTracker.init({ -- repeat base init, override fallback_state_lookup
			fallback_state_lookup = function(unit) return fallback_state[unit] end,
			-- ... rest of deps
		})
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)
		assert.equals("retry_wield", recorded.event_log[1].rule)
		assert.equals("abc123", recorded.event_log[1].attempt_id)
	end)

	it("does not record team cooldown when feature disabled", function()
		ChargeTracker.init({
			-- repeat base init but override settings:
			settings = { is_feature_enabled = function() return false end },
			-- ... (copy the rest of init from before_each; this is a minor inconvenience
			-- that can be cleaned up with a make_deps helper in this spec)
		})
		ChargeTracker.handle(make_self({ combat_ability = { name = "veteran_stance" } }), "combat_ability", 1)
		assert.equals(0, #recorded.team_cooldown)
	end)
end)
```

- [ ] **Step 2: Run → green**

Run: `busted tests/charge_tracker_spec.lua`. Since T7a already landed the module, this should go from red (new cases) to green with no production changes.

- [ ] **Step 3: `make check` + commit**

```bash
git add tests/charge_tracker_spec.lua AGENTS.md
git commit -m "test(charge_tracker): cover use_ability_charge branches incl. state and event fields"
```

---

### Task 8: Tests for `ActionCharacterStateChange.finish` retry

`BetterBots.lua:1224-1266`. Same extract-and-test pattern as Task 7. Host the handler in `scripts/mods/BetterBots/item_fallback.lua` (`ItemFallback.on_state_change_finish(self, reason, data, t, time_in_action)`) since `ItemFallback.schedule_retry` is the primary side effect.

**Critical semantic detail (per Codex audit):** the production retry uses `_fixed_time()` at the moment of the hook firing, NOT the callback's `t` parameter. See `BetterBots.lua:1248-1250`:

```lua
local fixed_t = _fixed_time()
local ability_name = _equipped_combat_ability_name(unit)
ItemFallback.schedule_retry(unit, fixed_t, ABILITY_STATE_FAIL_RETRY_S)
```

The test must assert that `schedule_retry` was called with `_fixed_time()`'s return value, not with the callback's `t`. Also, `ItemFallback.schedule_retry` is already exported — **do not** add a new `_set_schedule_retry_for_test` seam. Use a spy on the existing `ItemFallback.schedule_retry` instead.

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua` (add `M.on_state_change_finish`)
- Modify: `scripts/mods/BetterBots/BetterBots.lua:1224-1266` (inline body → `ItemFallback.on_state_change_finish(...)` call)
- Modify: `tests/item_fallback_spec.lua` (add cases)

- [ ] **Step 1: Extract**

Move the inline body to `ItemFallback.on_state_change_finish(self, reason, data, t, time_in_action)`. Preserve the `func(self, ...)` original-chain call order — the hook wrapper must still invoke `func` before the retry logic runs. Pass the original `func` as first arg or keep the wrapper in `BetterBots.lua`; the cleanest factoring is:

```lua
mod:hook(ActionCharacterStateChange, "finish", function(func, self, reason, data, t, time_in_action)
	return ItemFallback.on_state_change_finish(func, self, reason, data, t, time_in_action)
end)
```

with the module function handling both the original call and the retry.

- [ ] **Step 2: Write failing tests**

Add to `tests/item_fallback_spec.lua`:

```lua
describe("on_state_change_finish", function()
	local original_schedule_retry
	local scheduled

	before_each(function()
		original_schedule_retry = ItemFallback.schedule_retry
		scheduled = nil
		ItemFallback.schedule_retry = function(unit, fixed_t, window)
			scheduled = { unit = unit, fixed_t = fixed_t, window = window }
		end
	end)

	after_each(function()
		ItemFallback.schedule_retry = original_schedule_retry
	end)

	it("chains original func then schedules retry when bot + combat_ability + use_ability_charge + failed transition", function()
		local called_order = {}
		local orig_func = function() table.insert(called_order, "orig") end
		local schedule_wrapper = ItemFallback.schedule_retry
		ItemFallback.schedule_retry = function(...)
			schedule_wrapper(...)
			table.insert(called_order, "retry")
		end
		local self = {
			_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
			_player = { is_human_controlled = function() return false end },
			_player_unit = "unit_stub",
			_wanted_state_name = "stunned",
			_character_sate_component = { state_name = "walking" },
		}
		-- callback t is 100; _fixed_time() stub must return a different value (e.g. 42)
		-- so we can verify the production uses _fixed_time() not the callback t.
		ItemFallback.on_state_change_finish(orig_func, self, "interrupted", nil, 100, 0.1)
		assert.same({ "orig", "retry" }, called_order)
		assert.equals("unit_stub", scheduled.unit)
		assert.equals(42, scheduled.fixed_t) -- _fixed_time() stub, NOT the callback t=100
	end)

	it("does not schedule retry when human-controlled", function()
		-- ... (similar shape, with is_human_controlled returning true; assert scheduled == nil)
	end)

	it("does not schedule retry when state transition succeeded", function()
		-- wanted == current; assert scheduled == nil
	end)

	it("does not schedule retry for non-combat ability type", function()
		-- ability_type = "grenade_ability"; assert scheduled == nil
	end)

	it("does not schedule retry when use_ability_charge=false", function()
		-- assert scheduled == nil
	end)
end)
```

- [ ] **Step 3: Run → fail → extract → green**

First run fails (extraction incomplete). Extract the inline hook body from `BetterBots.lua:1224-1266` into `ItemFallback.on_state_change_finish(func, self, reason, data, t, time_in_action)` with deps wired through `ItemFallback.init({...})` for `fixed_time`, `debug_log`, `debug_enabled`. The `BetterBots.lua` hook becomes a single-line delegation.

- [ ] **Step 4: `make check` + commit**

```bash
git add scripts/mods/BetterBots/{item_fallback,BetterBots}.lua tests/item_fallback_spec.lua
git commit -m "test(item_fallback): cover state-change finish retry guards using _fixed_time"
```

---

### Task 9: Tests for gestalt injection hook

`BetterBots.lua:1328-1356`. Simple logic but untested. Extract the handler body into `scripts/mods/BetterBots/BetterBots.lua` module-local function already exists as an anonymous closure — move to a named local and export via the module's test helpers, OR create a new `gestalt_injector.lua` module (cleaner).

**Files:**
- Create: `scripts/mods/BetterBots/gestalt_injector.lua` with `M.inject(self, blackboard, physics_world, gestalts_or_nil)` returning the possibly-extended gestalts table
- Modify: `BetterBots.lua:1328-1356` to delegate
- Create: `tests/gestalt_injector_spec.lua`
- Update: README.md, AGENTS.md, CLAUDE.md inventory

- [ ] **Step 1: Extract**

New module exposes `M.inject(gestalts_or_nil, unit)` → `(new_gestalts, was_injected)` so the hook wrapper can still log and call `func`.

- [ ] **Step 2: Write failing tests**

```lua
describe("gestalt_injector.inject", function()
	it("injects defaults when gestalts are nil", function()
		local out, injected = GestaltInjector.inject(nil, "unit_a")
		assert.equals("killshot", out.ranged)
		assert.equals("linesman", out.melee)
		assert.is_true(injected)
	end)

	it("preserves existing ranged gestalt", function()
		local out, injected = GestaltInjector.inject({ ranged = "custom" }, "unit_b")
		assert.equals("custom", out.ranged)
		assert.is_false(injected)  -- not injected because .ranged was present
	end)

	it("fills only missing fields when partially specified", function()
		-- Depends on production behavior: the current code treats ANY non-nil
		-- gestalts_or_nil.ranged as "don't touch". Verify.
		local out, injected = GestaltInjector.inject({ ranged = "killshot" }, "unit_c")
		assert.equals("killshot", out.ranged)
		assert.is_nil(out.melee)  -- if that's the current behavior — DOCUMENT what the code does, don't hypothesize
		assert.is_false(injected)
	end)

	it("deduplicates per-unit injection tracking", function()
		local _, first = GestaltInjector.inject(nil, "unit_d")
		local _, second = GestaltInjector.inject(nil, "unit_d")
		assert.is_true(first)
		assert.is_false(second)  -- second call observes unit in dedup set
	end)
end)
```

Verify the third case by reading production code behavior BEFORE writing the assertion — the current block at `BetterBots.lua:1333-1336` uses `not gestalts_or_nil.ranged` as the gate, so a partial `{ ranged = "..." }` table skips injection entirely. The test should assert actual production behavior, not idealized behavior.

- [ ] **Step 3: Run → fail → extract → green**

- [ ] **Step 4: `make check` + commit**

```bash
git add scripts/mods/BetterBots/{gestalt_injector,BetterBots}.lua tests/gestalt_injector_spec.lua README.md AGENTS.md CLAUDE.md
git commit -m "test(gestalt_injector): extract and cover bot gestalt defaulting (#35)"
```

---

### Task 10a: Extract update dispatcher (refactor, no behavior change)

`BetterBots.lua:1358-1435`. This is the largest and highest-traffic hook body. Extract to `scripts/mods/BetterBots/update_dispatcher.lua` (single-responsibility: "every frame, dispatch these things in this order with these gates").

**This commit is pure extraction.** The `mod:hook_safe(BotBehaviorExtension, "update", ...)` wrapper stays in `BetterBots.lua`. `BEHAVIOR_DISPATCHER_SENTINEL` class-level guard stays where it is. The extracted module exposes `UpdateDispatcher.dispatch(self, unit)`; all shared state tables (`_last_snapshot_t_by_unit`, `_fallback_state_by_unit`, `_session_start_emitted`, `_SNAPSHOT_INTERVAL_S`) are passed into `UpdateDispatcher.init({...})` as references. Flag `_session_start_emitted` specifically — it's a module-local boolean in current code. Convert to a one-element table `{emitted = false}` passed into deps so the shared-reference pattern works.

**Files:**
- Create: `scripts/mods/BetterBots/update_dispatcher.lua`
- Modify: `BetterBots.lua:1358-1435`
- Modify: README.md, AGENTS.md, CLAUDE.md

- [ ] **Step 1: Extract**

`M.dispatch(self, unit)` runs (preserving exact order from `BetterBots.lua:1358-1435`):
1. Human-controlled short-circuit (line 1359-1362)
2. `Perf.sync_setting()` / `Perf.mark_bot_frame()` (1364-1365)
3. Session-start event if enabled + bots present + not yet emitted (1370-1392)
4. `AbilityQueue.try_queue` (1395)
5. `GrenadeFallback.try_queue` (1398)
6. `PingSystem.update` + `CompanionTag.update` gated on `pinging` setting (1400-1407)
7. `EventLog.try_flush` (1409)
8. Snapshot emit gated on cadence + EventLog enabled (1412-1434)

All collaborators passed via `M.init({...})`. Shared state (`_last_snapshot_t_by_unit`, `_session_start_emitted` flag via `{emitted=false}` box, constants like `_SNAPSHOT_INTERVAL_S`, `META_PATCH_VERSION`) passed by reference.

- [ ] **Step 2: Verify existing tests green**

Run: `make check`. Pure extraction — nothing should regress.

- [ ] **Step 3: Doc updates + commit**

- README.md repo layout, AGENTS.md mod file structure, CLAUDE.md mod file structure: add `update_dispatcher.lua`.

```bash
git add scripts/mods/BetterBots/{update_dispatcher,BetterBots}.lua README.md AGENTS.md CLAUDE.md
git commit -m "refactor(update_dispatcher): extract BotBehaviorExtension.update body"
```

---

### Task 10b: Test coverage for `update_dispatcher.dispatch`

Behavioral tests against the extracted module.

**Files:**
- Create: `tests/update_dispatcher_spec.lua`
- Modify: `AGENTS.md` (test list)

- [ ] **Step 1: Write failing tests (minimum 9 cases)**

```lua
describe("update_dispatcher.dispatch", function()
	-- Setup: build deps via a make_deps() helper that returns collaborator
	-- mocks recording every call in order to a single call_log table. This
	-- lets dispatch-order assertions use assert.same on the recorded sequence.

	it("short-circuits for human-controlled players (no AbilityQueue, no EventLog flush)", function() ... end)
	it("dispatches AbilityQueue and GrenadeFallback every frame", function() ... end)
	it("dispatches PingSystem and CompanionTag when pinging setting enabled", function() ... end)
	it("skips PingSystem and CompanionTag when pinging setting disabled", function() ... end)
	it("emits session_start exactly once across multiple calls", function() ... end)
	it("emits snapshot at first call and again after _SNAPSHOT_INTERVAL_S elapsed", function() ... end)
	it("does not emit snapshot within _SNAPSHOT_INTERVAL_S", function() ... end)

	-- Codex audit: T10 must explicitly prove dispatch order.
	it("calls EventLog.try_flush after GrenadeFallback.try_queue and before snapshot emit", function()
		-- call_log should read: ability_queue, grenade_fallback, [ping, companion], event_log_flush, snapshot_emit
		local log = {}
		local deps = make_deps({ call_log = log, pinging = false, snapshot_due = true })
		UpdateDispatcher.dispatch(make_self_bot(), "unit_stub")
		-- Assert relative ordering, not absolute timestamps.
		local pos = function(name)
			for i, e in ipairs(log) do if e == name then return i end end
			return -1
		end
		assert.is_true(pos("grenade_fallback") < pos("event_log_flush"))
		assert.is_true(pos("event_log_flush") < pos("snapshot_emit"))
	end)

	it("does not emit snapshot when EventLog is disabled, even if cadence elapsed", function() ... end)
end)
```

- [ ] **Step 2: Run → green**

- [ ] **Step 3: `make check` + commit**

```bash
git add tests/update_dispatcher_spec.lua AGENTS.md
git commit -m "test(update_dispatcher): cover dispatch order, gating, and snapshot cadence"
```

---

## Phase 3 — Suite hygiene

### Task 11: `_G` teardown for 5 contaminating specs

Specs mutate global state at file-load time with no `after_each` / `teardown` restore: `tests/condition_patch_spec.lua:16`, `tests/sprint_spec.lua:8`, `tests/revive_ability_spec.lua:14`, `tests/weapon_action_spec.lua:9`, `tests/grenade_fallback_spec.lua:81`. Order-dependent contamination.

**Files:** all five spec files listed above.

- [ ] **Step 1: For each file, capture current globals before mutation**

Pattern:

```lua
local _saved_globals = {}

setup(function()
	_saved_globals.ScriptUnit = rawget(_G, "ScriptUnit")
	_saved_globals.BLACKBOARDS = rawget(_G, "BLACKBOARDS")
	-- etc.
end)

teardown(function()
	for k, v in pairs(_saved_globals) do
		rawset(_G, k, v)
	end
end)
```

Move the current file-load mutations into `setup(function() ... end)`.

- [ ] **Step 2: Verify suite order-independence**

Run three times with shuffled file order:

```bash
for i in 1 2 3; do
	busted --shuffle tests/ | tail -1
done
```

Expected: all three runs report identical pass counts.

- [ ] **Step 3: Run → commit**

```bash
git add tests/{condition_patch,sprint,revive_ability,weapon_action,grenade_fallback}_spec.lua
git commit -m "test(hygiene): move _G mutations into setup/teardown to restore suite order-independence"
```

---

### Task 12: Fix `grenade_fallback_spec.lua:504` player/minion hybrid

The test uses `make_player_unit_data_extension` but attaches a minion breed (`chaos_traitor_gunner`). Per `docs/dev/mock-api-audit.md:26` minions only expose `breed() / faction_name() / is_companion() / breed_name() / breed_size_variation()`, not `read_component`. The existing `make_minion_unit_data_extension` builder at `tests/test_helper.lua:199` is the correct tool.

**Files:**
- Modify: `tests/grenade_fallback_spec.lua:504-514`

- [ ] **Step 1: Replace the builder call**

```lua
_extensions.enemy_1 = {
	unit_data_system = test_helper.make_minion_unit_data_extension({
		name = "chaos_traitor_gunner",
		tags = { special = true },
		ranged = true,
		game_object_type = "minion_ranged",
	}),
}
```

- [ ] **Step 2: Verify the test still exercises the same path**

Run: `busted tests/grenade_fallback_spec.lua`
Expected: the `normalizes priority-only targets before evaluating and selecting Assail profile` test still passes. If production code paths for this enemy unit are reading `read_component` on a minion, that's a production bug — report it before patching the test.

- [ ] **Step 3: Commit**

```bash
git add tests/grenade_fallback_spec.lua
git commit -m "test(grenade_fallback): use minion builder for minion breed (mock fidelity #95)"
```

---

### Task 13a: Extend mock audit doc + ScriptUnit-family regex

Add `input_system` and `behavior_system` to `scripts/doc-check.sh:137` `audited_extension_regex`. These are listed in `docs/dev/mock-api-audit.md:31, 40` as audited surfaces accessed via `ScriptUnit.has_extension`, but the doc-check silently excludes them. `side_system` and `liquid_area_system` are NOT ScriptUnit extensions — they're manager-system doubles, handled by T13b.

Also record in the audit:
- `BotUnitInput` method surface returned by `PlayerUnitInputExtension:bot_unit_input()` (existing entry at `docs/dev/mock-api-audit.md:31` covers the extension method but not the object it returns). Methods: `set_aiming()`, `set_aim_rotation()`, `set_aim_position()`.
- `side.valid_player_units` private field on `Side` (currently read by `heuristics_context.lua:48-56` with no audit entry).

**Files:**
- Modify: `docs/dev/mock-api-audit.md` (add BotUnitInput row + side private field row)
- Modify: `tests/test_helper.lua` (add `make_player_input_extension` + `make_bot_unit_input` builders)
- Modify: `tests/grenade_fallback_spec.lua` (`BotUnitInput` raw mocks at ~`:47-74`, route through builder)
- Modify: `scripts/doc-check.sh:137` (add `input_system|behavior_system` only)

- [ ] **Step 1: Inventory existing raw literals for `input_system` + `behavior_system`**

```bash
rg -n '"input_system"|"behavior_system"' tests/
```

Each match that appears inside a `has_extension` / `extension` mock needs conversion BEFORE the regex is extended. Count the hits up front — fix them first.

- [ ] **Step 2: Add builders to `test_helper.lua`**

`make_bot_unit_input` wraps the inner object; `make_player_input_extension` returns a pre-built `BotUnitInput` via `bot_unit_input()` — callers pass a built inner object, not a raw nested table.

```lua
function M.make_bot_unit_input(overrides)
	local ext = {
		set_aiming = function() end,
		set_aim_rotation = function() end,
		set_aim_position = function() end,
	}
	_apply_audited_overrides("make_bot_unit_input", ext, overrides, {
		set_aiming = true,
		set_aim_rotation = true,
		set_aim_position = true,
	})
	return ext
end

function M.make_player_input_extension(opts)
	opts = opts or {}
	local bot_input = opts.bot_unit_input or M.make_bot_unit_input()
	local ext = {
		bot_unit_input = function() return bot_input end,
	}
	_apply_audited_overrides("make_player_input_extension", ext, opts.overrides, {
		bot_unit_input = true,
	})
	return ext
end
```

- [ ] **Step 3: Convert existing raw literals to builder calls**

Route each inventory hit from Step 1 through the builders. One spec at a time, `busted <spec>` after each.

- [ ] **Step 4: Extend the audit doc**

Append to `docs/dev/mock-api-audit.md` Audited extension surfaces table:

```markdown
| `input_system` returned `BotUnitInput` | `BotUnitInput` | `set_aiming()`, `set_aim_rotation()`, `set_aim_position()` | `../Darktide-Source-Code/scripts/extension_systems/input/bot_unit_input.lua:95-107` | Returned by `PlayerUnitInputExtension:bot_unit_input()`. Grenade aim control reads this. |
| `side_system` `Side` private field | `Side` | `valid_player_units` (private) | `../Darktide-Source-Code/scripts/extension_systems/side/side.lua:33-39` | Private field; `heuristics_context.lua:48-56` reads it directly. |
```

- [ ] **Step 5: Extend doc-check regex (ScriptUnit families only)**

```bash
# scripts/doc-check.sh:137
audited_extension_regex='unit_data_system|ability_system|action_input_system|perception_system|smart_tag_system|companion_spawner_system|coherency_system|talent_system|input_system|behavior_system'
```

Note: `side_system` and `liquid_area_system` are NOT in this regex — they are accessed via `Managers.state.extension:system(...)`, not `ScriptUnit.has_extension(...)`. T13b handles them.

- [ ] **Step 6: Run `make doc-check`**

Expected: clean. If a raw literal slipped through Step 3, fix it now — do not loosen the regex.

- [ ] **Step 7: Commit**

```bash
git add docs/dev/mock-api-audit.md tests/test_helper.lua tests/grenade_fallback_spec.lua scripts/doc-check.sh
git commit -m "test(hygiene): enforce ScriptUnit audited families (input_system, behavior_system) + record BotUnitInput surface"
```

---

### Task 13b: Manager-system doubles enforcement (`side_system`, `liquid_area_system`)

Manager-system doubles — returned by `Managers.state.extension:system("side_system")` etc. — are a different class-split from ScriptUnit extensions. Currently raw in `tests/heuristics_spec.lua:2231, 2255` and `tests/sprint_spec.lua:44-51`. A separate `doc-check` rule and separate `test_helper` builders are needed.

**Files:**
- Modify: `tests/test_helper.lua` (add `make_side_system_double`, `make_liquid_area_system_double`)
- Modify: affected specs: `tests/heuristics_spec.lua:2231, 2255`, `tests/sprint_spec.lua:44-51` (route through builders)
- Modify: `scripts/doc-check.sh` (append a new check section for manager-system doubles, mirroring the existing extension-family check)

- [ ] **Step 1: Inventory raw literals**

```bash
rg -nUP 'Managers\.state\.extension:system\([^)]+\).*\n.*=\s*\{' tests/ -A 2 || true
rg -n '"side_system"|"liquid_area_system"' tests/
```

- [ ] **Step 2: Add builders**

Per `docs/dev/mock-api-audit.md:46-47`:

```lua
function M.make_side_system_double(overrides)
	local ext = {
		side_by_unit = overrides and overrides.side_by_unit or {},
		get_side_from_name = overrides and overrides.get_side_from_name or function() return nil end,
		relation_side_names = overrides and overrides.relation_side_names or function() return {} end,
	}
	return ext
end

function M.make_liquid_area_system_double(overrides)
	local ext = {
		find_liquid_areas_in_position = overrides and overrides.find_liquid_areas_in_position or function() return nil end,
		is_position_in_liquid = overrides and overrides.is_position_in_liquid or function() return false end,
	}
	return ext
end
```

Allowlist enforcement mirrors `_apply_audited_overrides` — if the builder accepts arbitrary overrides today, add rejection of unknown keys here too.

- [ ] **Step 3: Convert existing specs**

Route `heuristics_spec.lua:2231, 2255` and `sprint_spec.lua:44-51` through the builders. Run `busted <spec>` after each conversion.

- [ ] **Step 4: Add manager-system check to `doc-check.sh`**

Append after the existing ScriptUnit block (~line 157):

```bash
# ── 5b. Manager-system doubles ───────────────────────────────────────────────
audited_manager_regex='side_system|liquid_area_system'

manager_ad_hoc_matches=$(rg -nUP ":system\\(\"(${audited_manager_regex})\"\\)[^\\n]*\\n\\s*return\\s*\\{" tests/*_spec.lua 2>/dev/null || true)
if [[ -n "$manager_ad_hoc_matches" ]]; then
  err "audited Managers.state.extension:system(...) doubles must use tests/test_helper.lua builders:
$manager_ad_hoc_matches"
fi

ok "audited manager-system doubles route through shared builders"
```

- [ ] **Step 5: Run `make doc-check`**

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add tests/test_helper.lua tests/heuristics_spec.lua tests/sprint_spec.lua scripts/doc-check.sh docs/dev/mock-api-audit.md
git commit -m "test(hygiene): enforce audited manager-system doubles (side_system, liquid_area_system)"
```

---

## Post-plan verification

Before tagging v1.0.0:

- [ ] `make check-ci` green locally
- [ ] All commits present on `main`
- [ ] Full in-game cold-boot test per CLAUDE.md "In-game" testing section
- [ ] `bb-log summary` shows no new DMF warnings vs baseline
- [ ] Nexus description + changelog drafted per `docs/nexus-description.bbcode`

## Out of scope (tracked but not addressed here)

- Coverage tool (`luacov`) integration — nice-to-have, not a blocker
- Mutation / property-based testing — overkill for v1.0.0
- Deterministic `make package` zip — cosmetic, track as follow-up issue
- CI tool version pinning (`busted`, `luacheck`) — maintenance debt
- `release.sh:61-64` tag-before-artifact upload race — rare failure mode, track as follow-up
- `startup_regressions_spec.lua:618-710` source-regex block — pre-existing confidence theater, separate cleanup effort
- Hot-path `_debug_enabled()` gating assertion tests — tracked, not blocker
