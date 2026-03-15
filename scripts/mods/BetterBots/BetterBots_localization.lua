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
	diagnostics_group = {
		en = "Diagnostics",
	},
	-- Ability categories
	enable_stances = {
		en = "Stance abilities",
	},
	enable_stances_description = {
		en = "Self-buff abilities (Veteran Focus, Psyker Overcharge, Ogryn Gunlugger, Arbites Stance)",
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
		en = "Area-of-effect abilities (Psyker Shriek, Ogryn Taunt, Arbites Shout)",
	},
	enable_stealth = {
		en = "Stealth abilities",
	},
	enable_stealth_description = {
		en = "Invisibility and stealth abilities (Veteran Stealth, Zealot Invisibility)",
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
		en = "All throwable and blitz abilities",
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
		en = "Prioritize shooting distant specials",
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
	-- Healing deferral
	healing_deferral_mode = {
		en = "Healing deferral mode",
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
		en = "Defer when any player is below",
	},
	healing_deferral_emergency_threshold = {
		en = "Bot emergency override below",
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
	-- Diagnostics
	enable_debug_logs = {
		en = "Debug log level",
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
		en = "Enable event log (JSONL)",
	},
	enable_perf_timing = {
		en = "Enable runtime timing (/bb_perf to read/reset)",
	},
}
