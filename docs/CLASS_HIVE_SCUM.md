# Hive Scum (Internal: `broker`)

## Overview

The Hive Scum is a DLC class (released December 2, 2025) built around high mobility, close-range aggression, and chemical enhancement. Internal archetype name is `broker`. Base stats: 150 HP, 75 Toughness (5/s regen, 3s delay), 10% base crit chance, 3 base stamina. Toughness recovery on melee kill: 5%. Toughness damage is halved while sliding.

The class has three playstyle paths: **Gunslinger** (ranged-focused), **Ruffian** (melee/mobility-focused), and **Chemist/Anarchist** (toxin/stimm-focused). A unique secondary system, the **Stimm Lab**, allows customizing the Cartel Special stimm with stat buffs.

---

## Combat Ability (F key)

Three mutually exclusive combat ability choices, all `ability_type = "combat_ability"`.

### 1. Enhanced Desperado (Focus)

| Field | Value |
|---|---|
| Internal name | `broker_ability_focus` / `broker_ability_focus_improved` |
| Template | `broker_focus` |
| Buff applied | `broker_focus_stance` / `broker_focus_stance_improved` |
| Input action | `combat_ability_pressed` -> `stance_pressed` |
| Kind | `stance_change` (instant activation) |
| Cooldown | 45s (paused while stance is active) |
| Charges | 1 |
| Duration | 10s base |
| Required weapon | Ranged (`required_weapon_type = "ranged"`) |
| Auto-wield | `slot_secondary` (switches to ranged weapon) |

**What it does:**
- Refills toughness on activation (`refill_toughness = true`)
- Grants **suppression immunity** and **counts as dodge vs ranged** (immune to ranged damage)
- Free ammo: moves clip to reserve, fills clip to max, reloads don't consume ammo during stance
- +20% sprint movement speed, 0% sprint stamina cost
- FOV widens (1.1x multiplier, lerps back over duration)
- Close-range ranged kills extend duration (diminishing returns, divisor 5, max 20s)

**Improved variant** (`broker_ability_focus_improved`): Adds enemy outlines within close range, highlighting targets. Duration extends by 1s per close-range kill.

**Talent modifiers (sub-nodes):**
- `broker_ability_focus_noclip`: Disables minion collision during sprint and dodge while in Focus
- `broker_ability_focus_sub_2`: +15% ranged rending during Focus; ranged kills grant stacking ranged damage
- `broker_ability_focus_sub_3`: Close-range kills restore cooldown (0.5s base, 1s for elites, max 5s total)

**Bot usage notes:** Stance ability -- single `stance_pressed` input, instant activation. Already has `ability_meta_data`. Bot should activate when: (a) ranged weapon is equipped or can be auto-wielded, (b) multiple enemies at mid-range, (c) toughness is low (for the refill), (d) ammo is low (free reloads). Cooldown pauses while active, so effective cooldown is 45s + stance duration.

---

### 2. Rampage (Punk Rage)

| Field | Value |
|---|---|
| Internal name | `broker_ability_punk_rage` |
| Template | `broker_punk_rage` |
| Buff applied | `broker_punk_rage_stance` |
| Input action | `combat_ability_pressed` -> `stance_pressed` |
| Kind | `stance_change` (instant activation) |
| Cooldown | 30s (paused while stance is active) |
| Charges | 1 |
| Duration | 10s base |
| Required weapon | Melee (`required_weapon_type = "melee"`) |
| Auto-wield | `slot_primary` (switches to melee weapon) |

**What it does:**
- Refills toughness on activation
- Grants **stun immunity** and **slowdown immunity**
- +50% melee power level, +20% melee attack speed, 25% damage reduction
- Melee hits extend duration by 0.3s (divisor 2, max 20s)
- FOV effect (1.1x multiplier)
- Screen rage visual effect

