# Zealot (Preacher) -- Class Ability Reference

> Last updated: 2026-03-05
> Generated from decompiled source (`Darktide-Source-Code/` v1.10.7, Feb 2026) and community guides.
> For BetterBots mod development. All internal IDs and values traced to source files.

## Overview

The Zealot (Preacher) is a melee-focused class with high mobility, self-sustain through toughness replenishment, and a signature death-defying passive. Base stats: 200 HP, base crit chance 5%, breed `human`.

- **Archetype file**: `scripts/settings/archetype/archetypes/zealot_archetype.lua`
- **Abilities file**: `scripts/settings/ability/player_abilities/abilities/zealot_abilities.lua`
- **Talents file**: `scripts/settings/ability/archetype_talents/talents/zealot_talents.lua`
- **Buff templates**: `scripts/settings/buff/archetype_buff_templates/zealot_buff_templates.lua`
- **Talent settings (numbers)**: `scripts/settings/talent/talent_settings_zealot.lua`

### Base Talents (unlocked by default)

From `zealot_archetype.lua`:
```lua
base_talents = {
    zealot_dash = 1,               -- Fury of the Faithful / Chastise the Wicked (combat ability)
    zealot_shock_grenade = 1,       -- Stun Grenade (blitz)
    zealot_toughness_damage_coherency = 1,  -- Aura: The Emperor's Will
}
```

---

## Combat Abilities (F key)

The Zealot has **three** mutually exclusive combat ability variants, selected via talent tree.

### 1. Fury of the Faithful (Targeted Dash, internal: Chastise the Wicked)

| Field | Value |
|---|---|
| Internal talent name | `zealot_dash` |
| Player ability ID | `zealot_targeted_dash` |
| Ability template | `zealot_dash` (file: `ability_templates/zealot_dash.lua`) |
| Ability type | `combat_ability` |
| Ability group | `zealot_dash` |
| Cooldown | **30s** (`talent_settings_2.combat_ability.cooldown`) |
| Max charges | 1 |
| Lunge template | `zealot_dash` (file: `lunge/zealot_lunge_templates.lua`) |
| In-game name | `Fury of the Faithful` (current UI), historically `Chastise the Wicked` |

**Input actions** (two-step charge pattern):
```
aim_pressed:  combat_ability_pressed = true   (buffer 0.2s)
aim_released: combat_ability_hold = false      (buffer 0.1s, time_window = inf)
block_cancel: action_two_pressed while holding (buffer 0)
```

**Action sequence**:
1. `action_aim` (kind: `targeted_dash_aim`) -- hold to aim at target
2. `action_state_change` (kind: `character_state_change`) -- releases lunge, consumes charge

**What it does**:
- Dashes toward targeted enemy (distance: **7m**, target acquisition: **21m**)
- Deals `zealot_dash_impact` damage to enemies in **3m radius** during lunge
- Restores **50% Toughness** on completion
- Grants **+25% melee damage** and **100% melee crit chance** and **100% melee rending** for the dash duration
- Stops on super armor, void shields, and resistant armor types
- Grants `no_toughness_damage_buff` during dash (0.13s delay)
- Speed profile ramps 8 -> 12 -> 10 m/s over ~0.55s

**Bot usage notes**: This is a charge/dash ability. The bot needs to:
1. Press `combat_ability_pressed` to begin aiming
2. Hold briefly (minimum 0.075s hold time)
3. Release `combat_ability_hold` to execute the lunge

Best used: closing distance to elites/specials, toughness recovery when low, engaging priority targets. The guaranteed crit + rending on first hit makes it ideal for opening on armored elites. Do NOT use into super armor enemies (Maulers, Crushers) as the dash stops on contact.

#### Talent Variant: Improved Dash (Attack Speed)
| Field | Value |
|---|---|
| Talent name | `zealot_attack_speed_post_ability` |
| Player ability | `zealot_targeted_dash_improved` |
| Cooldown | 30s |
| Max charges | 1 |

Adds: After lunge ends, grants **+20% attack speed** for **10s** (`talent_settings_2.combat_ability_2`).

#### Talent Variant: Double Dash
| Field | Value |
|---|---|
| Talent name | `zealot_additional_charge_of_ability` |
| Player ability | `zealot_targeted_dash_improved_double` |
| Cooldown | 30s |
| Max charges | **2** |

Same as improved dash but with 2 charges.

