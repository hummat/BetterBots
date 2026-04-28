-- Weapon action hooks: overheat bridge, vent translation, peril guard,
-- _may_fire() validation, ADS logging, and diagnostic weapon logging.
local DEFAULT_WARP_WEAPON_PERIL_THRESHOLD = 0.99

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _is_enabled
local _close_range_ranged_policy
local _warp_weapon_peril_threshold
local _weapon_action_logging
local _weapon_action_shoot
local _weapon_action_voidblast
local _missing_shoot_extension_warned = {}

local OVERHEAT_PATCH_SENTINEL = "__bb_overheat_slot_percentage_installed"
local SHOOT_ACTION_PATCH_SENTINEL = "__bb_weapon_action_bt_bot_shoot_action_installed"
local _shoot_action_hooks_installed = false
local _missing_bt_bot_shoot_action_warned = false

local _voidblast_retarget_logged_scratchpads = setmetatable({}, { __mode = "k" })
local _bt_shoot_scratchpad_context = setmetatable({}, { __mode = "k" })

local M = {}

function M._stream_action_phase(template_name, action_input)
	return _weapon_action_logging._stream_action_phase(template_name, action_input)
end

function M.log_stream_action(bot_slot, template_name, action_input)
	return _weapon_action_logging.log_stream_action(bot_slot, template_name, action_input)
end

function M.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
	return _weapon_action_logging.weakspot_aim_selection_context(unit, weapon_template, scratchpad)
end

function M.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
	return _weapon_action_logging.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
end

function M._normalize_bt_shoot_scratchpad(weapon_template, scratchpad)
	return _weapon_action_shoot.normalize_bt_shoot_scratchpad(weapon_template, scratchpad)
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_is_enabled = deps.is_enabled
	_close_range_ranged_policy = deps.close_range_ranged_policy
	_warp_weapon_peril_threshold = deps.warp_weapon_peril_threshold
		or function()
			return DEFAULT_WARP_WEAPON_PERIL_THRESHOLD
		end
	_weapon_action_logging = deps.weapon_action_logging
	assert(_weapon_action_logging, "BetterBots: weapon_action requires weapon_action_logging")
	_weapon_action_logging.init({
		mod = _mod,
		debug_log = _debug_log,
		debug_enabled = _debug_enabled,
		fixed_time = _fixed_time,
		bot_slot_for_unit = deps.bot_slot_for_unit,
		ammo = deps.ammo,
		is_weakspot_aim_enabled = deps.is_weakspot_aim_enabled,
	})
	_weapon_action_shoot = deps.weapon_action_shoot
	assert(_weapon_action_shoot, "BetterBots: weapon_action requires weapon_action_shoot")
	_weapon_action_shoot.init({
		debug_log = _debug_log,
		debug_enabled = _debug_enabled,
		fixed_time = _fixed_time,
	})
	_weapon_action_voidblast = deps.weapon_action_voidblast
	assert(_weapon_action_voidblast, "BetterBots: weapon_action requires weapon_action_voidblast")
	_weapon_action_voidblast.init({
		debug_log = _debug_log,
		debug_enabled = _debug_enabled,
		fixed_time = _fixed_time,
		scratchpad_player_unit = _weapon_action_shoot.scratchpad_player_unit,
		current_weapon_action_template_name = _weapon_action_shoot.current_weapon_action_template_name,
	})
	_missing_shoot_extension_warned = {}
	_missing_bt_bot_shoot_action_warned = false
	_shoot_action_hooks_installed = false
	_voidblast_retarget_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_bt_shoot_scratchpad_context = setmetatable({}, { __mode = "k" })
end

function M.dead_zone_ranged_fire_context(unit, action_input)
	return _weapon_action_logging.dead_zone_ranged_fire_context(unit, action_input)
end

function M.log_dead_zone_ranged_fire(unit, action_input)
	return _weapon_action_logging.log_dead_zone_ranged_fire(unit, action_input)
