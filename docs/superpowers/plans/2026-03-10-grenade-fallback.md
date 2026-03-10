# Standard Grenade Bot Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bots throw standard/handleless grenades (12 templates) via a new `grenade_fallback.lua` state machine module.

**Architecture:** New `grenade_fallback.lua` module with a 5-stage state machine (idle → wield → wait_aim → wait_throw → wait_unwield → idle). Queues action inputs on the `"weapon_action"` parser to wield grenade slot, aim, throw, and unwield. Integrated into the main update tick alongside existing `AbilityQueue.try_queue`.

**Tech Stack:** Lua (Darktide Mod Framework), busted (unit tests)

**Spec:** `docs/superpowers/specs/2026-03-10-grenade-fallback-design.md`

**Branching:** All work on `feat/4-grenade-fallback` off `main`. Merges into `dev/m5-batch1` (not `main`) when complete.

---

## Chunk 1: Branches, heuristics, and core module

### Task 1: Set up branches

**Files:** None

- [ ] **Step 1: Create batch branch and feature branch**

```bash
git checkout main
git checkout -b dev/m5-batch1
git checkout -b feat/4-grenade-fallback
```

- [ ] **Step 2: Verify branch**

Run: `git branch --show-current`
Expected: `feat/4-grenade-fallback`

---

### Task 2: Add grenade heuristic to heuristics.lua

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Test: `tests/heuristics_spec.lua`

The grenade heuristic is minimal: check `enemies_in_proximity > 0`. A `GRENADE_HEURISTICS` table is provided for future per-grenade rules but is initially empty — all grenades fall through to the generic check.

- [ ] **Step 1: Write the failing test**

Add to `tests/heuristics_spec.lua` at the end, inside the top-level `describe` block:

```lua
describe("evaluate_grenade_heuristic", function()
    it("returns true when enemies are nearby", function()
        local ctx = helper.make_context({ num_nearby = 3 })
        local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", ctx)
        assert.is_true(result)
        assert.equals("grenade_generic", rule)
    end)

    it("returns false when no enemies", function()
        local ctx = helper.make_context({ num_nearby = 0 })
        local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", ctx)
        assert.is_false(result)
        assert.equals("grenade_no_enemies", rule)
    end)

    it("returns false for nil context", function()
        local result, rule = Heuristics.evaluate_grenade_heuristic("frag_grenade", nil)
        assert.is_false(result)
        assert.equals("grenade_no_context", rule)
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `evaluate_grenade_heuristic` does not exist

- [ ] **Step 3: Implement evaluate_grenade_heuristic**

In `scripts/mods/BetterBots/heuristics.lua`:

1. Add empty `GRENADE_HEURISTICS` table after the `ITEM_HEURISTICS` table (around line 730):

```lua
local GRENADE_HEURISTICS = {}
```

2. Add the function after `evaluate_item_heuristic` (around line 857):

```lua
local function evaluate_grenade_heuristic(grenade_template_name, context)
	if not context then
		return false, "grenade_no_context"
	end

	local fn = GRENADE_HEURISTICS[grenade_template_name]
	if fn then
		return fn(context)
	end

	-- Generic fallback: throw when enemies are nearby
	if context.num_nearby > 0 then
		return true, "grenade_generic"
	end

	return false, "grenade_no_enemies"
