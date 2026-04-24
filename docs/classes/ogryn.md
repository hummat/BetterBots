# Ogryn (Skullbreaker) - Class Ability Reference

> Last updated: 2026-03-05
> Source: Decompiled Darktide v1.10.7 (Feb 2026) + community guides.
> Purpose: Complete ability mapping for BetterBots mod development.

## Overview

The Ogryn is the melee frontline tank class. Base health 300, base crit chance 2.5%. Innate passive
`ogryn_base_tank_passive` grants 25% toughness damage reduction, 20% health damage reduction, and
immunity to movement-slowing effects (static_movement_reduction_multiplier = 0). Uninterruptible
while reviving allies (`ogryn_helping_hand`). Innate dodge-stagger (`ogryn_dodge_stagger`).

**Archetype base talents** (always active):
- `ogryn_base_tank_passive` -- Tough Skin
- `ogryn_charge` -- Indomitable (default combat ability; internal name "Bull Rush")
- `ogryn_dodge_stagger` -- stagger nearby enemies on dodge
- `ogryn_grenade_box` -- Big Box of Hurt (default blitz)
- `ogryn_helping_hand` -- uninterruptible revives
- `ogryn_melee_damage_coherency` -- aura: +7.5% melee damage in coherency

---

## Combat Ability (F key)

The Ogryn has **three** mutually exclusive combat ability paths selected via the talent tree. All
use `ability_type = "combat_ability"` and are bound to `combat_ability_pressed`.

### 1. Indomitable (Charge path) -- `ogryn_charge`

> **Note:** Internal/decompiled name is "Bull Rush" (`ogryn_charge`). Live UI uses "Indomitable".

**Template:** `ogryn_charge` (ability template), `ogryn_charge` (lunge template)
**Ability group:** `ogryn_charge`
**Input actions:**
- `aim_pressed`: `combat_ability_pressed` (buffer 0.2s) -- begin aiming direction
- `aim_released`: `combat_ability_hold = false` -- release to charge
- `block_cancel`: `action_two_pressed` while holding `combat_ability_hold` -- cancel

**Activation pattern:** Two-step: press F to aim direction, release F (or it auto-releases after
hold) to lunge forward. This is a **charge/dash** type -- not instant.

**Action sequence:**
1. `action_aim` (kind: `directional_dash_aim`) -- player aims charge direction
2. `action_state_change` (kind: `character_state_change`, state: `lunging`) -- executes the charge

**Cooldown:** 30s (from `TalentSettings.ogryn_2.combat_ability.cooldown`)
**Max charges:** 1
**Distance:** 12m (base)
**Charge radius:** 2m hit detection

**Lunge properties:**
- `allow_steering = true`, `sensitivity_modifier = 5`
- `disable_minion_collision = true` -- passes through enemies
- Speed ramp: 0→0s, 4→0.2s, 6→0.3s, 8→0.4s, 10→0.5s (5-step acceleration)
- Stops on: super_armor, void_shield, resistant armor types
- On finish: creates explosion (ExplosionTemplates.ogryn_charge_impact)
- `is_dodging = true` -- grants dodge frames during charge
- `slot_to_wield = "slot_unarmed"` -- switches to unarmed during charge

**Passive buffs granted by default Bull Rush talent:**
- `ogryn_base_lunge_toughness_and_damage_resistance`: While lunging, +50% heavy melee damage, 25% damage reduction
- `ogryn_charge_speed_on_lunge`: On lunge end, grants +25% movement speed and +25% melee attack speed for 5s

**Talent modifier variants:**

