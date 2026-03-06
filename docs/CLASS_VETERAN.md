# Veteran (Sharpshooter)

> Source version: Darktide v1.10.7 (decompiled source at `../Darktide-Source-Code/`)
> Last updated: 2026-03-05

## Overview

The Veteran is a ranged-damage-focused class with 150 HP and Veteran-tier toughness. Base
critical strike chance is 10%. The class excels at eliminating elites, specials, and bosses
at range. The talent tree has three clear "lanes" corresponding to the three combat ability
variants, but zig-zagging between lanes is encouraged by the layout.

**Archetype file:** `scripts/settings/archetype/archetypes/veteran_archetype.lua`

**Base talents (always active):**
- `veteran_aura_gain_ammo_on_elite_kill` (**Survivalist** aura; formerly: Scavenger)
- `veteran_combat_ability_stance` (Volley Fire — base combat ability)
- `veteran_cover_peeking` (Cover Peeking)
- `veteran_frag_grenade` (**Shredder Frag Grenade**; formerly: Frag Grenade)
- `veteran_supression_immunity` (Suppression Immunity)

---

## Combat Ability (F key)

All three variants share the same underlying template structure. The ability uses a
press-hold-release input pattern: `combat_ability_pressed` -> optional hold (aim phase) ->
`combat_ability_released` (execute). There is also a `block_cancel` to abort.

**Template files:**
- `scripts/settings/ability/ability_templates/veteran_combat_ability.lua`
- `scripts/settings/ability/ability_templates/veteran_stealth_combat_ability.lua`

**Action logic:** `scripts/extension_systems/ability/actions/action_veteran_combat_ability.lua`

**`ability_meta_data` (for bot activation):**
```lua
ability_meta_data = {
    activation = {
        action_input = "stance_pressed",
    },
}
```

Both templates ship with `action_input = "stance_pressed"` in `ability_meta_data`, but their
actual action graph is `combat_ability_pressed` -> `combat_ability_released` (hold/release).
BetterBots overrides metadata for bot activation to `combat_ability_pressed` with
`wait_action = combat_ability_released`.

### Variant 1: Volley Fire / Executioner's Stance (Ranger path)

**Volley Fire** is the base combat ability. **Executioner's Stance** (internal: `veteran_combat_ability_elite_and_special_outlines`) is its augmented talent upgrade that adds enemy outlines, improved damage bonuses, toughness regen, and kill-based duration extension.

| Field | Value |
|---|---|
| Internal name | `veteran_combat_ability_stance` (base) / `veteran_combat_ability_stance_improved` (augmented) |
| Ability group | `volley_fire_stance` |
| Ability template | `veteran_combat_ability` |
| Ability type | `combat_ability` |
| Class tag | `ranger` |
| Cooldown | 30s (`veteran_2.combat_ability.cooldown`) |
| Max charges | 1 |
| Required weapon | `ranged` (must have ranged weapon) |
| Duration | 5s (base Volley Fire), 8s (with Big Game Hunter talent) |

**What it does:**
- Enters Ranged Stance, instantly equipping the ranged weapon
- Applies `veteran_combat_ability_stance_master` buff (or `_increased_duration` variant)
- Grants keyword `veteran_combat_ability_stance` which activates conditional stat buffs
- Base Volley Fire stats (always active during stance via `veteran_combat_ability_increased_ranged_and_weakspot_damage_base`):
  - +15% Ranged Damage
  - +15% Ranged Weakspot Damage
  - +50% Ranged Impact Modifier
- Executioner's Stance stats (with outlines talent via `..._outlines` buff, replaces base buff entirely):
  - +25% Ranged Damage (replaces base +15%)
  - +25% Ranged Weakspot Damage (replaces base +15%)
  - +100% Ranged Impact Modifier (replaces base +50%)
  - Replenishes 10% toughness/s while active
  - FOV multiplied by 0.85 (slight zoom)
  - Recoil -24%, Spread -38%, Sway x0.4

