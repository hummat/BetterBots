# Psyker (Psykinetic)

## Overview

The Psyker is Darktide's "mage" archetype. Health: 150. Base crit chance: 7.5%. The class revolves around the **Peril of the Warp** (warp charge) mechanic: using warp-powered abilities and weapons generates Peril, and hitting 100% causes a warp explosion that knocks the Psyker down. Managing Peril is the class's central tension -- powerful abilities cost Peril, and venting Peril costs health.

The Psyker has access to three combat abilities (F key), three blitz abilities (grenade slot), three auras, and three keystones, chosen via the talent tree. The three tree paths roughly correspond to:

- **Left path (Biomancer / Warp Siphon)**: Soulblaze/Warpfire focus, Souls mechanic, Venting Shriek combat ability
- **Middle path (Protectorate / Empowered Psionics)**: Chain Lightning blitz, Telekine Shield combat ability, empowered blitz procs
- **Right path (Gunslinger / Disrupt Destiny)**: Crit-focused, Scrier's Gaze combat ability, weapon cycling, mark mechanic

Archetype file: `scripts/settings/archetype/archetypes/psyker_archetype.lua`
Talent settings: `scripts/settings/talent/talent_settings_psyker.lua`
Talent definitions: `scripts/settings/ability/archetype_talents/talents/psyker_talents.lua`
Player abilities: `scripts/settings/ability/player_abilities/abilities/psyker_abilities.lua`

---

## Peril of the Warp (Warp Charge System)

Source: `scripts/settings/warp_charge/archetype_warp_charge_templates.lua`

| Parameter | Value |
|---|---|
| Auto-vent delay | 3s (after last warp action) |
| Auto-vent duration | 12s (time to fully auto-vent) |
| Low threshold | 30% |
| High threshold | 50% |
| Critical threshold | 97% |
| Extreme / Explode threshold | 97% |
| Manual vent duration | 2.9s (full vent) |
| Manual vent interval | 0.25s |
| Vent self-damage | 0-8 power level (scales with Peril) |

**Decay rates** (Peril per second, auto-vent):
- Low (<30%): 1.0/s
- High (30-50%): 0.9/s
- Critical (>97%): 0.7/s

**Bot usage notes**: Bots must manage Peril proactively. At >80% Peril, a bot should stop using warp abilities and either vent manually or wait for auto-vent. At >97% the bot risks explosion. Venting deals self-damage, so it should be avoided when health is critically low.

---

## Combat Abilities (F Key)

The Psyker's base combat ability is **Venting Shriek**. Two alternatives can be selected in the talent tree: **Scrier's Gaze** (right path) and **Telekine Shield** (middle path).

### 1. Venting Shriek (Psyonic Discharge)

**Internal names**: `psyker_discharge_shout` (base), `psyker_discharge_shout_improved` (with vent talent)
**Ability template**: `psyker_shout` (`scripts/settings/ability/ability_templates/psyker_shout.lua`)
**Ability group**: `psyker_shout`
**Ability type**: `combat_ability`
**Talent key**: `psyker_combat_ability_shout` (base talent, always available)

| Parameter | Value |
|---|---|
| Cooldown | 30s |
| Max charges | 1 |
| Power level | 500 |
| Shout range | 30m |
| Shout shape | Cone (in front of Psyker) |
| Warp charge vent (base) | 10% |
| Warp charge vent (improved) | 50% |

**Input actions**:
- `combat_ability_pressed` -> `shout_pressed` (start aim phase)
- `combat_ability_hold` release -> `shout_released` (fire the shout)
- Can be block-cancelled with `action_two_pressed` while holding

**Action sequence**: Press F -> aim phase (hold) -> release F -> shout fires. Minimum hold time: 0.075s. The shout hits both enemies and allies in a cone. Animation: `ability_shout`, total time 0.75s, uninterruptible. Uses charge at start.

**What it does**: Knocks down enemies in a cone in front of the Psyker. Applies the `psyker_biomancer_shout` damage profile. Vents 10% Peril (base) or 50% Peril (with `psyker_shout_vent_warp_charge` talent).

