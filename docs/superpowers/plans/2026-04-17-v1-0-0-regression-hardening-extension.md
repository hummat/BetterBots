# v1.0.0 Regression Hardening Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the new test harness so v1.0.0 feature work catches more cross-module regressions and hook-registration drift without trying to reimplement the Darktide engine in Lua.

**Architecture:** Keep the current strategy: thin fake-runtime coverage around BetterBots-owned seams, not full engine emulation. Add one layer of higher-value contract tests in the existing startup/runtime specs, cover missing session-lifecycle negatives, and document the mandatory Solo Play smoke loop so engine drift is still caught by one real run per feature batch.

**Tech Stack:** Lua 5.4, busted, luacheck, stylua, lua-language-server, bash, repo-local fake runtime harness in `tests/startup_regressions_spec.lua`.

---

## File Map

- `tests/startup_regressions_spec.lua`
  - Existing fake-runtime harness. Extend it to assert actual hook dispatch and sentinel behavior, not just string presence and init wiring.
- `tests/charge_tracker_spec.lua`
  - Keep unit-level tests for `ChargeTracker`; add only missing helper extraction if needed.
- `tests/item_fallback_spec.lua`
  - Keep unit-level tests for retry/state sequencing; do not bloat it with harness concerns.
- `tests/update_dispatcher_spec.lua`
  - Add negative/session-lifecycle coverage around `session_start`, snapshot cadence, and event-log-disabled paths.
- `tests/runtime_contracts_spec.lua`
  - New cross-module contract spec using real BetterBots modules with shared state tables.
- `tests/test_helper.lua`
  - Modify only if a missing audited helper is required by the new spec. No ad-hoc raw engine tables.
- `AGENTS.md`
  - Update the test inventory if `tests/runtime_contracts_spec.lua` is added.
- `docs/dev/test-plan.md`
  - Add the mandatory post-harness feature-batch smoke checklist.
- `docs/dev/validation-tracker.md`
  - Add tracker fields for the new smoke checklist so logs and mission results are recorded consistently.

---

### Task 1: Tighten Startup Hook Contract Coverage

**Files:**
- Modify: `tests/startup_regressions_spec.lua`

- [ ] **Step 1: Add a failing spec for ability-extension hook dispatch**

Add this block near the existing hook-registration tests:

```lua
it("dispatches use_ability_charge through ChargeTracker.handle", function()
	local harness = make_bootstrap_harness()
	harness:load()

	local handled = {}
	harness.modules.ChargeTracker.handle = function(self, ability_type, optional_num_charges)
		handled[#handled + 1] = {
			self = self,
			ability_type = ability_type,
			charges = optional_num_charges,
		}
	end

	local ability_ext = {
		use_ability_charge = function(self, ability_type, optional_num_charges)
			return "orig", ability_type, optional_num_charges
		end,
	}

	harness:invoke_hook_require("scripts/extension_systems/ability/player_unit_ability_extension", ability_ext)
	local a, b, c = ability_ext:use_ability_charge("combat_ability", 2)

	assert.same("orig", a)
	assert.same("combat_ability", b)
	assert.same(2, c)
	assert.equals(1, #handled)
	assert.same("combat_ability", handled[1].ability_type)
	assert.same(2, handled[1].charges)
end)
```

- [ ] **Step 2: Add a failing spec for state-change finish dispatch**

```lua
it("dispatches ActionCharacterStateChange.finish through ItemFallback", function()
	local harness = make_bootstrap_harness()
	harness:load()

	local forwarded = {}
	harness.modules.ItemFallback.on_state_change_finish = function(func, self, reason, data, t, time_in_action)
		forwarded[#forwarded + 1] = {
			self = self,
			reason = reason,
			t = t,
			time_in_action = time_in_action,
		}
		return func(self, reason, data, t, time_in_action)
	end

	local action = {
		finish = function(self, reason, data, t, time_in_action)
			return "orig-finish", reason, t, time_in_action
		end,
	}

	harness:invoke_hook_require("scripts/extension_systems/ability/actions/action_character_state_change", action)
	local tag, reason, t, time_in_action = action:finish("interrupted", {}, 12, 0.1)

	assert.same("orig-finish", tag)
	assert.same("interrupted", reason)
	assert.same(1, #forwarded)
	assert.same(12, forwarded[1].t)
	assert.same(0.1, forwarded[1].time_in_action)
end)
```

- [ ] **Step 3: Add a failing spec for behavior sentinel + dispatch**

