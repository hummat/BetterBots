# Design: Behavior Presets + Configurable Mod Settings (#6)

## Summary

Expand BetterBots settings from 11 flat widgets to a structured 3-group layout with:
- Player-facing ability category gates (replacing developer-facing tier grouping)
- Feature toggles for optional bot behavior systems
- Full behavior preset system (aggressive/balanced/conservative) with per-heuristic threshold tables

Closes GitHub issue #6.

## Scope

### In scope

1. **Settings UI reorganization** — 3 DMF groups: Abilities, Bot Behavior, Diagnostics
2. **Ability category gates** — 6 player-facing categories replacing 4 tier-based toggles
3. **Feature gates** — on/off toggles for 4 optional bot behavior modules
4. **Behavior preset system** — 4 named presets with hybrid threshold + override implementation
5. **Template-to-category mapping** — new mapping tables in `settings.lua`
6. **Localization** — display strings for all new/changed settings
7. **Tests** — settings resolution, category mapping, preset threshold application
8. **Doc updates** — CLAUDE.md, architecture, roadmap, status, nexus description

### Out of scope

- Per-ability or per-template individual toggles (UI would be too large)
- Preset auto-selection based on difficulty
- The 9-argument heuristic dispatch signature cleanup (separate refactor; only done if the preset `(context, thresholds)` calling convention naturally eliminates it)
- `has_extension` guards in ability_queue/condition_patch (flagged in audit, separate fix)
- Grenade fallback event logging (flagged in audit, separate fix)

## Settings UI Structure

Three DMF `group` widgets with `sub_widgets`:

### Group: Abilities

6 checkboxes, all default `true`. Gate which categories of abilities bots can use.

| Setting ID | Label | Default | Templates |
|---|---|---|---|
| `enable_stances` | Stance abilities | `true` | `veteran_combat_ability`¹, `veteran_stealth_combat_ability`, `psyker_overcharge_stance`, `ogryn_gunlugger_stance`, `adamant_stance`, `broker_focus`, `broker_punk_rage` |
| `enable_charges` | Charge & dash abilities | `true` | `zealot_dash`, `zealot_targeted_dash`, `zealot_targeted_dash_improved`, `zealot_targeted_dash_improved_double`, `ogryn_charge`, `ogryn_charge_increased_distance`, `adamant_charge` |
| `enable_shouts` | Shout abilities | `true` | `psyker_shout`, `ogryn_taunt_shout`, `adamant_shout` |
| `enable_stealth` | Stealth abilities | `true` | `zealot_invisibility` |
| `enable_deployables` | Deployable abilities | `true` | `zealot_relic`, `psyker_force_field`, `psyker_force_field_improved`, `psyker_force_field_dome`, `adamant_area_buff_drone`, `broker_ability_stimm_field` |
| `enable_grenades` | Grenades & blitz | `true` | All `GRENADE_HEURISTICS` keys |

¹ `veteran_combat_ability` covers both Veteran Voice of Command (shout) and Veteran Stance/Focus (stance). It maps to stances because the template is shared and the stance variant is more common. Veteran VoC is resolved dynamically at heuristic evaluation time via `_resolve_veteran_class_tag`, not at the settings gate level.

**Note on `veteran_stealth_combat_ability` vs `zealot_invisibility`:** Both are "stealth" abilities from a player perspective, but `veteran_stealth_combat_ability` is Tier 1 (whitelist removal only) while `zealot_invisibility` is Tier 2 (meta_data injection). They end up in different categories because Veteran Stealth is a stance-like ability (self-buff, no movement) while Zealot Invisibility is a defensive escape. If this creates user confusion, both can be moved to the same category — the gate is purely a settings lookup, not tied to implementation tier.

### Group: Bot Behavior

Preset dropdown + 4 feature checkboxes + healing deferral cluster.

| Setting ID | Type | Label | Default | Notes |
|---|---|---|---|---|
| `behavior_preset` | dropdown | Behavior preset | `balanced` | Options: testing, aggressive, balanced, conservative |
| `enable_sprint` | checkbox | Bot sprinting | `true` | Gates `Sprint.register_hook()` |
| `enable_pinging` | checkbox | Elite & special pinging | `true` | Gates `PingSystem` update calls |
| `enable_special_penalty` | checkbox | Prioritize shooting distant specials | `true` | Gates `TargetSelection.register_hooks()` |
| `enable_poxburster` | checkbox | Poxburster safe targeting | `true` | Gates `Poxburster.register_hooks()` |
| `healing_deferral_mode` | dropdown | Healing deferral | `stations_and_deployables` | Options: off, stations_only, stations_and_deployables. Acts as master gate. |
| `healing_deferral_human_threshold` | dropdown | Defer when any player below | `90` | `show_widgets`: visible when mode ≠ off |
| `healing_deferral_emergency_threshold` | dropdown | Bot emergency override below | `25` | `show_widgets`: visible when mode ≠ off |

