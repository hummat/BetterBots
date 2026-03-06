# Tier 3 Reliability + Heuristics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Tier 3 item-ability timing (force field ~13% → reliable, drone ~21% → reliable) and add per-ability heuristics for all 4 Tier 3 abilities.

**Architecture:** Two orthogonal changes: (1) fix `ITEM_SEQUENCE_PROFILES` timing values in `item_fallback.lua` to match decompiled engine action durations, (2) add `ITEM_HEURISTICS` table in `heuristics.lua` keyed by ability name, wire into `can_use_item_fallback()`, extend `build_context()` with ally/corruption fields.

**Tech Stack:** Lua (Darktide Mod Framework), busted (test framework), make (build system)

**Design doc:** `docs/plans/2026-03-06-tier3-reliability-design.md`

---

### Task 1: Fix timing values in ITEM_SEQUENCE_PROFILES

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua:30-87`

**Step 1: Update timing values**

In `ITEM_SEQUENCE_PROFILES`, change these values:

```lua
-- force_field_regular (line 53-55)
followup_delay = 1.2,    -- was 0.12; 0.6s buffer_time + 0.6s total_time
unwield_delay = 1.6,     -- was 0.9; 1.2s action + 0.4s margin

-- force_field_instant (line 65)
unwield_delay = 0.5,     -- was 0.8; 0.1s action + 0.4s margin

-- drone_regular (line 73-75)
followup_delay = 1.9,    -- was 0.24; 0.6s buffer_time + 1.3s total_time
unwield_delay = 2.3,     -- was 1.0; 1.9s action + 0.4s margin

-- drone_instant (line 85)
unwield_delay = 1.1,     -- was 0.9; 1.0s action + 0.1s margin

-- press_release (line 44-46)
followup_delay = 0.6,    -- was 0.08; place_time = 0.54s + margin
unwield_delay = 0.7,     -- was 0.35; 0.6s + unwield margin
```

**Step 2: Run lint**

Run: `make lint`
Expected: PASS (no logic changes, just constants)

**Step 3: Commit**

```bash
git add scripts/mods/BetterBots/item_fallback.lua
git commit -m "fix(item_fallback): align ITEM_SEQUENCE_PROFILES timing with engine action durations (#3)"
```

---

### Task 2: Extend build_context() with ally and corruption fields

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:62-161`
- Modify: `tests/test_helper.lua:29-60`

**Step 1: Write failing tests for new context fields**

Add to `tests/heuristics_spec.lua` (or a new file if preferred) tests that verify the new fields exist in `make_context()` output:

Add to `tests/test_helper.lua` inside `make_context()`, after `target_is_super_armor = false`:

```lua
allies_in_coherency = 0,
avg_ally_toughness_pct = 1,
corruption_pct = 0,
```

**Step 2: Run tests to verify existing tests still pass**

