# Ammo Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace BetterBots' hardcoded ranged ammo threshold with a configurable ammo policy where one numeric slider controls opportunistic fire and pickup onset together, and a second numeric slider blocks bot ammo pickup until eligible humans are above a configured reserve.

**Architecture:** Keep BT ammo gating in `condition_patch.lua`, but move ammo pickup policy into a new `ammo_policy.lua` module that post-processes vanilla `BotBehaviorExtension._update_ammo()`. Centralize slider parsing in `settings.lua` so both modules consume normalized percentages rather than raw UI values.

**Tech Stack:** Lua, DMF mod settings (`type = "numeric"` with `range`/`step_size`), busted, luacheck, stylua, lua-language-server

---

## File Map

**Create**
- `scripts/mods/BetterBots/ammo_policy.lua` — ammo pickup policy hook, slider-backed threshold parsing via `settings.lua`, eligible-human filtering, debug logging, perf timing
- `tests/ammo_policy_spec.lua` — focused unit coverage for ammo pickup onset, human reserve guard, explicit pickup orders, and stale-state clearing

**Modify**
- `scripts/mods/BetterBots/BetterBots.lua` — load/init the new module and install its `BotBehaviorExtension` hook from the consolidated hook site
- `scripts/mods/BetterBots/BetterBots_data.lua` — add two numeric slider controls under Bot Behavior
- `scripts/mods/BetterBots/BetterBots_localization.lua` — add labels/descriptions for the new settings
- `scripts/mods/BetterBots/settings.lua` — add typed accessors for both ammo-policy sliders
- `scripts/mods/BetterBots/condition_patch.lua` — replace the hardcoded `0.2` ranged threshold with a slider-backed accessor
- `tests/settings_spec.lua` — add coverage for ammo slider defaults, parsing, invalid values, and normalization
- `tests/condition_patch_spec.lua` — update threshold override tests to use the new settings accessor and verify priority-target path remains untouched
- `docs/dev/architecture.md` — document `ammo_policy.lua` and the new ammo-sharing rules
- `docs/dev/status.md` — mark `#72` implemented on `dev/v0.9.1` after code lands
- `docs/dev/roadmap.md` — update `#72` notes from dead-band-only fix to configurable ammo policy
- `docs/dev/known-issues.md` — remove or restate the old `10-20%` dead-band issue
- `docs/nexus-description.bbcode` — document the user-facing ammo policy sliders

## Reference Notes

- DMF slider-style settings in installed mods are represented as `type = "numeric"` with `range = { min, max }` and `step_size = N`. See:
  - `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/mods/markers_aio/scripts/mods/markers_aio/markers_aio_data.lua`
  - `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/mods/CollectibleFinder/scripts/mods/CollectibleFinder/CollectibleFinder_data.lua`
- Vanilla ammo update source:
  - `../Darktide-Source-Code/scripts/extension_systems/behavior/bot_behavior_extension.lua`
- Vanilla ammo utility source:
  - `../Darktide-Source-Code/scripts/utilities/ammo.lua`
- Existing post-process module pattern:
  - `scripts/mods/BetterBots/healing_deferral.lua`

### Task 1: Add Slider Settings And Typed Accessors

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
- Modify: `scripts/mods/BetterBots/settings.lua`
- Test: `tests/settings_spec.lua`

- [ ] **Step 1: Write the failing settings tests**

Add these cases to `tests/settings_spec.lua` under a new `describe("ammo policy settings", ...)` block:

```lua
	describe("ammo policy settings", function()
		it("returns default ammo thresholds when mod returns nil", function()
			Settings.init(mock_mod({}))

			assert.are.equal(0.20, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.80, Settings.human_ammo_reserve_threshold())
		end)

		it("normalizes numeric slider values into percentages", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = 25,
				bot_human_ammo_reserve_threshold = 85,
			}))

			assert.are.equal(0.25, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.85, Settings.human_ammo_reserve_threshold())
		end)

		it("accepts stringified slider values from DMF", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = "15",
				bot_human_ammo_reserve_threshold = "95",
			}))

			assert.are.equal(0.15, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.95, Settings.human_ammo_reserve_threshold())
		end)

		it("falls back to defaults for invalid ammo slider values", function()
			Settings.init(mock_mod({
				bot_ranged_ammo_threshold = "bad",
				bot_human_ammo_reserve_threshold = -1,
			}))

			assert.are.equal(0.20, Settings.bot_ranged_ammo_threshold())
			assert.are.equal(0.80, Settings.human_ammo_reserve_threshold())
		end)
	end)
```