**Key modifying talents**:
- `psyker_shout_vent_warp_charge`: Increases vent to 50%, swaps to `psyker_discharge_shout_improved`
- `psyker_shout_reduces_warp_charge_generation`: After shout, reduces warp charge generation temporarily
- `psyker_shout_damage_per_warp_charge`: Shout deals damage scaled by current Peril
- `psyker_discharge_damage_debuff`: Hit enemies take 10% more damage for 8s, deal 10% less damage
- `psyker_warpfire_on_shout`: Applies Soulblaze/Warpfire stacks to hit enemies (1 to max, scaled by Peril)
- `psyker_warpfire_generate_souls`: Warpfire kills can grant Souls
- `psyker_souls_restore_cooldown_on_ability`: Consuming Souls on ability use reduces cooldown by 7.5% per Soul (max 2 Souls consumed)
- `psyker_ability_increase_brain_burst_speed`: For 10s after using ability, Brain Burst charges 75% faster and costs 50% less Peril

**Bot usage notes**: Venting Shriek is the most bot-friendly combat ability. Use when:
- Surrounded by enemies (knockdown provides breathing room)
- Peril is high and needs venting (especially with improved vent talent)
- Groups of enemies in front (cone AoE)
- Before boss/elite engagement to apply damage debuff (if talented)
- On cooldown, do not hold in reserve too long -- 30s CD is relatively short

### 2. Scrier's Gaze (Overcharge Stance)

**Internal name**: `psyker_overcharge_stance`
**Ability template**: `psyker_overcharge_stance` (`scripts/settings/ability/ability_templates/psyker_overcharge_stance.lua`)
**Ability group**: `psyker_overcharge_stance`
**Ability type**: `combat_ability`
**Talent key**: `psyker_combat_ability_stance`

| Parameter | Value |
|---|---|
| Cooldown | 25s |
| Max charges | 1 |
| Post-stance buff duration | 10s |
| Venting on activation | 50% Peril |
| Base damage bonus | 10% |
| Damage per weakspot stack | 1% |
| Finesse damage per stack | 1% |
| Max stacks | 30 |
| Crit chance bonus | 20% |
| Cooloff duration | 1.5s |

**Input actions**:
- `combat_ability_pressed` -> `stance_pressed` (instant activation)
- Buffer time: 0.5s

**Action sequence**: Single press of F. Animation: `ability_overcharge`, total time 1.0s, uninterruptible. Uses charge at start. Activates the `psyker_overcharge_stance` buff. Vents 50% Peril on activation.

**What it does**: Enters an empowered stance that grants +10% damage, +20% crit chance, and +weakspot damage. While active, Peril continually builds. Reaching 100% Peril ends the stance. Weakspot kills during stance grant stacking finesse damage (+1% per kill, up to 30 stacks). Stacks persist for 10s after stance ends. Cooldown does not start until the stance buff expires.

**Special rule**: `psyker_overcharge_stance_quell_peril` -- allows quelling Peril during stance.

**Key modifying talents**:
- `psyker_overcharge_reduced_warp_charge`: Reduced Peril generation during stance, increased vent speed
- `psyker_overcharge_stance_infinite_casting`: No Peril cap during stance (cannot explode)
- `psyker_overcharge_reduced_toughness_damage_taken`: Reduced toughness damage during stance
- `psyker_overcharge_increased_movement_speed`: Increased movement speed during stance
- `psyker_overcharge_weakspot_kill_bonuses`: Weakspot kills grant stacking finesse damage per kill

**Bot usage notes**: Scrier's Gaze is harder for bots to use optimally. Recommended behavior:
- Activate before engaging elites/bosses for the damage/crit buff
- Simple activation pattern (single press, stance type)
- Bot must monitor Peril during stance and be ready to vent or let stance expire
- Best for ranged-focused bot builds where Peril generation is lower
- 25s cooldown is the shortest of the three combat abilities

### 3. Telekine Shield / Dome

**Internal names**: `psyker_force_field` (wall), `psyker_force_field_improved` (wall + reduced CD), `psyker_force_field_dome` (sphere)
**Ability group**: `psyker_shield`
**Ability type**: `combat_ability`
**Talent key**: `psyker_combat_ability_force_field`

| Parameter | Value |
|---|---|
| Cooldown (base) | 45s |
| Cooldown (improved, with extra charge talent) | 35s |
| Max charges (base) | 1 |
| Duration (wall) | 17.5s |
| Duration (dome) | 25s |
| Sphere health | 20 |
| Toughness for allies inside | 10% per tick |
| Toughness damage reduction | 50% |
| Toughness DR duration (after leaving) | 5s |
| Damage cooldown (per hit absorbed) | 0.33s |