Run: `make test`
Expected: PASS (new defaults don't break anything)

**Step 3: Add ally coherency + toughness + corruption to build_context()**

In `heuristics.lua`, add three new fields to the context initializer (after `target_is_super_armor`, line 83):

```lua
allies_in_coherency = 0,
avg_ally_toughness_pct = 1,
corruption_pct = 0,
```

Then add the following block after the `unit_data_extension` / warp_charge block (after line 114), before the perception_extension block:

```lua
local coherency_extension = ScriptUnit.has_extension(unit, "coherency_system")
if coherency_extension and coherency_extension.in_coherence_units then
    local in_coherence_units = coherency_extension:in_coherence_units()
    local ally_count = 0
    local ally_toughness_sum = 0
    for ally_unit, _ in pairs(in_coherence_units) do
        local ally_breed = _enemy_breed(ally_unit)
        local is_dog = ally_breed and ally_breed.name and string.find(ally_breed.name, "companion", 1, true)
        if not is_dog then
            ally_count = ally_count + 1
            local ally_toughness_ext = ScriptUnit.has_extension(ally_unit, "toughness_system")
            if ally_toughness_ext and ally_toughness_ext.current_toughness_percent then
                ally_toughness_sum = ally_toughness_sum
                    + (ally_toughness_ext:current_toughness_percent() or 1)
            else
                ally_toughness_sum = ally_toughness_sum + 1
            end
        end
    end
    context.allies_in_coherency = ally_count
    context.avg_ally_toughness_pct = ally_count > 0 and (ally_toughness_sum / ally_count) or 1
end

if health_extension and health_extension.permanent_damage_taken_percent then
    context.corruption_pct = health_extension:permanent_damage_taken_percent() or 0
end
```

Note: `_enemy_breed()` is used to check breed on ally units — it calls `unit_data_extension:breed()` which works for any unit, not just enemies. The companion dog has breed name containing "companion".

**Step 4: Run tests**

Run: `make test`
Expected: PASS (build_context isn't called in unit tests — they use make_context)

**Step 5: Run full checks**

Run: `make check`
Expected: PASS

**Step 6: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/test_helper.lua
git commit -m "feat(heuristics): add allies_in_coherency, avg_ally_toughness_pct, corruption_pct to build_context (#3)"
```

---

### Task 3: Add zealot_relic heuristic function + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua` (add function + ITEM_HEURISTICS table + evaluate_item_heuristic)
- Modify: `tests/heuristics_spec.lua` (add tests)

**Step 1: Write failing tests**

Add to `tests/heuristics_spec.lua`:

```lua
-- zealot_relic (item-based)
describe("zealot_relic", function()
    local eval_item = Heuristics.evaluate_item_heuristic

    it("blocks with no allies in coherency", function()
        local ok, rule = eval_item("zealot_relic", ctx({ num_nearby = 2, allies_in_coherency = 0 }))
        assert.is_false(ok)
        assert.matches("no_allies", rule)
    end)

    it("blocks when overwhelmed and fragile", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 5, toughness_pct = 0.20, allies_in_coherency = 2,
        }))
        assert.is_false(ok)
        assert.matches("overwhelmed", rule)
    end)

    it("does not block overwhelmed if toughness ok", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 6, toughness_pct = 0.50, allies_in_coherency = 2,
            avg_ally_toughness_pct = 0.30,
        }))
        assert.is_true(ok)
        assert.matches("team_low_toughness", rule)
    end)

    it("activates on team low toughness", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 1, allies_in_coherency = 2, avg_ally_toughness_pct = 0.30,
        }))
        assert.is_true(ok)
        assert.matches("team_low_toughness", rule)
    end)

    it("activates on self critical toughness", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 2, toughness_pct = 0.20, allies_in_coherency = 1,
        }))
        assert.is_true(ok)
        assert.matches("self_critical", rule)
    end)

    it("holds in safe state", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 1, allies_in_coherency = 2, avg_ally_toughness_pct = 0.80,
        }))
        assert.is_false(ok)
        assert.matches("hold", rule)
    end)

    it("returns false for unknown item ability", function()
        local ok, rule = eval_item("unknown_ability_xyz", ctx({ num_nearby = 5 }))
        assert.is_false(ok)
        assert.matches("unknown_item", rule)
    end)
end)
```

**Step 2: Run tests — verify they fail**

Run: `make test`
Expected: FAIL — `evaluate_item_heuristic` does not exist yet

**Step 3: Implement zealot_relic heuristic + ITEM_HEURISTICS + evaluate_item_heuristic**

Add after the `_can_activate_broker_rage` function (after line 555) in `heuristics.lua`:

```lua
-- Item-ability heuristics (keyed by ability name, not template name)
local function _can_activate_zealot_relic(context)
    if context.allies_in_coherency == 0 then
        return false, "zealot_relic_block_no_allies"
    end
    if context.num_nearby >= 5 and context.toughness_pct < 0.30 then
        return false, "zealot_relic_block_overwhelmed"
    end
    if context.avg_ally_toughness_pct < 0.40 and context.allies_in_coherency >= 2 and context.num_nearby < 2 then
        return true, "zealot_relic_team_low_toughness"
    end
    if context.toughness_pct < 0.25 and context.num_nearby < 3 then
        return true, "zealot_relic_self_critical"
    end
    return false, "zealot_relic_hold"
end
```

Add the `ITEM_HEURISTICS` table after `TEMPLATE_HEURISTICS` (after line 609):

```lua
local ITEM_HEURISTICS = {
    zealot_relic = _can_activate_zealot_relic,
}
```

Add `evaluate_item_heuristic` function after `evaluate_heuristic` (after line 728):

```lua
local function evaluate_item_heuristic(ability_name, context)
    local fn = ITEM_HEURISTICS[ability_name]
    if not fn then
        return false, "unknown_item_ability"
    end
    return fn(context)
end
```

Add `evaluate_item_heuristic` to the return table (line 730+):

```lua
evaluate_item_heuristic = evaluate_item_heuristic,
```

**Step 4: Run tests**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add zealot_relic item heuristic + ITEM_HEURISTICS framework (#3)"
```

---

### Task 4: Add force_field heuristic function + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

**Step 1: Write failing tests**

```lua
describe("force_field", function()
    local eval_item = Heuristics.evaluate_item_heuristic

    it("blocks with no threats", function()
        local ok, rule = eval_item("psyker_force_field", ctx({ num_nearby = 0 }))
        assert.is_false(ok)
        assert.matches("no_threats", rule)
    end)

    it("blocks when safe", function()
        local ok, rule = eval_item("psyker_force_field", ctx({
            num_nearby = 2, toughness_pct = 0.90,
        }))
        assert.is_false(ok)
        assert.matches("safe", rule)
    end)

    it("activates under pressure", function()
        local ok, rule = eval_item("psyker_force_field", ctx({
            num_nearby = 4, toughness_pct = 0.30,
        }))
        assert.is_true(ok)
        assert.matches("pressure", rule)
    end)

    it("activates on ally aid", function()
        local ok, rule = eval_item("psyker_force_field", ctx({
            num_nearby = 1, target_ally_needs_aid = true,
        }))
        assert.is_true(ok)
        assert.matches("ally_aid", rule)
    end)

    it("activates on ranged pressure without num_nearby gate", function()
        local ok, rule = eval_item("psyker_force_field", ctx({
            num_nearby = 0, target_enemy_type = "ranged", toughness_pct = 0.40,
            target_enemy = true,
        }))
        assert.is_true(ok)
        assert.matches("ranged", rule)
    end)

    it("all variants use same heuristic", function()
        local c = ctx({ num_nearby = 4, toughness_pct = 0.30 })
        local ok1, rule1 = eval_item("psyker_force_field", c)
        local ok2, rule2 = eval_item("psyker_force_field_improved", c)
        local ok3, rule3 = eval_item("psyker_force_field_dome", c)
        assert.is_true(ok1)
        assert.is_true(ok2)
        assert.is_true(ok3)
        assert.are.equal(rule1, rule2)
        assert.are.equal(rule2, rule3)
    end)

    it("holds in moderate state", function()
        local ok, rule = eval_item("psyker_force_field", ctx({
            num_nearby = 2, toughness_pct = 0.60, target_enemy = true,
        }))
        assert.is_false(ok)
        assert.matches("hold", rule)
    end)
end)
```

**Step 2: Run tests — verify they fail**

Run: `make test`
Expected: FAIL

**Step 3: Implement force_field heuristic**

Add after `_can_activate_zealot_relic` in `heuristics.lua`:

```lua
local function _can_activate_force_field(context)
    if context.num_nearby == 0 and not context.target_enemy then
        return false, "force_field_block_no_threats"
    end
    if context.toughness_pct > 0.80 then
        return false, "force_field_block_safe"
    end
    if context.num_nearby >= 3 and context.toughness_pct < 0.40 then
        return true, "force_field_pressure"
    end
    if context.target_ally_needs_aid then
        return true, "force_field_ally_aid"
    end
    if context.target_enemy_type == "ranged" and context.toughness_pct < 0.60 then
        return true, "force_field_ranged_pressure"
    end
    return false, "force_field_hold"
end
```

Add to `ITEM_HEURISTICS`:

```lua
psyker_force_field = _can_activate_force_field,
psyker_force_field_improved = _can_activate_force_field,
psyker_force_field_dome = _can_activate_force_field,
```

**Step 4: Run tests**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add force_field item heuristic for all 3 variants (#3)"
```

---

### Task 5: Add drone heuristic function + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

**Step 1: Write failing tests**

```lua
describe("adamant_area_buff_drone", function()
    local eval_item = Heuristics.evaluate_item_heuristic

    it("blocks with no allies", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 5, allies_in_coherency = 0,
        }))
        assert.is_false(ok)
        assert.matches("no_allies", rule)
    end)

    it("blocks with few enemies", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 2, allies_in_coherency = 2,
        }))
        assert.is_false(ok)
        assert.matches("low_value", rule)
    end)

    it("activates on team horde", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 5, allies_in_coherency = 2,
        }))
        assert.is_true(ok)
        assert.matches("team_horde", rule)
    end)

    it("activates on monster fight with ally", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 3, allies_in_coherency = 1, target_is_monster = true,
        }))
        assert.is_true(ok)
        assert.matches("monster", rule)
    end)

    it("activates when overwhelmed", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 6, allies_in_coherency = 1, toughness_pct = 0.40,
        }))
        assert.is_true(ok)
        assert.matches("overwhelmed", rule)
    end)

    it("holds in moderate state", function()
        local ok, rule = eval_item("adamant_area_buff_drone", ctx({
            num_nearby = 3, allies_in_coherency = 1,
        }))
        assert.is_false(ok)
        assert.matches("hold", rule)
    end)
end)
```

**Step 2: Run tests — verify they fail**

Run: `make test`
Expected: FAIL

**Step 3: Implement drone heuristic**

Add after `_can_activate_force_field`:

```lua
local function _can_activate_drone(context)
    if context.allies_in_coherency == 0 then
        return false, "drone_block_no_allies"
    end
    if context.num_nearby <= 2 then
        return false, "drone_block_low_value"
    end
    if context.allies_in_coherency >= 2 and context.num_nearby >= 4 then
        return true, "drone_team_horde"
    end
    if context.target_is_monster and context.allies_in_coherency >= 1 then
        return true, "drone_monster_fight"
    end
    if context.num_nearby >= 5 and context.toughness_pct < 0.50 then
        return true, "drone_overwhelmed"
    end
    return false, "drone_hold"
end
```

Add to `ITEM_HEURISTICS`:

```lua
adamant_area_buff_drone = _can_activate_drone,
```

**Step 4: Run tests**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add adamant_area_buff_drone item heuristic (#3)"
```

---

### Task 6: Add stimm_field heuristic function + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

**Step 1: Write failing tests**

```lua
describe("broker_ability_stimm_field", function()
    local eval_item = Heuristics.evaluate_item_heuristic

    it("blocks with no enemies", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({ num_nearby = 0 }))
        assert.is_false(ok)
        assert.matches("no_enemies", rule)
    end)

    it("blocks with no allies", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 3, allies_in_coherency = 0,
        }))
        assert.is_false(ok)
        assert.matches("no_allies", rule)
    end)

    it("activates on ally corruption", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 2, allies_in_coherency = 1,
            avg_ally_corruption_pct = 0.40,
        }))
        assert.is_true(ok)
        assert.matches("corruption", rule)
    end)

    it("does not activate on low corruption", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 2, allies_in_coherency = 1,
            avg_ally_corruption_pct = 0.20,
        }))
        assert.is_false(ok)
        assert.matches("hold", rule)
    end)

    it("activates on ally aid with pressure", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 3, allies_in_coherency = 1,
            target_ally_needs_aid = true,
        }))
        assert.is_true(ok)
        assert.matches("ally_aid", rule)
    end)

    it("holds in safe state", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 2, allies_in_coherency = 2,
        }))
        assert.is_false(ok)
        assert.matches("hold", rule)
    end)
