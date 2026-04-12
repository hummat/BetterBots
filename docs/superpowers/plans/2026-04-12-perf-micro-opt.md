# Perf Micro-Opt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove three small hot-path wastes without changing BetterBots behavior.

**Architecture:** Keep patch tiny. Cache one-shot ability-template injection in `ability_queue.lua`, add per-frame memoization inside `target_selection.lua`, and only touch `grenade_fallback.lua` if a trivial read deferral falls out naturally. No heuristic or BT redesign.

**Tech Stack:** Lua, DMF hooks, busted, existing BetterBots perf/log/test tooling

---

## File map

- Modify: `scripts/mods/BetterBots/ability_queue.lua`
- Modify: `scripts/mods/BetterBots/target_selection.lua`
- Maybe modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Modify: `tests/ability_queue_spec.lua`
- Modify: `tests/target_selection_spec.lua`
- Maybe modify: `tests/grenade_fallback_spec.lua`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Maybe modify: `docs/dev/architecture.md`

### Task 1: Cache ability template injection

**Files:**
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
- Test: `tests/ability_queue_spec.lua`

- [ ] **Step 1: Write failing inject-cache test**

Add a focused spec near the existing template fast-path block:

```lua
	it("injects ability templates once across repeated fallback ticks", function()
		local saved_script_unit = _G.ScriptUnit
		local saved_require = require
		local inject_calls = 0
		local require_calls = 0
		local fixed_t = 10

		local ability_extension = {
			can_use_ability = function()
				return true
			end,
			action_input_is_currently_valid = function()
				return true
			end,
		}
		local action_input_extension = {
			bot_queue_action_input = function() end,
			_action_input_parsers = {
				combat_ability_action = {
					_ACTION_INPUT_SEQUENCE_CONFIGS = {
						psyker_shout = { shout_pressed = {} },
					},
				},
			},
		}
		local unit_data_extension = {
			read_component = function(_, component_name)
				if component_name == "combat_ability_action" then
					return { template_name = "psyker_shout" }
				end
			end,
		}

		_G.ScriptUnit = {
			has_extension = function(_, system_name)
				if system_name == "unit_data_system" then
					return unit_data_extension
				end
				if system_name == "ability_system" then
					return ability_extension
				end
				if system_name == "action_input_system" then
					return action_input_extension
				end
			end,
			extension = function(_, system_name)
				if system_name == "action_input_system" then
					return action_input_extension
				end
			end,
		}

		rawset(_G, "require", function(path)
			if path == "scripts/settings/ability/ability_templates/ability_templates" then
				require_calls = require_calls + 1
				return {
					psyker_shout = {
						ability_meta_data = {
							activation = { action_input = "shout_pressed" },
						},
					},
				}
			end
			if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
				return {}
			end
			return saved_require(path)
		end)

		AbilityQueue.init({
			mod = { echo = function() end, dump = function() end },
			debug_log = function() end,
			debug_enabled = function() return false end,
			fixed_time = function() return fixed_t end,
			equipped_combat_ability = function()
				return ability_extension, { name = "psyker_shout" }
			end,
			equipped_combat_ability_name = function()
				return "psyker_shout"
			end,
			is_suppressed = function() return false end,
			fallback_state_by_unit = {},
			fallback_queue_dumped_by_key = {},
			DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
			shared_rules = SharedRules,
		})
		AbilityQueue.wire({
			Heuristics = {
				resolve_decision = function()
					return false, "test_rule", {}
				end,
			},
			MetaData = {
				inject = function()
					inject_calls = inject_calls + 1
				end,
			},
			ItemFallback = {
				try_queue_item = function() end,
				reset_item_sequence_state = function() end,
			},
			Debug = {
				bot_slot_for_unit = function() return 1 end,
				context_snapshot = function(context) return context end,
				fallback_state_snapshot = function(state) return state end,
			},
			EventLog = { is_enabled = function() return false end },
			EngagementLeash = { is_movement_ability = function() return false end },
			is_combat_template_enabled = function() return true end,
		})

		AbilityQueue.try_queue("bot_unit", {})
		fixed_t = 11
		AbilityQueue.try_queue("bot_unit", {})

		assert.equals(1, inject_calls)
		assert.equals(1, require_calls)

		_G.ScriptUnit = saved_script_unit
		rawset(_G, "require", saved_require)
	end)
```

