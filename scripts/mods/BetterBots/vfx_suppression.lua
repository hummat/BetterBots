-- VFX/SFX bleed fix (#42): BotPlayer inherits from HumanPlayer, so
-- is_local_unit = true for all bots in Solo Play. Effect scripts and
-- CharacterStateMachineExtension gate first-person VFX/SFX on is_local_unit
-- but not is_human_controlled, causing screen particles, sound events, and
-- Wwise global state from bot abilities to bleed into the human player's view.
--
-- Fix: set is_local_unit = false on context tables (ability effect scripts,
-- wieldable slot scripts) and on _is_local_unit (state machine extension) for
-- bot units after init. This suppresses local-only effects (lunge screen
-- distortion, lunge sounds, shout aim indicator, targeted dash crosshair,
-- item placement previews) without touching gameplay state.
local _mod
local _debug_log
local _debug_enabled

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
end

function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/ability/player_unit_ability_extension",
		function(PlayerUnitAbilityExtension)
			_mod:hook_safe(PlayerUnitAbilityExtension, "init", function(self, _context, unit, extension_init_data)
				local player = extension_init_data.player
				if player and not player:is_human_controlled() then
					local ctx = self._equipped_ability_effect_scripts_context
					if ctx then
						ctx.is_local_unit = false
						if _debug_enabled() then
							_debug_log(
								"vfx_fix_ability:" .. tostring(unit),
								0,
								"patched ability effect context is_local_unit=false for bot"
							)
						end
					end
				end
			end)
		end
	)

	_mod:hook_require(
		"scripts/extension_systems/visual_loadout/player_unit_visual_loadout_extension",
		function(PlayerUnitVisualLoadoutExtension)
			_mod:hook_safe(PlayerUnitVisualLoadoutExtension, "init", function(self, _context, unit, extension_init_data)
				local player = extension_init_data.player
				if player and not player:is_human_controlled() then
					local ctx = self._wieldable_slot_scripts_context
					if ctx then
						ctx.is_local_unit = false
						if _debug_enabled() then
							_debug_log(
								"vfx_fix_loadout:" .. tostring(unit),
								0,
								"patched wieldable slot scripts context is_local_unit=false for bot"
							)
						end
					end
				end
			end)
		end
	)

	_mod:hook_require(
		"scripts/extension_systems/character_state_machine/character_state_machine_extension",
		function(CharacterStateMachineExtension)
			_mod:hook_safe(CharacterStateMachineExtension, "init", function(self, _context, unit, extension_init_data)
				local player = extension_init_data.player
				if player and not player:is_human_controlled() then
					self._is_local_unit = false
					if _debug_enabled() then
						_debug_log(
							"vfx_fix_csm:" .. tostring(unit),
							0,
							"patched CharacterStateMachine _is_local_unit=false for bot"
						)
					end
				end
			end)
		end
	)
end

return M