**Input actions**: This is an **item-based ability** -- it wields `content/items/weapons/player/psyker_shield` (or `psyker_shield_dome`). No `ability_template` field. Activation is through the inventory/wield system rather than action inputs.

**What it does**: Deploys a psychic shield (wall in front, or dome around the Psyker depending on talent). Blocks enemy ranged attacks while allies can shoot through it. Allies inside get toughness regeneration and toughness damage reduction.

**Key modifying talents**:
- `psyker_shield_extra_charge`: +1 charge, reduced cooldown to 35s
- `psyker_sphere_shield`: Shield becomes a dome centered on Psyker (25s duration)
- `psyker_boost_allies_in_sphere`: Allies inside gain 50% toughness DR, 10% toughness on use, buff for 5s after leaving
- `psyker_boost_allies_passing_through_force_field`: Allies passing through gain movement speed and toughness DR for 6s
- `psyker_shield_stun_passive`: 20% chance to stun enemies passing through (100% for specials)

**Bot usage notes**: Telekine Shield is the hardest ability for bots. It requires:
- Positional awareness (deploying wall facing the right direction)
- It is item-based (no `ability_template`, wielded like a weapon) making it **Tier 3 difficulty for bot implementation**
- Dome variant is somewhat simpler (centered on self, no aiming needed)
- Best deployed when team is under heavy ranged fire or holding a chokepoint
- Long cooldown (45s) means mistimed deployment is costly

---

## Blitz Abilities (Grenade Slot)

The Psyker's base blitz is **Brain Burst (Smite)**. Two alternatives: **Assail (Throwing Knives)** and **Chain Lightning**.

### 1. Brain Burst / Smite

**Internal name**: `psyker_smite`
**Ability type**: `grenade_ability`
**Talent key**: `psyker_grenade_smite` (base talent)
**Inventory item**: `content/items/weapons/player/psyker_smite`

| Parameter | Value |
|---|---|
| Max charges | 0 (unlimited, costs Peril) |
| Cooldown | None (Peril-gated) |

**What it does**: Wield the Smite "weapon" -- target an enemy and charge up a psychic attack that deals massive single-target damage. Effective for killing elites and specials at range. High Peril cost per use.

**Key modifying talents**:
- `psyker_brain_burst_improved`: Increased Brain Burst damage
- `psyker_smite_on_hit`: All attacks have a chance to auto-Smite the target (100% chance vs specials/elites, 12s cooldown)
- `psyker_ability_increase_brain_burst_speed`: After combat ability, Smite charges 75% faster and costs 50% less Peril for 10s
- `psyker_empowered_ability` (keystone): Empowered Smite costs 0% Peril, has increased attack speed and damage

**Bot usage notes**: Brain Burst is the most straightforward blitz for bots.
- Item-based ability (wielded like weapon), so it requires wield/aim/fire sequence
- Use against elites, specials, and bosses (high single-target damage)
- Bot must track Peril -- each use adds significant Peril
- Do not use when Peril is above ~80%
- Prioritize: Snipers > Specials > Elites > Monsters
- **Tier 3 for bot implementation** (item-based, no `ability_template`)

### 2. Assail (Throwing Knives)

**Internal name**: `psyker_throwing_knives`
**Ability type**: `grenade_ability`
**Talent key**: `psyker_grenade_throwing_knives`
**Inventory item**: `content/items/weapons/player/psyker_throwing_knives`

| Parameter | Value |
|---|---|
| Max charges | 10 |
| Cooldown (recharge per knife) | 3s |
| Can be wielded when depleted | Yes |

**What it does**: Throws homing psychic daggers that track enemies. Self-regenerating ammo (10 charges, 3s per charge). Less effective vs Carapace armor. The knives home in on targets near the crosshair.

**Key modifying talents**:
- `psyker_throwing_knives_piercing`: Knives pierce through enemies
- `psyker_throwing_knives_cast_speed`: Increased throw speed and reduced cooldown per knife
- `psyker_throwing_knives_combat_ability_recharge`: Using combat ability restores 5 knife charges
- `psyker_empowered_ability` (keystone): Empowered Assail costs 0 ammo, uses a piercing damage profile

**Special rule**: `disable_grenade_pickups` -- cannot pick up grenades (knives replace grenades entirely).