**Talent modifiers (sub-nodes):**
- `broker_ability_punk_rage_sub_1`: After 50% of Rage duration, heavy attacks gain +25% melee rending
- `broker_ability_punk_rage_sub_2`: +50% cleave (hit mass), plus ramping melee power (+2.5% per second, stacking)
- `broker_ability_punk_rage_sub_3`: On activation, shout in 4.5m radius reducing enemy melee attack speed by 50% for 5s
- `broker_ability_punk_rage_sub_4`: Hitting elites/specials/monsters extends duration by 1s instead of 0.3s, max duration increased to 30s

**Bot usage notes:** Stance ability -- same `stance_pressed` pattern as Focus. Bot should activate when: (a) engaged in melee with multiple enemies, (b) toughness is low (instant refill), (c) facing elites/hordes where sustained melee is needed. The stun/slowdown immunity makes this ideal for pushing through dangerous melee situations.

---

### 3. Stimm Field

| Field | Value |
|---|---|
| Internal name | `broker_ability_stimm_field` |
| Template | None (item-based: `inventory_item_name`) |
| Buff applied | `syringe_broker_buff_stimm_field` |
| Input action | Item-based (wield and use) |
| Cooldown | 60s (paused while field is active) |
| Charges | 1 |
| Duration | 20s lifetime |
| Ability group | `broker_stimm_field` |

**What it does:**
- Deploys a proximity field (3m radius) that heals corruption for allies inside
- Corruption heal: 50% per tick at 0.25s intervals over 20s
- Item-based ability: `content/items/weapons/player/broker_stimm_field_crate`
- `can_be_wielded_when_depleted = false` -- cannot use when on cooldown
- Cooldown pauses while a `ProximityBrokerStimmField` job exists

**Talent modifiers (sub-nodes):**
- `broker_ability_stimm_field_sub_1`: Reduced field lifetime to 5s, but 15s linger effect on allies who leave
- `broker_ability_stimm_field_sub_2`: Field applies Chem Toxin stacks to enemies inside
- `broker_ability_stimm_field_sub_3`: Monitors syringe/pocketable state for synergy effects

**Bot usage notes:** Item-based ability with no `ability_template` field -- `template_name` stays `"none"`. **Tier 3 difficulty for bot implementation** -- needs a different approach than stance abilities since it requires wielding and using an inventory item. Bot should deploy when: (a) team has significant corruption, (b) holding a defensive position, (c) during revive situations.

---

## Cartel Special Stimm (Pocketable Ability)

| Field | Value |
|---|---|
| Internal name | `broker_ability_syringe` |
| Ability type | `pocketable_ability` |
| Item | `content/items/pocketable/syringe_broker_pocketable` |
| Cooldown | 15s (min) to 75s (max), scales with Stimm Lab points spent |
| Charges | 1 |
| Buff applied | `syringe_broker_buff` |

**What it does:**
- Personal stimm injection with customizable effects via the Stimm Lab talent tree
- Only available if at least one Stimm Lab node is selected (`conditional_base_talents`)
- Cooldown scales via `cooldown_lerp_func`: lerps between 15s and 75s based on (points_spent - 1) / (max_points - 1)
- Cooldown pauses while `syringe_broker_buff` is active

**Stimm Lab categories:**
- **Celerity** (5 tiers + 2 branches): Attack speed (+4% per tier), wield speed (+25%), stamina cost reduction, reload speed, movement speed, stun/slowdown immunity at tier 5
- **Combat** (5 tiers + 2 branches): Power level (+4% per tier), finesse damage, rending, crit chance
- **Durability** (4 tiers + 2 branches): Toughness restore on use (6.25% per tier), +5% toughness replenish, 4% damage reduction per tier, toughness over time
- **Concentration** (5 tiers + 2 branches): Combat ability cooldown regen (+6.25% per tier), cooldown on melee/ranged kills

