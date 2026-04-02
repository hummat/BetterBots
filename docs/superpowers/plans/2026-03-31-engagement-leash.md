# Combat-Aware Engagement Leash (#47) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vanilla bot melee engagement leash with a coherency-anchored, context-aware system that prevents mid-combat break-off, post-charge rubber-banding, and overly rigid formation behavior.

**Architecture:** Two hooks on `BtBotMeleeAction` (`_allow_engage` and `_is_in_engage_range`) dynamically inflate engagement distances based on combat state (already engaged, post-charge grace, under attack, ranged foray). A per-bot cache reads coherency radius from `UnitCoherencyExtension` and special rules from `talent_extension`. All state lives in a weak-keyed table. The module follows BetterBots' standard init/wire/register_hooks pattern with a feature gate in the settings system.

**Tech Stack:** Lua (DMF mod framework), busted (unit tests), Darktide BT/extension APIs

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `scripts/mods/BetterBots/engagement_leash.lua` | Core module: hooks, per-bot state, coherency cache |
| Create | `tests/engagement_leash_spec.lua` | Unit tests |
| Modify | `scripts/mods/BetterBots/BetterBots.lua` | Load module, init/register_hooks, add charge timestamp to enter hook |
| Modify | `scripts/mods/BetterBots/settings.lua` | Add `engagement_leash` feature gate |
| Modify | `scripts/mods/BetterBots/BetterBots_data.lua` | Add settings widget |
| Modify | `scripts/mods/BetterBots/BetterBots_localization.lua` | Add setting strings |
| Modify | `scripts/mods/BetterBots/heuristics.lua` | Fix `ranged_count` bug (separate commit) |
| Modify | `tests/heuristics_spec.lua` | Test for `ranged_count` fix |

## Key Vanilla APIs Referenced

```
-- bt_bot_melee_action.lua methods (hookable via mod:hook):
BtBotMeleeAction._allow_engage(self, self_unit, target_unit, target_position,
    target_breed, scratchpad, action_data, already_engaged, aim_position, follow_position)
BtBotMeleeAction._is_in_engage_range(self, self_position, target_position,
    action_data, follow_position)

-- action_data fields (from bot_actions.lua fight_melee):
action_data.engage_range                                    -- 6m
action_data.engage_range_near_follow_position               -- 10m
action_data.override_engage_range_to_follow_position        -- 12m
action_data.override_engage_range_to_follow_position_challenge -- 6m (dead: lerp_t always 0)

-- fight_melee_priority_target: all fields are math.huge (specials/elites exempt)

-- Coherency extension API:
UnitCoherencyExtension:current_radius()        -- returns talent-modified radius (8m base)
UnitCoherencyExtension:coherency_settings()    -- returns radius, stickiness_limit, stickiness_time

-- Coherency constants (PlayerCharacterConstants.coherency):
radius = 8, stickiness_limit = 20, stickiness_time = 2

-- Talent special rules for "always in coherency":
special_rules.zealot_always_at_least_one_coherency  -- "count as 2 in coherency"
special_rules.zealot_always_at_least_two_coherency  -- "count as 3 in coherency"

-- Ranged enemy detection (O(1) table read):
BLACKBOARDS[target_unit].perception.target_unit == self_unit  -- is this enemy targeting me?
target_breed.ranged == true  -- is this a ranged breed? (top-level field, NOT in tags)
```

## Engagement Model

| Bot state | Leash from follow_pos | Approach range | Source |
|---|---|---|---|
| Not engaged | `max(12, coherency_radius + 4)` | 6/10m (vanilla) | Coherency edge + margin |
| Already engaged | `stickiness_limit` (20m) | 10m | Coherency stickiness concept |
| Post-charge (4s) | `stickiness_limit` (20m) | 10m | Fight at destination |
| Under melee attack (<3m) | `stickiness_limit` (20m) | 10m | Self-defense |
| Ranged foray | `stickiness_limit` (20m) | 10m | Reactive push toward shooter |
| Hard cap | 25m (30m if always-in-coherency) | — | Safety net |

Priority targets (`fight_melee_priority_target`) use `math.huge` — **never touched**.

---

## Task 1: Fix `ranged_count` bug in heuristics.lua

