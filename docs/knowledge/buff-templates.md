# Buff Template Values — All 6 Classes (v1.10.7)

Source: decompiled `scripts/settings/buff/archetype_buff_templates/*.lua`
Cross-referenced with `talent_settings_*.lua` for resolved numerical values.

This is the exhaustive reference. For a concise summary, see `class-talents.md`.

---

## VETERAN

### Stealth / Invisibility

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| veteran_invisibility | movement_speed | +0.25 | 8s; keywords: invisible |
| veteran_damage_bonus_leaving_invisibility | damage | +0.30 | 5s post-stealth |
| veteran_toughness_bonus_leaving_invisibility | toughness_damage_taken_multiplier | 0.50 | 10s post-stealth (50% TDR) |
| veteran_reduced_threat_generation | threat_weight_multiplier | 0.10 | 10s (90% threat reduction) |
| veteran_increased_close_damage_after_combat_ability | damage_near | +0.15 | 10s post-ability |
| veteran_increased_weakspot_power_after_combat_ability | weakspot_power_level_modifier | +0.20 | 10s post-ability |

### Grenades

| Template | Stat | Value |
|----------|------|-------|
| veteran_extra_grenade | extra_max_amount_of_grenades | +1 |
| veteran_improved_grenades | frag_damage | +0.25 |
| | explosion_radius_modifier_frag | +0.25 |
| | krak_damage | +0.75 |
| | smoke_fog_duration_modifier | +1.00 (doubles) |
| veteran_increased_explosion_radius | explosion_radius_modifier | +0.225 |

### Keystones

**Sniper's Focus** (`veteran_snipers_focus_stat_buff`): duration 5s, max 10 stacks (15 improved)
| Stat | Per Stack |
|------|-----------|
| ranged_finesse_modifier_bonus | +0.075 |
| reload_speed | +0.01 |
| toughness_replenish_modifier | +0.04 (with toughness talent) |
| At 10 stacks: rending_multiplier | +0.15 (via `veteran_snipers_focus_rending_buff`) |

**Weapon Switch** (`veteran_weapon_switch_*`):
| Buff | Stat | Value | Duration |
|------|------|-------|----------|
| ranged_buff | ranged_attack_speed | +0.02/stack | 10s, max 10 |
| | reload_speed | +0.02/stack | |
| | ranged_critical_strike_chance | +0.33 (first shot only) | conditional |
| melee_buff | melee_attack_speed | +0.15 | 10s |
| | dodge_speed_multiplier | ×1.1 | |
| | dodge_distance_modifier | +0.10 | |
| replenish_stamina | stamina | +20% on swap | |
| replenish_toughness | toughness | +20% on swap | 3s CD |
| replenish_ammo | ammo | +3.3% on swap | |
| reload_speed | reload_speed | +0.20 | 10s |
| melee_stamina_reduction | stamina_cost_multiplier | 0.75 | 3s |

**Focus Target** — see talent_settings (stacks every 1.5s, max 4/6). Damage values in buff_template are dynamic.

### Damage / Offense

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| veteran_increase_elite_damage | damage_vs_elites | +0.15 | passive |
| veteran_big_game_hunter | damage_vs_ogryn_and_monsters | +0.20 | passive |
| veteran_rending_bonus | rending_multiplier | +0.10 | passive |
| veteran_increase_crit_chance | critical_strike_chance | +0.10 | passive |
| veteran_flanking_damage | flanking_damage | +0.30 | passive; kw: allow_flanking |
| veteran_increase_suppression | suppression_dealt | +0.75 | passive |
| veteran_attack_speed | melee_attack_speed | +0.10 | passive |
| veteran_increased_melee_crit_chance_and_melee_finesse | melee_critical_strike_chance | +0.10 | passive |
| | melee_finesse_modifier_bonus | +0.25 | |
| veteran_reduce_swap_time | wield_speed | +0.50 | passive |
| veteran_reduce_sprinting_cost | sprinting_cost_multiplier | 0.80 | passive (−20%) |
| veteran_damage_after_sprinting_buff | damage | +0.0625/stack | 10s, max 4 (=+25%) |
| veteran_melee_kills_grant_range_damage | ranged_damage | +0.25 | 6s proc |
| veteran_ranged_kills_grant_melee_damage | melee_damage | +0.25 | 6s proc |
| veteran_melee_crits_increase_damage | damage | +0.20 | 6s proc |
| veteran_bonus_crit_chance_on_ammo | ranged_critical_strike_chance | +0.10 | conditional: ≥80% clip |

### Critical Strike

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| veteran_dodging_crit_buff | critical_strike_chance | +0.05/stack | 8s, max 5 (=+25%) |

### Toughness / Defense

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| veteran_tdr_on_high_toughness | toughness_damage_taken_multiplier | 0.50 | conditional: >75% toughness |
| veteran_all_kills_replenish_bonus_toughness | toughness_percentage | 0.05 or 0.10 | per kill (tier-dependent) |
| veteran_movement_speed_on_toughness_broken | movement_speed | +0.12 | 5s proc |
| veteran_movement_bonuses_on_toughness_broken | stun_immune + slowdown_immune | +50% stamina | 6s proc, 20s CD |
| veteran_hits_cause_bleed | bleed stacks | 2 per hit | proc on target |
| veteran_crits_apply_rending | rending_debuff_medium | applied to target | proc on melee crit |
| veteran_consecutive_hits_apply_rending | rending_debuff | applied to target | proc on consecutive hits |

### Coherency Auras

| Template | Stat | Value |
|----------|------|-------|
| veteran_damage_coherency | damage | +0.075 |
| veteran_movement_speed_coherency | movement_speed | +0.05 |
| veteran_combat_ability_increase_toughness_to_coherency | toughness_bonus_flat | +50 | 10s on ability |

### Deployables

| Template | Effect |
|----------|--------|
| veteran_better_deployables | keywords: improved_medical_crate, improved_ammo_pickups (grenades from ammo, corruption from healing) |

---

## ZEALOT

