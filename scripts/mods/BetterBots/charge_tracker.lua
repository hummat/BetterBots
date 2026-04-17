local M = {}

local _fixed_time
local _debug_log
local _debug_enabled
local _last_charge_event_by_unit
local _fallback_state_by_unit
local _grenade_fallback
local _settings
local _team_cooldown
local _combat_ability_identity
local _event_log
local _bot_slot_for_unit

function M.init(deps)
	_fixed_time = deps.fixed_time
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_last_charge_event_by_unit = deps.last_charge_event_by_unit
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_grenade_fallback = deps.grenade_fallback
	_settings = deps.settings
	_team_cooldown = deps.team_cooldown
	_combat_ability_identity = deps.combat_ability_identity
	_event_log = deps.event_log
	_bot_slot_for_unit = deps.bot_slot_for_unit
end

function M.handle(self, ability_type, optional_num_charges)
	if ability_type ~= "combat_ability" and ability_type ~= "grenade_ability" then
		return
	end

	local player = self._player
	if not player or player:is_human_controlled() then
		return
	end

	if ability_type == "grenade_ability" then
		local grenade_name = "unknown"
		local equipped_abilities = self._equipped_abilities
		local grenade_ability = equipped_abilities and equipped_abilities.grenade_ability
		if grenade_ability and grenade_ability.name then
			grenade_name = grenade_ability.name
		end

		local unit = self._unit
		if unit then
			_grenade_fallback.record_charge_event(unit, grenade_name, _fixed_time())
		end

		if _debug_enabled() then
			_debug_log(
				"grenade_charge:" .. grenade_name .. ":" .. tostring(unit),
				_fixed_time(),
				"grenade charge consumed for "
					.. grenade_name
					.. " (charges="
					.. tostring(optional_num_charges or 1)
					.. ")"
			)
		end
		return
	end

	local ability_name = "unknown"
	local equipped_abilities = self._equipped_abilities
	local combat_ability = equipped_abilities and equipped_abilities.combat_ability
	if combat_ability and combat_ability.name then
		ability_name = combat_ability.name
	end

	local fixed_t = _fixed_time()
	local unit = self._unit
	if unit then
		_last_charge_event_by_unit[unit] = {
			ability_name = ability_name,
			fixed_t = fixed_t,
		}
		if ability_name ~= "unknown" then
			-- Resolve to the base/semantic template name so variant talent
			-- names (e.g. psyker_discharge_shout_improved) collapse to the
			-- key team_cooldown.CATEGORY_MAP uses (psyker_shout). Without
			-- this, record() is a silent no-op for variant abilities and
			-- staggering never fires for their category.
			if _settings.is_feature_enabled("team_cooldown") then
				local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
				local ability_component = unit_data_ext and unit_data_ext:read_component("combat_ability_action")
				local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
				local identity = _combat_ability_identity.resolve(unit, ability_extension, ability_component)
				local team_key = (identity and identity.semantic_key) or ability_name
				_team_cooldown.record(unit, team_key, fixed_t)
			end
		end

		if _event_log.is_enabled() then
			local bot_slot = _bot_slot_for_unit(unit)
			local fb_state = _fallback_state_by_unit[unit]
			_event_log.emit({
				t = fixed_t,
				event = "consumed",
				bot = bot_slot,
				ability = ability_name,
				charges = optional_num_charges or 1,
				rule = fb_state and fb_state.item_rule or nil,
				attempt_id = fb_state and fb_state.attempt_id or nil,
			})
		end
	end

	if not _debug_enabled() then
		return
	end

	_debug_log(
		"charge:" .. ability_name,
		fixed_t,
		"charge consumed for " .. ability_name .. " (charges=" .. tostring(optional_num_charges or 1) .. ")"
	)
end

return M
