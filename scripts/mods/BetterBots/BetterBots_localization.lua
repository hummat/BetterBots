return {
	mod_name = {
		en = "Better Bots",
	},
	mod_description = {
		en = "Smarter bots with unlocked abilities for Solo Play.",
	},
	-- Groups
	abilities_group = {
		en = "Abilities",
	},
	bot_behavior_group = {
		en = "Bot Behavior",
	},
	bot_profiles_group = {
		en = "Bot Profiles",
	},
	diagnostics_group = {
		en = "Diagnostics",
	},
	-- Ability categories
	enable_stances = {
		en = "Stance abilities",
	},
	enable_stances_description = {
		en = "Self-buff abilities: Veteran Focus, Psyker Overcharge, Ogryn Gunlugger, Arbites/Hive Scum Stances",
	},
	enable_charges = {
		en = "Charge & dash abilities",
	},
	enable_charges_description = {
		en = "Gap-closing abilities (Zealot Dash, Ogryn Charge, Arbites Charge)",
	},
	enable_shouts = {
		en = "Shout abilities",
	},
	enable_shouts_description = {
		en = "Crowd control and team buff shouts: Psyker Shriek, Ogryn Taunt, Veteran Voice of Command, Arbites Shout",
	},
	enable_stealth = {
		en = "Stealth abilities",
	},
	enable_stealth_description = {
		en = "Bots can go invisible to reposition or rescue downed allies: Veteran Stealth, Zealot Invisibility",
	},
	enable_deployables = {
		en = "Deployable abilities",
	},
	enable_deployables_description = {
		en = "Placed items (Zealot Relic, Psyker Force Field, Arbites Drone)",
	},
	enable_grenades = {
		en = "Grenades & blitz",
	},
	enable_grenades_description = {
		en = "All grenade types (frag, krak, smoke, shock, fire) and Psyker blitz (Assail, Smite, Chain Lightning)",
	},
	-- Behavior preset
	behavior_profile = {
		en = "Behavior preset",
	},
	behavior_profile_description = {
		en = "How aggressively bots use abilities",
	},
	behavior_profile_testing = {
		en = "Testing - very lenient for development/validation",
	},
	behavior_profile_aggressive = {
		en = "Aggressive - liberal ability use, suited for lower difficulties",
	},
	behavior_profile_balanced = {
		en = "Balanced - tuned for challenging content (default)",
	},
	behavior_profile_conservative = {
		en = "Conservative - emergency-only, suited for Auric/Maelstrom",
	},
	-- Feature toggles
	enable_sprint = {
		en = "Bot sprinting",
	},
	enable_sprint_description = {
		en = "Bots sprint to catch up, during traversal, and for ally rescue",
	},
	enable_pinging = {
		en = "Elite & special pinging",
	},
	enable_pinging_description = {
		en = "Bots ping elites and specials they detect",
	},
	enable_special_penalty = {
		en = "Distant special targeting",
	},
	enable_special_penalty_description = {
		en = "Bots prefer ranged attacks against distant specials instead of charging into melee",
	},
	enable_poxburster = {
		en = "Poxburster safe targeting",
	},
	enable_poxburster_description = {
		en = "Bots hold fire on poxbursters within detonation range of bots or humans. Disabling removes this safety check.",
	},
	enable_melee_improvements = {
		en = "Melee improvements",
	},
	enable_melee_improvements_description = {
		en = "Bots use heavy attacks vs armor, lights vs hordes. Disabling reverts to vanilla light-only.",
	},
	enable_ranged_improvements = {
		en = "Ranged improvements",
	},
	enable_ranged_improvements_description = {
		en = "Bots aim down sights, use charged staff fire, and vent warp heat. Disabling reverts to vanilla.",
	},
	enable_engagement_leash = {
		en = "Combat engagement leash",
	},
	enable_engagement_leash_description = {
		en = "Bots stay in combat longer instead of breaking off to follow. Uses coherency-based ranges.",
	},
	bot_ranged_ammo_threshold = {
		en = "Bot ranged ammo threshold",
	},
	bot_ranged_ammo_threshold_description = {
		en = "Bots stop opportunistic ranged fire below this reserve and start looking for ammo at or below it. Priority-target shots are unchanged.",
	},
	bot_human_ammo_reserve_threshold = {
		en = "Human ammo reserve threshold",
	},
	bot_human_ammo_reserve_threshold_description = {
		en = "Bots only claim ammo when every eligible human ammo user is above this reserve.",
	},
	-- Healing deferral
	healing_deferral_mode = {
		en = "Healing deferral mode",
	},
	healing_deferral_mode_description = {
		en = "Bots defer healing pickups to human players. Off = bots heal freely.",
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
		en = "Deferral threshold",
	},
	healing_deferral_human_threshold_description = {
		en = "Bots step aside and let humans heal first when any human player's health is below this threshold.",
	},
	healing_deferral_emergency_threshold = {
		en = "Emergency override",
	},
	healing_deferral_emergency_threshold_description = {
		en = "Bots ignore deferral and heal themselves when their own health drops below this threshold.",
	},
	healing_deferral_threshold_10 = {
		en = "10%% health",
	},
	healing_deferral_threshold_25 = {
		en = "25%% health",
	},
	healing_deferral_threshold_40 = {
		en = "40%% health",
	},
	healing_deferral_threshold_50 = {
		en = "50%% health",
	},
	healing_deferral_threshold_75 = {
		en = "75%% health",
	},
	healing_deferral_threshold_90 = {
		en = "90%% health",
	},
	healing_deferral_threshold_100 = {
		en = "100%% health",
	},
	healing_deferral_emergency_never = {
		en = "Never override (bots may die)",
	},
	-- Bot profiles
	bot_slot_1_profile = {
		en = "Bot slot 1",
	},
	bot_slot_1_profile_description = {
		en = "Class for the first bot. Tertium4Or5 characters take priority when installed. None = vanilla veteran.",
	},
	bot_slot_2_profile = {
		en = "Bot slot 2",
	},
	bot_slot_2_profile_description = {
		en = "Class for the second bot. Tertium4Or5 characters take priority when installed. None = vanilla veteran.",
	},
	bot_slot_3_profile = {
		en = "Bot slot 3",
	},
	bot_slot_3_profile_description = {
		en = "Class for the third bot. Tertium4Or5 characters take priority when installed. None = vanilla veteran.",
	},
	bot_slot_4_profile = {
		en = "Bot slot 4 (Tertium)",
	},
	bot_slot_4_profile_description = {
		en = "Only used when Tertium4Or5/6 adds a 4th bot. Tertium characters take priority. None = vanilla veteran.",
	},
	bot_slot_5_profile = {
		en = "Bot slot 5 (Tertium)",
	},
	bot_slot_5_profile_description = {
		en = "Only used when Tertium 6 adds a 5th bot. Tertium characters take priority. None = vanilla veteran.",
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
		en = "Bot Weapon Quality",
	},
	bot_weapon_quality_description = {
		en = "Controls bot weapon power level. Auto scales with difficulty. Affects damage, stagger, and other stats.",
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
		en = "Max (fully empowered god-roll, expertise 500)",
	},
	-- Diagnostics
	enable_debug_logs = {
		en = "Debug log level",
	},
	enable_debug_logs_description = {
		en = "Controls how much BetterBots logs to the console. Higher levels produce more output.",
	},
	debug_log_level_off = {
		en = "Off",
	},
	debug_log_level_info = {
		en = "Info - patches and confirmations only",
	},
	debug_log_level_debug = {
		en = "Debug - ability decisions and events",
	},
	debug_log_level_trace = {
		en = "Trace - everything including per-frame diagnostics",
	},
	enable_event_log = {
		en = "Event log",
	},
	enable_event_log_description = {
		en = "Write structured ability events (JSONL) to binaries/dump/. Analyze with bb-log commands.",
	},
	enable_perf_timing = {
		en = "Performance timing",
	},
	enable_perf_timing_description = {
		en = "Track per-module execution times. Use /bb_perf in chat to view and reset.",
	},
}
