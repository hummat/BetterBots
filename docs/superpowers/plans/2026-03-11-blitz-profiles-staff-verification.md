# Blitz Profile Templates + Staff Verification Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the grenade state machine to support non-grenade blitz abilities (shock mine, whistle, zealot knives, missile launcher) via profile-driven input sequences, and verify staff p1/p2/p3 charged fire with current code.

**Architecture:** The existing `SUPPORTED_THROW_TEMPLATES` table is extended to accept table values alongside numbers. Number values retain existing behavior. Table values carry `aim_input`, `release_input`, `throw_delay`, `auto_unwield` fields that the state machine reads instead of hardcoded `"aim_hold"`/`"aim_released"`. Three new state machine behaviors emerge from nil combinations: auto-fire (nil aim_input → skip to wait_unwield), fire-and-wait (nil release_input → skip wait_throw), and forced unwield (auto_unwield=false → immediate unwield_to_previous on entering wait_unwield).

**Tech Stack:** Lua, busted (test framework), Darktide DMF mod hooks

**Scope exclusions:**
- **Psyker blitz** (smite, chain lightning, assail) — deferred to phase 2. These need fire loops, hold-release timing, and warp charge management that don't fit the profile-driven approach.
- **Per-template heuristics** — all new templates use `grenade_generic` for now. Heuristic pass is separate.
- **Zealot knives multi-throw** — the bot throws one knife per wield cycle (auto-fire + auto-unwield). Burst-throwing would require queuing `throw_pressed` in a loop, which is phase 2 complexity. One-per-cycle is acceptable for v1.

---

## File Map

- **Modify:** `scripts/mods/BetterBots/grenade_fallback.lua` — profile resolution, state machine branching, new template entries, `_reset_state` cleanup
- **Modify:** `tests/grenade_fallback_spec.lua` — tests for all new profile behaviors
- **Read-only (verification):** `scripts/mods/BetterBots/ranged_meta_data.lua` — staff p1/p2/p3 aim chain derivation check
- **Read-only (reference):** `docs/classes/grenade-inventory.md` — blitz input patterns

---

### Task 1: Profile resolution infrastructure + shock_mine

Shock mine (`adamant_shock_mine`) uses the exact same `aim_hold` → `aim_released` pattern as standard grenades. It only needs a table entry with `throw_delay = 1.0`. This task also adds the profile resolution logic so table values work.

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:37-59` (template table), `:61-72` (`_reset_state`), `:340-364` (idle stage profile resolution)
- Modify: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write test — shock_mine number entry works like existing grenades**

In `tests/grenade_fallback_spec.lua`, add inside the main `describe` block:

```lua
describe("profile-driven blitz templates", function()
	it("treats number entries as default aim_hold/aim_released profile", function()
		-- Wire with shock_mine (number entry = same as standard grenades)
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "adamant_shock_mine" }
			end,
		})
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("grenade_ability", _recorded_inputs[1].input)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)
	end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `adamant_shock_mine` not in `SUPPORTED_THROW_TEMPLATES`, so `try_queue` returns early.

- [ ] **Step 3: Add shock_mine entry + profile resolution**

In `grenade_fallback.lua`, add to `SUPPORTED_THROW_TEMPLATES` after the Arbites section:

```lua
	-- Arbites shock mine (mine generator, aim_hold chain_time=0.8)
	adamant_shock_mine = 1.0,
```

Then change the idle stage where the template is resolved (around line 343). Replace:

```lua
	local throw_delay = SUPPORTED_THROW_TEMPLATES[grenade_name]
	if not throw_delay then
		return
	end
```

With:

```lua
	local template_entry = SUPPORTED_THROW_TEMPLATES[grenade_name]
	if not template_entry then
		return
	end

	-- Resolve profile: number = default aim_hold/aim_released; table = custom profile.
	local aim_input, release_input, throw_delay, auto_unwield
	if type(template_entry) == "number" then
		aim_input = "aim_hold"
		release_input = "aim_released"
		throw_delay = template_entry
		auto_unwield = true
	else
		aim_input = template_entry.aim_input
		release_input = template_entry.release_input
		throw_delay = template_entry.throw_delay or DEFAULT_THROW_DELAY_S
		auto_unwield = template_entry.auto_unwield ~= false -- default true
	end
```

Update the state initialization (around line 361) to store profile fields:

```lua
	state.stage = "wield"
	state.deadline_t = fixed_t + WIELD_TIMEOUT_S
	state.throw_delay = throw_delay
	state.grenade_name = grenade_name
	state.aim_input = aim_input
	state.release_input = release_input
	state.auto_unwield = auto_unwield
```

Update `_reset_state` to nil the new fields:

```lua
local function _reset_state(state, next_try_t)
	state.stage = nil
	state.deadline_t = nil
	state.wait_t = nil
	state.throw_delay = nil
	state.grenade_name = nil
	state.release_t = nil
	state.unwield_requested_t = nil
	state.aim_input = nil
	state.release_input = nil
	state.auto_unwield = nil
	if next_try_t then
		state.next_try_t = next_try_t
	end
end
```

Update the comment at the top of `SUPPORTED_THROW_TEMPLATES` to document the table format:

```lua
-- Maps player-ability names → throw profile.
-- Number value: throw_delay seconds, uses default aim_hold/aim_released/auto-unwield.
-- Table value: { aim_input, release_input, throw_delay, auto_unwield } for custom input chains.
--   aim_input:     input to queue after wield (nil = auto-fires, skip to wait_unwield)
--   release_input: input to queue after throw_delay (nil = skip wait_throw)
--   throw_delay:   seconds between aim and release (default DEFAULT_THROW_DELAY_S)
--   auto_unwield:  engine auto-chains unwield? (default true; false = force immediately)
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: all pass (293 + 1 = 294)

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenade): add profile resolution for blitz templates + shock_mine entry"
```

---

### Task 2: Custom aim/release inputs (whistle pattern)

The adamant whistle uses `aim_pressed`/`aim_released` instead of `aim_hold`/`aim_released`, and has no auto-unwield. This task makes the `wait_aim` and `wait_throw` stages read `state.aim_input` and `state.release_input` instead of hardcoded values.

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:200-250` (wait_aim + wait_throw stages)
- Modify: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write test — table profile uses custom aim/release inputs**

```lua
	it("queues custom aim_input from table profile", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "adamant_whistle" }
			end,
		})

		-- Idle → wield
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Wield confirmed → wait_aim
		_wielded_slot = "slot_grenade_ability"
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

		-- wait_aim → queues aim_pressed (not aim_hold)
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("aim_pressed", _recorded_inputs[1].input)
		assert.equals("wait_throw", _grenade_state_by_unit[unit].stage)

		-- wait_throw → queues aim_released
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("aim_released", _recorded_inputs[1].input)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `adamant_whistle` not in template table, and wait_aim still hardcodes `"aim_hold"`.

- [ ] **Step 3: Add whistle entry + parameterize aim/throw stages**

Add to `SUPPORTED_THROW_TEMPLATES`:

```lua
	-- Arbites whistle (companion order: aim_pressed/aim_released, no auto-unwield)
	adamant_whistle = {
		aim_input = "aim_pressed",
		release_input = "aim_released",
		throw_delay = 0.15,
		auto_unwield = false,
	},
```

In the `wait_aim` stage (around line 214), replace the hardcoded `"aim_hold"`:

```lua
		if fixed_t >= (state.wait_t or 0) then
			_queue_weapon_input(unit, state.aim_input or "aim_hold")
			state.stage = "wait_throw"
			state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			if _debug_enabled() then
				_debug_log("grenade_aim:" .. tostring(unit), fixed_t, "grenade queued " .. (state.aim_input or "aim_hold"))
			end
		end
```

In the `wait_throw` stage (around line 239), replace the hardcoded `"aim_released"`:

```lua
		if fixed_t >= (state.wait_t or 0) then
			_queue_weapon_input(unit, state.release_input or "aim_released")
			state.stage = "wait_unwield"
			state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
			state.release_t = fixed_t
			state.unwield_requested_t = nil
			if _debug_enabled() then
				_debug_log("grenade_release:" .. tostring(unit), fixed_t, "grenade queued " .. (state.release_input or "aim_released"))
			end
		end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenade): parameterize aim/release inputs for whistle profile"
```

---

### Task 3: Auto-fire skip (zealot knives pattern)