```lua
it("installs behavior hooks once and dispatches update/init through extracted modules", function()
	local harness = make_bootstrap_harness()
	harness:load()

	local dispatched = { update = 0, inject = 0 }
	harness.modules.UpdateDispatcher.dispatch = function(_self, unit)
		dispatched.update = dispatched.update + 1
		dispatched.last_unit = unit
	end
	harness.modules.GestaltInjector.inject = function(gestalts_or_nil, unit)
		dispatched.inject = dispatched.inject + 1
		dispatched.inject_unit = unit
		return gestalts_or_nil or { ranged = "killshot" }, true
	end

	local behavior_ext = {
		update = function() end,
		_init_blackboard_components = function(_self, _blackboard, _physics_world, gestalts_or_nil)
			return gestalts_or_nil
		end,
		_refresh_destination = function() end,
	}

	harness:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)
	harness:invoke_hook_require("scripts/extension_systems/behavior/bot_behavior_extension", behavior_ext)

	behavior_ext._unit = "bot_unit_1"
	behavior_ext:update("bot_unit_1")
	local gestalts = behavior_ext:_init_blackboard_components({}, nil, nil)

	assert.equals(1, dispatched.update)
	assert.same("bot_unit_1", dispatched.last_unit)
	assert.equals(1, dispatched.inject)
	assert.same("killshot", gestalts.ranged)
end)
```

- [ ] **Step 4: Run the targeted spec and make it fail for the new assertions**

Run: `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua`
Expected: at least one of the three new tests fails before implementation adjustments.

- [ ] **Step 5: Make the minimal harness/test changes**

If needed, extend `make_bootstrap_harness()` with a tiny helper to count matching hook registrations cleanly:

```lua
local function count_hooks(hook_registrations, target, method_name, hook_type)
	local count = 0
	for _, reg in ipairs(hook_registrations) do
		if reg.target == target and reg.method == method_name and reg.hook_type == hook_type then
			count = count + 1
		end
	end
	return count
end
```

Use it in the new sentinel assertion instead of ad-hoc loops.

- [ ] **Step 6: Re-run targeted and full verification**

Run:
- `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua`
- `make check-ci`

Expected:
- `tests/startup_regressions_spec.lua`: PASS
- `make check-ci`: PASS

- [ ] **Step 7: Commit**

```bash
git add tests/startup_regressions_spec.lua
git commit -m "test(startup): assert hook dispatch and behavior sentinel contracts"
```

---

### Task 2: Add a Real Cross-Module Runtime Contract Spec

**Files:**
- Create: `tests/runtime_contracts_spec.lua`
- Modify: `AGENTS.md`

- [ ] **Step 1: Write the failing spec file**

Create `tests/runtime_contracts_spec.lua` with this structure:

```lua
local test_helper = require("tests.test_helper")

local ChargeTracker = dofile("scripts/mods/BetterBots/charge_tracker.lua")
local ItemFallback = dofile("scripts/mods/BetterBots/item_fallback.lua")

describe("runtime contracts", function()
	local saved_script_unit
	local fallback_state_by_unit
	local last_charge_event_by_unit
	local emitted
	local scheduled

	before_each(function()
		saved_script_unit = rawget(_G, "ScriptUnit")
		fallback_state_by_unit = {
			unit_stub = {
				item_rule = "zealot_relic_hazard",
				attempt_id = "attempt-7",
			},
		}
		last_charge_event_by_unit = {}
		emitted = {}
		scheduled = {}

		_G.ScriptUnit = test_helper.make_script_unit_mock({
			unit_stub = {
				unit_data_system = test_helper.make_player_unit_data_extension({
					combat_ability_action = { template_name = "veteran_stance" },
				}),
				ability_system = test_helper.make_player_ability_extension(),
			},
		})

		ChargeTracker.init({
			fixed_time = function()
				return 10
			end,
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			last_charge_event_by_unit = last_charge_event_by_unit,
			fallback_state_by_unit = fallback_state_by_unit,
			grenade_fallback = {
				record_charge_event = function() end,
			},
			settings = {
				is_feature_enabled = function()
					return false
				end,
			},
			team_cooldown = {
				record = function() end,
			},
			combat_ability_identity = {
				resolve = function()
					return nil
				end,
			},
			event_log = {
				is_enabled = function()
					return true
				end,
				emit = function(event)
					emitted[#emitted + 1] = event
				end,
			},
			bot_slot_for_unit = function()
				return 1
			end,
		})

		ItemFallback.init({
			mod = { echo = function() end, dump = function() end },
			debug_log = function() end,
			debug_enabled = function()
				return false
			end,
			fixed_time = function()
				return 10
			end,
			equipped_combat_ability_name = function()
				return "veteran_stance"
			end,
			fallback_state_by_unit = fallback_state_by_unit,
			last_charge_event_by_unit = last_charge_event_by_unit,
			fallback_queue_dumped_by_key = {},
			ITEM_WIELD_TIMEOUT_S = 2,
			ITEM_SEQUENCE_RETRY_S = 1,
			ITEM_CHARGE_CONFIRM_TIMEOUT_S = 1.5,
			ITEM_DEFAULT_START_DELAY_S = 0,
			event_log = {
				is_enabled = function()
					return false
				end,
				emit = function() end,
				next_attempt_id = function()
					return 8
				end,
			},
			bot_slot_for_unit = function()
				return 1
			end,
		})

		ItemFallback.schedule_retry = function(unit, fixed_t, retry_delay_s)
			scheduled[#scheduled + 1] = {
				unit = unit,
				fixed_t = fixed_t,
				retry_delay_s = retry_delay_s,
			}
		end
	end)

	after_each(function()
		rawset(_G, "ScriptUnit", saved_script_unit)
	end)

	it("carries fallback rule and attempt id into consumed event", function()
		ChargeTracker.handle({
			_unit = "unit_stub",
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			_equipped_abilities = {
				combat_ability = { name = "veteran_stance" },
			},
		}, "combat_ability", 1)

		assert.equals("consumed", emitted[1].event)
		assert.equals("zealot_relic_hazard", emitted[1].rule)
		assert.equals("attempt-7", emitted[1].attempt_id)
	end)

	it("schedules a retry after a failed combat-ability state transition", function()
		ItemFallback.on_state_change_finish(function() end, {
			_action_settings = { ability_type = "combat_ability", use_ability_charge = true },
			_player = {
				is_human_controlled = function()
					return false
				end,
			},
			_player_unit = "unit_stub",
			_wanted_state_name = "stunned",
			_character_sate_component = { state_name = "walking" },
		}, "interrupted", nil, 10, 0.1)

		assert.equals(1, #scheduled)
		assert.equals("unit_stub", scheduled[1].unit)
		assert.equals(0.35, scheduled[1].retry_delay_s)
	end)
end)
```