### Stealth / Invisibility

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| zealot_invisibility | movement_speed | +0.20 | 3s base, 20s improved |
| | critical_strike_chance | +1.00 (100%) | |
| | finesse_modifier_bonus | +1.50 | |
| | backstab_damage | +1.50 | |
| | flanking_damage | +1.50 | |
| | melee_rending_multiplier | +1.00 (100%) | |
| zealot_leaving_stealth_restores_toughness | damage_taken_multiplier | 0.70 (−30% DR) | 8s post-stealth |
| zealot_decrease_threat_increase_backstab_damage | threat_weight_multiplier | 0.25 | 5s; backstab_damage +0.50 |
| zealot_increase_ability_cooldown_increase_bonus | ability_cooldown_flat_reduction | −5s | passive |
| (same, conditional during stealth) | finesse_modifier_bonus | +0.50 | |
| | backstab_damage | +0.50 | |
| zealot_stealth_improved_with_block | perfect_block_timing | +0.20 | 8s; kw: block_unblockable |

### Keystones

**Fanatic Rage** (`zealot_fanatic_rage`): max 25 stacks, 8s duration
| Condition | Stat | Value |
|-----------|------|-------|
| At max stacks | toughness_damage_taken_multiplier | 0.75 (−25% TDR) |
| At max stacks | toughness restore | 50% instant, +2%/s ongoing |
| zealot_fanatic_rage_buff | critical_strike_chance | +0.15 | 8s |
| (with improved talent) | critical_strike_chance | +0.10 additional |

**Quickness** (`zealot_quickness_active`): max 20 stacks, 6s (10s improved)
| Stat | Per Stack |
|------|-----------|
| melee_attack_speed | +0.01 |
| ranged_attack_speed | +0.01 |
| damage | +0.01 |
| dodge_speed_multiplier | ×1.005 |
| dodge_distance_modifier | +0.005 |
| dodge_cooldown_reset_modifier | −0.01 |
| (momentum talent) toughness | +0.004 × stacks/s |

### Toughness Restoration

| Template | Value | Notes |
|----------|-------|-------|
| zealot_toughness_on_heavy_kills | 10% | per heavy kill |
| zealot_toughness_on_dodge | 15% | 0.5s CD |
| zealot_toughness_on_ranged_kill | 4% | per ranged kill |
| zealot_toughness_regen_in_melee | 2.5%/s base | +1%/s per nearby enemy (5m), cap 7.5%/s |

### Offense

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| zealot_backstab_damage | backstab_damage | +0.25 | passive; +flanking_damage +0.25 |
| zealot_flanking_damage | flanking_damage | +0.30 | passive; kw: allow_flanking |
| zealot_critstrike_damage_on_dodge | finesse_modifier_bonus | +0.50 | 3s proc on dodge |
| zealot_improved_weapon_swapping_impact | melee_impact_modifier | +0.30 | 5s on empty clip |
| (same) | melee_attack_speed | +0.10 | |
| zealot_improved_weapon_swapping_reload_speed_buff | reload_speed | +0.06/stack | max 5 stacks on melee kill |
| (same) | wield_speed | +0.06/stack | |
| zealot_pious_stabguy_increased_weakspot_impact | melee_weakspot_impact_modifier | +0.50 | passive |
| zealot_improved_weapon_handling_after_dodge | spread_modifier | −0.75 | 3s proc on dodge |
| (same) | recoil_modifier | −0.50 | |

### Sprint

| Template | Stat | Value |
|----------|------|-------|
| zealot_sprint_improvements | sprinting_cost_multiplier | 0.90 (−10%) |
| (same) | sprint_movement_speed | +0.10 |
| zealot_sprinting_cost_reduction | sprinting_cost_multiplier | 0.80 (−20%) |
| zealot_increased_sprint_speed | sprint_movement_speed | +0.05 |

---

## PSYKER

### Keystones

**Warp Siphon / Souls** (`psyker_souls`): max 4 stacks (6 improved), 25s duration
| Template | Stat | Value |
|----------|------|-------|
| psyker_souls_increase_damage | damage (lerped 0→max souls) | 0 → +0.24 |
| psyker_reduced_warp_charge_cost_and_venting_speed | warp_charge_amount (lerped) | 1.0 → 0.52 |
| psyker_souls_replenish_toughness_stacking_buff | toughness regen | 6%/s for 5s |
| Per soul: ability CDR | | −7.5% per soul |

**Disrupt Destiny / Marks** (`psyker_marked_enemies_passive_bonus_stacking`): max 15 (25 improved), 5s (10s improved)
| Stat | Per Stack |
|------|-----------|
| damage | +0.01 |
| critical_strike_damage | +0.02 |
| weakspot_damage | +0.025 |
| (per-mark proc, 2.5s) movement_speed | +0.20; toughness 25% over duration |

**Overcharge Stance** (`psyker_overcharge_stance`):
| Stat | Value | Notes |
|------|-------|-------|
| damage (base) | +0.10 flat | + lerped 0→+0.30 over 30s |
| weakspot_damage | +0.10 | flat |
| critical_strike_chance | +0.20 | |
| finesse_modifier_bonus (weakspot variant) | lerped 0→+0.30 | |
| toughness regen | 2.5%/s | |
| keywords | suppression_immune, psychic_fortress | |

Post-stance (`psyker_overcharge_stance_damage`): duration 10s, max 30 stacks
- damage: +0.01/stack accumulated during stance

Conditional during stance:
| Template | Stat | Value |
|----------|------|-------|
| psyker_overcharge_reduced_warp_charge | warp_charge_amount | 0.80 (−20%) |
| psyker_overcharge_reduced_toughness_damage_taken | toughness_damage_taken_multiplier | 0.80 |
| psyker_overcharge_increased_movement_speed | movement_speed | +0.20 |

### Abilities

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| psyker_shout_warp_generation_reduction | warp_charge_amount | 0.99/stack (0.98 improved) | 5s, max 25 stacks |
| psyker_efficient_smites | warp_charge_amount_smite | 0.50 | 10s post-ability |
| | smite_attack_speed | +0.75 | |
| psyker_combat_ability_extra_charge | ability_extra_charges | +1 | |
| psyker_boost_allies_in_sphere_end_buff | toughness_damage_taken_multiplier | 0.50 | 5s after Veil expires |
| psyker_force_field_buff | toughness_damage_taken_multiplier | 0.80 | 6s on barrier pass |
| | movement_speed | +0.10 | |