- [ ] **Step 2: Run the focused settings tests to verify they fail**

Run:

```bash
busted tests/settings_spec.lua
```

Expected: FAIL with missing `Settings.bot_ranged_ammo_threshold` / `Settings.human_ammo_reserve_threshold` functions or wrong default values.

- [ ] **Step 3: Add the UI settings in `BetterBots_data.lua`**

Insert these widgets under the Bot Behavior group after `enable_engagement_leash` and before `healing_deferral_mode`:

```lua
					{
						setting_id = "bot_ranged_ammo_threshold",
						type = "numeric",
						default_value = 20,
						range = { 5, 30 },
						step_size = 5,
					},
					{
						setting_id = "bot_human_ammo_reserve_threshold",
						type = "numeric",
						default_value = 80,
						range = { 50, 100 },
						step_size = 5,
					},
```

- [ ] **Step 4: Add localization strings**

Add these entries to `scripts/mods/BetterBots/BetterBots_localization.lua` near the Bot Behavior settings:

```lua
	bot_ranged_ammo_threshold = {
		en = "Bot ranged ammo threshold",
	},
	bot_ranged_ammo_threshold_description = {
		en = "Bots stop opportunistic ranged fire below this reserve and start looking for ammo at or below it. Priority-target shots are unchanged.",
	},
	bot_human_ammo_reserve_threshold = {
		en = "Human ammo reserve threshold",
	},
	bot_human_ammo_reserve_threshold_description = {
		en = "Bots only claim ammo when every eligible human ammo user is above this reserve.",
	},
```

- [ ] **Step 5: Implement typed accessors in `settings.lua`**

Add constants and helpers near the top of `scripts/mods/BetterBots/settings.lua`:

```lua
local DEFAULT_BOT_RANGED_AMMO_THRESHOLD = 0.20
local DEFAULT_HUMAN_AMMO_RESERVE_THRESHOLD = 0.80
local BOT_RANGED_AMMO_THRESHOLD_SETTING_ID = "bot_ranged_ammo_threshold"
local HUMAN_AMMO_RESERVE_THRESHOLD_SETTING_ID = "bot_human_ammo_reserve_threshold"

local function _read_percent_setting(setting_id, default_value, min_value, max_value)
	if not _mod then
		return default_value
	end

	local raw_value = _mod:get(setting_id)
	local numeric_value = tonumber(raw_value)
	if not numeric_value then
		return default_value
	end

	if numeric_value < min_value or numeric_value > max_value then
		return default_value
	end

	return numeric_value / 100
end
```

Then add these public functions:

```lua
function M.bot_ranged_ammo_threshold()
	return _read_percent_setting(BOT_RANGED_AMMO_THRESHOLD_SETTING_ID, DEFAULT_BOT_RANGED_AMMO_THRESHOLD, 5, 30)
end

function M.human_ammo_reserve_threshold()
	return _read_percent_setting(
		HUMAN_AMMO_RESERVE_THRESHOLD_SETTING_ID,
		DEFAULT_HUMAN_AMMO_RESERVE_THRESHOLD,
		50,
		100
	)
end
```

- [ ] **Step 6: Run the focused settings tests to verify they pass**

Run:

```bash
busted tests/settings_spec.lua
```

Expected: PASS

- [ ] **Step 7: Commit the settings slice**

```bash
git add scripts/mods/BetterBots/BetterBots_data.lua scripts/mods/BetterBots/BetterBots_localization.lua scripts/mods/BetterBots/settings.lua tests/settings_spec.lua
git commit -m "feat(settings): add ammo policy thresholds"
```

### Task 2: Make Opportunistic Ranged Fire Threshold Configurable

**Files:**
- Modify: `scripts/mods/BetterBots/condition_patch.lua`
- Test: `tests/condition_patch_spec.lua`

- [ ] **Step 1: Write the failing condition-patch tests**

Extend `tests/condition_patch_spec.lua` with settings-backed threshold coverage:

```lua
		it("uses the configured ammo threshold for opportunistic ranged fire", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local seen_ammo_percentage
			local conditions = {
				has_target_and_ammo_greater_than = function(_unit, _bb, _scratchpad, condition_args)
					seen_ammo_percentage = condition_args.ammo_percentage
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch.wire({
				Heuristics = { resolve_decision = function() return false end },
				MetaData = { inject = function() end },
				Debug = { log_ability_decision = function() end, bot_slot_for_unit = function() return 1 end },
				EventLog = { is_enabled = function() return false end },
				bot_ranged_ammo_threshold = function()
					return 0.25
				end,
			})
			ConditionPatch._install_condition_patch(conditions, {}, "test")

			assert.is_true(conditions.has_target_and_ammo_greater_than("bot1", bb, {}, { ammo_percentage = 0.5 }, {}, false))
			assert.are.equal(0.25, seen_ammo_percentage)
		end)

		it("leaves the priority-target 0 percent gate untouched", function()
			local target = "gunner1"
			setup_breed(target, "renegade_gunner")

			local bb = make_blackboard(target)
			bb.perception.target_enemy_type = "ranged"
			local seen_ammo_percentage
			local conditions = {
				has_target_and_ammo_greater_than = function(_unit, _bb, _scratchpad, condition_args)
					seen_ammo_percentage = condition_args.ammo_percentage
					return true
				end,
				can_activate_ability = function()
					return false
				end,
			}

			ConditionPatch._install_condition_patch(conditions, {}, "test")

			assert.is_true(conditions.has_target_and_ammo_greater_than("bot1", bb, {}, { ammo_percentage = 0 }, {}, false))
			assert.are.equal(0, seen_ammo_percentage)
		end)
```

- [ ] **Step 2: Run the focused condition-patch tests to verify they fail**

Run:

```bash
busted tests/condition_patch_spec.lua
```

Expected: FAIL because the override still hardcodes `0.2` and `ConditionPatch.wire(...)` does not yet accept a settings accessor.

- [ ] **Step 3: Thread the settings accessor through `condition_patch.lua`**

Make these changes in `scripts/mods/BetterBots/condition_patch.lua`:

1. Replace the hardcoded constant:

```lua
-local BETTERBOTS_RANGED_AMMO_THRESHOLD = 0.2
+local _bot_ranged_ammo_threshold
```

2. Update `_override_ranged_ammo_condition_args`:

```lua
local function _override_ranged_ammo_condition_args(condition_args)
	if not condition_args or condition_args.ammo_percentage ~= NORMAL_RANGED_AMMO_THRESHOLD then
		return condition_args
	end

	local threshold = _bot_ranged_ammo_threshold and _bot_ranged_ammo_threshold() or 0.20
	local adjusted_args = {}
	for key, value in pairs(condition_args) do
		adjusted_args[key] = value
	end
	adjusted_args.ammo_percentage = threshold

	if _debug_enabled() then
		_debug_log(
			"ranged_ammo_threshold_override",
			_fixed_time(),
			"ranged ammo gate lowered from "
				.. tostring(NORMAL_RANGED_AMMO_THRESHOLD)
				.. " to "
				.. tostring(threshold),
			10
		)
	end

	return adjusted_args
end
```

3. Accept the accessor in `M.wire(...)`:

```lua
function M.wire(deps)
	Heuristics = deps.Heuristics
	MetaData = deps.MetaData
	Debug = deps.Debug
	EventLog = deps.EventLog
	_bot_ranged_ammo_threshold = deps.bot_ranged_ammo_threshold
end
```

- [ ] **Step 4: Pass the accessor from `BetterBots.lua`**

Update the `ConditionPatch.wire({...})` call in `scripts/mods/BetterBots/BetterBots.lua`:

```lua
ConditionPatch.wire({
	Heuristics = Heuristics,
	MetaData = MetaData,
	Debug = Debug,
	EventLog = EventLog,
	bot_ranged_ammo_threshold = Settings.bot_ranged_ammo_threshold,
})
```

- [ ] **Step 5: Run the focused condition-patch tests to verify they pass**

Run:

```bash
busted tests/condition_patch_spec.lua
```

Expected: PASS

- [ ] **Step 6: Commit the BT-threshold slice**

```bash
git add scripts/mods/BetterBots/condition_patch.lua scripts/mods/BetterBots/BetterBots.lua tests/condition_patch_spec.lua
git commit -m "fix(condition-patch): make ranged ammo threshold configurable"
```

### Task 3: Implement Ammo Pickup Policy In A Dedicated Module

**Files:**
- Create: `scripts/mods/BetterBots/ammo_policy.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Test: `tests/ammo_policy_spec.lua`

- [ ] **Step 1: Write the failing ammo-policy tests**

Create `tests/ammo_policy_spec.lua` with this starting coverage:

```lua
local AmmoPolicy = dofile("scripts/mods/BetterBots/ammo_policy.lua")