| Talent | Mechanism | Changes | Cooldown |
|--------|-----------|---------|----------|
| `ogryn_charge_applies_bleed` | **Pulverise** (buff `ogryn_charge_bleed`, no ability swap) | Applies 5 bleed stacks to hit enemies during lunge | 30s |
| `ogryn_longer_charge` | Augmented **Indomitable** (swaps to `ogryn_charge_increased_distance`) | Distance 24m, only monsters stop the charge (ignores super_armor/resistant), extended timing anim | 30s |
| `ogryn_charge_toughness` | **Stomping Boots** (buff `ogryn_bull_rush_hits_replenish_toughness`, no ability swap) | Restores 10% toughness per enemy hit during charge | 30s |
| `ogryn_charge_trample` | **Trample** (buff `ogryn_charge_trample`, no ability swap) | Each enemy hit during charge grants +2.5% damage buff (stacks to 20, 10s duration, refreshes) | N/A |

> **Note:** `ogryn_charge_bleed`, `ogryn_charge_cooldown_reduction`, and `ogryn_charge_damage` exist
> as player abilities in `ogryn_abilities.lua` with their own lunge templates, but no talent in the
> tree references them. They appear to be orphaned/deprecated ability variants. The actual bleed and
> toughness mechanics are implemented entirely through passive buff templates.

**Bot usage notes:**
- Charge is a directional lunge with a two-step input (aim then release). Bots need to inject both
  `combat_ability_pressed` and then release `combat_ability_hold`.
- Best used to close distance to ranged threats, rescue downed allies, or escape hordes.
- The charge passes through enemies -- ideal for reaching backline specials.
- Stops on super armor by default -- bot should avoid charging directly at Crushers/Maulers unless
  the `ogryn_longer_charge` talent is equipped.
- After charge, the 5s speed/attack buff window is the ideal melee burst window.

---

### 2. Loyal Protector (Taunt Shout) -- `ogryn_taunt_shout`

**Template:** `ogryn_taunt_shout`
**Ability group:** `ogryn_taunt_shout`
**Input actions:**
- `shout_pressed`: `combat_ability_pressed` (buffer 0.2s)
- `shout_released`: `combat_ability_hold = false`
- `block_cancel`: `action_two_pressed` while holding `combat_ability_hold`

**Activation pattern:** Two-step hold-release shout, similar to charge but with shout mechanics.
Press F to begin aiming, release to shout. Minimum hold time 0.075s.

**Action sequence:**
1. `action_aim` (kind: `shout_aim`, radius: 12m) -- shows AoE indicator
2. `action_shout` (kind: `ogryn_shout`) -- executes the shout

**Cooldown:** 50s
**Max charges:** 1
**Radius:** 12m
**Total shout animation:** 0.75s, uninterruptible

**Shout target template** (`ogryn_shout`):
- Applies `taunted` buff to enemies (forces them to target the Ogryn)
- `force_stagger_type = "light"`, `force_stagger_duration = 1`
- `power_level = 500`
- `can_not_taunt`: chaos_daemonhost, chaos_mutator_daemonhost, chaos_mutator_ritualist
- `can_not_hit`: chaos_mutator_daemonhost, chaos_mutator_ritualist (daemonhost CAN be hit/staggered, just not taunted)
- With `ogryn_taunt_damage_taken_increase` talent: also applies `ogryn_taunt_increased_damage_taken_buff` (+20% damage taken, 15s)

**Repeat taunt buff** (`ogryn_repeat_taunt`):
- Duration 6s, pulses taunt again at 3s and at buff expiry (3 total pulses including initial)
- Each pulse re-applies taunt to enemies in radius

**Key modifying talents:**
- `ogryn_taunt_damage_taken_increase`: Taunted enemies take +20% damage from all sources
- `ogryn_taunt_staggers_reduce_cooldown`: Staggering enemies reduces taunt CD by 2.5% per stagger (melee/push only, 0.1s internal CD)
- `ogryn_taunt_radius_increase`: +50% shout radius modifier
- `ogryn_taunt_restore_toughness`: On taunt, instantly restore 10% toughness, then 0.5% per hit taken over 3.25s (up to 20 stacks)
- `ogryn_blocking_ranged_taunts`: Blocking or pushing enemies applies `taunted_short` to them

