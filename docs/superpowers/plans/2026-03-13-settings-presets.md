# Settings Presets & Feature Gates Implementation Plan (#6)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 11-widget settings panel with 3 structured DMF groups, implement 6 ability category gates, 4 feature gates, and a full 4-preset behavior system with per-heuristic threshold tables.

**Architecture:** Bottom-up implementation: settings infrastructure first (category tables, feature gates, preset resolver), then heuristic threshold tables, then UI (widget definitions + localization), then module gate wiring, then docs. Each layer builds on the previous and can be tested independently. The `balanced` preset produces identical behavior to current hardcoded values — zero regression for existing users.

**Tech Stack:** Lua (DMF modding framework), busted (unit tests), `make check` (quality gate)

**Spec:** `docs/superpowers/specs/2026-03-13-settings-presets-design.md`

**Branch:** `feat/6-settings-presets` from `main`

---

## Execution Order & Parallelization

### Dependency graph

```
Task 1 (settings.lua rewrite)
  ↓ hard — all downstream tasks import the new API
Task 2 (heuristic threshold tables)
  ↓ hard — tests exercise the new threshold tables
Task 3 (grenade helper presets)
  ↓ soft — grenade tests need preset param
Task 4 (item heuristic thresholds)
  ↓ soft — item tests need preset param
Task 5 (feature gate wiring)
  ↓ soft — depends on Task 1 is_feature_enabled
Task 6 (widget definitions + localization)
  ↓ soft — needs new setting IDs from Task 1
Task 7 (doc updates)
  ↓ soft — after all code is done
Task 8 (quality gate + commit)
```

### Dependency details

| Task | Hard depends on | Touches |
|------|----------------|---------|
| 1 (settings rewrite) | — | `settings.lua`, `settings_spec.lua` |
| 2 (heuristic threshold tables) | 1 | `heuristics.lua`, `heuristics_spec.lua` |
| 3 (grenade presets) | 2 | `heuristics.lua`, `heuristics_spec.lua` |
| 4 (item thresholds) | 2 | `heuristics.lua`, `heuristics_spec.lua` |
| 5 (feature gates) | 1 | `sprint.lua`, `target_selection.lua`, `poxburster.lua`, `ping_system.lua`, `BetterBots.lua`, `condition_patch.lua`, `ability_queue.lua` |
| 6 (UI + localization) | 1 | `BetterBots_data.lua`, `BetterBots_localization.lua` |
| 7 (docs) | all | `AGENTS.md`, `docs/dev/architecture.md`, `docs/dev/status.md`, `docs/dev/roadmap.md`, `docs/nexus-description.bbcode` |
| 8 (quality gate) | all | — |

### Recommended execution strategy

**Sequential.** Each task builds on the previous. Tasks 5-6 could run in parallel after Task 4 completes, but the shared files make sequential safer.

---

## Chunk 1: Settings Infrastructure

### Task 1: Rewrite `settings.lua` — category tables, feature gates, preset resolver

**Files:**
- Modify: `scripts/mods/BetterBots/settings.lua` (full rewrite)
- Modify: `tests/settings_spec.lua` (rewrite to match new API)

**Context for the implementer:**

`settings.lua` currently has:
- `TIER_1_COMBAT_TEMPLATES`, `TIER_2_COMBAT_TEMPLATES`, `TIER_3_ITEM_ABILITIES` lookup tables
- `resolve_behavior_profile()` returning `"standard"` or `"testing"`
- `is_combat_template_enabled(name)`, `is_item_ability_enabled(name)`, `is_grenade_enabled(name)`

It needs to become:
- Category tables: `CATEGORY_STANCES`, `CATEGORY_CHARGES`, `CATEGORY_SHOUTS`, `CATEGORY_STEALTH` + a reverse lookup `TEMPLATE_TO_CATEGORY_SETTING`
- `FEATURE_GATES` table mapping feature names to setting IDs
- `resolve_preset()` returning one of `"testing"`, `"aggressive"`, `"balanced"`, `"conservative"` (maps old `"standard"` → `"balanced"`)
- `is_combat_template_enabled(template_name, ability_extension)` with veteran dual-category gate
- `is_feature_enabled(feature_name)` — new function
- Existing `is_item_ability_enabled` and `is_grenade_enabled` updated to use `enable_deployables` / `enable_grenades`

The `_resolve_veteran_class_tag` function from `heuristics.lua` is needed here for the dual-category gate. Rather than importing heuristics (circular dep), inline a minimal version that reads `ability_extension._equipped_abilities.combat_ability.ability_template_tweak_data.class_tag` and falls back to ability name matching.

- [ ] **Step 1: Write failing tests for the new settings API**

Add these test cases to `settings_spec.lua` (replace the existing file content):

