# Team Cooldown Staggering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent multiple bots from wasting cooldowns and grenades by firing the same category of ability simultaneously.

**Architecture:** A new `team_cooldown.lua` module tracks the most recent activation per ability category. After a bot uses an ability (`use_ability_charge` hook), the module records it. Before another bot activates the same category, `condition_patch` and `grenade_fallback` query the module — if a different bot already activated within the suppression window, the activation is blocked (unless an emergency override rule applies).

**Tech Stack:** Lua (DMF mod), busted (tests)

**Spec:** `docs/superpowers/specs/2026-04-08-team-cooldown-staggering-design.md`

---

### Task 1: Create `team_cooldown.lua` with tests (TDD)

**Files:**
- Create: `scripts/mods/BetterBots/team_cooldown.lua`
- Create: `tests/team_cooldown_spec.lua`

- [ ] **Step 1: Write the test file with all test cases**

```lua
-- tests/team_cooldown_spec.lua

describe("team_cooldown", function()
	local TeamCooldown

	before_each(function()
		package.loaded["scripts/mods/BetterBots/team_cooldown"] = nil
		TeamCooldown = require("scripts/mods/BetterBots/team_cooldown")
		TeamCooldown.reset()
	end)

	local unit_a = { _test_id = "bot_a" }
	local unit_b = { _test_id = "bot_b" }
	local unit_c = { _test_id = "bot_c" }

	describe("record + is_suppressed", function()
		it("never suppresses the bot that recorded the activation", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed, reason = TeamCooldown.is_suppressed(unit_a, "ogryn_taunt_shout", 10.5)
			assert.is_false(suppressed)
			assert.is_nil(reason)
		end)

		it("suppresses a different bot in the same category within the window", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed, reason = TeamCooldown.is_suppressed(unit_b, "adamant_shout", 12)
			assert.is_true(suppressed)
			assert.is_string(reason)
			assert.truthy(string.find(reason, "taunt"))
		end)

		it("does not suppress a different bot in a different category", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_dash", 10.5)
			assert.is_false(suppressed)
		end)

		it("lifts suppression after the window expires", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			-- taunt window is 8s
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 18.1)
			assert.is_false(suppressed)
		end)

		it("suppresses just before the window expires", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 17.9)
			assert.is_true(suppressed)
		end)

		it("overwrites previous activation with newer one", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			TeamCooldown.record(unit_b, "psyker_shout", 14)
			-- unit_a should now be suppressed by unit_b's later activation
			local suppressed = TeamCooldown.is_suppressed(unit_a, "psyker_shout", 15)
			assert.is_true(suppressed)
			-- unit_b should NOT be suppressed (it's the recorder)
			local suppressed_b = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 15)
			assert.is_false(suppressed_b)
		end)
	end)

	describe("unknown templates", function()
		it("passes through unsuppressed for templates not in the category map", function()
			TeamCooldown.record(unit_a, "some_unknown_template", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "some_unknown_template", 10.5)
			assert.is_false(suppressed)
		end)
	end)

	describe("emergency overrides", function()
		it("bypasses suppression for psyker_shout_high_peril", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 11, "psyker_shout_high_peril")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for veteran_stealth_critical_toughness", function()
			TeamCooldown.record(unit_a, "veteran_stealth_combat_ability", 10)
			local suppressed =
				TeamCooldown.is_suppressed(unit_b, "veteran_stealth_combat_ability", 11, "veteran_stealth_critical_toughness")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for zealot_stealth_emergency", function()
			TeamCooldown.record(unit_a, "zealot_invisibility", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_invisibility", 11, "zealot_stealth_emergency")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for ogryn_charge_escape", function()
			TeamCooldown.record(unit_a, "ogryn_charge", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_charge", 11, "ogryn_charge_escape")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for any rule containing _rescue", function()
			TeamCooldown.record(unit_a, "zealot_dash", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "zealot_dash", 11, "zealot_dash_rescue")
			assert.is_false(suppressed)
		end)

		it("bypasses suppression for adamant_charge_rescue", function()
			TeamCooldown.record(unit_a, "adamant_charge", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "adamant_charge", 11, "adamant_charge_rescue")
			assert.is_false(suppressed)
		end)

		it("does NOT bypass for non-emergency rules", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "psyker_shout", 11, "psyker_shout_surrounded")
			assert.is_true(suppressed)
		end)
	end)

	describe("grenade category", function()
		it("suppresses different grenade templates in the same category", function()
			TeamCooldown.record_grenade(unit_a, "frag_grenade", 10)
			local suppressed = TeamCooldown.is_grenade_suppressed(unit_b, "krak_grenade", 11)
			assert.is_true(suppressed)
		end)

		it("suppresses psyker blitz as grenade category", function()
			TeamCooldown.record_grenade(unit_a, "psyker_chain_lightning", 10)
			local suppressed = TeamCooldown.is_grenade_suppressed(unit_b, "psyker_smite", 11)
			assert.is_true(suppressed)
		end)

		it("does not cross-suppress grenades with combat abilities", function()
			TeamCooldown.record_grenade(unit_a, "frag_grenade", 10)
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 11)
			assert.is_false(suppressed)
		end)

		it("never suppresses the same bot for grenades", function()
			TeamCooldown.record_grenade(unit_a, "frag_grenade", 10)
			local suppressed = TeamCooldown.is_grenade_suppressed(unit_a, "frag_grenade", 10.5)
			assert.is_false(suppressed)
		end)
	end)

	describe("suppression windows per category", function()
		it("taunt window is 8s", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 17.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 18.1))
		end)

		it("aoe_shout window is 6s", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "psyker_shout", 15.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "psyker_shout", 16.1))
		end)

		it("dash window is 4s", function()
			TeamCooldown.record(unit_a, "zealot_dash", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "zealot_dash", 13.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "zealot_dash", 14.1))
		end)

		it("stance window is 2s", function()
			TeamCooldown.record(unit_a, "psyker_overcharge_stance", 10)
			assert.is_true(TeamCooldown.is_suppressed(unit_b, "psyker_overcharge_stance", 11.9))
			assert.is_false(TeamCooldown.is_suppressed(unit_b, "psyker_overcharge_stance", 12.1))
		end)

		it("grenade window is 3s", function()
			TeamCooldown.record_grenade(unit_a, "frag_grenade", 10)
			assert.is_true(TeamCooldown.is_grenade_suppressed(unit_b, "krak_grenade", 12.9))
			assert.is_false(TeamCooldown.is_grenade_suppressed(unit_b, "krak_grenade", 13.1))
		end)
	end)

	describe("reset", function()
		it("clears all state", function()
			TeamCooldown.record(unit_a, "ogryn_taunt_shout", 10)
			TeamCooldown.reset()
			local suppressed = TeamCooldown.is_suppressed(unit_b, "ogryn_taunt_shout", 10.5)
			assert.is_false(suppressed)
		end)
	end)

	describe("three bots", function()
		it("third bot is suppressed by second bot after first window expires", function()
			TeamCooldown.record(unit_a, "psyker_shout", 10)
			TeamCooldown.record(unit_b, "psyker_shout", 17) -- after unit_a's window (6s)
			-- unit_c within unit_b's window
			local suppressed = TeamCooldown.is_suppressed(unit_c, "psyker_shout", 20)
			assert.is_true(suppressed)
			-- unit_a is also suppressed by unit_b
			local suppressed_a = TeamCooldown.is_suppressed(unit_a, "psyker_shout", 20)
			assert.is_true(suppressed_a)
		end)
	end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL — `team_cooldown` module not found

- [ ] **Step 3: Implement `team_cooldown.lua`**

```lua
-- scripts/mods/BetterBots/team_cooldown.lua
--
-- Team-level ability cooldown staggering (#14).
-- Tracks the most recent activation per ability category across all bots.
-- When a bot fires an ability, other bots in the same category are suppressed
-- for a time window. Emergency rules bypass suppression.

-- Combat ability template → category
local CATEGORY_MAP = {
	-- taunt
	ogryn_taunt_shout = "taunt",
	adamant_shout = "taunt",
	-- aoe_shout
	psyker_shout = "aoe_shout",
	-- dash
	zealot_dash = "dash",
	zealot_targeted_dash = "dash",
	zealot_targeted_dash_improved = "dash",
	zealot_targeted_dash_improved_double = "dash",
	ogryn_charge = "dash",
	ogryn_charge_increased_distance = "dash",
	adamant_charge = "dash",
	-- stance
	veteran_stealth_combat_ability = "stance",
	psyker_overcharge_stance = "stance",
	ogryn_gunlugger_stance = "stance",
	adamant_stance = "stance",
	broker_focus = "stance",
	broker_punk_rage = "stance",
}

local SUPPRESSION_WINDOW = {
	taunt = 8,
	aoe_shout = 6,
	dash = 4,
	stance = 2,
	grenade = 3,
}

local EMERGENCY_RULES = {
	psyker_shout_high_peril = true,
	veteran_stealth_critical_toughness = true,
	zealot_stealth_emergency = true,
	ogryn_charge_escape = true,
}

-- category → { unit = <unit>, fixed_t = <number> }
local _last_activation_by_category = {}

local function _resolve_category(template_name)
	local category = CATEGORY_MAP[template_name]
	if category then
		return category
	end
	-- Any template not in CATEGORY_MAP that isn't a known combat ability
	-- is treated as a grenade if it reaches this module. The caller
	-- (BetterBots.lua) calls record() for both combat_ability and
	-- grenade_ability charge events, so unknown combat templates just
	-- pass through (nil category = no suppression).
	return nil
end

local function _is_emergency(rule)
	if not rule then
		return false
	end
	if EMERGENCY_RULES[rule] then
		return true
	end
	if string.find(rule, "_rescue", 1, true) then
		return true
	end
	return false
end

local function record(unit, template_name, fixed_t)
	local category = _resolve_category(template_name)
	if not category then
		return
	end
	_last_activation_by_category[category] = {
		unit = unit,
		fixed_t = fixed_t,
	}
end

local function record_grenade(unit, grenade_name, fixed_t)
	_last_activation_by_category.grenade = {
		unit = unit,
		fixed_t = fixed_t,
	}
end

local function is_suppressed(unit, template_name, fixed_t, rule)
	if _is_emergency(rule) then
		return false, nil
	end

	local category = _resolve_category(template_name)
	if not category then
		return false, nil
	end

	local last = _last_activation_by_category[category]
	if not last then
		return false, nil
	end

	if last.unit == unit then
		return false, nil
	end

	local window = SUPPRESSION_WINDOW[category]
	if not window then
		return false, nil
	end

	if fixed_t - last.fixed_t < window then
		return true, "team_cd:" .. category
	end

	return false, nil
end

local function is_grenade_suppressed(unit, grenade_name, fixed_t, rule)
	if _is_emergency(rule) then
		return false, nil
	end

	local last = _last_activation_by_category.grenade
	if not last then
		return false, nil
	end

	if last.unit == unit then
		return false, nil
	end

	local window = SUPPRESSION_WINDOW.grenade
	if fixed_t - last.fixed_t < window then
		return true, "team_cd:grenade"
	end

	return false, nil
end

local function reset()
	for k in pairs(_last_activation_by_category) do
		_last_activation_by_category[k] = nil
	end
end

return {
	record = record,
	record_grenade = record_grenade,
	is_suppressed = is_suppressed,
	is_grenade_suppressed = is_grenade_suppressed,
	reset = reset,
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/team_cooldown.lua tests/team_cooldown_spec.lua
git commit -m "feat(team-cooldown): add team cooldown staggering module with tests (#14)"
```

---

### Task 2: Integrate recording into `BetterBots.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

The `use_ability_charge` hook already fires for all bots (line 734). We add `TeamCooldown.record()` calls at the two existing write points.

- [ ] **Step 1: Load the module at top of `BetterBots.lua`**

After the existing module loads (around line 6, near `SharedRules`), add:

```lua
local TeamCooldown = mod:io_dofile("BetterBots/scripts/mods/BetterBots/team_cooldown")
```

- [ ] **Step 2: Add `TeamCooldown.record()` for combat abilities**

In the `use_ability_charge` hook, after the existing `_last_charge_event_by_unit[unit]` write (line ~784), add:

```lua
			TeamCooldown.record(unit, ability_name, fixed_t)
```

This goes right after the closing `}` of the `_last_charge_event_by_unit[unit] = { ... }` block (before the `EventLog.is_enabled()` check).

- [ ] **Step 3: Add `TeamCooldown.record_grenade()` for grenades**

In the grenade branch of the same hook, after `GrenadeFallback.record_charge_event(unit, grenade_name, _fixed_time())` (line ~754), add:

```lua
				TeamCooldown.record_grenade(unit, grenade_name, _fixed_time())
```

- [ ] **Step 4: Add `TeamCooldown.reset()` to `on_game_state_changed`**

In `mod.on_game_state_changed` (line ~1033), inside the `status == "enter" and state == "GameplayStateRun"` block, after `BotProfiles.reset()` (line ~1037), add:

```lua
		TeamCooldown.reset()
```

- [ ] **Step 5: Wire TeamCooldown into ConditionPatch and GrenadeFallback**

In the `ConditionPatch.wire({...})` call (line ~484), add:

```lua
	TeamCooldown = TeamCooldown,
```

In the `GrenadeFallback.wire({...})` call (line ~503), add:

```lua
	TeamCooldown = TeamCooldown,
```

- [ ] **Step 6: Run tests to verify nothing broke**

Run: `make test`
Expected: ALL PASS (existing tests unaffected, team_cooldown tests still pass)

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(team-cooldown): wire recording into use_ability_charge hook (#14)"
```

---

### Task 3: Integrate suppression check into `condition_patch.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/condition_patch.lua`

- [ ] **Step 1: Add module-local variable for TeamCooldown**

At the top of `condition_patch.lua`, after the existing module-local declarations (around line 15), add:

```lua
local _TeamCooldown
```

- [ ] **Step 2: Receive TeamCooldown in `wire()`**

In the `wire` function of condition_patch's return table, add:

```lua
		_TeamCooldown = refs.TeamCooldown
```

Find the wire function by searching for `wire = function(refs)` in condition_patch.lua.

- [ ] **Step 3: Add suppression check after `resolve_decision` returns true**

In `_can_activate_ability`, after the `resolve_decision` call and the rescue intent block (after line ~272), add the team cooldown check before the `_Debug.log_ability_decision` call:

```lua
	if can_activate and _TeamCooldown then
		local team_suppressed, team_reason = _TeamCooldown.is_suppressed(unit, ability_template_name, fixed_t, rule)
		if team_suppressed then
			if _debug_enabled() then
				_debug_log(
					"team_cd:" .. ability_template_name .. ":" .. tostring(unit),
					fixed_t,
					"suppressed " .. ability_template_name .. " (" .. tostring(team_reason) .. ")"
				)
			end
			can_activate = false
			rule = "team_cooldown_suppressed"
		end
	end
```

This goes between the rescue intent block (lines 266-272) and the `_Debug.log_ability_decision` call (line 274).

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `make test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/condition_patch.lua
git commit -m "feat(team-cooldown): add suppression gate to condition_patch (#14)"
```

---

### Task 4: Integrate suppression check into `grenade_fallback.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`

- [ ] **Step 1: Add module-local variable for TeamCooldown**

At the top of `grenade_fallback.lua`, near the other module-local wire variables, add:

```lua
local _TeamCooldown
```

- [ ] **Step 2: Receive TeamCooldown in `wire()`**

In the `wire` function of grenade_fallback's return table, add:

```lua
		_TeamCooldown = refs.TeamCooldown
```

Find the wire function by searching for `wire = function(refs)` in grenade_fallback.lua.

- [ ] **Step 3: Add suppression check after grenade heuristic returns true**

In the `try_queue` function, after the heuristic check succeeds (`should_throw` is true, around line 995), add the team cooldown check before the `_resolve_template_entry` call (line 997):

```lua
	if _TeamCooldown then
		local team_suppressed, team_reason = _TeamCooldown.is_grenade_suppressed(unit, grenade_name, fixed_t, rule)
		if team_suppressed then
			if _debug_enabled() then
				_debug_log(
					"team_cd:" .. grenade_name .. ":" .. tostring(unit),
					fixed_t,
					"grenade suppressed " .. grenade_name .. " (" .. tostring(team_reason) .. ")"
				)
			end
			return
		end
	end
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `make test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua
git commit -m "feat(team-cooldown): add grenade suppression gate to grenade_fallback (#14)"
```

---

### Task 5: Update docs and run full quality gate

**Files:**
- Modify: `AGENTS.md` (mod file structure section — add `team_cooldown.lua` entry)
- Modify: `docs/dev/architecture.md` (add team_cooldown module description, if module listing exists)

- [ ] **Step 1: Add `team_cooldown.lua` to the mod file structure in `AGENTS.md`**

In the `## Mod file structure` section, add an entry for `team_cooldown.lua` in alphabetical order among the module files:

```
  team_cooldown.lua                          # Team-level ability cooldown staggering (#14)
```

And add a test entry:

```
  team_cooldown_spec.lua                     # team cooldown suppression, windows, emergency overrides
```

- [ ] **Step 2: Run `make check` (full quality gate)**

Run: `make check`
Expected: ALL PASS (format + lint + lsp + test)

- [ ] **Step 3: Fix any lint/format issues**

Run: `make format` if StyLua reports issues.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add team_cooldown module to file structure (#14)"
```

- [ ] **Step 5: Run `make check` one final time**

Run: `make check`
Expected: ALL PASS