end)
```

**Step 2: Run tests — verify they fail**

Run: `make test`
Expected: FAIL

**Step 3: Implement stimm_field heuristic**

Add after `_can_activate_drone`:

```lua
local function _can_activate_stimm_field(context)
    if context.num_nearby == 0 then
        return false, "stimm_block_no_enemies"
    end
    if context.allies_in_coherency == 0 then
        return false, "stimm_block_no_allies"
    end
    if (context.avg_ally_corruption_pct or 0) > 0.30 and context.allies_in_coherency >= 1 then
        return true, "stimm_corruption_heal"
    end
    if context.target_ally_needs_aid and context.num_nearby >= 2 then
        return true, "stimm_ally_aid"
    end
    return false, "stimm_hold"
end
```

Also add `avg_ally_corruption_pct` to `build_context()` — iterate coherency allies and average their corruption. Add to context initializer:

```lua
avg_ally_corruption_pct = 0,
```

Add to the coherency block (inside the ally iteration loop, after toughness):

```lua
local ally_health_ext = ScriptUnit.has_extension(ally_unit, "health_system")
if ally_health_ext and ally_health_ext.permanent_damage_taken_percent then
    ally_corruption_sum = ally_corruption_sum
        + (ally_health_ext:permanent_damage_taken_percent() or 0)
