-- smart_targeting.lua — seed bot precision targeting from bot perception.
-- Keeps vanilla sticky/range validation by swapping the candidate unit only
-- for the duration of SmartTargetingActionModule.fixed_update().
local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _fixed_time
local _last_logged_target_by_component = setmetatable({}, { __mode = "k" })
local _resolve_bot_target_unit_fn

local function resolve_bot_target_unit(perception_component)
	if _resolve_bot_target_unit_fn then
		return _resolve_bot_target_unit_fn(perception_component)
	end

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
					return func(self, dt, t)
				end

				local smart_targeting_extension = self and self._smart_targeting_extension
				local player = smart_targeting_extension and smart_targeting_extension._player
				if not player or player:is_human_controlled() then
					return func(self, dt, t)
				end

				local perception_component = unit_data_extension and unit_data_extension:read_component("perception")
				local bot_target_unit = resolve_bot_target_unit(perception_component)
				local targeting_data = smart_targeting_extension and smart_targeting_extension:targeting_data()
				if not (bot_target_unit and targeting_data) then
					return func(self, dt, t)
				end

				local original_target_unit = targeting_data.unit
				if _debug_enabled() and _last_logged_target_by_component[self._component] ~= bot_target_unit then
					_last_logged_target_by_component[self._component] = bot_target_unit
					_debug_log(
						"smart_targeting:" .. tostring(bot_target_unit),
						_fixed_time(),
						"smart targeting using bot perception target "
							.. tostring(bot_target_unit)
							.. " (already_seeded="
							.. tostring(original_target_unit == bot_target_unit)
							.. ")",
						nil,
						"info"
					)
				end

				if original_target_unit == bot_target_unit then
					return func(self, dt, t)
				end

				targeting_data.unit = bot_target_unit

				local ok, err = pcall(func, self, dt, t)
				targeting_data.unit = original_target_unit
				if not ok then
					error(err)
				end
			end)
		end
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
		local bot_targeting = deps.bot_targeting
		_resolve_bot_target_unit_fn = bot_targeting and bot_targeting.resolve_bot_target_unit or nil
	end,
	register_hooks = register_hooks,
	resolve_bot_target_unit = resolve_bot_target_unit,
}