**Bot usage notes:** Another item-based ability (`pocketable_ability`). Tier 3 difficulty -- same issues as Stimm Field. Bot should use when: (a) about to engage a tough fight, (b) combat ability is on cooldown and concentration buffs would help, (c) generally on cooldown (use whenever available in combat).

---

## Blitz (Grenade)

Three mutually exclusive grenade options, all `ability_type = "grenade_ability"`.

### 1. Flash Grenade (Default)

| Field | Value |
|---|---|
| Internal name | `broker_flash_grenade` / `broker_flash_grenade_improved` |
| Item | `content/items/weapons/player/grenade_quick_flash` |
| Charges | 3 (default) / 5 (improved) |
| Recharge | 1 charge per 20 kills |

**What it does:**
- Quick-throw flash grenade that staggers/blinds enemies
- Passively recharges via kill tracking (`broker_passive_blitz_charge_on_kill`)
- Special rule: `quick_flash_grenade`

**Bot usage notes:** Standard grenade ability. Bot should throw at: (a) dense enemy groups, (b) specials/elites to interrupt attacks, (c) to create breathing room when overwhelmed.

### 2. Tox Grenade

| Field | Value |
|---|---|
| Internal name | `broker_tox_grenade` |
| Item | `content/items/weapons/player/grenade_tox` |
| Charges | 3 |
| Max toxin stacks | 6 |

**What it does:**
- Creates a toxic area that applies Chem Toxin stacks (damage over time) to enemies
- Lasts 15s, applies up to 6 toxin stacks
- Synergizes with Chemist talent path

**Bot usage notes:** Area denial grenade. Bot should throw at: (a) chokepoints, (b) dense hordes, (c) priority targets when running Chemist build.

### 3. Missile Launcher

| Field | Value |
|---|---|
| Internal name | `broker_missile_launcher` |
| Item | `content/items/weapons/player/ranged/missile_launcher` |
| Charges | 3 |

**What it does:**
- Fires a missile for high single-target/AoE damage
- Special rule: `broker_missile_launcher`

**Bot usage notes:** High damage blitz option. Bot should use against: (a) monsters/bosses, (b) tightly grouped elites, (c) Chaos Spawn / Plague Ogryn.

---

## Aura (Coherency)

Three mutually exclusive aura choices.

### 1. Gunslinger Aura (Default)

| Field | Value |
|---|---|
| Internal name | `broker_aura_gunslinger` / `broker_aura_gunslinger_improved` |
| Buff template | `broker_aura_gunslinger` |
| Coherency ID | `broker_gunslinger_coherency_aura` |

**What it does:**
- When Hive Scum picks up ammo, shares 5% (base) / 10% (improved) of the pickup to allies in coherency
- Proc event: `on_ammo_pickup`

### 2. Ruffian Aura

| Field | Value |
|---|---|
| Internal name | `broker_coherency_melee_damage` |
| Buff template | `broker_coherency_melee_damage` |
| Coherency ID | `broker_ruffian_coherency_aura` |

**What it does:**
- +10% melee damage to allies in coherency

### 3. Anarchist Aura

| Field | Value |
|---|---|
| Internal name | `broker_coherency_anarchist` |
| Buff template | `broker_coherency_critical_chance` |
| Coherency ID | `broker_anarchist_coherency_aura` |

**What it does:**
- +5% critical strike chance to allies in coherency

---

## Keystones

### 1. Vulture's Mark

| Field | Value |
|---|---|
| Internal name | `broker_keystone_vultures_mark_on_kill` |
| Buff template | `vultures_mark` (stacking buff) |

**What it does:**
- Killing elites/specials with ranged weapons grants a stack of Vulture's Mark (8s duration, refreshes on new stack)
- Max 3 stacks, each granting: +5% ranged damage, +5% ranged crit chance, +5% movement speed
- At max stacks: additional elite/special ranged kills restore 15% toughness to all allies in coherency

