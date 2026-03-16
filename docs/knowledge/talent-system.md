# Talent System Internals

Source: decompiled `player_talents.lua`, `local_profile_backend_parser.lua`, `base_talents.lua`,
`ability_templates/`, and class-specific `*_talents.lua` files. Verified 2026-03-16.

## profile.talents format

```lua
profile.talents = { [talent_name_string] = tier_integer }
```

Flat table keyed by talent name strings, values are tier integers (typically 1).
This is the **runtime** representation consumed by `CharacterSheet.class_loadout` and talent buff resolution.

`profile.selected_nodes` (UUID-keyed) is the **UI-side** representation and is NOT needed for bots.
The conversion path is `selected_nodes` → `CharacterSheet.convert_selected_nodes_to_selected_talents` → `talents`.

## Talent name types

All talent names live in the same flat namespace. The key is a human-readable string.

### Class-specific talents

Defined in `archetype_talents/talents/{class}_talents.lua`. Examples:
- `veteran_ranged_power_out_of_melee` — passive buff (no `player_ability` field)
- `veteran_combat_ability_elite_and_special_outlines` — ability choice (has `player_ability = { ability_type = "combat_ability" }`)
- `veteran_snipers_focus` — keystone
- `zealot_crits_grant_cd` — talent modifier (keystone modifier)

### Stat node talents

Defined in `archetype_talents/talents/base_talents.lua`. Shared across all classes.
Pattern: `base_{stat}_node_buff_{tier}_{N}` where tier is `low`/`medium`/`high` and N is 1-5 (tree position slot).

All slots of the same type+tier give **identical effects** — the N suffix is just a tree position.
141 total stat node entries across 26 stat families.

| Stat family | Engine pattern | Available tiers |
|---|---|---|
| `toughness` | `base_toughness_node_buff_{tier}_{N}` | low, medium |
| `toughness_damage_reduction` | `base_toughness_damage_reduction_node_buff_{tier}_{N}` | low, medium |
| `melee_damage` | `base_melee_damage_node_buff_{tier}_{N}` | low, medium, high |
| `melee_heavy_damage` | `base_melee_heavy_damage_node_buff_{tier}_{N}` | low, medium |
| `ranged_damage` | `base_ranged_damage_node_buff_{tier}_{N}` | low, medium |
| `reload_speed` | `base_reload_speed_node_buff_{tier}_{N}` | low, medium |
| `stamina` | `base_stamina_node_buff_low_{N}` | low only |
| `stamina_regen` | `base_stamina_regen_delay_{N}` | no tiers, 2 slots only |
| `health` | `base_health_node_buff_{tier}_{N}` | low, medium |
| `crit_chance` | `base_crit_chance_node_buff_low_{N}` | low only |
| `movement_speed` | `base_movement_speed_node_buff_low_{N}` | low only |
| `coherency_regen` | `base_coherency_regen_node_buff_low_{N}` | low only (+2 unnumbered) |
| `suppression` | `base_suppression_node_buff_low_{N}` | low only |
| `armor_pen` | `base_armor_pen_node_buff_low_{N}` | low only |
| `warp_charge` | `base_warp_charge_node_buff_{tier}_{N}` | low, medium |

## add_archetype_base_talents behavior

Called by `LocalProfileBackendParser.parse_profile()` → `PlayerTalents.add_archetype_base_talents()`.

Source: `player_talents.lua` lines 38-87.

### Two-pass detection

**Pass 1** (lines 43-62): Iterate the already-populated `talents` table. For each talent,
look up its definition in `archetype.talents`. If the definition has
`player_ability.ability_type == "combat_ability"`, set `has_combat_ability = true`.
Same check for `"grenade_ability"`.

**Pass 2** (lines 66-86): Iterate base talents. For each one, if it has a
`player_ability.ability_type` that matches an already-present type, **skip it**.
Otherwise, add it: `talents[talent_name] = (talents[talent_name] or 0) + tier`.

### Effect

Pre-populating talents with a non-default combat ability (e.g.
`veteran_combat_ability_elite_and_special_outlines`) automatically suppresses the
default (e.g. `veteran_combat_ability_stance`). Same for grenades/blitz.