**Bot usage notes:**
- Shout pattern requires `combat_ability_pressed` then release of `combat_ability_hold`.
- Best used when surrounded by multiple enemies, especially to draw aggro off allies.
- The repeat pulses at 3s and 6s mean taunted enemies stay locked onto the Ogryn.
- Ideal triggers: allies downed, high enemy density, elites targeting squishier teammates.
- The 50s cooldown is long -- bots should not waste it on isolated trash mobs.

---

### 3. Point-Blank Barrage (Gunlugger Stance / Barrage) -- talent `ogryn_special_ammo`, ability `ogryn_ranged_stance`

**Template:** `ogryn_gunlugger_stance`
**Ability group:** `ogryn_gunlugger_stance`
**Input actions:**
- `stance_pressed`: `combat_ability_pressed` (buffer 0.5s) -- single press activation

**Activation pattern:** **Instant single-press** -- this is a stance ability. Press F once.
Has `ability_meta_data.activation.action_input = "stance_pressed"`.

**Action:** `action_stance_change`
- kind: `stance_change`
- `auto_wield_slot = "slot_secondary"` -- auto-switches to ranged weapon
- `reload_secondary = true` -- reloads the ranged weapon
- `stop_current_action = true`, `uninterruptible = true`
- `target_enemies = true` -- faces nearest enemy on activation
- `total_time = 0` -- instant activation
- `required_weapon_type = "ranged"` -- requires ranged weapon (set on player ability, not template)

**Cooldown:** 80s
**Max charges:** 1
**Stance duration:** 10s (from buff template)

**Buff applied** (`ogryn_ranged_stance`):
- `unique_buff_id = "ogryn_ranged_stance"`
- `+25% ranged attack speed`
- `+65% reload speed`
- Keyword: `ogryn_combat_ability_stance`

**Conditionally added sub-buffs** (based on talent special rules):
- `ogryn_ranged_stance_no_movement_penalty_buff`: 50% reduced braced/weapon-action movement penalty, +15% close-range damage (with `ogryn_special_ammo_movement` talent)
- `ogryn_ranged_stance_fire_shots`: Shots apply fire stacks, gain damage stacks per shot (with `ogryn_special_ammo_fire_shots` talent)
- `ogryn_ranged_stance_armor_pierce`: +15% rending, +15% ranged damage (with `ogryn_special_ammo_armor_pen` talent)
- `ogryn_ranged_stance_toughness_regen`: 2.5% toughness per shot, 15% on reload (with `ogryn_ranged_stance_toughness_regen` talent)

**Key modifying talents:**

| Talent | Effect |
|--------|--------|
| `ogryn_special_ammo_fire_shots` | Shots ignite enemies; gain +4 damage stacks per shot (max 16) |
| `ogryn_special_ammo_armor_pen` | +15% rending + 15% ranged damage during stance |
| `ogryn_special_ammo_movement` | 50% reduced braced/weapon-action move penalty, +15% close-range damage |
| `ogryn_ranged_stance_toughness_regen` | 2.5% toughness per shot, 15% on reload |

**Bot usage notes:**
- Simplest to implement for bots -- single `combat_ability_pressed` input.
- Already has `ability_meta_data` defined in the template (unlike charge/taunt).
- Auto-switches to ranged weapon and reloads -- bot should be prepared to shoot immediately after.
- 80s cooldown is the longest of all three -- use strategically against dense groups or armored targets.
- Requires ranged weapon equipped to use (`required_weapon_type = "ranged"`).
- BetterBots now has a first build-aware pass here: Fire Shots variants spend stance on medium-range crowd pressure, Armor Pen variants spend it on hard ranged targets, movement variants allow closer-range commitment before blocking, and toughness-regen variants use it as a low-toughness ranged sustain button.

---

## Blitz (Grenade Ability)

All Ogryn blitz abilities use `ability_type = "grenade_ability"`. They are **item-based** -- no
`ability_template` field, activation is via inventory item equip/throw. Stat buff for extra charges:
`extra_max_amount_of_grenades`.

### 1. Big Box of Hurt -- `ogryn_grenade_box` (Default)

