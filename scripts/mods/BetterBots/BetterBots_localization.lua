-- Settings UI color palette (markers_aio pattern). Tune these two RGB strings
-- to restyle every group header and subtitle in the BetterBots mod options.
local colours = {
	title = "200,140,20", -- Imperial gold: group headers
	subtitle = "226,199,126", -- citrine: sub-group descriptions
}

local function title(text)
	return "{#color(" .. colours.title .. ")}" .. text .. "{#reset()}"
end

local function subtitle(text)
	return "{#color(" .. colours.subtitle .. ")}" .. text .. "{#reset()}"
end

return {
	mod_name = {
		-- U+E029: Darktide UI font PUA glyph (Adeptus Mechanicus cog,
		-- per settings/live_event/mechanicus.lua `icon`). Defined in
		-- the game UI font, not Unicode — guaranteed to render.
		-- Chosen for the tech-priest / machine-spirit theme: BetterBots
		-- is about making the Omnissiah's servitors (bots) function
		-- as intended.
		-- Alternates: E051 (Cyber-Mastiff), E048 (mastery_points),
		-- E004 (party_status), E003 (powersword).
		en = "{#color(255,180,30)} Better Bots{#reset()}",
	},
	mod_description = {
		en = "Smarter bots with unlocked abilities for Solo Play.",
	},
	-- Groups
	abilities_group = {
		en = title("Abilities"),
	},
	bot_behavior_group = {
		en = title("Bot Behavior"),
	},
	bot_feature_toggles_group = {
		en = title("Bot Tweaks"),
	},
	bot_tuning_group = {
		en = title("Bot Tuning"),
	},
	healing_deferral_group = {
		en = title("Healing Priority"),
	},
	bot_profiles_group = {
		en = title("Bot Team Setup"),
	},
	bot_slots_core_group = {
		en = title("Solo Play Slots"),
	},
	bot_slots_core_group_description = {
		en = subtitle("The three normal bot slots used in Solo Play."),
	},
	bot_slots_tertium_group = {
		en = title("Extra Tertium Slots"),
	},
	bot_slots_tertium_group_description = {
		en = subtitle("Only used by Tertium extra-bot mods. Leave on None if you do not use one."),
	},
	diagnostics_group = {
		en = title("Diagnostics"),
	},
	-- Ability categories
	enable_stances = {
		en = "Stance abilities",
	},
	enable_stances_description = {
		en = "Bots use self-buff combat abilities such as stances, damage boosts, and focus skills.",
	},
	enable_charges = {
		en = "Charge & dash abilities",
	},
	enable_charges_description = {
		en = "Bots use charge and dash abilities to rush enemies or reach a rescue faster.",
	},
	enable_shouts = {
		en = "Shout abilities",
	},
	enable_shouts_description = {
		en = "Bots use shout-style abilities that stagger enemies or buff the team.",
	},
	enable_stealth = {
		en = "Stealth abilities",
	},
	enable_stealth_description = {
		en = "Bots use invisibility abilities to reposition or rescue allies.",
	},
	enable_deployables = {
		en = "Deployable abilities",
	},
	enable_deployables_description = {
		en = "Bots place support tools such as relics, shields, and drones.",
	},
	enable_grenades = {
		en = "Grenades & blitz",
	},
	enable_grenades_description = {
		en = "Bots throw grenades and use blitz attacks such as Assail, Smite, and Chain Lightning.",
	},
	-- Behavior preset
	behavior_profile = {
		en = "Ability use style",
	},
	behavior_profile_description = {
		en = "Changes how freely bots spend combat abilities.",
	},
	behavior_profile_testing = {
		en = "Testing - use abilities as soon as possible",
	},
	behavior_profile_aggressive = {
		en = "Aggressive - use abilities often",
	},
	behavior_profile_balanced = {
		en = "Balanced - default",
	},
	behavior_profile_conservative = {
		en = "Conservative - save abilities for danger",
	},
	-- Feature toggles
	enable_pinging = {
		en = "Enemy pinging",
	},
	enable_pinging_description = {
		en = "Bots ping dangerous enemies they spot. Also helps Arbites bots send the dog after tagged targets.",
	},
	enable_poxburster = {
		en = "Poxburster safety",
	},
	enable_poxburster_description = {
		en = "Bots stop shooting poxbursters that are too close to the team. Turn this off to remove that safety check.",
	},
	enable_melee_improvements = {
		en = "Melee improvements",
	},
	enable_melee_improvements_description = {
		en = "Bots use heavier swings on armor and quicker swings into crowds. Turn this off for vanilla melee behavior.",
	},
	enable_ranged_improvements = {
		en = "Ranged improvements",
	},
	enable_ranged_improvements_description = {
		en = "Bots aim before firing, use charged shots, and vent heat or peril when needed. "
			.. "Turn this off for vanilla ranged behavior.",
	},
	enable_team_cooldown = {
		en = "Spread out team abilities",
	},
	enable_team_cooldown_description = {
		en = "Stops several bots from using the same kind of ability at the same time.",
	},
	enable_engagement_leash = {
		en = "Stick to nearby fights",
	},
	enable_engagement_leash_description = {
		en = "Bots are less likely to drop a close fight just to run back to the group.",
	},
	enable_smart_targeting = {
		en = "Better blitz targeting",
	},
	enable_smart_targeting_description = {
		en = "Bots aim blitz attacks at the enemy they are already tracking. Turn this off for vanilla blitz targeting.",
	},
	enable_daemonhost_avoidance = {
		en = "Avoid sleeping daemonhosts",
	},
	enable_daemonhost_avoidance_description = {
		en = "Bots stop fighting and sprinting near a sleeping daemonhost. Turn this off for vanilla behavior.",
	},
	enable_target_type_hysteresis = {
		en = "Reduce weapon swap thrashing",
	},
	enable_target_type_hysteresis_description = {
		en = "Bots are less likely to keep flipping between melee and ranged when both choices are close.",
	},
	human_timing_profile = {
		en = "Timing profile",
	},
	human_timing_profile_description = {
		en = "Controls how much hesitation and reaction delay bots add before using abilities.",
	},
	human_timing_profile_off = {
		en = "Off",
	},
	human_timing_profile_fast = {
		en = "Fast",
	},
	human_timing_profile_medium = {
		en = "Medium",
	},
	human_timing_profile_slow = {
		en = "Slow",
	},
	human_timing_profile_custom = {
		en = "Custom",
	},
	human_timing_reaction_min = {
		en = "Minimum reaction delay",
	},
	human_timing_reaction_min_description = {
		en = "Lowest random reaction delay roll before the bot can respond.",
	},
	human_timing_reaction_max = {
		en = "Maximum reaction delay",
	},
	human_timing_reaction_max_description = {
		en = "Highest random reaction delay roll before the bot can respond.",
	},
	human_timing_defensive_jitter_min_ms = {
		en = "Minimum defensive jitter",
	},
	human_timing_defensive_jitter_min_ms_description = {
		en = "Shortest defensive hesitation in milliseconds, used for reactive self-preservation.",
	},
	human_timing_defensive_jitter_max_ms = {
		en = "Maximum defensive jitter",
	},
	human_timing_defensive_jitter_max_ms_description = {
		en = "Longest defensive hesitation in milliseconds, used for reactive self-preservation.",
	},
	human_timing_opportunistic_jitter_min_ms = {
		en = "Minimum opportunistic jitter",
	},
	human_timing_opportunistic_jitter_min_ms_description = {
		en = "Shortest opportunistic hesitation in milliseconds, used when an ability can wait.",
	},
	human_timing_opportunistic_jitter_max_ms = {
		en = "Maximum opportunistic jitter",
	},
	human_timing_opportunistic_jitter_max_ms_description = {
		en = "Longest opportunistic hesitation in milliseconds, used when an ability can wait.",
	},
	pressure_leash_profile = {
		en = "Pressure leash profile",
	},
	pressure_leash_profile_description = {
		en = "Controls how much bots tighten their melee leash as combat pressure rises.",
	},
	pressure_leash_profile_off = {
		en = "Off",
	},
	pressure_leash_profile_light = {
		en = "Light",
	},
	pressure_leash_profile_medium = {
		en = "Medium",
	},
	pressure_leash_profile_strong = {
		en = "Strong",
	},
	pressure_leash_profile_custom = {
		en = "Custom",
	},
	pressure_leash_start_rating = {
		en = "Start tightening at challenge rating",
	},
	pressure_leash_start_rating_description = {
		en = "Challenge-pressure total where leash tightening starts.",
	},
	pressure_leash_full_rating = {
		en = "Full tightening at challenge rating",
	},
	pressure_leash_full_rating_description = {
		en = "Challenge-pressure total where leash tightening reaches full strength.",
	},
	pressure_leash_scale_percent = {
		en = "Leash strength at full pressure",
	},
	pressure_leash_scale_percent_description = {
		en = "Percentage of the base leash to keep when combat pressure is maxed out.",
	},
	pressure_leash_floor_m = {
		en = "Minimum leash floor",
	},
	pressure_leash_floor_m_description = {
		en = "Smallest melee engagement leash allowed under pressure, in meters.",
	},
	enable_bot_grimoire_pickup = {
		en = "Bot grimoire pickup",
	},
	enable_bot_grimoire_pickup_description = {
		en = "Lets bots carry grimoires. Off by default because grimoires permanently corrupt the team.",
	},
	sprint_follow_distance = {
		en = "Sprint to catch up at",
	},
	sprint_follow_distance_description = {
		en = "Bots sprint when they fall this far behind the leader. "
			.. "This also covers traversal and rescue sprints. Set to 0 to disable bot sprinting.",
	},
	special_chase_penalty_range = {
		en = "Stop chasing specials into melee at",
	},
	special_chase_penalty_range_description = {
		en = "Beyond this distance, bots prefer to shoot specials instead of running in. "
			.. "Set to 0 to always allow the chase.",
	},
	player_tag_bonus = {
		en = "Response to your pings",
	},
	player_tag_bonus_description = {
		en = "How aggressively bots prioritize targets pinged by the human player. "
			.. "Higher values make bots respond faster. Set to 0 to ignore player pings.",
	},
	melee_horde_light_bias = {
		en = "Light attacks into crowds",
	},
	melee_horde_light_bias_description = {
		en = "Higher values make bots use more quick swings against unarmored hordes. "
			.. "Set to 0 for vanilla melee choices.",
	},
	bot_ranged_ammo_threshold = {
		en = "Bot ammo reserve",
	},
	bot_ranged_ammo_threshold_description = {
		en = "Below this, bots save ammo instead of taking extra ranged shots. "
			.. "If players are low on ammo, bots only grab ammo at or below this level. "
			.. "They still shoot high-priority threats.",
	},
	bot_human_ammo_reserve_threshold = {
		en = "Save ammo for players below",
	},
	bot_human_ammo_reserve_threshold_description = {
		en = "If any player with a gun is below this, bots leave ammo for players unless they are desperate.",
	},
	bot_grenade_charges_threshold = {
		en = "Bot grenade pickup threshold",
	},
	bot_grenade_charges_threshold_description = {
		en = "Bots seek nearby grenade refills only at or below this many remaining charges. "
			.. "Set to 0 to refill only when empty.",
	},
	bot_human_grenade_reserve_threshold = {
		en = "Save grenade refills for players below",
	},
	bot_human_grenade_reserve_threshold_description = {
		en = "If any player is below this grenade reserve, bots leave grenade refills for players.",
	},
	-- Healing deferral
	healing_deferral_mode = {
		en = "Healing pickup priority",
	},
	healing_deferral_mode_description = {
		en = "Choose when bots leave healing for players. Off lets bots heal normally.",
	},
	healing_deferral_mode_off = {
		en = "Off",
	},
	healing_deferral_mode_stations_only = {
		en = "Health stations only",
	},
	healing_deferral_mode_stations_and_deployables = {
		en = "Health stations and med-crates",
	},
	healing_deferral_human_threshold = {
		en = "Give healing to players below",
	},
	healing_deferral_human_threshold_description = {
		en = "Bots let players heal first when any player's health is below this.",
	},
	healing_deferral_emergency_threshold = {
		en = "Bot self-heal emergency",
	},
	healing_deferral_emergency_threshold_description = {
		en = "Bots ignore the rule above and heal themselves below this. Set to 0 to never override.",
	},
	-- Bot profiles
	bot_slot_1_profile = {
		en = "Bot slot 1",
	},
	bot_slot_1_profile_description = {
		en = "Chooses the class for this slot. "
			.. "If a Tertium bot fills it, that takes priority. "
			.. "None keeps the vanilla Veteran.",
	},
	bot_slot_2_profile = {
		en = "Bot slot 2",
	},
	bot_slot_2_profile_description = {
		en = "Chooses the class for this slot. "
			.. "If a Tertium bot fills it, that takes priority. "
			.. "None keeps the vanilla Veteran.",
	},
	bot_slot_3_profile = {
		en = "Bot slot 3",
	},
	bot_slot_3_profile_description = {
		en = "Chooses the class for this slot. "
			.. "If a Tertium bot fills it, that takes priority. "
			.. "None keeps the vanilla Veteran.",
	},
	bot_slot_4_profile = {
		en = "Bot slot 4 (Tertium)",
	},
	bot_slot_4_profile_description = {
		en = "Only used when a Tertium mod adds a fourth bot. None keeps the vanilla Veteran.",
	},
	bot_slot_5_profile = {
		en = "Bot slot 5 (Tertium)",
	},
	bot_slot_5_profile_description = {
		en = "Only used when a Tertium mod adds a fifth bot. None keeps the vanilla Veteran.",
	},
	bot_profile_none = {
		en = "None (vanilla veteran)",
	},
	bot_profile_veteran = {
		en = "Veteran - Plasma Gun + Devil's Claw Sword",
	},
	bot_profile_zealot = {
		en = "Zealot - Purgation Flamer + Relic Blade",
	},
	bot_profile_psyker = {
		en = "Psyker - Surge Staff + Force Greatsword",
	},
	bot_profile_ogryn = {
		en = "Ogryn - Heavy Stubber + Power Maul",
	},
	bot_weapon_quality = {
		en = "Bot weapon strength",
	},
	bot_weapon_quality_description = {
		en = "Sets how strong bot weapons are. Auto scales with difficulty.",
	},
	bot_weapon_quality_auto = {
		en = "Auto (scales with difficulty)",
	},
	bot_weapon_quality_low = {
		en = "Low (Sedition/Uprising)",
	},
	bot_weapon_quality_medium = {
		en = "Medium (Malice/Heresy)",
	},
	bot_weapon_quality_high = {
		en = "High (Damnation)",
	},
	bot_weapon_quality_max = {
		en = "Max (fully upgraded)",
	},
	-- Diagnostics
	enable_debug_logs = {
		en = "Debug logging",
	},
	enable_debug_logs_description = {
		en = "Controls how much BetterBots writes to the console and log file.",
	},
	debug_log_level_off = {
		en = "Off",
	},
	debug_log_level_info = {
		en = "Info - important confirmations only",
	},
	debug_log_level_debug = {
		en = "Debug - ability choices and events",
	},
	debug_log_level_trace = {
		en = "Trace - very verbose",
	},
	enable_event_log = {
		en = "Detailed event log",
	},
	enable_event_log_description = {
		en = "Writes a detailed BetterBots event log file for troubleshooting.",
	},
	enable_perf_timing = {
		en = "Performance timings",
	},
	enable_perf_timing_description = {
		en = "Measures how much time each BetterBots system takes. Use /bb_perf to view or reset it.",
	},
}