end
```

Initialize `ally_corruption_sum = 0` alongside `ally_toughness_sum`. Set context after loop:

```lua
context.avg_ally_corruption_pct = ally_count > 0 and (ally_corruption_sum / ally_count) or 0
```

Also add to `test_helper.lua` `make_context()`:

```lua
avg_ally_corruption_pct = 0,
```

Add to `ITEM_HEURISTICS`:

```lua
broker_ability_stimm_field = _can_activate_stimm_field,
```

**Step 4: Run tests**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua tests/test_helper.lua
git commit -m "feat(heuristics): add broker_ability_stimm_field item heuristic with corruption detection (#3)"
```

---

### Task 7: Wire item heuristics into item_fallback.lua

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua:410-433` (replace `can_use_item_fallback`)
- Modify: `scripts/mods/BetterBots/item_fallback.lua:1-17` (add wire dependency)
- Modify: `scripts/mods/BetterBots/BetterBots.lua:118-122` (wire evaluate_item_heuristic)

**Step 1: Add evaluate_item_heuristic as a late-bound ref in item_fallback.lua**

At the top of `item_fallback.lua`, after `_fallback_state_snapshot` (line 17), add:

```lua
local _evaluate_item_heuristic
```

In the `wire()` function (line 793), add:

```lua
_evaluate_item_heuristic = refs.evaluate_item_heuristic
```

**Step 2: Replace can_use_item_fallback with heuristic-based gate**

Replace the entire `can_use_item_fallback` function (lines 410-433) with:

```lua
local function can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
    if not ability_extension:can_use_ability("combat_ability") then
        return false
    end

    if not _evaluate_item_heuristic then
        return false
    end

    local context = _build_context(unit, blackboard)
    local can_activate, rule = _evaluate_item_heuristic(ability_name, context)
    return can_activate, rule
