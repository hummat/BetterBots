# Default Bot Profiles Design

> Date: 2026-03-10
> Status: Shipped (v0.8.0, 2026-03-15)
> Issue: #45
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

### Compatibility (resolved)

- **With Tertium4Or5/Tertium6**: Complementary, not conflicting. BetterBots yields when `profile.archetype` is non-veteran (Tertium already assigned a real player character). BetterBots fills gaps for slots Tertium doesn't cover. Hook order doesn't matter.
- **With #28**: When #28 lands, it extends the dropdown options with `Player Character 1..N` and adds a backend fetch path. Same hook, same settings UI, different profile source.

### Implementation notes (discovered during development)

- **Item resolution required**: loadout slots in `add_bot` contain resolved item objects, not template ID strings. `bot_character_profiles.lua` resolves items at require-time before profiles reach `add_bot`. Our templates must go through the same `MasterItems.get_item_or_fallback()` + `LocalProfileBackendParser.parse_profile()` pipeline.
- **Archetype must be a resolved table**: `package_synchronizer_client` reads `profile.archetype.name` (table field). Resolve via `Archetypes[archetype_string]`. `parse_profile` reads archetype as a string — save/restore around the call.
- **In-place mutation, not replacement**: the vanilla profile carries cosmetic slots, body data, and visual_loadout. Deep-copying breaks item objects (they're MasterItems cache references). Mutate gameplay fields only.
- **visual_loadout must be updated**: `package_synchronizer_client` iterates it for package resolution. Mirror weapon/cosmetic changes.
- **Ogryn needs different body meshes**: uses `content/items/characters/player/ogryn/...`. All non-veteran classes get full cosmetic overrides from Darktide Seven / tutorial bot profiles.
- **Talents are NOT a hard constraint**: `talents = {}` is a vanilla design choice, not an engine limitation. Tertium's backend profiles include talents and the engine processes them. Future: populate from hadrons-blessing builds.
- **Curios are a no-op**: `slot_trinket_1` has `ignore_character_spawning = true` — not processed during bot spawn.

### Downstream support already in place

BetterBots already handles everything non-Veteran bots need:
- `meta_data.lua`: ability metadata injection for all 6 classes
- `ranged_meta_data.lua`: attack metadata for player weapon templates
- `melee_meta_data.lua`: melee metadata for player weapon templates
- `condition_patch.lua`: activation conditions for all ability types
- `item_fallback.lua`: Tier 3 item ability sequences (relic, force field, drone, stimm field)
- `heuristics.lua`: per-ability activation rules
- `BetterBots.lua:507-528`: gestalt injection fallback for profiles missing `bot_gestalts`
