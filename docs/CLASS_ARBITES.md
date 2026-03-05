# Arbites (Internal Codename: `adamant`)

> Last updated: 2026-03-05
>
> Reference document for mod development. All internal names, values, and mechanics
> extracted from decompiled source (v1.10.7). Community usage notes from web guides.

## Overview

The Arbites (Arbitrator) is a DLC class (`requires_dlc = "adamant"`) added post-launch.
Breed: `human`. Companion breed: `companion_dog` (Cyber-Mastiff).

**Base stats:**
- Health: 200
- Toughness: 80 (regen delay 3s)
- Base crit chance: 7.5%

**Base talents (always active):**
- `adamant_area_buff_drone` (Nuncio-Aquila drone)
- `adamant_command_tog_with_tag` (Mastiff target command)
- `adamant_companion_aura` (companion coherency aura)
- `adamant_companion_damage_per_level` (mastiff scales with level)
- `adamant_grenade` (frag grenades)

The Arbites is a frontline enforcer with a unique Cyber-Mastiff companion. Three talent
tree paths: **Investigator** (target marking / execution), **Exterminator** (companion +
kill synergy), **Subjugator** (stagger / control / tanking).

---

## Combat Ability (F Key)

The Arbites has **three** mutually-exclusive combat ability choices in the talent tree
(`exclusive_group = "ability_1"`): **Nuncio-Aquila Improved** (`adamant_area_buff_drone_improved`),
**Break the Line** (`adamant_charge`), and **Castigator's Stance** (`adamant_stance`).

The base Nuncio-Aquila (`adamant_area_buff_drone`) is always active as a base talent. Taking the
Improved node upgrades it; taking Charge or Stance provides an alternative combat ability.

> **Note:** `adamant_shout` and `adamant_shout_improved` exist in ability/talent data but do NOT
> appear in the talent tree layout (`adamant_tree.lua`). They may be cut content or reserved for
> future use. Documented below for completeness.

### 1. Shout (Base) -- `adamant_shout`

| Field | Value |
|-------|-------|
| Template | `adamant_shout` (ability), `adamant_shout` (shout target) |
| Ability type | `combat_ability` |
| Input actions | `shout_pressed` (`combat_ability_pressed`) -> hold -> `shout_released` (`combat_ability_hold` = false) |
| Activation pattern | Hold-and-release shout (like Ogryn taunt). Can cancel with `block_cancel` (RMB while holding). |
| Action kind | `adamant_shout` (cone AoE) |
| Cooldown | **60s**, 1 charge |
| Range | 6m (near), 12m (far/cone forward) |
| Shape | Cone (`shout_dot = 0.75`) |
| Effects | Staggers enemies (light stagger, 2.5s duration, shout_target power 1000, action power 500). Applies `adamant_whistle_electrocution` to enemies. Refills own toughness to 100%. |
| Animation | `ability_shout`, 0.75s total |
| `ability_meta_data` | **None** -- no pre-defined bot activation metadata |

**Bot usage notes:** Shout-pattern ability with hold/release. Needs injected metadata with both `shout_pressed`/`shout_released` inputs. Good for emergency CC + toughness recovery. Bot should use when surrounded or toughness is low.

### 2. Shout Improved -- `adamant_shout_improved`

| Field | Value |
|-------|-------|
| Template | `adamant_shout` (same ability template), `adamant_shout_improved` (shout target) |
| Ability type | `combat_ability` |
| Input actions | Same as base shout |
| Cooldown | **60s**, 1 charge |
| Range | 6m (near), **16m** (far/cone forward -- larger range) |
| Additional effects | Same stagger + toughness refill for self. **Also restores 30% toughness to allies** in range. Does NOT apply electrocution (unlike base shout). |

**Bot usage notes:** Strictly better for team support. Same activation pattern. Bot should prioritize using this when allies are nearby and low on toughness.

### 3. Charge -- `adamant_charge`

