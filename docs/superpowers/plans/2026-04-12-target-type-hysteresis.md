# Target Type Hysteresis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop melee/ranged `target_enemy_type` flip thrash by adding perception-layer hysteresis with a margin requirement and momentum bonus.

**Architecture:** Add a small `target_type_hysteresis.lua` module that provides a pure chooser and installs a hook on `bot_target_selection_template.bot_default`. The hook stabilizes the final melee/ranged type decision in both full reevaluation and current-target-only rescoring without adding any BT cooldown layer.

**Tech Stack:** Lua, busted, BetterBots module wiring, Darktide perception target-selection template

---

## File Map

- Create: `scripts/mods/BetterBots/target_type_hysteresis.lua`
  - pure hysteresis chooser
  - hook installer for target-selection template
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
  - load/init new module
  - register hook installation
- Create: `tests/target_type_hysteresis_spec.lua`
  - chooser tests for margin + momentum
- Modify: `README.md`
  - update module/test counts
- Modify: `AGENTS.md`
  - update test list + module list/count
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/bot/perception-targeting.md`
  - document BetterBots hysteresis override

### Task 1: Add Failing Hysteresis Tests

**Files:**
- Create: `tests/target_type_hysteresis_spec.lua`

- [ ] **Step 1: Write the failing pure-function tests**

Create `tests/target_type_hysteresis_spec.lua`:

```lua
local Hysteresis = dofile("scripts/mods/BetterBots/target_type_hysteresis.lua")

describe("target_type_hysteresis", function()
	it("uses raw winner when current type is none", function()
		local chosen = Hysteresis.choose_target_type("none", 12, 8)
		assert.equals("melee", chosen)
	end)

	it("keeps current melee type on close scores", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.4)
		assert.equals("melee", chosen)
	end)

	it("keeps current ranged type on close scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 10.4, 10)
		assert.equals("ranged", chosen)
	end)

	it("flips when the opposite type wins by more than the margin", function()
		local chosen = Hysteresis.choose_target_type("ranged", 14, 10)
		assert.equals("melee", chosen)
	end)

	it("applies momentum bonus to the current type", function()
		local chosen = Hysteresis.choose_target_type("melee", 10, 10.49)
		assert.equals("melee", chosen)
	end)

	it("scales margin with larger scores", function()
		local chosen = Hysteresis.choose_target_type("ranged", 100, 108)
		assert.equals("ranged", chosen)
	end)
end)
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
make test TESTS=tests/target_type_hysteresis_spec.lua
```

Expected: FAIL because module does not exist yet.

### Task 2: Implement Pure Hysteresis Chooser

**Files:**
- Create: `scripts/mods/BetterBots/target_type_hysteresis.lua`
- Test: `tests/target_type_hysteresis_spec.lua`

- [ ] **Step 1: Create the module with constants and chooser**

Create `scripts/mods/BetterBots/target_type_hysteresis.lua`:

```lua
local M = {}

local MARGIN_FACTOR = 0.10
local MOMENTUM_FACTOR = 0.05

local function _abs(x)
	return x < 0 and -x or x
end

local function _max3(a, b, c)
	local ab = a > b and a or b
	return ab > c and ab or c
end

function M.init(deps)
	M._mod = deps and deps.mod or nil
	M._debug_log = deps and deps.debug_log or nil
	M._debug_enabled = deps and deps.debug_enabled or nil
	M._fixed_time = deps and deps.fixed_time or nil
end

function M.choose_target_type(current_type, melee_score, ranged_score)
	local raw_choice = ranged_score < melee_score and "melee" or "ranged"
	if current_type ~= "melee" and current_type ~= "ranged" then
		return raw_choice
	end

	local melee_stabilized = melee_score
	local ranged_stabilized = ranged_score
	local momentum_bonus = _max3(_abs(melee_score), _abs(ranged_score), 1) * MOMENTUM_FACTOR

	if current_type == "melee" then
		melee_stabilized = melee_stabilized + momentum_bonus
	else
		ranged_stabilized = ranged_stabilized + momentum_bonus
	end

	local margin = _max3(_abs(melee_score), _abs(ranged_score), 1) * MARGIN_FACTOR
	local candidate = ranged_stabilized < melee_stabilized and "melee" or "ranged"

	if candidate == current_type then
		return current_type
	end

	local winner = candidate == "melee" and melee_stabilized or ranged_stabilized
	local loser = candidate == "melee" and ranged_stabilized or melee_stabilized
	if winner - loser > margin then
		return candidate
	end

	return current_type
end