### Passive Nodes

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| psyker_damage_to_peril_conversion | damage_taken_multiplier | 0.75 | conditional: peril <97% |
| psyker_damage_resistance_stun_immunity | damage_taken_multiplier | 0.90 | at peril ≥97%; stun_immune |
| psyker_damage_vs_ogryns_and_monsters | damage_vs_ogryn_and_monsters | +0.20 | |
| psyker_warp_glass_cannon | warp_charge_amount | 0.60 (−40% peril gen) | toughness_replenish ×0.70 |
| psyker_melee_attack_speed | melee_attack_speed | +0.10 | +ranged_attack_speed +0.10 |
| psyker_melee_toughness | toughness_melee_replenish | +1.0 | enables melee toughness regen |
| psyker_improved_dodge | extra_consecutive_dodges | +1 | dodge_linger +0.50 |
| psyker_stat_mix | warp_charge_dissipation | +0.20 | +2 stamina, +25% toughness replenish |
| psyker_coherency_aura_size_increase | coherency_radius_modifier | +0.75 | |
| psyker_brain_burst_improved | smite_damage_multiplier | +1.50 (2.5× total) | |
| psyker_reduced_throwing_knife_cooldown | grenade_ability_cooldown_modifier | −0.30 | |
| psyker_increased_vent_speed | vent_warp_charge_speed | +0.70 | |
| psyker_alternative_peril_explosion | explosion_damage | +1.00 (doubles) | radius +0.25, speed ×1.65 |
| psyker_reload_speed_warp | reload_speed | +0.30 | conditional: peril ≤75% |
| psyker_block_costs_warp_charge | warp_charge_block_cost | 0.25 | conditional: peril <97% |

### Peril Scaling (lerped by peril %)

| Template | Stat | Min→Max |
|----------|------|---------|
| psyker_warp_charge_increase_force_weapon_damage | damage | 0→+0.20 |
| psyker_warp_charge_reduces_toughness_damage_taken | toughness_damage_taken_multiplier | 0.90→0.67 |
| psyker_warp_attacks_rending | warp_attacks_rending_multiplier | 0→+0.20 |
| psyker_cleave_from_peril | max_hit_mass_attack_modifier | 0→+1.00 |
| psyker_force_staff_wield_speed | wield_speed | 0→+0.50 |
| psyker_force_staff_melee_attack_bonus | force_staff_melee_damage | 0→+1.00 |

### Stacking Combat Buffs

| Template | Stat | Per Stack | Duration/Max |
|----------|------|-----------|--------------|
| psyker_cycle_stacking_warp_damage | warp_damage | +0.05 | 8s, max 5 |
| psyker_cycle_stacking_non_warp_damage | damage | +0.05 | 8s, max 5 |
| psyker_cycle_stacking_melee_damage_stacks | melee_damage | +0.05 | max 4 |
| psyker_cycle_stacking_ranged_damage_stacks | ranged_damage | +0.05 | max 4 |
| psyker_crits_empower_warp_buff | damage | +0.03 | 10s, max 5 |
| psyker_stacking_movement_buff | movement_speed | +0.05 | 4s, max 3 |
| psyker_throwing_knife_stacking_speed_buff | knife_speed_modifier | +0.05 | 8s, max 5 |
| psyker_force_staff_quick_attack_debuff (enemy) | warp_damage_taken_multiplier | ×1.06 | 10s, max 5 |

### Empowered Psyche (charge stacks)

`psyker_empowered_grenades_passive_visual_buff`: max 2 (4 with talent), consumed on use
| Stat | Value |
|------|-------|
| chain_lightning_damage | +2.0 |
| chain_lightning_jump_time_multiplier | +0.50 |
| psyker_smite_cost_multiplier | 0 (free smite) |
| smite_attack_speed | +0.50 |
| smite_damage | +0.50 |

### Coherency Auras

| Template | Stat | Value |
|----------|------|-------|
| psyker_aura_damage_vs_elites | damage_vs_elites | +0.10 |
| psyker_aura_crit_chance_aura | critical_strike_chance | +0.05 |
| psyker_aura_ability_cooldown | ability_cooldown_modifier | −0.075 |
| psyker_aura_ability_cooldown_improved | ability_cooldown_modifier | −0.10 |

### Toughness

| Template | Value | Notes |
|----------|-------|-------|
| psyker_toughness_on_warp_kill | 7.5% | instant on warp kill |
| psyker_toughness_on_warp_generation/vent | Δ% × 0.40 | proportional to peril change |
| psyker_killing_enemy_with_warpfire_boosts | +5% crit, 15% toughness over 5s | |
| psyker_soulblaze_reduces_damage_taken | toughness_damage_taken_multiplier 0.67 | 3s proc |

### Misc

| Template | Effect |
|----------|--------|
| psyker_venting_improvements | removes movement penalty during vent/reload |
| psyker_smite_vulnerable_debuff (enemy) | +25% non-warp damage taken, 5s |
| psyker_increased_chain_lightning_size | +1 max jumps, +1 max radius |
| psyker_force_staff_bonus_buff | +20% single target damage, 5s |
| psyker_force_staff_secondary_bonus_buff | +10% secondary damage, 5s |
| psyker_cooldown_buff | −0.6s/s ability CD regen, 5s on team elite kill |
| psyker_discharge_damage_debuff (self) | −10% damage, +10% damage taken, 8s |
| psyker_melee_weaving | −20% warp gen + vents 10% peril, 4s on melee weakspot kill |
| psyker_ranged_crits_vent | vents 4% peril on non-warp ranged crit |

---

## OGRYN

### Base Passives (always active)

| Template | Stat | Value |
|----------|------|-------|
| ogryn_base_passive_tank | damage_taken_multiplier | 0.80 (−20% DR) |
| | toughness_damage_taken_multiplier | 0.75 (−25% TDR) |
| | static_movement_reduction_multiplier | 0 |
| ogryn_base_passive_revive | revive_speed_modifier | +0.25 |
| | assist_speed_modifier | +0.25 |
| ogryn_corruption_resistance | corruption_taken_multiplier | 0.60 (−40%) |

### Keystone: Heavy Hitter

