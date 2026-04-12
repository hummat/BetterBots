# Grenade Ballistic Aim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BetterBots use ballistic aim rotation for supported gravity-arc grenade fallback projectiles while preserving flat-aim fallback for unsupported projectile families.

**Architecture:** Keep the patch local to `grenade_fallback.lua`. Add projectile-aware aim helpers that resolve grenade projectile data, decide whether ballistic solving applies, compute vanilla-style aim rotation with target lead, and fall back cleanly to flat `set_aim_position` when data is unavailable or excluded. Extend grenade fallback tests first, then implement the minimum code to satisfy them, then update docs.

**Tech Stack:** Lua 5.x, DMF mod modules, busted tests, StyLua, project Makefile checks

---

## File Map

- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`
  - Add projectile-aware aim helpers
  - Keep current state machine and queue timing unchanged
  - Add narrow debug logging for ballistic/fallback/solver-fail paths
- Modify: `tests/grenade_fallback_spec.lua`
  - Add failing tests for ballistic aim path and fallback behavior
  - Stub projectile/trajectory helpers instead of loading full engine projectile tables
- Modify: `docs/classes/grenade-inventory.md`
  - Update known aim limitation and correct stale zealot-knife note
- Modify: `docs/dev/architecture.md`
  - Note local ballistic aim solver in grenade fallback path
- Modify: `docs/dev/roadmap.md`
  - Mark `#93` as implemented on branch with exact scope
- Modify: `docs/dev/status.md`
  - Mark `#93` implemented on branch under v0.11.0 batch

## Task 1: Add Failing Tests For Ballistic Aim Selection

**Files:**
- Modify: `tests/grenade_fallback_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write failing test for supported ballistic path**

Add a test near the existing aim-related coverage:

```lua
	it("uses aim rotation for supported ballistic projectiles", function()
		local mock_rotation = { yaw = 1, pitch = 2 }

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "ballistic",
					speed = 30,
					gravity = 12.5,
				}
			end,
			solve_ballistic_rotation = function()
				return mock_rotation
			end,
		})

		advance_to_stage("wait_aim")

		local saw_rotation = false
		local saw_use_rotation = false

		for i = 1, #_aim_calls do
			local call = _aim_calls[i]
			if call.method == "set_aim_rotation" then
				saw_rotation = true
				assert.same(mock_rotation, call.rotation)
			end
			if call.method == "set_aiming" and call.use_rotation == true then
				saw_use_rotation = true
			end
		end

		assert.is_true(saw_rotation)
		assert.is_true(saw_use_rotation)
	end)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- FAIL because `grenade_fallback.lua` does not yet expose projectile-aware aim wiring
- likely failure: no `set_aim_rotation` call recorded

- [ ] **Step 3: Write failing test for unsupported projectile fallback**

Add:

```lua
	it("falls back to flat aim for excluded projectile families", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_missile_launcher"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "broker_missile_launcher" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return {
					mode = "flat",
				}
			end,
		})

		advance_to_stage("wait_aim")

		assert.same("set_aim_position", _aim_calls[#_aim_calls].method)
	end)
```

- [ ] **Step 4: Run test to verify it fails for the right reason**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- FAIL because supported ballistic path is still flat aim
- unsupported fallback test may already pass; that is acceptable

- [ ] **Step 5: Commit failing tests only**

```bash
git add tests/grenade_fallback_spec.lua
git commit -m "test(v0.11.0): add grenade ballistic aim coverage"
```

## Task 2: Implement Projectile-Aware Aim Helpers

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Add dependency-injected helper slots**

In `grenade_fallback.lua`, add late-bound helper refs near the existing `_resolve_bot_target_unit_fn` declaration:

```lua
local _resolve_grenade_projectile_data
local _solve_ballistic_rotation
```

And extend `wire({...})` to accept them with defaults:

```lua
function M.wire(deps)
	_build_context = deps.build_context
	_evaluate_grenade_heuristic = deps.evaluate_grenade_heuristic
	_equipped_grenade_ability = deps.equipped_grenade_ability
	_is_combat_ability_active = deps.is_combat_ability_active
	_is_grenade_enabled = deps.is_grenade_enabled
	_resolve_bot_target_unit_fn = deps.resolve_bot_target_unit
	_resolve_grenade_projectile_data = deps.resolve_grenade_projectile_data or _default_resolve_grenade_projectile_data
	_solve_ballistic_rotation = deps.solve_ballistic_rotation or _default_solve_ballistic_rotation
end
```

- [ ] **Step 2: Add projectile-data resolver and ballistic-exclusion logic**

Add local helpers in `grenade_fallback.lua`:

```lua
local BALLISTIC_GRENADE_NAMES = {
	veteran_frag_grenade = true,
	veteran_smoke_grenade = true,
	veteran_krak_grenade = true,
	zealot_fire_grenade = true,
	zealot_shock_grenade = true,
	ogryn_grenade_box = true,
	ogryn_grenade_box_cluster = true,
	ogryn_grenade_frag = true,
	ogryn_grenade_friend_rock = true,
	adamant_grenade = true,
	adamant_grenade_improved = true,
	broker_flash_grenade = true,
	broker_flash_grenade_improved = true,
	broker_tox_grenade = true,
	zealot_throwing_knives = true,
}

local EXCLUDED_FLAT_GRENADE_NAMES = {
	broker_missile_launcher = true,
	psyker_throwing_knives = true,
	adamant_whistle = true,
	adamant_shock_mine = true,
	psyker_smite = true,
	psyker_chain_lightning = true,
}
```

And a default resolver:

```lua
local function _default_resolve_grenade_projectile_data(grenade_name)
	if EXCLUDED_FLAT_GRENADE_NAMES[grenade_name] then
		return { mode = "flat", reason = "excluded_family" }
	end

	if not BALLISTIC_GRENADE_NAMES[grenade_name] then
		return { mode = "flat", reason = "unsupported_family" }
	end

	if grenade_name == "zealot_throwing_knives" then
		return { mode = "ballistic", speed = 75, gravity = 17.5 }
	end

	if string.find(grenade_name, "ogryn_grenade_", 1, true) then
		return { mode = "ballistic", speed = 60, gravity = 10.5 }
	end

	return { mode = "ballistic", speed = 30, gravity = 12.5 }
end
```

This is intentionally minimal and follows the approved scope. Do not widen it beyond the listed families.

- [ ] **Step 3: Add target-velocity helper and default ballistic solver**

Add:

```lua
local ACCEPTABLE_ACCURACY = 0.1

local function _target_velocity(target_unit)
	local unit_data_extension = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if unit_data_extension then
		local locomotion_component = unit_data_extension:read_component("locomotion")
		if locomotion_component and locomotion_component.velocity_current then
			return locomotion_component.velocity_current
		end
	end

	local locomotion_extension = ScriptUnit.has_extension(target_unit, "locomotion_system")
	if locomotion_extension and locomotion_extension.current_velocity then
		return locomotion_extension:current_velocity()
	end

	return Vector3.zero()
end

local function _default_solve_ballistic_rotation(unit, aim_unit, projectile_data)
	local unit_position = POSITION_LOOKUP and POSITION_LOOKUP[unit]
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[aim_unit]
	if not unit_position or not target_position then
		return nil, "position_lookup_missing"
	end

	local target_velocity = _target_velocity(aim_unit)
	local angle, solved_target_position = Trajectory.angle_to_hit_moving_target(
		unit_position,
		target_position,
		projectile_data.speed,
		target_velocity,
		projectile_data.gravity,
		ACCEPTABLE_ACCURACY,
		false
	)
	if not angle then
		return nil, "trajectory_solver_failed"
	end

	local flat_direction = Vector3.normalize(Vector3.flat(solved_target_position - unit_position))
	local look_rotation = Quaternion.look(flat_direction, Vector3.up())
	local wanted_rotation = Quaternion.multiply(look_rotation, Quaternion(Vector3.right(), angle))

	return wanted_rotation
end
```

- [ ] **Step 4: Replace `_set_bot_aim()` with ballistic-or-flat selection**

Update `_set_bot_aim(unit, aim_unit)` to:

```lua
local function _set_bot_aim(unit, aim_unit, grenade_name)
	if not aim_unit then
		return false, "no_target_unit"
	end

	if not POSITION_LOOKUP then
		return false, "position_lookup_unavailable"
	end

	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local bot_unit_input = input_extension and input_extension.bot_unit_input and input_extension:bot_unit_input()
	if not bot_unit_input then
		return false, "bot_input_missing"
	end

	local projectile_data = _resolve_grenade_projectile_data and _resolve_grenade_projectile_data(grenade_name) or nil
	if projectile_data and projectile_data.mode == "ballistic" then
		local wanted_rotation, reason = _solve_ballistic_rotation(unit, aim_unit, projectile_data)
		if wanted_rotation then
			bot_unit_input:set_aiming(true, false, true)
			bot_unit_input:set_aim_rotation(wanted_rotation)
			return true, "ballistic"
		end

		if _debug_enabled() then
			_debug_log("grenade_aim_solver_fail:" .. tostring(unit), _fixed_time(), "grenade aim solver fallback (" .. tostring(reason) .. ")")
		end
	end

	local aim_position = POSITION_LOOKUP[aim_unit]
	if not aim_position then
		return false, "target_position_missing"
	end

	bot_unit_input:set_aiming(true, false, false)
	bot_unit_input:set_aim_position(aim_position)
	return true, projectile_data and projectile_data.reason or "flat"
end
```

Then update `_refresh_bot_aim(...)` call site to pass `state.grenade_name`.

- [ ] **Step 5: Run narrow grenade fallback tests**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- PASS

- [ ] **Step 6: Commit minimal implementation**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(v0.11.0): add ballistic grenade aim"
```

## Task 3: Add Explicit Logging Coverage For Ballistic vs Flat Aim

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Modify: `tests/grenade_fallback_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write failing test for ballistic debug log**

Add:

```lua
	it("logs ballistic aim path when debug is enabled", function()
		_debug_enabled_result = true

		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3, target_enemy = "enemy_1", target_enemy_distance = 20 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_frag_horde"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "veteran_frag_grenade" }
			end,
			is_combat_ability_active = function()
				return false
			end,
			is_grenade_enabled = function()
				return true
			end,
			resolve_grenade_projectile_data = function()
				return { mode = "ballistic", speed = 30, gravity = 12.5 }
			end,
			solve_ballistic_rotation = function()
				return { yaw = 1 }
			end,
		})

		advance_to_stage("wait_aim")
		assert.truthy(find_debug_log("grenade aim ballistic"))
	end)
```

- [ ] **Step 2: Run narrow test to verify it fails**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- FAIL because no ballistic confirmation log exists yet

- [ ] **Step 3: Add minimal confirmation logs**

In `_refresh_bot_aim(...)`, after `_set_bot_aim(...)` succeeds, emit:

```lua
if _debug_enabled() and aim_reason == "ballistic" then
	_debug_log(
		"grenade_aim_ballistic:" .. tostring(unit),
		fixed_t,
		"grenade aim ballistic"
	)
elseif _debug_enabled() and aim_reason ~= "ballistic" then
	_debug_log(
		"grenade_aim_flat_fallback:" .. tostring(unit),
		fixed_t,
		"grenade aim flat fallback (" .. tostring(aim_reason) .. ")"
	)
end
```

- [ ] **Step 4: Run grenade fallback tests again**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- PASS

- [ ] **Step 5: Commit logging refinement**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "test(v0.11.0): verify grenade aim path logging"
```

## Task 4: Update Docs For #93 And Zealot Knife Correction

**Files:**
- Modify: `docs/classes/grenade-inventory.md`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`

- [ ] **Step 1: Update grenade inventory limitation note**

Replace the stale limitation text in `docs/classes/grenade-inventory.md` with:

```md
**Known aim limitation:** BetterBots grenade fallback now uses ballistic aim rotation for gravity-affected manual-physics projectile families by mirroring vanilla `Trajectory.angle_to_hit_moving_target(...)` math. Covered families: standard grenades, handleless grenades, Ogryn grenade throws, and zealot throwing knives. Excluded: `broker_missile` (near-flat), psyker knives (true-flight), whistle, smite, chain lightning, and mines.
```

- [ ] **Step 2: Update architecture doc**

Add a bullet in `docs/dev/architecture.md` under the grenade fallback/module list:

```md
- grenade ballistic aim (#93): `grenade_fallback.lua` resolves supported projectile families and switches from flat `set_aim_position` to vanilla-style solved `set_aim_rotation` for gravity-arc throws, with flat fallback for excluded or unavailable projectile data
```

- [ ] **Step 3: Update roadmap and status**

Change `#93` entry in `docs/dev/roadmap.md` and v0.11.0 line in `docs/dev/status.md` to implemented-on-branch wording:

```md
| 93 | Grenade ballistic arc fix | Implemented on branch. `grenade_fallback.lua` now uses ballistic aim rotation for supported manual-physics gravity projectiles (standard grenades, Ogryn throws, zealot knives) while leaving near-flat/true-flight/non-ballistic families on flat fallback. |
```

And:

```md
- **v0.11.0 "Combat Execution" (final polish batch)**: ... #93 (grenade ballistic arc fix — implemented on branch: ballistic rotation for supported gravity projectiles, flat fallback preserved for excluded families)
```

- [ ] **Step 4: Run doc gate**

Run:

```bash
make doc-check
```

Expected:
- `doc-check: all checks passed`

- [ ] **Step 5: Commit docs**

```bash
git add docs/classes/grenade-inventory.md docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md
git commit -m "docs(v0.11.0): document grenade ballistic aim"
```

## Task 5: Final Verification

**Files:**
- Modify: none
- Test: full suite

- [ ] **Step 1: Run targeted grenade tests**

Run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected:
- PASS

- [ ] **Step 2: Run full test suite**

Run:

```bash
make test
```

Expected:
- `... successes / 0 failures / 0 errors`

- [ ] **Step 3: Run doc gate**

Run:

```bash
make doc-check
```

Expected:
- `doc-check: all checks passed`

- [ ] **Step 4: Inspect worktree**

Run:

```bash
git status --short
git diff --stat
```

Expected:
- only intended `#93` files changed

- [ ] **Step 5: Final integration commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua docs/classes/grenade-inventory.md docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md
git commit -m "feat(v0.11.0): fix grenade ballistic aim"
```

## Self-Review

- Spec coverage: all approved scope points mapped
  - ballistic-only supported families: Task 2
  - excluded families: Task 2 + Task 4 docs
  - logging: Task 3
  - tests: Tasks 1, 3, 5
  - doc correction for zealot knives: Task 4
- Placeholder scan: none left; each task has concrete files, code, commands, expected output
- Consistency check: helper names stay consistent across tasks (`_resolve_grenade_projectile_data`, `_solve_ballistic_rotation`, `_set_bot_aim`)