Zealot throwing knives auto-fire on wield via `quick_throw` (engine-driven `conditional_state_to_action_input.action_end` on `action_wield`). The bot only needs to wield, then wait for auto-unwield. When `aim_input` is nil, the state machine skips `wait_aim` and `wait_throw` entirely, going from `wield` straight to `wait_unwield`.

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:176-198` (wield stage transition)
- Modify: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write test — nil aim_input skips to wait_unwield**

```lua
	it("skips aim/throw stages for auto-fire templates", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "zealot_throwing_knives" }
			end,
		})

		-- Idle → wield
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Wield confirmed → straight to wait_unwield (no wait_aim/wait_throw)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = _mock_time + 0.5
		_recorded_inputs = {}
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
		assert.equals(0, #_recorded_inputs) -- no aim/throw inputs queued
	end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `zealot_throwing_knives` not in template table.

- [ ] **Step 3: Add knives entry + wield→wait_unwield skip**

Add to `SUPPORTED_THROW_TEMPLATES`:

```lua
	-- Zealot throwing knives (auto-fires on wield via quick_throw, auto-unwields after last charge)
	zealot_throwing_knives = {
		auto_unwield = true,
	},
```

In the `wield` stage, where `wielded_slot == "slot_grenade_ability"` is detected (around line 177), change:

```lua
	if state.stage == "wield" then
		if wielded_slot == "slot_grenade_ability" then
			if not state.aim_input then
				-- Auto-fire template: skip aim/throw, go straight to wait_unwield
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
				if _debug_enabled() then
					_debug_log("grenade_auto_fire:" .. tostring(unit), fixed_t, "grenade auto-fire, waiting for unwield")
				end
			else
				state.stage = "wait_aim"
				state.wait_t = fixed_t + AIM_DELAY_S
				if _debug_enabled() then
					_debug_log("grenade_wield_ok:" .. tostring(unit), fixed_t, "grenade wield confirmed, waiting for aim")
				end
			end
			return
		end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenade): add auto-fire skip for zealot throwing knives"
```

---

### Task 4: Fire-and-wait skip (missile launcher pattern)

Broker missile launcher queues `shoot_charge` after wield, then the engine auto-chains the rest (`charged_enough` → blast → shoot → unwield). When `release_input` is nil, the state machine skips `wait_throw` and goes from `wait_aim` directly to `wait_unwield` after queuing the aim input.

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:200-223` (wait_aim stage)
- Modify: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write test — nil release_input skips wait_throw**

```lua
	it("skips wait_throw when release_input is nil", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "broker_missile_launcher" }
			end,
		})

		-- Idle → wield
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wield", _grenade_state_by_unit[unit].stage)

		-- Wield confirmed → wait_aim
		_wielded_slot = "slot_grenade_ability"
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_aim", _grenade_state_by_unit[unit].stage)

		-- wait_aim → queues shoot_charge, skips to wait_unwield
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("shoot_charge", _recorded_inputs[1].input)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)
	end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `broker_missile_launcher` not in template table.

- [ ] **Step 3: Add missile entry + wait_aim→wait_unwield skip**

Add to `SUPPORTED_THROW_TEMPLATES`:

```lua
	-- Hive Scum missile launcher (queue shoot_charge, rest auto-chains; DLC-blocked)
	broker_missile_launcher = {
		aim_input = "shoot_charge",
		auto_unwield = true,
	},
```

In the `wait_aim` stage, after queuing the aim input (around line 214), change:

```lua
		if fixed_t >= (state.wait_t or 0) then
			_queue_weapon_input(unit, state.aim_input or "aim_hold")
			if state.release_input then
				state.stage = "wait_throw"
				state.wait_t = fixed_t + (state.throw_delay or DEFAULT_THROW_DELAY_S)
			else
				-- No release needed: skip to wait_unwield (e.g. missile auto-chains)
				state.stage = "wait_unwield"
				state.deadline_t = fixed_t + UNWIELD_TIMEOUT_S
				state.release_t = fixed_t
				state.unwield_requested_t = nil
			end
			if _debug_enabled() then
				_debug_log("grenade_aim:" .. tostring(unit), fixed_t, "grenade queued " .. (state.aim_input or "aim_hold"))
			end
		end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenade): add fire-and-wait skip for missile launcher"
```

---

### Task 5: Forced unwield for non-auto-unwield templates (whistle)