```lua
local Settings = dofile("scripts/mods/BetterBots/settings.lua")
local helper = require("tests.test_helper")

-- Helper: create a mock mod that returns specific setting values
local function mock_mod(overrides)
    return {
        mod = {
            get = function(_, setting_id)
                return overrides and overrides[setting_id]
            end,
        },
    }
end

describe("settings", function()
    describe("resolve_preset", function()
        it("defaults to balanced when mod returns nil", function()
            Settings.init(mock_mod())
            assert.equals("balanced", Settings.resolve_preset())
        end)

        it("accepts all four preset values", function()
            for _, preset in ipairs({"testing", "aggressive", "balanced", "conservative"}) do
                Settings.init(mock_mod({ behavior_profile = preset }))
                assert.equals(preset, Settings.resolve_preset())
            end
        end)

        it("migrates standard to balanced", function()
            Settings.init(mock_mod({ behavior_profile = "standard" }))
            assert.equals("balanced", Settings.resolve_preset())
        end)

        it("falls back to balanced for unknown values", function()
            Settings.init(mock_mod({ behavior_profile = "broken" }))
            assert.equals("balanced", Settings.resolve_preset())
        end)
    end)

    describe("is_testing_profile", function()
        it("returns true only for testing preset", function()
            Settings.init(mock_mod({ behavior_profile = "testing" }))
            assert.is_true(Settings.is_testing_profile())

            Settings.init(mock_mod({ behavior_profile = "balanced" }))
            assert.is_false(Settings.is_testing_profile())
        end)
    end)

    describe("category gates", function()
        it("gates stance templates via enable_stances", function()
            Settings.init(mock_mod({ enable_stances = false }))
            assert.is_false(Settings.is_combat_template_enabled("psyker_overcharge_stance"))
            assert.is_false(Settings.is_combat_template_enabled("ogryn_gunlugger_stance"))
            assert.is_false(Settings.is_combat_template_enabled("adamant_stance"))
            assert.is_false(Settings.is_combat_template_enabled("broker_focus"))
            assert.is_false(Settings.is_combat_template_enabled("broker_punk_rage"))
        end)

        it("gates charge templates via enable_charges", function()
            Settings.init(mock_mod({ enable_charges = false }))
            assert.is_false(Settings.is_combat_template_enabled("zealot_dash"))
            assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash"))
            assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash_improved"))
            assert.is_false(Settings.is_combat_template_enabled("zealot_targeted_dash_improved_double"))
            assert.is_false(Settings.is_combat_template_enabled("ogryn_charge"))
            assert.is_false(Settings.is_combat_template_enabled("ogryn_charge_increased_distance"))
            assert.is_false(Settings.is_combat_template_enabled("adamant_charge"))
        end)

        it("gates shout templates via enable_shouts", function()
            Settings.init(mock_mod({ enable_shouts = false }))
            assert.is_false(Settings.is_combat_template_enabled("psyker_shout"))
            assert.is_false(Settings.is_combat_template_enabled("ogryn_taunt_shout"))
            assert.is_false(Settings.is_combat_template_enabled("adamant_shout"))
        end)

        it("gates stealth templates via enable_stealth", function()
            Settings.init(mock_mod({ enable_stealth = false }))
            assert.is_false(Settings.is_combat_template_enabled("veteran_stealth_combat_ability"))
            assert.is_false(Settings.is_combat_template_enabled("zealot_invisibility"))
        end)

        it("gates deployable items via enable_deployables", function()
            Settings.init(mock_mod({ enable_deployables = false }))
            assert.is_false(Settings.is_item_ability_enabled("zealot_relic"))
            assert.is_false(Settings.is_item_ability_enabled("psyker_force_field"))
            assert.is_false(Settings.is_item_ability_enabled("adamant_area_buff_drone"))
        end)

        it("gates grenades via enable_grenades", function()
            Settings.init(mock_mod({ enable_grenades = false }))
            assert.is_false(Settings.is_grenade_enabled("veteran_frag_grenade"))
            assert.is_false(Settings.is_grenade_enabled("psyker_throwing_knives"))
        end)

        it("leaves unknown templates enabled", function()
            Settings.init(mock_mod({ enable_stances = false, enable_charges = false }))
            assert.is_true(Settings.is_combat_template_enabled("unknown_template"))
            assert.is_true(Settings.is_item_ability_enabled("unknown_item"))
        end)
    end)

    describe("veteran dual-category gate", function()
        it("gates veteran_combat_ability as stance when class_tag is ranger", function()
            Settings.init(mock_mod({ enable_stances = false, enable_shouts = true }))
            local ext = helper.make_veteran_ability_extension("ranger", "veteran_combat_ability")
            assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ext))
        end)

        it("gates veteran_combat_ability as stance when class_tag is base", function()
            Settings.init(mock_mod({ enable_stances = false, enable_shouts = true }))
            local ext = helper.make_veteran_ability_extension("base", "veteran_combat_ability")
            assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ext))
        end)

        it("gates veteran_combat_ability as shout when class_tag is squad_leader", function()
            Settings.init(mock_mod({ enable_shouts = false, enable_stances = true }))
            local ext = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability")
            assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ext))
        end)

        it("falls back to enable_stances when class_tag is unknown", function()
            Settings.init(mock_mod({ enable_stances = false }))
            local ext = helper.make_veteran_ability_extension(nil, "veteran_combat_ability")
            assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability", ext))
        end)

        it("falls back to enable_stances when no ability_extension provided", function()
            Settings.init(mock_mod({ enable_stances = false }))
            assert.is_false(Settings.is_combat_template_enabled("veteran_combat_ability"))
        end)
    end)

    describe("feature gates", function()
        it("returns true when feature setting is true or nil", function()
            Settings.init(mock_mod())
            assert.is_true(Settings.is_feature_enabled("sprint"))
            assert.is_true(Settings.is_feature_enabled("pinging"))
            assert.is_true(Settings.is_feature_enabled("special_penalty"))
            assert.is_true(Settings.is_feature_enabled("poxburster"))
        end)

        it("returns false when feature setting is false", function()
            Settings.init(mock_mod({
                enable_sprint = false,
                enable_pinging = false,
                enable_special_penalty = false,
                enable_poxburster = false,
            }))
            assert.is_false(Settings.is_feature_enabled("sprint"))
            assert.is_false(Settings.is_feature_enabled("pinging"))
            assert.is_false(Settings.is_feature_enabled("special_penalty"))
            assert.is_false(Settings.is_feature_enabled("poxburster"))
        end)

        it("returns true for unknown feature names", function()
            Settings.init(mock_mod())
            assert.is_true(Settings.is_feature_enabled("nonexistent"))
        end)
    end)

    describe("heuristic coverage", function()
        it("keeps settings-exposed combat templates aligned with heuristic coverage", function()
            local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
            local handle = assert(io.open("scripts/mods/BetterBots/settings.lua", "r"))
            local source = assert(handle:read("*a"))
            handle:close()

            -- Extract template names from all CATEGORY_ tables
            local template_names = {}
            for block in source:gmatch("local%s+CATEGORY_%w+%s*=%s*(%b{})") do
                for name in block:gmatch("([a-z0-9_]+)%s*=") do
                    template_names[name] = true
                end
            end

            Heuristics.init({
                fixed_time = function() return 0 end,
                decision_context_cache = {},
                super_armor_breed_cache = {},
                ARMOR_TYPE_SUPER_ARMOR = 6,
                is_testing_profile = function() return false end,
                resolve_preset = function() return "balanced" end,
            })

            for template_name in pairs(template_names) do
                local result, rule = Heuristics.evaluate_heuristic(template_name, helper.make_context({
                    num_nearby = 1,
                }), {
                    conditions = helper.make_conditions(false),
                    ability_extension = helper.make_veteran_ability_extension("ranger", template_name),
                })

                assert.are_not.equal(
                    "fallback_unhandled_template",
                    rule,
                    string.format(
                        "settings template %s is missing heuristic coverage (result=%s, rule=%s)",
                        template_name, tostring(result), tostring(rule)
                    )
                )
            end
        end)
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `resolve_preset`, `is_feature_enabled`, new category setting IDs don't exist yet.

- [ ] **Step 3: Implement `settings.lua`**

Rewrite `settings.lua` with the following structure. The full implementation:

```lua
local M = {}

local _mod

-- Category → setting ID mapping
local CATEGORY_STANCES = {
    -- veteran_combat_ability is NOT here — uses dual-category gate
    psyker_overcharge_stance = true,
    ogryn_gunlugger_stance = true,
    adamant_stance = true,
    broker_focus = true,
    broker_punk_rage = true,
}

local CATEGORY_CHARGES = {
    zealot_dash = true,
    zealot_targeted_dash = true,
    zealot_targeted_dash_improved = true,
    zealot_targeted_dash_improved_double = true,
    ogryn_charge = true,
    ogryn_charge_increased_distance = true,
    adamant_charge = true,
}

local CATEGORY_SHOUTS = {
    psyker_shout = true,
    ogryn_taunt_shout = true,
    adamant_shout = true,
}

local CATEGORY_STEALTH = {
    veteran_stealth_combat_ability = true,
    zealot_invisibility = true,
}

-- Reverse lookup: template_name → setting_id
-- Built once at load time. veteran_combat_ability excluded (dual-category).
local TEMPLATE_TO_CATEGORY_SETTING = {}

local CATEGORY_TO_SETTING = {
    { table = CATEGORY_STANCES, setting = "enable_stances" },
    { table = CATEGORY_CHARGES, setting = "enable_charges" },
    { table = CATEGORY_SHOUTS,  setting = "enable_shouts" },
    { table = CATEGORY_STEALTH, setting = "enable_stealth" },
}

for _, entry in ipairs(CATEGORY_TO_SETTING) do
    for template_name in pairs(entry.table) do
        TEMPLATE_TO_CATEGORY_SETTING[template_name] = entry.setting
    end
end

-- Deployable item abilities (all map to enable_deployables)
local DEPLOYABLE_ITEMS = {
    zealot_relic = true,
    psyker_force_field = true,
    psyker_force_field_improved = true,
    psyker_force_field_dome = true,
    adamant_area_buff_drone = true,
    broker_ability_stimm_field = true,
}

-- Feature gates: feature_name → setting_id
local FEATURE_GATES = {
    sprint          = "enable_sprint",
    pinging         = "enable_pinging",
    special_penalty = "enable_special_penalty",
    poxburster      = "enable_poxburster",
}

-- Preset system
local VALID_PRESETS = {
    testing = true,
    aggressive = true,
    balanced = true,
    conservative = true,
}

