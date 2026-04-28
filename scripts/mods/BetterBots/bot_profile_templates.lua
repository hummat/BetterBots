local M = {}

-- Verified via 2026-04-22 live /curio_dump in Mourningstar: the current
-- attachment-slot Blessed Bullet base item is the Reliquary gadget variant.
local BLESSED_BULLET_GADGET_ID = "content/items/gadgets/defensive_gadget_11"
local BLESSED_BULLET_DISPLAY_NAME = "Blessed Bullet (Reliquary)"

local function _trait_id(family, effect_name)
	return "content/items/traits/bespoke_" .. family .. "/" .. effect_name
end

local function _perk_id(category, perk_name)
	return "content/items/perks/" .. category .. "/" .. perk_name
end

local function _trait_override(id)
	return {
		id = id,
		rarity = 4,
		value = 1,
	}
end

local function _perk_override(id)
	return {
		id = id,
		rarity = 4,
		value = 1,
	}
end

local function _default_curio_entry()
	return {
		name = BLESSED_BULLET_DISPLAY_NAME,
		master_item_id = BLESSED_BULLET_GADGET_ID,
		traits = {
			{ id = "gadget_innate_toughness_increase", rarity = 4 },
			{ id = "gadget_cooldown_reduction", rarity = 4 },
			{ id = "gadget_damage_reduction_vs_gunners", rarity = 4 },
			{ id = "gadget_stamina_regeneration", rarity = 4 },
		},
	}
end