For templates with `auto_unwield = false`, the engine won't auto-chain `unwield_to_previous`. The state machine must force it. On entering `wait_unwield`, immediately queue `unwield_to_previous` (don't wait for charge confirmation or timeout). The existing charge-confirmation and timeout paths remain as fallbacks.

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:252-291` (wait_unwield stage)
- Modify: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write test — auto_unwield=false forces immediate unwield**

```lua
	it("forces immediate unwield for non-auto-unwield templates", function()
		GrenadeFallback.wire({
			build_context = function()
				return { num_nearby = 3 }
			end,
			evaluate_grenade_heuristic = function()
				return true, "grenade_generic"
			end,
			equipped_grenade_ability = function()
				return mock_ability_extension, { name = "adamant_whistle" }
			end,
		})

		-- Advance through wield → wait_aim → wait_throw → wait_unwield
		GrenadeFallback.try_queue(unit, blackboard)
		_wielded_slot = "slot_grenade_ability"
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		_mock_time = _mock_time + 0.5
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals("wait_unwield", _grenade_state_by_unit[unit].stage)

		-- Next tick: should immediately queue unwield_to_previous
		_recorded_inputs = {}
		_mock_time = _mock_time + 0.05
		GrenadeFallback.try_queue(unit, blackboard)
		assert.equals(1, #_recorded_inputs)
		assert.equals("unwield_to_previous", _recorded_inputs[1].input)
	end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — wait_unwield doesn't check `state.auto_unwield`, waits for charge confirmation or timeout.

- [ ] **Step 3: Add forced unwield in wait_unwield**

In the `wait_unwield` stage, after the slot-change check (around line 264), add before the charge confirmation check:

```lua
		-- For non-auto-unwield templates, force unwield immediately.
		-- The engine won't auto-chain unwield_to_previous for these.
		if state.auto_unwield == false and not state.unwield_requested_t then
			_queue_weapon_input(unit, "unwield_to_previous")
			state.unwield_requested_t = fixed_t
			if _debug_enabled() then
				_debug_log(
					"grenade_force_unwield:" .. tostring(unit),
					fixed_t,
					"grenade forced unwield_to_previous (no auto-unwield)"
				)
			end
			return
		end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenade): force unwield for non-auto-unwield blitz templates"
```

---

### Task 6: Update module header comment + clean up stale comments

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua:1-3` (header), `:35-36` (stale comment about blitz exclusion)

- [ ] **Step 1: Update header and stale comments**

Update file header:

```lua
-- grenade_fallback.lua — bot blitz/grenade state machine (#4)
-- Wields grenade slot, queues the appropriate input sequence, and returns to previous weapon.
-- Supports standard grenades (aim_hold/aim_released), whistle (aim_pressed/aim_released),
-- auto-fire (zealot knives), and fire-and-wait (missile launcher) patterns.
-- Only activates when charges are available and the heuristic permits.
```

Remove or update the stale comment at lines 35-36 that says blitz abilities "must NOT enter this state machine" — they now can, via profiles.

Update the comment block above `SUPPORTED_THROW_TEMPLATES` to reflect the new name semantics (the table name stays the same for backward compat, but document the dual format).

- [ ] **Step 2: Run quality checks**

Run: `make check`
Expected: all pass (format + lint + lsp + test)

- [ ] **Step 3: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua
git commit -m "docs(grenade): update header and comments for profile-driven blitz support"
```

---

### Task 7: Staff p1/p2/p3 in-game verification

This is a manual verification task. No code changes unless a staff family fails.

**Preparation:**
- Ensure bot lineup includes a Psyker with a force staff (any variant)
- Enable debug logging
- Run a mission with enough combat to trigger aim/charge sequences

**Verification checklist per staff:**

- [ ] **p3 voidstrike** (`forcestaff_p3_m1`): Watch for `shoot_charged` in weapon action logs. Same input as p4 — expected to work.
- [ ] **p1 surge** (`forcestaff_p1_m1`): Watch for `trigger_explosion` in weapon action logs. If 0 charged fires, check `bb-log raw "trigger_explosion"` in the session log.
- [ ] **p2 flame** (`forcestaff_p2_m1`): Watch for `trigger_charge_flame` in weapon action logs. Previously FAIL (March 9). If still failing, investigate whether the `_may_fire()` hook swap is reaching p2 bots.

**Log analysis after session:**

```bash
bb-log raw "forcestaff\|shoot_charged\|trigger_explosion\|trigger_charge_flame\|charge_release"
```

**If a staff fails:** Open a focused sub-task. The `find_aim_action_for_fire` derivation appears structurally correct for all 4 families (confirmed by code review). Runtime failures likely stem from ActionInputParser `hold_input` requirements or charge state transitions — investigate the specific failure before proposing a fix.

- [ ] **Record results in `docs/dev/validation-tracker.md`**

Add a run entry with per-staff PASS/FAIL and log evidence.