### Crash risk

Pass 1 calls `talent_definitions[talent_name]` without a nil guard. If the talents table
contains a key not present in `archetype.talents` (wrong class, typo, base_talents key),
it will crash on indexing `talent.player_ability`. **Only inject valid talent names for
the correct class.**

Base stat node talents (e.g. `base_toughness_node_buff_medium_1`) ARE in every class's
talent definitions — they're shared. So they are safe to inject.

## Ability template dispatch

BetterBots' heuristic system keys on **ability_template_name** (the runtime template
from `ability_component.template_name`), NOT on talent names.

Multiple talent choices can map to the same ability template:

| Talent(s) | Ability template | BetterBots heuristic |
|---|---|---|
| `veteran_combat_ability_stance` (Volley Fire), `veteran_combat_ability_elite_and_special_outlines` (Exec Stance) | `veteran_combat_ability` | `_can_activate_veteran_combat_ability` (special-cased) |
| `veteran_stealth_combat_ability` (Infiltrate) | `veteran_stealth_combat_ability` | `TEMPLATE_HEURISTICS` |
| `zealot_dash`, `zealot_targeted_dash*` (Charge variants) | `zealot_dash` / `zealot_targeted_dash*` | `TEMPLATE_HEURISTICS` |
| `zealot_invisibility` (Shroudfield) | `zealot_invisibility` | `TEMPLATE_HEURISTICS` |
| `zealot_bolstering_prayer` (Chorus) | `zealot_relic` | `ITEM_HEURISTICS` |
| `psyker_shout` (Venting Shriek) | `psyker_shout` | `TEMPLATE_HEURISTICS` |
| `psyker_combat_ability_stance` (Scrier's Gaze) | `psyker_overcharge_stance` | `TEMPLATE_HEURISTICS` |
| `ogryn_charge*` (Bull Rush variants) | `ogryn_charge*` | `TEMPLATE_HEURISTICS` |
| `ogryn_taunt_shout` (Loyal Protector) | `ogryn_taunt_shout` | `TEMPLATE_HEURISTICS` |

The talent → template mapping is defined in `{class}_talents.lua` via the
`player_ability.ability` field, which references a `PlayerAbilities.*` entry.
The ability template file lives at `ability_templates/{template_name}.lua`.

## hadrons-blessing canonical_entity_id mapping

hadrons-blessing builds use `canonical_entity_id` format: `domain.type.name`.

### Class-specific talents (direct mapping)

Strip the `domain.type.` prefix — the remainder IS the engine talent key:
- `veteran.talent.veteran_ranged_power_out_of_melee` → `veteran_ranged_power_out_of_melee`
- `zealot.talent_modifier.zealot_crits_grant_cd` → `zealot_crits_grant_cd`
- `psyker.keystone.psyker_new_mark_passive` → `psyker_new_mark_passive`

Applies to: `*.talent.*`, `*.talent_modifier.*`, `*.ability.*`, `*.aura.*`, `*.keystone.*`.

### Stat nodes (require mapping)

`shared.stat_node.*` IDs do NOT directly match engine keys:

| hadrons-blessing ID | Engine pattern | Recommended tier |
|---|---|---|
| `toughness_boost` | `base_toughness_node_buff_medium_{N}` | medium |
| `melee_damage_boost` | `base_melee_damage_node_buff_high_{N}` | high |
| `ranged_damage_boost` | `base_ranged_damage_node_buff_medium_{N}` | medium |
| `toughness_damage_reduction` | `base_toughness_damage_reduction_node_buff_medium_{N}` | medium |
| `stamina_boost` | `base_stamina_node_buff_low_{N}` | low (only) |
| `stamina_regeneration_boost` | `base_stamina_regen_delay_{N}` | no tier |
| `movement_speed_boost` | `base_movement_speed_node_buff_low_{N}` | low (only) |
| `reload_boost` | `base_reload_speed_node_buff_medium_{N}` | medium |
| `critical_chance_boost` | `base_crit_chance_node_buff_low_{N}` | low (only) |

Use sequential `_N` suffixes for multiple occurrences of the same stat in a build.
Prefer highest available tier for endgame builds.