**Key talents that modify it:**
| Talent | Internal ID | Effect |
|---|---|---|
| Volley Fire (base) | `veteran_combat_ability_stance` | Base combat ability: +15% ranged damage/weakspot |
| Executioner's Stance (augmented) | `veteran_combat_ability_elite_and_special_outlines` | Upgrades Volley Fire to +25%/25%, outlines elites/specials, outlined kills extend duration, toughness regen |
| Big Game Hunter | `veteran_combat_ability_ogryn_outlines` | Also outlines Ogryn-type enemies, +25% damage vs Ogryn/Monsters, extends duration to 8s |
| Ranged Roamer Outlines | `veteran_combat_ability_ranged_roamer_outlines` | Outlines ranged enemies too |
| Coherency Outlines | `veteran_combat_ability_coherency_outlines` | Shares outlines to allies in coherency for 5s |
| Reloads Weapon | `veteran_combat_ability_reloads_secondary_weapon` | Ability instantly reloads ranged weapon |
| Extra Charge | `veteran_combat_ability_extra_charge` | +1 ability charge (but increases cooldown) |

**Bot usage notes:**
- Activate when multiple elites/specials are visible at medium-long range
- Should be used proactively before engaging high-threat targets, not as panic button
- Best when bot has clear line of sight and ranged weapon equipped
- Bot must have ranged weapon wielded (or ability auto-equips it)
- Duration of 5s means bot should already be in a shooting position
- Cooldown is short (30s) so relatively spammable

### Variant 2: Infiltrate (Shock Trooper path)

| Field | Value |
|---|---|
| Internal name | `veteran_combat_ability_stealth` |
| Ability group | `veteran_stealth` |
| Ability template | `veteran_stealth_combat_ability` |
| Ability type | `combat_ability` |
| Class tag | `shock_trooper` |
| Cooldown | 45s (`veteran_1.combat_ability.cooldown`) |
| Max charges | 1 |
| Required weapon | `nil` (any weapon) |

**What it does:**
- Triggers `on_combat_ability` proc event -> adds `veteran_invisibility` buff
- Invisibility buff: 8s duration, `keywords.invisible`, +25% movement speed
- Suppresses nearby enemies when leaving stealth (stagger_range = melee range + 1)
- Recovering full toughness on activation (server-side `Toughness.recover_max_toughness`)
- Plays `ability_cloak` animation (no shout, no stance)
- Stealth breaks on: shooting, hitting, reviving, rescuing (but NOT on frag/plasma/bleed/burning damage types if `can_attack_during_invisibility` keyword)
- Does NOT abort sprint, does NOT prevent sprint

**Key talents that modify it:**
| Talent | Internal ID | Effect |
|---|---|---|
| Infiltrate (base) | `veteran_invisibility_on_combat_ability` | Grants stealth + movement speed on combat ability |
| Damage Leaving Stealth | `veteran_damage_bonus_leaving_invisibility` | +X% damage for Y seconds after stealth ends |
| Toughness Leaving Stealth | `veteran_toughness_bonus_leaving_invisibility` | Toughness damage reduction after stealth ends |
| Reduced Threat | `veteran_reduced_threat_after_combat_ability` | Threat greatly reduced after using ability |
| Close Damage Bonus | `veteran_increased_close_damage_after_combat_ability` | Increased close damage after ability use |
| Weakspot Power Bonus | `veteran_increased_weakspot_power_after_combat_ability` | Increased weakspot power after ability use |

**Bot usage notes:**
- Use as escape when surrounded or about to go down (toughness recovery + stealth)
- Use to reposition safely when pinned by ranged enemies
- Use to reach downed allies for revives safely
- Bot should NOT attack during stealth unless truly necessary (breaks it)
- 45s cooldown is longest of the three variants -- save for emergencies
- After stealth ends, the bot gets damage bonuses, so follow-up attacks are important
- Ideal trigger condition: toughness < 30% OR ally is downed and needs revive

### Variant 3: Voice of Command (Squad Leader path)

| Field | Value |
|---|---|
| Internal name | `veteran_combat_ability_shout` |
| Ability group | `voice_of_command` |
| Ability template | `veteran_combat_ability` |
| Ability type | `combat_ability` |
| Class tag | `squad_leader` |
| Cooldown | 30s (`veteran_3.combat_ability.cooldown`) |
| Max charges | 1 |
| Required weapon | `nil` (any weapon) |
| Shout radius | 9m (`veteran_3.combat_ability.radius`) |