**Bot usage notes**: Assail is moderately bot-friendly.
- Item-based (wielded), same Tier 3 challenge as Brain Burst
- Homing behavior makes aiming less critical
- Finite charges (10) require charge management
- Use against specials and ranged threats
- Good for softening groups before melee engagement
- No Peril cost (charge-based instead)

### 3. Chain Lightning

**Internal name**: `psyker_chain_lightning`
**Ability type**: `grenade_ability`
**Talent key**: `psyker_grenade_chain_lightning`
**Inventory item**: `content/items/weapons/player/psyker_chain_lightning`

| Parameter | Value |
|---|---|
| Max charges | 0 (unlimited, costs Peril) |
| Cooldown | 1s |
| Default power level | 500 |
| Stun interval | 0.3-0.8s |
| On-hit proc chance | 15% |

**What it does**: Wield Chain Lightning weapon. Left-click for a quick lightning attack; right-click + hold to charge a more powerful chain lightning that jumps between enemies. Excellent crowd control -- stunlocks groups of enemies. Empowered versions deal +200% damage and have increased jump speed.

**Key modifying talents**:
- `psyker_increased_chain_lightning_size`: +1 max jumps for chain lightning spread
- `psyker_chain_lightning_improved_target_buff`: Targets hit take increased damage from all sources
- `psyker_empowered_grenades_increased_max_stacks`: Can store up to 3 empowered charges
- `psyker_chain_lightning_heavy_attacks`: Heavy melee attacks electrocute enemies
- `psyker_empowered_ability` (keystone): Empowered Chain Lightning has +200% damage and faster jump speed

**Passive buffs included with this blitz**:
- `psyker_kills_during_smite_tracking`
- `psyker_increased_chain_lightning_size`

**Bot usage notes**: Chain Lightning is the best crowd-control blitz.
- Item-based (wielded), Tier 3 implementation
- Use charged (right-click) for maximum crowd control
- Stunlocks groups of enemies -- excellent for protecting teammates
- Costs Peril, so same Peril management concerns as Brain Burst
- Best used when team is being overwhelmed by hordes
- Quick attack (left-click) good for single targets or quick stuns

---

## Auras

Three aura choices, mutually exclusive (all share `identifier = "psyker_aura"`). The base aura is **Seer's Presence** (ability cooldown reduction).

### 1. Seer's Presence (Ability Cooldown Reduction)

**Internal name**: `psyker_aura_ability_cooldown`
**Buff template**: `psyker_aura_ability_cooldown`
**Base talent**: Yes (in `base_talents`)

| Parameter | Value |
|---|---|
| Ability cooldown modifier | -7.5% |

**What it does**: All allies in coherency get 7.5% ability cooldown reduction.

**Improved version** (`psyker_cooldown_aura_improved`): Increases to -10% cooldown reduction. Uses `psyker_aura_ability_cooldown_improved` buff. Priority 2 (overrides base).

### 2. Kinetic Presence (Damage vs Elites)

**Internal name**: `psyker_aura_damage_vs_elites`
**Buff template**: `psyker_aura_damage_vs_elites`
**Talent**: `psyker_aura_damage_vs_elites`

| Parameter | Value |
|---|---|
| Damage vs elites | +10% |

**What it does**: All allies in coherency deal 10% more damage to elites and specials.

### 3. Gunslinger Aura (Crit Chance)

**Internal name**: `psyker_aura_crit_chance_aura`
**Buff template**: `psyker_aura_crit_chance_aura`
**Talent**: `psyker_aura_crit_chance_aura`

**What it does**: Allies in coherency gain critical strike chance (exact value defined in buff template).

**Bot usage notes**: Auras are passive and always active. No bot action needed. The choice affects team composition -- for bots, Kinetic Presence (+10% damage vs elites) is the most universally useful.

---

## Keystones

Three keystones, mutually exclusive (`exclusive_group = "keystone"`). Located at the bottom of the talent tree (y=2330).

### 1. Warp Siphon (Souls)

**Internal name**: `psyker_passive_souls_from_elite_kills`
**Icon**: `psyker_keystone_warp_syphon`

**What it does**: Killing enemies grants "Souls" (stacks). Each Soul:
- Reduces next combat ability cooldown by 7.5%
- Increases damage by 4% per Soul (at 6 max Souls = 24% damage)
- Souls last 25 seconds, base max 4 (upgradeable to 6)

