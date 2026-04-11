# Revive-with-ability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bots self-cast a defensive ability (shout or stealth) before starting a revive/rescue interaction when enemies are nearby.

**Architecture:** Hook `BtBotInteractAction.enter` in a new `revive_ability.lua` module. The hook detects rescue-type interactions, validates a 5-template defensive ability whitelist, and queues the initial action input. It then sets up the shared `_fallback_state_by_unit` state machine so the existing `ability_queue.lua` cleanup code handles the hold→release lifecycle on subsequent ticks — no changes to ability_queue needed.

**Tech Stack:** Lua (DMF mod framework), busted (tests)

---

### Task 1: Create revive_ability.lua module skeleton + test file

**Files:**
- Create: `scripts/mods/BetterBots/revive_ability.lua`
- Create: `tests/revive_ability_spec.lua`

- [ ] **Step 1: Write the test file with engine stubs and module loading**

```lua
-- tests/revive_ability_spec.lua
local _extensions = {}
local _debug_logs = {}
local _debug_on = false
local _recorded_inputs = {}
local _suppressed = false
local _suppressed_reason = nil
local _combat_template_enabled = true

_G.ScriptUnit = {
	has_extension = function(unit, system_name)
		local unit_exts = _extensions[unit]
		return unit_exts and unit_exts[system_name] or nil
	end,
	extension = function(unit, system_name)
		local ext = _extensions[unit] and _extensions[unit][system_name]
		if not ext then
			error("No extension " .. system_name .. " for " .. tostring(unit))
		end
		return ext
	end,
}
_G.ALIVE = setmetatable({}, { __index = function() return true end })
_G.Managers = { state = { extension = { system = function() return nil end } } }

local _orig_require = require
local _ability_templates = {}
local function _mock_require(path)
	if path == "scripts/settings/ability/ability_templates/ability_templates" then
		return _ability_templates
	end
	if path:match("^scripts/") then
		return {}
	end
	return _orig_require(path)
end
rawset(_G, "require", _mock_require)

local SharedRules = dofile("scripts/mods/BetterBots/shared_rules.lua")
local ReviveAbility = dofile("scripts/mods/BetterBots/revive_ability.lua")

rawset(_G, "require", _orig_require)

-- Mock factories
local function make_unit(id)
	return { _test_id = id or "bot_1" }
end

local function make_action_input_ext()
	return {
		bot_queue_action_input = function(_, component, input, raw)
			_recorded_inputs[#_recorded_inputs + 1] = {
				component = component,
				input = input,
				raw = raw,
			}
		end,
		_action_input_parsers = {},
	}
end

local function make_ability_ext(can_use, charges)
	return {
		can_use_ability = function(_, _ability_type)
			return can_use
		end,
		remaining_ability_charges = function(_, _ability_type)
			return charges or 1
		end,
	}
end

local function make_unit_data_ext(template_name)
	return {
		read_component = function(_, component_name)
			if component_name == "combat_ability_action" then
				return { template_name = template_name or "none" }
			end
			return nil
		end,
	}
end

local function setup_unit(unit, template_name, can_use, charges)
	local action_input_ext = make_action_input_ext()
	local ability_ext = make_ability_ext(can_use ~= false, charges or 1)
	local unit_data_ext = make_unit_data_ext(template_name)
	_extensions[unit] = {
		unit_data_system = unit_data_ext,
		ability_system = ability_ext,
		action_input_system = action_input_ext,
	}
	return action_input_ext, ability_ext, unit_data_ext
end

local function make_blackboard(enemies)
	return {
		perception = {
			enemies_in_proximity = enemies or 3,
		},
	}
end

local _fallback_state = {}
local _event_log_events = {}

local function init_module()
	_fallback_state = {}
	_event_log_events = {}
	_debug_logs = {}
	_recorded_inputs = {}
	_suppressed = false
	_suppressed_reason = nil
	_combat_template_enabled = true

	ReviveAbility.init({
		mod = {
			echo = function() end,
			hook = function() end,
			hook_require = function() end,
		},
		debug_log = function(key, fixed_t, message)
			_debug_logs[#_debug_logs + 1] = { key = key, fixed_t = fixed_t, message = message }
		end,
		debug_enabled = function() return _debug_on end,
		fixed_time = function() return 100 end,
		is_suppressed = function()
			return _suppressed, _suppressed_reason
		end,
		equipped_combat_ability_name = function() return "test_ability" end,
		fallback_state_by_unit = _fallback_state,
		perf = nil,
		shared_rules = SharedRules,
	})

	local mock_meta_data = {
		inject = function() end,
	}
	local mock_event_log = {
		is_enabled = function() return true end,
		emit = function(evt)
			_event_log_events[#_event_log_events + 1] = evt
		end,
	}
	local mock_debug = {
		bot_slot_for_unit = function() return 1 end,
	}

	ReviveAbility.wire({
		MetaData = mock_meta_data,
		EventLog = mock_event_log,
		Debug = mock_debug,
		is_combat_template_enabled = function()
			return _combat_template_enabled
		end,
	})
end

describe("revive_ability", function()
	before_each(function()
		_extensions = {}
		init_module()
	end)

	it("loads without error", function()
		assert.is_table(ReviveAbility)
		assert.is_function(ReviveAbility.init)
		assert.is_function(ReviveAbility.wire)
		assert.is_function(ReviveAbility.try_pre_revive)
	end)
end)
```