| Field | Value |
|-------|-------|
| Template | `adamant_charge` (ability), `adamant_charge` (lunge) |
| Ability type | `combat_ability` |
| Input actions | `aim_pressed` (`combat_ability_pressed`) -> hold to aim direction -> `aim_released` (`combat_ability_hold` = false) |
| Activation pattern | Directional dash aim, then lunge on release. Can cancel with `block_cancel`. |
| Action kind | `directional_dash_aim` -> `character_state_change` (lunging) |
| Cooldown | **20s**, 1 charge |
| Distance | 3.75m base (7.5m with `adamant_charge_longer_distance` talent) |
| Speed | Ramps 8 -> 13 m/s over 0.2s |
| Effects | Disables minion collision during charge. Deals `adamant_charge_impact` damage in 1m radius. Stops on elites/specials/monsters/captains. On finish: directional shout with heavy stagger (2.5s). Post-charge buff: +25% damage, +50% impact for **6s**. During lunge: counts as blocking (melee + ranged) + dodge vs chaos hound pounce + dodge vs netgunner. |
| Lunge template | `adamant_charge` -- `slot_to_wield = "slot_primary"`, `disable_weapon_actions = true` |
| `ability_meta_data` | **None** -- needs injected metadata |

**Key modifying talents:**
- `adamant_charge_cooldown_reduction`: Kill enemies during charge to reduce CD (0.5s per hit, 1s per elite, max 5s refund)
- `adamant_charge_toughness`: 20% toughness per elite hit during charge (max 100%), 15% stamina per elite (max 75%)
- `adamant_charge_longer_distance`: Increases distance to 7.5m total

**Bot usage notes:** Short-cooldown gap-closer. Two-step aim+release pattern like zealot dash. Bot should use to close distance to priority targets or escape danger. The blocking-during-charge makes it good for traversing dangerous ground.

### 4. Stance (Castigator's Stance) -- `adamant_stance`

| Field | Value |
|-------|-------|
| Template | `adamant_stance` |
| Ability type | `combat_ability` |
| Input actions | `stance_pressed` (`combat_ability_pressed`) -- single press, instant activation |
| Activation pattern | **Single press** -- Tier 1, simplest pattern |
| Action kind | `stance_change` |
| Cooldown | **50s**, 1 charge |
| Duration | **10s** (+ 2s linger for damage reduction) |
| Effects | **Refills toughness to 100%** on activation. +15% movement speed, removes ADS/weapon action movement penalty, **-80% damage taken** (`damage_taken_multiplier = 0.2`), disables sprint (`no_sprint` keyword). On expiry: 2s lingering DR at same 80% reduction. |
| `ability_meta_data` | **Yes** -- has `activation.action_input = "stance_pressed"`. Bots can use this natively. |
| Buff applied | `adamant_hunt_stance` (proc buff, duration-based) |

**Key modifying talents:**
- `adamant_stance_dog_bloodlust`: During stance, companion gets +75% damage
- `adamant_stance_damage`: +25% damage during stance
- `adamant_stance_elite_kills_stack_damage`: Elite/special kills during stance grant +5% damage stacks (max 10, 10s duration)
- `adamant_stance_ranged_kills_transfer_ammo`: Ranged kills during stance transfer 10% ammo from reserve to clip (1.5s ICD)

**Bot usage notes:** This is the easiest ability for bots -- single-press activation with pre-existing `ability_meta_data`. Massive 80% DR plus full toughness refill makes it ideal as a defensive panic button. Bot should activate when taking heavy damage or before engaging a dangerous pack. The `no_sprint` keyword means bot will walk during stance -- factor this into movement logic. Note: internal identifiers still use `adamant_stance`/`adamant_hunt_stance`.

---

## Blitz / Grenade Ability

