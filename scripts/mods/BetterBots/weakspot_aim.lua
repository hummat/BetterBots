-- weakspot_aim.lua — per-breed override for ranged aim nodes on armored elites.
--
-- Vanilla ranged weapon metadata can expose multiple aim nodes, and the shoot
-- action picks one per target acquisition. For breeds where one of those nodes
-- is a trap (for example Mauler helmet shots glancing off armor), this module
-- post-processes the chosen node and pins the scratchpad to the safer weakspot.
--
-- Per-target cost: one breed lookup on acquisition for static breeds, plus a
-- live re-check for the two stateful breeds (Bulwark/Crusher) while the target
-- stays locked so shield/facing changes do not go stale mid-burst.

local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _is_enabled

local M = {}

local BULWARK_BREED_NAME = "chaos_ogryn_bulwark"
local BULWARK_WEAKSPOT_NODE = "j_head"
local BULWARK_BLOCKING_ANGLE = math.rad(70)
local BLOCK_ANGLE_DISTANCE_SQUARED_EPSILON = 0.01
local CRUSHER_BREED_NAME = "chaos_ogryn_executor"
local CRUSHER_PROVISIONAL_WEAKSPOT_NODE = "j_head"
local CRUSHER_REAR_ARC_MIN_ANGLE = math.pi / 2
local _missing_override_node_logged_by_breed = {}
local _missing_shield_api_logged_by_unit = setmetatable({}, { __mode = "k" })

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_enabled = deps.is_enabled
end

-- Static breed → override node map. Entries live here only when:
--  * MVP 50/50 head/spine meaningfully loses shots, AND
--  * a single safe fallback node is verifiable on the breed rig.
-- Angle-aware weakspots (Bulwark shield exposure) are handled separately.
-- Crusher's claimed back-of-head weakspot is still unverified at the rig-node
-- level, so the code below only uses a documented provisional rear-arc proxy.
local BREED_WEAKSPOT_OVERRIDE = {
	-- Scab Mauler: helmet is super_armor, torso is armored. Head shots glance
	-- off; spine is the reliable finesse node.
	renegade_executor = "j_spine",
}

M._BREED_WEAKSPOT_OVERRIDE = BREED_WEAKSPOT_OVERRIDE

function M._breed_override_for(breed_name)
	if not breed_name then
		return nil
	end
	return BREED_WEAKSPOT_OVERRIDE[breed_name]
end

local function requires_live_refresh(breed_name)
	return breed_name == BULWARK_BREED_NAME or breed_name == CRUSHER_BREED_NAME
end

local function flat_normalized_xy(x, y)
	if not Vector3 or not Vector3.normalize then
		return nil
	end

	local distance_squared = x * x + y * y
	if distance_squared < BLOCK_ANGLE_DISTANCE_SQUARED_EPSILON then
		return nil
	end

	return Vector3.normalize({
		x = x,
		y = y,
		z = 0,
	})
end

local function target_forward_angle_to_bot(target_unit, scratchpad)
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[target_unit] or nil
	if
		not target_position
		or not scratchpad
		or not scratchpad.first_person_component
		or not scratchpad.first_person_component.position
		or not Unit
		or not Quaternion
		or not Quaternion.forward
		or not Vector3
		or not Vector3.angle
	then
		return nil
	end

	local target_rotation = nil
	if Unit.local_rotation then
		target_rotation = Unit.local_rotation(target_unit, 1)
	elseif Unit.world_rotation then
		target_rotation = Unit.world_rotation(target_unit, 1)
	end
	local target_forward = target_rotation and Quaternion.forward(target_rotation)
	if not target_forward then
		return nil
	end

	local target_forward_flat_normalized = flat_normalized_xy(target_forward.x or 0, target_forward.y or 0)
	if not target_forward_flat_normalized then
		return nil
	end

	local bot_position = scratchpad.first_person_component.position
	local to_bot_flat_normalized = flat_normalized_xy(
		(bot_position.x or 0) - (target_position.x or 0),
		(bot_position.y or 0) - (target_position.y or 0)
	)

	if not to_bot_flat_normalized then
		return nil
	end

	return Vector3.angle(target_forward_flat_normalized, to_bot_flat_normalized)