**Item:** `content/items/weapons/player/grenade_box_ogryn`
**Max charges:** 3
**Type:** Thrown box of explosives, impact detonation.

### 2. Big Box of Hurt (Cluster) -- `ogryn_grenade_box_cluster`

**Item:** `content/items/weapons/player/grenade_box_ogryn_cluster`
**Max charges:** 3
**Type:** Cluster variant -- splits into multiple sub-explosions on impact.
**Talent:** `ogryn_box_explodes` -- replaces standard box with cluster variant.

### 3. Demolition Frag Grenade -- `ogryn_grenade_frag`

**Item:** `content/items/weapons/player/grenade_ogryn_frag`
**Max charges:** 1
**Type:** Standard frag grenade with larger blast radius.
**Talent:** `ogryn_grenade_frag` -- replaces box with frag grenade.

### 4. Big Friendly Rock (B.F. Rock) -- `ogryn_grenade_friend_rock`

**Item:** `content/items/weapons/player/grenade_ogryn_friend_rock`
**Max charges:** 4
**Cooldown:** 45s (regenerating)
**Type:** Thrown rock, direct impact damage. Regenerates on a cooldown instead of using ammo pickups.
**Talent:** `ogryn_grenade_friend_rock` -- replaces box with rock, disables grenade pickups.
**Special:** `ogryn_replenish_rock_on_miss` talent: if the rock misses, refund the charge after 5s.

**Grenade-modifying talents:**
- `ogryn_big_box_of_hurt_more_bombs`: +3 max grenade charges (for box variants)
- `ogryn_box_bleed`: Box hits apply 2 bleed stacks (burn on explosion)
- `ogryn_explosions_burn`: Explosions apply 1 burn stack (2 on close targets, max 8)
- `ogryn_frag_bomb_bleed`: Frag grenade applies 12 bleed stacks
- `ogryn_increase_explosion_radius`: Increased explosion AoE

**Bot usage notes:**
- Grenades are item-based (`inventory_item_name`), not template-based. No `ability_template` field.
- `template_name` resolves to `"none"` -- **unreachable via current BT ability path** (Tier 3 problem).
- Bots would need a different activation mechanism: equip grenade item, aim, throw.
- B.F. Rock has self-regenerating charges -- safer for bots to spam.
- Standard box is also worth throwing into clustered elite/special pressure at safe range; it is not just a pure horde-clearing consumable.
- Frag grenade has only 1 charge -- bots should reserve it for monsters or genuinely high-challenge mixed packs, not ordinary horde clear.

---

## Aura (Coherency)

The Ogryn has **four** mutually exclusive aura options:

### 1. Intimidating Presence (Default) -- `ogryn_melee_damage_coherency`

**Buff:** `ogryn_coherency_increased_melee_damage`
**Effect:** +7.5% melee damage to allies in coherency
**Coherency priority:** 1

### 2. Intimidating Presence (Improved) -- `ogryn_melee_damage_coherency_improved`

**Buff:** `ogryn_melee_damage_coherency_improved`
**Effect:** +10% melee damage to allies in coherency
**Coherency priority:** 2

### 3. Damage vs Suppressed -- `ogryn_damage_vs_suppressed_coherency`

**Buff:** `ogryn_aura_increased_damage_vs_suppressed`
**Effect:** +20% damage vs suppressed enemies to allies in coherency; also grants Ogryn +25% suppression
**Coherency priority:** 2

### 4. Toughness Regen Aura -- `ogryn_toughness_regen_aura`

**Buff:** `ogryn_toughness_regen_aura`
**Effect:** +20% toughness regeneration rate to allies in coherency
**Coherency priority:** 2

---

## Keystones

### 1. Heavy Hitter -- `ogryn_passive_heavy_hitter`

**Buff:** `ogryn_passive_heavy_hitter` (parent tracker)
**Mechanic:** Heavy attacks grant stacking damage buff (`ogryn_heavy_hitter_damage_effect`):
- +3% melee damage per stack, max 8 stacks
- Heavy attacks grant 2 stacks, light attacks grant 1 (base)
- Duration refreshes on stack