The Arbites has **three** mutually-exclusive blitz choices in the talent tree
(`exclusive_group = "blitz_1"`): **Whistle** (`adamant_whistle`), **Frag Grenade Improved**
(`adamant_grenade_improved`), and **Shock Mine** (`adamant_shock_mine`).

The base frag grenade (`adamant_grenade`) is always active as a base talent. The Whistle is
`incompatible_talent = "adamant_disable_companion"` (cannot be used with Lone Wolf).

### 1. Frag Grenade (Base) -- `adamant_grenade`

| Field | Value |
|-------|-------|
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_adamant` |
| Max charges | **3** |
| No ability_template | Item-based (thrown grenade). No `ability_template` field. |

**Bot usage notes:** Standard thrown grenade, same pattern as other classes. Item-based, no ability template -- must be used through inventory/grenade system. Tier 3 complexity for bot integration.

### 2. Frag Grenade Improved -- `adamant_grenade_improved`

| Field | Value |
|-------|-------|
| Same as base but | **4 charges** instead of 3 |

Modifying talents:
- `adamant_grenade_increased_radius`: +50% explosion radius
- `adamant_grenade_increased_damage`: +50% frag damage

### 3. Whistle (Remote Detonation / Mastiff Command) -- `adamant_whistle`

| Field | Value |
|-------|-------|
| Template | `adamant_whistle` |
| Ability type | `grenade_ability` |
| Input actions | `aim_pressed` (`grenade_ability_pressed`) -> hold to aim -> `aim_released` (`grenade_ability_hold` = false) |
| Activation pattern | Hold-aim-release targeting. |
| Action kind | `shout_aim` -> `order_companion` |
| Cooldown | **50s** per charge |
| Max charges | **2** |
| Smart targeting | `SmartTargetingTemplates.default_melee` |
| Effects | Commands Cyber-Mastiff to target. Electric discharge at mastiff's position dealing damage + heavy stagger. Disables grenade pickups (`disable_grenade_pickups` special rule). |
| Charge replenishment | Auto-replenishes charges on cooldown timer (via `adamant_whistle_replenishment` buff) |

**Bot usage notes:** This replaces grenades entirely. Uses `grenade_ability_pressed/hold` input -- different from combat ability. The `order_companion` action kind is unique to Arbites. Bot should use to direct mastiff at priority targets (specials, elites). Requires companion to be alive. Incompatible with Lone Wolf talent.

### 4. Shock Mine -- `adamant_shock_mine`

| Field | Value |
|-------|-------|
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/mine_shock` |
| Max charges | **2** |
| Duration | 15s (mine persists) |
| Range | 3m trigger radius |

**Bot usage notes:** Deployable mine, item-based. Difficult for bot to use effectively -- requires positional awareness of choke points.

---

## Nuncio-Aquila (Area Buff Drone) -- `adamant_area_buff_drone`

The Nuncio-Aquila is a **base talent** (always active) AND a selectable **combat ability** in the
talent tree (`exclusive_group = "ability_1"`). The base version is always present; the tree offers
`adamant_area_buff_drone_improved` as one of three combat ability choices.

| Field | Value |
|-------|-------|
| Ability type | `combat_ability` |
| Inventory item | `content/items/weapons/player/drone_area_buff` |
| Cooldown | **60s** |
| Max charges | 1 |
| Duration | **20s** |
| Range | 7.5m |
| Base effects | +15% damage taken by enemies in zone, +5% toughness regen/sec for allies |
| `can_be_previously_wielded_to` | false |
| `can_be_wielded_when_depleted` | false |

**Key modifying talents:**
- `adamant_area_buff_drone_improved`: Adds suppression immunity, slowdown immunity, +30% suppression dealt, +30% impact, -25% recoil, toughness regen increased to 7.5%/sec
- `adamant_drone_buff_talent`: Allies in zone get -30% TDR, +30% revive speed, +10% attack speed
- `adamant_drone_debuff_talent`: Enemies in zone get -25% melee attack speed, -25% melee damage