**Modifier talents** (children of keystone):
- `psyker_increased_max_souls`: Max Souls increased to 6
- `psyker_spread_warpfire_on_kill`: Warpfire deaths spread 4 stacks to nearby enemies
- `psyker_reduced_warp_charge_cost_and_venting_speed`: Reduced Peril generation per Soul (8% per Soul at 6 Souls = 48%)
- `psyker_souls_increase_damage`: +4% damage per Soul

**Bot usage notes**: Warp Siphon is passive -- bot just needs to kill enemies to gain Souls. The Soul-based cooldown reduction incentivizes using combat ability (Venting Shriek) frequently to consume Souls. Works well for bot builds focused on ability cycling.

### 2. Empowered Psionics

**Internal name**: `psyker_empowered_ability`
**Icon**: `psyker_keystone_empowered_psyche`

**What it does**: Kills have a chance to "empower" the next blitz ability:
- **Empowered Brain Burst**: 0% Peril cost, increased attack speed, increased damage
- **Empowered Chain Lightning**: +200% damage, faster chain jump speed
- **Empowered Assail**: 0 ammo cost, uses piercing damage profile
- Base proc chance: ~15% on kill

**Modifier talents**:
- `psyker_empowered_grenades_increased_max_stacks`: Can store up to 3 empowered charges
- `psyker_empowered_grenades_passive_improved`: Increased proc chance
- `psyker_empowered_ability_on_elite_kills`: Elite kills guarantee empowered proc
- `psyker_empowered_chain_lightnings_replenish_toughness_to_allies`: Empowered blitz restores 20% toughness to allies in coherency

**Bot usage notes**: Also partially passive (procs stack automatically). Bot should:
- Prioritize using blitz when empowered charges are available (free/enhanced abilities)
- Track empowered state and use blitz immediately when available
- Pairs well with Chain Lightning for crowd control or Brain Burst for elite deletion

### 3. Disrupt Destiny (Mark Enemies)

**Internal name**: `psyker_new_mark_passive`
**Icon**: `psyker_keystone_unnatural_talent`

**What it does**: Automatically marks nearby enemies. Killing marked enemies grants:
- Toughness regeneration
- Movement speed buff
- Stacking damage, crit damage, and weakspot damage bonuses

**Modifier talents**:
- `psyker_mark_increased_range`: Increased mark detection range
- `psyker_mark_increased_max_stacks`: More bonus stacks from marked kills
- `psyker_mark_increased_duration`: Longer duration on damage bonuses
- `psyker_mark_increased_mark_targets`: Mark more targets simultaneously
- `psyker_mark_kills_can_vent`: Marked kills can vent Peril
- `psyker_mark_weakspot_kills`: Weakspot kills on marked enemies grant extra stacks

**Bot usage notes**: Disrupt Destiny is fully passive -- marks appear automatically, bonuses trigger on kills. The bot gains value just by killing marked targets (no active decision needed). Works well for weapon-focused bot builds.

---

## Talent Tree Summary

### Shared / Universal Nodes (Top of Tree)

**Toughness regeneration** (first row, pick one):
- `psyker_toughness_on_warp_kill`: 7.5% toughness on warp kills
- `psyker_toughness_on_vent`: 4% toughness per 10% Peril vented (also 4% on warp generation)
- `psyker_toughness_on_melee`: 15% toughness over 3s on melee hit, 2.5% instant
- `psyker_warp_charge_generation_generates_toughness`: 2.5% toughness per 10% Peril generated

**Blitz selection** (pick one):
- `psyker_grenade_smite` (Brain Burst) -- base, always available
- `psyker_grenade_throwing_knives` (Assail) -- left/center path
- `psyker_grenade_chain_lightning` (Chain Lightning) -- center/right path

**Blitz modifiers**:
- `psyker_brain_burst_improved`: +damage to Brain Burst
- `psyker_throwing_knives_piercing`: Knives pierce enemies
- `psyker_throwing_knives_cast_speed`: Faster throw, reduced recharge
- `psyker_throwing_knives_combat_ability_recharge`: Combat ability restores 5 knives
- `psyker_chain_lightning_improved_target_buff`: Targets hit take more damage
- `psyker_increased_chain_lightning_size`: +1 chain lightning jumps
- `psyker_smite_on_hit`: Attacks randomly trigger Brain Burst (12s CD)