**Modifier talents:**
- `ogryn_heavy_hitter_light_attacks_refresh`: Light attacks refresh duration
- `ogryn_heavy_hitter_max_stacks_improves_attack_speed`: At max stacks, gain attack speed
- `ogryn_heavy_hitter_max_stacks_improves_toughness`: At max stacks, +15% toughness melee replenish
- `ogryn_heavy_hitter_tdr`: Each stack grants +1.25% toughness damage reduction
- `ogryn_heavy_hitter_cleave`: Each stack grants +12.5% cleave
- `ogryn_heavy_hitter_stagger`: Each stack grants +7.5% stagger

### 2. Feel No Pain (Carapace Armor) -- `ogryn_carapace_armor`

**Buff:** `ogryn_carapace_armor_parent` (parent), `ogryn_carapace_armor_child` (stacks)
**Mechanic:** Gain stacks of armor that provide toughness damage reduction and toughness regeneration.
Stacks are consumed when taking damage.

**Modifier talents:**
- `ogryn_carapace_armor_add_stack_on_push`: Pushing restores a stack
- `ogryn_carapace_armor_trigger_on_zero_stacks`: At zero stacks, create shockwave + restore 50% toughness (5 stacks required)
- `ogryn_carapace_armor_more_toughness`: More toughness regen per stack

### 3. Leadbelcher -- `ogryn_leadbelcher_no_ammo_chance`

**Buff:** `ogryn_leadbelcher_aura_tracking_buff` + `ogryn_blo_new_passive`
**Mechanic:** 15% chance not to consume ammo on ranged shots. Ranged kills grant `ogryn_blo_stacking_buff`:
- +2% ranged damage per stack
- Max 10 stacks, 10s duration (refreshes on new stack)

**Modifier talents:**
- `ogryn_leadbelcher_cooldown_reduction`: Leadbelcher procs grant +100% cooldown regen for 4s
- `ogryn_leadbelcher_trigger_chance_increase`: Increase proc chance to 12% (net 27%)
- `ogryn_leadbelcher_crits`: Leadbelcher shots are always critical hits
- `ogryn_blo_wield_speed`: Leadbelcher stacks also grant lerped ranged attack speed (up to +15% at max stacks, via `ogryn_blo_fire_rate` buff)
- `ogryn_blo_melee`: 10% chance per melee hit to gain Leadbelcher stacks (max 10)
- `ogryn_blo_ally_ranged_buffs`: Leadbelcher procs grant allies +15% ranged damage for 8s

---

## Talent Tree Summary

### Innate / Base Row
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Tough Skin | `ogryn_base_tank_passive` | 25% toughness DR, 20% health DR, no movement slow |
| Helping Hand | `ogryn_helping_hand` | Uninterruptible revives |
| Dodge Stagger | `ogryn_dodge_stagger` | Stagger nearby enemies on dodge |
| Intimidating Presence | `ogryn_melee_damage_coherency` | Aura: +7.5% melee damage |

### Combat Ability Row (choose one)
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Indomitable | `ogryn_charge` | Charge forward, 30s CD, +25% speed/attack speed for 5s after |
| Loyal Protector | `ogryn_taunt_shout` | AoE taunt in 12m, 50s CD, 3 pulses over 6s |
| Point-Blank Barrage | `ogryn_special_ammo` | Ranged stance, 80s CD, 10s duration, +25% attack speed, +65% reload |

### Blitz Row (choose one)
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Big Box of Hurt | `ogryn_grenade_box` | 3 charges, impact explosive |
| Big Box of Hurt (Cluster) | `ogryn_box_explodes` | 3 charges, splits into sub-explosions |
| B.F. Rock | `ogryn_grenade_friend_rock` | 4 charges, 45s regen, direct impact |
| Demolition Frag | `ogryn_grenade_frag` | 1 charge, large AoE frag |