local function _setting_enabled(setting_id)
    if not _mod then
        return true
    end

    local value = _mod:get(setting_id)
    if value == nil then
        return true
    end

    return value == true
end

-- Minimal veteran class_tag resolution for the dual-category gate.
-- Mirrors _resolve_veteran_class_tag in heuristics.lua but avoids the
-- circular dependency by inlining the lookup chain.
local function _veteran_class_tag(ability_extension)
    local equipped = ability_extension and ability_extension._equipped_abilities
    local combat = equipped and equipped.combat_ability
    local tweak = combat and combat.ability_template_tweak_data
    local class_tag = tweak and tweak.class_tag

    if class_tag then
        return class_tag
    end

    local name = combat and combat.name or ""
    if string.find(name, "shout", 1, true) then
        return "squad_leader"
    end
    if string.find(name, "stance", 1, true) then
        return "ranger"
    end

    return nil
end

function M.init(deps)
    _mod = deps.mod
end

function M.resolve_preset()
    if not _mod then
        return "balanced"
    end

    local value = _mod:get("behavior_profile")

    -- Silent migration: "standard" → "balanced"
    if value == "standard" then
        return "balanced"
    end

    if VALID_PRESETS[value] then
        return value
    end

    return "balanced"
end

function M.is_testing_profile()
    return M.resolve_preset() == "testing"
end

function M.is_combat_template_enabled(template_name, ability_extension)
    -- Dual-category gate for veteran_combat_ability
    if template_name == "veteran_combat_ability" then
        local tag = _veteran_class_tag(ability_extension)
        if tag == "squad_leader" then
            return _setting_enabled("enable_shouts")
        end
        -- ranger, base, or unknown → stances
        return _setting_enabled("enable_stances")
    end

    local setting_id = TEMPLATE_TO_CATEGORY_SETTING[template_name]
    if not setting_id then
        return true
    end

    return _setting_enabled(setting_id)
end

function M.is_item_ability_enabled(ability_name)
    if DEPLOYABLE_ITEMS[ability_name] then
        return _setting_enabled("enable_deployables")
    end

    return true
end

function M.is_grenade_enabled(_grenade_name)
    return _setting_enabled("enable_grenades")
end

function M.is_feature_enabled(feature_name)
    local setting_id = FEATURE_GATES[feature_name]
    if not setting_id then
        return true
    end

    return _setting_enabled(setting_id)
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All settings tests PASS. Some existing tests that reference `resolve_behavior_profile` or old tier setting IDs may fail — those are expected and will be handled.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/settings.lua tests/settings_spec.lua
git commit -m "feat(settings): category gates, feature gates, preset resolver (#6)

Replace tier-based template grouping with 6 player-facing categories.
Add is_feature_enabled() for runtime module gating.
Add resolve_preset() with 4 presets + standard→balanced migration.
Veteran dual-category gate resolves class_tag at runtime."
```

---

## Chunk 2: Heuristic Threshold Tables

### Task 2: Add per-heuristic threshold tables

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

**Context for the implementer:**

The existing 9-arg dispatch signature and `TEMPLATE_HEURISTICS` table stay unchanged. Thresholds are resolved in `_evaluate_template_heuristic` and passed as an extra trailing argument to each function. Functions that need thresholds accept them as a new final parameter; functions that don't simply ignore the extra arg (Lua silently drops it).

**Key constraint:** The `balanced` threshold values MUST exactly match the current hardcoded constants. This ensures zero behavior change for existing users and that all 418 existing tests pass with no changes.

**Approach — do it in this order within heuristics.lua:**

1. Add `_resolve_preset` module-local and update `init(deps)` to accept `resolve_preset`
2. Add `context.preset` to `build_context()`
3. Add threshold tables above each function (16 combat + 3 item heuristics) with concrete values
4. Each function that uses thresholds adds a `thresholds` parameter as its last arg and reads from it instead of hardcoded values
5. `_evaluate_template_heuristic` resolves the threshold table, then passes it as an extra arg when calling each function
6. `TEMPLATE_HEURISTICS` dispatch table stays as-is — the wrappers just pass thresholds through
7. Update `evaluate_heuristic`, `evaluate_item_heuristic`, `evaluate_grenade_heuristic` to accept `opts.preset`

- [ ] **Step 1: Add `_resolve_preset` to heuristics init and `context.preset` to build_context**

In `heuristics.lua`, add a module-local `_resolve_preset` alongside the existing module-locals at the top. Update `init(deps)` to accept `resolve_preset`:

```lua
-- Add near top with other module-locals:
local _resolve_preset

-- In init(deps):
_resolve_preset = deps.resolve_preset
```

In `build_context()`, after constructing the context table (after `in_hazard = false`), add:

```lua
context.preset = _resolve_preset and _resolve_preset() or "balanced"
```

- [ ] **Step 2: Add ALL threshold tables with concrete values**

Place each table directly above its corresponding function. Every `balanced` value MUST match the current hardcoded constant exactly. Here are all 16 combat + 3 item tables:

```lua
-- VETERAN VoC (squad_leader branch of veteran_combat_ability)
local VETERAN_VOC_THRESHOLDS = {
    aggressive   = { surrounded = 2, low_toughness = 0.65, low_toughness_nearby = 1,
                     critical_toughness = 0.40, ally_aid_dist = 14,
                     block_safe_toughness = 0.70, block_safe_max_enemies = 2 },
    balanced     = { surrounded = 3, low_toughness = 0.50, low_toughness_nearby = 2,
                     critical_toughness = 0.25, ally_aid_dist = 9,
                     block_safe_toughness = 0.85, block_safe_max_enemies = 1 },
    conservative = { surrounded = 4, low_toughness = 0.35, low_toughness_nearby = 3,
                     critical_toughness = 0.15, ally_aid_dist = 6,
                     block_safe_toughness = 0.95, block_safe_max_enemies = 0 },
}

-- VETERAN STANCE (ranger/base branch of veteran_combat_ability)
local VETERAN_STANCE_THRESHOLDS = {
    aggressive   = { block_surrounded = 7, urgent_max_enemies = 3 },
    balanced     = { block_surrounded = 5, urgent_max_enemies = 2 },
    conservative = { block_surrounded = 4, urgent_max_enemies = 1 },
}

local VETERAN_STEALTH_THRESHOLDS = {
    aggressive   = { critical_toughness = 0.35, low_health = 0.55,
                     overwhelmed_nearby = 4, overwhelmed_toughness = 0.65 },
    balanced     = { critical_toughness = 0.25, low_health = 0.40,
                     overwhelmed_nearby = 5, overwhelmed_toughness = 0.50 },
    conservative = { critical_toughness = 0.15, low_health = 0.25,
                     overwhelmed_nearby = 6, overwhelmed_toughness = 0.35 },
}

local ZEALOT_DASH_THRESHOLDS = {
    aggressive   = { low_toughness = 0.45, elite_min_dist = 3, elite_max_dist = 28,
                     combat_gap_nearby = 1, combat_gap_min_dist = 3, combat_gap_max_dist = 22 },
    balanced     = { low_toughness = 0.30, elite_min_dist = 5, elite_max_dist = 20,
                     combat_gap_nearby = 2, combat_gap_min_dist = 4, combat_gap_max_dist = 15 },
    conservative = { low_toughness = 0.20, elite_min_dist = 6, elite_max_dist = 15,
                     combat_gap_nearby = 3, combat_gap_min_dist = 5, combat_gap_max_dist = 10 },
}