#### Cooldown Modifiers
- **Melee crits reduce cooldown** (`zealot_crits_grant_cd`): buff `zealot_combat_ability_crits_reduce_cooldown` -- crits grant +100% cooldown regen for 3.25s
- **Backstab/weakspot kills restore CD** (`zealot_backstab_kills_restore_cd`): 10% CD refund per backstab kill, +75% cooldown regen for 2s on weakspot/backstab hits
- **Martyrdom CDR** (`zealot_martyrdom_cdr`): +10% ability cooldown regen per missing health segment per second

---

### 2. Stealth / Shroudfield (Invisibility)

| Field | Value |
|---|---|
| Internal talent name | `zealot_stealth` |
| Player ability ID | `zealot_invisibility` |
| Ability template | `zealot_invisibility` (file: `ability_templates/zealot_invisibility.lua`) |
| Ability type | `combat_ability` |
| Ability group | `zealot_invisibility` |
| Cooldown | **30s** |
| Max charges | 1 |

**Input actions** (single-press stance pattern):
```
stance_pressed: combat_ability_pressed = true   (buffer 0.5s)
```

**Action sequence**:
1. `action_stance_change` (kind: `stance_change`) -- instant activation, consumes charge

This is a **stance ability** -- single press, instant activation. Much simpler for bot implementation than the dash.

**Template note for BetterBots**: Vanilla `zealot_invisibility` has no `ability_meta_data`. BetterBots injects `activation.action_input = "stance_pressed"` so bots can enter this ability path.

