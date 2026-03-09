# Grenade & Blitz Inventory

> Source version: Darktide v1.10.7 (decompiled source at `../Darktide-Source-Code/`)
> Last updated: 2026-03-06

## Summary

19 total grenade/blitz weapon templates exist across all classes. **All lack an `ability_template` field** (except `adamant_whistle`), meaning none can be activated through the standard `bt_bot_conditions.can_activate_ability` BT path. All require an item-based fallback approach (wield -> use -> unwield), similar to Tier 3 combat abilities.

The BT node `activate_grenade_ability` exists at priority 9 with component `grenade_ability_action`, but it relies on `ability_meta_data` lookup via `ability_template` -- a field none of these templates define.

**Source directory:** `../Darktide-Source-Code/scripts/settings/equipment/weapon_templates/grenades/`

---

## Template Inventory

### Standard Grenades (9)

Generated via `grenade_weapon_template_generator`. Default wield time ~1.5s. All use the same input pattern: `aim_hold` (`action_one_pressed`) -> hold -> `aim_released` (`action_one_hold` release). Action kind: `throw_grenade`.

| Template name | File | Class |
|---|---|---|
| `adamant_grenade` | `adamant_grenade.lua` | Arbites |
| `fire_grenade` | `fire_grenade.lua` | Zealot |
| `frag_grenade` | `frag_grenade.lua` | Veteran |
| `ogryn_grenade_box` | `ogryn_grenade_box.lua` | Ogryn |
| `ogryn_grenade_box_cluster` | `ogryn_grenade_box_cluster.lua` | Ogryn |
| `ogryn_grenade_frag` | `ogryn_grenade_frag.lua` | Ogryn |
| `ogryn_grenade_friend_rock` | `ogryn_grenade_friend_rock.lua` | Ogryn |
| `smoke_grenade` | `smoke_grenade.lua` | Veteran |
| `tox_grenade` | `tox_grenade.lua` | Hive Scum (via `broker_tox_grenade`) |

**Input sequence:**
1. `action_one_pressed` -- begins aim/hold (`aim_hold` action)
2. Release `action_one_hold` -- triggers `aim_released`, throws grenade

### Handleless Grenades (3)

Generated via `grenade_handleless_weapon_template_generator`. Faster wield time (~0.3s vs 1.5s for standard). Same throw input pattern as standard grenades. Action kind: `throw_grenade`.

| Template name | File | Class |
|---|---|---|
| `quick_flash_grenade` | `quick_flash_grenade.lua` | Hive Scum |
| `shock_grenade` | `shock_grenade.lua` | Zealot (via `zealot_shock_grenade`) |
| `krak_grenade` | `krak_grenade.lua` | Veteran |

### Mine (1)

Place-down mechanic instead of throw. Uses `action_one_pressed` to place.

| Template name | File | Class |
|---|---|---|
| `shock_mine` | `shock_mine.lua` | Arbites (via `adamant_shock_mine`) |

### Class-Specific Blitz Abilities (6)

Each has a unique action hierarchy and input pattern. These are the most complex to support.

| Template name | File | Class | Input pattern | Action kind | Notes |
|---|---|---|---|---|---|
| `adamant_whistle` | `adamant_whistle.lua` | Arbites | `aim_pressed` -> `aim_released` | `ability_target_finder` | Only blitz with an `ability_template` field reference in related code |
| `psyker_chain_lightning` | `psyker_chain_lightning.lua` | Psyker | Custom chain | `chain_lightning` | Warp charge gated |
| `psyker_smite` | `psyker_smite.lua` | Psyker | Custom chain | `smite_targeting` | Warp charge gated, channeled |
| `psyker_throwing_knives` | `psyker_throwing_knives.lua` | Psyker | `throw_pressed` (`grenade_ability_pressed`) | `spawn_projectile` | Multiple charges |
| `broker_missile_launcher` | `missile_launcher` (inventory item) | Hive Scum | Custom | `spawn_projectile` | Boom Bringer — burst damage at range |
| `zealot_throwing_knives` | `zealot_throwing_knives.lua` | Zealot | `throw_pressed` (`grenade_ability_pressed`) | `spawn_projectile` | Multiple charges |

**Psyker blitz notes:** `psyker_chain_lightning` and `psyker_smite` have custom action hierarchies with warp charge costs. Activation requires checking `warp_charge.current_percentage` via `unit_data_extension:read_component("warp_charge")` to avoid self-damage from overcharge.

---

## BT Integration

The bot behavior tree has an `activate_grenade_ability` node at **priority 9** (below combat ability at priority 8). The node uses:

- **Component:** `grenade_ability_action`
- **Condition:** `bt_bot_conditions.can_activate_ability` (same gate as combat abilities)
- **Action node:** `bt_bot_activate_ability_action` (same as combat abilities)

The condition checks for `ability_meta_data` on the ability template, which requires an `ability_template` field on the weapon template to resolve. Since none of the 18 grenade templates define this field, the condition always returns `false` for grenades.

---

## Implementation Approaches

Two paths exist for bot grenade support:

### Path A: Inject `ability_template` + metadata

Inject a synthetic `ability_template` field and matching `ability_meta_data` into each grenade weapon template at load time. This would let the existing BT path (`can_activate_ability` -> `bt_bot_activate_ability_action`) handle activation.

- **Pro:** Reuses existing BT infrastructure.
- **Con:** Grenade templates were never designed to have `ability_template`. The field resolution path may have assumptions that break. Psyker blitz abilities have complex action hierarchies that may not map cleanly to `ability_meta_data.activation`.

### Path B: Extend item fallback with grenade profiles

Extend `item_fallback.lua` (or a new `grenade_fallback.lua`) with per-template sequence profiles: wield grenade item -> execute input sequence -> unwield.

- **Pro:** Full control over timing and input sequencing per template. Handles the variety of action kinds (throw, place, channel, target-find).
- **Con:** More code to maintain. Bypasses the BT ability node entirely.

### Recommended approach

Path B is more robust given the diversity of input patterns (throw vs place vs channel vs target-find). Standard and handleless grenades could share a single `throw` profile. Mines, whistle, and psyker blitz each need dedicated profiles. This mirrors the Tier 3 item-ability fallback pattern already proven for `zealot_relic`, `force_field`, and `drone`.

---

## Related

- Issue #4 -- Blitz/grenade support
- `docs/bot/input-system.md` -- Action input queuing and item wield sequences
- `docs/bot/combat-actions.md` -- BT action node lifecycles
- `docs/classes/*.md` -- Per-class ability references (grenade sections)