- [ ] **Step 2: Run the new spec to verify it fails first**

Run: `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/runtime_contracts_spec.lua`
Expected: FAIL until the spec is wired cleanly and helper setup is correct.

- [ ] **Step 3: Make the minimal fixes**

Only adjust the new spec or a missing audited helper. Do **not** change production code unless the failure exposes a real contract bug.

If a helper is required, add it in `tests/test_helper.lua` by copying the audited pattern already used by `make_side_system_double()` and `make_liquid_area_system_double()`: exact verified surface only, `_apply_audited_overrides(...)`, and no raw ad-hoc escape hatches.

- [ ] **Step 4: Register the new spec in AGENTS**

Add one line under the `tests/` inventory block in `AGENTS.md`:

```text
  runtime_contracts_spec.lua               # cross-module charge/event/retry contract coverage
```

Also update the `make test` inventory sentence near the top to include `runtime_contracts`.

- [ ] **Step 5: Re-run targeted and full verification**

Run:
- `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/runtime_contracts_spec.lua`
- `make check-ci`

Expected:
- `tests/runtime_contracts_spec.lua`: PASS
- `make check-ci`: PASS

- [ ] **Step 6: Commit**

```bash
git add tests/runtime_contracts_spec.lua AGENTS.md
git commit -m "test(runtime): add cross-module charge and retry contracts"
```

---

### Task 3: Extend UpdateDispatcher Negative and Session-Lifecycle Coverage

**Files:**
- Modify: `tests/update_dispatcher_spec.lua`

- [ ] **Step 1: Add failing negative/session-lifecycle tests**

Append these cases:

```lua
it("does not emit session_start when no alive bots are reported", function()
	UpdateDispatcher.init(make_deps({ bots = {} }))

	UpdateDispatcher.dispatch(make_self(false), "unit_stub")

	local session_start_count = 0
	for i = 1, #emitted_events do
		if emitted_events[i].event == "session_start" then
			session_start_count = session_start_count + 1
		end
	end

	assert.equals(0, session_start_count)
	assert.is_false(session_start_state.emitted)
end)

it("re-emits session_start after the caller resets session_start_state", function()
	local self = make_self(false)

	UpdateDispatcher.dispatch(self, "unit_stub")
	session_start_state.emitted = false
	fixed_t = fixed_t + 1
	UpdateDispatcher.dispatch(self, "unit_stub")

	local session_start_count = 0
	for i = 1, #emitted_events do
		if emitted_events[i].event == "session_start" then
			session_start_count = session_start_count + 1
		end
	end

	assert.equals(2, session_start_count)
end)

it("emits snapshot with cooldown_ready=false when ability extension is missing", function()
	extension_map = { unit_stub = {} }
	_G.ScriptUnit = test_helper.make_script_unit_mock(extension_map)

	UpdateDispatcher.dispatch(make_self(false), "unit_stub")

	assert.equals("snapshot", emitted_events[#emitted_events].event)
	assert.is_false(emitted_events[#emitted_events].cooldown_ready)
	assert.is_nil(emitted_events[#emitted_events].charges)
end)

it("skips collect_alive_bots entirely when the event log is disabled", function()
	UpdateDispatcher.init(make_deps({
		event_log_enabled = false,
	}))

	UpdateDispatcher.dispatch(make_self(false), "unit_stub")

	assert.falsy(table.concat(call_log, ","):find("collect_alive_bots", 1, true))
end)
```

