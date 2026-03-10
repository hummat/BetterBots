# Default Bot Profiles Design

> Date: 2026-03-10
> Status: Approved
> Issue: #44 (pending creation)
> Related: #28 (Tertium consolidation — shares hook point, complementary feature)

## Problem

Players without leveled characters across all classes can't benefit from BetterBots' ability support. Vanilla bots are always Veterans with combat swords and lasguns — no class diversity, no interesting abilities. The only way to get non-Veteran bots is Tertium4Or5/Tertium6, which requires the player to have leveled characters of each class.

## Solution

Ship hardcoded default profiles for each class (Veteran, Zealot, Psyker, Ogryn) with player weapon templates and correct archetypes. Players configure per-slot dropdowns in mod settings to select which class each bot slot uses.

## Approach

Single new module `bot_profiles.lua` with profile tables + spawning hook + DMF settings.

### Profile tables

One profile per class (core 4 initially). Each profile contains:

- `archetype` — class name (zealot/psyker/ogryn/veteran)
- `gender`, `selected_voice` — cosmetic
- `loadout.slot_primary` — melee weapon (player weapon template ID)
- `loadout.slot_secondary` — ranged weapon (player weapon template ID)
- `loadout.slot_gear_*` — basic cosmetic slots
- `bot_gestalts` — `{ melee = "linesman", ranged = "killshot" }`
- `talents` — `{}` (hard constraint — game doesn't load talent trees for bots)

Weapon choices TBD during implementation — selected from `docs/classes/meta-builds-research.md` based on bot compatibility (avoid weapons requiring weakspot aim, dodge-stacking, peril management, or block timing).

### Spawning hook

Hook `BotSynchronizerHost.add_bot` to intercept profile assignment. Read the mod setting for the bot's slot number, and if a default profile is selected, replace the vanilla veteran profile with the corresponding class profile.

Slot mapping: track a spawn counter incremented per `add_bot` call, mapping nth bot to slot n's setting. Reset counter on `GameplayStateRun` enter.

### Settings UI

Three DMF dropdown widgets in `BetterBots_data.lua`:

```
Bot Slot 1: [None | Default Veteran | Default Zealot | Default Psyker | Default Ogryn]
Bot Slot 2: [None | Default Veteran | Default Zealot | Default Psyker | Default Ogryn]
Bot Slot 3: [None | Default Veteran | Default Zealot | Default Psyker | Default Ogryn]
```

`None` = vanilla behavior (default). Arbites/Hive Scum omitted initially — Arbites can be added once tested, Hive Scum blocked on #8/DLC.

### File changes

| File | Change |
|------|--------|
| `bot_profiles.lua` | **New.** Profile tables, `add_bot` hook, slot counter |
| `BetterBots.lua` | `io_dofile`, `init()`, `register_hooks()`. Reset slot counter in `on_game_state_changed`. |
| `BetterBots_data.lua` | 3 dropdown widgets |
| `BetterBots_localization.lua` | Localization for settings + options |

Estimated ~150-200 LOC new code. No changes to existing ability/metadata/heuristics code.

### Compatibility

- **With Tertium4Or5/Tertium6**: Both mods hook the same `add_bot` path. When both are active, hook execution order determines which profile wins. Document that users should use one or the other for a given slot, not both.
- **With #28**: When #28 lands, it extends the dropdown options with `Player Character 1..N` and adds a backend fetch path. Same hook, same settings UI, different profile source.

### Risks

- **Item data format**: `MasterItems.get_item_or_fallback()` may expect more than a template name string. Tertium proves this path works with player weapon templates, but the exact format needs verification during implementation.
- **Cosmetic slots**: Minimal cosmetics may look odd. Can be refined later or combined with fancy_bots.

### Downstream support already in place

BetterBots already handles everything non-Veteran bots need:
- `meta_data.lua`: ability metadata injection for all 6 classes
- `ranged_meta_data.lua`: attack metadata for player weapon templates
- `melee_meta_data.lua`: melee metadata for player weapon templates
- `condition_patch.lua`: activation conditions for all ability types
- `item_fallback.lua`: Tier 3 item ability sequences (relic, force field, drone, stimm field)
- `heuristics.lua`: per-ability activation rules
- `BetterBots.lua:507-528`: gestalt injection fallback for profiles missing `bot_gestalts`
