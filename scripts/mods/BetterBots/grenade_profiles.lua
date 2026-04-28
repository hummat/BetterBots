-- Data-driven grenade/blitz sequence profiles.
-- The fallback state machine consumes these profiles; this module has no queue side effects.
local M = {}

local _warp_weapon_peril_threshold

local DEFAULT_THROW_DELAY_S = 0.3

-- Maps player-ability names to throw profiles.
-- Number value: throw_delay seconds, using default aim_hold/aim_released/auto-unwield.
-- Boolean true: supported but resolved dynamically by M.resolve_template_entry().
-- Table value: explicit queued-input sequence for custom chains.
local SUPPORTED_THROW_TEMPLATES = {
	veteran_frag_grenade = DEFAULT_THROW_DELAY_S,
	veteran_smoke_grenade = DEFAULT_THROW_DELAY_S,
	veteran_krak_grenade = 1.0,
	zealot_fire_grenade = DEFAULT_THROW_DELAY_S,
	zealot_shock_grenade = 1.0,
	psyker_throwing_knives = true,
	psyker_chain_lightning = {
		aim_input = "charge_heavy",
		followup_input = "shoot_heavy_hold",
		followup_delay = 0.8,
		release_input = "shoot_heavy_hold_release",
		throw_delay = 0.9,
		auto_unwield = true,
		allow_external_wield_cleanup = true,
		confirmation_action = "action_spread_charged",
	},
	psyker_smite = {
		aim_input = "charge_power_sticky",
		followup_input = "use_power",
		followup_delay = 2.0,
		auto_unwield = true,
		allow_external_wield_cleanup = true,
		confirmation_action = "action_use_power",
	},
	ogryn_grenade_box = 1.1,
	ogryn_grenade_box_cluster = 1.1,
	ogryn_grenade_frag = 0.8,
	ogryn_grenade_friend_rock = 0.6,
	adamant_grenade = DEFAULT_THROW_DELAY_S,
	adamant_grenade_improved = DEFAULT_THROW_DELAY_S,
	broker_flash_grenade = 1.0,
	broker_flash_grenade_improved = 1.0,
	broker_tox_grenade = DEFAULT_THROW_DELAY_S,
	adamant_shock_mine = 1.0,
	zealot_throwing_knives = {
		auto_unwield = true,
	},
	adamant_whistle = {
		component = "grenade_ability_action",
		aim_input = "aim_pressed",
		release_input = "aim_released",
		throw_delay = 0.15,
	},
	broker_missile_launcher = {
		aim_input = "shoot_charge",
		auto_unwield = true,
	},
}

local ASSAIL_FAST_PROFILE = {
	aim_input = "shoot",
	auto_unwield = true,
	allow_external_wield_cleanup = true,
	require_charge_confirmation = true,
}

local ASSAIL_BURST_PROFILE = {
	aim_input = "shoot",
	followup_input = "shoot",
	followup_delay = { 0.5, 0.9 },
	auto_unwield = true,
	allow_external_wield_cleanup = true,
	continue_followup_until_depleted = true,
	require_charge_confirmation = true,
	stop_followup_peril_pct = function()
		return _warp_weapon_peril_threshold and _warp_weapon_peril_threshold() or nil
	end,
}

local ASSAIL_AIMED_PROFILE = {
	aim_input = "zoom",
	followup_input = "zoom_shoot",
	followup_delay = 0.5,
	auto_unwield = true,
	allow_external_wield_cleanup = true,
	confirmation_action = "action_rapid_zoomed",
	require_charge_confirmation = true,
}

local PRECISION_TARGET_GRENADE_NAMES = {
	psyker_smite = true,
	psyker_throwing_knives = true,
}

local function should_use_assail_aimed_profile(context, rule_text)
	if not context then
		return false
	end

	if context.target_is_special then
		return true
	end

	local target_distance = context.target_enemy_distance or 0
	if target_distance >= 8 and string.find(rule_text, "priority", 1, true) then
		return true
	end

	return false
end

function M.init(deps)
	deps = deps or {}
	_warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold
end

function M.resolve_template_entry(grenade_name, context, rule)
	if grenade_name ~= "psyker_throwing_knives" then
		return SUPPORTED_THROW_TEMPLATES[grenade_name]
	end

	local rule_text = tostring(rule or "")

	if string.find(rule_text, "crowd_soften", 1, true) then
		return ASSAIL_BURST_PROFILE
	end

	if should_use_assail_aimed_profile(context, rule_text) then
		return ASSAIL_AIMED_PROFILE
	end

	return ASSAIL_FAST_PROFILE
end

function M.is_precision_target_grenade(grenade_name)
	return PRECISION_TARGET_GRENADE_NAMES[grenade_name] == true
end

return M
