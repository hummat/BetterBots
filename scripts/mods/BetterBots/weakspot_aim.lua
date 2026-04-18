-- weakspot_aim.lua — per-breed override for ranged aim node (#92).
--
-- Builds on the #91 MVP injection (`ranged_meta_data.lua` sets
-- attack_meta_data.aim_at_node = {"j_head", "j_spine"} for finesse weapons).
-- The shoot action randomly picks one per target acquisition. For breeds
-- where the head is the most armored hitbox (Scab Mauler) or carapace
-- redirects the weakspot elsewhere, this module post-processes
-- `BtBotShootAction._set_new_aim_target` to pin scratchpad.aim_at_node
-- to the correct node.
--
-- Per-target cost: one breed lookup, an extra shield/angle check only for
-- Bulwarks, and one Unit.has_node guard on target acquisition, not per frame.

local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _is_enabled

local M = {}

local BULWARK_BREED_NAME = "chaos_ogryn_bulwark"
local BULWARK_WEAKSPOT_NODE = "j_head"
local BULWARK_BLOCKING_ANGLE = math.rad(70)
local CRUSHER_BREED_NAME = "chaos_ogryn_executor"
local CRUSHER_PROVISIONAL_WEAKSPOT_NODE = "j_head"
local CRUSHER_REAR_ARC_MIN_ANGLE = math.pi / 2

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

local function target_forward_angle_to_bot(target_unit, scratchpad)
	local target_position = POSITION_LOOKUP and POSITION_LOOKUP[target_unit] or nil
	if
		not target_position
		or not scratchpad
		or not scratchpad.first_person_component
		or not scratchpad.first_person_component.position
		or not Unit
		or not Unit.local_rotation
		or not Quaternion
		or not Quaternion.forward
		or not Vector3
		or not Vector3.normalize
		or not Vector3.angle
	then
		return nil
	end

	local target_rotation = Unit.local_rotation(target_unit, 1)
	local target_forward = target_rotation and Quaternion.forward(target_rotation)
	if not target_forward then
		return nil
	end

	local to_bot = scratchpad.first_person_component.position - target_position
	local to_bot_normalized = Vector3.normalize(to_bot)

	return Vector3.angle(target_forward, to_bot_normalized)
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

	local shield_extension = ScriptUnit.has_extension(target_unit, "shield_system")
	if not shield_extension or not shield_extension.is_blocking then
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
	if not target_unit then
		return nil
	end
	local data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
	if not data_ext then
		return nil
	end
	local breed = data_ext:breed()
	return breed and breed.name or nil
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

function M.apply_override(target_unit, scratchpad)
	if not scratchpad then
		return nil
	end
	capture_baseline_once(scratchpad)
	if _is_enabled and not _is_enabled() then
		restore_baseline(scratchpad)
		return nil
	end
	local breed_name = resolve_breed_name(target_unit)
	local override = resolve_override(target_unit, scratchpad, breed_name)
	if override and Unit and Unit.has_node and not Unit.has_node(target_unit, override) then
		override = nil
	end

	if not override then
		restore_baseline(scratchpad)
		return nil
	end

	scratchpad.aim_at_node = override
	scratchpad.aim_at_node_charged = override
	if _debug_enabled and _debug_enabled() and _debug_log then
		_debug_log(
			"weakspot_aim:" .. tostring(target_unit),
			0,
			"weakspot override applied (breed=" .. breed_name .. ", node=" .. override .. ")"
		)
	end
	return override
end

local SENTINEL = "__bb_weakspot_aim_installed"

-- Called from `weapon_action.lua`'s existing `bt_bot_shoot_action` hook_require
-- callback. `BetterBots.lua` wraps `mod:hook_require` with a duplicate-path
-- guard, so this module deliberately does not own its own hook_require
-- registration — weapon_action hands us the class.
function M.install_on_shoot_action(BtBotShootAction)
	if not _mod or not BtBotShootAction then
		return
	end
	if rawget(BtBotShootAction, SENTINEL) then
		return
	end
	BtBotShootAction[SENTINEL] = true

	_mod:hook_safe(BtBotShootAction, "_set_new_aim_target", function(_self, _t, target_unit, scratchpad, _action_data)
		M.apply_override(target_unit, scratchpad)
	end)
end

return M