**Talent modifiers:**
- `broker_keystone_vultures_mark_increased_duration`: Stack duration increased to 12s
- `broker_keystone_vultures_mark_aoe_stagger`: Ranged elite/special kills trigger AoE stagger explosion at player position
- `broker_keystone_vultures_mark_dodge_on_ranged_crit`: Ranged crits grant a 1s dodge buff

### 2. Chemical Dependency

| Field | Value |
|---|---|
| Internal name | `broker_keystone_chemical_dependency` |
| Buff template | `broker_keystone_chemical_dependency` / `broker_keystone_chemical_dependency_stack` |

**What it does:**
- Using a stimm (Cartel Special or pickup) grants a stack of Chemical Dependency
- Max 3 stacks, 90s duration each. Per stack: +10% combat ability cooldown regen, +5% crit chance, 5% toughness damage reduction
- Reaching max stacks grants 50% toughness (sub_2)

**Talent modifiers:**
- Sub 1: Adds crit chance counting per stack
- Sub 2: +50% toughness on reaching max stacks
- Sub 3: Reduced duration (60s) but max stacks increased to 4

### 3. Adrenaline Junkie

| Field | Value |
|---|---|
| Internal name | `broker_keystone_adrenaline_junkie` |
| Buff template | `broker_keystone_adrenaline_junkie` / `broker_keystone_adrenaline_junkie_stack` / `broker_keystone_adrenaline_junkie_proc` |

**What it does:**
- Melee hits grant Adrenaline stacks (1 per hit, +1 bonus on crit)
- Stacks last 2s each, max 30 stacks, refreshing on new stacks
- At 30 stacks: all stacks consumed, gain **Adrenaline Frenzy** for 10s (+25% melee damage, +10% melee attack speed)
- Reaching Frenzy again during active Frenzy refreshes duration

**Talent modifiers:**
- Sub 1: No regular hit grants; instead, weakspot hits grant 3 stacks (0 regular + 1 base + 2 additional)
- Sub 2: Only procs on melee kills (not hits), but grants +4 stacks per kill (+10 additional for elite kills)
- Sub 3: Frenzy duration extended to 20s
- Sub 4: Adrenaline stack duration extended to 4s (easier to maintain)
- Sub 5: During Frenzy, restore 5% toughness per second

---

## Talent Tree Summary

### Passive Talents (ability-affecting)

**Damage / Offense:**
- `broker_passive_first_target_damage`: +15% damage to first target hit
- `broker_passive_close_ranged_damage`: +25% ranged damage within 12.5m, +10% within 30m
- `broker_passive_close_ranged_finesse_damage`: +25% finesse damage at close range
- `broker_passive_finesse_damage`: +15% finesse damage
- `broker_passive_increased_weakspot_damage`: +25% weakspot damage
- `broker_passive_strength_vs_aggroed`: +10% power level vs enemies targeting you
- `broker_passive_repeated_melee_hits_increases_damage`: After 2 consecutive melee hits on same target, +25% damage
- `broker_passive_ramping_backstabs`: Backstabs grant +10% melee power (stacks 5x)
- `broker_passive_damage_on_reload`: Reloading grants damage buff based on ammo spent (2% base + 2% per 10% ammo stage, 7s)
- `broker_passive_close_range_damage_on_dodge`: +15% close-range damage for 3s after dodging
- `broker_passive_close_range_damage_on_slide`: +15% close-range damage while sliding
- `broker_passive_melee_damage_carry_over`: 25% of overkill melee damage carries to next target (1s window)
- `broker_passive_cleave_on_cleave`: +50% hit mass on attacks hitting 3+ targets

**Crit Chance:**
- `broker_passive_ninja_grants_crit_chance`: Dodging grants +20% crit chance for 3s
- `broker_passive_parries_grant_crit_chance`: Parrying grants +20% crit chance for 2s
- `broker_passive_backstabs_grant_crit_chance`: Backstabs grant +20% crit chance for 2s
- `broker_passive_reload_on_crit`: Ranged crits replenish 15% ammo

