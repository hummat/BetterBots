# Tier 3 Reliability + Heuristics Implementation Plan

**Goal:** Fix Tier 3 item-ability timing (force field ~13% → reliable, drone ~21% → reliable) and add per-ability heuristics for all 4 Tier 3 abilities.

**Architecture:** Two sequential changes validated separately: (1) fix `ITEM_SEQUENCE_PROFILES` timing values in `item_fallback.lua`, validate consume-rate improvement, (2) add `ITEM_HEURISTICS` table in `heuristics.lua` keyed by ability name, wire into `can_use_item_fallback()`, extend `build_context()` with ally/corruption fields, update debug plumbing.

**Tech Stack:** Lua (Darktide Mod Framework), busted (test framework), make (build system)

**Design doc:** `docs/plans/2026-03-06-tier3-reliability-design.md`

---

### Task 1: Fix timing values in ITEM_SEQUENCE_PROFILES

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua:30-87`

**Step 1: Update timing values**

In `ITEM_SEQUENCE_PROFILES`, change these values:

```lua
-- press_release (line 44-46)
followup_delay = 0.6,    -- was 0.08; place_time = 0.54s + margin
unwield_delay = 0.7,     -- was 0.35; 0.6s + unwield margin

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

### Task 2: Validate timing fix in-game (manual)

**Purpose:** Measure consume-rate improvement from timing fix BEFORE changing gating logic. This isolates timing impact from heuristic impact.

**Bot lineup:**
- Zealot (Bolstering Prayer / relic)
- Psyker (Telekine Shield / dome variant preferred)
- Arbites (Nuncio-Aquila drone)
- Any 4th bot

**Steps:**
1. Launch Solo Play, start mission
2. Play through combat encounters (~10 min)
3. After mission: `bb-log summary` on latest log
4. Compare `charge consumed` vs `finished without charge consume` ratios to pre-fix baseline:
   - Force field: was ~13% → target: >50%
   - Drone: was ~21% → target: >50%
   - Relic: was 100% → should remain 100%
5. Record results in `docs/VALIDATION_TRACKER.md` as a new run entry

**Commit:**
```bash
git add docs/VALIDATION_TRACKER.md
git commit -m "docs: record Tier 3 timing fix validation run (#3)"
```

---

### Task 3: Extend build_context() with ally and corruption fields

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:62-161`
- Modify: `tests/test_helper.lua:29-60`

**Step 1: Add new field defaults to make_context()**

In `tests/test_helper.lua`, add inside `make_context()` after `target_is_super_armor = false`:

```lua
allies_in_coherency = 0,
avg_ally_toughness_pct = 1,
max_ally_corruption_pct = 0,
```

**Step 2: Add new field defaults to build_context()**

In `heuristics.lua`, add to the context initializer (after `target_is_super_armor = false`, line 83):

```lua
allies_in_coherency = 0,
avg_ally_toughness_pct = 1,
max_ally_corruption_pct = 0,
```

**Step 3: Add coherency + corruption data collection**

In `heuristics.lua`, add after the `unit_data_extension` / warp_charge block (after line 114), before the perception_extension block:

```lua
local coherency_extension = ScriptUnit.has_extension(unit, "coherency_system")
if coherency_extension and coherency_extension.in_coherence_units then
    local in_coherence_units = coherency_extension:in_coherence_units()
    local ally_count = 0
    local ally_toughness_sum = 0
    local max_corruption = 0
    for ally_unit, _ in pairs(in_coherence_units) do
        local ally_breed_data = ScriptUnit.has_extension(ally_unit, "unit_data_system")
        local ally_breed = ally_breed_data and ally_breed_data:breed()
        local is_dog = ally_breed and ally_breed.name
            and string.find(ally_breed.name, "companion", 1, true)
        if not is_dog then
            ally_count = ally_count + 1
            local ally_toughness_ext = ScriptUnit.has_extension(ally_unit, "toughness_system")
            if ally_toughness_ext and ally_toughness_ext.current_toughness_percent then
                ally_toughness_sum = ally_toughness_sum
                    + (ally_toughness_ext:current_toughness_percent() or 1)
            else
                ally_toughness_sum = ally_toughness_sum + 1
            end
            local ally_health_ext = ScriptUnit.has_extension(ally_unit, "health_system")
            if ally_health_ext and ally_health_ext.permanent_damage_taken_percent then
                local corruption = ally_health_ext:permanent_damage_taken_percent() or 0
                if corruption > max_corruption then
                    max_corruption = corruption
                end
            end
        end
    end
    context.allies_in_coherency = ally_count
    context.avg_ally_toughness_pct = ally_count > 0 and (ally_toughness_sum / ally_count) or 1
    context.max_ally_corruption_pct = max_corruption
