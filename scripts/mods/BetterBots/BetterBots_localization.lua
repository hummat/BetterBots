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
		en = title("Bot Behavior - Feature Toggles"),
	},
	bot_tuning_group = {
		en = title("Bot Behavior - Tuning"),
	},
	healing_deferral_group = {
		en = title("Healing Deferral"),
	},
	bot_profiles_group = {
		en = title("Bot Profiles"),
	},
	bot_slots_core_group = {
		en = title("Bot Slots 1-3"),
	},
	bot_slots_core_group_description = {
		en = subtitle("Core bot slots used by Solo Play."),
	},
	bot_slots_tertium_group = {
		en = title("Bot Slots 4-5 (Tertium)"),
	},
	bot_slots_tertium_group_description = {
		en = subtitle("Only used when Tertium4Or5/6 adds extra bots. Leave as None without a Tertium mod."),
	},
	diagnostics_group = {
		en = title("Diagnostics"),
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
	enable_pinging = {
		en = "Elite & special pinging",
	},
	enable_pinging_description = {
		en = "Bots ping elites and specials they detect. Also controls Arbites companion (dog) targeting.",
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
	enable_smart_targeting = {
		en = "Smart blitz targeting",
	},
	enable_smart_targeting_description = {
		en = "Seed bot blitz targeting from perception. Disabling restores vanilla blitz targeting.",
	},
	enable_daemonhost_avoidance = {
		en = "Daemonhost avoidance",
	},
	enable_daemonhost_avoidance_description = {
		en = "Suppress combat and sprinting near dormant daemonhosts. Disabling lets bots engage freely (advanced).",
	},
	sprint_follow_distance = {
		en = "Sprint catch-up distance",
	},
	sprint_follow_distance_description = {
		en = "Bots sprint to catch up when further than this distance from the group leader. "
			.. "Also enables traversal and rescue sprinting. Set to 0 to disable all sprinting.",
	},
	special_chase_penalty_range = {
		en = "Special chase penalty range",
	},
	special_chase_penalty_range_description = {
		en = "Bots prefer ranged attacks against specials beyond this distance instead of charging into melee. "
			.. "Set to 0 to disable the penalty.",
	},
	player_tag_bonus = {
		en = "Player tag response",
	},
	player_tag_bonus_description = {
		en = "How aggressively bots prioritize targets pinged by the human player. "
			.. "Higher values make bots respond faster. Set to 0 to ignore player pings.",
	},
	melee_horde_light_bias = {
		en = "Melee horde light bias",
	},
	melee_horde_light_bias_description = {
		en = "Bias bots toward light attacks into unarmored hordes for better cleave. "
			.. "Higher values prefer lights more. Set to 0 for vanilla attack selection.",
	},
	bot_ranged_ammo_threshold = {
		en = "Bot ranged ammo threshold",
	},
	bot_ranged_ammo_threshold_description = {
		en = "Bots stop opportunistic ranged fire below this reserve. "
			.. "When a human is low on ammo, bots only pick up ammo at or below this threshold. "
			.. "Priority-target shots are unchanged.",
	},
	bot_human_ammo_reserve_threshold = {
		en = "Human ammo reserve threshold",
	},
	bot_human_ammo_reserve_threshold_description = {
		en = "Bots freely pick up ammo when every eligible human ammo user is above this reserve. "
			.. "When a human is below this reserve, bots defer ammo to humans unless desperate.",
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
		en = "Bots ignore deferral and heal themselves when their own health drops below this threshold. "
			.. "Set to 0 to never override (bots may die).",
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
		en = "Max (fully upgraded)",
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
