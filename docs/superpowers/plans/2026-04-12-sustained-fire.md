# Sustained Fire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bots hold sustained-fire raw input for supported held-fire ranged weapons instead of tap-firing them.

**Architecture:** Add a focused `sustained_fire.lua` module that observes queued weapon action inputs, resolves whether they map to supported sustained-fire paths, stores per-unit sustained state, and injects `action_one_hold` through `BotUnitInput._update_actions`. Keep `#87` execution-only: no ADS/brace selection policy, no target-persistence changes, no broad `weapon_action.lua` sprawl.

**Tech Stack:** Lua, DMF hooks, busted, Darktide weapon template data

---

## File Map

- Create: `scripts/mods/BetterBots/sustained_fire.lua`
  - Own sustained-fire template resolution, per-unit state, hook registration, and debug logs.
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
  - Wire new module through `init()` / `register_hooks()`.
- Modify: `tests/startup_regressions_spec.lua`
  - Assert new module is wired.
- Create: `tests/sustained_fire_spec.lua`
  - Cover detection, hold injection, and clear conditions.
- Modify: `docs/dev/architecture.md`
  - Document new module and hook points.
- Modify: `docs/dev/roadmap.md`
  - Mark `#87` implemented when done.
- Modify: `docs/dev/status.md`
  - Record shipped behavior.
- Modify: `docs/bot/input-system.md`
  - Document sustained-fire raw-hold bridge.
- Modify: `docs/bot/vanilla-capabilities.md`
  - Update held-fire limitation/status.
- Modify: `README.md`
  - Update highlights/module counts/test counts if needed.
- Modify: `AGENTS.md`
  - Update module/test inventory counts.

### Task 1: Add failing sustained-fire detection tests

**Files:**
- Create: `tests/sustained_fire_spec.lua`

- [ ] **Step 1: Write failing tests for supported and unsupported paths**

```lua
describe("sustained_fire", function()
	it("arms held-primary sustained state for recon lasgun fire", function()
		local state = SustainedFire.observe_weapon_action_input(bot_unit, "lasgun_p3_m1", "shoot_pressed")
		assert.is_truthy(state)
		assert.equals("action_one_hold", state.hold_input)
	end)

	it("arms sustained state for flamer braced stream", function()
		local state = SustainedFire.observe_weapon_action_input(bot_unit, "flamer_p1_m1", "shoot_braced")
		assert.is_truthy(state)
		assert.equals("action_one_hold", state.hold_input)
	end)

	it("does not arm sustained state for rippergun burst hipfire", function()
		local state = SustainedFire.observe_weapon_action_input(bot_unit, "ogryn_rippergun_p1_m1", "shoot")
		assert.is_nil(state)
	end)

	it("arms sustained state for rippergun braced fire", function()
		local state = SustainedFire.observe_weapon_action_input(bot_unit, "ogryn_rippergun_p1_m1", "zoom_shoot")
		assert.is_truthy(state)
	end)
end)
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
```

Expected: FAIL with missing module/function errors.

- [ ] **Step 3: Commit failing test scaffold**

```bash
git add tests/sustained_fire_spec.lua
git commit -m "test(v0.11.0): add sustained fire coverage scaffold"
```

### Task 2: Implement sustained-fire path resolution

**Files:**
- Create: `scripts/mods/BetterBots/sustained_fire.lua`
- Test: `tests/sustained_fire_spec.lua`

- [ ] **Step 1: Add minimal module skeleton**

```lua
local M = {}

function M.init(deps)
	-- stash deps
end

function M.observe_weapon_action_input(_unit, _template_name, _action_input)
	return nil
end

return M
```

- [ ] **Step 2: Implement template/action-input resolver**

```lua
local SUSTAINED_ACTION_INPUTS = {
	flamer_p1_m1 = { shoot_braced = true },
	forcestaff_p2_m1 = { trigger_charge_flame = true },
	lasgun_p3_m1 = { shoot_pressed = true, zoom_shoot = true },
	lasgun_p3_m2 = { shoot_pressed = true, zoom_shoot = true },
	lasgun_p3_m3 = { shoot_pressed = true, zoom_shoot = true },
}

function M.observe_weapon_action_input(unit, template_name, action_input)
	local supported = SUSTAINED_ACTION_INPUTS[template_name]
	if not supported or not supported[action_input] then
		return nil
	end

	return {
		unit = unit,
		template_name = template_name,
		action_input = action_input,
		hold_input = "action_one_hold",
	}
end
```