end
```

3. Add to the module return table:

```lua
evaluate_grenade_heuristic = evaluate_grenade_heuristic,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: All tests PASS (existing 230 + 3 new = 233)

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add evaluate_grenade_heuristic with generic fallback (#4)"
```

---

### Task 3: Write grenade_fallback.lua — core state machine

**Files:**
- Create: `scripts/mods/BetterBots/grenade_fallback.lua`
- Create: `tests/grenade_fallback_spec.lua`

This is the main new module. The test file sets up mocks for `ScriptUnit`, ability extension, and action input extension, then tests each state transition.

- [ ] **Step 1: Write grenade_fallback_spec.lua with tests for all state transitions**

Create `tests/grenade_fallback_spec.lua`. The test file needs:

Mock setup:
- `ScriptUnit.has_extension` / `ScriptUnit.extension` returning mock extensions
- Mock `ability_extension` with `can_use_ability("grenade_ability")` returning configurable bool
- Mock `unit_data_extension` with `read_component("inventory")` returning configurable `wielded_slot`
- Mock `action_input_extension` with `bot_queue_action_input` that records calls
- Mock `equipped_grenade_ability` function returning `{ name = "frag_grenade" }`
- Mock `evaluate_grenade_heuristic` returning configurable result

Test cases:

```lua
describe("grenade_fallback", function()
    -- (mock setup at top of file, before dofile)

    describe("try_queue", function()
        it("does nothing when grenade charges depleted", function()
            -- can_use_ability returns false
            -- assert no action_input calls
        end)

        it("does nothing when heuristic blocks", function()
            -- can_use_ability returns true, heuristic returns false
            -- assert no action_input calls
        end)

        it("queues grenade_ability wield when idle and heuristic passes", function()
            -- can_use_ability returns true, heuristic returns true
            -- assert bot_queue_action_input called with ("weapon_action", "grenade_ability", nil)
            -- assert state transitions to "wield"
        end)

        it("waits in wield stage until slot changes", function()
            -- state is "wield", wielded_slot is "slot_secondary"
            -- call try_queue, assert still in "wield"
            -- change wielded_slot to "slot_grenade_ability"
            -- call try_queue, assert transitions to "wait_aim"
        end)

        it("times out wield stage and retries", function()
            -- state is "wield", advance time past deadline
            -- call try_queue, assert state resets to idle
        end)

        it("queues aim_hold in wait_aim stage", function()
            -- state is "wait_aim", time past aim delay
            -- assert bot_queue_action_input called with ("weapon_action", "aim_hold", nil)
            -- assert state transitions to "wait_throw"
        end)

        it("queues aim_released in wait_throw stage", function()
            -- state is "wait_throw", time past throw delay
            -- assert bot_queue_action_input called with ("weapon_action", "aim_released", nil)
            -- assert state transitions to "wait_unwield"
        end)

        it("completes when slot leaves grenade", function()
            -- state is "wait_unwield", wielded_slot changes to "slot_secondary"
            -- assert state resets to idle with retry cooldown
        end)

        it("forces unwield on timeout in wait_unwield", function()
            -- state is "wait_unwield", time past deadline, still on grenade slot
            -- assert bot_queue_action_input called with ("weapon_action", "unwield_to_previous", nil)
        end)

        it("respects retry cooldown between throws", function()
            -- state is idle, next_try_t is in the future
            -- assert no action_input calls
        end)
    end)
end)
```

Write each test case with full mock setup and assertions. Use the patterns from `tests/sprint_spec.lua` for mock structure.

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `grenade_fallback.lua` does not exist

- [ ] **Step 3: Implement grenade_fallback.lua**

Create `scripts/mods/BetterBots/grenade_fallback.lua`. Module structure:

```lua
-- grenade_fallback.lua — bot grenade throw state machine (#4)
-- Wields grenade slot, aims, throws, and returns to previous weapon.

-- Dependencies (set via init/wire)
local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _event_log
local _bot_slot_for_unit

-- Late-bound cross-module refs (set via wire)
local _build_context
local _evaluate_grenade_heuristic
local _equipped_grenade_ability

-- State tracking (weak-keyed by unit)
local _grenade_state_by_unit
local _last_grenade_charge_event_by_unit

-- Timing constants
local WIELD_TIMEOUT_S = 2.0
local AIM_DELAY_S = 0.15      -- delay after wield before queuing aim
local THROW_DELAY_S = 0.3     -- hold time before releasing throw
local UNWIELD_TIMEOUT_S = 3.0 -- max wait for auto-unwield
local RETRY_COOLDOWN_S = 2.0  -- cooldown between throw attempts

local function _reset_state(state, next_try_t)
    state.stage = nil
    state.deadline_t = nil
    state.wait_t = nil
    state.action_input_extension = nil
    if next_try_t then
        state.next_try_t = next_try_t
    end
end

local function _queue_weapon_input(state, input_name)
    local ext = state.action_input_extension
    if ext then
        ext:bot_queue_action_input("weapon_action", input_name, nil)
    end
end

local function try_queue(unit, blackboard)
    -- ... full state machine implementation
    -- See design spec for stage transitions
end

local function record_charge_event(unit, grenade_name, fixed_t)
    -- Called from the use_ability_charge hook for grenade_ability
    _last_grenade_charge_event_by_unit[unit] = {
        grenade_name = grenade_name,
        fixed_t = fixed_t,
    }
end

return {
    init = function(deps)
        _mod = deps.mod
        _debug_log = deps.debug_log
        _debug_enabled = deps.debug_enabled
        _fixed_time = deps.fixed_time
        _event_log = deps.event_log
        _bot_slot_for_unit = deps.bot_slot_for_unit
        _grenade_state_by_unit = deps.grenade_state_by_unit
        _last_grenade_charge_event_by_unit = deps.last_grenade_charge_event_by_unit
    end,
    wire = function(refs)
        _build_context = refs.build_context
        _evaluate_grenade_heuristic = refs.evaluate_grenade_heuristic
        _equipped_grenade_ability = refs.equipped_grenade_ability
    end,
    try_queue = try_queue,
    record_charge_event = record_charge_event,
}
```

The `try_queue` function follows this logic:

1. Get or create `_grenade_state_by_unit[unit]`
2. Check `state.next_try_t` — if in future, return early
3. Read `inventory_component.wielded_slot` via `unit_data_extension`
4. Switch on `state.stage`:
   - `nil` (idle): Check `ability_extension:can_use_ability("grenade_ability")`, then heuristic. If both pass, queue `"grenade_ability"` on `"weapon_action"`, set stage = `"wield"`, deadline.
   - `"wield"`: If `wielded_slot == "slot_grenade_ability"`, set stage = `"wait_aim"`, `wait_t`. If past deadline, `_reset_state` with retry.
   - `"wait_aim"`: If `wielded_slot ~= "slot_grenade_ability"`, lost wield — reset with retry. If past `wait_t`, queue `"aim_hold"`, set stage = `"wait_throw"`, `wait_t`.
   - `"wait_throw"`: If `wielded_slot ~= "slot_grenade_ability"`, lost wield — reset with retry. If past `wait_t`, queue `"aim_released"`, set stage = `"wait_unwield"`, deadline.
   - `"wait_unwield"`: If `wielded_slot ~= "slot_grenade_ability"`, throw complete — `_reset_state` with retry cooldown. If past deadline, queue `"unwield_to_previous"` and reset.
5. Add `_debug_log` calls at each transition (throttled, same pattern as `item_fallback.lua`)

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 5: Run full quality gate**

Run: `make check`
Expected: format + lint + lsp + test all PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat: add grenade_fallback.lua state machine module (#4)"
```

---

## Chunk 2: Integration and docs

### Task 4: Integrate into BetterBots.lua

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

Four changes needed:

- [ ] **Step 1: Add module load and init**

After the `AbilityQueue` load block (around line 162), add:

```lua
local GrenadeFallback = mod:io_dofile("BetterBots/scripts/mods/BetterBots/grenade_fallback")
assert(GrenadeFallback, "BetterBots: failed to load grenade_fallback module")
```

Add state dicts near the other weak-keyed tables (around line 18):

```lua
local _grenade_state_by_unit = setmetatable({}, { __mode = "k" })
local _last_grenade_charge_event_by_unit = setmetatable({}, { __mode = "k" })
```

Add a helper to get the equipped grenade ability (near `_equipped_combat_ability`):

```lua
local function _equipped_grenade_ability(unit)
    local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
    local equipped_abilities = ability_extension and ability_extension._equipped_abilities
    local grenade_ability = equipped_abilities and equipped_abilities.grenade_ability
    return ability_extension, grenade_ability
end

local function _equipped_grenade_ability_name(unit)
    local _, grenade_ability = _equipped_grenade_ability(unit)
    return grenade_ability and grenade_ability.name or "unknown"
end
```

Add init call after the `AbilityQueue.init` block:

```lua
GrenadeFallback.init({
    mod = mod,
    debug_log = _debug_log,
    debug_enabled = _debug_enabled,
    fixed_time = _fixed_time,
    event_log = EventLog,
    bot_slot_for_unit = Debug.bot_slot_for_unit,
    grenade_state_by_unit = _grenade_state_by_unit,
    last_grenade_charge_event_by_unit = _last_grenade_charge_event_by_unit,
})
```

Add wire call after the `AbilityQueue.wire` block:

```lua
GrenadeFallback.wire({
    build_context = Heuristics.build_context,
    evaluate_grenade_heuristic = Heuristics.evaluate_grenade_heuristic,
    equipped_grenade_ability = _equipped_grenade_ability,
})
```

- [ ] **Step 2: Add try_queue call to update tick**

In the `BotBehaviorExtension.update` hook_safe, after `AbilityQueue.try_queue(unit, blackboard)` (line 561), add:

```lua
GrenadeFallback.try_queue(unit, blackboard)
```

- [ ] **Step 3: Add grenade charge tracking to existing hook**

In the `use_ability_charge` hook_safe (line 401), change the early return guard from:

```lua
if ability_type ~= "combat_ability" then
    return
end
```

to:

```lua
if ability_type ~= "combat_ability" and ability_type ~= "grenade_ability" then
    return
end
```

Then, after the existing combat_ability tracking block, add grenade tracking:

```lua
if ability_type == "grenade_ability" then
    local grenade_name = "unknown"
    local equipped_abilities = self._equipped_abilities
    local grenade_ability = equipped_abilities and equipped_abilities.grenade_ability
    if grenade_ability and grenade_ability.name then
        grenade_name = grenade_ability.name
    end

    if unit then
        GrenadeFallback.record_charge_event(unit, grenade_name, fixed_t)
    end

    _debug_log(
        "grenade_charge:" .. grenade_name,
        fixed_t,
        "grenade charge consumed for " .. grenade_name .. " (charges=" .. tostring(optional_num_charges or 1) .. ")"
    )
    return
end
```

- [ ] **Step 4: Clear grenade state on session start**

In `mod.on_game_state_changed`, inside the `"enter" and "GameplayStateRun"` block, add state cleanup:

```lua
for unit in pairs(_grenade_state_by_unit) do
    _grenade_state_by_unit[unit] = nil
end
```

- [ ] **Step 5: Run full quality gate**

Run: `make check`
Expected: All checks PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat: integrate grenade_fallback into update tick and charge tracking (#4)"
```

---

### Task 5: Update docs and test counts

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/dev/roadmap.md`

- [ ] **Step 1: Update AGENTS.md**

Update the test count line:
```
- `make test` — NNN unit tests via busted (heuristics, meta_data, resolve_decision, event_log, sprint, melee_meta_data, ranged_meta_data, grenade_fallback)
```

Update the file structure to include new files:
```
  grenade_fallback.lua                      # Grenade throw state machine (wield/aim/throw/unwield)
```
and:
```
  grenade_fallback_spec.lua                 # NN tests for grenade throw state machine
```

(Replace NNN/NN with actual counts after tests pass.)

- [ ] **Step 2: Update docs/dev/roadmap.md**

In the M4 row for #4, update status to reflect Phase 1 implementation. In the P2 table entry for #4, add implementation note.

- [ ] **Step 3: Run doc-check**

Run: `make doc-check`
Expected: PASS (test counts match)

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/dev/roadmap.md
git commit -m "docs: update test counts and roadmap for grenade support (#4)"
```

---

### Task 6: Merge to batch branch

**Files:** None

- [ ] **Step 1: Run full quality gate one final time**

Run: `make check`
Expected: All PASS

- [ ] **Step 2: Merge feature branch into batch branch**

```bash
git checkout dev/m5-batch1
git merge feat/4-grenade-fallback
```

- [ ] **Step 3: Verify merge is clean**

Run: `make check`
Expected: All PASS

- [ ] **Step 4: Update HANDOFF.md**

Update current task, #4 status, and log entry. Do NOT merge to `main` — batch branch stays open for more M5 features and in-game testing.