**Aura selection** (pick one):
- `psyker_aura_ability_cooldown` (Seer's Presence) -- base
- `psyker_aura_damage_vs_elites` (Kinetic Presence)
- `psyker_aura_crit_chance_aura` (Gunslinger Aura)

### Left Path (Biomancer / Soulblaze Focus)

Key talents:
- `psyker_chance_to_vent_on_kill`: 10% chance on kill to reduce Peril by 10%
- `psyker_damage_based_on_warp_charge`: Up to +20% damage based on current Peril
- `psyker_block_costs_warp_charge`: Blocking costs Peril instead of stamina (25% rate)
- `psyker_warp_charge_reduces_toughness_damage_taken`: Reduced toughness damage based on Peril (10-33%)
- `psyker_elite_kills_add_warpfire`: Elite/special kills apply 3 Soulblaze stacks nearby
- `psyker_venting_improvements`: Venting no longer slows movement, reloading doesn't slow
- `psyker_aura_souls_on_kill`: Coherency kills have 4% chance to grant a Soul
- `psyker_2_tier_3_name_2`: Elite kills restore 60% combat ability cooldown to allies (5s CD)
- `psyker_2_tier_3_name_3`: Smite-damaged enemies take 25% more damage for 5s

### Middle Path (Protectorate / Support)

Key talents:
- `psyker_increased_vent_speed`: +30% venting speed
- `psyker_aura_toughness_on_ally_knocked_down`: Fully restore toughness to allies when any ally goes down
- `psyker_boost_allies_in_sphere`: Shield allies get 50% toughness DR, 10% toughness
- `psyker_boost_allies_passing_through_force_field`: Allies passing through shield get movement speed + toughness DR for 6s
- `psyker_shield_stun_passive`: 20% chance to stun enemies passing through shield (100% for specials)
- `psyker_shield_extra_charge`: +1 shield charge, reduced cooldown (35s)
- `psyker_sphere_shield`: Shield becomes a dome centered on Psyker (25s duration)

### Right Path (Gunslinger / Crit Focus)

Key talents:
- `psyker_guaranteed_crit_on_multiple_weakspot_hits`: Multiple weakspot hits guarantee next crit
- `psyker_kills_stack_other_weapon_damage`: Kills with one weapon type buff the other (cycling bonus)
- `psyker_crits_empower_next_attack`: Crits grant stacking damage buff
- `psyker_dodge_after_crits`: Crits grant bonus dodge
- `psyker_crits_regen_toughness_movement_speed`: Crits restore 10% toughness + 5% movement speed (3 stacks, 4s)
- `psyker_improved_dodge`: Better dodge distance and extra consecutive dodges
- `psyker_coherency_aura_size_increase`: Increased coherency radius

### Flexible / Mixed Talents (Available from multiple paths)

- `psyker_melee_attack_speed`: +10% melee attack speed
- `psyker_cleave_from_peril`: Up to +100% cleave based on Peril
- `psyker_blocking_soulblaze`: Push applies 1 Soulblaze stack
- `psyker_melee_weaving`: Melee hits vent 10% Peril, reduce warp generation by 20% for 4s
- `psyker_warp_attacks_rending`: Warp attacks gain 20% Rending above 75% Peril
- `psyker_warp_glass_cannon`: Reduced Peril generation (-40%), but reduced toughness regen (-30%)
- `psyker_soulblaze_reduces_damage_taken`: Applying Soulblaze reduces toughness damage taken
- `psyker_ranged_crits_vent`: Ranged crits vent 4% Peril
- `psyker_reload_speed_warp_charge`: +30% reload speed, costs 15% Peril (above 75% threshold)
- `psyker_alternative_peril_explosion`: Peril explosions no longer knock you down, +100% explosion damage, +25% explosion radius
- `psyker_damage_to_peril_conversion`: Convert 25% of health damage to Peril instead
- `psyker_damage_resistance_stun_immunity`: 90% damage resistance + stun immunity for 4s on Peril explosion
- `psyker_stat_mix`: +2 stamina, -80% Peril decay speed, +25% toughness regen
- `psyker_damage_vs_ogryns_and_monsters`: +20% damage vs Ogryn-class and Monsters
- `psyker_force_staff_bonus`: Force Staff secondary buffs primary damage and vice versa
- `psyker_force_staff_quick_attack_bonus`: Force Staff left clicks increase warp damage taken on target
- `psyker_force_staff_wield_speed`: Up to 50% faster Force Staff wield speed based on Peril
- `psyker_chain_lightning_heavy_attacks`: Heavy melee attacks electrocute enemies

---

## Practical Usage (from Community Guides)

### When to Use Combat Abilities

**Venting Shriek**:
- Use at 85%+ Peril to safely vent while dealing damage
- Use when overwhelmed in melee (knockdown + vent combo)
- With Soulblaze talents, 6 stacks are sufficient to kill most ranged enemies
- Goes through walls and cover -- use for enemies behind obstacles
- Best paired with Soulblaze-focused builds

**Scrier's Gaze**:
- Activate before boss fights or elite-dense segments
- Works best with ranged weapon builds (gun Psyker) where Peril generation is lower
- Use the vent-on-activation (50%) to reset Peril before a damage window
- Avoid with Force Staff builds (competing Peril generation)

**Telekine Shield**:
- Deploy when team is under sustained ranged fire
- Hold chokepoints -- allies shoot through, enemies can't
- Dome variant for mobile protection during objectives
- Deploy early in ranged engagements, not as a panic button (long cooldown)

### When to Use Blitz Abilities

**Brain Burst**:
- Priority targets: Snipers > Trappers > other Specials > Elites > Monsters
- One of the best single-target damage abilities in the game
- Effective boss killer, but high Peril cost
- Keep 2-3 Brain Bursts worth of Peril headroom

**Chain Lightning**:
- Use charged (right-click) for maximum stunlock and spread
- Best when team is being swarmed or during horde events
- Stunlocks allow allies to dispatch enemies safely
- Use quick (left-click) for single-target stuns on specials

**Assail**:
- Use liberally due to self-regenerating charges (10 charges, 3s each)
- Homing behavior makes it forgiving for aim
- Less effective vs Carapace armor -- switch to melee for armored targets
- Good for softening approaching groups before melee

### Peril Management Tips

- Auto-vent kicks in after 3s of inactivity -- plan pauses in warp ability use
- Manual venting deals self-damage -- avoid when health is low
- Melee attacks do not generate Peril (use melee to let Peril decay)
- `psyker_melee_weaving` talent vents 10% Peril per melee hit
- At 97%+ Peril, one more warp action causes explosion (1000ms reaction window)
- With `psyker_alternative_peril_explosion`, explosions are survivable but still costly

### Positioning / Priority Tips

- Psyker is squishy (150 HP, lowest alongside Veteran)
- Stay in coherency range for aura benefits and toughness regen
- Use range advantage -- Brain Burst and Chain Lightning work at distance
- In melee, rely on dodge (Psyker gets improved dodge talent)
- Target priority for blitz: Disablers > Ranged specials > Elites > Hordes
- Keep line-of-sight for Brain Burst targeting
- Telekine Shield is most effective at chokepoints and doorways

---

## Summary: Bot Implementation Priority

| Ability | Type | Input Pattern | Difficulty | Notes |
|---|---|---|---|---|
| Venting Shriek | Combat (shout) | shout_pressed -> hold -> shout_released | **Tier 1** (has `ability_template` + `ability_meta_data`) | Best F-ability for bots |
| Scrier's Gaze | Combat (stance) | stance_pressed (instant) | **Tier 1** (has `ability_template` + `ability_meta_data`) | Simple activation |
| Telekine Shield | Combat (item) | Wield item | **Tier 3** (item-based, no `ability_template`) | Needs separate wield logic |
| Brain Burst | Blitz (item) | Wield + aim + hold | **Tier 3** (item-based) | Needs targeting + charge logic |
| Assail | Blitz (item) | Wield + throw | **Tier 3** (item-based) | Homing helps, but still item wield |
| Chain Lightning | Blitz (item) | Wield + click/hold | **Tier 3** (item-based) | Best CC, needs charge logic |
| Auras | Passive | None | **N/A** | Always active, no action needed |
| Keystones | Passive | None | **N/A** | Passive procs, no action needed |

---

*Sources: Decompiled Darktide source (v1.10.7), community guides from [Gamer Guides](https://www.gamerguides.com/warhammer-40000-darktide/guide/classes/psyker), [Darktide GameSlantern](https://darktide.gameslantern.com/builds/psyker), [Steam Community Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3094028505), [Fatshark Forums](https://forums.fatsharkgames.com/t/psyker-talent-tree-assessment-discussion/100668)*
