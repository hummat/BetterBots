local STALE_WINDOW_S = 0.25

local _mod
local _debug_log
local _debug_enabled
local _fixed_time = function()
	return 0
end
local _bot_slot_for_unit
local _is_enabled

local _active_state_by_unit = setmetatable({}, { __mode = "k" })

local CLEAR_ACTION_INPUTS = {
	reload = true,
	brace_reload = true,
	wield = true,
	vent = true,
	vent_release = true,
	shoot_release = true,
	shoot_braced_release = true,
	zoom_release = true,
	brace_release = true,
	cancel_flame = true,
	charge_release = true,
}

local SHOOT_AND_ZOOM_HOLD = {
	shoot = { action_one_hold = true },
	zoom_shoot = { action_one_hold = true },
}

local ZOOM_ONLY_HOLD = {
	zoom_shoot = { action_one_hold = true },
}

local SUSTAINED_TEMPLATE_ACTIONS = {
	flamer_p1_m1 = {
		shoot_braced = { action_one_hold = true },
	},
	forcestaff_p2_m1 = {
		trigger_charge_flame = { action_two_hold = true },
	},
	lasgun_p3_m1 = SHOOT_AND_ZOOM_HOLD,
	lasgun_p3_m2 = SHOOT_AND_ZOOM_HOLD,
	lasgun_p3_m3 = SHOOT_AND_ZOOM_HOLD,
	autogun_p1_m1 = SHOOT_AND_ZOOM_HOLD,
	autogun_p1_m2 = SHOOT_AND_ZOOM_HOLD,
	autogun_p1_m3 = SHOOT_AND_ZOOM_HOLD,
	autogun_p2_m1 = SHOOT_AND_ZOOM_HOLD,
	autogun_p2_m2 = SHOOT_AND_ZOOM_HOLD,
	autogun_p2_m3 = SHOOT_AND_ZOOM_HOLD,
	autopistol_p1_m1 = SHOOT_AND_ZOOM_HOLD,
	dual_autopistols_p1_m1 = SHOOT_AND_ZOOM_HOLD,
	bolter_p1_m2 = {
		shoot_pressed = { action_one_hold = true },
	},
	ogryn_heavystubber_p1_m1 = SHOOT_AND_ZOOM_HOLD,
	ogryn_heavystubber_p1_m2 = SHOOT_AND_ZOOM_HOLD,
	ogryn_heavystubber_p1_m3 = SHOOT_AND_ZOOM_HOLD,
	ogryn_heavystubber_p2_m1 = SHOOT_AND_ZOOM_HOLD,
	ogryn_heavystubber_p2_m2 = SHOOT_AND_ZOOM_HOLD,
	ogryn_heavystubber_p2_m3 = SHOOT_AND_ZOOM_HOLD,
	ogryn_rippergun_p1_m1 = ZOOM_ONLY_HOLD,
	ogryn_rippergun_p1_m2 = ZOOM_ONLY_HOLD,
}

local M = {}

local function _copy_table(src)
	local dst = {}

	for key, value in pairs(src or {}) do
		dst[key] = value
	end

	return dst
end

local function _current_weapon_template_name(unit)
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return nil
	end

	local weapon_action = unit_data_extension:read_component("weapon_action")
	return weapon_action and weapon_action.template_name or nil
end

local function _debug_key(prefix, unit, template_name)
	return prefix .. ":" .. tostring(unit) .. ":" .. tostring(template_name or "none")
end

local function _log_arm(unit, state)
	if not _debug_enabled or not _debug_enabled() then
		return
	end

	_debug_log(
		_debug_key("sustained_fire_arm", unit, state.template_name),
		_fixed_time(),
		"armed sustained fire (bot="
			.. tostring(_bot_slot_for_unit and _bot_slot_for_unit(unit) or "?")
			.. ", template="
			.. tostring(state.template_name)
			.. ", action="
			.. tostring(state.action_input)
			.. ")"
	)
end

local function _log_hold(unit, state)
	if not _debug_enabled or not _debug_enabled() or state.hold_logged then
		return
	end

	state.hold_logged = true
	_debug_log(
		_debug_key("sustained_fire_hold", unit, state.template_name),
		_fixed_time(),
		"holding sustained fire inputs (bot="
			.. tostring(_bot_slot_for_unit and _bot_slot_for_unit(unit) or "?")
			.. ", template="
			.. tostring(state.template_name)
			.. ", action="
			.. tostring(state.action_input)
			.. ")"
	)
end