local ZEALOT_INVISIBILITY_THRESHOLDS = {
    aggressive   = { emergency_toughness = 0.45, emergency_health = 0.45,
                     overwhelmed_nearby = 3, overwhelmed_toughness = 0.75,
                     ally_dist = 18, ally_nearby = 1 },
    balanced     = { emergency_toughness = 0.30, emergency_health = 0.30,
                     overwhelmed_nearby = 4, overwhelmed_toughness = 0.60,
                     ally_dist = 12, ally_nearby = 2 },
    conservative = { emergency_toughness = 0.20, emergency_health = 0.20,
                     overwhelmed_nearby = 5, overwhelmed_toughness = 0.45,
                     ally_dist = 8, ally_nearby = 3 },
}

local PSYKER_SHOUT_THRESHOLDS = {
    aggressive   = { high_peril = 0.60, surrounded = 2, low_toughness = 0.30,
                     priority_dist = 30, block_low_value_toughness = 0.35 },
    balanced     = { high_peril = 0.75, surrounded = 3, low_toughness = 0.20,
                     priority_dist = 20, block_low_value_toughness = 0.50 },
    conservative = { high_peril = 0.85, surrounded = 4, low_toughness = 0.12,
                     priority_dist = 15, block_low_value_toughness = 0.65 },
}

local PSYKER_STANCE_THRESHOLDS = {
    aggressive   = { threat_cr = 3.0, combat_density = 2 },
    balanced     = { threat_cr = 4.0, combat_density = 3 },
    conservative = { threat_cr = 5.0, combat_density = 4 },
}

local OGRYN_CHARGE_THRESHOLDS = {
    aggressive   = { opportunity_min_dist = 4, opportunity_max_dist = 28,
                     escape_nearby = 2, escape_toughness = 0.45 },
    balanced     = { opportunity_min_dist = 6, opportunity_max_dist = 20,
                     escape_nearby = 3, escape_toughness = 0.30 },
    conservative = { opportunity_min_dist = 8, opportunity_max_dist = 15,
                     escape_nearby = 4, escape_toughness = 0.20 },
}

local OGRYN_TAUNT_THRESHOLDS = {
    aggressive   = { horde_nearby = 2, horde_toughness = 0.20, horde_health = 0.15,
                     high_threat_cr = 3.0, block_low_value_enemies = 3, block_low_value_cr = 2.5 },
    balanced     = { horde_nearby = 3, horde_toughness = 0.35, horde_health = 0.25,
                     high_threat_cr = 4.0, block_low_value_enemies = 2, block_low_value_cr = 1.5 },
    conservative = { horde_nearby = 4, horde_toughness = 0.50, horde_health = 0.35,
                     high_threat_cr = 5.0, block_low_value_enemies = 1, block_low_value_cr = 1.0 },
}

local OGRYN_GUNLUGGER_THRESHOLDS = {
    aggressive   = { block_melee_nearby = 5, block_low_threat_cr = 1.0,
                     high_threat_cr = 3.0, high_threat_max_enemies = 3 },
    balanced     = { block_melee_nearby = 4, block_low_threat_cr = 1.5,
                     high_threat_cr = 4.0, high_threat_max_enemies = 2 },
    conservative = { block_melee_nearby = 3, block_low_threat_cr = 2.0,
                     high_threat_cr = 5.5, high_threat_max_enemies = 1 },
}

local ADAMANT_STANCE_THRESHOLDS = {
    aggressive   = { low_toughness = 0.45, surrounded_nearby = 1, surrounded_toughness = 0.85,
                     elite_count = 1, elite_toughness = 0.65,
                     block_safe_toughness = 0.55, block_safe_max_enemies = 2 },
    balanced     = { low_toughness = 0.30, surrounded_nearby = 2, surrounded_toughness = 0.70,
                     elite_count = 2, elite_toughness = 0.50,
                     block_safe_toughness = 0.70, block_safe_max_enemies = 1 },
    conservative = { low_toughness = 0.20, surrounded_nearby = 3, surrounded_toughness = 0.55,
                     elite_count = 3, elite_toughness = 0.35,
                     block_safe_toughness = 0.80, block_safe_max_enemies = 0 },
}

local ADAMANT_CHARGE_THRESHOLDS = {
    aggressive   = { density_nearby = 1, density_max_dist = 14 },
    balanced     = { density_nearby = 2, density_max_dist = 10 },
    conservative = { density_nearby = 3, density_max_dist = 7 },
}

local ADAMANT_SHOUT_THRESHOLDS = {
    aggressive   = { low_toughness = 0.40, low_toughness_nearby = 1,
                     density_nearby = 3, density_toughness = 0.75,
                     elite_toughness = 0.65 },
    balanced     = { low_toughness = 0.25, low_toughness_nearby = 2,
                     density_nearby = 4, density_toughness = 0.60,
                     elite_toughness = 0.50 },
    conservative = { low_toughness = 0.15, low_toughness_nearby = 3,
                     density_nearby = 5, density_toughness = 0.45,
                     elite_toughness = 0.35 },
}

local ZEALOT_RELIC_THRESHOLDS = {
    aggressive   = { team_toughness = 0.55, team_max_enemies = 3,
                     self_critical_toughness = 0.35, self_max_enemies = 4 },
    balanced     = { team_toughness = 0.40, team_max_enemies = 2,
                     self_critical_toughness = 0.25, self_max_enemies = 3 },
    conservative = { team_toughness = 0.30, team_max_enemies = 1,
                     self_critical_toughness = 0.15, self_max_enemies = 2 },
}

local FORCE_FIELD_THRESHOLDS = {
    aggressive   = { block_safe_toughness = 0.65, pressure_nearby = 2,
                     pressure_toughness = 0.55, ranged_toughness = 0.75 },
    balanced     = { block_safe_toughness = 0.80, pressure_nearby = 3,
                     pressure_toughness = 0.40, ranged_toughness = 0.60 },
    conservative = { block_safe_toughness = 0.90, pressure_nearby = 4,
                     pressure_toughness = 0.25, ranged_toughness = 0.45 },
}

local DRONE_THRESHOLDS = {
    aggressive   = { block_low_value_enemies = 1, team_horde_nearby = 3,
                     overwhelmed_nearby = 4, overwhelmed_toughness = 0.65 },
    balanced     = { block_low_value_enemies = 2, team_horde_nearby = 4,
                     overwhelmed_nearby = 5, overwhelmed_toughness = 0.50 },
    conservative = { block_low_value_enemies = 3, team_horde_nearby = 5,
                     overwhelmed_nearby = 6, overwhelmed_toughness = 0.35 },
}
```

- [ ] **Step 3: Add thresholds parameter to each function that needs it**

Each function adds `thresholds` as its LAST parameter and reads from it instead of hardcoded values. The existing `(context)` parameter stays in place. Example for `_can_activate_veteran_stealth`:

Before:
```lua
local function _can_activate_veteran_stealth(context)
    if context.toughness_pct < 0.25 and context.num_nearby >= 2 then
```

After:
```lua
local function _can_activate_veteran_stealth(context, thresholds)
    if context.toughness_pct < thresholds.critical_toughness and context.num_nearby >= 2 then