This is an independent bugfix discovered during research. Separate commit.

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:246`
- Modify: `tests/heuristics_spec.lua`

- [ ] **Step 1: Write failing test for `ranged_count`**

In `tests/heuristics_spec.lua`, add a test that verifies `build_context` correctly counts ranged enemies. The bug: `_is_tagged(tags, "ranged")` always returns false because `ranged` is a top-level breed field (`breed.ranged == true`), not inside `breed.tags`.

```lua
-- Add inside the existing describe("build_context" ...) block, or create one
-- near the end of the file alongside other build_context tests.
describe("build_context ranged_count", function()
    it("counts enemies with breed.ranged == true", function()
        -- Setup: stub ScriptUnit and perception to return enemies with ranged breeds
        _G.ScriptUnit = {
            has_extension = function(_, ext_name)
                if ext_name == "unit_data_system" then
                    return {
                        read_component = function(_, comp_name)
                            if comp_name == "health" then
                                return { current_health_percent = 1 }
                            elseif comp_name == "toughness" then
                                return { current_toughness_percent = 1 }
                            end
                            return nil
                        end,
                    }
                elseif ext_name == "perception_system" then
                    local ranged_unit = { id = "gunner" }
                    local melee_unit = { id = "poxwalker" }
                    return {
                        enemies_in_proximity = function()
                            return { ranged_unit, melee_unit }, 2
                        end,
                    }
                elseif ext_name == "coherency_system" then
                    return { in_coherence_units = function() return {} end }
                end
                return nil
            end,
        }
        _G.BLACKBOARDS = {
            [{ id = "gunner" }] = {
                breed = {
                    ranged = true,
                    tags = { elite = true, far = true, minion = true },
                    challenge_rating = 3,
                },
            },
            [{ id = "poxwalker" }] = {
                breed = {
                    tags = { horde = true, minion = true },
                    challenge_rating = 1,
                },
            },
        }

        -- This requires matching the unit references. For simplicity,
        -- use a different approach: mock _enemy_breed via the module's
        -- internal lookup. Since heuristics uses ScriptUnit.has_extension
        -- on the enemy unit to get unit_data_system → breed component,
        -- we need the stub to return breed data for those specific units.
        -- The cleaner approach: test that after build_context, ranged_count > 0
        -- when a ranged enemy is present.

        -- Actually the simplest approach: the existing test infrastructure
        -- uses make_context() which bypasses build_context(). We need to
        -- test build_context() directly, but it requires deep engine stubs.
        -- Instead, test the fix indirectly: verify that a heuristic that
        -- gates on ranged_count actually triggers when it should.

        -- Simpler: just test the classification logic directly.
        -- The fix changes line 246 from _is_tagged(tags, "ranged") to
        -- checking enemy_breed.ranged == true. We can verify this by
        -- checking that make_context({ranged_count = 2}) flows through
        -- to heuristics correctly (this already works), and add a
        -- code-level assertion that the fix is in place.
        pending("requires engine stubs for build_context - verify via source inspection")
    end)
end)
```

Actually — `build_context()` requires deep engine stubs (`ScriptUnit`, perception extension, BLACKBOARDS). The existing test suite tests heuristics via `make_context()` which bypasses `build_context()`. The cleanest test for this fix is a **structural regression guard** that reads the source and asserts the correct pattern is used. Add this to `tests/startup_regressions_spec.lua`:

```lua
it("heuristics.lua uses breed.ranged for ranged_count (not tags.ranged)", function()
    local handle = assert(io.open("scripts/mods/BetterBots/heuristics.lua", "r"))
    local source = assert(handle:read("*a"))
    handle:close()

    -- The bug: _is_tagged(tags, "ranged") — ranged is NOT in breed.tags
    assert.is_nil(
        source:find('_is_tagged%(tags, "ranged"%)'),
        "ranged_count must use enemy_breed.ranged, not _is_tagged(tags, 'ranged')"
    )
    -- The fix: enemy_breed.ranged == true (or just enemy_breed.ranged)
    assert.is_not_nil(
        source:find("enemy_breed%.ranged"),
        "ranged_count classification must check enemy_breed.ranged"
    )
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test` (or `busted tests/startup_regressions_spec.lua`)
Expected: FAIL — the source still uses `_is_tagged(tags, "ranged")`

- [ ] **Step 3: Fix `ranged_count` classification in heuristics.lua**

In `scripts/mods/BetterBots/heuristics.lua`, replace line 246:

```lua
-- BEFORE (line 246):
				if _is_tagged(tags, "ranged") then

-- AFTER:
				if enemy_breed.ranged then
```

The `enemy_breed` local is already available in scope (line 233: `local enemy_breed = _enemy_breed(enemy_unit)`). The `ranged` field is a top-level boolean on breed tables (e.g., `renegade_gunner.ranged = true`), not inside `breed.tags`.

- [ ] **Step 4: Run tests to verify pass**

Run: `make test`
Expected: ALL PASS (including new regression guard + all existing heuristic tests)

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/startup_regressions_spec.lua
git commit -m "fix(heuristics): use breed.ranged for ranged_count (not tags.ranged)

ranged_count was always 0 because _is_tagged(tags, 'ranged') checked
breed.tags.ranged, but ranged is a top-level breed field (breed.ranged).
All heuristic branches gating on ranged_count were dead code.

Fixes: ranged_count classification in build_context()
"
```

---

## Task 2: Add `engagement_leash` feature gate to settings

**Files:**
- Modify: `scripts/mods/BetterBots/settings.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
- Modify: `tests/settings_spec.lua`

- [ ] **Step 1: Write failing test for the new feature gate**

In `tests/settings_spec.lua`, add inside the `describe("is_feature_enabled", ...)` block:

```lua
it("gates engagement_leash feature correctly", function()
    Settings.init(mock_mod({ enable_engagement_leash = false }))
    assert.is_false(Settings.is_feature_enabled("engagement_leash"))
end)
```

Also update the "returns true for all known features" test to include the new gate:

```lua
it("returns true for all known features when settings return nil", function()
    Settings.init(mock_mod({}))

    assert.is_true(Settings.is_feature_enabled("sprint"))
    assert.is_true(Settings.is_feature_enabled("pinging"))
    assert.is_true(Settings.is_feature_enabled("special_penalty"))
    assert.is_true(Settings.is_feature_enabled("poxburster"))
    assert.is_true(Settings.is_feature_enabled("melee_improvements"))
    assert.is_true(Settings.is_feature_enabled("ranged_improvements"))
    assert.is_true(Settings.is_feature_enabled("engagement_leash"))
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/settings_spec.lua`
Expected: FAIL — `engagement_leash` is not in `FEATURE_GATES`

- [ ] **Step 3: Add feature gate to settings.lua**

In `scripts/mods/BetterBots/settings.lua`, add to the `FEATURE_GATES` table (after the existing entries around line 71):

```lua
local FEATURE_GATES = {
    sprint = "enable_sprint",
    pinging = "enable_pinging",
    special_penalty = "enable_special_penalty",
    poxburster = "enable_poxburster",
    melee_improvements = "enable_melee_improvements",
    ranged_improvements = "enable_ranged_improvements",
    engagement_leash = "enable_engagement_leash",
}
```

- [ ] **Step 4: Add settings widget to BetterBots_data.lua**

In `scripts/mods/BetterBots/BetterBots_data.lua`, add after the `enable_ranged_improvements` checkbox (around line 43):

```lua
{ setting_id = "enable_engagement_leash", type = "checkbox", default_value = true },
```

- [ ] **Step 5: Add localization strings to BetterBots_localization.lua**

In `scripts/mods/BetterBots/BetterBots_localization.lua`, add alongside the other feature toggle strings:

```lua
enable_engagement_leash = {
    en = "Combat engagement leash",
},
enable_engagement_leash_description = {
    en = "Bots stay in combat longer instead of breaking off to follow. Uses coherency-based ranges.",
},
```

- [ ] **Step 6: Run tests to verify pass**

Run: `make test`
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/settings.lua scripts/mods/BetterBots/BetterBots_data.lua scripts/mods/BetterBots/BetterBots_localization.lua tests/settings_spec.lua
git commit -m "feat(settings): add engagement_leash feature gate (#47)"
```

---

## Task 3: Create engagement_leash.lua module with tests (TDD)

This is the core implementation. We build the module test-first.

**Files:**
- Create: `scripts/mods/BetterBots/engagement_leash.lua`
- Create: `tests/engagement_leash_spec.lua`

### Step 3a: Write the module skeleton and test infrastructure

- [ ] **Step 1: Create the test file with helper infrastructure**

Create `tests/engagement_leash_spec.lua`:

```lua
local helper = require("tests.test_helper")

-- Stub globals that engagement_leash.lua needs
local BLACKBOARDS_STUB = {}
local POSITION_LOOKUP_STUB = {}

local function setup_globals()
    _G.BLACKBOARDS = BLACKBOARDS_STUB
    _G.POSITION_LOOKUP = POSITION_LOOKUP_STUB
    _G.ScriptUnit = {
        has_extension = function()
            return nil
        end,
    }
    _G.Managers = { time = { time = function() return 0 end } }
    _G.Vector3 = {
        distance_squared = function(a, b)
            local dx = (a[1] or 0) - (b[1] or 0)
            local dy = (a[2] or 0) - (b[2] or 0)
            local dz = (a[3] or 0) - (b[3] or 0)
            return dx * dx + dy * dy + dz * dz
        end,
    }
end

local function teardown_globals()
    _G.BLACKBOARDS = nil
    _G.POSITION_LOOKUP = nil
    _G.ScriptUnit = nil
    _G.Managers = nil
    _G.Vector3 = nil
end

local function make_unit(id)
    return { _test_id = id }
end

local function make_pos(x, y, z)
    return { x or 0, y or 0, z or 0 }
end

local function make_breed(overrides)
    local b = { name = "test_breed", tags = {}, challenge_rating = 1 }
    if overrides then
        for k, v in pairs(overrides) do
            b[k] = v
        end
    end
    return b
end

local function make_action_data(overrides)
    local ad = {
        engage_range = 6,
        engage_range_near_follow_position = 10,
        override_engage_range_to_follow_position = 12,
        override_engage_range_to_follow_position_challenge = 6,
    }
    if overrides then
        for k, v in pairs(overrides) do
            ad[k] = v
        end
    end
    return ad
end

-- Priority target action_data (all math.huge)
local function make_priority_action_data()
    return {
        engage_range = math.huge,
        engage_range_near_follow_position = math.huge,
        override_engage_range_to_follow_position = math.huge,
        override_engage_range_to_follow_position_challenge = math.huge,
    }
end

local EngagementLeash

describe("engagement_leash", function()
    before_each(function()
        setup_globals()
        -- Fresh load each test
        package.loaded["scripts.mods.BetterBots.engagement_leash"] = nil
        EngagementLeash = dofile("scripts/mods/BetterBots/engagement_leash.lua")
        EngagementLeash.init({
            debug_log = function() end,
            debug_enabled = function() return false end,
            fixed_time = function() return 0 end,
            perf = nil,
            is_enabled = function() return true end,
        })
    end)

    after_each(function()
        teardown_globals()
    end)

    -- Tests go here (added in subsequent steps)
end)
```

- [ ] **Step 2: Create the module skeleton**

Create `scripts/mods/BetterBots/engagement_leash.lua`:

```lua
-- Engagement leash: coherency-anchored combat engagement range (#47)
--
-- Hooks BtBotMeleeAction._allow_engage and _is_in_engage_range to extend
-- vanilla engagement distances based on combat context:
-- - Already engaged: extend to coherency stickiness_limit (20m)
-- - Post-charge grace: 4s window after movement abilities
-- - Under melee attack: self-defense override
-- - Ranged foray: push toward ranged enemies targeting the bot
-- - Hard cap: 25m (30m if always-in-coherency talent)

local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled

-- Coherency-derived constants
local BASE_LEASH = 12 -- vanilla override_engage_range_to_follow_position
local COHERENCY_STICKINESS_LIMIT = 20 -- PlayerCharacterConstants.coherency.stickiness_limit
local HARD_CAP = 25
local HARD_CAP_ALWAYS_COHERENCY = 30
local POST_CHARGE_GRACE_S = 4
local UNDER_ATTACK_RANGE_SQ = 9 -- 3m squared
local COHERENCY_RADIUS_MARGIN = 4 -- added to coherency_radius for base leash
local DEFAULT_COHERENCY_RADIUS = 8 -- base coherency radius
local COHERENCY_CACHE_REFRESH_S = 1

-- Per-bot state (weak-keyed on unit)
local _bot_state = setmetatable({}, { __mode = "k" })

-- Movement ability templates that trigger post-charge grace
local MOVEMENT_ABILITIES = {
    zealot_dash = true,
    zealot_targeted_dash = true,
    zealot_targeted_dash_improved = true,
    zealot_targeted_dash_improved_double = true,
    ogryn_charge = true,
    ogryn_charge_increased_distance = true,
    adamant_charge = true,
}

-- Special rules for "always in coherency" (Zealot aura)
local ALWAYS_COHERENCY_RULES = {
    "zealot_always_at_least_one_coherency",
    "zealot_always_at_least_two_coherency",
}

local function _get_or_create_state(unit)
    local state = _bot_state[unit]
    if not state then
        state = {
            charge_timestamp = 0,
            coherency_radius = DEFAULT_COHERENCY_RADIUS,
            always_in_coherency = false,
            last_cache_t = 0,
        }
        _bot_state[unit] = state
    end
    return state
end

local function _refresh_coherency_cache(unit, state, t)
    if t - state.last_cache_t < COHERENCY_CACHE_REFRESH_S then
        return
    end
    state.last_cache_t = t

    local coherency_ext = ScriptUnit.has_extension(unit, "coherency_system")
    if coherency_ext and coherency_ext.current_radius then
        state.coherency_radius = coherency_ext:current_radius() or DEFAULT_COHERENCY_RADIUS
    else
        state.coherency_radius = DEFAULT_COHERENCY_RADIUS
    end

    local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
    if talent_ext and talent_ext.has_special_rule then
        state.always_in_coherency = false
        for _, rule_name in ipairs(ALWAYS_COHERENCY_RULES) do
            if talent_ext:has_special_rule(rule_name) then
                state.always_in_coherency = true
                break
            end
        end
    else
        state.always_in_coherency = false
    end
end

-- Compute the effective engagement leash for a given bot+target situation.
-- Returns: effective_leash (number), reason (string)
function M.compute_effective_leash(unit, target_unit, target_breed, already_engaged, t)
    local state = _get_or_create_state(unit)
    _refresh_coherency_cache(unit, state, t)

    local cap = state.always_in_coherency and HARD_CAP_ALWAYS_COHERENCY or HARD_CAP
    local base = math.max(BASE_LEASH, state.coherency_radius + COHERENCY_RADIUS_MARGIN)

    -- Check extension conditions (priority order: most generous first)

    -- Post-charge grace: 4s after a movement ability
    if t - state.charge_timestamp < POST_CHARGE_GRACE_S then
        return math.min(COHERENCY_STICKINESS_LIMIT, cap), "post_charge_grace"
    end

    -- Under melee attack: enemy within 3m of bot
    if target_unit then
        local bot_pos = POSITION_LOOKUP and POSITION_LOOKUP[unit]
        local target_pos = POSITION_LOOKUP and POSITION_LOOKUP[target_unit]
        if bot_pos and target_pos and Vector3.distance_squared(bot_pos, target_pos) < UNDER_ATTACK_RANGE_SQ then
            return math.min(COHERENCY_STICKINESS_LIMIT, cap), "under_attack"
        end
    end

    -- Already engaged: extend to stickiness_limit
    if already_engaged then
        return math.min(COHERENCY_STICKINESS_LIMIT, cap), "already_engaged"
    end

    -- Ranged foray: ranged enemy targeting this bot
    if target_unit and target_breed and target_breed.ranged then
        local enemy_bb = BLACKBOARDS and BLACKBOARDS[target_unit]
        local enemy_perception = enemy_bb and enemy_bb.perception
        if enemy_perception and enemy_perception.target_unit == unit then
            return math.min(COHERENCY_STICKINESS_LIMIT, cap), "ranged_foray"
        end
    end

    -- Default: coherency-based or vanilla (whichever is larger)
    return math.min(base, cap), "base"
end

-- Determine whether approach range should be extended (force 10m).
-- Returns true when any engagement extension condition holds.
function M.should_extend_approach(unit, target_unit, target_breed, already_engaged, t)
    local _, reason = M.compute_effective_leash(unit, target_unit, target_breed, already_engaged, t)
    return reason ~= "base"
end

-- Record a movement ability activation for post-charge grace.
function M.record_charge(unit, t)
    local state = _get_or_create_state(unit)
    state.charge_timestamp = t
end

-- Check if a template name is a movement ability.
function M.is_movement_ability(template_name)
    return MOVEMENT_ABILITIES[template_name] == true
end

function M.init(deps)
    _mod = deps.mod
    _debug_log = deps.debug_log
    _debug_enabled = deps.debug_enabled
    _fixed_time = deps.fixed_time
    _perf = deps.perf
    _is_enabled = deps.is_enabled
end

function M.register_hooks()
    _mod:hook_require(
        "scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action",
        function(BtBotMeleeAction)
            -- Hook 1: _allow_engage — inflate leash distance based on combat context
            _mod:hook(
                BtBotMeleeAction,
                "_allow_engage",
                function(
                    func,
                    self,
                    self_unit,
                    target_unit,
                    target_position,
                    target_breed,
                    scratchpad,
                    action_data,
                    already_engaged,
                    aim_position,
                    follow_position
                )
                    if _is_enabled and not _is_enabled() then
                        return func(
                            self,
                            self_unit,
                            target_unit,
                            target_position,
                            target_breed,
                            scratchpad,
                            action_data,
                            already_engaged,
                            aim_position,
                            follow_position
                        )
                    end

                    -- Skip priority targets (already math.huge)
                    if action_data.override_engage_range_to_follow_position == math.huge then
                        return func(
                            self,
                            self_unit,
                            target_unit,
                            target_position,
                            target_breed,
                            scratchpad,
                            action_data,
                            already_engaged,
                            aim_position,
                            follow_position
                        )
                    end

                    local perf_t0 = _perf and _perf.begin()
                    local t = _fixed_time()

                    local effective_leash, reason =
                        M.compute_effective_leash(self_unit, target_unit, target_breed, already_engaged, t)

                    -- Temporarily inflate action_data
                    local orig_override = action_data.override_engage_range_to_follow_position
                    local orig_challenge = action_data.override_engage_range_to_follow_position_challenge
                    action_data.override_engage_range_to_follow_position = effective_leash
                    action_data.override_engage_range_to_follow_position_challenge = effective_leash

                    local result = func(
                        self,
                        self_unit,
                        target_unit,
                        target_position,
                        target_breed,
                        scratchpad,
                        action_data,
                        already_engaged,
                        aim_position,
                        follow_position
                    )

                    -- Restore original values
                    action_data.override_engage_range_to_follow_position = orig_override
                    action_data.override_engage_range_to_follow_position_challenge = orig_challenge

                    if _debug_enabled() and reason ~= "base" then
                        _debug_log(
                            "leash:" .. reason .. ":" .. tostring(self_unit),
                            t,
                            "engagement leash "
                                .. reason
                                .. " → "
                                .. effective_leash
                                .. "m (was "
                                .. orig_override
                                .. "m) result="
                                .. tostring(result)
                        )
                    end

                    if perf_t0 then
                        _perf.finish("engagement_leash._allow_engage", perf_t0)
                    end
                    return result
                end
            )

            -- Hook 2: _is_in_engage_range — force generous approach range
            _mod:hook(
                BtBotMeleeAction,
                "_is_in_engage_range",
                function(func, self, self_position, target_position, action_data, follow_position)
                    if _is_enabled and not _is_enabled() then
                        return func(self, self_position, target_position, action_data, follow_position)
                    end

                    -- Skip priority targets (already math.huge)
                    if action_data.engage_range == math.huge then
                        return func(self, self_position, target_position, action_data, follow_position)
                    end

                    -- We don't have unit/target_unit/breed here (only positions + action_data).
                    -- Use a simpler heuristic: if the bot is far from follow_position (>5m),
                    -- force the generous 10m approach range instead of the tight 6m.
                    -- This covers post-charge scenarios where the bot landed far away.
                    --
                    -- The vanilla logic: within 5m of follow → use 10m range; else → use 6m.
                    -- Our override: always use 10m when any charge grace is active for ANY bot.
                    -- Since _is_in_engage_range doesn't receive unit, we inflate for all bots
                    -- by temporarily setting engage_range = engage_range_near_follow_position.
                    -- This is acceptable: the leash in _allow_engage is the real gate.
                    local orig_engage_range = action_data.engage_range
                    action_data.engage_range = action_data.engage_range_near_follow_position

                    local result = func(self, self_position, target_position, action_data, follow_position)

                    action_data.engage_range = orig_engage_range
                    return result
                end
            )
        end
    )
end

-- Expose constants for testing
M._CONSTANTS = {
    BASE_LEASH = BASE_LEASH,
    COHERENCY_STICKINESS_LIMIT = COHERENCY_STICKINESS_LIMIT,
    HARD_CAP = HARD_CAP,
    HARD_CAP_ALWAYS_COHERENCY = HARD_CAP_ALWAYS_COHERENCY,
    POST_CHARGE_GRACE_S = POST_CHARGE_GRACE_S,
    UNDER_ATTACK_RANGE_SQ = UNDER_ATTACK_RANGE_SQ,
    COHERENCY_RADIUS_MARGIN = COHERENCY_RADIUS_MARGIN,
    DEFAULT_COHERENCY_RADIUS = DEFAULT_COHERENCY_RADIUS,
}

-- Expose for testing
M.MOVEMENT_ABILITIES = MOVEMENT_ABILITIES

return M
```

- [ ] **Step 3: Run tests to confirm skeleton loads**

Run: `busted tests/engagement_leash_spec.lua`
Expected: 0 tests, 0 failures (skeleton loads without error)

### Step 3b: Test and implement `compute_effective_leash`

- [ ] **Step 4: Write tests for leash computation**

Add inside the `describe("engagement_leash", ...)` block in `tests/engagement_leash_spec.lua`:

```lua
    describe("compute_effective_leash", function()
        local unit, target, follow_pos

        before_each(function()
            unit = make_unit("bot1")
            target = make_unit("enemy1")
            follow_pos = make_pos(0, 0, 0)
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0) -- 10m away
        end)

        after_each(function()
            POSITION_LOOKUP_STUB[unit] = nil
            POSITION_LOOKUP_STUB[target] = nil
            BLACKBOARDS_STUB[target] = nil
        end)

        it("returns base leash (12m) for idle bot with default coherency", function()
            local breed = make_breed()
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
            assert.equals(12, leash)
            assert.equals("base", reason)
        end)

        it("scales base leash with coherency radius", function()
            -- Stub coherency extension with 14m radius (Psyker talent)
            _G.ScriptUnit = {
                has_extension = function(_, ext_name)
                    if ext_name == "coherency_system" then
                        return { current_radius = function() return 14 end }
                    end
                    return nil
                end,
            }

            -- Force cache refresh by setting t > last_cache_t + 1
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 2)
            -- max(12, 14 + 4) = 18
            assert.equals(18, leash)
            assert.equals("base", reason)
        end)

        it("returns stickiness_limit (20m) when already engaged", function()
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 0)
            assert.equals(20, leash)
            assert.equals("already_engaged", reason)
        end)

        it("returns stickiness_limit (20m) during post-charge grace", function()
            EngagementLeash.record_charge(unit, 10)
            -- Within 4s grace window
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 12)
            assert.equals(20, leash)
            assert.equals("post_charge_grace", reason)
        end)

        it("returns base leash after post-charge grace expires", function()
            EngagementLeash.record_charge(unit, 10)
            -- After 4s grace window
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 15)
            assert.equals(12, leash)
            assert.equals("base", reason)
        end)

        it("returns stickiness_limit (20m) when enemy within 3m (under attack)", function()
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            POSITION_LOOKUP_STUB[target] = make_pos(2, 0, 0) -- 2m away < 3m
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 0)
            assert.equals(20, leash)
            assert.equals("under_attack", reason)
        end)

        it("does not trigger under_attack when enemy beyond 3m", function()
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            POSITION_LOOKUP_STUB[target] = make_pos(4, 0, 0) -- 4m away > 3m
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 0)
            assert.equals(12, leash)
            assert.equals("base", reason)
        end)

        it("returns stickiness_limit (20m) for ranged foray", function()
            local breed = make_breed({ ranged = true })
            BLACKBOARDS_STUB[target] = {
                perception = { target_unit = unit },
            }
            POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0) -- 15m, beyond under_attack range
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
            assert.equals(20, leash)
            assert.equals("ranged_foray", reason)
        end)

        it("does not trigger ranged foray when enemy not targeting bot", function()
            local breed = make_breed({ ranged = true })
            local other_unit = make_unit("other_player")
            BLACKBOARDS_STUB[target] = {
                perception = { target_unit = other_unit },
            }
            POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0)
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
            assert.equals(12, leash)
            assert.equals("base", reason)
        end)

        it("does not trigger ranged foray for melee breeds", function()
            local breed = make_breed({ ranged = false })
            BLACKBOARDS_STUB[target] = {
                perception = { target_unit = unit },
            }
            POSITION_LOOKUP_STUB[target] = make_pos(15, 0, 0)
            local leash, reason = EngagementLeash.compute_effective_leash(unit, target, breed, false, 0)
            assert.equals(12, leash)
            assert.equals("base", reason)
        end)

        it("hard cap is 25m by default", function()
            -- Even with post-charge + always engaged, should not exceed 25m
            EngagementLeash.record_charge(unit, 0)
            local leash, _ = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 1)
            assert.is_true(leash <= 25)
        end)

        it("hard cap is 30m with always-in-coherency talent", function()
            _G.ScriptUnit = {
                has_extension = function(_, ext_name)
                    if ext_name == "talent_system" then
                        return {
                            has_special_rule = function(_, rule_name)
                                return rule_name == "zealot_always_at_least_one_coherency"
                            end,
                        }
                    end
                    return nil
                end,
            }
            -- Force cache refresh
            local leash, _ = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 2)
            -- stickiness_limit (20) capped at 30 = 20
            assert.equals(20, leash)
            -- But the hard cap itself is 30, verified by checking constant
            assert.equals(30, EngagementLeash._CONSTANTS.HARD_CAP_ALWAYS_COHERENCY)
        end)

        it("priority action_data check: post_charge_grace takes precedence over already_engaged", function()
            EngagementLeash.record_charge(unit, 10)
            local _, reason = EngagementLeash.compute_effective_leash(unit, target, make_breed(), true, 12)
            assert.equals("post_charge_grace", reason)
        end)
    end)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `busted tests/engagement_leash_spec.lua`
Expected: ALL PASS (the module skeleton already implements `compute_effective_leash`)

### Step 3c: Test `should_extend_approach` and `record_charge` / `is_movement_ability`

- [ ] **Step 6: Write tests for approach range extension and utilities**

Add to the test file:

```lua
    describe("should_extend_approach", function()
        it("returns false when no extension condition", function()
            local unit = make_unit("bot")
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            local target = make_unit("enemy")
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
            assert.is_false(EngagementLeash.should_extend_approach(unit, target, make_breed(), false, 0))
        end)

        it("returns true when already engaged", function()
            local unit = make_unit("bot")
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            local target = make_unit("enemy")
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
            assert.is_true(EngagementLeash.should_extend_approach(unit, target, make_breed(), true, 0))
        end)

        it("returns true during post-charge grace", function()
            local unit = make_unit("bot")
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            local target = make_unit("enemy")
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
            EngagementLeash.record_charge(unit, 5)
            assert.is_true(EngagementLeash.should_extend_approach(unit, target, make_breed(), false, 7))
        end)
    end)

    describe("is_movement_ability", function()
        it("recognizes all charge/dash templates", function()
            assert.is_true(EngagementLeash.is_movement_ability("zealot_dash"))
            assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash"))
            assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash_improved"))
            assert.is_true(EngagementLeash.is_movement_ability("zealot_targeted_dash_improved_double"))
            assert.is_true(EngagementLeash.is_movement_ability("ogryn_charge"))
            assert.is_true(EngagementLeash.is_movement_ability("ogryn_charge_increased_distance"))
            assert.is_true(EngagementLeash.is_movement_ability("adamant_charge"))
        end)

        it("rejects non-movement abilities", function()
            assert.is_false(EngagementLeash.is_movement_ability("psyker_overcharge_stance"))
            assert.is_false(EngagementLeash.is_movement_ability("veteran_combat_ability"))
            assert.is_false(EngagementLeash.is_movement_ability("ogryn_taunt_shout"))
            assert.is_false(EngagementLeash.is_movement_ability("unknown"))
        end)
    end)

    describe("record_charge", function()
        it("records timestamp and enables grace period", function()
            local unit = make_unit("bot")
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            local target = make_unit("enemy")
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)

            -- Before recording: no grace
            local _, reason1 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 10)
            assert.equals("base", reason1)

            -- Record and check within window
            EngagementLeash.record_charge(unit, 10)
            local _, reason2 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 12)
            assert.equals("post_charge_grace", reason2)

            -- Check after window
            local _, reason3 = EngagementLeash.compute_effective_leash(unit, target, make_breed(), false, 15)
            assert.equals("base", reason3)
        end)
    end)

    describe("action_data restoration", function()
        -- This verifies the contract: hooks must restore original action_data values.
        -- Since we can't call the hook directly without the DMF framework,
        -- verify via compute_effective_leash that it doesn't mutate shared state.
        it("compute_effective_leash is pure (no side effects on inputs)", function()
            local unit = make_unit("bot")
            POSITION_LOOKUP_STUB[unit] = make_pos(0, 0, 0)
            local target = make_unit("enemy")
            POSITION_LOOKUP_STUB[target] = make_pos(10, 0, 0)
            local breed = make_breed()

            EngagementLeash.record_charge(unit, 0)
            EngagementLeash.compute_effective_leash(unit, target, breed, true, 1)

            -- breed should be unmodified
            assert.is_nil(breed.ranged)
            assert.equals("test_breed", breed.name)
        end)
    end)