local function _log_clear(unit, template_name, reason)
	if not _debug_enabled or not _debug_enabled() then
		return
	end

	_debug_log(
		_debug_key("sustained_fire_clear", unit, template_name),
		_fixed_time(),
		"cleared sustained fire (bot="
			.. tostring(_bot_slot_for_unit and _bot_slot_for_unit(unit) or "?")
			.. ", template="
			.. tostring(template_name)
			.. ", reason="
			.. tostring(reason)
			.. ")"
	)
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time or function()
		return 0
	end
	_bot_slot_for_unit = deps.bot_slot_for_unit
	_is_enabled = deps.is_enabled
	_active_state_by_unit = setmetatable({}, { __mode = "k" })
end

function M.resolve_state(unit, template_name, action_input)
	local actions = SUSTAINED_TEMPLATE_ACTIONS[template_name]
	local hold_inputs = actions and actions[action_input]
	if not hold_inputs then
		return nil
	end

	return {
		unit = unit,
		template_name = template_name,
		action_input = action_input,
		hold_inputs = _copy_table(hold_inputs),
		last_seen_t = _fixed_time(),
		hold_logged = false,
	}
end

function M.arm(unit, state)
	if not unit or not state then
		return
	end

	state.last_seen_t = _fixed_time()
	state.hold_logged = false
	_active_state_by_unit[unit] = state
end

function M.active_state(unit)
	return _active_state_by_unit[unit]
end

function M.clear(unit, reason)
	local state = _active_state_by_unit[unit]
	if not state then
		return
	end

	_active_state_by_unit[unit] = nil
	_log_clear(unit, state.template_name, reason)
end

function M.observe_weapon_action_input(unit, template_name, action_input)
	if not unit or not template_name then
		return nil
	end

	if CLEAR_ACTION_INPUTS[action_input] then
		M.clear(unit, action_input)
		return nil
	end

	local state = M.resolve_state(unit, template_name, action_input)
	if state then
		M.arm(unit, state)
		_log_arm(unit, state)
		return state
	end

	local active = _active_state_by_unit[unit]
	if active and active.template_name == template_name and active.action_input ~= action_input then
		M.clear(unit, "replace:" .. tostring(action_input))
	end

	return nil
end

function M.observe_queued_weapon_action(unit, action_input)
	local template_name = _current_weapon_template_name(unit)
	return M.observe_weapon_action_input(unit, template_name, action_input)
end

function M.update_actions(unit, input, current_template_name)
	local state = _active_state_by_unit[unit]
	if not state then
		return
	end

	local live_template_name = current_template_name or _current_weapon_template_name(unit)
	if live_template_name ~= state.template_name then
		M.clear(unit, "template_changed")
		return
	end

	local now = _fixed_time()
	if now - state.last_seen_t > STALE_WINDOW_S then
		M.clear(unit, "stale")
		return
	end

	-- Refresh liveness while the hold bridge is still actively asserting inputs.
	-- Without this, long-hold weapons expire after STALE_WINDOW_S even though
	-- the bot is still intentionally sustaining the fire path.
	state.last_seen_t = now

	for hold_input, value in pairs(state.hold_inputs) do
		input[hold_input] = value
	end

	_log_hold(unit, state)
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/action_input/player_unit_action_input_extension",
		function(PlayerUnitActionInputExtension)
			_mod:hook_safe(PlayerUnitActionInputExtension, "extensions_ready", function(self, _world, unit)
				self._betterbots_player_unit = unit
			end)

			_mod:hook(
				PlayerUnitActionInputExtension,
				"bot_queue_action_input",
				function(func, self, id, action_input, raw_input)
					local result = func(self, id, action_input, raw_input)
					if result and id == "weapon_action" then
						M.observe_queued_weapon_action(self._betterbots_player_unit, action_input)
					end
					return result
				end
			)
		end
	)

	_mod:hook_require("scripts/extension_systems/input/bot_unit_input", function(BotUnitInput)
		_mod:hook(BotUnitInput, "update", function(func, self, unit, dt, t)
			self._betterbots_player_unit = unit
			return func(self, unit, dt, t)
		end)

		_mod:hook(BotUnitInput, "_update_actions", function(func, self, input)
			func(self, input)

			if _is_enabled and not _is_enabled() then
				return
			end

			local ok, err = pcall(M.update_actions, self._betterbots_player_unit, input)
			if not ok and _debug_enabled and _debug_enabled() then
				_debug_log(
					"sustained_fire_error:" .. tostring(self._betterbots_player_unit),
					_fixed_time(),
					tostring(err)
				)
			end
		end)
	end)
end

return M
