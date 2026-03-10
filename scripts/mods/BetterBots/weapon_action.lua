-- Weapon action hooks: overheat bridge (#30), vent translation (#30),
-- peril guard, _may_fire() validation fix (#43), ADS logging (#35),
-- and diagnostic weapon logging (#43).
local PERIL_CRITICAL_THRESHOLD = 0.97

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit

-- One-shot set: each unique bot:template:action:raw_input combo logged once
-- per load. Mirrors the ability_queue.lua context dump pattern.
local _weapon_logged_combos = {}

local function _weapon_log_context(unit)
	local bot_slot = _bot_slot_for_unit(unit) or "?"
	local wielded_slot = "none"
	local weapon_template_name = "none"
	local warp_charge_template_name = "none"
	local unit_data_extension = unit and ScriptUnit.has_extension(unit, "unit_data_system")
	if unit_data_extension then
		local inventory_component = unit_data_extension:read_component("inventory")
		local weapon_action_component = unit_data_extension:read_component("weapon_action")
		local weapon_tweaks_component = unit_data_extension:read_component("weapon_tweak_templates")
		wielded_slot = inventory_component and inventory_component.wielded_slot or "none"
		weapon_template_name = weapon_action_component and weapon_action_component.template_name or "none"
		warp_charge_template_name = weapon_tweaks_component and weapon_tweaks_component.warp_charge_template_name
			or "none"
	end

	return bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name
end

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
end

function M.register_hooks(deps)
	local should_lock_weapon_switch = deps.should_lock_weapon_switch

	-- Overheat bridge (#30): warp weapons have no overheat_configuration,
	-- so slot_percentage returns 0 and the BT vent node never fires. Bridge
	-- warp_charge.current_percentage so should_vent_overheat triggers for peril.
	-- Also guards against plasma-style nested thresholds that crash vanilla.
	_mod:hook_require("scripts/utilities/overheat", function(Overheat)
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

	-- ADS verification log (#35) + _may_fire() validation fix (#43)
	local _ads_logged_scratchpads = setmetatable({}, { __mode = "k" })
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action",
		function(BtBotShootAction)
			_mod:hook_safe(BtBotShootAction, "_start_aiming", function(_self, _t, scratchpad)
				if scratchpad and not _ads_logged_scratchpads[scratchpad] then
					_ads_logged_scratchpads[scratchpad] = true
					if _debug_enabled() then
						local gestalt = scratchpad.ranged_gestalt or "?"
						_mod:echo("BetterBots DEBUG: bot ADS confirmed (ranged_gestalt=" .. tostring(gestalt) .. ")")
					end
				end
			end)

			-- #43: vanilla _may_fire() validates fire_action_input even though
			-- _fire() dispatches aim_fire_action_input while aiming. Swap only
			-- for this validation call so ADS/charge weapons validate the input
			-- they will actually queue.
			_mod:hook(BtBotShootAction, "_may_fire", function(func, self, unit, scratchpad, range_squared, t)
				if
					not scratchpad
					or not scratchpad.aiming_shot
					or scratchpad.fire_action_input == scratchpad.aim_fire_action_input
				then
					return func(self, unit, scratchpad, range_squared, t)
				end

				local fire_action_input = scratchpad.fire_action_input
				scratchpad.fire_action_input = scratchpad.aim_fire_action_input

				local may_fire = func(self, unit, scratchpad, range_squared, t)

				scratchpad.fire_action_input = fire_action_input

				return may_fire
			end)
		end
	)

	-- bot_queue_action_input: wield lock, vent translation (#30), peril guard,
	-- and diagnostic weapon logging (#43).
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
					local unit = self._betterbots_player_unit
					if unit and id == "weapon_action" and action_input == "wield" then
						local should_lock, ability_name, lock_reason = should_lock_weapon_switch(unit)
						if should_lock then
							local fixed_t = _fixed_time()
							_debug_log(
								"lock_wield:" .. tostring(ability_name),
								fixed_t,
								"blocked weapon switch while keeping "
									.. tostring(ability_name)
									.. " "
									.. tostring(lock_reason)
									.. " (raw_input="
									.. tostring(raw_input)
									.. ")"
							)
							return nil
						end
					end

					-- #30: BtBotReloadAction queues "reload" but warp weapons have
					-- "vent" not "reload". Translate BEFORE the peril guard so
					-- venting is not blocked at critical peril.
					if unit and id == "weapon_action" and action_input == "reload" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local tweaks = ude:read_component("weapon_tweak_templates")
							if tweaks and tweaks.warp_charge_template_name ~= "none" then
								_debug_log(
									"vent_translate:" .. tostring(unit),
									_fixed_time(),
									"translated reload -> vent (warp weapon)"
								)
								action_input = "vent"
							end
						end
					end

					if unit and id == "weapon_action" and action_input ~= "wield" and action_input ~= "vent" then
						local ude = ScriptUnit.has_extension(unit, "unit_data_system")
						if ude then
							local warp = ude:read_component("warp_charge")
							if warp and warp.current_percentage >= PERIL_CRITICAL_THRESHOLD then
								local tweaks = ude:read_component("weapon_tweak_templates")
								if tweaks and tweaks.warp_charge_template_name ~= "none" then
									_debug_log(
										"peril_block:" .. tostring(action_input),
										_fixed_time(),
										"blocked "
											.. tostring(action_input)
											.. " (peril="
											.. string.format("%.0f%%", warp.current_percentage * 100)
											.. ", warp weapon)"
									)
									return nil
								end
							end
						end
					end

					-- DIAGNOSTIC (#43): log bot weapon actions (except wield) with
					-- bot/template tags so charged inputs can be attributed to the
					-- correct bot and staff family. One-shot per unique combo.
					-- Remove after validation.
					if id == "weapon_action" and action_input ~= "wield" and _debug_enabled() then
						local bot_slot, wielded_slot, weapon_template_name, warp_charge_template_name =
							_weapon_log_context(unit)
						local combo_key = tostring(bot_slot)
							.. ":"
							.. tostring(weapon_template_name)
							.. ":"
							.. tostring(action_input)
							.. ":"
							.. tostring(raw_input)
						if not _weapon_logged_combos[combo_key] then
							_weapon_logged_combos[combo_key] = true
							_debug_log(
								"bot_weapon:" .. combo_key,
								_fixed_time(),
								"bot weapon: bot="
									.. tostring(bot_slot)
									.. " slot="
									.. tostring(wielded_slot)
									.. " weapon_template="
									.. tostring(weapon_template_name)
									.. " warp_template="
									.. tostring(warp_charge_template_name)
									.. " action="
									.. tostring(action_input)
									.. " raw_input="
									.. tostring(raw_input)
							)
						end
					end

					return func(self, id, action_input, raw_input)
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
					if slot_to_wield ~= "slot_combat_ability" then
						local should_lock, ability_name, lock_reason = should_lock_weapon_switch(player_unit)
						if should_lock then
							local fixed_t = _fixed_time()
							_debug_log(
								"lock_wield_direct:" .. tostring(ability_name),
								fixed_t,
								"redirected wield_slot("
									.. tostring(slot_to_wield)
									.. ") -> slot_combat_ability while keeping "
									.. tostring(ability_name)
									.. " "
									.. tostring(lock_reason)
							)
							return func("slot_combat_ability", player_unit, t, skip_wield_action)
						end
					end

					return func(slot_to_wield, player_unit, t, skip_wield_action)
				end
			)
		end
	)

	-- Perils of the warp achievement guard: bot players can have nil account_id.
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