describe("ammo_policy", function()
	local update_hook
	local debug_logs

	before_each(function()
		update_hook = nil
		debug_logs = {}
	end)

	local function install_module(overrides)
		AmmoPolicy.init({
			mod = {
				hook_safe = function(_, _, _, fn)
					update_hook = fn
				end,
			},
			debug_log = function(key, fixed_t, message)
				debug_logs[#debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
			end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 100
			end,
			perf = nil,
			ammo_module = overrides and overrides.ammo_module,
			settings = overrides and overrides.settings,
		})
	end

	it("registers a BotBehaviorExtension _update_ammo hook", function()
		install_module({
			ammo_module = { current_total_percentage = function() return 0.2 end, uses_ammo = function() return true end },
			settings = { bot_ranged_ammo_threshold = function() return 0.20 end, human_ammo_reserve_threshold = function() return 0.80 end },
		})

		AmmoPolicy.install_behavior_ext_hooks({})

		assert.is_function(update_hook)
	end)

	it("sets needs_ammo when bot is at threshold and all eligible humans are above reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.20 or 0.90
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = { ammo_pickup_order_unit = function() return nil end },
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("clears needs_ammo when an eligible human is below reserve", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.20 or 0.75
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = { ammo_pickup_order_unit = function() return nil end },
			_pickup_component = { needs_ammo = true },
		}

		update_hook(self, "bot1")

		assert.is_false(self._pickup_component.needs_ammo)
	end)

	it("ignores humans whose loadouts do not use ammo", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.15 or 0.10
				end,
				uses_ammo = function(unit)
					return unit == "bot1"
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human_staff" } },
			_bot_group = { ammo_pickup_order_unit = function() return nil end },
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)

	it("preserves explicit ammo pickup orders", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.50 or 0.10
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = { ammo_pickup_order_unit = function() return "pickup_unit" end },
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)
end)
```

- [ ] **Step 2: Run the focused ammo-policy tests to verify they fail**

Run:

```bash
busted tests/ammo_policy_spec.lua
```

Expected: FAIL because `ammo_policy.lua` does not exist yet.

- [ ] **Step 3: Create `ammo_policy.lua` with the minimal implementation**

Create `scripts/mods/BetterBots/ammo_policy.lua` with this structure:

```lua
local M = {}

local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _perf
local _Ammo
local _Settings

local function _log(key, message)
	if not (_debug_enabled and _debug_enabled()) then
		return
	end

	_debug_log(key, _fixed_time and _fixed_time() or 0, message)
end

local function _bot_threshold()
	return (_Settings and _Settings.bot_ranged_ammo_threshold and _Settings.bot_ranged_ammo_threshold()) or 0.20
end

local function _human_threshold()
	return (_Settings and _Settings.human_ammo_reserve_threshold and _Settings.human_ammo_reserve_threshold()) or 0.80
end

local function _all_eligible_humans_above_threshold(human_units, threshold)
	if not (human_units and _Ammo) then
		return true
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		if human_unit and _Ammo.uses_ammo(human_unit) then
			local ammo_percentage = _Ammo.current_total_percentage(human_unit)
			if ammo_percentage <= threshold then
				return false
			end
		end
	end

	return true
end

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_perf = deps.perf
	_Ammo = deps.ammo_module or require("scripts/utilities/ammo")
	_Settings = deps.settings
end

function M.install_behavior_ext_hooks(BotBehaviorExtension)
	_mod:hook_safe(BotBehaviorExtension, "_update_ammo", function(self, unit)
		local perf_t0 = _perf and _perf.begin()
		local pickup_component = self._pickup_component
		if not pickup_component then
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local bot_group = self._bot_group
		if bot_group and bot_group:ammo_pickup_order_unit(unit) ~= nil then
			pickup_component.needs_ammo = true
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local bot_ammo_percentage = _Ammo.current_total_percentage(unit)
		local bot_threshold = _bot_threshold()
		if bot_ammo_percentage > bot_threshold then
			pickup_component.needs_ammo = false
			if perf_t0 then
				_perf.finish("ammo_policy.update_ammo", perf_t0)
			end
			return
		end

		local humans_ok = _all_eligible_humans_above_threshold(
			self._side and self._side.valid_human_units,
			_human_threshold()
		)

		pickup_component.needs_ammo = humans_ok

		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
	end)
end

M.all_eligible_humans_above_threshold = _all_eligible_humans_above_threshold

return M
```

- [ ] **Step 4: Load, init, and install the new module from `BetterBots.lua`**

Add the module alongside `HealingDeferral`:

```lua
local AmmoPolicy = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ammo_policy")
assert(AmmoPolicy, "BetterBots: failed to load ammo_policy module")
```

Add the init block near `HealingDeferral.init({...})`:

```lua
AmmoPolicy.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	perf = Perf,
	settings = Settings,
})
```

Add the hook install in the consolidated `BotBehaviorExtension` hook site:

```lua
AmmoPolicy.install_behavior_ext_hooks(BotBehaviorExtension)
```

- [ ] **Step 5: Run the focused ammo-policy tests to verify they pass**

Run:

```bash
busted tests/ammo_policy_spec.lua
```

Expected: PASS

- [ ] **Step 6: Commit the ammo-policy module slice**

```bash
git add scripts/mods/BetterBots/ammo_policy.lua scripts/mods/BetterBots/BetterBots.lua tests/ammo_policy_spec.lua
git commit -m "feat: add configurable bot ammo pickup policy"
```

### Task 4: Tighten Coverage And Debug Logging

**Files:**
- Modify: `scripts/mods/BetterBots/ammo_policy.lua`
- Modify: `tests/ammo_policy_spec.lua`
- Modify: `tests/condition_patch_spec.lua`

- [ ] **Step 1: Write the remaining failing tests**

Add these test cases:

```lua
	it("clears stale needs_ammo when bot rises above threshold", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.30 or 0.95
				end,
				uses_ammo = function()
					return true
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "human1" } },
			_bot_group = { ammo_pickup_order_unit = function() return nil end },
			_pickup_component = { needs_ammo = true },
		}

		update_hook(self, "bot1")

		assert.is_false(self._pickup_component.needs_ammo)
	end)

	it("treats no eligible humans as reserve guard satisfied", function()
		install_module({
			ammo_module = {
				current_total_percentage = function(unit)
					return unit == "bot1" and 0.10 or 0.10
				end,
				uses_ammo = function(unit)
					return unit == "bot1"
				end,
			},
			settings = {
				bot_ranged_ammo_threshold = function() return 0.20 end,
				human_ammo_reserve_threshold = function() return 0.80 end,
			},
		})

		AmmoPolicy.install_behavior_ext_hooks({})
		local self = {
			_side = { valid_human_units = { "staff_user" } },
			_bot_group = { ammo_pickup_order_unit = function() return nil end },
			_pickup_component = { needs_ammo = false },
		}

		update_hook(self, "bot1")

		assert.is_true(self._pickup_component.needs_ammo)
	end)