- [ ] **Step 2: Write the module skeleton**

```lua
-- scripts/mods/BetterBots/revive_ability.lua
-- Revive-with-ability (#7): fire a defensive ability before rescue interactions.
-- Hooks BtBotInteractAction.enter; delegates hold+release to ability_queue's
-- state machine via _fallback_state_by_unit.
local _mod
local _debug_log
local _debug_enabled
local _fixed_time
local _is_suppressed
local _equipped_combat_ability_name
local _fallback_state_by_unit
local _perf

local _MetaData
local _EventLog
local _Debug
local _is_combat_template_enabled
local _action_input_is_bot_queueable

local REVIVE_DEFENSIVE_ABILITIES = {
	ogryn_taunt_shout = true,
	psyker_shout = true,
	adamant_shout = true,
	zealot_invisibility = true,
	veteran_stealth_combat_ability = true,
}

local RESCUE_INTERACTION_TYPES = {
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
}

local M = {}

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_is_suppressed = deps.is_suppressed
	_equipped_combat_ability_name = deps.equipped_combat_ability_name
	_fallback_state_by_unit = deps.fallback_state_by_unit
	_perf = deps.perf
	local shared_rules = deps.shared_rules or {}
	_action_input_is_bot_queueable = shared_rules.action_input_is_bot_queueable
end

function M.wire(deps)
	_MetaData = deps.MetaData
	_EventLog = deps.EventLog
	_Debug = deps.Debug
	_is_combat_template_enabled = deps.is_combat_template_enabled
end

function M.try_pre_revive(unit, blackboard, action_data)
	-- Implementation in Task 2
	return false
end

function M.register_hooks()
	-- Hook registration in Task 3
end

-- Exposed for testing
M.REVIVE_DEFENSIVE_ABILITIES = REVIVE_DEFENSIVE_ABILITIES
M.RESCUE_INTERACTION_TYPES = RESCUE_INTERACTION_TYPES

return M
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `make test`
Expected: New test file loads, "loads without error" passes. All existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/mods/BetterBots/revive_ability.lua tests/revive_ability_spec.lua
git commit -m "feat(revive-ability): add module skeleton and test scaffolding (#7)"
```

---

### Task 2: Implement try_pre_revive core logic

**Files:**
- Modify: `scripts/mods/BetterBots/revive_ability.lua`
- Modify: `tests/revive_ability_spec.lua`

- [ ] **Step 1: Write failing tests for the core activation path**

Add to `tests/revive_ability_spec.lua` inside the outer `describe` block:

```lua
	describe("try_pre_revive", function()
		local unit, blackboard

		before_each(function()
			_debug_on = true
			unit = make_unit("bot_1")
			blackboard = make_blackboard(3)
		end)

		it("queues ability for revive interaction with enemies nearby", function()
			setup_unit(unit, "ogryn_taunt_shout")
			_ability_templates.ogryn_taunt_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
			local action_data = { interaction_type = "revive" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals(1, #_recorded_inputs)
			assert.equals("combat_ability_action", _recorded_inputs[1].component)
			assert.equals("shout_pressed", _recorded_inputs[1].input)
		end)

		it("sets up fallback state machine for hold+release", function()
			setup_unit(unit, "psyker_shout")
			_ability_templates.psyker_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
			local action_data = { interaction_type = "revive" }
			ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			local state = _fallback_state[unit]
			assert.is_not_nil(state)
			assert.is_true(state.active)
			assert.equals(100 + 0.075, state.hold_until)
			assert.equals("shout_released", state.wait_action_input)
			assert.is_false(state.wait_sent)
		end)

		it("queues stealth ability (zealot_invisibility)", function()
			setup_unit(unit, "zealot_invisibility")
			_ability_templates.zealot_invisibility = {
				ability_meta_data = {
					activation = { action_input = "stance_pressed" },
				},
			}
			local action_data = { interaction_type = "revive" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals("stance_pressed", _recorded_inputs[1].input)
		end)

		it("queues veteran stealth ability", function()
			setup_unit(unit, "veteran_stealth_combat_ability")
			_ability_templates.veteran_stealth_combat_ability = {
				ability_meta_data = {
					activation = { action_input = "combat_ability_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "combat_ability_released" },
				},
			}
			local action_data = { interaction_type = "rescue" }
			local result = ReviveAbility.try_pre_revive(unit, blackboard, action_data)
			assert.is_true(result)
			assert.equals("combat_ability_pressed", _recorded_inputs[1].input)
		end)
	end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: 4 new tests FAIL (try_pre_revive returns false, no inputs queued).

- [ ] **Step 3: Implement try_pre_revive**

Replace the `try_pre_revive` function in `scripts/mods/BetterBots/revive_ability.lua`:

```lua
function M.try_pre_revive(unit, blackboard, action_data)
	local interaction_type = action_data and action_data.interaction_type
	if not RESCUE_INTERACTION_TYPES[interaction_type] then
		return false
	end

	local perception = blackboard and blackboard.perception
	local enemies_nearby = perception and perception.enemies_in_proximity or 0
	if enemies_nearby < 1 then
		return false
	end

	local suppressed, suppress_reason = _is_suppressed(unit)
	if suppressed then
		if _debug_enabled() then
			_debug_log(
				"revive_ability_suppressed:" .. tostring(suppress_reason) .. ":" .. tostring(unit),
				_fixed_time(),
				"revive ability suppressed (" .. tostring(suppress_reason) .. ")"
			)
		end
		return false
	end

	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_extension then
		return false
	end

	local ability_component = unit_data_extension:read_component("combat_ability_action")
	local ability_template_name = ability_component and ability_component.template_name
	if not ability_template_name or not REVIVE_DEFENSIVE_ABILITIES[ability_template_name] then
		return false
	end

	local ability_extension = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_extension then
		return false
	end

	if _is_combat_template_enabled and not _is_combat_template_enabled(ability_template_name, ability_extension) then
		return false
	end
	if not ability_extension then
		return false
	end

	if not ability_extension:can_use_ability("combat_ability") then
		return false
	end

	local charges = ability_extension:remaining_ability_charges("combat_ability")
	if not charges or charges < 1 then
		return false
	end

	local AbilityTemplates = require("scripts/settings/ability/ability_templates/ability_templates")
	_MetaData.inject(AbilityTemplates)

	local ability_template = rawget(AbilityTemplates, ability_template_name)
	local ability_meta_data = ability_template and ability_template.ability_meta_data
	if not ability_meta_data or not ability_meta_data.activation then
		return false
	end

	local activation_data = ability_meta_data.activation
	local action_input = activation_data.action_input
	if not action_input then
		return false
	end

	local action_input_extension = ScriptUnit.has_extension(unit, "action_input_system")
	if not action_input_extension then
		return false
	end

	if _action_input_is_bot_queueable then
		local is_valid = _action_input_is_bot_queueable(
			action_input_extension,
			ability_extension,
			"combat_ability_action",
			ability_template_name,
			action_input,
			activation_data.used_input,
			_fixed_time()
		)
		if not is_valid then
			return false
		end
	end

	local fixed_t = _fixed_time()
	action_input_extension:bot_queue_action_input("combat_ability_action", action_input, nil)

	local state = _fallback_state_by_unit[unit]
	if not state then
		state = {}
		_fallback_state_by_unit[unit] = state
	end
	state.active = true
	state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
	state.wait_action_input = ability_meta_data.wait_action
		and ability_meta_data.wait_action.action_input
		or nil
	state.wait_sent = false
	state.action_input_extension = action_input_extension

	if _debug_enabled() then
		_debug_log(
			"revive_ability:" .. ability_template_name .. ":" .. tostring(unit),
			fixed_t,
			"revive ability queued: "
				.. ability_template_name
				.. " (interaction="
				.. tostring(interaction_type)
				.. ", enemies="
				.. tostring(enemies_nearby)
				.. ")"
		)
	end

	if _EventLog and _EventLog.is_enabled() then
		local bot_slot = _Debug and _Debug.bot_slot_for_unit(unit) or nil
		_EventLog.emit({
			t = fixed_t,
			event = "revive_ability",
			bot = bot_slot,
			ability = _equipped_combat_ability_name(unit),
			template = ability_template_name,
			interaction = interaction_type,
			enemies = enemies_nearby,
		})
	end

	return true
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All 4 new tests PASS plus skeleton test. All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/revive_ability.lua tests/revive_ability_spec.lua
git commit -m "feat(revive-ability): implement try_pre_revive core logic (#7)"
```

---

### Task 3: Add guard tests (rejection paths)

**Files:**
- Modify: `tests/revive_ability_spec.lua`

- [ ] **Step 1: Write failing tests for all rejection paths**

Add inside the `describe("try_pre_revive", ...)` block:

```lua
		describe("rejection guards", function()
			before_each(function()
				_ability_templates.ogryn_taunt_shout = {
					ability_meta_data = {
						activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
						wait_action = { action_input = "shout_released" },
					},
				}
			end)

			it("rejects non-rescue interaction types", function()
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "health_station" })
				assert.is_false(result)
				assert.equals(0, #_recorded_inputs)
			end)

			it("rejects nil action_data", function()
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, nil)
				assert.is_false(result)
			end)

			it("rejects when no enemies nearby", function()
				setup_unit(unit, "ogryn_taunt_shout")
				blackboard = make_blackboard(0)
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when suppressed", function()
				_suppressed = true
				_suppressed_reason = "dodging"
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects non-whitelisted ability (charge)", function()
				setup_unit(unit, "ogryn_charge")
				_ability_templates.ogryn_charge = {
					ability_meta_data = {
						activation = { action_input = "aim_pressed", min_hold_time = 0.01 },
						wait_action = { action_input = "aim_released" },
					},
				}
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects non-whitelisted ability (stance)", function()
				setup_unit(unit, "veteran_combat_ability")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when ability on cooldown", function()
				setup_unit(unit, "ogryn_taunt_shout", false)
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when no charges remaining", function()
				setup_unit(unit, "ogryn_taunt_shout", true, 0)
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("rejects when category disabled", function()
				_combat_template_enabled = false
				setup_unit(unit, "ogryn_taunt_shout")
				local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
				assert.is_false(result)
			end)

			it("fires for all rescue interaction types", function()
				for _, itype in ipairs({ "revive", "rescue", "pull_up", "remove_net" }) do
					_recorded_inputs = {}
					_fallback_state = {}
					ReviveAbility.init({
						mod = { echo = function() end, hook = function() end, hook_require = function() end },
						debug_log = function() end,
						debug_enabled = function() return false end,
						fixed_time = function() return 100 end,
						is_suppressed = function() return false end,
						equipped_combat_ability_name = function() return "test" end,
						fallback_state_by_unit = _fallback_state,
						shared_rules = SharedRules,
					})
					ReviveAbility.wire({
						MetaData = { inject = function() end },
						EventLog = { is_enabled = function() return false end },
						Debug = { bot_slot_for_unit = function() return 1 end },
						is_combat_template_enabled = function() return true end,
					})
					setup_unit(unit, "ogryn_taunt_shout")
					local result = ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = itype })
					assert.is_true(result, "expected true for interaction_type=" .. itype)
				end
			end)
		end)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `make test`