`ogryn_heavy_hitter_damage_effect`: duration 7.5s, max 8 stacks
| Stat | Per Stack | At Max (8) |
|------|-----------|------------|
| melee_damage | +0.03 | +0.24 |
| toughness_damage_taken_multiplier (lerped) | ×0.9875 | ×0.90 (−10% TDR) |
| max_melee_hit_mass_attack_modifier (lerped) | +0.125 | +1.00 (doubles cleave) |
| melee_impact_modifier (lerped) | +0.075 | +0.60 (+60% stagger) |
| toughness_melee_replenish (lerped) | +0.15 | +1.20 |
| attack_speed (at max only) | — | +0.10 |

### Keystone: Carapace Armor (Feel No Pain)

`ogryn_carapace_armor_child`: max 10 stacks, start at max, decrements on hit
| Stat | Per Stack |
|------|-----------|
| toughness_replenish_modifier | +0.03 |
| toughness_damage_taken_multiplier | ×0.97 |
| (with toughness talent) | +0.025 additional replenish |

At zero stacks: explosion + 50% toughness restore (30s CD).

### Point-Blank Barrage (Ranged Stance)

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| ogryn_ranged_stance | ranged_attack_speed | +0.25 | 10s |
| | reload_speed | +0.65 | |
| ogryn_ranged_stance_no_movement_penalty_buff | movespeed_reduction_multiplier | 0.50 | conditional: ranged |
| | damage_near | +0.15 | |
| ogryn_ranged_stance_armor_pierce | ranged_rending_multiplier | +0.15 | |
| | ranged_damage | +0.15 | |
| ogryn_ranged_stance_toughness_regen | toughness per shot | 2.5% | |
| | toughness per reload | 15% | |

### Bull Rush Buffs

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| ogryn_charge_speed_on_lunge | movement_speed | +0.25 | 5s post-lunge |
| | melee_attack_speed | +0.25 | |
| ogryn_charge_trample_buff | damage | +0.025/stack | 10s, max 20 (=+50%) |
| ogryn_base_lunge_toughness_and_damage_resistance | melee_heavy_damage | +0.50 | during lunge |
| | damage_taken_multiplier | 0.75 | |
| ogryn_allied_movement_speed_buff | movement_speed | +0.20 | 6s for allies |

### Offense

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| ogryn_crit_damage_increase | critical_strike_damage | +0.75 | passive |
| ogryn_far_damage | damage_far | +0.15 | passive |
| ogryn_weakspot_damage | melee_weakspot_power_modifier | +0.10 | passive |
| ogryn_increased_ammo_reserve_passive | ammo_reserve_capacity | +0.25 | passive |
| ogryn_increased_clip_size | clip_size_modifier | +0.25 | passive |
| ogryn_increased_suppression | suppression_dealt | +0.25 | passive |
| ogryn_suppress_increase | suppression_dealt | +0.25 | passive |
| ogryn_passive_stagger | melee_impact_modifier | +0.25 | passive; +5% stamina/stagger |
| ogryn_better_ogryn_fighting | damage_vs_ogryn | +0.30 | +30% DR from plague ogryns |
| ogryn_increased_reload_speed_on_multiple_hits_effect | reload_speed | +0.15 | proc on 3+ hits |
| ogryn_increased_damage_after_reload | ranged_damage | +0.15 | 8s post-reload |
| ogryn_rending_on_elite_kills | rending_multiplier | +0.10 | 10s proc |
| ogryn_fully_charged_attacks_gain_damage_and_stagger | melee_damage | +0.40 | during charged swing |
| | melee_impact_modifier | +0.40 | |
| ogryn_melee_damage_after_heavy | melee_damage | +0.15 | 5s proc |
| ogryn_block_increases_power_active_buff | melee_impact_modifier | +0.10/stack | 6s, max 8 (=+80%) |
| ogryn_stacking_attack_speed_active_buff | melee_attack_speed | +0.025/stack | 5s, max 5 (=+12.5%) |
| ogryn_melee_revenge_damage_buff | damage | +0.15 | 5s proc on hit received |
| ogryn_hitting_multiple_with_melee | melee_damage (lerped) | 0→+0.30 | per sweep (scales with targets) |
| ogryn_big_bully_heavy_hits_buff | melee_heavy_damage | +0.01/stack | 10s, max 25 |
| ogryn_block_all_attacks_perfect_damage_boost | melee_damage | +0.20 | 5s on perfect block |
| ogryn_windup_increases_power_child | melee_damage +0.0375, impact +0.075 | per stack | max 4 |
| ogryn_stagger_cleave_on_third_active_buff | hit_mass +0.25, impact +0.25 | | at 3 stacks |
| ogryn_big_box_of_hurt_more_bombs | cluster_amount | +3 | passive |
| ogryn_movement_speed_on_ranged_kill | movement_speed | +0.20 | 3s proc |

### Defense

| Template | Stat | Value | Duration/Notes |
|----------|------|-------|----------------|
| ogryn_melee_attacks_give_mtdr_stacking_buff | melee_damage_taken_multiplier | ×0.96/stack | max 5 (≈18.5% DR) |
| ogryn_ranged_damage_immunity | ranged_damage_taken_multiplier | 0.80 | 2.5s, 4s CD |
| ogryn_movement_boost_on_ranged_damage | ranged_damage_taken_multiplier | 0.25 | 1s(!), 6s CD |
| ogryn_windup_reduces_damage_taken | damage_taken_multiplier | 0.85 | during windup |
| ogryn_bracing_reduces_damage_taken | damage_taken_multiplier | 0.75 | while braced |
| ogryn_damage_reduction_on_high_stamina | damage_taken_multiplier | 0.875 | conditional: stamina >75% |
| ogryn_damage_reduction_after_elite_kill | damage_taken_multiplier | 0.90 | 5s proc |
| ogryn_reduce_damage_taken_per_bleed | damage_taken_multiplier (lerped) | 1.0→0.70 | per nearby bleeding enemy, max 6 |
| ogryn_reduce_damage_taken_on_disabled_allies | damage_taken_multiplier (lerped) | 1.0→0.40 | per downed ally, max 3 |
| ogryn_increased_toughness_at_low_health | toughness_replenish_modifier | +1.00 | conditional: HP <50% |
| ogryn_block_cost_reduction | block_cost_multiplier | 0.80 | passive |
| ogryn_blocking_reduces_push_cost | push_cost_multiplier | 0.80 | 5s proc |
| ogryn_empowered_push | push_impact_modifier | +2.50 | 8s CD |
| ogryn_protect_allies_toughness_broken | toughness_damage_taken_multiplier 0.75, power +0.10 | | 10s, 20s CD |
| ogryn_protect_allies | revive_speed_modifier +0.25 | stun_immune | 10s on ally down |
| ogryn_increased_coherency_regen | toughness_regen_rate_modifier | +1.00 (doubles) | passive |
| ogryn_wield_speed_increase | wield_speed | +0.20 | passive |
| ogryn_taking_damage_improves_handling | spread −0.35, recoil −0.35 | | 5s proc |
| ogryn_drain_stamina_for_handling | spread −0.20, recoil −0.15 | costs 0.5 stam/s | while braced |
| ogryn_decrease_suppressed_decay | suppressor_decay_multiplier | 0.50 | passive |