```

Also update the existing condition-patch logging test to assert the configured percentage appears in the message:

```lua
			assert.is_truthy(find_debug_log("to 0.25"))
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
busted tests/ammo_policy_spec.lua tests/condition_patch_spec.lua
```

Expected: FAIL because the current minimal module does not yet log policy decisions and may not expose enough behavior for the new assertions.

- [ ] **Step 3: Add the missing behavior and logging**

Extend `scripts/mods/BetterBots/ammo_policy.lua` inside the hook:

```lua
		if bot_group and bot_group:ammo_pickup_order_unit(unit) ~= nil then
			pickup_component.needs_ammo = true
			_log("ammo_pickup_order:" .. tostring(unit), "ammo pickup preserved due to explicit order")
			...
		end
```

```lua
		if bot_ammo_percentage > bot_threshold then
			pickup_component.needs_ammo = false
			_log(
				"ammo_pickup_hold:" .. tostring(unit),
				"ammo pickup blocked: bot reserve above threshold (" .. tostring(bot_ammo_percentage) .. " > " .. tostring(bot_threshold) .. ")"
			)
			...
		end
```

```lua
		if humans_ok then
			_log(
				"ammo_pickup_allow:" .. tostring(unit),
				"ammo pickup permitted: all eligible humans above reserve"
			)
		else
			_log(
				"ammo_pickup_block_human_reserve:" .. tostring(unit),
				"ammo pickup blocked: eligible human below reserve"
			)
		end
