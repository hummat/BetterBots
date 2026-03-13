local _mod -- luacheck: ignore 231

local function resolve_bot_target_unit(perception_component)
	if not perception_component then
		return nil
	end

	return perception_component.target_enemy
		or perception_component.priority_target_enemy
		or perception_component.opportunity_target_enemy
		or perception_component.urgent_target_enemy
end

local function register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/weapon/actions/modules/smart_target_targeting_action_module",
		function(SmartTargetingActionModule)
			_mod:hook(SmartTargetingActionModule, "fixed_update", function(func, self, dt, t)
				local unit_data_extension = self and self._unit_data_extension
				if unit_data_extension and unit_data_extension.is_resimulating then
					return
				end

				local smart_targeting_extension = self and self._smart_targeting_extension
				local player = smart_targeting_extension and smart_targeting_extension._player
				if not player or player:is_human_controlled() then
					return func(self, dt, t)
				end

				local perception_component = unit_data_extension and unit_data_extension:read_component("perception")
				local component = self._component

				component.target_unit_1 = resolve_bot_target_unit(perception_component)
				component.target_unit_2 = nil
				component.target_unit_3 = nil
			end)
		end
	)
end

return {
	init = function(deps)
		_mod = deps.mod
	end,
	register_hooks = register_hooks,
	resolve_bot_target_unit = resolve_bot_target_unit,
}