**What it does:**
- Executes `ShoutAbilityImplementation.execute()` -- an AoE shout
- Uses `veteran_shout` shout target template:
  - **Enemies:** Applies `force_stagger_type_if_not_staggered = "heavy"` (2.5s duration), power level 500, uses `shout_stagger_veteran` damage profile. Does NOT stagger already-staggered enemies.
  - **Allies:** Can revive knocked-down allies (if talent taken)
- Recovers ALL toughness (`Toughness.recover_max_toughness`)
- Plays `ability_shout` animation
- Sets `combat_ability_component.active = true`

**Key talents that modify it:**
| Talent | Internal ID | Effect |
|---|---|---|
| Voice of Command (base) | `veteran_combat_ability_stagger_nearby_enemies` | Stagger enemies within 9m, restore toughness |
| Revive Allies | `veteran_combat_ability_revive_nearby_allies` | Shout revives downed allies in range, but radius -33% and cooldown +50% (to 45s) |
| Toughness to Coherency | `veteran_combat_ability_increase_and_restore_toughness_to_coherency` | Grants +50 flat toughness to allies in coherency for duration |
| Damage to Coherency | `veteran_combat_ability_melee_and_ranged_damage_to_coherency` | Grants melee and ranged damage buff to coherency allies |
| Extra Charge | `veteran_combat_ability_extra_charge` | +1 ability charge |
| Elite Kill CDR | `veteran_elite_kills_reduce_cooldown` | Elite kills reduce cooldown by 6s |

**Bot usage notes:**
- Use when surrounded by melee enemies (stagger buys 2.5s breathing room)
- Use when toughness is critically low (instant full recovery)
- Use when allies are downed and within 9m (revive talent)
- Short cooldown (30s) allows fairly aggressive use
- Most team-friendly ability -- buffs coherency allies
- Ideal trigger: multiple enemies within 9m AND toughness < 50%, OR ally downed within range

---

## Blitz (Grenade)

All veteran grenades are item-based abilities (`ability_type = "grenade_ability"`). They use
`inventory_item_name` to reference a weapon item, NOT an `ability_template`. This means they
have no `ability_template` field and `template_name` stays `"none"` -- they are unreachable
via the standard BT ability activation path. This is a **Tier 3** implementation challenge.

**Abilities file:** `scripts/settings/ability/player_abilities/abilities/veteran_abilities.lua`

### Shredder Frag Grenade (Default; formerly: Frag Grenade)

| Field | Value |
|---|---|
| Internal name | `veteran_frag_grenade` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_frag` |
| Max charges | 3 (`veteran_2.grenade.max_charges`) |
| Stat buff | `extra_max_amount_of_grenades` |

**What it does:**
- Fragmentation grenade with bleed -- AoE explosion dealing damage in radius
- Good horde clear and stagger
- Base 3 charges

**Key talents:**
| Talent | Internal ID | Effect |
|---|---|---|
| Extra Grenade | `veteran_extra_grenade` | +1 grenade, chance to throw extra |
| Improved Grenades | `veteran_improved_grenades` | +25% frag damage, +25% explosion radius |
| Grenade Apply Bleed | `veteran_grenade_apply_bleed` | Frag applies 6 stacks of bleed |
| Replenish Grenades | `veteran_replenish_grenades` | Regenerate 1 grenade every 60s |
| Increased Explosion Radius | `veteran_increased_explosion_radius` | Increased explosion AoE |
| Extra Throw Chance | `veteran_extra_grenade_throw_chance` | Chance grenade splits on throw |

**Bot usage notes:**
- Throw into dense hordes for maximum value
- Good for creating space when team is being overwhelmed
- With bleed talent, useful against elites too
- 3 charges means bot can be moderately generous with usage

### Smoke Grenade

| Field | Value |
|---|---|
| Internal name | `veteran_smoke_grenade` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_smoke` |
| Max charges | 3 (`veteran_1.grenade.max_charges`) |

**What it does:**
- Creates smoke cloud that blocks line of sight
- Enemies in smoke cannot target players accurately
- Duration is a parameter on the smoke projectile template

**Key talents:** Same grenade-modifying talents apply. Improved Grenades gives +100% smoke duration.