end
```

**Step 3: Pass blackboard to can_use_item_fallback call site**

In `try_queue_item` (line 451), change:

```lua
if not can_use_item_fallback(unit, ability_extension, ability_name) then
```

to:

```lua
if not can_use_item_fallback(unit, ability_extension, ability_name, blackboard) then
```

**Step 4: Wire evaluate_item_heuristic in BetterBots.lua**

In `BetterBots.lua`, in the `ItemFallback.wire()` call (line 118-122), add:

```lua
evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
```

**Step 5: Run checks**

Run: `make check`
Expected: PASS

**Step 6: Commit**

```bash
git add scripts/mods/BetterBots/item_fallback.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(item_fallback): replace coarse gate with per-ability item heuristics (#3)"
```

---

### Task 8: Remove zealot_relic special cases

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua:211-222` (remove zealot_relic branch in `_can_activate_ability`)
- Modify: `scripts/mods/BetterBots/item_fallback.lua` (confirm zealot_relic branch already removed in Task 7)

**Step 1: Remove zealot_relic special case from _can_activate_ability**

In `BetterBots.lua`, delete lines 211-222:

```lua
	if ability_template_name == "zealot_relic" then
		local can_activate =
			conditions._can_activate_zealot_relic(unit, blackboard, scratchpad, condition_args, action_data, is_running)
		Debug.log_ability_decision(
			ability_template_name,
			fixed_t,
			can_activate,
			"zealot_relic_vanilla",
			Heuristics.build_context(unit, blackboard)
		)
		return can_activate
	end
```

Note: zealot_relic goes through the item_fallback path (template_name == "none" in BT), so this branch in `_can_activate_ability` was dead code for the BT path. It only triggered if zealot_relic somehow had a template_name, which it doesn't. Removing it is safe.

**Step 2: Run checks**

Run: `make check`
Expected: PASS

**Step 3: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "refactor: remove zealot_relic special case from condition hook (#3)"
```

---

### Task 9: Run full check + review

**Step 1: Run full quality gate**

Run: `make check`
Expected: PASS (format + lint + lsp + test)

**Step 2: Count total tests**

Run: `make test 2>&1 | tail -5`
Expected: All tests pass. Count should be ~101 + ~30 new = ~131.

**Step 3: Review diff**

Run: `git diff main --stat`
Review the changes are scoped to the expected files.

**Step 4: Update docs**

Update `docs/KNOWN_ISSUES.md`:
- Change "Tier 3 item fallback timing mismatch" to note timing values have been corrected
- Update heuristic count (now covers Tier 3 abilities too)

Update `docs/VALIDATION_TRACKER.md`:
- Add placeholder for Tier 3 heuristic validation run
- Note timing fix applied

**Step 5: Commit docs**

```bash
git add docs/KNOWN_ISSUES.md docs/VALIDATION_TRACKER.md
git commit -m "docs: update known issues and validation tracker for Tier 3 timing fix (#3)"
```

---

### Task 10: In-game validation (manual)

This is the manual verification step — not automatable.

**Bot lineup:**
- Zealot (Bolstering Prayer / relic)
- Psyker (Telekine Shield / dome variant preferred)
- Arbites (Nuncio-Aquila drone)
- Any 4th bot

**Verify:**
1. Launch Solo Play, start mission
2. Confirm `BetterBots loaded` in chat
3. Play through combat encounters
4. After mission: `bb-log summary` on latest log
5. Check for `charge consumed` events for each Tier 3 ability
6. Check `fallback item finished without charge consume` — ratio should be much better than ~13%/~21%
7. Check heuristic hold/activate rules in debug log
8. Record results in VALIDATION_TRACKER.md