**Bot usage notes:** Deployable zone, typed `combat_ability` but item-based (no `ability_template`). Bot should deploy it at the team's hold position during horde defense or near objectives. Long cooldown makes timing important. Tier 3 for bot integration (item-based, no ability template).

---

## Aura (Coherency)

The Arbites has a unique coherency mechanic: the Cyber-Mastiff can count toward coherency.

### Base Aura -- `adamant_companion_aura`

The default aura. Makes the companion count toward coherency via `adamant_dog_counts_towards_coherency` special rule.

### Aura Choices (talent row):

| Talent | Buff | Effect |
|--------|------|--------|
| `adamant_wield_speed_aura` | `adamant_wield_speed_aura` | +10% wield speed in coherency (talent setting: `coherency.adamant_wield_speed_aura.wield_speed = 0.1`; note: buff template `"adamant_wield_speed_aura"` not found in buff_templates -- may be dynamically registered) |
| `adamant_reload_speed_aura` | `adamant_reload_speed_aura` | +12.5% reload speed in coherency |
| `adamant_damage_vs_staggered_aura` | `adamant_damage_vs_staggered_aura` | +10% damage vs staggered in coherency |
| `adamant_companion_coherency` | `adamant_companion_aura` | Companion counts for coherency + allies get -7.5% TDR in coherency |

Note: When `adamant_wield_speed_aura` is selected, it replaces the companion coherency with a `adamant_no_companion_coherency` buff (no-op). The companion no longer counts for coherency. Same for `adamant_reload_speed_aura` and `adamant_damage_vs_staggered_aura`.

### Lone Wolf -- `adamant_disable_companion`

A special talent that **disables the companion entirely** in exchange for:
- +10% damage
- +15% TDR
- +10% attack speed
- +1 grenade charge
- Blitz recharges over time (60s whistle / 45s grenade / 90s mine)

---

## Keystones

### 1. Forceful -- `adamant_forceful`

**Core mechanic:** Staggering enemies or blocking attacks grants stacks (max 10, 5s duration each). Each stack gives:
- +5% impact
- +2.5% damage reduction

At max stacks, conditional bonuses apply based on sub-talents.

**Sub-talents:**
| Talent | Effect |
|--------|--------|
| `adamant_forceful_toughness_regen_per_stack` | +0.5% toughness per stack |
| `adamant_forceful_stun_immune_and_block_all` | At max stacks: stun immune + block all (3s linger) |
| `adamant_forceful_ranged` | Per-stack conditional: +2.5% ranged attack speed, +2% reload speed (at 10 stacks: +25%/+20%) |
| `adamant_forceful_ability_damage` | Using combat ability at max stacks: +2.5% power for 12s |
| `adamant_forceful_stagger_on_low_high` | At 0 stacks: stagger burst. At 10 stacks: stagger burst. 5s ICD |
| `adamant_forceful_offensive` | At max stacks: +10% attack speed, +50% cleave for 3s |

**Bot usage notes:** Passive keystone, no special activation needed. Stacks build naturally from the Arbites' frontline playstyle (blocking + staggering). Bot benefits automatically.

### 2. Stance Dance (Weapon Swap Keystone) -- `adamant_stance_dance`

**Core mechanic:** Alternating between melee and ranged weapons grants buffs. After swapping to melee:
- +15% melee damage
- +10% melee attack speed
- +15% toughness shared to coherency

After swapping to ranged:
- +15% ranged damage
- +50% suppression dealt
- +10% shared power

Buffs last 5s after each swap.

**Sub-talents:**
| Talent | Effect |
|--------|--------|
| `adamant_stance_dance_elite_kills` | Elite kills: +15% DR, +10% crit chance for 5s |
| `adamant_stance_dance_reload_speed` | After swap: +15% fire rate, +20% reload speed for 5s |
| `adamant_stance_dance_cleave` | After 3+ hits: +75% cleave for 5s |
| `adamant_stance_dance_weakspots` | After swap: +15% power, +25% crit damage, +25% weakspot damage |