```

For `_can_activate_veteran_combat_ability`, it keeps the full 9-arg signature and adds `thresholds` as arg 10:
```lua
local function _can_activate_veteran_combat_ability(
    conditions, unit, blackboard, scratchpad, condition_args,
    action_data, is_running, ability_extension, context, thresholds
)
```

The VoC branch reads from `VETERAN_VOC_THRESHOLDS[context.preset]`, the stance branch from `VETERAN_STANCE_THRESHOLDS[context.preset]`. The `thresholds` parameter passed in is the stance table (used for the common case); VoC looks up its own.

Functions without tables (broker_focus, broker_rage, stimm_field) keep `(context)` — the extra `nil` arg from the caller is silently ignored by Lua.

- [ ] **Step 4: Update `_evaluate_template_heuristic` to resolve and pass thresholds**

The existing function structure stays. Add threshold resolution before calling each heuristic:

```lua
-- Master lookup — maps template name to threshold table
local HEURISTIC_THRESHOLDS = {
    veteran_stealth_combat_ability = VETERAN_STEALTH_THRESHOLDS,
    zealot_dash = ZEALOT_DASH_THRESHOLDS,
    zealot_targeted_dash = ZEALOT_DASH_THRESHOLDS,
    zealot_targeted_dash_improved = ZEALOT_DASH_THRESHOLDS,
    zealot_targeted_dash_improved_double = ZEALOT_DASH_THRESHOLDS,
    zealot_invisibility = ZEALOT_INVISIBILITY_THRESHOLDS,
    psyker_shout = PSYKER_SHOUT_THRESHOLDS,
    psyker_overcharge_stance = PSYKER_STANCE_THRESHOLDS,
    ogryn_charge = OGRYN_CHARGE_THRESHOLDS,
    ogryn_charge_increased_distance = OGRYN_CHARGE_THRESHOLDS,
    ogryn_taunt_shout = OGRYN_TAUNT_THRESHOLDS,
    ogryn_gunlugger_stance = OGRYN_GUNLUGGER_THRESHOLDS,
    adamant_stance = ADAMANT_STANCE_THRESHOLDS,
    adamant_charge = ADAMANT_CHARGE_THRESHOLDS,
    adamant_shout = ADAMANT_SHOUT_THRESHOLDS,
    -- broker_focus, broker_punk_rage: no table (DLC-blocked)
}
```

In `_evaluate_template_heuristic`, resolve thresholds and pass as extra arg:

```lua
local preset = context.preset or "balanced"
local threshold_table = HEURISTIC_THRESHOLDS[ability_template_name]
local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil

-- veteran_combat_ability special case: pass thresholds as arg 10
if ability_template_name == "veteran_combat_ability" then
    return _can_activate_veteran_combat_ability(
        conditions, unit, blackboard, scratchpad, condition_args,
        action_data, is_running, ability_extension, context, thresholds
    )
end

-- All other templates: existing dispatch + thresholds as extra trailing arg
local fn = TEMPLATE_HEURISTICS[ability_template_name]
if not fn then return nil, "fallback_unhandled_template" end
return fn(conditions, unit, blackboard, scratchpad, condition_args,
    action_data, is_running, ability_extension, context, thresholds)
```

- [ ] **Step 5: Update `TEMPLATE_HEURISTICS` wrappers to pass thresholds through**

Each wrapper adds the thresholds parameter. The 9-arg convention stays:

```lua
-- Before:
veteran_stealth_combat_ability = function(_, _, _, _, _, _, _, _, context)
    return _can_activate_veteran_stealth(context)
end,

-- After:
veteran_stealth_combat_ability = function(_, _, _, _, _, _, _, _, context, thresholds)
    return _can_activate_veteran_stealth(context, thresholds)
end,
```

Same pattern for all entries. Functions without thresholds (broker_focus, broker_rage) stay as-is — the extra `thresholds` arg is silently dropped.

- [ ] **Step 6: Update `_testing_profile_active` to use `opts.preset`**

The existing function checks `opts.behavior_profile == "testing"`. Update it to check `opts.preset`:

```lua
local function _testing_profile_active(opts)
    if opts and opts.preset then
        return opts.preset == "testing"
    end

    return _is_testing_profile and _is_testing_profile() or false
end
```

- [ ] **Step 7: Update `evaluate_heuristic`, `evaluate_item_heuristic`, `evaluate_grenade_heuristic` to accept `opts.preset`**

```lua
local function evaluate_heuristic(template_name, context, opts)
    opts = opts or {}
    local preset = opts.preset or "balanced"

    if template_name == "veteran_combat_ability" then
        -- Look up VoC vs stance thresholds based on class_tag
        local tag = _resolve_veteran_class_tag_from_ext(opts.ability_extension)
        local threshold_table = (tag == "squad_leader")
            and VETERAN_VOC_THRESHOLDS or VETERAN_STANCE_THRESHOLDS
        local thresholds = threshold_table[preset] or threshold_table.balanced

        local can_activate, rule = _can_activate_veteran_combat_ability(
            opts.conditions or {},
            opts.unit,
            nil, nil, nil, nil, false,
            opts.ability_extension,
            context,
            thresholds
        )
        return _apply_behavior_profile(can_activate, rule, context, opts)
    end

    local fn = TEMPLATE_HEURISTICS[template_name]
    if not fn then
        return nil, "fallback_unhandled_template"
    end

    local threshold_table = HEURISTIC_THRESHOLDS[template_name]
    local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
    -- TEMPLATE_HEURISTICS entries expect 9 positional args + thresholds as arg 10
    local can_activate, rule = fn(nil, nil, nil, nil, nil, nil, nil, nil, context, thresholds)
    return _apply_behavior_profile(can_activate, rule, context, opts)
end
```

Apply the same `opts.preset` pattern to `evaluate_item_heuristic` and `evaluate_grenade_heuristic`.

- [ ] **Step 8: Update `init(deps)` to accept `resolve_preset`**

```lua
init = function(deps)
    _fixed_time = deps.fixed_time
    _decision_context_cache = deps.decision_context_cache
    _super_armor_breed_cache = deps.super_armor_breed_cache
    _armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
    _is_testing_profile = deps.is_testing_profile
    _resolve_preset = deps.resolve_preset
end,
```

- [ ] **Step 9: Run all tests**

Run: `make test`
Expected: All 418 existing tests PASS (balanced thresholds = current hardcoded values). Some tests may need mechanical updates if they call `TEMPLATE_HEURISTICS` entries directly rather than through `evaluate_heuristic`.

- [ ] **Step 10: Add preset directional tests**

Add tests to `heuristics_spec.lua` that verify aggressive triggers more readily than conservative. For one representative heuristic:

```lua
describe("preset thresholds", function()
    it("aggressive triggers veteran_stealth at higher toughness than balanced", function()
        -- This context triggers under aggressive but NOT under balanced
        local borderline = ctx({
            num_nearby = 3,
            toughness_pct = 0.30, -- above balanced's 0.25, below aggressive's 0.35
        })
        local ok_agg = evaluate(T, borderline, { preset = "aggressive" })
        local ok_bal = evaluate(T, borderline, { preset = "balanced" })
        assert.is_true(ok_agg)
        assert.is_false(ok_bal)
    end)

    it("conservative triggers veteran_stealth only at lower toughness than balanced", function()
        local borderline = ctx({
            num_nearby = 3,
            toughness_pct = 0.20, -- above conservative's 0.15, below balanced's 0.25
        })
        local ok_bal = evaluate(T, borderline, { preset = "balanced" })
        local ok_con = evaluate(T, borderline, { preset = "conservative" })
        assert.is_true(ok_bal)
        assert.is_false(ok_con)
    end)
end)
```

Add similar directional tests for at least 3 more heuristics (zealot_dash distance, ogryn_taunt density, psyker_shout count).

- [ ] **Step 11: Run tests**

Run: `make test`
Expected: All PASS.

- [ ] **Step 12: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): per-heuristic threshold tables for behavior presets (#6)

16 combat + 3 item heuristics get preset-specific threshold tables.
balanced values match current hardcoded constants (zero behavior change).
Thresholds passed as extra trailing arg — 9-arg dispatch unchanged.
evaluate_heuristic accepts opts.preset for test injection."
```

---

### Task 3: Grenade helper preset offsets

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

- [ ] **Step 1: Add offset tables for all 4 grenade helpers**

Above each helper function, add the offset table:

```lua
local GRENADE_HORDE_PRESETS = {
    aggressive   = { nearby_offset = -1, challenge_offset = -0.5 },
    balanced     = { nearby_offset =  0, challenge_offset =  0   },
    conservative = { nearby_offset =  1, challenge_offset =  0.5 },
}

local GRENADE_PRIORITY_PRESETS = {
    aggressive   = { distance_offset = -1 },
    balanced     = { distance_offset =  0 },
    conservative = { distance_offset =  1 },
}

local GRENADE_DEFENSIVE_PRESETS = {
    aggressive   = { toughness_offset = 0.10, count_offset = -1 },
    balanced     = { toughness_offset = 0,    count_offset =  0 },
    conservative = { toughness_offset = -0.10, count_offset = 1 },
}

local GRENADE_MINE_PRESETS = {
    aggressive   = { elite_offset = -1, density_offset = -1 },
    balanced     = { elite_offset =  0, density_offset =  0 },
    conservative = { elite_offset =  1, density_offset =  1 },
}
```

- [ ] **Step 2: Update each helper to accept `preset` parameter and apply offsets**

Example for `_grenade_horde`:

```lua
local function _grenade_horde(context, min_nearby, min_challenge, rule_prefix, preset)
    local t = GRENADE_HORDE_PRESETS[preset] or GRENADE_HORDE_PRESETS.balanced
    local adj_nearby = min_nearby + t.nearby_offset
    local adj_challenge = min_challenge + t.challenge_offset
    if context.num_nearby >= adj_nearby and context.challenge_rating_sum >= adj_challenge then
        return true, rule_prefix .. "_horde"
    end
    return false, rule_prefix .. "_hold"
end
```

Do the same for `_grenade_priority_target`, `_grenade_defensive`, `_grenade_mine`.

- [ ] **Step 3: Update `GRENADE_HEURISTICS` callers to pass preset**

Each entry now passes `context.preset`:

```lua
veteran_frag_grenade = function(context)
    return _grenade_horde(context, 6, 2.5, "grenade_frag", context.preset)
end,
```

For `_grenade_chain_lightning`, add a standalone threshold table (not offset-based):

```lua
local CHAIN_LIGHTNING_THRESHOLDS = {
    aggressive   = { crowd = 3, mixed_nearby = 2 },
    balanced     = { crowd = 4, mixed_nearby = 3 },
    conservative = { crowd = 5, mixed_nearby = 4 },
}
```

- [ ] **Step 4: Update `evaluate_grenade_heuristic` to inject preset into context**

```lua
local function evaluate_grenade_heuristic(grenade_template_name, context, opts)
    if not context then
        return false, "grenade_no_context"
    end

    local preset = (opts and opts.preset) or context.preset or "balanced"
    -- Temporarily inject preset into context for helper functions
    local saved_preset = context.preset
    context.preset = preset

    local fn = GRENADE_HEURISTICS[grenade_template_name]
    local can_activate, rule
    if fn then
        can_activate, rule = fn(context)
    elseif context.num_nearby > 0 then
        can_activate, rule = true, "grenade_generic"
    else
        can_activate, rule = false, "grenade_no_enemies"
    end

    context.preset = saved_preset
    return _apply_behavior_profile(can_activate, rule, context, opts)
end
```

- [ ] **Step 5: Add grenade preset directional tests**

```lua
describe("grenade preset offsets", function()
    it("aggressive frag triggers at lower density than balanced", function()
        local c = ctx({ num_nearby = 5, challenge_rating_sum = 2.0, preset = "aggressive" })
        local ok_agg = evaluate_grenade("veteran_frag_grenade", c, { preset = "aggressive" })
        local ok_bal = evaluate_grenade("veteran_frag_grenade", c, { preset = "balanced" })
        assert.is_true(ok_agg)
        assert.is_false(ok_bal)
    end)
end)
```

- [ ] **Step 6: Run tests**

