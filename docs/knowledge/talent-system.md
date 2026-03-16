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

## Weapon blessing/perk overrides (Phase 2)

Source: MasterItems cache dump, 2026-03-16. 571 TRAITs, 67 PERKs in the catalog.

### How weapon overrides work

`MasterItems.get_item_or_fallback()` returns a bare weapon definition with no blessings.
`MasterItems.get_item_instance(gear, gear_id)` returns a proxied item with `overrides` merged on top.

The `gear` parameter must have this shape:
```lua
gear = {
    masterDataInstance = {
        id = "content/items/weapons/player/...",  -- master item content path
        overrides = {
            traits = {
                { id = "content/items/traits/bespoke_X/Y", rarity = 4, value = 1 },
            },
            perks = {
                { id = "content/items/perks/melee_common/Z", rarity = 4 },
            },
        },
    },
}
```

Each trait/perk `id` must exist in `MasterItems.get_cached()` or it gets silently dropped
by `_validate_overrides`.

### Trait (blessing) content paths

Format: `content/items/traits/bespoke_<weapon_family>/<effect_name>`

Weapon family = weapon template with `_mN` suffix stripped:
- `combatsword_p2_m1` → `bespoke_combatsword_p2`
- `plasmagun_p1_m1` → `bespoke_plasmagun_p1`

The `<effect_name>` is an internal description, NOT the display name:
- "Rampage" → `increased_melee_damage_on_multiple_hits`
- "Blazing Spirit" → `warp_charge_power_bonus`
- "Blaze Away" → `power_bonus_on_continuous_fire`

Each trait entry has a `trait` field containing the Lua buff template name:
`weapon_trait_bespoke_<family>_<effect_name>`.

### Perk content paths

Format: `content/items/perks/<category>/<perk_short_name>`

Categories: `melee_common`, `ranged_common`, `gadget_common`.

The `trait` field in the perk entry matches the hadrons-blessing perk entity ID directly:
- `weapon_trait_melee_common_wield_increased_armored_damage` → `content/items/perks/melee_common/wield_increase_armored_damage`
- `weapon_trait_ranged_common_wield_increased_super_armor_damage` → `content/items/perks/ranged_common/wield_increase_super_armor_damage`

Note: the content path short name doesn't always match the trait name exactly (e.g.
`increased_armored_damage` in the trait field vs `increase_armored_damage` in the path).
Use the content path as the authoritative `id` for overrides.

### hadrons-blessing entity ID → content path mapping

**Blessings** (`shared.name_family.blessing.*`): These are display-name families, NOT
directly mappable to content paths. Each blessing has a different internal effect name
per weapon family. Must look up the specific weapon family's trait list to find the
matching content path. The mapping requires either:
1. A pre-built lookup table (display_name → content_path per weapon family)
2. Runtime search of MasterItems cache by `display_name` localization key

**Perks** (`shared.weapon_perk.melee.*` / `shared.weapon_perk.ranged.*`): The entity ID's
last segment matches the `trait` field in the MasterItems perk entry. Can reverse-lookup
the content path by searching for matching `trait` values in the perk catalog.

### Verified trait content paths for bot profile weapons

From MasterItems dump (2026-03-16). Missing entries need runtime lookup.

**combatsword_p2 (veteran melee)**:
- `increased_melee_damage_on_multiple_hits` — Rampage
- `increase_power_on_hit` — Wrath
- `pass_past_armor_on_crit`, `stacking_rending_on_cleave`, `chained_hits_increases_cleave`,
  `increased_attack_cleave_on_multiple_hits`, `infinite_melee_cleave_on_weakspot_kill`,
  `increased_crit_chance_on_weakspot_kill`, `power_bonus_based_on_charge_time`

**plasmagun_p1 (veteran ranged)**:
- `power_bonus_scaled_on_heat` — (Hot-Shot candidate)
- `crit_chance_scaled_on_heat`, `lower_overheat_gives_faster_charge`,
  `reduced_overheat_on_critical_strike`, `reduced_overheat_on_continuous_fire`,
  `toughness_on_elite_kills`, `armor_rend_on_projectile_hit`,
  `power_bonus_on_continuous_fire`, `crit_chance_bonus_based_on_charge_time`,
  `no_vent_damage_but_slower`

**powersword_2h_p1 (zealot melee)**:
- `reduce_fixed_overheat_amount` — Heatsink
- `chained_weakspot_hits_increase_finesse_and_reduce_overheat` — Cranial Grounding candidate
- `increased_melee_damage_on_multiple_hits`, `chained_hits_increases_cleave`,
  `infinite_melee_cleave_on_crit`, `power_bonus_scaled_on_heat`,
  `explosion_on_overheat_lockout`, `slower_heat_buildup_on_perfect_block`,
  `attack_speed_on_perfect_block`,
  `regain_toughness_on_multiple_hits_by_weapon_special`

**flamer_p1 (zealot ranged)**:
- `power_bonus_on_continuous_fire` — Blaze Away
- `armor_rending_from_dot_burning` — Penetrating Flame
- `toughness_on_continuous_fire`, `power_scales_with_clip_percentage`,
  `faster_reload_on_empty_clip`, `ammo_spent_from_reserve_on_crit`,
  `chance_to_explode_elites_on_kill`,
  `ignore_stagger_reduction_with_primary_on_burning`

**forcesword_2h_p1 (psyker melee)**:
- `warp_charge_power_bonus` — Blazing Spirit
- `chained_hits_increases_cleave` — Shred candidate
- `warp_burninating_on_crit`, `wind_slash_periodically_crits`,
  `can_block_ranged`, `chained_hits_increases_crit_chance`,
  `dodge_grants_crit_chance`, `dodge_grants_finesse_damage`,
  `toughness_recovery_on_multiple_hits`, `vent_warp_charge_on_multiple_hits`

**forcestaff_p4 (psyker ranged)**:
- `faster_charge_on_chained_secondary_attacks` — Warp Nexus candidate
- `followup_shots_ranged_damage` — Warp Flurry candidate
- `warpfire_burn_on_crit`, `suppression_on_close_kill`,
  `allow_hipfire_while_sprinting`, `peril_vent_on_weakspot_hit`,
  `increased_crit_chance_scaled_on_peril`, `uninterruptable_while_charging`,
  `double_shot_on_crit`

**ogryn_powermaul_p1 (ogryn melee)**:
- `explosion_on_activated_attacks_on_armor` — Power Surge candidate
- `staggered_targets_receive_increased_stagger_debuff` — Skullcrusher candidate
- `armor_penetration_against_staggered`, `armor_rend_on_activated_attacks`,
  `toughness_recovery_on_chained_attacks`, `infinite_melee_cleave_on_weakspot_kill`,
  `pass_past_armor_on_crit`, `staggered_targets_receive_increased_damage_debuff`

**ogryn_thumper_p1 (ogryn ranged)**: NOT IN DUMP — zero traits found under
`bespoke_ogryn_thumper_p1`. May use a different family name. Needs investigation.