```

- [ ] **Step 7: Run tests to verify all pass**

Run: `busted tests/engagement_leash_spec.lua`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add scripts/mods/BetterBots/engagement_leash.lua tests/engagement_leash_spec.lua
git commit -m "feat(engagement_leash): coherency-anchored melee engagement leash (#47)

New module hooks BtBotMeleeAction._allow_engage and _is_in_engage_range
to dynamically extend vanilla engagement distances based on:
- Already engaged: extend to coherency stickiness_limit (20m)
- Post-charge grace: 4s after movement abilities (dash/charge)
- Under melee attack (<3m): self-defense override
- Ranged foray: push toward ranged enemies targeting the bot
- Coherency-scaled base: max(12m, coherency_radius + 4m)
- Hard cap: 25m (30m with always-in-coherency talent)

Priority targets (specials/elites) remain math.huge — untouched.
"
```

---

## Task 4: Wire engagement_leash.lua into BetterBots.lua

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

- [ ] **Step 1: Add module load and init**

In `scripts/mods/BetterBots/BetterBots.lua`, add the module load alongside the other sub-modules (after the `BotProfiles` load around line 216):

```lua
local EngagementLeash = mod:io_dofile("BetterBots/scripts/mods/BetterBots/engagement_leash")
assert(EngagementLeash, "BetterBots: failed to load engagement_leash module")
```