### Taunt

| Template | Stat | Value |
|----------|------|-------|
| ogryn_taunt_radius_increase | shout_radius_modifier | +0.50 |
| ogryn_taunt_increased_damage_taken_buff (enemy) | damage_taken_multiplier | ×1.20 | 15s |
| ogryn_taunt_restore_toughness_over_time | toughness | 10% instant + 0.5%/s × stacks | 3.25s, max 20 stacks |

### Leadbelcher Stacking

| Template | Stat | Per Stack | Max |
|----------|------|-----------|-----|
| ogryn_blo_stacking_buff | ranged_damage | +0.02 | 10s, max 10 (=+20%) |
| ogryn_blo_wield_speed (lerped) | wield_speed | +0.015 | max 10 (=+15%) |
| ogryn_blo_fire_rate (lerped) | ranged_attack_speed | +0.015 | max 10 (=+15%) |
| ogryn_blo_melee_active_buff | leadbelcher_chance_bonus | +0.10 | max 10 (=+100%) |
| ogryn_blo_ally_ranged_buff | ranged_damage | +0.15 | 8s for allies |

### Stacking Toughness/Power

| Template | Stat | Per Stack | Max |
|----------|------|-----------|-----|
| ogryn_crit_chance_on_kill_effect | critical_strike_chance | +0.02 | 12s, max 8 (=+16%) |
| ogryn_melee_improves_ranged_stacking_buff | ranged_damage | +0.03 | 10s, max 5 (=+15%) |
| ogryn_damage_taken_by_all_increases_strength | power_level_modifier | +0.02 | 10s, max 5 (=+10%) |
| (at max 5 stacks) | toughness_damage_taken_multiplier | 0.85 | |
| ogryn_ranged_improves_melee | melee_damage +0.15, melee_attack_speed +0.075 | | 6s proc |

### Coherency Auras

| Template | Stat | Value |
|----------|------|-------|
| ogryn_aura_increased_damage_vs_suppressed | damage_vs_suppressed | +0.20 |
| ogryn_coherency_increased_melee_damage | melee_damage | +0.075 |
| ogryn_melee_damage_coherency_improved | melee_damage | +0.10 |
| ogryn_toughness_regen_aura | toughness_replenish_modifier | +0.20 |
| ogryn_bigger_coherency_radius | coherency_radius_modifier | +0.75 |

---

## ADAMANT (Arbites)

### Hunt Stance

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| adamant_hunt_stance | movement_speed | +0.15 | 10s |
| | damage_taken_multiplier | 0.20 | (×0.2 = −80% DR) |
| | movespeed_reduction | 0 | |
| adamant_hunt_stance_linger_dr | damage_taken_multiplier | 0.20 | 2s post-stance |
| adamant_hunt_stance_damage | damage | +0.05/stack | 10s, max 10 (on elite kills) |
| adamant_hunt_stance_dog_bloodlust | companion_damage_modifier | +0.75 | during stance |

### Charge

| Template | Stat | Value |
|----------|------|-------|
| adamant_post_charge_buff | damage +0.25, impact +0.50 | 6s |
| adamant_charge_increased_distance | lunge_distance | +3.75 |
| adamant_charge_cooldown_buff | CDR | 0.5s/hit, 1s/elite, cap 5s |
| adamant_charge_toughness_buff | toughness | 20%/elite, 15% stamina/hit |
| adamant_charge_passive_buff | keywords | count_as_blocking, dodge vs hound/netgunner |

### Drone (Nuncio-Aquila)

| Template | Stat | Value |
|----------|------|-------|
| adamant_drone_base_buff | toughness regen | 5%/s |
| adamant_drone_improved_buff | toughness regen | 7.5%/s |
| | suppression_dealt +0.30, impact +0.30 | |
| | recoil | −0.25 | + suppression/slowdown immune |
| adamant_drone_talent_buff | toughness_damage_taken_multiplier | 0.70 |
| | revive_speed +0.30, attack_speed +0.10 | |
| adamant_drone_enemy_debuff (enemy) | damage_taken_multiplier | ×1.15 |
| adamant_drone_talent_debuff (enemy) | melee_attack_speed −0.25, melee_damage −0.25 | |

### Keystone: Execution Order

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| adamant_execution_order_buff | damage +0.10, attack_speed +0.10 | | 8s on marked kill |
| adamant_execution_order_crit | crit_chance +0.10, crit_damage +0.25 | | 8s |
| adamant_execution_order_rending | rending_multiplier +0.10 | | 8s |
| adamant_execution_order_cdr | CDR | 0.5s/s for 8s |
| adamant_execution_order_permastack | damage_vs_monsters +0.01/stack | max 30 | permanent |
| adamant_execution_order_companion_buff | companion_damage +1.50 | | 8s |

### Keystone: Forceful

`adamant_forceful_stacks`: max 10, 5s each
| Stat | Per Stack |
|------|-----------|
| impact_modifier | +0.05 |
| damage_taken_multiplier | ×0.975 (−2.5%) |
| (ranged talent) ranged_attack_speed | +0.025 |
| (ranged talent) reload_speed | +0.02 |
| (toughness talent) toughness | 0.5%/s |

At max stacks:
| Template | Stat | Value |
|----------|------|-------|
| adamant_forceful_offensive | attack_speed +0.10, cleave +0.50 | + 3s linger |
| adamant_forceful_stun_immune | stun_immune, slowdown_immune | + 3s linger |
| adamant_forceful_strength_stacks | power_level +0.025/stack | 12s |

### Keystone: Terminus Warrant