Then extend the table for:

- `autogun_p1_m1/m2/m3`
- `autogun_p2_m1/m2/m3`
- `autopistol_p1_m1`
- `dual_autopistols_p1_m1`
- `bolter_p1_m2`
- `ogryn_heavystubber_p1_m1/m2/m3`
- `ogryn_heavystubber_p2_m1/m2/m3`
- `ogryn_rippergun_p1_m1/m2` with `zoom_shoot` only

- [ ] **Step 3: Run focused tests**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
```

Expected: detection tests PASS; later hook/injection tests still FAIL.

- [ ] **Step 4: Commit resolver**

```bash
git add scripts/mods/BetterBots/sustained_fire.lua tests/sustained_fire_spec.lua
git commit -m "feat(v0.11.0): resolve sustained fire weapon paths"
```

### Task 3: Add per-unit sustained state and hold injection

**Files:**
- Modify: `scripts/mods/BetterBots/sustained_fire.lua`
- Test: `tests/sustained_fire_spec.lua`

- [ ] **Step 1: Write failing hold-injection and clear-condition tests**

```lua
it("injects action_one_hold while sustained state is active", function()
	local input = {}
	SustainedFire.arm(bot_unit, {
		template_name = "lasgun_p3_m1",
		action_input = "shoot_pressed",
		hold_input = "action_one_hold",
	})

	SustainedFire.update_actions(bot_unit, input)

	assert.is_true(input.action_one_hold)
end)

it("clears sustained state on reload", function()
	SustainedFire.arm(bot_unit, state)
	SustainedFire.observe_weapon_action_input(bot_unit, "lasgun_p3_m1", "reload")
	assert.is_nil(SustainedFire.active_state(bot_unit))
end)
```

- [ ] **Step 2: Run focused test to verify failure**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
```

Expected: FAIL on missing `arm`, `update_actions`, or clear behavior.

- [ ] **Step 3: Implement state machine**

```lua
local _active_by_unit = setmetatable({}, { __mode = "k" })
local CLEARING_INPUTS = {
	reload = true,
	wield = true,
	vent = true,
}

function M.arm(unit, state)
	_active_by_unit[unit] = state
end

function M.active_state(unit)
	return _active_by_unit[unit]
end

function M.clear(unit)
	_active_by_unit[unit] = nil
end

function M.update_actions(unit, input)
	local state = _active_by_unit[unit]
	if not state then
		return
	end

	input[state.hold_input] = true
end
```

In `observe_weapon_action_input(...)`:

```lua
if CLEARING_INPUTS[action_input] then
	M.clear(unit)
	return nil
end

local state = resolve_state(...)
if state then
	M.arm(unit, state)
end
return state
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit state machine**

```bash
git add scripts/mods/BetterBots/sustained_fire.lua tests/sustained_fire_spec.lua
git commit -m "feat(v0.11.0): inject sustained fire hold input"
```

### Task 4: Hook game integration points

**Files:**
- Modify: `scripts/mods/BetterBots/sustained_fire.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Test: `tests/startup_regressions_spec.lua`

- [ ] **Step 1: Write failing startup wiring regression**

```lua
it("wires sustained_fire module", function()
	assert.is_truthy(loaded_modules["sustained_fire"])
end)
```

- [ ] **Step 2: Run targeted startup regression test**

Run:

```bash
make test TESTS=tests/startup_regressions_spec.lua
```

Expected: FAIL until module is wired.

- [ ] **Step 3: Hook queue observer and BotUnitInput injection**

In `sustained_fire.lua` register hooks roughly like:

```lua
_mod:hook_require(
	"scripts/extension_systems/action_input/player_unit_action_input_extension",
	function(PlayerUnitActionInputExtension)
		_mod:hook_safe(PlayerUnitActionInputExtension, "extensions_ready", function(self, _world, unit)
			self._betterbots_player_unit = unit
		end)

		_mod:hook(PlayerUnitActionInputExtension, "bot_queue_action_input", function(func, self, id, action_input, raw_input)
			local result = func(self, id, action_input, raw_input)
			if id == "weapon_action" then
				M.observe_queued_input(self._betterbots_player_unit, action_input, raw_input)
			end
			return result
		end)
	end
)

_mod:hook_require("scripts/extension_systems/input/bot_unit_input", function(BotUnitInput)
	_mod:hook(BotUnitInput, "_update_actions", function(func, self, input)
		func(self, input)
		M.inject_hold_from_bot_input(self, input)
	end)
end)
```