- [ ] **Step 2: Run focused test and confirm red**

Run: `make test TESTS=tests/ability_queue_spec.lua`

Expected: fail on `inject_calls` or `require_calls` being `2`.

- [ ] **Step 3: Implement one-shot accessor**

In `scripts/mods/BetterBots/ability_queue.lua`, add file-local cache:

```lua
local _ability_templates
local _ability_templates_injected

local function _ability_templates_once()
	if not _ability_templates then
		_ability_templates = require("scripts/settings/ability/ability_templates/ability_templates")
	end

	if not _ability_templates_injected then
		_MetaData.inject(_ability_templates)
		_ability_templates_injected = true
	end

	return _ability_templates
end
```

Replace:

```lua
	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)
```

with:

```lua
	local AbilityTemplates = _ability_templates_once()
```

Reset cache in `init()`:

```lua
	_ability_templates = nil
	_ability_templates_injected = false
```

- [ ] **Step 4: Re-run focused test**

Run: `make test TESTS=tests/ability_queue_spec.lua`

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/ability_queue.lua tests/ability_queue_spec.lua
git commit -m "perf(v0.11.0): cache ability template injection"
```

### Task 2: Add per-frame target-selection memoization

**Files:**
- Modify: `scripts/mods/BetterBots/target_selection.lua`
- Test: `tests/target_selection_spec.lua`

- [ ] **Step 1: Write failing cache tests**

Add counters to prove same-frame reuse and next-frame refresh:

```lua
	it("reuses smart-tag lookup within one fixed_t", function()
		local target_unit = {}
		local smart_tag_calls = 0
		local fixed_t = 0

		_G.Managers.state.extension.system = function(_self, name)
			if name == "smart_tag_system" then
				return {
					unit_tag = function(_, unit)
						if unit == target_unit then
							smart_tag_calls = smart_tag_calls + 1
							return {
								tagger_player = function()
									return {
										is_human_controlled = function()
											return true
										end,
									}
								end,
							}
						end
					end,
				}
			end
		end

		TargetSelection.init({
			mod = _mod,
			debug_log = function() end,
			debug_enabled = function() return false end,
			fixed_time = function() return fixed_t end,
		})
		TargetSelection.register_hooks()

		local unit = { has_ammo = true }
		local breed = { tags = { elite = true }, name = "chaos_hound" }

		_mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		_mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.equals(1, smart_tag_calls)

		fixed_t = 1
		_mod.handlers.slot_weight(original_slot_weight, unit, target_unit, 100, breed, nil)
		assert.equals(2, smart_tag_calls)
	end)
```

Mirror same pattern for:

- `_is_friendly_companion_pin`
- `Ammo.current_slot_percentage(unit, "slot_secondary")`

- [ ] **Step 2: Run focused test and confirm red**

Run: `make test TESTS=tests/target_selection_spec.lua`

Expected: fail because call counters increment on every invocation.

- [ ] **Step 3: Implement per-frame caches**

In `scripts/mods/BetterBots/target_selection.lua`, add:

```lua
local _cached_frame_t
local _cached_tag_results
local _cached_companion_pin_results
local _cached_slot_ammo_pct

local function _reset_frame_caches(fixed_t)
	if _cached_frame_t == fixed_t then
		return
	end

	_cached_frame_t = fixed_t
	_cached_tag_results = {}
	_cached_companion_pin_results = {}
	_cached_slot_ammo_pct = {}
end
```

Use wrappers:

```lua
local function _has_human_player_tag_cached(target_unit, fixed_t)
	_reset_frame_caches(fixed_t)
	local cached = _cached_tag_results[target_unit]
	if cached ~= nil then
		return cached
	end

	local value = _has_human_player_tag(target_unit)
	_cached_tag_results[target_unit] = value
	return value