**Bot usage notes:** Requires frequent weapon swapping to maintain buffs. Bot would need custom swap logic to maximize this keystone. Most effective when bot alternates melee/ranged regularly.

### 3. Terminus Warrant (Stacking Keystone) -- `adamant_terminus_warrant`

**Core mechanic:** Build stacks (max 30) by fighting. Stacks grant different bonuses based on weapon type:

**Melee stacks give:**
- +15% melee damage
- +15% melee cleave
- +25% melee impact
- +15% melee attack speed

**Ranged stacks give:**
- +15% ranged damage
- +50% suppression dealt
- +50% ranged hit mass modifier
- +15% fire rate, +20% reload speed

Swapping weapons converts 15 stacks to the new weapon type. Stacks last 8s.

**Sub-talents:**
| Talent | Effect |
|--------|--------|
| `adamant_terminus_warrant_upgrade` | Swap converts up to 30 stacks (instead of 15). +15% attack speed/fire rate. |
| `adamant_terminus_warrant_ranged` | +20% reload speed, +10 bonus stacks on ranged swap |
| `adamant_terminus_warrant_melee` | Melee kills restore 100% toughness, +10 bonus stacks on melee swap, 25% toughness shared |
| `adamant_terminus_warrant_improved` | +15% melee/ranged rending, +25% crit damage, +25% weakspot damage, swap grants 30 stacks |

**Bot usage notes:** Like Stance Dance, benefits from weapon swapping. The stack system is more forgiving -- stacks accumulate from combat and transfer on swap.

### 4. Exterminator (Mark & Execute) -- `adamant_exterminator`

**Core mechanic:** Passively marks enemies (via `adamant_mark_enemies_passive`). Marked enemies take bonus damage. Companion and player damage against marked targets triggers execution bonuses.

Stacks: max 10, duration 12s. Each stack: +4% damage, +4% companion damage.

**Sub-talents:**
| Talent | Effect |
|--------|--------|
| `adamant_exterminator_toughness` | Marked kills restore 10% toughness |
| `adamant_exterminator_boss_damage` | +4% boss damage per stack |
| `adamant_exterminator_ability_cooldown` | 25% CDR from marked kills |
| `adamant_exterminator_stack_during_activation` | Gain 2 stacks on combat ability use |
| `adamant_exterminator_stamina_ammo` | Marked kills restore 10% stamina and 10% ammo |

### 5. Execution Order (Advanced Mark & Execute) -- `adamant_execution_order`

**Core mechanic:** An upgrade/extension of Exterminator. Automatically marks the nearest visible enemy. Killing marked targets grants:
- +15% toughness (instant)
- +10% damage for 8s
- +10% attack speed for 8s
- +150% companion damage for 8s

**Sub-talents:**
| Talent | Effect |
|--------|--------|
| `adamant_execution_order_crit` | +10% crit chance, +25% crit damage for 8s |
| `adamant_execution_order_rending` | +10% rending for 8s |
| `adamant_execution_order_cdr` | +50% combat ability CDR while kill buff is active (8s window) |
| `adamant_execution_order_permastack` | Permanent stacks (max 30): +1% damage vs monsters, +1% monster DR per stack |
| `adamant_execution_order_monster_debuff` | Companion hits on monsters debuff them: -25% melee damage |
| `adamant_execution_order_ally_toughness` | Allied kills on marked targets restore 10% toughness |

**Bot usage notes:** Execution Order is the strongest keystone for Cyber-Mastiff builds. The marking is automatic (broadphase scan every update tick, 40m range). Bot just needs to kill marked targets. The +150% companion damage is additive and massive.

---

## Talent Tree Summary (Grouped by Function)