**Bot usage notes:**
- Throw to block line of sight from ranged enemies (gunners, shooters, snipers)
- Use to cover revives of downed allies
- Most complex to use correctly -- poorly placed smoke is useless or harmful
- Bot AI should target ranged enemy clusters, not melee enemies
- Probably the hardest grenade type to implement well for bots

### Krak Grenade

| Field | Value |
|---|---|
| Internal name | `veteran_krak_grenade` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_krak` |
| Max charges | 3 (`veteran_3.grenade.max_charges`) |

**What it does:**
- Anti-armor grenade, focused single-target damage
- Extremely effective against Crushers, Bulwarks, Maulers, and monsters
- Damage profile: `close_krak_grenade`

**Key talents:** Improved Grenades gives +75% krak damage (`krak_damage = 0.75`).
Mixed talent: +50% krak damage (`veteran_3.mixed_2.krak_damage`).

**Bot usage notes:**
- Throw at high-armor targets: Crushers, Bulwarks, Maulers, Plague Ogryns
- Best single-target grenade -- save for dangerous elites
- Can delete groups of armored enemies if clustered
- Bot should prioritize monsters and Ogryn-type enemies

---

## Aura

Veterans have a coherency-based aura system. Only one aura can be active (all share the
`veteran_aura` identifier with different priorities).

### Survivalist (Default; internal: `veteran_aura_gain_ammo_on_elite_kill`; formerly: Scavenger)

| Field | Value |
|---|---|
| Internal name | `veteran_aura_gain_ammo_on_elite_kill` |
| Buff template | `veteran_aura_gain_ammo_on_elite_kill` |
| Priority | 1 |

**What it does:**
- Elite kills by you or allies in coherency replenish 0.75% ammo to you and coherency allies
- 5s cooldown between procs

### Survivalist (Improved)

| Field | Value |
|---|---|
| Internal name | `veteran_aura_gain_ammo_on_elite_kill_improved` |
| Buff template | `veteran_aura_gain_ammo_on_elite_kill_improved` |
| Priority | 2 (replaces base) |

**What it does:**
- Same as base but increases to 1% ammo replenishment

### Fire Team (internal: `veteran_increased_damage_coherency`; formerly: Close Order Drill)

Note: Close Order Drill is a separate passive talent, not this aura.

| Field | Value |
|---|---|
| Internal name | `veteran_increased_damage_coherency` |
| Buff template | `veteran_damage_coherency` |
| Priority | 2 |

**What it does:**
- Allies in coherency gain bonus damage

### Close and Kill (internal: `veteran_movement_speed_coherency`; formerly: Double Time)

| Field | Value |
|---|---|
| Internal name | `veteran_movement_speed_coherency` |
| Buff template | `veteran_movement_speed_coherency` |
| Priority | 2 |

**What it does:**
- Allies in coherency gain bonus movement speed

---

## Keystones

The Veteran has three keystone talent paths. Each fundamentally changes playstyle.

### 1. Marksman's Focus (internal: `veteran_snipers_focus`)

| Field | Value |
|---|---|
| Internal name | `veteran_snipers_focus` |
| Buff template | `veteran_snipers_focus` |

**What it does:**
- Gain stacks (up to 10, or 15 with talent) that grant +7.5% power and +1% reload speed per stack
- Stacks gained on ranged weakspot hits (3 stacks per hit)
- Stacks decay after 5s of not hitting weakspots (6s grace, 3s on non-weakspot hit)
- Rewards precision shooting at range

**Modifier talents:**
| Talent | Internal ID | Effect |
|---|---|---|
| Rending Bonus | `veteran_snipers_focus_rending_bonus` | At 10 stacks, gain rending multiplier |
| Toughness Bonus | `veteran_snipers_focus_toughness_bonus` | +4% toughness replenish per stack, +10% stamina |
| Stacks on Still | `veteran_snipers_focus_stacks_on_still` | Gain 1 stack per 0.75s while standing still |
| Increased Stacks | `veteran_snipers_focus_increased_stacks` | Max stacks increased from 10 to 15 |

**Bot usage notes:**
- Bot must prioritize headshots / weakspot hits to maintain stacks
- "Stacks on Still" is the easiest modifier for bots -- just stop moving
- Rewards staying at range and aiming carefully

### 2. Weapons Specialist

| Field | Value |
|---|---|
| Internal name | `veteran_weapon_switch_passive` |
| Buff template | `veteran_weapon_switch_passive_buff` |

**What it does:**
- Switching weapons grants stacking buffs:
  - Ranged: attack speed, reload speed, crit chance per stack
  - Melee: attack speed, dodge distance per stack
- Duration per stack (10s ranged)
- Encourages frequent weapon swapping

**Modifier talents:**
| Talent | Internal ID | Effect |
|---|---|---|
| Replenish Stamina | `veteran_weapon_switch_replenish_stamina` | Weapon switch replenishes 20% stamina, grants stamina cost reduction |
| Replenish Ammo | `veteran_weapon_switch_replenish_ammo` | Weapon switch replenishes 3.3% ammo |
| Reload Speed | `veteran_weapon_switch_reload_speed` | Bonus reload speed after switching |
| Stamina Reduction | `veteran_weapon_switch_stamina_reduction` | Stamina cost reduction after switching to melee |
| Replenish Toughness | `veteran_weapon_switch_replenish_toughness` | Weapon switch replenishes 20% toughness (3s cooldown) |

**Bot usage notes:**
- Bot needs to switch weapons frequently to maintain stacks
- More complex to implement -- requires deliberate swap cadence
- Works well with builds that alternate melee/ranged frequently

### 3. Focus Target!

| Field | Value |
|---|---|
| Internal name | `veteran_improved_tag` |
| Buff template | `veteran_improved_tag` |

**What it does:**
- Tagging an enemy applies a debuff: +5% damage taken per stack, up to 4 stacks (6 with talent)
- Stack applied every 1.5s while target remains tagged
- Whole team benefits from the damage increase on tagged target

**Modifier talents:**
| Talent | Internal ID | Effect |
|---|---|---|
| Dead Bonus | `veteran_improved_tag_dead_bonus` | Tagged enemies dying grants 5% toughness and 5% stamina |
| Coherency Bonus | `veteran_improved_tag_dead_coherency_bonus` | Tagged enemy deaths grant damage buff to coherency allies |
| More Damage | `veteran_improved_tag_more_damage` | Increases max stacks on tagged target |

**Bot usage notes:**
- Bot should tag elites and specials immediately on spotting them
- Team-wide damage amplifier -- especially strong in coordinated play
- Simple to implement: just tag priority targets

---

## Talent Tree Summary

### Passive / Utility Nodes

| Talent | Internal ID | Effect |
|---|---|---|
| Suppression Immunity | `veteran_supression_immunity` | Cannot be suppressed |
| Increased Weakspot Damage | `veteran_increased_weakspot_damage` | +30% weakspot damage |
| Cover Peeking | `veteran_cover_peeking` | Can peek from cover |
| Increased Ammo Reserve | (base passive_2) | +40% ammo reserve capacity |
| Clip Size | `veteran_clip_size` | +25% clip size |
| Reduced Swap Time | `veteran_reduce_swap_time` | +25% wield speed |
| Reduced Sprint Cost | `veteran_reduce_sprinting_cost` | Reduced stamina cost for sprinting |

### Offensive Nodes

| Talent | Internal ID | Effect |
|---|---|---|
| Increased Damage at Range | `veteran_increased_damage_based_on_range` | +10-25% ranged damage scaling with distance |
| Increased Suppression | `veteran_increase_suppression` | Bonus suppression dealt |
| Increased Elite Damage | `veteran_increase_damage_vs_elites` | Bonus damage vs elites |
| Increased Crit Chance | `veteran_increase_crit_chance` | Bonus crit chance |
| Damage After Sprinting | `veteran_increase_damage_after_sprinting` | Sprinting grants damage stacks |
| Big Game Hunter | `veteran_big_game_hunter` | Bonus damage vs Ogryn/Monsters |
| ADS Drain Stamina | `veteran_ads_drain_stamina` | ADS drains stamina but grants +25% crit and sway reduction |
| Crits Apply Rending | `veteran_crits_apply_rending` | Critical hits apply rending debuff |
| Consecutive Hits Rending | `veteran_continous_hits_apply_rending` | Consecutive hits apply stacking rending |
| Kills Grant Other Slot Damage | `veteran_kill_grants_damage_to_other_slot` | Melee kills buff ranged and vice versa |
| Grenade Bleed | `veteran_grenade_apply_bleed` | Frag grenades apply 6 stacks of bleed |
| Reload Speed on Elite Kill | `veteran_reload_speed_on_elite_kill` | +30% reload speed after elite kill |
| Hits Cause Bleed | `veteran_hits_cause_bleed` | Attacks apply bleed stacks |
| Bonus Crit on Low Ammo | `veteran_bonus_crit_chance_on_ammo` | Bonus crit when ammo below threshold |
| Las Weapon Crit No Ammo | `veteran_no_ammo_consumption_on_lasweapon_crit` | Las weapon crits cost no ammo |
| Flanking Damage | `veteran_increased_damage_when_flanking` | Bonus damage when flanking |
| Ranged Power Out of Melee | `veteran_ranged_power_out_of_melee` | Ranged damage bonus when no enemies in melee range (8s cooldown) |
| Melee Crit + Finesse | `veteran_increased_melee_crit_chance_and_melee_finesse` | Increased melee crit chance and finesse |
| Ally Kills Damage Buff | `veteran_ally_kills_increase_damage` | 2.5% chance ally kills grant +20% damage/impact/suppression for 8s |

### Defensive Nodes

| Talent | Internal ID | Effect |
|---|---|---|
| Toughness on Elite Kill | `veteran_elite_kills_replenish_toughness` | 10% instant + 20% over 10s toughness on elite kill |
| All Kills Toughness | `veteran_all_kills_replenish_toughness` | Bonus toughness on any kill |
| Weakspot Kill Toughness | `veteran_replenish_toughness_on_weakspot_kill` | 15% toughness + stacking TDR on ranged weakspot kills |
| Toughness Regen Out of Melee | `veteran_replenish_toughness_outside_melee` | 5% toughness every 5s when not in melee |
| TDR per Ally in Coherency | `veteran_reduced_toughness_damage_in_coherency` | Up to 33% TDR based on allies nearby |
| TDR on High Toughness | `veteran_tdr_on_high_toughness` | 25% TDR while above 75% toughness |
| Block Break / Toughness Break | `veteran_block_break_gives_tdr` | Block break gives TDR, toughness break gives block cost reduction |
| Reduced Threat When Still | `veteran_reduced_threat_when_still` | -90% threat generation while stationary |
| Dodging Grants Stamina | `veteran_dodging_grants_stamina` | Dodging ranged attacks grants +30% stamina |
| Dodging Grants Crit | `veteran_dodging_grants_crit` | Dodging attacks grants stacking crit chance |
| Movement Speed on Toughness Broken | `veteran_movement_speed_on_toughness_broken` | Movement speed buff when toughness breaks |

### Support / Cooperative Nodes

| Talent | Internal ID | Effect |
|---|---|---|
| Elite Kill CDR | `veteran_elite_kills_reduce_cooldown` | Elite kills reduce combat ability cooldown by 6s |
| Better Deployables | `veteran_better_deployables` | Ammo crates replenish grenades, healing crates heal corruption |
| Movement Speed Towards Downed | `veteran_movement_speed_towards_downed` | +20% move speed toward disabled allies, revived allies get DR |
| Share Toughness Gain | `veteran_allies_in_coherency_share_toughness_gain` | Allies in coherency get 20% of your toughness gains |
| Coherency Radius Increase | `veteran_coherency_aura_size_increase` | Increased coherency aura radius |
| Replenish Ally Toughness on Kill | `veteran_replenish_toughness_and_boost_allies` | Ranged kills near allies restore their toughness + damage buff |
| Elite Kills Restore Grenade | `veteran_aura_elite_kills_restore_grenade` | 5% chance elite kills restore grenade to coherency |

---

## Practical Usage (from community guides)

### When to Use Combat Ability

**Volley Fire / Executioner's Stance:**
- Activate when you spot a cluster of elites/specials at range
- Use to burst down high-priority targets (Ragers, Gunners, Snipers)
- Pair with a high-DPS semi-auto weapon (Infantry Lasgun MkIX is popular)
- Killing outlined enemies refreshes the 5s duration -- chain kills to extend
- Short 30s cooldown allows aggressive usage

**Infiltrate (Stealth):**
- Use as an escape when surrounded or about to go down
- Use to reposition when pinned by ranged enemies
- Use to safely revive downed teammates
- Use to do hacking objectives uninterrupted
- Do NOT attack during stealth unless you have `can_attack_during_invisibility`
- After leaving stealth, enemies near you get suppressed -- follow up with attacks
- 45s cooldown is the longest -- reserve for emergencies or high-value plays

**Voice of Command (Shout):**
- Use when surrounded by melee enemies for instant breathing room (2.5s heavy stagger)
- Use when toughness is critically low (instant full recovery)
- Use to revive downed allies within 9m (if revive talent is taken)
- 30s cooldown (45s with revive talent) -- use aggressively
- The stagger does NOT affect already-staggered enemies
- Buffs allies in coherency (damage, toughness) -- use when team is grouped

### When to Use Grenades

**Shredder Frag Grenade:**
- Throw into dense hordes for maximum AoE damage and stagger
- With bleed talent, useful for softening elite packs
- 3 charges -- use moderately

**Krak Grenade:**
- Save for Crushers, Bulwarks, Maulers, and Plague Ogryns
- Can delete groups of armored enemies if they are clustered
- Highest single-target damage of all veteran grenades

**Smoke Grenade:**
- Throw between your team and ranged enemies (gunners/snipers)
- Use to cover revives of downed allies
- NEVER throw on your own melee position -- blocks your own vision
- Most difficult to use correctly; poorly placed smoke is harmful

### Positioning and Priority Tips

- Veterans are most effective at medium-to-long range
- Prioritize killing specials (Trappers, Mutants, Hounds) first, then elites
- Stay behind melee classes (Ogryn, Zealot) when possible
- Maintain coherency range for aura benefits
- For Marksman's Focus builds: find a vantage point and aim for headshots
- For Weapon Specialist builds: alternate melee/ranged regularly
- For Focus Target! builds: tag priority targets immediately and let the team focus them

---

## Implementation Notes for BotAbilities Mod

### Activation Pattern
Vanilla metadata points to `stance_pressed`, but template action inputs are
`combat_ability_pressed`/`combat_ability_released`. BetterBots patches metadata at runtime so
bot validity checks and queueing use the actual press/release path.

### Grenade Challenge
Veteran grenades are item-based (`inventory_item_name` based, no `ability_template`).
The `template_name` remains `"none"`, making them unreachable via the standard BT
`use_ability` node. This requires a Tier 3 approach -- likely injecting a custom BT node
or intercepting the grenade input system.

### Class Tag Detection
The `ability_template_tweak_data.class_tag` field determines which variant is active:
- `"base"` or `"ranger"` = Volley Fire / Executioner's Stance
- `"shock_trooper"` = Infiltrate
- `"squad_leader"` = Voice of Command

The bot should check this tag to determine appropriate usage heuristics.

### Key Differences Between Variants for Bot Logic
| Aspect | Exec. Stance | Infiltrate | Voice of Command |
|---|---|---|---|
| Requires ranged weapon | Yes | No | No |
| Stagger enemies | No | On exit | On activation |
| Recovers toughness | Via buff over time | Full on activation | Full on activation |
| Team support | Outlines (visual only) | None | Stagger + buffs + revive |
| Defensive use | Low | High | High |
| Offensive use | High | Medium | Low |
| Cooldown | 30s | 45s | 30s |

### Source References
- Ability templates: `scripts/settings/ability/ability_templates/veteran_combat_ability.lua`
- Stealth template: `scripts/settings/ability/ability_templates/veteran_stealth_combat_ability.lua`
- Player abilities: `scripts/settings/ability/player_abilities/abilities/veteran_abilities.lua`
- Talent definitions: `scripts/settings/ability/archetype_talents/talents/veteran_talents.lua`
- Talent settings (values): `scripts/settings/talent/talent_settings_veteran.lua`
- Buff templates: `scripts/settings/buff/archetype_buff_templates/veteran_buff_templates.lua`
- Action logic: `scripts/extension_systems/ability/actions/action_veteran_combat_ability.lua`
- Shout targets: `scripts/settings/ability/shout_target_templates.lua`
- Archetype: `scripts/settings/archetype/archetypes/veteran_archetype.lua`