return M
```

- [ ] **Step 2: Run focused chooser tests**

Run:

```bash
make test TESTS=tests/target_type_hysteresis_spec.lua
```

Expected: PASS

### Task 3: Hook Perception Target-Type Selection

**Files:**
- Modify: `scripts/mods/BetterBots/target_type_hysteresis.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

- [ ] **Step 1: Add hook installer to the module**

Extend `target_type_hysteresis.lua` with an installer:

```lua
function M.install_hooks(target_selection_template)
	local original = target_selection_template.bot_default

	target_selection_template.bot_default = function(unit, unit_position, side, perception_component, behavior_component, breed, target_units, t, threat_units, bot_group, target_selection_debug_info_or_nil)
		original(unit, unit_position, side, perception_component, behavior_component, breed, target_units, t, threat_units, bot_group, target_selection_debug_info_or_nil)

		local current_type = perception_component.target_enemy_type
		if current_type ~= "melee" and current_type ~= "ranged" then
			return
		end
	end
end
```

Then replace the stub with a real wrap that re-runs the final type comparison locally. Do **not** rewrite the whole vanilla function. Instead:

- copy the tiny decision logic needed for full reevaluation and current-target rescoring
- use `choose_target_type(...)` for the final type
- write back stabilized `perception_component.target_enemy_type`

If actual wrapping requires copying more than the final comparison block, stop and reassess before broadening scope.

- [ ] **Step 2: Register the hook from `BetterBots.lua`**

Add module load:

```lua
local TargetTypeHysteresis = mod:io_dofile("BetterBots/scripts/mods/BetterBots/target_type_hysteresis")
assert(TargetTypeHysteresis, "BetterBots: failed to load target_type_hysteresis module")
```

Init:

```lua
TargetTypeHysteresis.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
})
```

Hook registration:

```lua
mod:hook_require("scripts/extension_systems/perception/target_selection_templates/bot_target_selection_template", function(TargetSelectionTemplate)
	TargetTypeHysteresis.install_hooks(TargetSelectionTemplate)
end)
```

### Task 4: Add Flip-Only Debug Logging

**Files:**
- Modify: `scripts/mods/BetterBots/target_type_hysteresis.lua`

- [ ] **Step 1: Log only on actual stabilized flips**

Inside the hook logic, when `old_type ~= new_type`:

```lua
if M._debug_enabled and M._debug_enabled() then
	M._debug_log(
		"target_type_flip:" .. tostring(unit),
		M._fixed_time and M._fixed_time() or 0,
		"type flip "
			.. tostring(old_type)
			.. " -> "
			.. tostring(new_type)
			.. " (melee="
			.. tostring(melee_score)
			.. ", ranged="
			.. tostring(ranged_score)
			.. ", margin="
			.. tostring(margin)
			.. ")"
	)
end
```

No “held current type” logs.

### Task 5: Update Docs And Counts

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/bot/perception-targeting.md`

- [ ] **Step 1: Update README / AGENTS parity**

Adjust:
- module count `37 -> 38`
- test count `822 -> 828` if the new spec count lands exactly one file and current suite stays stable

If actual busted total differs, trust `make test` + `make doc-check`, not this estimate.

- [ ] **Step 2: Add new module to module lists**

Add `target_type_hysteresis.lua` and `target_type_hysteresis_spec.lua` to README + AGENTS inventories.

- [ ] **Step 3: Update architecture and roadmap**

Add `#90` as implemented on branch in:
- `docs/dev/architecture.md`
- `docs/dev/roadmap.md`
- `docs/dev/status.md`

- [ ] **Step 4: Update perception doc**

In `docs/bot/perception-targeting.md`, note:
- vanilla still reevaluates every `0.3s`
- BetterBots now adds hysteresis at the final type pick to suppress close-score oscillation

### Task 6: Full Verification

**Files:**
- Modify: none

- [ ] **Step 1: Run focused hysteresis tests**

Run:

```bash
make test TESTS=tests/target_type_hysteresis_spec.lua
```

Expected: PASS

- [ ] **Step 2: Run full suite**

Run:

```bash
make test
```

Expected: PASS

- [ ] **Step 3: Run doc check**

Run:

```bash
make doc-check
```

Expected: PASS

- [ ] **Step 4: Check branch state**

Run:

```bash
git status --short
```

Expected: only intended `#90` changes are present.

## Self-Review

- Spec coverage: root-cause hook, margin, momentum, no BT debounce, pure tests, and docs all mapped.
- Placeholder scan: all steps contain concrete file paths and commands.
- Type consistency: plan consistently uses `target_enemy_type`, `choose_target_type`, and the perception-template hook site rather than drifting into `BotTargetSelection` or BT nodes.