### Passive / Keystone Row (choose one)
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Heavy Hitter | `ogryn_passive_heavy_hitter` | Stacking melee damage on heavy attacks |
| Feel No Pain | `ogryn_carapace_armor` | Ablative toughness armor stacks |
| Leadbelcher | `ogryn_leadbelcher_no_ammo_chance` | 15% free ammo + ranged damage stacks |

### Combat Ability Modifiers (Tier 6)

**Indomitable modifiers:**
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Pulverise | `ogryn_charge_applies_bleed` | Hit enemies take 5 bleed stacks |
| Augmented Indomitable | `ogryn_longer_charge` | 24m distance, only monsters stop you |
| Stomping Boots | `ogryn_charge_toughness` | +10% toughness per enemy hit |
| Trample | `ogryn_charge_trample` | +2.5% damage per enemy hit (stacks 20, 10s) |

**Barrage modifiers:**
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Fire Shots | `ogryn_special_ammo_fire_shots` | Shots ignite, +4 damage stacks/shot (max 16) |
| Armor Pierce | `ogryn_special_ammo_armor_pen` | +15% rending, +15% ranged damage |
| No Movement Penalty | `ogryn_special_ammo_movement` | 50% reduced braced/weapon move penalty, +15% close damage |
| Toughness Regen | `ogryn_ranged_stance_toughness_regen` | 2.5% toughness/shot, 15% on reload |

**Taunt modifiers:**
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Damage Taken Increase | `ogryn_taunt_damage_taken_increase` | Taunted enemies take +20% damage |
| Stagger CD Reduction | `ogryn_taunt_staggers_reduce_cooldown` | Staggering reduces CD by 2.5% |
| Radius Increase | `ogryn_taunt_radius_increase` | +50% shout radius |
| Toughness Restore | `ogryn_taunt_restore_toughness` | 10% instant + 0.5%/hit over 3.25s |

### Notable General Talents
| Talent | Internal ID | Effect |
|--------|-------------|--------|
| Ogryn Killer | `ogryn_ogryn_killer` | +30% dmg vs Ogryns, 30% DR from Ogryns |
| Heavy Bleeds | `ogryn_heavy_bleeds` | Heavy attacks apply bleed (1 light / 4 heavy stacks) |
| Block All Attacks | `ogryn_block_all_attacks` | Perfect blocks stop all attack types, +20% melee damage for 5s (consumed on next melee sweep) |
| Blocking Taunts | `ogryn_blocking_ranged_taunts` | Blocking/pushing applies short taunt |
| Pushing Brittleness | `ogryn_pushing_applies_brittleness` | Pushes apply 4 brittleness stacks |
| Stagger Cleave | `ogryn_stagger_cleave_on_third` | Every 3rd attack: +25% cleave, +25% stagger |
| Ally Movement on Charge | `ogryn_ally_movement_boost_on_ability` | Allies get +20% move speed for 6s |
| Coherency Radius | `ogryn_coherency_radius_increase` | +75% coherency radius |
| Damage Taken Increases Strength | `ogryn_damage_taken_by_all_increases_strength_tdr` | Per hit: +2% power, 15% TDR, 5 stacks, 10s |
| Protect Allies | `ogryn_protect_allies` | On ally toughness break: +10% power, 25% TDR, +25% revive speed, 10s (20s CD) |

---

## Practical Usage (from community guides)

### When to use Indomitable (charge)
- Close distance to ranged specials (Trappers, Gunners, Snipers) that threaten the team
- Reach and rescue downed allies through a horde
- Escape being surrounded -- the charge grants dodge frames and passes through enemies
- Open a fight with charge for the 5s attack/move speed buff before engaging melee
- With Longer Charge talent: use as a long-range repositioning tool (24m)
- Avoid charging into super armor (Crushers) unless running Longer Charge

### When to use Loyal Protector (Taunt)
- When allies are under heavy pressure from melee elites
- Against mixed hordes with ranged enemies -- taunt pulls all aggro
- Before a revive attempt to ensure enemies target you instead
- The 3-pulse repeat means you can taunt, then focus on reviving for the next 6s
- Pair with Blocking Taunts talent for sustained aggro control between cooldowns
- Save for emergencies -- 50s cooldown is unforgiving