end

function M.register_hooks(deps)
	local should_lock_weapon_switch = deps.should_lock_weapon_switch
	local should_block_wield_input = deps.should_block_wield_input or should_lock_weapon_switch
	local should_block_weapon_action_input = deps.should_block_weapon_action_input
	local rewrite_weapon_action_input = deps.rewrite_weapon_action_input
	local observe_queued_weapon_action = deps.observe_queued_weapon_action
	local install_weakspot_aim = deps.install_weakspot_aim

	-- Overheat bridge (#30): warp weapons have no overheat_configuration,
	-- so slot_percentage returns 0 and the BT vent node never fires. Bridge
	-- warp_charge.current_percentage so should_vent_overheat triggers for peril.
	-- Also guards against plasma-style nested thresholds that crash vanilla.
	_mod:hook_require("scripts/utilities/overheat", function(Overheat)
		if not Overheat or rawget(Overheat, OVERHEAT_PATCH_SENTINEL) then
			return
		end
		Overheat[OVERHEAT_PATCH_SENTINEL] = true

		local _orig_slot_percentage = Overheat.slot_percentage
		Overheat.slot_percentage = function(unit, slot_name, threshold_type)
			local vis_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
			if vis_ext then
				local cfg = Overheat.configuration(vis_ext, slot_name)
				if cfg and not cfg[threshold_type] then
					return 0
				end
				if not cfg then
					local ude = ScriptUnit.has_extension(unit, "unit_data_system")
					if ude then
						local tweaks = ude:read_component("weapon_tweak_templates")
						if tweaks and tweaks.warp_charge_template_name ~= "none" then
							local warp = ude:read_component("warp_charge")
							if warp then
								return warp.current_percentage
							end
						end
					end
				end
			end
			return _orig_slot_percentage(unit, slot_name, threshold_type)
		end
	end)

	-- Shoot-action hooks: weakspot handoff, scratchpad cleanup, close-range ADS
	-- policy, and the _may_fire() validation fix.
	local _ads_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action",
		function(BtBotShootAction)
			if not BtBotShootAction then
				if not _missing_bt_bot_shoot_action_warned and _mod and _mod.warning then
					_missing_bt_bot_shoot_action_warned = true
					_mod:warning("BetterBots: bt_bot_shoot_action hook_require resolved nil")
				end
				return
			end
			if _shoot_action_hooks_installed or rawget(BtBotShootAction, SHOOT_ACTION_PATCH_SENTINEL) then
				return
			end
			_shoot_action_hooks_installed = true
			BtBotShootAction[SHOOT_ACTION_PATCH_SENTINEL] = true

			local PlayerUnitVisualLoadout =
				require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
			local _close_range_ads_logged_scratchpads = setmetatable({}, { __mode = "k" })

			if install_weakspot_aim then
				install_weakspot_aim(BtBotShootAction)
			end

			_mod:hook_safe(BtBotShootAction, "enter", function(_self, unit, _breed, _blackboard, scratchpad)
				if _is_enabled and not _is_enabled() then
					return
				end

				if scratchpad then
					-- This is a post-hook, so the first _set_new_aim_target call inside
					-- vanilla enter cannot rely on __bb_weakspot_self_unit functionally.
					-- Today the field is only used for weakspot logging context.
					scratchpad.__bb_weakspot_self_unit = unit
				end

				local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
				local visual_loadout_extension = ScriptUnit.has_extension(unit, "visual_loadout_system")
				if not unit_data_extension or not visual_loadout_extension then
					local unit_key = tostring(unit)
					if _debug_enabled() then
						_debug_log(
							"shoot_scratchpad_missing_ext:" .. unit_key,
							_fixed_time(),
							"shoot scratchpad normalization skipped: missing unit_data_system or visual_loadout_system"
						)
					end
					if not _missing_shoot_extension_warned[unit_key] and _mod and _mod.warning then
						_missing_shoot_extension_warned[unit_key] = true
						_mod:warning(
							"BetterBots: shoot scratchpad normalization skipped for "
								.. unit_key
								.. " because unit_data_system or visual_loadout_system is missing"
						)
					end
					return
				end

				local inventory_component = unit_data_extension:read_component("inventory")
				local weapon_template =
					PlayerUnitVisualLoadout.wielded_weapon_template(visual_loadout_extension, inventory_component)
				if M._normalize_bt_shoot_scratchpad(weapon_template, scratchpad) and _debug_enabled() then
					_debug_log(
						"shoot_scratchpad_normalized:" .. tostring(unit),
						_fixed_time(),
						"normalized shoot scratchpad inputs (fire="
							.. tostring(scratchpad.fire_action_input)
							.. ", aim_fire="
							.. tostring(scratchpad.aim_fire_action_input)
							.. ", aim="
							.. tostring(scratchpad.aim_action_input)
							.. ", unaim="
							.. tostring(scratchpad.unaim_action_input)
							.. ")"
					)
				end

				scratchpad.close_range_ranged_policy = _close_range_ranged_policy
						and _close_range_ranged_policy(weapon_template)
					or nil
				M.log_weakspot_aim_selection(unit, weapon_template, scratchpad)
			end)

			_mod:hook(BtBotShootAction, "_update_aim", function(func, self, unit, scratchpad, action_data, dt, t)
				if _is_enabled and not _is_enabled() then
					return func(self, unit, scratchpad, action_data, dt, t)
				end

				local perception_component = scratchpad and scratchpad.perception_component or nil
				local locked_target = scratchpad
						and scratchpad.__bb_voidblast_anchor
						and scratchpad.__bb_voidblast_anchor.target_unit
					or nil
				local anchor_state, anchor_reason
				if _weapon_action_voidblast.should_lock_anchor(scratchpad) and locked_target then
					anchor_state, anchor_reason =
						_weapon_action_voidblast.resolve_anchor_state(self, unit, scratchpad, locked_target)
					if anchor_reason then
						_weapon_action_voidblast.log_fallback(scratchpad, unit, locked_target, anchor_reason)
					end
				end

				if not anchor_state then
					locked_target = nil
				end

				local should_lock = _weapon_action_voidblast.should_lock_anchor(scratchpad)
					and perception_component
					and locked_target
				local locked_perception_component = should_lock and perception_component or nil
				local original_target = locked_perception_component and locked_perception_component.target_enemy or nil

				_bt_shoot_scratchpad_context[unit] = scratchpad
				if locked_perception_component and original_target ~= locked_target then
					if
						_debug_enabled
						and _debug_enabled()
						and not _voidblast_retarget_logged_scratchpads[scratchpad]
					then
						_voidblast_retarget_logged_scratchpads[scratchpad] = true
						_debug_log(
							"voidblast_retarget:" .. tostring(_weapon_action_shoot.scratchpad_player_unit(scratchpad)),
							_fixed_time(),
							"voidblast anchor held through retarget (from="
								.. tostring(original_target)
								.. ", to="
								.. tostring(locked_target)
								.. ")"
						)
					end

					locked_perception_component.target_enemy = locked_target
				end

				local ok, done, evaluate = pcall(func, self, unit, scratchpad, action_data, dt, t)
				_bt_shoot_scratchpad_context[unit] = nil
				if scratchpad then
					scratchpad.__bb_voidblast_anchor_suppressed = nil
				end

				if locked_perception_component and original_target ~= locked_target then
					locked_perception_component.target_enemy = original_target
				end

				if not ok then
					if _debug_enabled and _debug_enabled() then
						local scratchpad_unit = _weapon_action_shoot.scratchpad_player_unit(scratchpad) or unit
						_debug_log(
							"voidblast_retarget_restore_error:" .. tostring(scratchpad_unit),
							t,
							"restored Voidblast locked target after vanilla _update_aim error"
								.. " (bot="
								.. tostring(scratchpad_unit)
								.. ", target="
								.. tostring(original_target)
								.. ")",
							nil,
							"info"
						)
					end
					error(done, 0)
				end

				return done, evaluate
			end)

			_mod:hook(
				BtBotShootAction,
				"_wanted_aim_rotation",
				function(
					func,
					self,
					self_unit,
					target_unit,
					target_breed,
					current_position,
					projectile_template,
					aim_at_node
				)
					if _is_enabled and not _is_enabled() then
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					local scratchpad = _bt_shoot_scratchpad_context[self_unit]
					local state, state_reason =
						_weapon_action_voidblast.resolve_anchor_state(self, self_unit, scratchpad, target_unit)
					if not state then
						if state_reason then
							_weapon_action_voidblast.log_fallback(scratchpad, self_unit, target_unit, state_reason)
						end
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					local wanted_rotation, rotation_reason =
						_weapon_action_voidblast.aim_rotation(current_position, state.position)
					if not wanted_rotation then
						if rotation_reason then
							_weapon_action_voidblast.log_fallback(scratchpad, self_unit, target_unit, rotation_reason)
						end
						return func(
							self,
							self_unit,
							target_unit,
							target_breed,
							current_position,
							projectile_template,
							aim_at_node
						)
					end

					return wanted_rotation, state.position
				end
			)

			_mod:hook(BtBotShootAction, "_should_aim", function(func, self, t, scratchpad, action_data)
				if _is_enabled and not _is_enabled() then
					return func(self, t, scratchpad, action_data)
				end

				local should_aim = func(self, t, scratchpad, action_data)
				if not should_aim then
					return false
				end

				local policy = scratchpad and scratchpad.close_range_ranged_policy
				local perception_component = scratchpad and scratchpad.perception_component or nil
				local target_enemy_distance = perception_component and perception_component.target_enemy_distance or nil
				local target_enemy_distance_sq = target_enemy_distance and target_enemy_distance * target_enemy_distance
					or nil

				if
					not policy
					or not policy.hipfire_distance_sq
					or not target_enemy_distance_sq
					or target_enemy_distance_sq > policy.hipfire_distance_sq
				then
					local suppress, template_name = _weapon_action_shoot.should_suppress_stale_shoot_action(
						scratchpad,
						scratchpad and scratchpad.aim_action_input
					)
					if suppress then
						_weapon_action_shoot.log_stale_shoot_action(
							scratchpad,
							"aim",
							scratchpad and scratchpad.aim_action_input,
							template_name
						)
						return false
					end
					return should_aim
				end

				if not _close_range_ads_logged_scratchpads[scratchpad] and _debug_enabled() then
					_close_range_ads_logged_scratchpads[scratchpad] = true
					_debug_log(
						"close_range_hipfire:" .. tostring(scratchpad),
						_fixed_time(),
						"close-range hipfire suppressed ADS (family="
							.. tostring(policy.family or "?")
							.. ", distance="
							.. string.format("%.2f", target_enemy_distance)
							.. ")"
					)
				end

				return false
			end)

			_mod:hook(BtBotShootAction, "_start_aiming", function(func, self, t, scratchpad)
				if _is_enabled and not _is_enabled() then
					return func(self, t, scratchpad)
				end

				local suppress, template_name = _weapon_action_shoot.should_suppress_stale_shoot_action(
					scratchpad,
					scratchpad and scratchpad.aim_action_input
				)
				if suppress then
					if scratchpad then
						scratchpad.aiming_shot = false
						scratchpad.aim_done_t = 0
					end
					_weapon_action_shoot.log_stale_shoot_action(
						scratchpad,
						"aim",
						scratchpad and scratchpad.aim_action_input,
						template_name
					)
					return nil
				end

				local result = func(self, t, scratchpad)
				if scratchpad and not _ads_logged_scratchpads[scratchpad] then
					_ads_logged_scratchpads[scratchpad] = true
					if _debug_enabled() then
						local gestalt = scratchpad.ranged_gestalt or "?"
						_mod:echo("BetterBots DEBUG: bot ADS confirmed (ranged_gestalt=" .. tostring(gestalt) .. ")")
					end
				end
				return result
			end)

			_mod:hook(BtBotShootAction, "_stop_aiming", function(func, self, scratchpad)
				if _is_enabled and not _is_enabled() then
					return func(self, scratchpad)
				end

				local suppress, template_name = _weapon_action_shoot.should_suppress_stale_shoot_unaim(scratchpad)
				if suppress then
					if scratchpad and scratchpad.aiming_shot then
						scratchpad.aiming_shot = false
						scratchpad.aim_done_t = 0
					end
					_weapon_action_shoot.log_stale_shoot_action(
						scratchpad,
						"unaim",
						scratchpad and scratchpad.unaim_action_input,
						template_name
					)
					return nil
				end

				return func(self, scratchpad)
			end)

			-- #43: vanilla _may_fire() validates fire_action_input even though
			-- _fire() dispatches aim_fire_action_input while aiming. Swap only
			-- for this validation call so ADS/charge weapons validate the input
			-- they will actually queue.
			local _may_fire_logged = setmetatable({}, { __mode = "k" })
			_mod:hook(BtBotShootAction, "_may_fire", function(func, self, unit, scratchpad, range_squared, t)
				if _is_enabled and not _is_enabled() then
					return func(self, unit, scratchpad, range_squared, t)
				end
				local perf_t0 = _perf and _perf.begin()
				local forced_fire_action_input = _weapon_action_voidblast.forced_fire_input(scratchpad)
				if not scratchpad or not forced_fire_action_input then
					local result = func(self, unit, scratchpad, range_squared, t)
					if not result then
						_weapon_action_shoot.log_plasma_may_fire_block(scratchpad, range_squared, t)
					end
					if perf_t0 then
						_perf.finish("weapon_action.may_fire", perf_t0)
					end
					return result
				end

				if not _may_fire_logged[scratchpad] and _debug_enabled() then
					_may_fire_logged[scratchpad] = true
					_debug_log(
						"may_fire_swap:" .. tostring(forced_fire_action_input),
						_fixed_time(),
						"_may_fire swap: fire="
							.. tostring(scratchpad.fire_action_input)
							.. " -> aim_fire="
							.. tostring(forced_fire_action_input)
					)
				end

				local fire_action_input = scratchpad.fire_action_input
				scratchpad.fire_action_input = forced_fire_action_input

				local may_fire = func(self, unit, scratchpad, range_squared, t)

				scratchpad.fire_action_input = fire_action_input
				if not may_fire then
					_weapon_action_shoot.log_plasma_may_fire_block(scratchpad, range_squared, t)
				end
				if perf_t0 then
					_perf.finish("weapon_action.may_fire", perf_t0)
				end

				return may_fire
			end)

			local _voidblast_fire_override_logged = setmetatable({}, { __mode = "k" })
			_mod:hook(BtBotShootAction, "_fire", function(func, self, scratchpad, action_data, bot_unit_input, t)
				if _is_enabled and not _is_enabled() then
					return func(self, scratchpad, action_data, bot_unit_input, t)
				end

				if not _weapon_action_voidblast.should_force_charged_fire(scratchpad) then
					return func(self, scratchpad, action_data, bot_unit_input, t)
				end

				local charged_fire_input = _weapon_action_voidblast.forced_fire_input(scratchpad)
				local aiming_shot = scratchpad.aiming_shot
				local aim_fire_action_input = scratchpad.aim_fire_action_input
				scratchpad.aiming_shot = true
				scratchpad.aim_fire_action_input = charged_fire_input

				if not _voidblast_fire_override_logged[scratchpad] and _debug_enabled() then
					_voidblast_fire_override_logged[scratchpad] = true
					_debug_log(
						"voidblast_fire_override:" .. tostring(_weapon_action_shoot.scratchpad_player_unit(scratchpad)),
						_fixed_time(),
						"voidblast charged fire override (fire="
							.. tostring(scratchpad.fire_action_input)
							.. " -> charged_fire="
							.. tostring(charged_fire_input)
							.. ")"
					)
				end

				local ok, result_a, result_b, result_c, result_d =
					pcall(func, self, scratchpad, action_data, bot_unit_input, t)
				scratchpad.aim_fire_action_input = aim_fire_action_input
				scratchpad.aiming_shot = aiming_shot

				if not ok then
					error(result_a, 0)
				end

				return result_a, result_b, result_c, result_d
			end)
		end
	)

	-- bot_queue_action_input: wield lock, vent translation, peril guard,
	-- and diagnostic weapon logging.
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
					if _is_enabled and not _is_enabled() then
						return func(self, id, action_input, raw_input)
					end
					local perf_t0 = _perf and _perf.begin()
					local unit = self._betterbots_player_unit
					local original_action_input = action_input
					if unit and id == "weapon_action" and action_input == "wield" then
						local should_block, ability_name = should_block_wield_input(unit)
						if should_block then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								local _, _, lock_reason = should_lock_weapon_switch(unit)
								_debug_log(
									"lock_wield:" .. tostring(ability_name),
									fixed_t,
									"blocked weapon switch while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(lock_reason or "sequence")
										.. " (raw_input="
										.. tostring(raw_input)
										.. ")"
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					if unit and id == "weapon_action" and rewrite_weapon_action_input then
						local rewritten_action_input, rewritten_raw_input =
							rewrite_weapon_action_input(unit, action_input, raw_input)
						action_input = rewritten_action_input or action_input
						if rewritten_raw_input ~= nil then
							raw_input = rewritten_raw_input
						end
					end

					if unit and id == "weapon_action" and (action_input == "zoom" or action_input == "unzoom") then
						local template_name = _weapon_action_shoot.current_weapon_action_template_name(unit)
						if
							template_name
							and not _weapon_action_shoot.accepts_weapon_action_input(self, template_name, action_input)
						then
							if _debug_enabled() then
								_debug_log(
									"drop_unsupported_weapon_action:"
										.. tostring(template_name)
										.. ":"
										.. tostring(action_input),
									_fixed_time(),
									"dropped unsupported queued weapon action "
										.. tostring(action_input)
										.. " for "
										.. tostring(template_name)
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					if
						unit
						and id == "weapon_action"
						and action_input ~= "wield"
						and should_block_weapon_action_input
					then
						local should_block, ability_name, block_reason =
							should_block_weapon_action_input(unit, action_input)
						if should_block then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								_debug_log(
									"lock_weapon_action:" .. tostring(ability_name) .. ":" .. tostring(action_input),
									fixed_t,
									"blocked foreign weapon action "
										.. tostring(action_input)
										.. " while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(block_reason or "sequence")
								)
							end
							if perf_t0 then
								_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
							end
							return nil
						end
					end

					-- BtBotReloadAction queues "reload" but warp weapons have
					-- "vent" not "reload". Translate before the peril guard so
					-- venting is not blocked at critical peril.
					if unit and id == "weapon_action" and action_input == "reload" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local tweaks = ude:read_component("weapon_tweak_templates")
							if tweaks and tweaks.warp_charge_template_name ~= "none" then
								if _debug_enabled() then
									_debug_log(
										"vent_translate:" .. tostring(unit),
										_fixed_time(),
										"translated reload -> vent (warp weapon)"
									)
								end
								action_input = "vent"
							end
						end
					end

					if unit and id == "weapon_action" and action_input ~= "wield" and action_input ~= "vent" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local warp = ude:read_component("warp_charge")
							local peril_threshold = _warp_weapon_peril_threshold and _warp_weapon_peril_threshold()
								or DEFAULT_WARP_WEAPON_PERIL_THRESHOLD
							if warp and warp.current_percentage >= peril_threshold then
								local tweaks = ude:read_component("weapon_tweak_templates")
								if tweaks and tweaks.warp_charge_template_name ~= "none" then
									if _debug_enabled() then
										_debug_log(
											"peril_block:" .. tostring(action_input),
											_fixed_time(),
											"blocked "
												.. tostring(action_input)
												.. " (peril="
												.. string.format("%.0f%%", warp.current_percentage * 100)
												.. ", warp weapon)"
										)
									end
									if perf_t0 then
										_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
									end
									return nil
								end
							end
						end
					end

					-- Log bot weapon actions (except wield) with bot/template tags
					-- so charged inputs can be attributed to the correct bot and
					-- staff family. One-shot per unique combo.
					if id == "weapon_action" and action_input ~= "wield" and _debug_enabled() then
						_weapon_action_logging.log_bot_weapon_action(unit, action_input, raw_input)
					end

					local result = func(self, id, action_input, raw_input)
					if result ~= nil and id == "weapon_action" and unit then
						if observe_queued_weapon_action then
							observe_queued_weapon_action(unit, action_input, original_action_input)
						end
					end
					if result ~= nil and id == "weapon_action" and unit and _debug_enabled() then
						local bot_slot, _, weapon_template_name = _weapon_action_logging.weapon_log_context(unit)
						M.log_stream_action(bot_slot, weapon_template_name, action_input)
					end
					if perf_t0 then
						_perf.finish("weapon_action.bot_queue_action_input", perf_t0)
					end
					return result
				end
			)
		end
	)

	-- Wield slot redirect: keep combat ability slot wielded during item fallback.
	_mod:hook_require(
		"scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout",
		function(PlayerUnitVisualLoadout)
			_mod:hook(
				PlayerUnitVisualLoadout,
				"wield_slot",
				function(func, slot_to_wield, player_unit, t, skip_wield_action)
					local perf_t0 = _perf and _perf.begin()
					local should_lock, ability_name, lock_reason, slot_to_keep = should_lock_weapon_switch(player_unit)
					if should_lock then
						slot_to_keep = slot_to_keep or "slot_combat_ability"
						if slot_to_wield ~= slot_to_keep then
							if _debug_enabled() then
								local fixed_t = _fixed_time()
								_debug_log(
									"lock_wield_direct:" .. tostring(ability_name),
									fixed_t,
									"redirected wield_slot("
										.. tostring(slot_to_wield)
										.. ") -> "
										.. tostring(slot_to_keep)
										.. " while keeping "
										.. tostring(ability_name)
										.. " "
										.. tostring(lock_reason)
								)
							end
							local result = func(slot_to_keep, player_unit, t, skip_wield_action)
							if perf_t0 then
								_perf.finish("weapon_action.wield_slot", perf_t0)
							end
							return result
						end
					end

					local result = func(slot_to_wield, player_unit, t, skip_wield_action)
					if perf_t0 then
						_perf.finish("weapon_action.wield_slot", perf_t0)
					end
					return result
				end
			)
		end
	)

	-- WeaponSystem.queue_perils_of_the_warp_elite_kills_achievement calls
	-- player:account_id() unconditionally; bot-backed player objects can return nil.
	_mod:hook_require("scripts/extension_systems/weapon/weapon_system", function(WeaponSystem)
		_mod:hook(
			WeaponSystem,
			"queue_perils_of_the_warp_elite_kills_achievement",
			function(func, self, player, explosion_queue_index)
				local account_id = nil
				if player and type(player.account_id) == "function" then
					account_id = player:account_id()
				end

				if account_id == nil then
					_debug_log(
						"skip_perils_nil_account",
						_fixed_time(),
						"skipped perils achievement queue with nil account_id"
					)
					return nil
				end

				return func(self, player, explosion_queue_index)
			end
		)
	end)
end

return M