### Group: Diagnostics

| Setting ID | Type | Label | Default |
|---|---|---|---|
| `enable_debug_logs` | dropdown | Debug log level | `off` |
| `enable_event_log` | checkbox | Event log (JSONL) | `false` |
| `enable_perf_timing` | checkbox | Runtime timing (/bb_perf) | `false` |

### Always-on modules (no gate)

These are improvements/bugfixes that all users benefit from:
- `vfx_suppression.lua` — VFX/SFX bleed fix
- `melee_meta_data.lua` — melee classification improvement
- `ranged_meta_data.lua` — ranged input derivation fix
- `weapon_action.lua` — overheat bridge, vent, peril guard, ADS fix

## Feature Gate Architecture

### Gate mechanism: `on_setting_changed` + runtime check

Feature gates use **runtime checks** inside hook callbacks, not registration-time gating. This ensures settings take effect immediately when changed through the DMF options panel, without requiring hot-reload.

Each gated module reads its setting via `Settings.is_feature_enabled(feature_name)`, which calls `mod:get()` (a table lookup — negligible cost).

DMF fires `on_setting_changed(setting_id)` when settings change through the options UI. BetterBots uses this callback to refresh any cached state (e.g., debug log level, which is already refreshed this way).

```lua
-- settings.lua
local FEATURE_GATES = {
    sprint          = "enable_sprint",
    pinging         = "enable_pinging",
    special_penalty = "enable_special_penalty",
    poxburster      = "enable_poxburster",
}

function M.is_feature_enabled(feature_name)
    local setting_id = FEATURE_GATES[feature_name]
    if not setting_id then return true end
    return _setting_enabled(setting_id)
end
```

### Where gates are checked

| Module | Gate location | Notes |
|---|---|---|
| Sprint | Inside `on_update_movement` hook callback | Early return if disabled |
| PingSystem | Inside `PingSystem.update()` call in BetterBots.lua update tick | Early return if disabled |
| TargetSelection | Inside hook callbacks registered by `TargetSelection.register_hooks()` | Hooks call original function and return if disabled |
| Poxburster | Inside hook callbacks registered by `Poxburster.register_hooks()` | Hooks call original function and return if disabled |
| Healing deferral | Already runtime-gated via `_resolve_settings().mode` | Mode "off" = no deferral. No change needed. |

### Ability category gates

`settings.lua` replaces `TIER_1_COMBAT_TEMPLATES` / `TIER_2_COMBAT_TEMPLATES` / `TIER_3_ITEM_ABILITIES` with category-based mapping tables:

```lua
local CATEGORY_STANCES = {
    veteran_combat_ability = true,
    veteran_stealth_combat_ability = true,
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
    zealot_invisibility = true,
}

local TEMPLATE_TO_CATEGORY_SETTING = {}
-- Populated at module load from the above tables
```

A single `TEMPLATE_TO_CATEGORY_SETTING` reverse lookup maps any template name to its setting ID. `is_combat_template_enabled` does one table lookup + one `mod:get()`. Same API surface as today — callers don't change.

Item abilities map to `enable_deployables`. Grenade abilities map to `enable_grenades`. Both use the same pattern.

## Behavior Preset System

### Four presets, two implementation strategies

| Preset | Strategy | Use case |
|---|---|---|
| **Testing** | Override layer (existing `_apply_behavior_profile`) | Dev/validation — overrides `_hold`/`_block_safe`/`_block_low_value` rules when combat triggers present |
| **Aggressive** | Threshold-driven — relaxed preset-sensitive values | Sedition–Heresy difficulty |
| **Balanced** | Hardcoded baseline — no lookup needed | Damnation (default) |
| **Conservative** | Threshold-driven — tightened preset-sensitive values | Auric+ / Maelstrom |

### Hybrid threshold + override pattern

**Principle:** `balanced` is the readable baseline hardcoded in each heuristic function. `aggressive` and `conservative` override only the thresholds where behavior genuinely differs. Hard safety blocks and boolean guards stay hardcoded in all presets.

**What gets extracted into per-heuristic threshold tables:**
- `num_nearby` activation minimums
- `toughness_pct` / `health_pct` activation thresholds
- `challenge_rating_sum` minimums
- Distance thresholds for gap-closers (charges/dashes)

**What stays hardcoded (identical across all presets):**
- Safety blocks: `block_target_too_close`, `block_super_armor`, `block_no_target`, `block_no_enemies`
- Peril window boundaries (psyker abilities)
- Ally-needs-aid triggers (situational, not preference)
- `block_too_fragile` (Ogryn taunt — absolute safety floor)

### Per-heuristic threshold table pattern

Each heuristic function that has preset-sensitive thresholds gets a small config table co-located directly above it in `heuristics.lua`:

```lua
local VETERAN_STEALTH_THRESHOLDS = {
    aggressive   = { critical_toughness = 0.35, low_health = 0.50,
                     overwhelmed_nearby = 4, overwhelmed_toughness = 0.60 },
    balanced     = { critical_toughness = 0.25, low_health = 0.40,
                     overwhelmed_nearby = 5, overwhelmed_toughness = 0.50 },
    conservative = { critical_toughness = 0.15, low_health = 0.30,
                     overwhelmed_nearby = 6, overwhelmed_toughness = 0.40 },
}

local function _can_activate_veteran_stealth(context, thresholds)
    -- Hard blocks: always hardcoded
    if context.num_nearby == 0 then
        return false, "veteran_stealth_block_no_enemies"
    end
    -- Preset-sensitive thresholds
    if context.toughness_pct < thresholds.critical_toughness
       and context.num_nearby >= 2 then
        return true, "veteran_stealth_critical_toughness"
    end
    if context.health_pct < thresholds.low_health
       and context.num_nearby >= 1 then
        return true, "veteran_stealth_low_health"
    end
    -- Ally aid: hardcoded (situational, not preference)
    if context.target_ally_needs_aid
       and (context.target_ally_distance or math.huge) <= 20
       and context.num_nearby >= 2 then
        return true, "veteran_stealth_ally_aid"
    end
    if context.num_nearby >= thresholds.overwhelmed_nearby
       and context.toughness_pct < thresholds.overwhelmed_toughness then
        return true, "veteran_stealth_overwhelmed"
    end
    return false, "veteran_stealth_hold"
end
```

### Which heuristics get threshold tables

Not every heuristic needs one. Functions with purely boolean logic (e.g., "has priority target? fire.") or functions where aggressive/balanced/conservative would produce identical output get no table.

**Gets threshold table (behavior genuinely differs):**
- `_can_activate_veteran_combat_ability` (VoC and stance branches)
- `_can_activate_veteran_stealth`
- `_can_activate_zealot_dash`
- `_can_activate_zealot_invisibility`
- `_can_activate_psyker_shout`
- `_can_activate_psyker_stance`
- `_can_activate_ogryn_charge`
- `_can_activate_ogryn_taunt`
- `_can_activate_ogryn_gunlugger`
- `_can_activate_adamant_stance`
- `_can_activate_adamant_charge`
- `_can_activate_adamant_shout`
- `_can_activate_zealot_relic`
- `_can_activate_force_field`
- `_can_activate_drone`
- Grenade helpers: `_grenade_horde`, `_grenade_priority_target`, `_grenade_defensive`, `_grenade_mine`

**No threshold table (purely boolean or identical across presets):**
- `_can_activate_broker_focus` — DLC-blocked, no calibration data
- `_can_activate_broker_rage` — DLC-blocked, no calibration data
- `_can_activate_stimm_field` — DLC-blocked, no calibration data
- `_grenade_whistle` — binary priority-target check
- `_grenade_smite` — delegates to `_grenade_priority_target` (gets thresholds there)
- `_grenade_assail` — many checks are binary (has priority target, is ranged, has super armor)
- `_grenade_chain_lightning` — simple density check

DLC-blocked abilities (broker/stimm) can get threshold tables when they become testable.

### Preset plumbing

1. `settings.lua` exposes `resolve_behavior_preset()` — returns `"testing"` / `"aggressive"` / `"balanced"` / `"conservative"`
2. `heuristics.lua` init receives `resolve_preset` function reference
3. `build_context()` resolves the preset name once per unit per frame and stores it in the context: `context.preset = resolve_preset()`
4. `_evaluate_template_heuristic()` looks up the per-heuristic threshold table using `context.preset` and passes it to the heuristic function
5. For `balanced`, the threshold table contains the same values as the current hardcoded constants — zero behavior change for existing users
6. For `testing`, `_apply_behavior_profile` continues to work as an override layer *after* threshold evaluation, same as today

### Heuristic function signature change

Currently: `function(conditions, unit, blackboard, scratchpad, condition_args, action_data, is_running, ability_extension, context)`

The preset work requires passing thresholds to each function. Most functions (all except `veteran_combat_ability`) ignore the first 8 arguments. The new signature is:

**Most functions:** `function(context, thresholds)`
**`veteran_combat_ability`:** `function(context, thresholds, conditions, ability_extension)` (needs these for vanilla VoC fallback)

The `TEMPLATE_HEURISTICS` dispatch table and `_evaluate_template_heuristic` adapt the call. `evaluate_heuristic` (test entry point) already takes `(template_name, context, opts)` — it resolves thresholds internally.

This is not a separate refactor — it's a direct consequence of the `(context, thresholds)` calling convention. The 9-arg signature naturally collapses.

### Migration