**Toughness / Survivability:**
- `broker_passive_restore_toughness_on_close_ranged_kill`: +8% toughness on close-range ranged kill, +15% for elites
- `broker_passive_restore_toughness_on_weakspot_kill`: +4% default, +8% weakspot, +12% crit kill
- `broker_passive_reduced_toughness_damage_during_reload`: -25% toughness damage taken for 4s while reloading
- `broker_passive_replenish_toughness_on_ranged_toughness_damage`: Restoring 30% toughness over 3s when taking ranged toughness damage
- `broker_passive_stun_immunity_on_toughness_broken`: On toughness break, gain stun immunity for 6s and restore 50% toughness (10s cooldown)
- `broker_passive_push_on_damage_taken`: Taking damage reduces push cost and grants impact (stacks 3x)
- `broker_passive_punk_grit`: +10% ranged damage, 10% toughness damage reduction

**Mobility:**
- `broker_passive_improved_dodges`: +25% dodge speed, +0.15s dodge linger time
- `broker_passive_dodge_melee_on_slide`: Sliding dodges melee attacks
- `broker_passive_extra_consecutive_dodges`: +1 extra consecutive dodge
- `broker_passive_improved_sprint_dodge`: Sprint dodge angle threshold reduced by 15 degrees
- `broker_passive_improved_dodges_at_full_stamina`: At 75%+ stamina, -40% dodge cooldown
- `broker_passive_sprinting_reduces_threat`: Sprinting reduces enemy threat weight (stacks 4x)
- `broker_passive_increased_ranged_dodges`: +1 extra consecutive dodge while wielding ranged weapon

**Weapon Handling:**
- `broker_passive_reduce_swap_time`: +40% wield speed, -10% recoil, -30% spread
- `broker_passive_extended_mag`: +15% clip size
- `broker_passive_reload_speed_on_close_kill`: +30% reload speed for 8s after close-range kill
- `broker_passive_stamina_grants_atk_speed`: +2% attack speed per stamina point (stacks 15x)

**Toxin:**
- `broker_passive_melee_attacks_apply_toxin`: Melee attacks apply 1 stack of Chem Toxin
- `broker_passive_weakspot_on_x_hit`: Every 6th hit counts as weakspot
- `broker_passive_close_range_rending`: +15% rending at close range
- `broker_passive_stun_on_max_toxin_stacks`: Enemies stunned at max toxin stacks (3s)
- `broker_passive_reduced_damage_by_toxined`: Toxined enemies deal -15% damage (-30% for monsters)
- `broker_passive_damage_after_toxined_enemies`: +5% damage per toxin stack on nearby enemies (max +15%, 12.5m)
- `broker_passive_toughness_on_toxined_kill`: +15% toughness on killing toxined enemy
- `broker_passive_increased_toxin_damage`: +10% toxin DoT damage
- `broker_passive_blitz_charge_on_kill`: Regain 1 grenade charge per 20 kills

**Stimm:**
- `broker_passive_stimm_increased_duration`: +5s to Cartel Special duration
- `broker_passive_stimm_cleanse_on_kill`: Kills during stimm cleanse 1% corruption (up to 50% threshold)
- `broker_passive_stimm_cd_on_kill`: Kills restore 1% stimm cooldown (2% for toxined targets)
- `broker_passive_dr_damage_tradeoff_on_stamina`: +20% damage but +20% damage taken based on stamina
- `broker_passive_ammo_on_backstab`: Backstabs restore 1% ammo (5s cooldown)
- `broker_passive_increased_aura_size`: +75% coherency radius

---

## Ability Template Summary for Bot Implementation

