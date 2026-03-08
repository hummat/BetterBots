# Charge-to-Rescue Aim Direction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make charge/dash abilities aim toward disabled allies when activated for rescue, and add missing rescue triggers for zealot dash and adamant charge.

**Architecture:** Heuristics return rescue rule names (pure functions, no side effects). The condition hook in BetterBots.lua detects rescue-charge rules and stores `{ally_unit}` in a module-local table keyed by bot unit. A new `mod:hook` on `BtBotActivateAbilityAction.enter()` reads that table and calls `set_aim_position()` before the lunge fires.

**Tech Stack:** Lua (Darktide Mod Framework), busted (unit tests)

---

### Task 1: Add `target_ally_unit` to `build_context()` and test helper

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:79-98`
- Modify: `tests/test_helper.lua:29-53`

**Step 1: Add `target_ally_unit` to context defaults**

In `heuristics.lua`, add to the context table (after line 80):

```lua
target_ally_unit = nil,
```

In the perception block (after line 98), add:

```lua
context.target_ally_unit = perception_component.target_ally
```

**Step 2: Add `target_ally_unit` to test helper defaults**

In `test_helper.lua`, add to `make_context` defaults (after line 47):

```lua
target_ally_unit = nil,
```

**Step 3: Run tests to verify no regressions**

Run: `make test`
Expected: All 160 tests pass (new field defaults to nil, no existing test affected)

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/test_helper.lua
git commit -m "feat(heuristics): add target_ally_unit to build_context (#10)"
```

---

### Task 2: Add zealot dash rescue trigger with tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:304-334` (`_can_activate_zealot_dash`)
- Modify: `tests/heuristics_spec.lua:63-160` (zealot_dash describe block)

**Step 1: Write failing tests**

Add to the `zealot_dash` describe block in `tests/heuristics_spec.lua` (before the closing `end` at line 160):

```lua
it("activates for ally rescue at range", function()
    local ok, rule = evaluate(T, ctx({
        target_enemy = "unit",
        target_enemy_distance = 8,
        target_ally_needs_aid = true,
        target_ally_distance = 10,
    }))
    assert.is_true(ok)
    assert.matches("ally_aid", rule)
end)

it("blocks ally rescue when ally too close", function()
    local ok, rule = evaluate(T, ctx({
        target_enemy = "unit",
        target_enemy_distance = 8,
        target_ally_needs_aid = true,
        target_ally_distance = 2,
    }))
    assert.is_false(ok)
    assert.matches("hold", rule)
end)

it("blocks ally rescue when target too close", function()
    local ok, rule = evaluate(T, ctx({
        target_enemy = "unit",
        target_enemy_distance = 2,
        target_ally_needs_aid = true,
        target_ally_distance = 10,
    }))
    assert.is_false(ok)
    assert.matches("too_close", rule)
end)
```

**Step 2: Run tests to verify they fail**

Run: `make test`
Expected: 3 new tests FAIL (no `ally_aid` rule in zealot dash yet)

**Step 3: Implement rescue trigger**

In `_can_activate_zealot_dash` (`heuristics.lua`), add after the super armor block (after line 314) and before the priority target check (line 315):

```lua
if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 3 then
    return true, "zealot_dash_ally_aid"
end
```

The `> 3` gate reuses the existing `target_too_close` distance (line 309) — don't dash if the ally is already within melee range. The `target_too_close` check on enemy distance (line 309-311) fires first and blocks when the bot's current target is < 3m, preventing wasted dashes. The super armor block (line 312-313) also fires first.

**Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All tests pass including 3 new ones

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add zealot dash rescue trigger (#10)"
```

---

### Task 3: Add adamant charge rescue trigger with tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:515-534` (`_can_activate_adamant_charge`)
- Modify: `tests/heuristics_spec.lua:533-569` (adamant_charge describe block)

**Step 1: Write failing tests**

Add to the `adamant_charge` describe block in `tests/heuristics_spec.lua` (before the closing `end`):

```lua
it("activates for ally rescue at range", function()
    local ok, rule = evaluate(T, ctx({
        target_enemy_distance = 6,
        target_ally_needs_aid = true,
        target_ally_distance = 10,
    }))
    assert.is_true(ok)
    assert.matches("ally_aid", rule)
end)

it("blocks ally rescue when ally too close", function()
    local ok, rule = evaluate(T, ctx({
        target_enemy_distance = 6,
        target_ally_needs_aid = true,
        target_ally_distance = 2,
    }))
    assert.is_false(ok)
    assert.matches("hold", rule)
end)
```

**Step 2: Run tests to verify they fail**

Run: `make test`
Expected: 2 new tests FAIL

**Step 3: Implement rescue trigger**

In `_can_activate_adamant_charge` (`heuristics.lua`), add after the `target_too_close` block (after line 519) and before the `no_pressure` block (line 520):

```lua
if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) > 3 then
    return true, "adamant_charge_ally_aid"
end
```

Same distance gate logic as zealot dash — `> 3` prevents charging when ally is already in melee range.

**Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All tests pass including 2 new ones

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): add adamant charge rescue trigger (#10)"
```

---

### Task 4: Add rescue aim direction in BetterBots.lua

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

This task adds the aim correction mechanism. Two changes:

1. Store rescue intent when a rescue-charge rule triggers
2. Apply aim direction in the existing `BtBotActivateAbilityAction.enter()` hook

**Step 1: Add rescue intent tracking table and rule set**

After the `_gestalt_injected_units` declaration (line 38), add:

```lua
-- Rescue aim (#10): when a charge/dash activates for ally rescue, store the
-- ally unit so the enter hook can aim the bot toward it before the lunge fires.
local RESCUE_CHARGE_RULES = {
    ogryn_charge_ally_aid = true,
    zealot_dash_ally_aid = true,
    adamant_charge_ally_aid = true,
}
local _rescue_intent = setmetatable({}, { __mode = "k" })
```

**Step 2: Store rescue intent in `_can_activate_ability`**

In `_can_activate_ability` (`BetterBots.lua`), after the `Heuristics.resolve_decision` call (line 310-320) and before `Debug.log_ability_decision` (line 322), add:

```lua
if can_activate and rule and RESCUE_CHARGE_RULES[rule] then
    local perception = blackboard and blackboard.perception
    local ally_unit = perception and perception.target_ally
    if ally_unit then
        _rescue_intent[unit] = ally_unit
    end
end
```

**Step 3: Also store rescue intent in `_fallback_try_queue_combat_ability`**

In `_fallback_try_queue_combat_ability`, after the `Heuristics.resolve_decision` call (line 498-508) and before the `EventLog.is_enabled()` check (line 510), add:

```lua
if can_activate and rule and RESCUE_CHARGE_RULES[rule] then
    local perception = blackboard and blackboard.perception
    local ally_unit = perception and perception.target_ally
    if ally_unit then
        _rescue_intent[unit] = ally_unit
    end
end
```

**Step 4: Apply aim direction in the enter hook**

The existing `BtBotActivateAbilityAction.enter()` hook is at line 715-761. It uses `mod:hook_safe` which runs AFTER the original. We need to run BEFORE the original to set aim position before the lunge direction is calculated.

Change the hook from `mod:hook_safe` to `mod:hook` (wrapping). Replace lines 718-758:

```lua
mod:hook(
    BtBotActivateAbilityAction,
    "enter",
    function(func, self, unit, breed, blackboard, scratchpad, action_data, t)
        -- Rescue aim (#10): if this activation was rescue-motivated,
        -- aim the bot toward the disabled ally before the lunge fires.
        local ally_unit = _rescue_intent[unit]
        if ally_unit then
            _rescue_intent[unit] = nil
            local ally_pos = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
            if ally_pos then
                local bot_unit_input = scratchpad.bot_unit_input
                    or ScriptUnit.has_extension(unit, "input_system")
                if bot_unit_input and bot_unit_input.set_aim_position then
                    bot_unit_input:set_aim_position(ally_pos)
                    _debug_log(
                        "rescue_aim:" .. tostring(unit),
                        _fixed_time(),
                        "rescue aim: directed charge toward disabled ally"
                    )
                end
            end
        end

        -- Call original enter
        func(self, unit, breed, blackboard, scratchpad, action_data, t)

        -- Existing trace/event logging (preserved from hook_safe)
        local ability_component_name = action_data and action_data.ability_component_name or "?"
        local activation_data = scratchpad and scratchpad.activation_data
        local action_input = activation_data and activation_data.action_input or "?"
        local fixed_t = _fixed_time()

        _debug_log(
            "enter:" .. tostring(ability_component_name) .. ":" .. tostring(action_input),
            fixed_t,
            "enter ability node component="
                .. tostring(ability_component_name)
                .. " action_input="
                .. tostring(action_input)
        )

        if EventLog.is_enabled() and unit then
            local state = _fallback_state_by_unit[unit]
            if not state then
                state = {}
                _fallback_state_by_unit[unit] = state
            end
            local attempt_id = EventLog.next_attempt_id()
            state.attempt_id = attempt_id
            local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
            local ability_comp = unit_data_ext and unit_data_ext:read_component(ability_component_name)
            local template_name = ability_comp and ability_comp.template_name or "?"
            EventLog.emit({
                t = fixed_t,
                event = "queued",
                bot = Debug.bot_slot_for_unit(unit),
                ability = _equipped_combat_ability_name(unit),
                template = template_name,
                input = action_input,
                source = "bt",
                attempt_id = attempt_id,
            })
        end
    end
)
```

**Step 5: Run quality gate**

Run: `make check`
Expected: All checks pass (format + lint + lsp + tests)

**Step 6: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat: add rescue aim direction for charge/dash abilities (#10)"
```

---

### Task 5: Update docs and close issue

**Files:**
- Modify: `docs/ROADMAP.md` (strike through #10 in M3)
- Modify: `docs/STATUS.md` (update next steps)
- Modify: `docs/KNOWN_ISSUES.md` (if relevant)

**Step 1: Update ROADMAP.md**

In the M3 milestone line, strike through `charge rescue (#10)`:
```
3. **M3 (in progress):** Ability quality + bot fixes — ~~suppression (#11)~~, ~~charge rescue (#10)~~. ...
```

Since #10 was the last item, also change "in progress" to "closed":
```
3. **M3 (closed):** Ability quality + bot fixes — ...
```

**Step 2: Update STATUS.md next steps**

Remove or strike through the #10 line in the next steps section.

**Step 3: Run doc-check**

Run: `make doc-check`
Expected: No stale claims

**Step 4: Commit**

```bash
git add docs/ROADMAP.md docs/STATUS.md
git commit -m "docs: close M3 with charge rescue aim (#10)"
```

**Step 5: Close the GitHub issue**

```bash
gh issue close 10 -c "Implemented in feat/10-charge-rescue-aim branch: rescue triggers for zealot dash and adamant charge, aim direction correction via BtBotActivateAbilityAction.enter hook."
```

Wait — don't close until merged to main. Just note the branch.