end
```

**Step 4: Run tests**

Run: `make test`
Expected: PASS (build_context isn't called in unit tests — they use make_context. But schema parity is maintained by matching field defaults.)

**Step 5: Run full checks**

Run: `make check`
Expected: PASS

**Step 6: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/test_helper.lua
git commit -m "feat(heuristics): add allies_in_coherency, avg_ally_toughness_pct, max_ally_corruption_pct to build_context (#3)"
```

---

### Task 4: Add zealot_relic heuristic function + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua` (add function + ITEM_HEURISTICS table + evaluate_item_heuristic)
- Modify: `tests/heuristics_spec.lua` (add tests)

**Step 1: Write failing tests**

Add to `tests/heuristics_spec.lua`:

```lua
-- zealot_relic (item-based)
describe("zealot_relic", function()
    local eval_item = Heuristics.evaluate_item_heuristic

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

    it("activates on self critical toughness even without allies", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 2, toughness_pct = 0.20, allies_in_coherency = 0,
        }))
        assert.is_true(ok)
        assert.matches("self_critical", rule)
    end)

    it("blocks with no allies when toughness is fine", function()
        local ok, rule = eval_item("zealot_relic", ctx({
            num_nearby = 2, toughness_pct = 0.60, allies_in_coherency = 0,
        }))
        assert.is_false(ok)
        assert.matches("no_allies", rule)
    end)

    it("holds in safe state with allies", function()
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
-- Item-ability heuristics (keyed by ability name, not template name).
-- Unknown items default to false — item abilities are expensive, no accidental activation.

local function _can_activate_zealot_relic(context)
    if context.num_nearby >= 5 and context.toughness_pct < 0.30 then
        return false, "zealot_relic_block_overwhelmed"
    end
    if context.avg_ally_toughness_pct < 0.40 and context.allies_in_coherency >= 2 and context.num_nearby < 2 then
        return true, "zealot_relic_team_low_toughness"
    end
    if context.toughness_pct < 0.25 and context.num_nearby < 3 then
        return true, "zealot_relic_self_critical"
    end
    if context.allies_in_coherency == 0 then
        return false, "zealot_relic_block_no_allies"
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

Add `evaluate_item_heuristic` to the return table:

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

### Task 5: Add force_field heuristic function + tests

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

### Task 6: Add drone heuristic function + tests

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

### Task 7: Add stimm_field heuristic function + tests

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
            max_ally_corruption_pct = 0.40,
        }))
        assert.is_true(ok)
        assert.matches("corruption", rule)
    end)

    it("does not activate on low corruption", function()
        local ok, rule = eval_item("broker_ability_stimm_field", ctx({
            num_nearby = 2, allies_in_coherency = 1,
            max_ally_corruption_pct = 0.20,
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
    if (context.max_ally_corruption_pct or 0) > 0.30 and context.allies_in_coherency >= 1 then
        return true, "stimm_corruption_heal"
    end
    if context.target_ally_needs_aid and context.num_nearby >= 2 then
        return true, "stimm_ally_aid"
    end
    return false, "stimm_hold"
end
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
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add broker_ability_stimm_field item heuristic with corruption detection (#3)"
```

---

### Task 8: Wire item heuristics into item_fallback.lua + debug.lua

**Files:**
- Modify: `scripts/mods/BetterBots/item_fallback.lua:1-17,410-433,451,779-802`
- Modify: `scripts/mods/BetterBots/debug.lua:12,356-359,416`
- Modify: `scripts/mods/BetterBots/BetterBots.lua:118-129`

**Step 1: Add evaluate_item_heuristic as late-bound ref in item_fallback.lua**

At the top of `item_fallback.lua`, after `_fallback_state_snapshot` (line 17), add:

```lua
local _evaluate_item_heuristic
```

In the `wire()` function (line 793+), add:

```lua
_evaluate_item_heuristic = refs.evaluate_item_heuristic
```

**Step 2: Replace can_use_item_fallback with heuristic-based gate**

Replace the entire `can_use_item_fallback` function (lines 410-433) with:

```lua
local function can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
    if not ability_extension:can_use_ability("combat_ability") then
        return false, "item_cooldown_not_ready"
    end

    if not _evaluate_item_heuristic then
        return false, "item_heuristics_not_wired"
    end

    local context = _build_context(unit, blackboard)
    return _evaluate_item_heuristic(ability_name, context)
end
```

**Step 3: Pass blackboard to can_use_item_fallback call site**

In `try_queue_item` (line 451), change:

```lua
if not can_use_item_fallback(unit, ability_extension, ability_name) then
```

to:

```lua
local can_use, item_rule = can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
if not can_use then
```

**Step 4: Update debug.lua /bb_decide**

In `debug.lua`, update the item fallback branch (lines 356-359):

Change:
```lua
can_activate = _can_use_item_fallback(unit, ability_extension, ability_name)
rule = can_activate and "item_fallback_ready" or "item_fallback_blocked"
context = _build_context(unit, blackboard)
```

To:
```lua
can_activate, rule = _can_use_item_fallback(unit, ability_extension, ability_name, blackboard)
rule = rule or (can_activate and "item_fallback_ready" or "item_fallback_blocked")
context = _build_context(unit, blackboard)
```

**Step 5: Wire evaluate_item_heuristic in BetterBots.lua**

In `BetterBots.lua`, in the `ItemFallback.wire()` call (line 118-122), add:

```lua
evaluate_item_heuristic = Heuristics.evaluate_item_heuristic,
```

**Step 6: Run checks**

Run: `make check`
Expected: PASS

**Step 7: Commit**

```bash
git add scripts/mods/BetterBots/item_fallback.lua scripts/mods/BetterBots/debug.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(item_fallback): replace coarse gate with per-ability item heuristics (#3)"
```

---

### Task 9: Remove zealot_relic special case

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua:211-222`

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

Note: zealot_relic goes through the item_fallback path (template_name == "none" in BT), so this branch was only reachable if zealot_relic somehow had a template_name, which it doesn't. Removing it is safe.

**Step 2: Run checks**

Run: `make check`
Expected: PASS

**Step 3: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "refactor: remove zealot_relic special case from condition hook (#3)"
```

---

### Task 10: Full check + doc updates

**Step 1: Run full quality gate**

Run: `make check`
Expected: PASS (format + lint + lsp + test)

**Step 2: Count total tests**

Run: `make test 2>&1 | tail -5`
Expected: All tests pass. Count should be ~101 + ~30 new = ~131.

**Step 3: Review diff**

Run: `git diff main --stat`
Verify changes are scoped to expected files.

**Step 4: Update docs**

Update `docs/KNOWN_ISSUES.md`:
- Note timing values have been corrected in ITEM_SEQUENCE_PROFILES
- Note item heuristics now replace coarse `enemies_in_proximity > 0` gate
- Update heuristic count

Update `docs/VALIDATION_TRACKER.md`:
- Add placeholder for Tier 3 heuristic validation run (separate from timing run in Task 2)

**Step 5: Commit docs**

```bash
git add docs/KNOWN_ISSUES.md docs/VALIDATION_TRACKER.md
git commit -m "docs: update known issues and validation tracker for Tier 3 heuristics (#3)"
```

---

### Task 11: Validate heuristics in-game (manual)

**Purpose:** Measure heuristic decision quality AFTER timing fix is already validated. This is a separate run from Task 2.

**Bot lineup:**
- Zealot (Bolstering Prayer / relic)
- Psyker (Telekine Shield / dome variant preferred)
- Arbites (Nuncio-Aquila drone)
- Any 4th bot

**Steps:**
1. Enable debug logging in mod settings
2. Launch Solo Play, start mission
3. Play through combat encounters (~10 min)
4. Use `/bb_decide` during combat to verify heuristic rule names appear (not generic "ready/blocked")
5. After mission: `bb-log summary` on latest log
6. Check heuristic activate/hold rules fire correctly:
   - zealot_relic: `team_low_toughness`, `self_critical` vs `hold`, `no_allies`
   - force_field: `pressure`, `ranged_pressure` vs `safe`, `hold`
   - drone: `team_horde`, `monster_fight` vs `no_allies`, `low_value`
7. Verify consume rates remain at improved levels from Task 2
8. Record results in `docs/VALIDATION_TRACKER.md`

**Commit:**
```bash
git add docs/VALIDATION_TRACKER.md
git commit -m "docs: record Tier 3 heuristic validation run (#3)"
```
