-- bot_profiles.lua — hardcoded default class profiles for bots (#45)
-- Replaces vanilla all-veteran profiles with class-diverse loadouts so players
-- without leveled characters can still benefit from BetterBots' ability support.
-- Weapon and talent choices are curated from selected live/community builds,
-- then resolved into engine item objects at spawn time.
--
-- Profile resolution: vanilla bot profiles are pre-baked by bot_character_profiles.lua
-- (items resolved, parse_profile called) BEFORE reaching add_bot. We must resolve our
-- items the same way, or the engine gets string IDs where it expects item objects.

local _mod
local _debug_log
local _debug_enabled

-- Spawn counter: incremented per add_bot call within a mission, maps to slot 1-5.
-- Reset on GameplayStateRun enter.
local _spawn_counter = 0

-- Timestamp of the last resolve_profile swap (os.clock). Used to time-window the
-- set_profile sentinel so it only blocks within 5 s of the swap that tagged the profile.
local _last_resolve_t = -math.huge

local SLOT_SETTING_IDS = {
	"bot_slot_1_profile",
	"bot_slot_2_profile",
	"bot_slot_3_profile",
	"bot_slot_4_profile",
	"bot_slot_5_profile",
}

local ATTACHMENT_SLOT_NAMES = {
	"slot_attachment_1",
	"slot_attachment_2",
	"slot_attachment_3",
}

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

local function _copy_item_overrides(entries)
	local copy = {}

	if type(entries) ~= "table" then
		return copy
	end

	for index, entry in ipairs(entries) do
		copy[index] = {
			id = entry.id,
			rarity = entry.rarity,
			value = entry.value ~= nil and entry.value or 1,
		}
	end

	return copy
end

local function _ensure_loadout_metadata(profile)
	profile.loadout_item_ids = profile.loadout_item_ids or {}
	profile.loadout_item_data = profile.loadout_item_data or {}

	for slot_name, item in pairs(profile.loadout or {}) do
		local item_name = item and item.name

		if item_name and not profile.loadout_item_ids[slot_name] then
			profile.loadout_item_ids[slot_name] = item_name .. slot_name
		end

		if item_name and not profile.loadout_item_data[slot_name] then
			profile.loadout_item_data[slot_name] = {
				id = item_name,
			}
		end
	end
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
--   psyker:  Venting Shriek + Warp Siphon + duelling sword + voidstrike staff
--   ogryn:   Indomitable + Heavy Hitter + latrine shovel + ripper gun
-- Experimental backlog picks once the profile UI/export surface widens past the
-- core 4 classes:
--   adamant: [Havoc 40 Meta] Hyper Carry Dog Build
--   broker:  Lihoe's Havoc 40 Scumlinger build.
-- All talent keys verified against decompiled tree layouts.
-- Stat node names verified against class-specific tree files.
-- Mapping: see docs/knowledge/talent-system.md for entity ID → engine key rules.
local DEFAULT_PROFILE_TEMPLATES = {
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
		-- Assail, duelling sword, and Voidstrike staff.
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

-- Resolved profiles cache: built on first use by resolving item strings to objects.
-- Keyed by class name. Reset on GameplayStateRun enter (item catalog may change).
local _resolved_profiles = {}

-- Per-class throttle for profile-resolution failure warnings: once a class trips
-- a given failure reason, the warning fires the first time unconditionally and
-- the detailed payload still gates on debug flag.
local _warned_resolution = {}
local function _warn_resolution(key, message)
	if _warned_resolution[key] then
		return
	end
	_warned_resolution[key] = true
	if _mod and _mod.warning then
		_mod:warning("BetterBots: " .. message)
	end
end

local function _get_slot_profile_choice(slot_index)
	if not _mod then
		return "none"
	end

	local setting_id = SLOT_SETTING_IDS[slot_index]
	if not setting_id then
		return "none"
	end

	return _mod:get(setting_id) or "none"
end

local function _deep_copy_profile(source)
	local copy = {}
	for k, v in pairs(source) do
		if type(v) == "table" then
			copy[k] = _deep_copy_profile(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function _resolve_profile_template(class_name)
	if _resolved_profiles[class_name] then
		return _resolved_profiles[class_name]
	end

	local template = DEFAULT_PROFILE_TEMPLATES[class_name]
	if not template then
		return nil
	end

	local ok_mi, MasterItems = pcall(require, "scripts/backend/master_items")
	local ok_lp, LocalProfileBackendParser = pcall(require, "scripts/utilities/local_profile_backend_parser")
	local ok_ar, Archetypes = pcall(require, "scripts/settings/archetype/archetypes")

	if not (ok_mi and MasterItems and ok_lp and LocalProfileBackendParser and ok_ar and Archetypes) then
		if _mod and _mod.warning then
			_mod:warning("BetterBots: profile resolution unavailable (missing engine module)")
		end
		return nil
	end

	local item_definitions = MasterItems.get_cached()

	if not item_definitions then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:no_items",
				0,
				"MasterItems not cached yet, cannot resolve profile for " .. class_name
			)
		end
		return nil
	end

	local profile = _deep_copy_profile(template)

	-- Resolve archetype string to the Archetypes table entry.
	-- The spawning pipeline (package_synchronizer_client) reads archetype.name,
	-- so it must be the resolved table, not the raw string.
	local archetype_table = Archetypes[template.archetype]
	if not archetype_table then
		_warn_resolution(
			"bad_archetype:" .. class_name,
			"profile resolution failed for "
				.. class_name
				.. " (unknown archetype '"
				.. tostring(template.archetype)
				.. "')"
		)
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:bad_archetype",
				0,
				"unknown archetype '" .. tostring(template.archetype) .. "' for " .. class_name
			)
		end
		return nil
	end
	profile.archetype = archetype_table

	-- Add cosmetic overrides (e.g. ogryn body meshes) to loadout for resolution
	if template.cosmetic_overrides then
		for slot_name, item_id in pairs(template.cosmetic_overrides) do
			profile.loadout[slot_name] = item_id
		end
	end

	local item_overrides = {}
	local weapon_overrides = template.weapon_overrides or {}

	for slot_name, overrides in pairs(weapon_overrides) do
		item_overrides[slot_name] = {
			traits = _copy_item_overrides(overrides.traits),
			perks = _copy_item_overrides(overrides.perks),
		}
	end

	if template.curios then
		for index, curio in ipairs(template.curios) do
			local slot_name = ATTACHMENT_SLOT_NAMES[index]

			if not slot_name then
				break
			end

			if curio.master_item_id then
				profile.loadout[slot_name] = curio.master_item_id
				item_overrides[slot_name] = {
					traits = _copy_item_overrides(curio.traits),
					perks = _copy_item_overrides(curio.perks),
				}
			else
				_warn_resolution(
					"gadget_missing:" .. class_name .. ":" .. slot_name,
					"skipping runtime curio for "
						.. slot_name
						.. " on "
						.. class_name
						.. " (missing master_item_id for "
						.. tostring(curio.name)
						.. ")"
				)
				if _debug_enabled() then
					_debug_log(
						"bot_profiles:gadget_missing:" .. class_name .. ":" .. slot_name,
						0,
						"skipping runtime curio for "
							.. slot_name
							.. " (missing master_item_id for "
							.. tostring(curio.name)
							.. ")"
					)
				end
			end
		end
	end

	-- Resolve all template strings to item objects.
	-- For weapon slots with overrides (blessings/perks), use get_item_instance with a
	-- synthetic gear table so overrides are merged onto the base item via the proxy metatable.
	-- For everything else (cosmetics, trinkets), use get_item_or_fallback (bare definition).
	--
	-- Weapon stat quality: configurable via "Bot Weapon Quality" setting.
	-- In-game, players empower weapons at the Omnissiah in steps of 10, up to power 500.
	-- Power level drives how far each stat bar fills. In-game, bars range ~60% (basic)
	-- to ~80% (perfect/max). A real perfect weapon has one dump stat (~60%) and the
	-- rest at ~80%, NOT all five at 80%. Modelling per-stat distribution was deferred —
	-- we use a uniform stat_value for all stats instead. At power 500 with 5 stats,
	-- stat_value ≈ 0.76 (~75% bar each). This is a simplification: real weapons have
	-- uneven distributions, but uniform values are good enough for bot gameplay.
	--
	-- Under the hood: base_stats[].value (0.0-1.0) lerps between each stat template's
	-- "basic" and "perfect" values. The expertise formula is:
	--   expertise = floor((sum(values)*100 - 80) / 6) * 10
	-- Reversing: stat_value_per_stat = (power/10 * 6 + 80) / num_stats / 100
	-- For a 5-stat weapon at power 500: (50*6+80)/5/100 = 380/500 = 0.76
	--
	-- "Auto" scales with difficulty to match what a player at that tier would have.
	local QUALITY_POWER_LEVELS = { low = 200, medium = 350, high = 450, max = 500 }
	local AUTO_POWER_BY_CHALLENGE = {
		[1] = 200, -- sedition
		[2] = 300, -- uprising
		[3] = 380, -- malice
		[4] = 450, -- heresy
		[5] = 500, -- damnation/havoc
	}

	local quality_setting = _mod and _mod:get("bot_weapon_quality") or "auto"
	local target_power = QUALITY_POWER_LEVELS[quality_setting]
	if not target_power then
		-- Auto: read difficulty
		local difficulty_manager = Managers and Managers.state and Managers.state.difficulty
		local challenge = difficulty_manager and difficulty_manager:get_challenge() or 3
		target_power = AUTO_POWER_BY_CHALLENGE[challenge] or 380
	end

	for slot_name, item_id in pairs(profile.loadout) do
		local overrides = item_overrides[slot_name]
		if overrides then
			local master_overrides = {
				traits = _copy_item_overrides(overrides.traits),
				perks = _copy_item_overrides(overrides.perks),
			}
			local is_weapon_slot = slot_name == "slot_primary" or slot_name == "slot_secondary"

			if is_weapon_slot then
				-- Read the master item definition to discover its stat names,
				-- then construct a base_stats array with uniform quality value.
				-- Discover stat names from the weapon template (NOT the MasterItems catalog —
				-- the catalog doesn't carry base_stats). Extract template name from the content
				-- path and look it up in WeaponTemplates.
				-- pcall-wrap the require: if Fatshark renames the weapon-templates path in a
				-- patch the mod must still fall back gracefully (warn once, skip the
				-- base_stats override) instead of throwing through the add_bot hook.
				local ok_wt, WeaponTemplates =
					pcall(require, "scripts/settings/equipment/weapon_templates/weapon_templates")
				local template_name = item_id:match("([^/]+)$") -- e.g. "combatsword_p2_m1"
				local weapon_template = ok_wt
						and type(WeaponTemplates) == "table"
						and template_name
						and WeaponTemplates[template_name]
					or nil
				if not ok_wt or type(WeaponTemplates) ~= "table" then
					_warn_resolution(
						"weapon_templates_unavailable",
						"weapon_templates engine module unavailable; bot weapons ship without base_stats override"
					)
				end
				local base_stats_override = {}
				if weapon_template and weapon_template.base_stats then
					for stat_name, _ in pairs(weapon_template.base_stats) do
						base_stats_override[#base_stats_override + 1] = { name = stat_name }
					end
				end
				local num_stats = math.max(1, #base_stats_override)
				local total_stat_points = target_power / 10 * 6 + 80
				local stat_value = math.min(1.0, total_stat_points / num_stats / 100)
				for _, stat in ipairs(base_stats_override) do
					stat.value = stat_value
				end

				-- baseItemLevel for display: use total_stat_points (matches total_stats_value)
				master_overrides.baseItemLevel = math.floor(total_stat_points + 0.5)
				master_overrides.base_stats = base_stats_override
			end

			local gear_id = "betterbots_" .. class_name .. "_" .. slot_name
			local gear = {
				masterDataInstance = {
					id = item_id,
					overrides = master_overrides,
				},
				slots = { slot_name },
			}
			local item = MasterItems.get_item_instance(gear, gear_id)
			if not item then
				_warn_resolution(
					"item_fail:" .. class_name .. ":" .. slot_name,
					"failed to resolve weapon " .. tostring(item_id) .. " for " .. slot_name .. " on " .. class_name
				)
				if _debug_enabled() then
					_debug_log(
						"bot_profiles:item_fail:" .. class_name .. ":" .. slot_name,
						0,
						"failed to resolve weapon " .. tostring(item_id) .. " for " .. slot_name
					)
				end
				return nil
			end
			profile.loadout[slot_name] = item

			if _debug_enabled() then
				if is_weapon_slot then
					local stat_names = {}
					local base_stats_override = master_overrides.base_stats or {}
					local stat_value = base_stats_override[1] and base_stats_override[1].value or 0

					for _, s in ipairs(base_stats_override) do
						stat_names[#stat_names + 1] = s.name:match("([^_]+_stat)$") or s.name
					end

					_debug_log(
						"bot_profiles:weapon:" .. class_name .. ":" .. slot_name,
						0,
						slot_name
							.. " quality="
							.. tostring(quality_setting)
							.. " power="
							.. tostring(target_power)
							.. " stat_value="
							.. string.format("%.2f", stat_value)
							.. " baseItemLevel="
							.. tostring(master_overrides.baseItemLevel)
							.. " stats="
							.. tostring(#base_stats_override)
							.. " ("
							.. table.concat(stat_names, ",")
							.. ")"
							.. " traits="
							.. tostring(#(master_overrides.traits or {}))
							.. " perks="
							.. tostring(#(master_overrides.perks or {}))
					)
				else
					_debug_log(
						"bot_profiles:gadget:" .. class_name .. ":" .. slot_name,
						0,
						slot_name
							.. " item="
							.. tostring(item_id)
							.. " traits="
							.. tostring(#(master_overrides.traits or {}))
							.. " perks="
							.. tostring(#(master_overrides.perks or {}))
					)
				end
			end
		else
			local item = MasterItems.get_item_or_fallback(item_id, slot_name, item_definitions)
			if not item then
				_warn_resolution(
					"item_fail:" .. class_name .. ":" .. slot_name,
					"failed to resolve item " .. tostring(item_id) .. " for " .. slot_name .. " on " .. class_name
				)
				if _debug_enabled() then
					_debug_log(
						"bot_profiles:item_fail:" .. class_name .. ":" .. slot_name,
						0,
						"failed to resolve item " .. tostring(item_id) .. " for " .. slot_name
					)
				end
				return nil
			end
			profile.loadout[slot_name] = item
		end
	end

	-- Run parse_profile to inject base talents and build loadout metadata.
	-- Note: parse_profile reads profile.archetype as a string for the archetype name,
	-- but we've already resolved it to a table. Save and restore.
	local saved_archetype = profile.archetype
	profile.archetype = template.archetype -- string for parse_profile
	local parse_ok, parse_err = pcall(LocalProfileBackendParser.parse_profile, profile, "betterbots_" .. class_name)
	profile.archetype = saved_archetype -- restore table for spawning pipeline
	if not parse_ok then
		if _mod and _mod.warning then
			_mod:warning("BetterBots: profile parse failed for " .. class_name .. ": " .. tostring(parse_err))
		end
		return nil
	end

	_ensure_loadout_metadata(profile)

	-- The package synchronizer client iterates visual_loadout to resolve item packages.
	-- Bot profiles don't have visual_loadout natively — vanilla bots get it set elsewhere.
	-- Set it to loadout so the package system finds our weapons.
	profile.visual_loadout = profile.visual_loadout or profile.loadout

	_resolved_profiles[class_name] = profile

	if _debug_enabled() then
		_debug_log(
			"bot_profiles:resolved:" .. class_name,
			0,
			"resolved profile for " .. class_name .. " (archetype=" .. tostring(profile.archetype) .. ")"
		)
	end

	return profile
end

-- Resolve the profile for a given bot spawn. Returns (resolved_profile, was_swapped).
-- Extracted from the hook for testability.
local function resolve_profile(profile)
	_spawn_counter = _spawn_counter + 1
	local slot_index = _spawn_counter

	if slot_index > #SLOT_SETTING_IDS then
		return profile, false
	end

	-- Real backend character profiles (Tertium-assigned player characters) always
	-- have a persistent `name` field from the character backend. Vanilla bot profiles
	-- (including Tertium "None" pass-throughs) never have `name` — they use
	-- `name_list_id` instead. Neither `character_id` nor `current_level` is reliable:
	-- vanilla bots get character_id="high_bot_N" and current_level=1 after parse_profile().
	-- This check is load-order-independent and handles both #68 scenarios:
	-- (a) real Tertium veterans preserved, (b) Tertium "None" stubs overridden.
	local has_real_character = profile.character_id and profile.name
	if has_real_character then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:yield_character_id:" .. tostring(slot_index),
				0,
				"preserving external profile for bot slot "
					.. tostring(slot_index)
					.. " (character_id="
					.. tostring(profile.character_id)
					.. ", name="
					.. tostring(profile.name)
					.. ")"
			)
		end
		return profile, false
	end

	-- If another mod (Tertium4Or5/6) already swapped the profile to a non-veteran
	-- class, yield — vanilla only spawns veterans, so a non-veteran archetype means
	-- another mod provided a real player character for this slot.
	-- Note: profile.archetype can be a resolved table (with .name field) or a string.
	local archetype = profile.archetype
	local archetype_name = type(archetype) == "table" and archetype.name or archetype
	if archetype_name and archetype_name ~= "veteran" then
		return profile, false
	end

	local choice = _get_slot_profile_choice(slot_index)
	if choice == "none" then
		return profile, false
	end

	local resolved = _resolve_profile_template(choice)
	if not resolved then
		if _debug_enabled() then
			_debug_log(
				"bot_profiles:resolve_failed:" .. tostring(slot_index),
				0,
				"bot slot " .. tostring(slot_index) .. " failed to resolve profile for " .. tostring(choice)
			)
		end
		return profile, false
	end

	-- Guard against partial-mutation: committing archetype/talents without resolved
	-- primary+secondary weapons would leave the bot flagged as e.g. a zealot but
	-- holding vanilla veteran weapons. Reject before touching `profile`.
	local resolved_loadout = resolved.loadout
	if not (resolved_loadout and resolved_loadout.slot_primary and resolved_loadout.slot_secondary) then
		_warn_resolution(
			"missing_weapon_slots:" .. tostring(choice),
			"resolved profile for " .. tostring(choice) .. " is missing slot_primary or slot_secondary"
		)
		return profile, false
	end

	-- Mutate the vanilla profile in-place rather than replacing it entirely.
	-- The vanilla profile has cosmetic slots, body data, and visual_loadout already
	-- set up correctly. We swap class identity fields (archetype, level, gender, voice,
	-- weapons, talents, gestalts) and cosmetics. Other vanilla fields (trinkets, etc.)
	-- are preserved. Weapon item objects are MasterItems cache references — no copying.
	profile.archetype = resolved.archetype
	profile.current_level = resolved.current_level or 30
	profile.gender = resolved.gender
	profile.selected_voice = resolved.selected_voice
	-- Shallow-copy: same-class bots must not share mutable table references
	profile.talents = {}
	for k, v in pairs(resolved.talents or {}) do
		profile.talents[k] = v
	end
	profile.bot_gestalts = {}
	for k, v in pairs(resolved.bot_gestalts or {}) do
		profile.bot_gestalts[k] = v
	end
	profile.loadout_item_ids = profile.loadout_item_ids or {}
	profile.loadout_item_data = profile.loadout_item_data or {}
	profile.visual_loadout = profile.visual_loadout or {}

	for slot_name, item in pairs(resolved.loadout or {}) do
		profile.loadout[slot_name] = item

		local item_name = item and item.name
		local item_id = resolved.loadout_item_ids and resolved.loadout_item_ids[slot_name] or nil
		local item_data = resolved.loadout_item_data and resolved.loadout_item_data[slot_name] or nil

		profile.loadout_item_ids[slot_name] = item_id
			or (item_name and item_name .. slot_name)
			or profile.loadout_item_ids[slot_name]

		if item_data then
			profile.loadout_item_data[slot_name] = item_data
		elseif item_name and not profile.loadout_item_data[slot_name] then
			profile.loadout_item_data[slot_name] = {
				id = item_name,
			}
		end

		profile.visual_loadout[slot_name] = item
	end

	-- Guard against 1.11+ profile overwrite (#65): the network-sync pipeline
	-- JSON-serializes and reconstructs the profile, losing weapon overrides and
	-- running validate_talent_layouts (new in 1.11). Tag the profile so that:
	-- (1) unit_templates.lua skips talent re-validation (is_local_profile)
	-- (2) our BotPlayer.set_profile hook blocks the lossy overwrite (_bb_resolved)
	profile.is_local_profile = true
	profile._bb_resolved = true
	_last_resolve_t = os.clock()

	if _debug_enabled() then
		_debug_log(
			"bot_profiles:swap:" .. tostring(slot_index),
			0,
			"bot slot " .. tostring(slot_index) .. " → " .. tostring(choice)
		)
	end

	return profile, true
end

local function register_hooks()
	_mod:hook("BotSynchronizerHost", "add_bot", function(func, self, local_player_id, profile)
		local resolved = resolve_profile(profile)
		return func(self, local_player_id, resolved)
	end)

	-- Guard against 1.11+ network-sync profile overwrite (#65).
	-- ProfileSynchronizerClient reconstructs the profile from JSON (losing weapon
	-- overrides, running validate_talent_layouts) then calls set_profile, replacing
	-- our fully-resolved profile. Time-windowed block: only intercept within 5 s of
	-- the resolve_profile swap that tagged the profile, so legitimate later profile
	-- updates (e.g. queued sync, profile_changed) pass through normally.
	_mod:hook("BotPlayer", "set_profile", function(func, self, profile)
		if self._profile and self._profile._bb_resolved and os.clock() - _last_resolve_t < 5 then
			_mod:echo("BetterBots WARNING: blocked network-sync profile overwrite (bot customization preserved)")
			if _debug_enabled() then
				_debug_log(
					"bot_profiles:set_profile_blocked",
					0,
					"blocked lossy network-sync profile overwrite",
					nil,
					"info"
				)
			end
			self._profile._bb_resolved = nil
			return
		end

		if _debug_enabled() then
			_debug_log(
				"bot_profiles:set_profile_passthrough",
				0,
				"allowed profile update (no _bb_resolved sentinel)",
				nil,
				"debug"
			)
		end
		return func(self, profile)
	end)
end

local function reset()
	_spawn_counter = 0
	_last_resolve_t = -math.huge
	-- Clear resolved cache — item catalog may have changed between missions
	for k in pairs(_resolved_profiles) do
		_resolved_profiles[k] = nil
	end
	-- Let resolution warnings fire again after a reset so a fresh mission surfaces
	-- regressions that appeared between mission loads.
	for k in pairs(_warned_resolution) do
		_warned_resolution[k] = nil
	end
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
	end,
	register_hooks = register_hooks,
	reset = reset,
	resolve_profile = resolve_profile,
	_get_profiles = function()
		return DEFAULT_PROFILE_TEMPLATES
	end,
	_get_last_resolve_t = function()
		return _last_resolve_t
	end,
	_set_last_resolve_t = function(t)
		_last_resolve_t = t
	end,
}