### Toughness Recovery
| Talent | Effect |
|--------|--------|
| `adamant_close_kills_restore_toughness` | Close-range kills: +5% toughness |
| `adamant_staggers_replenish_toughness` | Staggering enemies: +10% toughness |
| `adamant_elite_special_kills_replenish_toughness` | Elite/special kills: +10% instant + 2.5%/s for 4s |
| `adamant_dog_kills_replenish_toughness` | Companion kills: +5%/s for 5s (25% total) |
| `adamant_toughness_regen_near_companion` | 5%/s toughness when within 8m of companion |
| `adamant_restore_toughness_to_allies_on_combat_ability` | Combat ability restores 20% toughness to allies |

### Damage / Offense
| Talent | Effect |
|--------|--------|
| `adamant_elite_special_kills_offensive_boost` | Elite/special kills: +10% damage, +10% move speed for 4s |
| `adamant_damage_after_reloading` | After reload: +15% ranged damage for 5s |
| `adamant_multiple_hits_attack_speed` | 3+ hits: +10% melee attack speed for 3s |
| `adamant_heavy_attacks_increase_damage` | Heavy attacks: +15% damage for 5s |
| `adamant_increased_damage_vs_horde` | +20% damage vs horde enemies |
| `adamant_crit_chance_on_kill` | +2% crit chance on kill, 10s, max 8 stacks |
| `adamant_crits_rend` | Crits apply +20% rending |
| `adamant_melee_attacks_on_staggered_rend` | Melee vs staggered: +15% rending |
| `adamant_cleave_after_push` | After push: +75% cleave for 5s |
| `adamant_wield_speed_on_melee_kill` | Melee kills: +5% wield speed per stack, max 5, 8s |

### Defense / Survivability
| Talent | Effect |
|--------|--------|
| `adamant_staggers_reduce_damage_taken` | Stagger grants DR stacks: 3% per stack, max 5, 8s |
| `adamant_perfect_block_damage_boost` | Perfect block: +15% damage, +15% attack speed, -15% block cost, 8s |
| `adamant_damage_reduction_after_elite_kill` | Elite kill: 25% DR for 5s |
| `adamant_limit_dmg_taken_from_hits` | Cap damage per hit at 50 |
| `adamant_shield_plates` | Blocking restores 15% toughness (10% on perfect), 3s duration, 1s ICD |
| `adamant_hitting_multiple_gives_tdr` | 3+ enemies hit: 20% TDR for 5s |

### Equipment Passive Nodes
| Talent | Effect |
|--------|--------|
| `adamant_armor` | +25 max toughness |
| `adamant_plasteel_plates` | +25 max toughness |
| `adamant_mag_strips` | +25% wield speed |
| `adamant_verispex` | +25m tag range |
| `adamant_ammo_belt` | +25% ammo reserve |
| `adamant_rebreather` | -20% corruption, -75% toxic gas damage |
| `adamant_riot_pads` | 5 stacks of hit immunity, 5s cooldown |
| `adamant_gutter_forged` | +15% TDR, -10% movement speed |
| `adamant_no_movement_penalty` | -50% weapon movement penalty |

### Companion (Cyber-Mastiff)
| Talent | Effect |
|--------|--------|
| `adamant_dog_attacks_electrocute` | Dog attacks electrocute for 5s |
| `adamant_dog_pounces_bleed_nearby` | Dog pounces apply 6 bleed stacks to nearby |
| `adamant_dog_applies_brittleness` | Dog applies 6 brittleness stacks |
| `adamant_dog_damage_after_ability` | +50% companion damage for 12s after combat ability |
| `adamant_companion_focus_melee` | Companion focuses melee targets, +25% damage |
| `adamant_companion_focus_ranged` | Companion focuses ranged targets, +50% damage |
| `adamant_companion_focus_elite` | Companion focuses elites, +25% damage |

---

## Practical Usage (from Community Guides)

### When to Use Combat Ability

