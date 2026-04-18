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
-- Per-target cost: one breed lookup + one Unit.has_node guard on target
-- acquisition, not per frame.

local _mod -- luacheck: ignore 231
local _debug_log
local _debug_enabled
local _is_enabled

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_is_enabled = deps.is_enabled
end

-- Breed → override node map. Entries live here only when:
--  * MVP 50/50 head/spine meaningfully loses shots, AND
--  * a single safe fallback node is verifiable on the breed rig.
-- Breeds with angle-aware weakspots (Bulwark shield) or unverified back-of-
-- head nodes (Crusher) are deliberately omitted and stay on the #91 MVP.
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
	local override = breed_name and BREED_WEAKSPOT_OVERRIDE[breed_name] or nil
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