### When to use Point-Blank Barrage (Ranged Stance)
- Against dense ranged enemy formations (Scab Shooters)
- When armored targets appear and the Ogryn has a good ranged weapon
- The auto-reload on activation means timing doesn't need to account for reload state
- Fire Shots variant is best for hordes, Armor Pierce for elites
- 80s cooldown means this is roughly once-per-encounter
- Movement variant can justify slightly closer activation windows because the stance reduces the usual braced movement penalty
- Toughness Regen variant can be used as a ranged sustain tool instead of waiting only for a pure damage spike

### Grenade usage priorities
- **B.F. Rock**: Spam freely on specials and elites -- 45s regen means it's always available
- **Big Box of Hurt**: Use on dense packs. Save at least 1 charge for emergencies
- **Frag Grenade**: Single charge -- save for Monster or dense elite pack
- **Cluster Box**: Best overall AoE value, use against mixed groups

### General positioning tips for bots
- Ogryn should be **front-line** -- large hitbox absorbs fire that would hit smaller classes
- Stay in coherency for aura benefits (especially with +75% coherency radius talent)
- Prioritize engaging the largest/most dangerous enemy (elites, specials) first
- When low on toughness, use heavy attacks to proc Heavy Hitter stacks and melee toughness regen

---

## Technical Notes for BetterBots Implementation

### Ability activation patterns

| Ability | Pattern | Inputs | Has `ability_meta_data`? |
|---------|---------|--------|--------------------------|
| Bull Rush | Two-step charge | `combat_ability_pressed` -> hold -> `combat_ability_hold = false` | **No** -- needs injected metadata |
| Loyal Protector (taunt) | Two-step shout | `combat_ability_pressed` -> hold -> `combat_ability_hold = false` | **No** -- needs injected metadata |
| Point-Blank Barrage | Single-press stance | `combat_ability_pressed` | **Yes** -- has `ability_meta_data.activation` |
| Grenades | Item-based | Equip grenade item -> aim -> throw | **N/A** -- no `ability_template` at all |

### Implementation priority
1. **Point-Blank Barrage** (Tier 1): Already has `ability_meta_data`, single-press activation. Easiest to implement.
2. **Indomitable (charge path)** (Tier 2): Needs injected metadata with both `aim_pressed` and `aim_released` inputs. Charge direction targeting required.
3. **Loyal Protector (taunt path)** (Tier 2): Needs injected metadata with `shout_pressed` and `shout_released`. No directional targeting needed (AoE around self).
4. **Grenades** (Tier 3): No ability template -- requires different approach entirely (inventory item manipulation).

### Key source files
- Ability templates: `scripts/settings/ability/ability_templates/ogryn_charge.lua`, `ogryn_gunlugger_stance.lua`, `ogryn_taunt_shout.lua`
- Player abilities: `scripts/settings/ability/player_abilities/abilities/ogryn_abilities.lua`
- Lunge templates: `scripts/settings/lunge/ogryn_lunge_templates.lua`
- Buff templates: `scripts/settings/buff/archetype_buff_templates/ogryn_buff_templates.lua`
- Talent definitions: `scripts/settings/ability/archetype_talents/talents/ogryn_talents.lua`
- Talent settings (values): `scripts/settings/talent/talent_settings_ogryn.lua`
- Shout targets: `scripts/settings/ability/shout_target_templates.lua`
- Archetype data: `scripts/settings/archetype/archetypes/ogryn_archetype.lua`

Sources:
- [Ogryn Builds Database - Darktide WH40k](https://darktide.gameslantern.com/builds/ogryn)
- [The Ogrynomicon - Steam Community Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3044646170)
- [Havoc 40 Ogryn Shield Tank Build](https://darktide.gameslantern.com/builds/a006d28e-3024-4c8b-b73f-b57383335a8a/dec-2025-havoc-40-ogryn-shield-tank-build-for-the-liluns)