| Template | Stat | Value |
|----------|------|-------|
| adamant_terminus_warrant_melee_stat_buff | melee_damage +0.15, impact +0.25 | |
| | (talent) toughness_melee_replenish +1.0 | |
| adamant_terminus_warrant_ranged_stat_buff | ranged_damage +0.15, suppression +0.50 | |
| | ranged_cleave +0.50 | (talent) reload +0.20 |
| On swap with 15+ stacks: | attack_speed | +0.15 (opposite slot) |
| On swap with 30+ melee stacks: | melee_rending | +0.15 |
| On swap with 30+ ranged stacks: | crit_damage +0.25, weakspot +0.25 | |

### Passive Offense

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| adamant_damage_vs_suppressed | damage_vs_suppressed | +0.25 | passive |
| adamant_monster_hunter | damage_vs_ogryn_and_monsters | +0.20 | passive |
| adamant_increased_damage_to_high_health | damage_vs_healthy | +0.15 | passive (≥75% HP) |
| adamant_increased_damage_vs_horde | damage_vs_horde | +0.20 | passive |
| adamant_crits_rend | ranged_crit_rending | +0.20 | passive |
| adamant_melee_attacks_on_staggered_rend | melee_rending_vs_staggered | +0.15 | passive |
| adamant_ranged_damage_on_melee_stagger | ranged_damage | +0.15 | 5s proc |
| adamant_damage_after_reloading | ranged_damage | +0.15 | 5s proc |
| adamant_cleave_after_push | melee_cleave | +0.75 | 5s proc |
| adamant_heavy_attacks_increase_damage | damage | +0.15 | 5s proc |
| adamant_elite_special_kills_offensive_boost | damage +0.10, movement +0.10 | | 4s proc |
| adamant_perfect_block_damage_boost_buff | damage +0.15, attack_speed +0.15 | | 8s on perfect block |
| adamant_dodge_grants_damage | damage | +0.15 | 5s on dodge |
| adamant_stacking_damage_buff | damage | +0.02/stack | 5s, max 5 |
| adamant_multiple_hits_attack_speed | melee_attack_speed | +0.10 | 3s on 3+ targets |
| adamant_stacking_weakspot_strength_buff | weakspot_power | +0.02/stack | 10s, max 8 |
| adamant_crit_chance_on_kill_effect | crit_chance | +0.02/stack | 10s, max 8 |
| adamant_wield_speed_on_melee_kill_buff | wield_speed | +0.05/stack | 8s, max 5 |
| adamant_increased_reload_speed_elite_kill | reload_speed | +0.20 | until reload done |
| adamant_first_melee_hit_increased_damage | melee_damage +0.15, impact +0.30 | | first hit of sweep |

### Passive Defense

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| adamant_armor | toughness | +25 flat | passive |
| adamant_plasteel_plates | toughness | +25 flat | passive |
| adamant_limit_dmg_taken_from_hits | max_health_damage_per_hit | 50 | passive |
| adamant_damage_reduction_after_elite_kill | damage_taken_multiplier | 0.75 | 5s proc |
| adamant_staggers_reduce_damage_taken_buff | damage_taken_multiplier | ×0.97/stack | 8s, max 5 |
| adamant_hitting_multiple_gives_tdr | toughness_damage_taken_multiplier | 0.80 | 5s on 3 targets |
| adamant_movement_speed_on_block | movement_speed | +0.15 | 3s on ranged block |
| adamant_perfect_block_damage_boost | block_cost_multiplier | 0.85 | passive |
| adamant_suppress_immunity | keyword: suppression_immune | | passive |
| adamant_rebreather | corruption_taken ×0.80 | toxic_gas_taken ×0.25 | passive |
| adamant_dodge_improvement | +1 dodge, linger +0.25 | | passive |
| adamant_no_movement_penalty | movespeed_reduction ×0.50 | | while ranged |
| adamant_weapon_handling_buff | spread −0.075, recoil −0.075/stack | max 10 | ADS only |

### Equipment / Misc

| Template | Stat | Value |
|----------|------|-------|
| adamant_mag_strips | wield_speed | +0.25 |
| adamant_ammo_belt | ammo_reserve_capacity | +0.25 |
| adamant_clip_size | clip_size_modifier | +0.15 |
| adamant_grenade_radius_increase | explosion_radius_frag | +0.50 |
| adamant_grenade_damage_increase | frag_damage | +0.50 |
| adamant_disable_companion_buff | damage +0.10, TDR −0.15, attack_speed +0.10 | +1 grenade |
| adamant_sprinting_sliding | sprint_movement_speed | +0.05 | 5s on slide |

### Companion (Cyber-Mastiff)

| Template | Stat | Value |
|----------|------|-------|
| adamant_companion_focus_melee | companion_damage_vs_melee | +0.25 |
| adamant_companion_focus_ranged | companion_damage_vs_ranged | +0.50 |
| adamant_companion_focus_elite | companion_damage_vs_elites/specials | +0.25 each |
| adamant_dog_damage_after_ability | companion_damage | +0.50 | 12s on ability |
| adamant_pinning_dog_permanent_stacks_buff | companion_damage | +0.025/stack | max 30, permanent |
| adamant_pinning_dog_elite_damage_buff | damage_vs_elites/specials | +0.15 | 8s on pounce-kill |

### Toughness Restoration

| Template | Value | Notes |
|----------|-------|-------|
| adamant_elite_special_kills_replenish | 10% instant + 2.5%/s for 4s | on elite kill |
| adamant_close_kills_restore | 5% | on close kill |
| adamant_staggers_replenish | 10% | on melee stagger |
| adamant_shield_plates_buff | 15% over 3s | on block |
| adamant_shield_plates | 10% instant | on perfect block, 1s CD |
| adamant_stamina_spent_replenish | 10% per stamina spent over 3s | |
| adamant_toughness_regen_near_companion | 5%/s | within 8m of dog |
| adamant_restore_toughness_to_allies_on_ability | 20% | to coherency allies |

### Coherency Auras

| Template | Stat | Value |
|----------|------|-------|
| adamant_reload_speed_aura | reload_speed | +0.125 |
| adamant_companion_aura | toughness_damage_taken | −0.075 |
| adamant_damage_vs_staggered_aura | damage_vs_staggered | +0.10 |

### Enemy Debuffs