- `settings.lua` recognizes `standard` and silently returns `balanced`
- `behavior_profile` setting ID renamed to `behavior_preset` for clarity
- Old `VALID_BEHAVIOR_PROFILES` replaced with `VALID_PRESETS`
- `is_testing_profile()` updated to check against `"testing"` preset (functionally identical)

## Settings Label Guidelines

User-facing labels describe outcomes, not implementation:

| Setting ID | Label | Tooltip (localization description key) |
|---|---|---|
| `enable_stances` | Stance abilities | Self-buff abilities (Veteran Focus, Psyker Overcharge, Ogryn Gunlugger, Arbites Stance) |
| `enable_charges` | Charge & dash abilities | Gap-closing abilities (Zealot Dash, Ogryn Charge, Arbites Charge) |
| `enable_shouts` | Shout abilities | Area-of-effect abilities (Psyker Shriek, Ogryn Taunt, Arbites Shout) |
| `enable_stealth` | Stealth abilities | Invisibility abilities (Zealot Invisibility) |
| `enable_deployables` | Deployable abilities | Placed items (Zealot Relic, Psyker Force Field, Arbites Drone) |
| `enable_grenades` | Grenades & blitz | All throwable and blitz abilities |
| `enable_sprint` | Bot sprinting | Bots sprint to catch up, during traversal, and for ally rescue |
| `enable_pinging` | Elite & special pinging | Bots ping elites and specials they detect |
| `enable_special_penalty` | Prioritize shooting distant specials | Bots prefer ranged attacks against distant specials instead of charging into melee |
| `enable_poxburster` | Poxburster safe targeting | Bots target and suppress poxbursters at safe range. Disabling reverts to vanilla targeting. |
| `behavior_preset` | Behavior preset | How aggressively bots use abilities |
| `behavior_preset_testing` | Testing | Very lenient — bots use abilities at every opportunity (for development/validation) |
| `behavior_preset_aggressive` | Aggressive | Liberal ability use, suited for lower difficulties |
| `behavior_preset_balanced` | Balanced | Tuned for challenging content (default) |
| `behavior_preset_conservative` | Conservative | Emergency-only ability use, suited for Auric/Maelstrom |

## Test Strategy

### New tests required

| Test file | What it covers |
|---|---|
| `settings_spec.lua` (extend) | Category mapping: every template resolves to correct category. Feature gate: `is_feature_enabled` returns correct values. Preset resolution: `resolve_behavior_preset` handles all values including `standard` migration. |
| `heuristics_spec.lua` (extend) | Each heuristic function tested with `balanced` thresholds produces identical output to current behavior. Each heuristic tested with `aggressive` and `conservative` thresholds produces expected directional changes (aggressive activates more readily, conservative less). |

### Regression strategy

- All existing 418 tests must pass with zero changes (balanced = current behavior)
- `make check` (format + lint + lsp + test) must pass
- In-game validation: one mission with `balanced` preset to verify no behavior change from v0.7.0

## Doc Updates Required

| Doc | Change |
|---|---|
| `CLAUDE.md` / `AGENTS.md` | Update mod file structure (settings.lua description), update tier table to mention category gates |
| `docs/dev/architecture.md` | Document preset system, feature gates, `on_setting_changed` usage |
| `docs/dev/status.md` | Mark #6 as complete |
| `docs/dev/roadmap.md` | Move #6 from active to completed |
| `docs/nexus-description.bbcode` | Update features list, settings description |
| `BetterBots_localization.lua` | All new localization strings |
| `BetterBots_data.lua` | Complete rewrite of widget definitions |

## Open Questions

1. **Veteran Stealth in Stances vs Stealth category:** Currently mapped to Stances (Tier 1 stance-like self-buff). Could map to Stealth alongside Zealot Invisibility if users find it confusing. Low-stakes decision — can be changed post-ship.
2. **Threshold calibration for aggressive/conservative:** Initial values are hand-tuned estimates based on the current balanced thresholds (relaxed/tightened by ~30-50%). Real calibration requires in-game testing across difficulties. Ship with best estimates, tune in patches.
3. **`_grenade_assail` threshold table:** Assail has many binary checks but also a density+challenge check (`num_nearby >= 4 and challenge_rating_sum >= 2.0`) that could benefit from preset tuning. Revisit during implementation.

## DMF Widget Reference

Verified from `mods/dmf/scripts/mods/dmf/modules/core/options.lua:456-461`:

- `group` + `sub_widgets` = collapsible section (purely visual)
- `checkbox` + `sub_widgets` = conditional reveal when enabled
- `dropdown` + `sub_widgets` + `show_widgets` = per-option conditional reveal
- Recursive nesting confirmed to 3 levels (markers_aio)
- `allowed_parent_widget_types = { header=true, group=true, checkbox=true, dropdown=true }`