**What it does** (from buff `zealot_invisibility`):
- Grants **3s** of stealth (invisible keyword)
- **+20% movement speed**
- **+100% critical strike chance**
- **+150% finesse damage bonus**
- **+150% backstab damage**
- **+150% flanking damage**
- **+100% melee rending**
- Allows backstabbing and flanking while active
- Breaks on: shooting, hitting enemies, reviving, rescuing, pulling up, removing nets, throwing grenades
- Exception: bleeding, burning, frag grenade, plasma, and electrocution damage types do NOT break stealth via `on_hit`
- 0.5s exit grace period (non-damaging actions within 0.5s of activation don't break stealth)

**Bot usage notes**: Single press of `combat_ability_pressed`. Ideal for:
- Repositioning behind an elite for a massive backstab
- Emergency escape from being surrounded
- Setting up a heavy attack on a high-value target before breaking stealth
- The bot should attack immediately after activation to maximize the damage buffs

#### Talent Variant: Increased Duration
| Field | Value |
|---|---|
| Talent name | `zealot_increased_duration` |
| Player ability | `zealot_invisibility_improved` |
| Buff | `zealot_invisibility_increased_duration` |
| Duration | **5s** (from `talent_settings.zealot_increased_duration.duration = 5`) |

Also grants on stealth end: -75% threat weight and +50% backstab damage for 5s.

#### Talent Variant: Increased Damage / Longer Cooldown
| Field | Value |
|---|---|
| Talent name | `zealot_stealth_more_cd_more_damage` |
| Buff | `zealot_increase_ability_cooldown_increase_bonus` |

Increases cooldown (flat reduction is negative = increase), but adds extra finesse and backstab damage during stealth. Also adds perfect block timing bonus.

#### Related Talents
- **Leaving stealth restores toughness** (`zealot_leaving_stealth_restores_toughness`): 50% toughness + 30% damage reduction for 8s on stealth end
- **Stealth cooldown on kills** (`zealot_stealth_cooldown_regeneration`): monster kills restore 50%, ogryn 30%, other 15% cooldown
- **Damage taken restores CD** (`zealot_restore_stealth_cd_on_damage`): 1% CD per damage taken (up to 25% max HP), +50% cooldown regen

---

### 3. Bolstering Prayer (Relic / Channel)

| Field | Value |
|---|---|
| Internal talent name | `zealot_bolstering_prayer` |
| Player ability ID | `zealot_relic` |
| Ability type | `combat_ability` |
| Ability group | `bolstering_prayer` |
| Cooldown | **60s** |
| Max charges | 1 |
| Inventory item | `content/items/weapons/player/preacher_relic` |

**IMPORTANT**: This is an **item-based ability** -- there is NO `ability_template` field. The relic is wielded as an inventory item in `slot_combat_ability`. The cooldown pauses while the relic is not wielded.

**Input actions**: This ability is activated by wielding the relic item, NOT through the standard ability template action system. The player equips the relic and uses it like a weapon.

**What it does** (from talent settings and buff templates):
- Channels a prayer that restores toughness to self and nearby allies
- Self toughness restore: **50%** per tick
- Team toughness restore: **25%** per tick
- Tick rate: **0.8s**
- Grants stacking `zealot_channel_toughness_bonus`: **+15 flat toughness** per stack (up to 5 stacks, 10s duration)
- Total potential bonus toughness: +75 flat

**Bot usage notes**: This is the hardest ability to implement for bots (Tier 3). It requires:
1. Switching to the relic weapon slot
2. Channeling (holding) the ability
3. Switching back to normal weapons when done

The `template_name` stays `"none"` because there's no `ability_template`. This means bots cannot use the standard ability BT path. Best used when team is low on toughness, during a lull in combat.

#### Talent Modifiers
- **Staggers enemies** (`zealot_channel_staggers`): enemies are staggered while channeling
- **Grants damage buff** (`zealot_channel_grants_damage`): +30% damage buff for 10s per channel tick (1 stack max)
- **Grants toughness DR** (`zealot_channel_grants_toughness_damage_reduction`): 40% toughness damage reduction for 10s per tick

---

## Blitz (Grenade Abilities)

Three mutually exclusive grenade types.

### 1. Stun Grenade (Default)

| Field | Value |
|---|---|
| Internal talent name | `zealot_shock_grenade` |
| Player ability ID | `zealot_shock_grenade` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_shock` |
| Max charges | **3** (`talent_settings_2.grenade.max_charges`) |
| Stat buff for extra | `extra_max_amount_of_grenades` |

**What it does**: Throws a stun grenade that staggers and temporarily incapacitates enemies in an area.

**Bot usage notes**: Standard grenade throw via `grenade_ability_pressed`. Use against dense packs, especially to interrupt dangerous enemy attacks or to stagger elites.

#### Talent Modifier
- **Improved Stun Grenade** (`zealot_improved_stun_grenade`): +50% explosion radius

### 2. Flame Grenade

| Field | Value |
|---|---|
| Internal talent name | `zealot_flame_grenade` |
| Player ability ID | `zealot_fire_grenade` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/grenade_fire` |
| Stat buff for extra | `extra_max_amount_of_grenades` |
| Max charges | **3** (`talent_settings_3.grenade.max_charges`) |

**What it does**: Throws a fire grenade that creates a burning area (liquid_area_fire_burning damage profile). Deals damage over time to enemies in the area.

**Bot usage notes**: Best thrown at chokepoints or dense groups. Creates area denial. Bots should avoid throwing at their own feet.

### 3. Throwing Knives

| Field | Value |
|---|---|
| Internal talent name | `zealot_throwing_knives` |
| Player ability ID | `zealot_throwing_knives` |
| Ability type | `grenade_ability` |
| Inventory item | `content/items/weapons/player/zealot_throwing_knives` |
| Stat buff for extra | `extra_max_amount_of_grenades` |
| Max charges | **12** |
| Refill | 1 knife per melee kill |

**Special rules applied**:
- `disable_grenade_pickups` -- cannot pick up grenade boxes
- `ammo_pickups_refills_grenades` -- ammo pickups restore knives
- `zealot_throwing_knives` -- enables knife-specific mechanics

**What it does**: Fast-throwing single-target projectiles. Replenished by melee kills (1 per kill). Uses `zealot_throwing_knives` damage profile.

**Bot usage notes**: High-frequency use ability. Bots should throw at specials/elites at range, then melee to replenish. Unlike grenades, these are meant to be used frequently.

#### Talent Modifier
- **Bleed generates knives** (`zealot_bleed_generates_throwing_knife`): bleeding enemies killed have a chance to refill a knife

---

## Auras (Coherency Buffs)

Four mutually exclusive aura options.

### 1. The Emperor's Will (Default)

| Field | Value |
|---|---|
| Talent name | `zealot_toughness_damage_coherency` |
| Coherency buff | `zealot_coherency_toughness_damage_resistance` |
| Coherency ID | `zelot_maniac_coherency_aura` |

**Effect**: Allies in coherency take **7.5% less toughness damage** (`toughness_damage_taken_multiplier = 0.925`).

#### Improved Variant
- Talent: `zealot_toughness_damage_reduction_coherency_improved`
- Buff: `zealot_coherency_toughness_damage_resistance_improved`
- Effect: **15% toughness damage reduction** (`multiplier = 0.85`)

### 2. Cleansing Prayer (Corruption Healing)

| Field | Value |
|---|---|
| Talent name | `zealot_corruption_healing_coherency` |
| Coherency buff | `zealot_preacher_coherency_corruption_healing` |
| Type | `interval_buff` |
| Interval | **1s** |

**Effect**: Allies in coherency heal **0.5 corruption** per second.

#### Improved Variant
- Talent: `zealot_corruption_healing_coherency_improved`
- Buff: `zealot_preacher_coherency_corruption_healing_improved`
- Effect: **1.5 corruption** healed per second

### 3. Stamina Cost Reduction

| Field | Value |
|---|---|
| Talent name | `zealot_stamina_cost_multiplier_aura` |
| Coherency buff | `zealot_stamina_cost_multiplier_aura` |

**Effect**: Allies in coherency have **15% reduced stamina cost** (`stamina_cost_multiplier = 0.85`).

### 4. Lone Wolf (Always in Coherency)

| Field | Value |
|---|---|
| Talent name | `zealot_always_in_coherency` |
| Coherency buff | `zealot_always_in_coherency_buff` |

**Effect**: Always count as in at least **2 coherency** (even when solo). Improved variant (`zealot_always_in_coherency_improved`) counts as 3.

**Bot usage notes**: Auras are passive -- no bot action needed. However, bots should try to stay in coherency range of the player to benefit from and provide aura effects.

---

## Passives

### Martyrdom

| Field | Value |
|---|---|
| Talent name | `zealot_martyrdom` |
| Buff | `zealot_martyrdom_base` |

**Effect**: For each missing health segment (wound), gain **+10% damage**. Max 5 stacks.
- Toughness variant (talent: `zealot_martyrdom_grants_toughness`, buff: `zealot_martyrdom_toughness`): -7.5% toughness damage taken per missing segment
- Attack speed variant (`zealot_martyrdom_grants_attack_speed`): +6% attack speed per missing segment
- CDR variant (`zealot_martyrdom_cdr`): +10% ability cooldown regeneration per missing segment per second

### Until Death (Resist Death)

| Field | Value |
|---|---|
| Buff | `zealot_resist_death` |
| Active duration | **5s** (invulnerability window) |
| Cooldown | **120s** (2 minutes) |
| Trigger | `on_damage_taken` that would kill |

**Effect**: When you would die, instead become invulnerable for 5s. 120s internal cooldown. Shows `resist_death` keyword while off cooldown (via `off_cooldown_keywords`). Note: `stun_immune` is NOT on this buff -- it exists on the separate `bolstering_prayer_resist_death` buff.

#### Improved Variant (with Leech)
- Buff: `zealot_resist_death_improved_with_leech`
- Same trigger, but also grants leech effect (0.7% lifesteal, 3x for melee) for 5s
- Can also instantly restore a combat ability charge on proc

### Melee Attack Speed

| Field | Value |
|---|---|
| Talent name | `zealot_attack_speed` |
| Buff | `zealot_increased_melee_attack_speed` |

**Effect**: +10% melee attack speed (passive, always active).

### Increased Damage vs Disgustingly Resilient

| Field | Value |
|---|---|
| Talent name | `zealot_increased_damage_vs_resilient` |
| Buff | `zealot_preacher_damage_vs_disgusting` |

**Effect**: +20% damage vs Disgusting and Resistant enemies.

### Reduced Corruption Damage

| Field | Value |
|---|---|
| Buff | `zealot_preacher_reduce_corruption_damage` |

**Effect**: 50% reduced corruption taken (`corruption_taken_multiplier = 0.5`).

---

## Keystones

### 1. Martyrdom (zealot_2 tree)

See Passives > Martyrdom above. The core keystone for the Maniac (zealot_2) path. Damage scales with missing health.

### 2. Fanatic Rage (zealot_3 tree -- Preacher)

| Field | Value |
|---|---|
| Talent name | `zealot_fanatic_rage` |
| Buff | `zealot_fanatic_rage` |
| Type | `proc_buff` with talent resource |
| Max resource | **25 stacks** |
| Decay | Stacks decay after **8s** out of combat |
| Range | **25m** (enemies dying within range grant stacks) |

**Effect**: Enemies dying near you grant Fury stacks. At max stacks, gain **+15% crit chance**. Crits on hit also consume all stacks.

**Conditional buff at max**: **25% toughness damage reduction** (`toughness_damage_taken_multiplier = 0.75`).

#### Talent Modifiers
- **Improved crit** (`zealot_fanatic_rage_improved`): additional +10% crit chance at max
- **Crits grant stacks** (`zealot_fanatic_rage_stacks_on_crit`): your crits also add Fury stacks
- **Toughness on max** (`zealot_fanatic_rage_toughness_on_max`): 50% toughness restore on reaching max, 2% per tick while at max, 25% toughness DR
- **Shared rage** (`zealot_shared_fanatic_rage`): allies in coherency gain 10% crit from your rage

### 3. Quickness (zealot_3 tree -- Preacher)

| Field | Value |
|---|---|
| Talent name | `zealot_quickness_passive` |
| Buff | `zealot_quickness_passive` (parent) + `zealot_quickness_counter` (child) |
| Max stacks | **20** |
| Active duration | **6s** (base), **10s** (increased) |

**Effect**: Moving builds Momentum stacks (1 per 5m moved, doubled while sprinting). On hit, all stacks are consumed and grant per-stack bonuses for 6s:
- +1% melee attack speed per stack
- +1% ranged attack speed per stack
- +1% damage per stack
- +0.5% dodge speed per stack
- +0.5% dodge distance per stack
- -1% dodge cooldown per stack

Stacks reset on an 8s cooldown after consumption.

#### Talent Modifiers
- **Dodge stacks** (`zealot_quickness_passive_dodge_stacks`): successful dodges grant 3 stacks
- **Toughness per stack** (`zealot_quickness_toughness_per_stack`): replenish 2% toughness per stack consumed
- **Momentum toughness** (`zealot_momentum_toughness_replenish`): 0.4% toughness regen per stack per second while active
- **Increased duration** (special rule `zealot_quickness_increased_duration`): active buff lasts 10s instead of 6s

---

## Toughness Talents

| Talent | Buff | Effect |
|---|---|---|
| Toughness on melee | `toughness_melee_replenish = 1` | Replenish toughness on melee hits |
| Toughness DR after hit | `toughness_damage_taken_multiplier = 0.6` | 40% toughness DR for 4s after hit |
| Toughness regen near enemies | `toughness = 0.05, num_enemies = 3, range = 5` | 5% toughness/tick when 3+ enemies within 5m |
| Toughness on heavy kills | `zealot_toughness_on_heavy_kills` | 10% toughness per heavy attack kill |
| Toughness on ranged kills | `zealot_toughness_on_ranged_kill` | 4% toughness per ranged kill |
| Toughness on dodge | `zealot_toughness_on_dodge` | 15% toughness per successful dodge (0.5s cooldown) |
| Toughness in melee range | `zealot_toughness_in_melee` | 2.5%-7.5% toughness regen based on nearby enemies |

---

## Talent Tree Summary

The Zealot talent tree has three main paths, each centered on a different playstyle:

### Left Path: Infiltrator / Assassin (zealot_1 / Pious Stabber)
- **Combat ability**: Stealth / Shroudfield
- **Aura**: Lone Wolf (always in coherency)
- **Focus**: Backstab damage, flanking, dodge synergies, finesse damage
- **Key talents**: `zealot_backstab_damage`, `zealot_increased_crit_and_weakspot_damage_after_dodge`, `zealot_increased_stagger_on_weakspot_melee`, `zealot_more_damage_when_low_on_stamina`, `zealot_increased_damage_when_flanking`

### Center Path: Maniac / Berserker (zealot_2)
- **Combat ability**: Fury of the Faithful (dash; internal/template naming still references Chastise the Wicked)
- **Keystone**: Martyrdom
- **Aura**: The Emperor's Will (toughness DR)
- **Focus**: Attack speed, bleed, crit chains, melee damage stacking
- **Key talents**: `zealot_crits_apply_bleed`, `zealot_multi_hits_grant_impact_and_uninterruptible`, `zealot_martyrdom_grants_attack_speed`, `zealot_hits_grant_stacking_damage`
- **Blitz**: Stun Grenade or Throwing Knives

### Right Path: Preacher / Support (zealot_3)
- **Combat ability**: Bolstering Prayer (relic channel)
- **Keystones**: Fanatic Rage, Quickness
- **Aura**: Cleansing Prayer (corruption healing)
- **Focus**: Team support, impact/cleave, damage vs elites, toughness management
- **Key talents**: `zealot_fanatic_rage`, `zealot_quickness_passive`, `zealot_increased_impact`, `zealot_multi_hits_increase_damage`, `zealot_increased_cleave`, `zealot_shared_fanatic_rage`
- **Blitz**: Flame Grenade

### Cross-Path Talents (available to multiple builds)
- `zealot_crits_rend`: +15% rending on crits
- `zealot_elite_kills_empowers`: +10% damage, 15% toughness on elite kills
- `zealot_uninterruptible_no_slow_heavies`: uninterruptible heavy attacks
- `zealot_damage_vs_elites`: +15% damage vs elites
- `zealot_dodge_improvements`: +25% dodge distance, +1 consecutive dodge
- `zealot_revive_speed`: +25% revive speed, 10% move speed, 15% toughness DR for 5s
- `zealot_sprint_improvements`: +10% sprint speed, -10% sprint cost, slowdown immunity after 1s

---

## Practical Usage (Community Guides)

### When to use Fury of the Faithful (Dash)
- **Engage**: Close distance to specials (trappers, snipers, flamers) for quick kills
- **Toughness recovery**: Use when toughness is depleted for 50% instant restore
- **Elite burst**: The guaranteed crit + rending makes the first hit post-dash devastating against armored targets
- **Escape**: Can dash through enemies to break out of encirclement
- **Combo**: Prep a heavy attack before dashing for maximum first-hit damage
- **Do NOT dash into**: Chaos Warriors (super armor), Bulwarks (void shield), Plague Ogryns (resistant) -- the dash stops on these

### When to use Stealth (Shroudfield)
- **Assassination**: Activate, reposition behind a Crusher/Mauler, deliver a massive backstab
- **Emergency**: Pop when surrounded to shed aggro and reposition
- **Revive**: Stealth DOES break on revive (`on_revive` is a registered proc event in the buff). Do not use stealth to revive.
- **Duration management**: Attack quickly after activating -- the buffs are massive but brief (3-5s)
- **Caution**: Throwing grenades WILL break stealth

### When to use Bolstering Prayer (Relic)
- **Team heal**: Use during safe moments when team toughness is depleted
- **Pre-engagement**: Channel briefly before a known dangerous encounter
- **Stagger utility**: With the stagger talent, can be used defensively when surrounded
- **NOT in combat**: Channeling locks you into the relic weapon -- vulnerable to melee

### When to use grenades
- **Stun grenade**: Interrupt dangerous enemy attacks, crowd control dense packs, stagger mutants mid-charge
- **Flame grenade**: Area denial at chokepoints, soften hordes before engagement
- **Throwing knives**: Use constantly on specials at range; the 12-charge pool and melee-kill refill means these should be used aggressively and often

---

## Bot Implementation Priority

| Ability | Pattern | Complexity | Priority |
|---|---|---|---|
| Stealth (Shroudfield) | `stance_pressed` (single press) | Low | Tier 2 (metadata injection) |
| Fury of the Faithful (Chastise the Wicked) | `aim_pressed` -> hold -> `aim_released` | Medium | Tier 2 |
| Throwing Knives | Item-based grenade | Medium | Tier 3 (grenade path, out of current scope) |
| Stun/Flame Grenade | Item-based grenade | Medium | Tier 3 (grenade path, out of current scope) |
| Bolstering Prayer | Item-based, channel, no `ability_template` | High | Tier 3 |

### Key Source References

| File | Content |
|---|---|
| `ability_templates/zealot_dash.lua` | Dash action inputs and action hierarchy |
| `ability_templates/zealot_invisibility.lua` | Stealth action inputs (single press) |
| `player_abilities/abilities/zealot_abilities.lua` | All ability definitions with cooldowns and charges |
| `archetype_talents/talents/zealot_talents.lua` | Full talent tree with all talent nodes |
| `buff/archetype_buff_templates/zealot_buff_templates.lua` | All buff implementations |
| `talent/talent_settings_zealot.lua` | Numeric values for all talent parameters |
| `lunge/zealot_lunge_templates.lua` | Dash lunge speed curves and damage settings |

### Sources (Community)
- [Steam Guide: Zealot Talents & Mechanics [1.10.x]](https://steamcommunity.com/sharedfiles/filedetails/?id=3088553235)
- [Darktide Zealot Class Overview](https://darktide.gameslantern.com/classes)
- [Tips For Playing A Zealot](https://www.thegamer.com/warhammer-40000-darktide-zealot-preacher-class-guide/)
- [Zealot: Preacher Wiki](https://warhammer-40k-darktide.fandom.com/wiki/Zealot:_Preacher)
- [Fatshark Dev Blog: Talent Trees Deep Dive](https://www.playdarktide.com/news/dev-blog-talent-trees-deep-dive)
- [SteamDB Hotfix #35 (shows dual naming `Chastise the Wicked` / `Fury of the Faithful`)](https://steamdb.info/patchnotes/13937298/)