Expected: All 10 new guard tests PASS (try_pre_revive already implements rejection logic). All existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add tests/revive_ability_spec.lua
git commit -m "test(revive-ability): add guard rejection tests (#7)"
```

---

### Task 4: Add debug and event log tests

**Files:**
- Modify: `tests/revive_ability_spec.lua`

- [ ] **Step 1: Write tests for logging behavior**

Add inside the outer `describe("revive_ability", ...)` block:

```lua
	describe("logging", function()
		local unit, blackboard

		before_each(function()
			unit = make_unit("bot_1")
			blackboard = make_blackboard(5)
			init_module()
			setup_unit(unit, "adamant_shout")
			_ability_templates.adamant_shout = {
				ability_meta_data = {
					activation = { action_input = "shout_pressed", min_hold_time = 0.075 },
					wait_action = { action_input = "shout_released" },
				},
			}
		end)

		it("emits debug log with per-bot key", function()
			_debug_on = true
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.is_true(#_debug_logs > 0)
			local log = _debug_logs[1]
			assert.truthy(string.find(log.key, "revive_ability:"))
			assert.truthy(string.find(log.key, "adamant_shout"))
			assert.truthy(string.find(log.key, tostring(unit)))
		end)

		it("does not emit debug log when debug disabled", function()
			_debug_on = false
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "revive" })
			assert.equals(0, #_debug_logs)
		end)

		it("emits event log with interaction type", function()
			ReviveAbility.try_pre_revive(unit, blackboard, { interaction_type = "rescue" })
			assert.equals(1, #_event_log_events)
			local evt = _event_log_events[1]
			assert.equals("revive_ability", evt.event)
			assert.equals("adamant_shout", evt.template)
			assert.equals("rescue", evt.interaction)
			assert.equals(5, evt.enemies)
		end)
	end)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `make test`
Expected: All 3 logging tests PASS. All existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add tests/revive_ability_spec.lua
git commit -m "test(revive-ability): add debug and event log tests (#7)"
```

---

### Task 5: Wire module into BetterBots.lua and register hook

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Modify: `scripts/mods/BetterBots/revive_ability.lua`

- [ ] **Step 1: Add register_hooks implementation**

Replace the `register_hooks` function in `scripts/mods/BetterBots/revive_ability.lua`:

```lua
function M.register_hooks()
	_mod:hook_require(
		"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_interact_action",
		function(BtBotInteractAction)
			local orig_enter = BtBotInteractAction.enter
			BtBotInteractAction.enter = function(self, unit, breed, blackboard, scratchpad, action_data, t)
				local perf_t0 = _perf and _perf.begin()
				M.try_pre_revive(unit, blackboard, action_data)
				if perf_t0 and _perf then
					_perf.finish("revive_ability", perf_t0)
				end
				return orig_enter(self, unit, breed, blackboard, scratchpad, action_data, t)
			end

			if _debug_enabled and _debug_enabled() then
				_debug_log(
					"revive_ability:hook_installed",
					0,
					"installed BtBotInteractAction.enter hook"
				)
			end
		end
	)
end
```

- [ ] **Step 2: Wire module into BetterBots.lua — add io_dofile**

In `scripts/mods/BetterBots/BetterBots.lua`, after the EngagementLeash load block (line ~222), add:

```lua
local ReviveAbility = mod:io_dofile("BetterBots/scripts/mods/BetterBots/revive_ability")
assert(ReviveAbility, "BetterBots: failed to load revive_ability module")
```

- [ ] **Step 3: Wire module into BetterBots.lua — add init call**

After the AbilityQueue.init block (line ~432), add:

```lua
ReviveAbility.init({
	mod = mod,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	fixed_time = _fixed_time,
	is_suppressed = _is_suppressed,
	equipped_combat_ability_name = _equipped_combat_ability_name,
	fallback_state_by_unit = _fallback_state_by_unit,
	perf = Perf,
	shared_rules = SharedRules,
})
```

- [ ] **Step 4: Wire module into BetterBots.lua — add wire call**

After the AbilityQueue.wire block (line ~505), add:

```lua
ReviveAbility.wire({
	MetaData = MetaData,
	EventLog = EventLog,
	Debug = Debug,
	is_combat_template_enabled = Settings.is_combat_template_enabled,
})
```

- [ ] **Step 5: Wire module into BetterBots.lua — add register_hooks call**

After the EngagementLeash.register_hooks() call (line ~559), add:

```lua
ReviveAbility.register_hooks()
```

- [ ] **Step 6: Run full quality gate**

Run: `make check`
Expected: format + lint + lsp + test all pass. No regressions.

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/revive_ability.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(revive-ability): wire module into BetterBots and register hook (#7)"
```

---

### Task 6: Add startup regression guard

**Files:**
- Modify: `tests/startup_regressions_spec.lua`

- [ ] **Step 1: Read the existing startup regressions test**

Read `tests/startup_regressions_spec.lua` to find the pattern for module load guards.

- [ ] **Step 2: Add revive_ability to the module load guard**

Add a test alongside the existing module load assertions:

```lua
	it("revive_ability loads without error", function()
		local ok, result = pcall(dofile, "scripts/mods/BetterBots/revive_ability.lua")
		assert.is_true(ok, "revive_ability.lua failed to load: " .. tostring(result))
		assert.is_table(result)
		assert.is_function(result.init)
		assert.is_function(result.wire)
		assert.is_function(result.try_pre_revive)
		assert.is_function(result.register_hooks)
	end)
```

- [ ] **Step 3: Run tests**

Run: `make test`
Expected: New regression guard passes. All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/startup_regressions_spec.lua
git commit -m "test(revive-ability): add startup regression guard (#7)"
```

---

### Task 7: Update docs and close out

**Files:**
- Modify: `CLAUDE.md` (symlink to `AGENTS.md`) — mod file structure table
- Modify: `docs/dev/roadmap.md` — v0.10.0 table
- Modify: `docs/dev/status.md` — v0.10.0 section
- Modify: `docs/dev/debugging.md` — log key catalog (if maintained there)

- [ ] **Step 1: Update CLAUDE.md mod file structure**

Add to the file structure table in `CLAUDE.md`, after the `engagement_leash.lua` entry:

```
  revive_ability.lua                        # Pre-revive defensive ability activation (#7)
```

And in the tests section, add:

```
  revive_ability_spec.lua                   # revive-with-ability hook + guards
```

- [ ] **Step 2: Update roadmap.md v0.10.0 table**

Change the #7 row from:

```
| 7 | Revive-with-ability (P1) | Reviving bot self-casts a defensive ability before starting revive. Implement after #37 — reuses `ally_interacting` context fields. P1 scope: gate in existing condition hook / fallback path (no BT node injection). |
```

to:

```
| 7 | Revive-with-ability (P1) | **Done.** Hook on BtBotInteractAction.enter fires shout/stealth before rescue interactions. 5-template whitelist, state machine handoff to ability_queue. ~14 tests. Needs in-game validation (`revive_ability:` log entries). |
```

- [ ] **Step 3: Update status.md**

Add a v0.10.0 row for #7:

```
| #7 | Revive-with-ability (P1) | **Done** | Hook BtBotInteractAction.enter, 5-template whitelist (shouts+stealth), fallback state machine handoff. Awaiting in-game validation. |
```

- [ ] **Step 4: Update debugging.md log key catalog**

Add `revive_ability:<template>:<unit>` to the log key catalog in `docs/dev/debugging.md` under the ability activation section.

- [ ] **Step 5: Run doc-check**

Run: `make doc-check`
Expected: No stale claims. Function counts and issue references up to date.

- [ ] **Step 6: Run full quality gate**

Run: `make check`
Expected: All checks pass (format + lint + lsp + test + doc-check).

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md docs/dev/roadmap.md docs/dev/status.md docs/dev/debugging.md
git commit -m "docs: update roadmap, status, and file structure for #7 revive-with-ability"
```
