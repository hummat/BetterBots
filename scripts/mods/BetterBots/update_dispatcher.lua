local M = {}

local _perf
local _event_log
local _debug
local _ability_queue
local _grenade_fallback
local _pocketable_pickup
local _ping_system
local _companion_tag
local _settings
local _build_context
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _last_snapshot_t_by_unit
local _session_start_state
local _snapshot_interval_s
local _meta_patch_version
local _fixed_time

function M.init(deps)
	_perf = deps.perf
	_event_log = deps.event_log
	_debug = deps.debug
	_ability_queue = deps.ability_queue
	_grenade_fallback = deps.grenade_fallback
	_pocketable_pickup = deps.pocketable_pickup
	_ping_system = deps.ping_system
	_companion_tag = deps.companion_tag
	_settings = deps.settings
	_build_context = deps.build_context
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_last_snapshot_t_by_unit = deps.last_snapshot_t_by_unit
	_session_start_state = deps.session_start_state
	_snapshot_interval_s = deps.snapshot_interval_s
	_meta_patch_version = deps.meta_patch_version
	_fixed_time = deps.fixed_time
end

function M.dispatch(self, unit)
	local player = self._player
	if not player or player:is_human_controlled() then
		return
	end

	_perf.sync_setting()
	_perf.mark_bot_frame()

	local brain = self._brain
	local blackboard = brain and brain._blackboard or nil

	if _event_log.is_enabled() and not _session_start_state.emitted then
		local perf_t0 = _perf.begin()
		local bots = _debug.collect_alive_bots()
		if bots and #bots > 0 then
			_session_start_state.emitted = true
			local bot_info = {}
			for i, bot_entry in ipairs(bots) do
				local p = bot_entry.player
				bot_info[i] = {
					slot = type(p.slot) == "function" and p:slot() or nil,
					archetype = type(p.archetype_name) == "function" and p:archetype_name() or nil,
					ability = _equipped_combat_ability_name(bot_entry.unit),
				}
			end
			_event_log.emit({
				t = _fixed_time(),
				event = "session_start",
				version = _meta_patch_version,
				bots = bot_info,
			})
		end
		_perf.finish("event_log_session_start", perf_t0)
	end

	local perf_t0 = _perf.begin()
	_ability_queue.try_queue(unit, blackboard)
	_perf.finish("ability_queue", perf_t0)
	perf_t0 = _perf.begin()
	_grenade_fallback.try_queue(unit, blackboard)
	_perf.finish("grenade_fallback", perf_t0)
	perf_t0 = _perf.begin()
	if _pocketable_pickup and _pocketable_pickup.try_queue then
		_pocketable_pickup.try_queue(unit, blackboard)
	end
	_perf.finish("pocketable_pickup", perf_t0)
	if _settings.is_feature_enabled("pinging") then
		perf_t0 = _perf.begin()
		_ping_system.update(unit, blackboard)
		_perf.finish("ping_system", perf_t0)
		perf_t0 = _perf.begin()
		_companion_tag.update(unit, blackboard)
		_perf.finish("companion_tag", perf_t0)
	end
	perf_t0 = _perf.begin()
	_event_log.try_flush(_fixed_time())
	_perf.finish("event_log_flush", perf_t0)

	if _event_log.is_enabled() then
		local fixed_t = _fixed_time()
		local last_snap = _last_snapshot_t_by_unit[unit]
		if not last_snap or fixed_t - last_snap >= _snapshot_interval_s then
			local snapshot_t0 = _perf.begin()
			_last_snapshot_t_by_unit[unit] = fixed_t
			local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
			local bot_slot = _debug.bot_slot_for_unit(unit)
			local fb_state = _fallback_state_by_unit[unit]
			_event_log.emit({
				t = fixed_t,
				event = "snapshot",
				bot = bot_slot,
				ability = _equipped_combat_ability_name(unit),
				cooldown_ready = ability_extension and ability_extension:can_use_ability("combat_ability") or false,
				charges = ability_extension and ability_extension:remaining_ability_charges("combat_ability") or nil,
				ctx = _debug.context_snapshot(_build_context(unit, blackboard)),
				item_stage = fb_state and fb_state.item_stage or nil,
			})
			_perf.finish("event_log_snapshot", snapshot_t0)
		end
	end
end

return M