Update `make_deps(opts)` so `debug.collect_alive_bots` records a call-log entry:

```lua
debug = {
	collect_alive_bots = function()
		call_log[#call_log + 1] = "collect_alive_bots"
		return opts.bots or {
			{
				player = {
					slot = function()
						return 2
					end,
					archetype_name = function()
						return "psyker"
					end,
				},
				unit = "unit_stub",
			},
		}
	end,
```

Then assert `"collect_alive_bots"` is absent when `event_log_enabled = false`.

- [ ] **Step 2: Run the targeted spec to verify red first**

Run: `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/update_dispatcher_spec.lua`
Expected: FAIL until the new tests and call-log assertions are wired correctly.

- [ ] **Step 3: Make the minimal test-only fixes**

Do not change `scripts/mods/BetterBots/update_dispatcher.lua` unless one of the new tests exposes a real lifecycle bug. If production changes are needed, keep them minimal and comment-free unless the sequencing would otherwise be opaque.

- [ ] **Step 4: Re-run targeted and full verification**

Run:
- `lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/update_dispatcher_spec.lua`
- `make check-ci`

Expected:
- `tests/update_dispatcher_spec.lua`: PASS
- `make check-ci`: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/update_dispatcher_spec.lua
git commit -m "test(dispatcher): cover session lifecycle and negative paths"
```

---

### Task 4: Document the Mandatory Smoke Loop for Feature Batches

**Files:**
- Modify: `docs/dev/test-plan.md`
- Modify: `docs/dev/validation-tracker.md`

- [ ] **Step 1: Add a new smoke section to the manual test plan**

Insert this section after `## Acceptance criteria` in `docs/dev/test-plan.md`:

```md
## Release-Candidate Smoke Loop

Run this after every feature batch that touches hooks, fallback state, event logging, or bot input dispatch:

1. Fresh launch smoke
   - Start Darktide from a cold process.
   - Launch one Solo Play mission.
   - Confirm `BetterBots loaded` appears exactly once.
   - Confirm no startup traceback appears in the first minute.

2. Ability-path smoke
   - Observe at least one template-path activation.
   - Observe at least one item-path activation.
   - Observe at least one grenade/blitz activation if the batch touched grenade logic.

3. Session-lifecycle smoke
   - Finish the mission or return to Mourningstar.
   - Launch a second Solo Play mission without restarting the game.
   - Confirm no duplicate startup spam, no stale fallback loops, and no immediate traceback on mission start.

4. Core regression smoke
   - Revive/rescue still works.
   - Navigation/combat loop still looks normal.
```

- [ ] **Step 2: Add matching tracker fields**

Insert these lines into the run template in `docs/dev/validation-tracker.md` under `Regression checks:`:

```text
- fresh launch / startup load: PASS/FAIL/UNKNOWN
- second mission without restart: PASS/FAIL/UNKNOWN
- duplicate startup spam: yes/no
- template/item/grenade smoke all observed: yes/no
```

- [ ] **Step 3: Verify docs still pass repo checks**

Run: `make doc-check`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add docs/dev/test-plan.md docs/dev/validation-tracker.md
git commit -m "docs(test-plan): require smoke loop for release-candidate feature batches"
```

---

## Self-Review

- **Spec coverage:** This plan covers the three high-ROI gaps left by the current harness: real hook dispatch, cross-module contract coverage, and session-lifecycle negatives. It also turns the manual smoke requirement into a tracked repo rule.
- **Placeholder scan:** No `TODO`, `TBD`, or “similar to above” placeholders remain. Every task names exact files, commands, and expected assertions.
- **Type consistency:** All test snippets use existing helper/module names already present in the repo: `make_bootstrap_harness`, `ChargeTracker.handle`, `ItemFallback.on_state_change_finish`, `UpdateDispatcher.dispatch`, and `test_helper.make_script_unit_mock`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-v1-0-0-regression-hardening-extension.md`. Two execution options:

**1. Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks.

**2. Inline Execution** - execute tasks in one session using the plan as the checklist.