```

Keep the logging behind `_debug_enabled()` so hot-path cost stays low.

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run:

```bash
busted tests/ammo_policy_spec.lua tests/condition_patch_spec.lua
```

Expected: PASS

- [ ] **Step 5: Commit the coverage/logging slice**

```bash
git add scripts/mods/BetterBots/ammo_policy.lua tests/ammo_policy_spec.lua tests/condition_patch_spec.lua
git commit -m "test: cover ammo policy edge cases"
```

### Task 5: Run Project Verification

**Files:**
- Modify: none
- Test: `tests/settings_spec.lua`
- Test: `tests/condition_patch_spec.lua`
- Test: `tests/ammo_policy_spec.lua`

- [ ] **Step 1: Run the focused test files together**

Run:

```bash
busted tests/settings_spec.lua tests/condition_patch_spec.lua tests/ammo_policy_spec.lua
```

Expected: PASS

- [ ] **Step 2: Run the full test suite**

Run:

```bash
make test
```

Expected: PASS

- [ ] **Step 3: Run the full quality gate**

Run:

```bash
make check
```

Expected: PASS

- [ ] **Step 4: Commit verification-only follow-ups if needed**

```bash
git add -A
git commit -m "chore: address ammo policy verification findings"
```

Only do this step if verification forces a real code/doc fix.

### Task 6: Update Documentation For The New Ammo Policy

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/known-issues.md`
- Modify: `docs/nexus-description.bbcode`

- [ ] **Step 1: Write the failing doc assertions mentally from the spec**

Before editing, verify each doc currently says the outdated thing:

- `architecture.md` does not mention `ammo_policy.lua`
- `roadmap.md` and `known-issues.md` still describe `#72` as a dead-band bug
- `nexus-description.bbcode` still says ammo conservation is just a fixed `50% -> 20%` threshold drop

- [ ] **Step 2: Update `docs/dev/architecture.md`**

Add a new numbered item near the other bot-behavior policy modules:

```md
32. Ammo policy (`ammo_policy.lua`):
    - hook `BotBehaviorExtension._update_ammo` (post-process)
    - bots start seeking ammo at the configured ranged-ammo threshold
    - bots only claim ammo when every eligible human ammo user is above the configured reserve threshold
    - explicit ammo pickup orders are preserved
```

- [ ] **Step 3: Update project status docs**

Edit `docs/dev/status.md`, `docs/dev/roadmap.md`, and `docs/dev/known-issues.md` so `#72` is described as:

```md
Implemented on `dev/v0.9.1`: configurable ammo policy. Opportunistic ranged fire and ammo pickup onset share one threshold; bots only take ammo when eligible humans are above the configured reserve. Pending in-game validation.
```

Remove language that frames `#72` as only the `10-20%` dead band once the code is in place.

- [ ] **Step 4: Update the Nexus description**

Replace the old fixed-threshold note in `docs/nexus-description.bbcode` with user-facing wording such as:

```bbcode
[*][b]Configurable ammo policy:[/b] Bots keep opportunistic ranged fire until your chosen reserve threshold, start looking for ammo at that same point, and only take ammo when human players with ammo-based weapons are above your configured reserve.
[*]Bot ranged ammo threshold
[*]Human ammo reserve threshold
```

- [ ] **Step 5: Run doc verification**

Run:

```bash
make doc-check
```

Expected: PASS

- [ ] **Step 6: Commit the doc updates**

```bash
git add docs/dev/architecture.md docs/dev/status.md docs/dev/roadmap.md docs/dev/known-issues.md docs/nexus-description.bbcode
git commit -m "docs: update ammo policy status and user docs"
```

## Self-Review

### Spec coverage

- Slider-backed `X` and `Z` settings: covered in Task 1
- Opportunistic ranged threshold override only: covered in Task 2
- Dedicated `ammo_policy.lua` module and pickup logic: covered in Task 3
- Eligible-human filtering, explicit pickup orders, stale-state clearing, and logging: covered in Task 4
- Project verification: covered in Task 5
- Docs updates required by the spec: covered in Task 6

No spec gaps found.

### Placeholder scan

- No `TODO`, `TBD`, or "implement later" placeholders remain
- Each code-edit step includes concrete code
- Each verification step includes exact commands and expected outcomes

### Type consistency

- Public settings accessors use `Settings.bot_ranged_ammo_threshold()` and `Settings.human_ammo_reserve_threshold()` consistently across all tasks
- The new module is consistently named `ammo_policy.lua` / `AmmoPolicy`
- DMF control syntax is consistently `type = "numeric"` with `range` and `step_size`