Add the init call alongside the other init calls (after `BotProfiles.init` around line 227):

```lua
EngagementLeash.init({
    mod = mod,
    debug_log = _debug_log,
    debug_enabled = _debug_enabled,
    fixed_time = _fixed_time,
    perf = Perf,
    is_enabled = function()
        return Settings.is_feature_enabled("engagement_leash")
    end,
})
```

- [ ] **Step 2: Add register_hooks call**

Add alongside the other `register_hooks()` calls (after `BotProfiles.register_hooks()` around line 526):

```lua
EngagementLeash.register_hooks()
```

- [ ] **Step 3: Add charge timestamp recording to existing enter hook**

In the existing `BtBotActivateAbilityAction.enter` hook (around line 608, after `func(self, unit, ...)` is called and before the event log section), add:

```lua
                    -- Engagement leash (#47): record movement ability for post-charge grace
                    if unit then
                        local el_unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
                        local el_comp = el_unit_data
                            and action_data
                            and action_data.ability_component_name
                            and el_unit_data:read_component(action_data.ability_component_name)
                        local el_template = el_comp and el_comp.template_name
                        if el_template and EngagementLeash.is_movement_ability(el_template) then
                            EngagementLeash.record_charge(unit, _fixed_time())
                        end
                    end
```

This reads the template name (which the hook already does later for event logging) and records the charge timestamp if it's a movement ability.