end

M._target_forward_angle_to_bot = target_forward_angle_to_bot

local function log_missing_shield_api_once(target_unit)
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
		return
	end
	if _missing_shield_api_logged_by_unit[target_unit] then
		return
	end

	_missing_shield_api_logged_by_unit[target_unit] = true
	_debug_log(
		"weakspot_aim:shield_api_missing:" .. tostring(target_unit),
		0,
		"weakspot shield API missing; leaving Bulwark on vanilla aim"
	)
end

local function log_missing_override_node_once(breed_name, override)
	if not breed_name or not override then
		return
	end
	if not (_debug_log and _debug_enabled and _debug_enabled()) then
		return
	end

	local key = tostring(breed_name) .. ":" .. tostring(override)
	if _missing_override_node_logged_by_breed[key] then
		return
	end

	_missing_override_node_logged_by_breed[key] = true
	_debug_log(
		"weakspot_aim:missing_node:" .. key,
		0,
		"weakspot override node missing; leaving vanilla aim (breed="
			.. tostring(breed_name)
			.. ", node="
			.. tostring(override)
			.. ")"
	)
end

local function resolve_bulwark_override(target_unit, scratchpad)
	if
		not target_unit
		or not scratchpad
		or not scratchpad.first_person_component
		or not scratchpad.first_person_component.position
	then
		return nil
	end

	if not ScriptUnit or not ScriptUnit.has_extension then
		return nil
	end

	local shield_extension = ScriptUnit.has_extension(target_unit, "shield_system")
	if not shield_extension then
		return nil
	end
	if not shield_extension.is_blocking then
		log_missing_shield_api_once(target_unit)
		return nil
	end
	if not shield_extension:is_blocking() then
		return BULWARK_WEAKSPOT_NODE
	end

	local angle = target_forward_angle_to_bot(target_unit, scratchpad)

	if angle and angle >= BULWARK_BLOCKING_ANGLE then
		return BULWARK_WEAKSPOT_NODE
	end

	return nil
end

local function resolve_crusher_override(target_unit, scratchpad)
	local angle = target_forward_angle_to_bot(target_unit, scratchpad)

	-- Provisional proxy: the issue claims Crusher's weakspot is the back of the
	-- head, but the decompiled rig does not expose a verified back-head node. We
	-- therefore only route to `j_head` from the rear arc, where head aim is at
	-- least directionally consistent with that claim.
	if angle and angle >= CRUSHER_REAR_ARC_MIN_ANGLE then
		return CRUSHER_PROVISIONAL_WEAKSPOT_NODE
	end

	return nil
end

local function resolve_override(target_unit, scratchpad, breed_name)
	if breed_name == BULWARK_BREED_NAME then
		return resolve_bulwark_override(target_unit, scratchpad)
	end
	if breed_name == CRUSHER_BREED_NAME then
		return resolve_crusher_override(target_unit, scratchpad)
	end

	return breed_name and BREED_WEAKSPOT_OVERRIDE[breed_name] or nil
end

-- `BtBotShootAction.enter` picks one node from the weapon's `aim_at_node`
-- list (random when the field is a table) and caches it on the scratchpad,
-- then calls `_set_new_aim_target` before returning. Our hook_safe post-hook
-- on `_set_new_aim_target` fires BEFORE `enter` returns, so any `enter`
-- post-hook would see a scratchpad that has already been overridden if the
-- first target is a Mauler. Capture the baseline lazily on the first
-- `apply_override` call — before any mutation — so retargets to non-override
-- breeds restore the vanilla random pick, not the overridden `j_spine`.
local function capture_baseline_once(scratchpad)
	if scratchpad.__bb_weakspot_baseline_captured then
		return
	end
	scratchpad.__bb_weakspot_baseline_captured = true
	scratchpad.__bb_weakspot_baseline_aim_at_node = scratchpad.aim_at_node
	scratchpad.__bb_weakspot_baseline_aim_at_node_charged = scratchpad.aim_at_node_charged