Wire in `BetterBots.lua` via `mod:io_dofile(...)`, `init`, and `register_hooks`.

- [ ] **Step 4: Run targeted tests**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
make test TESTS=tests/startup_regressions_spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit integration**

```bash
git add scripts/mods/BetterBots/sustained_fire.lua scripts/mods/BetterBots/BetterBots.lua tests/sustained_fire_spec.lua tests/startup_regressions_spec.lua
git commit -m "feat(v0.11.0): wire sustained fire hooks"
```

### Task 5: Add permanent debug logs and stale-state guards

**Files:**
- Modify: `scripts/mods/BetterBots/sustained_fire.lua`
- Test: `tests/sustained_fire_spec.lua`

- [ ] **Step 1: Write failing tests for stale clear paths if missing**

```lua
it("clears sustained state when weapon template changes", function()
	SustainedFire.arm(bot_unit, old_state)
	set_weapon_template(bot_unit, "combat_axe_p1_m1")
	SustainedFire.update_actions(bot_unit, input)
	assert.is_nil(SustainedFire.active_state(bot_unit))
end)
```

- [ ] **Step 2: Implement stale guards and one-shot logs**

Add:

```lua
local _hold_logged = setmetatable({}, { __mode = "k" })

local function _log_arm(unit, state) end
local function _log_clear(unit, reason) end
local function _log_hold_once(unit, state) end
```

Guard conditions:

- no current weapon template
- template changed from armed template
- unsupported queued input replaces sustained path
- explicit clear inputs

- [ ] **Step 3: Run focused tests**

Run:

```bash
make test TESTS=tests/sustained_fire_spec.lua
```

Expected: PASS.

- [ ] **Step 4: Commit guards/logs**

```bash
git add scripts/mods/BetterBots/sustained_fire.lua tests/sustained_fire_spec.lua
git commit -m "feat(v0.11.0): add sustained fire debug guards"
```

### Task 6: Update docs and repo metadata

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/bot/input-system.md`
- Modify: `docs/bot/vanilla-capabilities.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update architecture and behavior docs**

Document:

- new `sustained_fire.lua` module
- queue observer + `BotUnitInput._update_actions` injection path
- supported sustained-fire families
- `#87` scope boundary vs `#41`

- [ ] **Step 2: Update inventory/count docs**

Adjust:

- module counts
- test counts
- `make test` suite list if new spec file added

- [ ] **Step 3: Commit docs**

```bash
git add docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md docs/bot/input-system.md docs/bot/vanilla-capabilities.md README.md AGENTS.md
git commit -m "docs(v0.11.0): document sustained fire support"
```

### Task 7: Full verification and final commit cleanup

**Files:**
- Modify: working tree as needed from failures

- [ ] **Step 1: Run targeted suite**

```bash
make test TESTS=tests/sustained_fire_spec.lua
make test TESTS=tests/startup_regressions_spec.lua
```

Expected: PASS.

- [ ] **Step 2: Run full suite and doc gate**

```bash
make test
make doc-check
make check
```

Expected:

- `make test`: all tests pass, count increases by new sustained-fire spec coverage
- `make doc-check`: PASS
- `make check`: PASS

- [ ] **Step 3: If verification required follow-up edits, commit them**

```bash
git add scripts/mods/BetterBots/sustained_fire.lua scripts/mods/BetterBots/BetterBots.lua tests/sustained_fire_spec.lua tests/startup_regressions_spec.lua docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md docs/bot/input-system.md docs/bot/vanilla-capabilities.md README.md AGENTS.md
git commit -m "feat(v0.11.0): add sustained fire support"
```

## Self-Review

- Spec coverage: all required pieces mapped: supported template list, execution-only scope, queue observation, `BotUnitInput` hold injection, mixed rippergun handling, stale clear rules, permanent debug logs, tests, docs.
- Placeholder scan: no `TODO` / `TBD` / “similar to above” shortcuts remain.
- Type consistency: plan uses one module name (`sustained_fire.lua`), one main entrypoints family (`observe_weapon_action_input`, `arm`, `clear`, `update_actions`), and one raw hold input (`action_one_hold`) throughout.