| Ability | Template | Type | Input | `ability_meta_data` | Bot Tier |
|---|---|---|---|---|---|
| Enhanced Desperado | `broker_focus` | `stance_change` | `combat_ability_pressed` | Yes (`stance_pressed`) | Tier 1 |
| Rampage | `broker_punk_rage` | `stance_change` | `combat_ability_pressed` | Yes (`stance_pressed`) | Tier 1 |
| Stimm Field | None (item-based) | `inventory_item` | Wield + use | No | Tier 3 |
| Cartel Special | None (pocketable) | `pocketable_ability` | Wield + use | No | Tier 3 |
| Flash Grenade | None (inventory item) | `grenade_ability` | `grenade_ability_pressed` | No | Tier 3 |
| Tox Grenade | None (inventory item) | `grenade_ability` | `grenade_ability_pressed` | No | Tier 3 |
| Missile Launcher | None (inventory item) | `grenade_ability` | `grenade_ability_pressed` | No | Tier 3 |

---

## Practical Usage (from community guides)

### When to use Enhanced Desperado (Focus)
- Activate before engaging a group of ranged specials/elites at close-mid range
- Use for the toughness refill when shields are low
- The free ammo allows sustained fire without conservation
- Sprint through enemies with noclip talent to reposition
- Best paired with Vulture's Mark keystone for ranged elite hunting

### When to use Rampage (Punk Rage)
- Activate when surrounded by melee enemies or engaging a horde
- Use the instant toughness refill as an emergency defensive tool
- The stun/slowdown immunity allows uninterrupted melee combos
- With Sub 3 (shout), activation disrupts nearby enemy attacks -- use when being swarmed
- Extend duration by continuously hitting enemies; elites give more extension with Sub 4

### When to use grenades/blitz
- Flash grenades: crowd control tool, throw into dense groups before engaging
- Tox grenades: area denial at chokepoints and synergy with Chemist talents
- Missile launcher: save for monsters, bosses, or tightly packed elite groups

### Positioning/priority tips
- Hive Scum excels at close range (12.5m) where many damage bonuses activate
- Dodge-heavy playstyle -- many talents reward successful dodges
- The class is fragile at 75 toughness and 150 HP, so ability timing is critical for survivability
- Stimm usage should be proactive (before fights), not reactive
- In team play, stay in coherency for aura benefits but play aggressively at the front

---

## Source Files

| File | Path |
|---|---|
| Archetype definition | `scripts/settings/archetype/archetypes/broker_archetype.lua` |
| Ability templates | `scripts/settings/ability/ability_templates/broker_focus.lua` |
| | `scripts/settings/ability/ability_templates/broker_punk_rage.lua` |
| Player abilities | `scripts/settings/ability/player_abilities/abilities/broker_abilities.lua` |
| Talent settings | `scripts/settings/talent/talent_settings_broker.lua` |
| Talent definitions | `scripts/settings/ability/archetype_talents/talents/broker_talents.lua` |
| Buff templates | `scripts/settings/buff/archetype_buff_templates/broker_buff_templates.lua` |
| Toughness template | `scripts/settings/toughness/archetype_toughness_templates.lua` |
| Stamina template | `scripts/settings/stamina/archetype_stamina_templates.lua` |

---

## Community Sources

- [Steam Community: Hive Scum Talents & Mechanics [1.10.x]](https://steamcommunity.com/sharedfiles/filedetails/?id=3586590987)
- [Fatshark Dev Blog: Hive Scum Class Design & Talents](https://www.playdarktide.com/news/dev-blog-hive-scum-class-design-talents)
- [PCGamer: Best Hive Scum Build](https://www.pcgamer.com/games/fps/warhammer-40k-darktide-hive-scum-build-best/)
- [Games Lantern: Complete Hive Scum Operative Guide](https://darktide.gameslantern.com/user/br1ckst0n/guide/the-complete-hive-scum-operative-guide)
- [Games Lantern: Hive Scum Class Overview](https://darktide.gameslantern.com/classes/hive-scum)
- [Steam Community: Hive Scum Builds (Auric+)](https://steamcommunity.com/sharedfiles/filedetails/?id=3667251410)