-- Raw profile templates — archetype as string, loadout as template ID strings.
-- These get resolved to full item objects at hook time via MasterItems.
--
-- Current shipped lineup:
--   veteran: Voice of Command + Focus Target + power sword + plasma gun
--   zealot:  Chorus + Blazing Piety + heavy eviscerator + boltgun
--   psyker:  Venting Shriek + Warp Siphon + duelling sword + voidblast staff
--   ogryn:   Indomitable + Heavy Hitter + latrine shovel + ripper gun
-- Experimental backlog picks once the profile UI/export surface widens past the
-- core 4 classes:
--   adamant: [Havoc 40 Meta] Hyper Carry Dog Build
--   broker:  Lihoe's Havoc 40 Scumlinger build.
-- All talent keys verified against decompiled tree layouts.
-- Stat node names verified against class-specific tree files.
-- Mapping: see docs/knowledge/talent-system.md for entity ID → engine key rules.
M.DEFAULT_PROFILE_TEMPLATES = {
	veteran = {
		archetype = "veteran",
		current_level = 30,
		gender = "male",
		selected_voice = "veteran_male_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/powersword_p1_m2",
			slot_secondary = "content/items/weapons/player/ranged/plasmagun_p1_m1",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		weapon_overrides = {
			slot_primary = {
				traits = {
					_trait_override(_trait_id("powersword_p1", "extended_activation_duration_on_chained_attacks")),
					_trait_override(_trait_id("powersword_p1", "increase_power_on_kill")),
				},
				perks = {
					_perk_override(_perk_id("melee_common", "wield_increase_super_armor_damage")),
					_perk_override(_perk_id("melee_common", "wield_increase_resistant_damage")),
				},
			},
			slot_secondary = {
				traits = {
					_trait_override(_trait_id("plasmagun_p1", "crit_chance_scaled_on_heat")),
					_trait_override(_trait_id("plasmagun_p1", "reduced_overheat_on_critical_strike")),
				},
				perks = {
					_perk_override(_perk_id("ranged_common", "wield_increase_armored_damage")),
					_perk_override(_perk_id("ranged_common", "wield_increase_resistant_damage")),
				},
			},
		},
		curios = {
			_default_curio_entry(),
			_default_curio_entry(),
			_default_curio_entry(),
		},
		-- Veteran now mirrors the requested Voice of Command + Focus Target plasma
		-- build instead of the earlier validation-first lasgun fallback.
		talents = {
			-- Combat ability, blitz, aura, keystone
			veteran_combat_ability_stagger_nearby_enemies = 1,
			veteran_krak_grenade = 1,
			veteran_aura_gain_ammo_on_elite_kill_improved = 1,
			veteran_improved_tag = 1,
			-- Class talents
			veteran_all_kills_replenish_toughness = 1,
			veteran_aura_elite_kills_restore_grenade = 1,
			veteran_crits_apply_rending = 1,
			veteran_increase_damage_after_sprinting = 1,
			veteran_increased_melee_crit_chance_and_melee_finesse = 1,
			veteran_extra_grenade = 1,
			veteran_dodging_grants_crit = 1,
			veteran_kill_grants_damage_to_other_slot = 1,
			veteran_attack_speed = 1,
			veteran_reduced_toughness_damage_in_coherency = 1,
			veteran_tdr_on_high_toughness = 1,
			veteran_increase_damage_vs_elites = 1,
			veteran_better_deployables = 1,
			veteran_replenish_toughness_outside_melee = 1,
			veteran_improved_grenades = 1,
			veteran_replenish_grenades = 1,
			veteran_elite_kills_reduce_cooldown = 1,
			veteran_big_game_hunter = 1,
			veteran_reduce_swap_time = 1,
			-- Keystone/ability modifiers
			veteran_combat_ability_increase_and_restore_toughness_to_coherency = 1,
			veteran_improved_tag_more_damage = 1,
			veteran_improved_tag_dead_coherency_bonus = 1,
			-- Stat nodes (names verified against veteran_tree.lua)
			base_toughness_node_buff_low_5 = 1,
			base_stamina_node_buff_low_2 = 1,
			base_toughness_node_buff_medium_1 = 1,
			base_toughness_node_buff_medium_2 = 1,
			base_melee_damage_node_buff_high_1 = 1,
		},
	},
	-- Cosmetics sourced from Darktide Seven (misc_bot_profiles.lua) and tutorial bots.
	-- Each non-veteran class gets full body/gear overrides so the bot looks correct.
	zealot = {
		archetype = "zealot",
		current_level = 30,
		gender = "female",
		selected_voice = "zealot_female_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/chainsword_2h_p1_m1",
			slot_secondary = "content/items/weapons/player/ranged/bolter_p1_m2",
		},
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/human/attachment_base/female_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_brown_02",
			slot_body_face = "content/items/characters/player/human/faces/female_asian_face_02",
			slot_body_face_hair = "content/items/characters/player/human/face_hair/female_facial_hair_base",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/human/face_tattoo/empty_face_tattoo",
			slot_body_hair = "content/items/characters/player/human/hair/hair_short_bobcut_a",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_black_02",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_asian_01",
			slot_body_tattoo = "content/items/characters/player/human/body_tattoo/empty_body_tattoo",
			slot_body_torso = "content/items/characters/player/human/attachment_base/female_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/empty_headgear",
			slot_gear_lowerbody = "content/items/characters/player/human/gear_lowerbody/d7_zealot_f_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/human/gear_upperbody/d7_zealot_f_upperbody",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		weapon_overrides = {
			slot_primary = {
				traits = {
					_trait_override(_trait_id("chainsword_2h_p1", "toughness_recovery_on_multiple_hits")),
					_trait_override(_trait_id("chainsword_2h_p1", "chained_hits_increases_crit_chance")),
				},
				perks = {
					_perk_override(_perk_id("melee_common", "wield_increase_armored_damage")),
					_perk_override(_perk_id("melee_common", "wield_increase_berserker_damage")),
				},
			},
			slot_secondary = {
				traits = {
					_trait_override(_trait_id("bolter_p1", "targets_receive_rending_debuff")),
					_trait_override(_trait_id("bolter_p1", "bleed_on_ranged")),
				},
				perks = {
					_perk_override(_perk_id("ranged_common", "wield_increase_super_armor_damage")),
					_perk_override(_perk_id("ranged_common", "wield_increase_resistant_damage")),
				},
			},
		},
		curios = {
			_default_curio_entry(),
			_default_curio_entry(),
			_default_curio_entry(),
		},
		-- Zealot now mirrors the requested Sister of Battle loadout: Chorus,
		-- heavy eviscerator, boltgun, and Blazing Piety.
		talents = {
			-- Combat ability, blitz, aura, keystone
			zealot_bolstering_prayer = 1,
			zealot_flame_grenade = 1,
			zealot_toughness_damage_reduction_coherency_improved = 1,
			zealot_fanatic_rage = 1,
			-- Class talents
			zealot_crits_apply_bleed = 1,
			zealot_multi_hits_increase_damage = 1,
			zealot_increased_damage_vs_resilient = 1,
			zealot_increase_ranged_close_damage = 1,
			zealot_crits_reduce_toughness_damage = 1,
			zealot_toughness_on_dodge = 1,
			zealot_increased_crit_and_weakspot_damage_after_dodge = 1,
			zealot_ally_damage_taken_reduced = 1,
			zealot_resist_death = 1,
			zealot_channel_grants_damage = 1,
			zealot_resist_death_healing = 1,
			zealot_reduced_damage_after_dodge = 1,
			zealot_toughness_in_melee = 1,
			zealot_attack_speed = 1,
			zealot_crits_grant_cd = 1,
			zealot_fanatic_rage_toughness_on_max = 1,
			zealot_fanatic_rage_improved = 1,
			zealot_bled_enemies_take_more_damage = 1,
			zealot_revive_speed = 1,
			zealot_elite_kills_empowers = 1,
			zealot_damage_vs_elites = 1,
			-- Stat nodes (names verified against zealot_tree.lua)
			base_melee_damage_node_buff_medium_4 = 1,
			base_toughness_node_buff_medium_2 = 1,
			base_melee_damage_node_buff_medium_1 = 1,
			base_toughness_damage_reduction_node_buff_medium_1 = 1,
		},
	},
	psyker = {
		archetype = "psyker",
		current_level = 30,
		gender = "male",
		selected_voice = "psyker_male_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/combatsword_p3_m2",
			slot_secondary = "content/items/weapons/player/ranged/forcestaff_p1_m1",
		},
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/human/attachment_base/male_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_psyker_02",
			slot_body_face = "content/items/characters/player/human/faces/male_african_face_01",
			slot_body_face_hair = "content/items/characters/player/human/face_hair/empty_face_hair",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/human/face_tattoo/face_tattoo_psyker_05",
			slot_body_hair = "content/items/characters/player/human/hair/empty_hair",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_black_01",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_african_02",
			slot_body_tattoo = "content/items/characters/player/human/body_tattoo/empty_body_tattoo",
			slot_body_torso = "content/items/characters/player/human/gear_torso/empty_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/d7_psyker_m_headgear",
			slot_gear_lowerbody = "content/items/characters/player/human/gear_lowerbody/d7_psyker_m_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/human/gear_upperbody/d7_psyker_m_upperbody",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		weapon_overrides = {
			slot_primary = {
				traits = {
					_trait_override(_trait_id("combatsword_p3", "windup_increases_power")),
					_trait_override(_trait_id("combatsword_p3", "stacking_rending_on_weakspot")),
				},
				perks = {
					_perk_override(_perk_id("melee_common", "wield_increase_super_armor_damage")),
					_perk_override(_perk_id("melee_common", "wield_increase_berserker_damage")),
				},
			},
			slot_secondary = {
				traits = {
					_trait_override(_trait_id("forcestaff_p1", "warp_charge_critical_strike_chance_bonus")),
					_trait_override(_trait_id("forcestaff_p1", "double_shot_on_crit")),
				},
				perks = {
					_perk_override(_perk_id("ranged_common", "wield_increase_super_armor_damage")),
					_perk_override(_perk_id("ranged", "increase_crit_chance")),
				},
			},
		},
		curios = {
			_default_curio_entry(),
			_default_curio_entry(),
			_default_curio_entry(),
		},
		-- Psyker now mirrors the requested Karen Mode loadout: Venting Shriek,
		-- Assail, duelling sword, and Voidblast staff.
		talents = {
			-- Combat ability, blitz, aura, keystone
			psyker_shout_vent_warp_charge = 1,
			psyker_grenade_throwing_knives = 1,
			psyker_cooldown_aura_improved = 1,
			psyker_passive_souls_from_elite_kills = 1,
			-- Class talents
			psyker_toughness_on_warp_kill = 1,
			psyker_crits_regen_toughness_movement_speed = 1,
			psyker_elite_kills_add_warpfire = 1,
			psyker_crits_empower_next_attack = 1,
			psyker_throwing_knives_piercing = 1,
			psyker_shout_reduces_warp_charge_generation = 1,
			psyker_warpfire_on_shout = 1,
			psyker_throwing_knives_cast_speed = 1,
			psyker_spread_warpfire_on_kill = 1,
			psyker_2_tier_3_name_2 = 1,
			psyker_warp_charge_reduces_toughness_damage_taken = 1,
			psyker_increased_vent_speed = 1,
			psyker_damage_based_on_warp_charge = 1,
			psyker_warpfire_generate_souls = 1,
			psyker_increased_max_souls = 1,
			psyker_killing_enemy_with_warpfire_boosts = 1,
			psyker_warp_glass_cannon = 1,
			psyker_warp_attacks_rending = 1,
			psyker_damage_vs_ogryns_and_monsters = 1,
			-- Stat nodes (names verified against psyker_tree.lua)
			base_toughness_node_buff_medium_5 = 1,
			base_toughness_damage_reduction_node_buff_medium_1 = 1,
			base_crit_chance_node_buff_low_1 = 1,
			base_toughness_node_buff_medium_4 = 1,
			base_ranged_damage_node_buff_medium_4 = 1,
			base_stamina_node_buff_low_1 = 1,
			base_toughness_damage_reduction_node_buff_low_4 = 1,
		},
	},
	ogryn = {
		archetype = "ogryn",
		current_level = 30,
		gender = "male",
		selected_voice = "ogryn_a",
		loadout = {
			slot_primary = "content/items/weapons/player/melee/ogryn_club_p1_m1",
			slot_secondary = "content/items/weapons/player/ranged/ogryn_rippergun_p1_m3",
		},
		-- Ogryn now mirrors the requested shovel/ripper build instead of the older
		-- Point-Blank Barrage Kickback validation profile.
		-- Trait IDs: internal mechanic names from decompiled weapon_traits_bespoke_*.lua.
		weapon_overrides = {
			slot_primary = {
				traits = {
					_trait_override(_trait_id("ogryn_club_p1", "staggered_targets_receive_increased_damage_debuff")),
					_trait_override(_trait_id("ogryn_club_p1", "windup_increases_power")),
				},
				perks = {
					{ id = "content/items/perks/melee_common/wield_increase_armored_damage", rarity = 4 },
					{ id = "content/items/perks/melee_common/wield_increase_resistant_damage", rarity = 4 },
				},
			},
			slot_secondary = {
				traits = {
					_trait_override(_trait_id("ogryn_rippergun_p1", "toughness_on_continuous_fire")),
					_trait_override(_trait_id("ogryn_rippergun_p1", "power_bonus_on_continuous_fire")),
				},
				perks = {
					_perk_override(_perk_id("ranged_common", "wield_increase_armored_damage")),
					_perk_override(_perk_id("ranged_common", "wield_increase_berserker_damage")),
				},
			},
		},
		cosmetic_overrides = {
			slot_body_arms = "content/items/characters/player/ogryn/attachment_base/male_arms",
			slot_body_eye_color = "content/items/characters/player/eye_colors/eye_color_green_02",
			slot_body_face = "content/items/characters/player/ogryn/attachment_base/male_face_caucasian_02",
			slot_body_face_hair = "content/items/characters/player/ogryn/face_hair/ogryn_facial_hair_b_eyebrows",
			slot_body_face_scar = "content/items/characters/player/human/face_scars/empty_face_scar",
			slot_body_face_tattoo = "content/items/characters/player/ogryn/face_tattoo/face_tattoo_ogryn_01",
			slot_body_hair = "content/items/characters/player/human/hair/empty_hair",
			slot_body_hair_color = "content/items/characters/player/hair_colors/hair_color_brown_01",
			slot_body_skin_color = "content/items/characters/player/skin_colors/skin_color_caucasian_02",
			slot_body_tattoo = "content/items/characters/player/ogryn/body_tattoo/body_tattoo_ogryn_03",
			slot_body_torso = "content/items/characters/player/ogryn/attachment_base/male_torso",
			slot_gear_head = "content/items/characters/player/human/gear_head/empty_headgear",
			slot_gear_lowerbody = "content/items/characters/player/ogryn/gear_lowerbody/d7_ogryn_lowerbody",
			slot_gear_upperbody = "content/items/characters/player/ogryn/gear_upperbody/d7_ogryn_upperbody",
		},
		bot_gestalts = {
			melee = "linesman",
			ranged = "killshot",
		},
		curios = {
			_default_curio_entry(),
			_default_curio_entry(),
			_default_curio_entry(),
		},
		-- Ogryn now mirrors the requested shovel/ripper Heavy Hitter build.
		talents = {
			-- Combat ability, blitz, aura, keystone
			ogryn_longer_charge = 1,
			ogryn_grenade_friend_rock = 1,
			ogryn_melee_damage_coherency_improved = 1,
			ogryn_passive_heavy_hitter = 1,
			-- Class talents
			ogryn_multi_heavy_toughness = 1,
			ogryn_single_heavy_toughness = 1,
			ogryn_ogryn_killer = 1,
			ogryn_melee_stagger = 1,
			ogryn_targets_recieve_damage_taken_increase_debuff = 1,
			ogryn_heavy_bleeds = 1,
			ogryn_nearby_bleeds_reduce_damage_taken = 1,
			ogryn_ally_elite_kills_grant_cooldown = 1,
			ogryn_charge_toughness = 1,
			ogryn_blocking_reduces_push_cost = 1,
			ogryn_damage_taken_by_all_increases_strength_tdr = 1,
			ogryn_replenish_rock_on_miss = 1,
			ogryn_protect_allies = 1,
			ogryn_damage_reduction_on_high_stamina = 1,
			ogryn_stacking_attack_speed = 1,
			ogryn_melee_damage_after_heavy = 1,
			ogryn_wield_speed_increase = 1,
			ogryn_weakspot_damage = 1,
			-- Keystone/ability modifiers
			ogryn_heavy_hitter_max_stacks_improves_attack_speed = 1,
			ogryn_heavy_hitter_stagger = 1,
			-- Stat nodes (names verified against ogryn_tree.lua)
			base_toughness_node_buff_medium_2 = 1,
			base_toughness_damage_reduction_node_buff_medium_1 = 1,
			base_toughness_damage_reduction_node_buff_low_5 = 1,
			base_armor_pen_node_buff_low_1 = 1,
			base_melee_damage_node_buff_medium_2 = 1,
			base_toughness_node_buff_low_2 = 1,
		},
	},
}

return M
