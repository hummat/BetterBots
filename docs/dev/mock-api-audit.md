# Mock API Audit

This file tracks the engine API surface that BetterBots tests are allowed to mock.

Scope:

- `ScriptUnit.has_extension()` / `ScriptUnit.extension()` doubles
- manager-system doubles returned from `Managers.state.extension:system(...)`
- private engine fields only where BetterBots production code reads those exact fields

Source of truth:

- decompiled source in `../Darktide-Source-Code/`
- in-game dumps only if decompiled source is ambiguous

Current status:

- Current test surface audited against decompiled source
- No current mock requires an in-game dump to disambiguate behavior

## Audited extension surfaces

| Surface | Real class/system | BetterBots-tested API | Decompiled proof | Notes |
|---|---|---|---|---|
| `unit_data_system` (player) | `PlayerUnitDataExtension` | `read_component()` | `scripts/extension_systems/unit_data/player_unit_data_extension.lua:547` | Player path only |
| `unit_data_system` (minion) | `MinionUnitDataExtension` | `breed()`, `faction_name()`, `is_companion()`, `breed_name()`, `breed_size_variation()` | `scripts/extension_systems/unit_data/minion_unit_data_extension.lua:110`, `:114`, `:118`, `:124`, `:167` | Minions do **not** expose `read_component()` |
| `locomotion_system` (player) | `PlayerUnitLocomotionExtension` | `current_velocity()` | `scripts/extension_systems/locomotion/player_unit_locomotion_extension.lua:1187` | |
| `locomotion_system` (minion) | `MinionLocomotionExtension` | `current_velocity()` | `scripts/extension_systems/locomotion/minion_locomotion_extension.lua:134` | |
| `ability_system` | `PlayerUnitAbilityExtension` | `can_use_ability()`, `action_input_is_currently_valid()`, `remaining_ability_charges()`, `_equipped_abilities` | `scripts/extension_systems/ability/player_unit_ability_extension.lua:613`, `:655`, `:750`, `_equipped_abilities` initialized at `:62` | `_equipped_abilities` is private but BetterBots reads it directly |
| `action_input_system` | `PlayerUnitActionInputExtension` | `bot_queue_action_input()`, `_action_input_parsers` | `scripts/extension_systems/action_input/player_unit_action_input_extension.lua:204`, `_action_input_parsers` initialized at `:9` | `_action_input_parsers` is private but BetterBots reads it directly |
| `input_system` | `PlayerUnitInputExtension` | `bot_unit_input()` | `scripts/extension_systems/input/player_unit_input_extension.lua:46` | Used by grenade fallback aim control |
| `perception_system` (bot) | `BotPerceptionExtension` | `enemies_in_proximity()` | `scripts/extension_systems/perception/bot_perception_extension.lua:94` | |
| `perception_system` (minion) | `MinionPerceptionExtension` | `has_line_of_sight()` | `scripts/extension_systems/perception/minion_perception_extension.lua:181` | |
| `smart_tag_system` via `ScriptUnit.has_extension(unit, ...)` | `SmartTagExtension` | `tag_id()` | `scripts/extension_systems/smart_tag/smart_tag_extension.lua:262` | Same system name, different object than manager lookup |
| `smart_tag_system` via `Managers.state.extension:system(...)` | `SmartTagSystem` | `set_tag()`, `set_contextual_unit_tag()`, `unit_tag()` | `scripts/extension_systems/smart_tag/smart_tag_system.lua:152`, `:202`, `:318` | `unit_tag()` returns `SmartTag` objects |
| `smart_tag` object returned by `SmartTagSystem:unit_tag()` | `SmartTag` | `template()`, `tagger_player()` | `scripts/extension_systems/smart_tag/smart_tag.lua:46`, `:84` | Used by target-selection tests |
| `companion_spawner_system` | `CompanionSpawnerExtension` | `companion_units()`, `should_have_companion()` | `scripts/extension_systems/companion_spawner/companion_spawner_extension.lua:292`, `:316` | No `companion_unit()` method exists |
| `coherency_system` | `UnitCoherencyExtension` | `current_radius()` | `scripts/extension_systems/coherency/unit_coherency_extension.lua:148` | |
| `talent_system` | `PlayerUnitTalentExtension` / `PlayerHuskTalentExtension` | `has_special_rule()` | `scripts/extension_systems/talent/player_unit_talent_extension.lua:94`, `scripts/extension_systems/talent/player_husk_talent_extension.lua:99` | |
| `behavior_system` | `BotBehaviorExtension` + `AiBrain` | `_brain`, `_brain._blackboard` | `scripts/extension_systems/behavior/bot_behavior_extension.lua:83`, `:1048`; `scripts/extension_systems/behavior/ai_brain.lua:8` | Private fields, but production sprint code reads them directly |

## Audited manager-system doubles

| Surface | Real class/system | BetterBots-tested API | Decompiled proof | Notes |
|---|---|---|---|---|
| `side_system` | `SideSystem` + `Side` | `side_by_unit`, `get_side_from_name()`, `relation_side_names()` | `scripts/extension_systems/side/side_system.lua:21`, `:142`; `scripts/extension_systems/side/side.lua:273` | Sprint + heuristics tests |
| `liquid_area_system` | `LiquidAreaSystem` | `find_liquid_areas_in_position()`, `is_position_in_liquid()` | `scripts/extension_systems/liquid_area/liquid_area_system.lua:176`, `:162` | Hazard detection tests |

## Rules

- Add new shared builders to `tests/test_helper.lua` before spreading a new extension family across specs.
- If production code reads a private engine field, the audit must record the exact file and line where that field exists.
- If decompiled source does not prove a method/field exists, do not mock it. Get an in-game dump first.
- `scripts/doc-check.sh` hard-fails on ad-hoc raw table literals for the audited `ScriptUnit` extension families above. Extend that check when a new audited family is added.