| Template | Stat | Value |
|----------|------|-------|
| adamant_staggering_enemies_take_more_damage | melee_damage_taken | +0.15 | 5s |
| adamant_staggered_enemies_deal_less_damage | damage | −0.20 | 5s |
| adamant_melee_weakspot_hits_count_as_stagger | keyword: count_as_staggered | 4s |

---

## BROKER (Hive Scum)

### Focus (Gunslinger Stance)

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| broker_focus_stance | sprint_movement_speed | +0.20 | 10s (max 20s) |
| | sprinting_cost_multiplier | 0 (free sprint) | |
| | (sub_2) ranged_rending_multiplier | +0.15 | |
| | keywords: suppression_immune, count_as_dodge_vs_ranged | | |
| broker_focus_sub_2_damage | ranged_damage | +0.03/stack | 3s, max 5 (=+15%) |

Focus CDR: 0.5s/normal kill, 1s/elite, cap 5s; +1s duration/kill (diminishing /5), max 20s.
Ammo: 10% clip refill on kill.

### Punk Rage (Rampage)

| Template | Stat | Value | Duration |
|----------|------|-------|----------|
| broker_punk_rage_stance | melee_power_level_modifier | +0.50 | 10s (max 20-30s) |
| | melee_attack_speed | +0.20 | |
| | damage_taken_multiplier | 0.75 (−25% DR) | |
| | (sub_1) melee_heavy_rending | +0.25 | |
| | (sub cleave) hit_mass_attack/impact | +0.50 | |
| | keywords: stun_immune, slowdown_immune | | |
| broker_punk_rage_ramping_melee_power | melee_power_level | +0.025/stack | max 10 (=+25%) |
| broker_punk_rage_exhaustion | damage_taken ×1.25, stamina_regen ×0.25 | 7s | currently disabled |
| broker_punk_rage_improved_shout_debuff (enemy) | melee_attack_speed | −0.50 | 5s, 4.5m radius |

### Stimm Field

| Template | Effect | Notes |
|----------|--------|-------|
| broker_stimm_field_corruption_buff | blocks all corruption | heals 0.5 corruption/0.25s |
| Parameters: 20s life, 3m radius, 60s CD | | DLC content — heal_amount unresolved |

### Keystones

**Vulture's Mark** (`vultures_mark`): max 3 stacks, 8s (12s improved)
| Stat | Per Stack |
|------|-----------|
| ranged_damage | +0.05 |
| ranged_critical_strike_chance | +0.05 |
| movement_speed | +0.05 |
| At max: 15% toughness to coherency on elite/special kill | |
| (sub) crit_ranged_dodge_buff | dodge keywords 1s | on ranged crit |

**Chemical Dependency** (`broker_keystone_chemical_dependency_stack`): max 3 (4 with sub_3), 90s (60s with sub_3)
| Stat | Per Stack |
|------|-----------|
| combat_ability_cooldown_regen_modifier | +0.10 |
| (sub_1) critical_strike_chance | +0.05 |
| (sub_2) toughness_damage_taken_multiplier | ×0.95 |
| On stimm use: 50% toughness instant (sub_2) | |

**Adrenaline Junkie** (`broker_keystone_adrenaline_junkie`): 30 hit stacks → Frenzy
| Frenzy buff | Value | Duration |
|-------------|-------|----------|
| melee_damage | +0.25 | 10s (20s improved) |
| melee_attack_speed | +0.10 | |
| (sub_5) toughness | +5%/s while active | |
| Stack generation: +1/hit, +1/crit, sub_1: +2 weakspot, sub_2: +4/kill (+10 elite) | |

### Passives

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| broker_passive_close_ranged_damage | damage_near +0.25, damage_far +0.10 | | conditional: ranged wielded |
| broker_passive_punk_grit | ranged_damage +0.10 | TDR ×0.90 | passive |
| broker_passive_extended_mag | clip_size_modifier | +0.15 | passive |
| broker_passive_finesse_damage | finesse_modifier_bonus | +0.15 | passive |
| broker_passive_increased_weakspot_damage | weakspot_damage | +0.25 | passive |
| broker_passive_close_ranged_finesse_damage | finesse_close_range | +0.25 | passive |
| broker_passive_close_range_rending | close_range_rending | +0.15 | passive |
| broker_passive_reduce_swap_time | wield_speed +0.40 | spread −0.30, recoil −0.10 (hipfire) | passive |
| broker_passive_improved_dodges | dodge_speed ×1.25, dodge_linger +0.15 | | passive |
| broker_passive_extra_consecutive_dodges | extra_dodges | +1 | passive |
| broker_passive_increased_ranged_dodges | extra_dodges | +1 | conditional: ranged wielded |
| broker_passive_ninja_grants_crit_chance | critical_strike_chance | +0.20 | 3s; proc on dodge/perfect block |
| broker_passive_parries_grant_crit_chance | critical_strike_chance | +0.20 | 2s; proc on perfect block |
| broker_passive_backstabs_grant_crit_chance | critical_strike_chance | +0.20 | 2s; proc on backstab |
| broker_passive_strength_vs_aggroed | power_level vs aggroed elites/monsters | +0.10 | passive |
| broker_passive_damage_vs_elites_monsters | damage_vs_elites +0.15, damage_vs_monsters +0.15 | | passive |
| broker_passive_damage_vs_heavy_staggered | damage_vs_staggered +0.10, vs_medium +0.15 | | passive |
| broker_passive_crit_to_damage | crit_chance_to_damage_convert | 1.0 | converts all crit→flat damage |
| broker_passive_first_target_damage | first_target_melee_damage | +0.15 | passive |
| broker_passive_repeated_melee_hits | damage | +0.25 | conditional: after 2 hits on same target |
| broker_ramping_backstabs_stat_buff | melee_power_level | +0.10/stack | max 5 |
| broker_passive_reload_speed_on_close_kill | reload_speed | +0.30 | 8s proc |
| broker_passive_close_range_damage_on_dodge | damage_near | +0.15 | 3s proc |
| broker_passive_close_range_damage_on_slide | damage_near | +0.15 | while sliding |
| broker_passive_melee_cleave_on_kill_buff | melee_cleave | +0.10/stack | 5s, max 5 |
| broker_passive_cleave_on_cleave_buff | hit_mass +0.50, impact +0.50 | | proc after 3+ targets hit |
| broker_passive_damage_on_reload_buff | ranged_damage | 0.02 + 0.02/ammo_stage | 7s, scales with ammo spent |