end

local function resolve_breed_name(target_unit)
	if not target_unit or not ScriptUnit or not ScriptUnit.has_extension then
		return nil
	end
	local data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if not data_ext then
		return nil
	end
	local breed = data_ext:breed()
	return breed and breed.name or nil
end

local function current_breed_name(target_unit, scratchpad)
	local target_breed = scratchpad and scratchpad.target_breed
	if target_breed and target_breed.name then
		return target_breed.name
	end

	return resolve_breed_name(target_unit)
end

local function restore_baseline(scratchpad)
	local baseline = scratchpad.__bb_weakspot_baseline_aim_at_node
	if baseline == nil then
		return
	end
	if scratchpad.aim_at_node ~= baseline then
		scratchpad.aim_at_node = baseline
	end
	local baseline_charged = scratchpad.__bb_weakspot_baseline_aim_at_node_charged or baseline
	if scratchpad.aim_at_node_charged ~= baseline_charged then
		scratchpad.aim_at_node_charged = baseline_charged
	end
end

function M.apply_override(target_unit, scratchpad, self_unit)
	if not scratchpad then
		return nil
	end
	capture_baseline_once(scratchpad)
	if _is_enabled and not _is_enabled() then
		restore_baseline(scratchpad)
		return nil
	end
	local breed_name = current_breed_name(target_unit, scratchpad)
	local override = resolve_override(target_unit, scratchpad, breed_name)
	if override and Unit and Unit.has_node and not Unit.has_node(target_unit, override) then
		log_missing_override_node_once(breed_name, override)
		override = nil
	end

	if not override then
		restore_baseline(scratchpad)
		return nil
	end

	scratchpad.aim_at_node = override
	scratchpad.aim_at_node_charged = override
	if _debug_enabled and _debug_enabled() and _debug_log then
		local shooter_unit = self_unit or scratchpad.__bb_weakspot_self_unit
		_debug_log(
			"weakspot_aim:" .. tostring(target_unit) .. ":" .. tostring(shooter_unit),
			0,
			"weakspot override applied (breed=" .. breed_name .. ", node=" .. override .. ")"
		)
	end
	return override
end

function M.refresh_live_override(target_unit, scratchpad, self_unit)
	if not scratchpad then
		return nil
	end

	local breed_name = current_breed_name(target_unit, scratchpad)
	if not requires_live_refresh(breed_name) then
		return nil
	end

	return M.apply_override(target_unit, scratchpad, self_unit)
end

local SENTINEL = "__bb_weakspot_aim_installed"

-- This module only patches the class it is handed. It deliberately does not
-- own any `hook_require` registration because the mod bootstrap consolidates
-- shared hook targets and rejects duplicate path ownership.
function M.install_on_shoot_action(BtBotShootAction)
	if not _mod or not BtBotShootAction then
		return
	end
	if rawget(BtBotShootAction, SENTINEL) then
		return
	end
	BtBotShootAction[SENTINEL] = true

	_mod:hook_safe(BtBotShootAction, "_set_new_aim_target", function(_self, _t, target_unit, scratchpad, _action_data)
		M.apply_override(target_unit, scratchpad, scratchpad and scratchpad.__bb_weakspot_self_unit or nil)
	end)
	_mod:hook(
		BtBotShootAction,
		"_aim_position",
		function(func, self, self_unit, scratchpad, action_data, dt, current_position, current_rotation, target_unit)
			M.refresh_live_override(target_unit, scratchpad, self_unit)

			return func(self, self_unit, scratchpad, action_data, dt, current_position, current_rotation, target_unit)
		end
	)
end

return M