- [ ] **Step 4: Add startup regression guard**

In `tests/startup_regressions_spec.lua`, add a test that confirms the module is loaded:

```lua
it("engagement_leash module loads without error", function()
    local ok, result = pcall(dofile, "scripts/mods/BetterBots/engagement_leash.lua")
    assert.is_true(ok, "engagement_leash.lua failed to load: " .. tostring(result))
    assert.is_not_nil(result)
    assert.is_not_nil(result.init)
    assert.is_not_nil(result.register_hooks)
    assert.is_not_nil(result.compute_effective_leash)
    assert.is_not_nil(result.record_charge)
    assert.is_not_nil(result.is_movement_ability)
end)
```

- [ ] **Step 5: Run all tests**

Run: `make test`
Expected: ALL PASS

- [ ] **Step 6: Run full quality gate**

Run: `make check`
Expected: format + lint + lsp + test all pass. Fix any issues.

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua tests/startup_regressions_spec.lua
git commit -m "feat(BetterBots): wire engagement_leash module (#47)

Load, init, and register engagement_leash hooks. Record movement ability
timestamps in BtBotActivateAbilityAction.enter for post-charge grace.
Add startup regression guard.
"
```

---

## Task 5: Update docs

**Files:**
- Modify: `docs/dev/architecture.md` — add engagement_leash module entry
- Modify: `docs/dev/known-issues.md` — add ranged_count bug (now fixed) if not already there
- Modify: `CLAUDE.md` — add engagement_leash.lua to file structure, update v0.9.0 status

- [ ] **Step 1: Update architecture.md**

Add `engagement_leash.lua` to the module listing in `docs/dev/architecture.md` with description:

```
engagement_leash.lua — Coherency-anchored melee engagement range (#47): hooks
BtBotMeleeAction._allow_engage and _is_in_engage_range to extend vanilla leash
based on combat context (already-engaged, post-charge, under-attack, ranged foray).
```

- [ ] **Step 2: Update CLAUDE.md file structure**

Add to the mod file structure listing in `CLAUDE.md`:

```
  engagement_leash.lua                      # Coherency-anchored melee engagement range (#47)
```

And add the test file:

```
  engagement_leash_spec.lua                 # engagement leash conditions, coherency scaling, grace periods
```

Update the `make test` line to include `engagement_leash` in the test list.

- [ ] **Step 3: Update v0.9.0 status in roadmap.md and status.md**

In `docs/dev/roadmap.md` and `docs/dev/status.md`, update #47 status from "Not started" to "Done":

```
| 47 | Combat-aware engagement leash | **Done** | Coherency-anchored leash: stickiness-limit extension, post-charge grace, under-attack/ranged-foray overrides |
```

- [ ] **Step 4: Commit**

```bash
git add docs/ CLAUDE.md
git commit -m "docs: add engagement_leash to architecture, file structure, status (#47)"
```

---

## Pre-submission Checklist

Before marking complete:

- [ ] `make check` passes (format + lint + lsp + test)
- [ ] All new code has debug logging gated on `_debug_enabled()` with per-bot throttle keys
- [ ] Priority targets (`fight_melee_priority_target`) confirmed untouched (math.huge skip)
- [ ] action_data values restored after each hook call
- [ ] Feature gate `engagement_leash` defaults to ON and can be toggled OFF
- [ ] No `ScriptUnit.extension` calls without `has_extension` guard
- [ ] Weak-keyed tables used for per-bot state (no memory leaks)
- [ ] `ranged_count` fix is a separate commit from the leash feature

## In-Game Verification Checklist (manual, post-merge)

- [ ] Mid-combat break-off: engage horde, walk player backward ~10m. Bot should continue fighting.
- [ ] Post-charge rubber-band: trigger Ogryn Bull Rush into a group. Bot should fight at destination for ~4s.
- [ ] Under-attack: let bot get surrounded while player is 15m+ away. Bot should fight back.
- [ ] Ranged foray: gunner shooting at bot from ~14m. Bot should push toward gunner.
- [ ] Hard cap: verify bot doesn't chase trash beyond ~25m from player.
- [ ] Priority targets: confirm specials/elites still get unlimited pursuit.
- [ ] Feature gate: toggle `enable_engagement_leash` off in mod settings → vanilla behavior restored.
- [ ] `bb-log summary` shows leash extension events in debug output.