### Defense / Toughness

| Template | Stat | Value | Notes |
|----------|------|-------|-------|
| broker_passive_restore_toughness_on_close_ranged_kill | toughness | 8% normal, 15% elite | on close ranged kill |
| broker_passive_restore_toughness_on_weakspot_kill | toughness | 4%/8% (ws/crit)/12% (both) | melee only |
| broker_passive_stun_immunity_on_toughness_broken | stun_immune | 6s; +50% toughness | 10s CD |
| broker_passive_push_on_damage_taken_stack | push_impact +0.50, cost ×0 | max 3 | on melee hit taken |
| broker_passive_reduced_toughness_damage_during_reload | TDR | −0.25 | while reloading + 4s |
| broker_passive_sprinting_reduces_threat_buff | threat_weight | ×0.875/stack | 3s, max 4 |
| broker_passive_improved_sprint_dodge | sprint_dodge_angle | ~15° | + overtime keyword |
| broker_passive_improved_dodges_at_full_stamina | dodge_cooldown_reset | −0.40 | conditional: ≥75% stamina |
| broker_passive_stamina_grants_atk_speed | melee_attack_speed | +0.02/pip | max 15 stacks |
| broker_passive_big_sidesteps_during_reload | dodge_distance +2.0, speed +0.40, CD −1.0 | | while reloading |
| broker_passive_dr_damage_tradeoff_on_stamina | DR lerp: up to −20% at full stam | melee_damage up to +20% at 0 stam | |
| broker_passive_replenish_toughness_on_ranged_hit | toughness regen | 10%/s for 3s | on ranged toughness hit |

### Toxin

| Template | Effect | Value |
|----------|--------|-------|
| toxin_damage_debuff (enemy) | damage dealt | −0.15 (−0.30 vs monsters) |
| broker_passive_damage_after_toxined_enemies | damage per toxined enemy | +0.05/enemy, max +0.15 |
| broker_passive_toughness_on_toxined_kill | toughness | 15% on melee kill of toxined |
| broker_increased_toxin_damage | toxin damage taken (enemy) | +0.10 |
| broker_passive_stun_on_max_toxin_stacks | electrocuted keyword | 3s at max stacks |

### Stimm Lab (per-tier stacking, active during syringe buff)

**Celerity track:**
| Tier | Stat | Per-Tier Value |
|------|------|----------------|
| 1–4 | attack_speed | +0.04 |
| 1 | wield_speed | +0.25 |
| 2–4 | stamina_cost_multiplier | 0.85→0.80 |
| 5a | stun_immune, slowdown_immune | |
| 5b | reload_speed +0.30, recoil −0.50 | |
| 5c | movement_speed +0.10, dodge_distance +0.10, dodge_speed ×1.1, dodge_CD −0.10 | |

**Combat track:**
| Tier | Stat | Per-Tier Value |
|------|------|----------------|
| 1–3 | power_level_modifier | +0.04 |
| 4a/5a | finesse_modifier_bonus | +0.10/+0.25 |
| 4b/5b | rending_multiplier | +0.05/+0.10 |
| 4c/5c | critical_strike_chance | +0.05/+0.10 |

**Durability track:**
| Tier | Stat | Per-Tier Value |
|------|------|----------------|
| 1–4 | toughness_replenish_modifier | +0.05 |
| 1–4 | damage_taken_multiplier | ×0.96 (−4%) |
| 1–4 | toughness burst on stimm | +6.25% per tier |
| 5a | toughness_replenish_modifier | +0.30 |
| 5b | toughness over time | +5%/s for stimm duration |

**Concentration track:**
| Tier | Stat | Per-Tier Value |
|------|------|----------------|
| 1–4 | combat_ability_cooldown_regen | +0.0625 |
| 5a | combat_ability_cooldown_regen | +0.25 |
| 5b | CDR on melee kill | +75% for 1s |
| 5c | CDR on ranged kill | +75% for 1s |

### Coherency Auras

| Template | Stat | Value |
|----------|------|-------|
| broker_coherency_melee_damage | melee_damage | +0.10 |
| broker_coherency_critical_chance | critical_strike_chance | +0.05 |
| broker_aura_gunslinger | ammo share to allies | 5% (10% improved) |

### Misc Procs

| Template | Effect | Notes |
|----------|--------|-------|
| broker_passive_hollowtip_bullets | 15% force-stagger on ranged hit | procedural |
| broker_passive_melee_crit_instakill | instakill human-sized on crit if HP < threshold | not captains |
| broker_passive_ammo_on_backstab | 1% total ammo | on backstab kill or ranged crit, 5s CD |
| broker_passive_low_ammo_regen | refill to 20% reserve | on elite kill when below 20% |
| broker_passive_stimm_cd_on_kill | stimm CD: 1% kill, 2% toxined kill | |
| broker_passive_stimm_increased_duration | syringe_duration | +5s |

---

## Shared / Cross-Class

### Rending Debuffs (applied to enemies by various talents)

| Template | Effect | Notes |
|----------|--------|-------|
| rending_debuff | enemy armor reduction | per-hit stacking, multiple sources |
| rending_debuff_medium | stronger armor reduction | on melee crit (veteran) |

### Player Base Buff

| Template | Stat | Notes |
|----------|------|-------|
| player_buff_templates.lua | Base toughness regen, coherency bonuses, stamina regen | 1446 lines — class-agnostic |
| common_buff_templates.lua | Status effects (bleed, burn, stagger, soulblaze) | 232 lines |

---

## Known Gaps in Decompiled Source

| Class | Missing Value | Reference |
|-------|--------------|-----------|
| Psyker | nearby_soublaze_defense.critical_min/max | lerp bounds for soulblaze crit |
| Psyker | soulblaze_range local var | referenced but undefined |
| Ogryn | ogryn_drain_stamina_for_handling.critical_strike_chance | nil at runtime (bug/placeholder) |
| Broker | broker_stimm_med_vitality.heal_amount | DLC content, not in decompile |
| Zealot | zealot_melee_crits_reduce_damage_dealt — .damage and .max_stacks nil | likely data bug |