Run: `make test`
Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): grenade helper preset offsets (#6)

All 4 grenade helpers (_grenade_horde, _grenade_priority_target,
_grenade_defensive, _grenade_mine) accept preset parameter and
apply additive offsets. _grenade_chain_lightning gets a standalone
threshold table."
```

---

### Task 4: Wire item heuristic preset plumbing + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`

**Context:** Item threshold tables (ZEALOT_RELIC_THRESHOLDS, FORCE_FIELD_THRESHOLDS, DRONE_THRESHOLDS) and function signature updates were already done in Task 2. This task wires the lookup/dispatch and adds item-specific tests.

- [ ] **Step 1: Add `ITEM_THRESHOLDS` lookup table and wire `evaluate_item_heuristic`**

Add a master lookup keyed by ability name, same pattern as `HEURISTIC_THRESHOLDS` for combat:

```lua
local ITEM_THRESHOLDS = {
    zealot_relic = ZEALOT_RELIC_THRESHOLDS,
    psyker_force_field = FORCE_FIELD_THRESHOLDS,
    psyker_force_field_improved = FORCE_FIELD_THRESHOLDS,
    psyker_force_field_dome = FORCE_FIELD_THRESHOLDS,
    adamant_area_buff_drone = DRONE_THRESHOLDS,
    -- broker_ability_stimm_field: no table (DLC-blocked)
}
```

Update `evaluate_item_heuristic` to resolve thresholds from `opts.preset` and pass to the heuristic function:

```lua
local function evaluate_item_heuristic(ability_name, context, opts)
    local fn = ITEM_HEURISTICS[ability_name]
    if not fn then
        return false, "unknown_item_ability"
    end

    local preset = (opts and opts.preset) or context.preset or "balanced"
    local threshold_table = ITEM_THRESHOLDS[ability_name]
    local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
    local can_activate, rule = fn(context, thresholds)
    return _apply_behavior_profile(can_activate, rule, context, opts)
end
```

- [ ] **Step 2: Add item preset directional tests**

```lua
describe("item preset thresholds", function()
    it("aggressive relic triggers at higher team toughness than balanced", function()
        local c = ctx({ num_nearby = 3, toughness_pct = 0.50 })
        local ok_agg = evaluate_item("zealot_relic", c, { preset = "aggressive" })
        local ok_bal = evaluate_item("zealot_relic", c, { preset = "balanced" })
        assert.is_true(ok_agg)
        assert.is_false(ok_bal)
    end)
end)
```

- [ ] **Step 3: Run tests, commit**

Run: `make test`
Expected: All PASS.

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(heuristics): wire item heuristic preset plumbing + tests (#6)

ITEM_THRESHOLDS lookup table + evaluate_item_heuristic preset
resolution. Directional tests for item presets."
```

---

## Chunk 3: Feature Gates, UI, Wiring & Docs

### Task 5: Wire feature gates into modules

**Files:**
- Modify: `scripts/mods/BetterBots/sprint.lua`
- Modify: `scripts/mods/BetterBots/target_selection.lua`
- Modify: `scripts/mods/BetterBots/poxburster.lua`
- Modify: `scripts/mods/BetterBots/ping_system.lua`
- Modify: `scripts/mods/BetterBots/condition_patch.lua`
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua` (init blocks + update tick)

**Context:** Each module needs an `_is_enabled` function injected via `init(deps)` and checked at the top of its hot-path callbacks.

- [ ] **Step 1: Add `is_enabled` to Sprint**

In `sprint.lua`, add `local _is_enabled` near the top module-locals. In `Sprint.init`:
```lua
_is_enabled = deps.is_enabled
```

In `on_update_movement`, add early return after `func(self, unit, input, dt, t)`:
```lua
if _is_enabled and not _is_enabled() then
    if perf_t0 then _perf.finish("sprint.update_movement", perf_t0) end
    return
end
```

- [ ] **Step 2: Add `is_enabled` to TargetSelection**

In `target_selection.lua`, add `local _is_enabled` module-local. In `M.init`:
```lua
_is_enabled = deps.is_enabled
```

In `register_hooks`, each hook callback should early-return (calling the original function) if disabled. The hooks use `hook_safe` / `hook` — for `hook` callbacks, call `func(...)` then return if disabled. For `hook_safe`, just return.

- [ ] **Step 3: Add `is_enabled` to Poxburster**

In `poxburster.lua`, add `local _is_enabled` module-local. In `M.init`:
```lua
_is_enabled = deps.is_enabled
```

In the `_update_target_enemy` hook_safe callback, add early return after `perf_t0`:
```lua
if _is_enabled and not _is_enabled() then
    if perf_t0 then _perf.finish("poxburster.update_target_enemy", perf_t0) end
    return
end
```

Note: The breed patch (`not_bot_target` removal) stays always-on. The gate only controls the suppression logic.

- [ ] **Step 4: Add pinging gate in BetterBots.lua update tick**

In `BetterBots.lua`, wrap the `PingSystem.update()` call:
```lua
if Settings.is_feature_enabled("pinging") then
    perf_t0 = Perf.begin()
    PingSystem.update(unit, blackboard)
    Perf.finish("ping_system", perf_t0)
end
```

- [ ] **Step 5: Update init blocks in BetterBots.lua to pass `is_enabled` functions**

```lua
Sprint.init({
    ...existing deps...,
    is_enabled = function() return Settings.is_feature_enabled("sprint") end,
})

TargetSelection.init({
    ...existing deps...,
    is_enabled = function() return Settings.is_feature_enabled("special_penalty") end,
})

Poxburster.init({
    ...existing deps...,
    is_enabled = function() return Settings.is_feature_enabled("poxburster") end,
})
```

- [ ] **Step 6: Update Heuristics.init to pass `resolve_preset`**

```lua
Heuristics.init({
    ...existing deps...,
    resolve_preset = Settings.resolve_preset,
})
```

- [ ] **Step 7: Update `condition_patch.lua` to pass `ability_extension` to `is_combat_template_enabled`**

In `condition_patch.lua`, at line 116, change:
```lua
if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name) then
```
to:
```lua
if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
```

The `ability_extension` variable is currently resolved at line 179 (`ScriptUnit.extension(unit, "ability_system")`), which is AFTER this gate check. Move that resolution to just after `ability_template_name` is known (after line 101). The veteran dual-category gate needs it.

- [ ] **Step 8: Update `ability_queue.lua` to pass `ability_extension` to `is_combat_template_enabled`**

In `ability_queue.lua`, at line 73:
```lua
if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name) then
```
change to:
```lua
local ability_extension_for_gate = ScriptUnit.has_extension(unit, "ability_system")
if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension_for_gate) then
```

Note: `ability_queue.lua` resolves `ability_extension` later at line 180 via `ScriptUnit.extension` (not `has_extension`). Use `has_extension` here for the gate check to avoid crashing if the extension is missing. The later call at line 180 uses the throwing variant because by that point we know the ability is valid.

- [ ] **Step 9: Add wiring tests for veteran dual-category gate in condition_patch and ability_queue**

These tests verify the two call sites actually pass `ability_extension` through for the veteran gate. Add to `tests/settings_spec.lua` or a new `tests/gate_wiring_spec.lua`:

```lua
describe("veteran dual-category gate wiring", function()
    describe("condition_patch", function()
        it("passes ability_extension to is_combat_template_enabled for veteran_combat_ability", function()
            -- Setup: mock is_combat_template_enabled that captures its args
            local captured_args = {}
            local mock_gate = function(template_name, ability_ext)
                captured_args.template_name = template_name
                captured_args.ability_extension = ability_ext
                return true
            end

            -- Wire condition_patch with the capturing gate
            ConditionPatch.wire({ is_combat_template_enabled = mock_gate })

            -- Trigger the code path with veteran_combat_ability
            -- (uses the test harness pattern from condition_patch_spec.lua)
            local ext = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability")
            -- Exercise the _can_activate_ability path with veteran template
            -- ... (adapter depends on condition_patch_spec test harness)

            assert.equals("veteran_combat_ability", captured_args.template_name)
            assert.is_not_nil(captured_args.ability_extension)
        end)
    end)

    describe("ability_queue", function()
        it("passes ability_extension to is_combat_template_enabled for veteran_combat_ability", function()
            -- Same pattern: mock gate that captures args, trigger ability_queue code path
            local captured_args = {}
            local mock_gate = function(template_name, ability_ext)
                captured_args.template_name = template_name
                captured_args.ability_extension = ability_ext
                return true
            end

            AbilityQueue.wire({ is_combat_template_enabled = mock_gate })
            -- Exercise the queue path with veteran template
            -- ... (adapter depends on ability_queue test harness)

            assert.equals("veteran_combat_ability", captured_args.template_name)
            assert.is_not_nil(captured_args.ability_extension)
        end)
    end)
end)
```

Note: The exact test setup depends on how `condition_patch_spec.lua` and the ability_queue tests exercise their code paths. The implementer should adapt this skeleton to match the existing test harness patterns. The key assertion is that `ability_extension` is non-nil when `veteran_combat_ability` is the template.

- [ ] **Step 10: Run tests, commit**

Run: `make test`
Expected: All PASS.

```bash
git add scripts/mods/BetterBots/sprint.lua scripts/mods/BetterBots/target_selection.lua \
  scripts/mods/BetterBots/poxburster.lua scripts/mods/BetterBots/BetterBots.lua \
  scripts/mods/BetterBots/condition_patch.lua scripts/mods/BetterBots/ability_queue.lua \
  tests/settings_spec.lua
git commit -m "feat(gates): wire feature gates into sprint, pinging, target selection, poxburster (#6)

Each module receives is_enabled via init(deps). Runtime gate check
inside hook callbacks — early return when disabled. Poxburster breed
patch stays always-on; gate controls suppression only. PingSystem
gate checked in BetterBots.lua before calling update().
condition_patch and ability_queue pass ability_extension for veteran
dual-category gate. Wiring tests verify ability_extension propagation."
```

---

### Task 6: Widget definitions + localization
**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua` (full rewrite)
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua` (extend)

- [ ] **Step 1: Rewrite `BetterBots_data.lua` with 3 DMF groups**

```lua
local mod = get_mod("BetterBots")

return {
    name = "Better Bots",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            -- Group: Abilities
            {
                setting_id = "abilities_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "enable_stances", type = "checkbox", default_value = true },
                    { setting_id = "enable_charges", type = "checkbox", default_value = true },
                    { setting_id = "enable_shouts", type = "checkbox", default_value = true },
                    { setting_id = "enable_stealth", type = "checkbox", default_value = true },
                    { setting_id = "enable_deployables", type = "checkbox", default_value = true },
                    { setting_id = "enable_grenades", type = "checkbox", default_value = true },
                },
            },
            -- Group: Bot Behavior
            {
                setting_id = "bot_behavior_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "behavior_profile",
                        type = "dropdown",
                        default_value = "balanced",
                        options = {
                            { text = "behavior_profile_testing", value = "testing" },
                            { text = "behavior_profile_aggressive", value = "aggressive" },
                            { text = "behavior_profile_balanced", value = "balanced" },
                            { text = "behavior_profile_conservative", value = "conservative" },
                        },
                    },
                    { setting_id = "enable_sprint", type = "checkbox", default_value = true },
                    { setting_id = "enable_pinging", type = "checkbox", default_value = true },
                    { setting_id = "enable_special_penalty", type = "checkbox", default_value = true },
                    { setting_id = "enable_poxburster", type = "checkbox", default_value = true },
                    {
                        setting_id = "healing_deferral_mode",
                        type = "dropdown",
                        default_value = "stations_and_deployables",
                        options = {
                            { text = "healing_deferral_mode_off", value = "off" },
                            { text = "healing_deferral_mode_stations_only", value = "stations_only",
                              show_widgets = { 1, 2 } },
                            { text = "healing_deferral_mode_stations_and_deployables",
                              value = "stations_and_deployables", show_widgets = { 1, 2 } },
                        },
                        sub_widgets = {
                            {
                                setting_id = "healing_deferral_human_threshold",
                                type = "dropdown",
                                default_value = "90",
                                options = {
                                    { text = "healing_deferral_threshold_50", value = "50" },
                                    { text = "healing_deferral_threshold_75", value = "75" },
                                    { text = "healing_deferral_threshold_90", value = "90" },
                                    { text = "healing_deferral_threshold_100", value = "100" },
                                },
                            },
                            {
                                setting_id = "healing_deferral_emergency_threshold",
                                type = "dropdown",
                                default_value = "25",
                                options = {
                                    { text = "healing_deferral_emergency_never", value = "never" },
                                    { text = "healing_deferral_threshold_10", value = "10" },
                                    { text = "healing_deferral_threshold_25", value = "25" },
                                    { text = "healing_deferral_threshold_40", value = "40" },
                                },
                            },
                        },
                    },
                },
            },
            -- Group: Diagnostics
            {
                setting_id = "diagnostics_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_debug_logs",
                        type = "dropdown",
                        default_value = "off",
                        options = {
                            { text = "debug_log_level_off", value = "off" },
                            { text = "debug_log_level_info", value = "info" },
                            { text = "debug_log_level_debug", value = "debug" },
                            { text = "debug_log_level_trace", value = "trace" },
                        },
                    },
                    { setting_id = "enable_event_log", type = "checkbox", default_value = false },
                    { setting_id = "enable_perf_timing", type = "checkbox", default_value = false },
                },
            },
        },
    },
}
```

- [ ] **Step 2: Update `BetterBots_localization.lua`**

Add all new localization entries per the spec's Settings Label Guidelines table. Keep all existing healing deferral and debug entries. Replace the tier-based entries with category entries:

```lua
-- Replace these:
--   enable_tier_1_abilities, enable_tier_2_abilities, enable_tier_3_abilities
-- With:
abilities_group = { en = "Abilities" },
enable_stances = { en = "Stance abilities" },
enable_stances_description = { en = "Self-buff abilities (Veteran Focus, Psyker Overcharge, Ogryn Gunlugger, Arbites Stance)" },
enable_charges = { en = "Charge & dash abilities" },
enable_charges_description = { en = "Gap-closing abilities (Zealot Dash, Ogryn Charge, Arbites Charge)" },
enable_shouts = { en = "Shout abilities" },
enable_shouts_description = { en = "Area-of-effect abilities (Psyker Shriek, Ogryn Taunt, Arbites Shout)" },
enable_stealth = { en = "Stealth abilities" },
enable_stealth_description = { en = "Invisibility and stealth abilities (Veteran Stealth, Zealot Invisibility)" },
enable_deployables = { en = "Deployable abilities" },
enable_deployables_description = { en = "Placed items (Zealot Relic, Psyker Force Field, Arbites Drone)" },
enable_grenades = { en = "Grenades & blitz" },  -- replaces enable_grenade_blitz_abilities
enable_grenades_description = { en = "All throwable and blitz abilities" },

-- New: Bot Behavior group
bot_behavior_group = { en = "Bot Behavior" },
enable_sprint = { en = "Bot sprinting" },
enable_sprint_description = { en = "Bots sprint to catch up, during traversal, and for ally rescue" },
enable_pinging = { en = "Elite & special pinging" },
enable_pinging_description = { en = "Bots ping elites and specials they detect" },
enable_special_penalty = { en = "Prioritize shooting distant specials" },
enable_special_penalty_description = { en = "Bots prefer ranged attacks against distant specials instead of charging into melee" },
enable_poxburster = { en = "Poxburster safe targeting" },
enable_poxburster_description = { en = "Bots suppress fire on poxbursters within detonation range of bots or humans. Disabling removes this safety check." },

-- Update behavior_profile entries
behavior_profile = { en = "Behavior preset" },
behavior_profile_description = { en = "How aggressively bots use abilities" },
-- behavior_profile_standard removed
behavior_profile_testing = { en = "Testing - very lenient for development/validation" },
behavior_profile_aggressive = { en = "Aggressive - liberal ability use, suited for lower difficulties" },
behavior_profile_balanced = { en = "Balanced - tuned for challenging content (default)" },
behavior_profile_conservative = { en = "Conservative - emergency-only, suited for Auric/Maelstrom" },

-- New: Diagnostics group
diagnostics_group = { en = "Diagnostics" },
```

- [ ] **Step 3: Run `make check`**

Run: `make check`
Expected: format + lint + lsp + test all pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots_data.lua scripts/mods/BetterBots/BetterBots_localization.lua
git commit -m "feat(ui): 3-group settings layout with healing deferral show_widgets (#6)

Abilities (6 category checkboxes), Bot Behavior (preset dropdown +
4 feature toggles + healing deferral with conditional sub-widgets),
Diagnostics (log level, event log, perf timing). All new localization
strings with outcome-oriented labels and tooltips."
```

---

### Task 7: Doc updates
**Files:**
- Modify: `AGENTS.md` (which `CLAUDE.md` symlinks to)
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/nexus-description.bbcode`

- [ ] **Step 1: Update `AGENTS.md`**

In the "Mod file structure" section, update `settings.lua` description:
```
settings.lua                              # Category gates, feature gates, preset resolver, dual-category veteran gate
```

In the "Architecture" section tier table, add a note about category gates replacing tier gates.

- [ ] **Step 2: Update `docs/dev/architecture.md`**

Add a section documenting the preset system, feature gate mechanism, `on_setting_changed` usage, and the DI pattern for gate injection.

- [ ] **Step 3: Update `docs/dev/status.md` and `docs/dev/roadmap.md`**

Mark #6 as complete.

- [ ] **Step 4: Update `docs/nexus-description.bbcode`**

Update the features list to mention configurable ability categories, behavior presets, and feature toggles.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/dev/architecture.md docs/dev/status.md docs/dev/roadmap.md docs/nexus-description.bbcode
git commit -m "docs: update architecture, status, roadmap, nexus for #6 settings presets"
```

---

### Task 8: Quality gate + final verification
- [ ] **Step 1: Run full quality gate**

Run: `make check`
Expected: format + lint + lsp + test all PASS.

- [ ] **Step 2: Verify test count**

Run: `make test 2>&1 | tail -5`
Expected: 418 + new preset/category/feature tests = ~440+ tests, 0 failures.

- [ ] **Step 3: Verify `doc-check` passes**

Run: `make doc-check`
Expected: PASS (heuristic function counts may need updating if any functions were added/removed).

- [ ] **Step 4: Review diff**

Run: `git diff main --stat`
Verify all changed files are expected and nothing was accidentally modified.

---

## Open Items for In-Game Testing

After implementation, one in-game session is needed:
1. Launch with `balanced` preset — verify identical behavior to v0.7.0
2. Switch to `aggressive` — verify abilities trigger more readily on lower difficulty
3. Switch to `conservative` — verify abilities trigger less on Damnation+
4. Toggle each feature gate off/on via DMF settings and verify the module stops/starts
5. Toggle ability categories off/on and verify the correct abilities are blocked
6. Verify healing deferral sub-widgets show/hide when mode changes