end
```

```lua
local function _is_friendly_companion_pin_cached(target_unit, fixed_t)
	_reset_frame_caches(fixed_t)
	local cached = _cached_companion_pin_results[target_unit]
	if cached ~= nil then
		return cached
	end

	local value = _is_friendly_companion_pin(target_unit)
	_cached_companion_pin_results[target_unit] = value
	return value
end
```

```lua
local function _slot_ammo_pct_cached(unit, fixed_t)
	_reset_frame_caches(fixed_t)
	local cached = _cached_slot_ammo_pct[unit]
	if cached ~= nil then
		return cached
	end

	local value = _Ammo and _Ammo.current_slot_percentage(unit, "slot_secondary") or nil
	_cached_slot_ammo_pct[unit] = value == nil and false or value
	return value
end
```

When reading cached ammo:

```lua
local ammo_percent = _slot_ammo_pct_cached(unit, fixed_t)
if ammo_percent == false then
	ammo_percent = nil
end
```

Also reset caches in `init()`.

- [ ] **Step 4: Re-run focused test**

Run: `make test TESTS=tests/target_selection_spec.lua`

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/target_selection.lua tests/target_selection_spec.lua
git commit -m "perf(v0.11.0): memoize hot target selection lookups"
```

### Task 3: Optional grenade idle-path trim

**Files:**
- Maybe modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Maybe test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Decide if change is truly tiny**

Inspect current `try_queue()` branch structure.

Rule:
- if change is just moving `read_component("inventory")` below guards and using same local later, continue
- if it needs state-machine reshaping, skip whole task

- [ ] **Step 2: If tiny, add focused red/green coverage only if behavior could drift**

Likely no new test needed if behavior is identical and all grenade specs still pass. If a branch condition changes, add a focused regression in `tests/grenade_fallback_spec.lua`.

- [ ] **Step 3: Implement or skip**

If implemented, keep diff to local variable timing only. No branch rewrite, no new helper, no new logging.

- [ ] **Step 4: Verify grenade suite if touched**

Run: `make test TESTS=tests/grenade_fallback_spec.lua`

Expected: pass.

- [ ] **Step 5: Commit only if code changed**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "perf(v0.11.0): trim grenade fallback idle path"
```

### Task 4: Docs and full verification

**Files:**
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Maybe modify: `docs/dev/architecture.md`

- [ ] **Step 1: Update issue/docs wording**

Adjust docs to reflect:

- `#82` got another narrow perf pass
- no fresh measured headline claim yet
- remaining perf debt, if any, stays out of `v0.11.0`

- [ ] **Step 2: Run focused suites**

Run:

```bash
make test TESTS=tests/ability_queue_spec.lua
make test TESTS=tests/target_selection_spec.lua
```

If Task 3 touched grenade path, also run:

```bash
make test TESTS=tests/grenade_fallback_spec.lua
```

Expected: all pass.

- [ ] **Step 3: Run full verification**

Run:

```bash
make test
make doc-check
make check
```

Expected:
- `make test` passes with updated total count
- `make doc-check` passes
- `make check` passes

- [ ] **Step 4: Final commit**

```bash
git add docs/dev/roadmap.md docs/dev/status.md docs/dev/architecture.md
git add scripts/mods/BetterBots/ability_queue.lua scripts/mods/BetterBots/target_selection.lua scripts/mods/BetterBots/grenade_fallback.lua
git add tests/ability_queue_spec.lua tests/target_selection_spec.lua tests/grenade_fallback_spec.lua
git commit -m "perf(v0.11.0): finish low-risk perf micro-opts"
```

## Self-review notes

- Spec coverage:
  - one-shot ability-template injection: Task 1
  - target-selection per-frame memoization: Task 2
  - optional grenade tiny cleanup: Task 3
  - doc/verif/issue-state update: Task 4
- Placeholder scan:
  - no placeholder markers left in executable steps
  - Task 3 explicitly allows skip rather than vague future work
- Consistency:
  - cache names and file targets match spec
  - no step depends on undefined new APIs outside listed wrappers