- **Nuncio-Aquila (base/improved)**: Deploy at hold positions. The damage amp zone benefits the whole team. With improved talents, it provides suppression immunity -- critical for ranged play. 60s cooldown means you should save it for key holdouts.
- **Charge**: With only 20s cooldown, use aggressively. Good for closing distance to specials, repositioning, or escaping. The blocking-during-charge makes it safe. Post-charge damage buff (+25%) encourages using it offensively before a fight.
- **Castigator's Stance**: The 80% damage reduction + full toughness refill makes this a powerful defensive tool. Best used when holding a position or tanking a boss. The `no_sprint` keyword means you commit to standing your ground. Pair with companion damage talents for synergy.

### When to Use Blitz

- **Grenades (frag)**: Standard use against dense packs. 3-4 charges means you can be liberal.
- **Whistle (Remote Detonation)**: Best blitz for Cyber-Mastiff builds. Direct the dog to priority targets. The electric discharge provides AoE stagger. Use on specials, elites, or to interrupt dangerous enemies. Incompatible with Lone Wolf.
- **Shock Mine**: Place at choke points or flanking routes. Niche but effective in defense missions.

### Positioning / Priority Tips

- The Arbites excels at frontline control. Shield weapons + companion create a strong defensive line.
- Execution Order is the strongest keystone for overall builds -- the +150% companion damage is additive (not multiplicative), making it by far the highest single-node damage value.
- "Lone Wolf" (disable companion) is surprisingly strong -- +10% damage, +15% TDR, +10% attack speed with self-replenishing grenades.
- Toughness recovery is the Arbites' bread and butter. "Up Close" (close kills restore toughness) and "Force of Will" (stagger replenishes toughness) are near-universal picks.
- The Arbites Shotpistol's secondary fire (shield brace) allows shooting while blocking -- unique weapon synergy for defensive play.

### Sources

- [Darktide Arbites Class Overview](https://darktide.gameslantern.com/classes/arbites)
- [Full Arbites Guide](https://darktide.gameslantern.com/user/nrgaa/guide/full-arbites-guide)
- [Best Arbites Build - PC Gamer](https://www.pcgamer.com/games/fps/warhammer-40k-darktide-arbites-build-best/)
- [Fatshark Dev Blog: Arbites Talent Tree](https://www.playdarktide.com/news/dev-blog-arbites-talent-tree)
- [Arbites Builds Database](https://darktide.gameslantern.com/builds/arbites)

---

## Key Source Files

| File | Contents |
|------|----------|
| `scripts/settings/archetype/archetypes/adamant_archetype.lua` | Archetype definition, base stats, base talents |
| `scripts/settings/ability/player_abilities/abilities/adamant_abilities.lua` | All ability definitions (cooldowns, charges, types) |
| `scripts/settings/ability/ability_templates/adamant_charge.lua` | Charge ability template (inputs, actions) |
| `scripts/settings/ability/ability_templates/adamant_shout.lua` | Shout ability template (inputs, actions) |
| `scripts/settings/ability/ability_templates/adamant_stance.lua` | Stance ability template (inputs, actions, **has ability_meta_data**) |
| `scripts/settings/ability/ability_templates/adamant_whistle.lua` | Whistle/companion command template |
| `scripts/settings/talent/talent_settings_adamant.lua` | All numerical values (cooldowns, percentages, durations) |
| `scripts/settings/ability/archetype_talents/talents/adamant_talents.lua` | Full talent tree definitions |
| `scripts/settings/buff/archetype_buff_templates/adamant_buff_templates.lua` | All buff implementations |
| `scripts/settings/lunge/adamant_lunge_templates.lua` | Charge lunge physics/behavior |
| `scripts/settings/ability/shout_target_templates.lua` | Shout target configs (stagger, damage, ally effects) |
| `scripts/ui/views/talent_builder_view/layouts/adamant_tree.lua` | Talent tree layout (node positions, exclusive groups, parent/child links) |
