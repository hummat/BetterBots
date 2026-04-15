# Grenade Pickup Heuristic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let charge-based bots pick up `small_grenade` refills through the existing vanilla pickup lane while deferring grenade refills to humans and preserving current ammo behavior.

**Architecture:** Extend `ammo_policy.lua` instead of adding a new pickup module. Keep vanilla bot-group scan untouched, then layer grenade arbitration after the current ammo decision by reusing `pickup_component.ammo_pickup`. Add grenade-specific thresholds in settings/UI, extend `ammo_policy_spec.lua`, and update docs/counts after tests pass.

**Tech Stack:** Lua, DMF hooks, busted, Stylua/Luacheck/LuaLS via project `make` targets.

---

## File map

- Modify: `scripts/mods/BetterBots/ammo_policy.lua`
  - Add grenade eligibility helpers, human grenade reserve cache, nearby grenade candidate lookup, and ammo-vs-grenade arbitration.
- Modify: `scripts/mods/BetterBots/settings.lua`
  - Add default values and getters for grenade pickup thresholds.
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
  - Add two numeric settings in the pickup-policy UI block.
- Modify: `tests/ammo_policy_spec.lua`
  - Add focused grenade-pickup tests beside existing ammo-policy coverage.
- Modify: `docs/dev/architecture.md`
  - Mention that `ammo_policy.lua` now arbitrates ammo and grenade pickups via shared vanilla slot.
- Modify: `docs/dev/roadmap.md`
  - Mark `#89` implemented/closed in v0.11.0 batch section when done.
- Modify: `docs/dev/status.md`
  - Add `#89` to implemented items in v0.11.0 snapshot.
- Modify: `README.md`
  - Update highlights/module summary if grenade pickup behavior is called out there.
- Modify: `AGENTS.md`
  - Update module/test count text only if total module or test-file counts change. For this issue they should not.

### Task 1: Add failing grenade-pickup tests

**Files:**
- Modify: `tests/ammo_policy_spec.lua`
- Read: `scripts/mods/BetterBots/ammo_policy.lua`

- [ ] **Step 1: Inspect current ammo-policy test helpers**

Run:
```bash
sed -n '1,260p' tests/ammo_policy_spec.lua
```
Expected: existing `AmmoPolicy.init(...)` wiring, mock pickup component, mock ammo module, and `_update_ammo` hook tests.

- [ ] **Step 2: Add failing grenade-pickup coverage**

Append tests covering these cases:

```lua
it("binds nearby grenade pickup when bot empty and humans stocked", function()
	local bot_unit = "bot_unit"
	local grenade_unit = "grenade_pickup"
	local pickup_component = {
		needs_ammo = false,
		ammo_pickup = nil,
		ammo_pickup_distance = math.huge,
		ammo_pickup_valid_until = 0,
	}
	local ability_extension = {
		remaining_ability_charges = function(_, ability_type)
			assert.equals("grenade_ability", ability_type)
			return 0
		end,
		max_ability_charges = function(_, ability_type)
			assert.equals("grenade_ability", ability_type)
			return 1
		end,
	}

	AmmoPolicy.init(make_deps({
		fixed_time = function() return 10 end,
		settings = make_settings({
			human_grenade_reserve_threshold = function() return 1.0 end,
		}),
		ability_extension = function(unit)
			return unit == bot_unit and ability_extension or nil
		end,
		nearby_grenade_pickups = function(_, unit)
			assert.equals(bot_unit, unit)
			return { grenade_unit }
		end,
		human_grenade_units = { "human_1" },
		human_grenade_state = {
			human_1 = { current = 2, max = 2 },
		},
	}))

	install_update_ammo_hook({
		_pickup_component = pickup_component,
		_side = { valid_human_units = { "human_1" } },
	})
	call_update_ammo(bot_unit)

	assert.equals(grenade_unit, pickup_component.ammo_pickup)
	assert.is_true(pickup_component.needs_ammo)
end)

it("defers grenade pickup to low-reserve human but preserves ammo decision", function()
	-- Arrange existing ammo path to allow ammo pickup first.
	-- Then make human grenade reserve low and verify grenade does not overwrite ammo slot.
end)

it("ignores grenade pickup for cooldown-only blitz users", function()
	-- `max_ability_charges("grenade_ability") == 0` should skip grenade binding.
end)

it("preserves explicit ammo pickup orders over grenade arbitration", function()
	-- Existing explicit order should early-return exactly as current behavior.
end)
```

- [ ] **Step 3: Run targeted tests to confirm failure**

Run:
```bash
make test TESTS=tests/ammo_policy_spec.lua
```
Expected: FAIL on missing grenade helper/wiring in `ammo_policy.lua`.

- [ ] **Step 4: Commit failing tests**

```bash
git add tests/ammo_policy_spec.lua
git commit -m "test(v0.11.0): cover grenade pickup policy"
```

### Task 2: Implement grenade pickup arbitration in `ammo_policy.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/ammo_policy.lua`
- Read: `scripts/mods/BetterBots/BetterBots.lua`
- Read: `../Darktide-Source-Code/scripts/extension_systems/group/bot_group.lua`
- Read: `../Darktide-Source-Code/scripts/extension_systems/ability/player_unit_ability_extension.lua`

- [ ] **Step 1: Add grenade thresholds, caches, and dependency injection points**

Add module locals near existing ammo locals:

```lua
local _ABILITY_EXTENSION
local _nearby_grenade_pickups
local _human_grenade_scan_cache = {}
local AMMO_MAX_DISTANCE = 5
local AMMO_MAX_FOLLOW_DISTANCE = 15
```

Extend `M.init(deps)` with injectable refs:

```lua
	_ABILITY_EXTENSION = deps.ability_extension or ScriptUnit.has_extension
	_nearby_grenade_pickups = deps.nearby_grenade_pickups
	_human_grenade_scan_cache = {}
```

Add threshold helper:

```lua
local function _human_grenade_threshold()
	return (_Settings and _Settings.human_grenade_reserve_threshold and _Settings.human_grenade_reserve_threshold()) or 1
end
```

- [ ] **Step 2: Add grenade state helpers**

Add focused helpers:

```lua
local function _grenade_charge_state(unit)
	local ability_extension = _ABILITY_EXTENSION and _ABILITY_EXTENSION(unit, "ability_system")
	if not ability_extension then
		return nil
	end

	local max_charges = ability_extension:max_ability_charges("grenade_ability")
	if max_charges <= 0 then
		return {
			current = 0,
			max = 0,
		}
	end

	return {
		current = ability_extension:remaining_ability_charges("grenade_ability"),
		max = max_charges,
	}
end

local function _eligible_for_grenade_pickup(unit)
	local state = _grenade_charge_state(unit)
	return state ~= nil and state.max > 0, state
end
```

Add cached human scan parallel to ammo cache:

```lua
local function _all_eligible_humans_above_grenade_threshold(human_units, threshold)
	local fixed_t = _fixed_time and _fixed_time() or 0
	if _human_grenade_scan_cache.fixed_t == fixed_t
		and _human_grenade_scan_cache.human_units == human_units
		and _human_grenade_scan_cache.threshold == threshold then
		return _human_grenade_scan_cache.result
	end

	for i = 1, #human_units do
		local human_unit = human_units[i]
		local eligible, state = _eligible_for_grenade_pickup(human_unit)
		if eligible then
			local fraction = state.max > 0 and (state.current / state.max) or 1
			if fraction < threshold then
				_human_grenade_scan_cache = {
					fixed_t = fixed_t,
					human_units = human_units,
					threshold = threshold,
					result = false,
				}
				return false
			end
		end
	end

	_human_grenade_scan_cache = {
		fixed_t = fixed_t,
		human_units = human_units,
		threshold = threshold,
		result = true,
	}
	return true
end
```

- [ ] **Step 3: Add nearby grenade candidate lookup**

Implement a helper with injectable fast path for tests and vanilla-distance fallback for runtime:

```lua
local function _best_nearby_grenade_pickup(self, unit)
	if _nearby_grenade_pickups then
		return _nearby_grenade_pickups(self, unit)
	end

	local pickup_system = Managers.state.extension:system("pickup_system")
	local pickups = pickup_system and pickup_system._pickup_units
	local bot_position = POSITION_LOOKUP[unit]
	local follow_position = self._bot_group and self._bot_group._bot_data and self._bot_group._bot_data[unit] and self._bot_group._bot_data[unit].follow_position
	local best_unit, best_distance

	if not (pickups and bot_position) then
		return nil
	end

	for pickup_unit, _ in pairs(pickups) do
		local pickup_name = Unit.get_data(pickup_unit, "pickup_type")
		if pickup_name == "small_grenade" then
			local pickup_position = POSITION_LOOKUP[pickup_unit]
			if pickup_position then
				local distance = Vector3.distance(bot_position, pickup_position)
				local follow_distance = follow_position and Vector3.distance(follow_position, pickup_position) or math.huge
				if distance < AMMO_MAX_DISTANCE or follow_distance < AMMO_MAX_FOLLOW_DISTANCE then
					if not best_distance or distance < best_distance then
						best_unit = pickup_unit
						best_distance = distance
					end
				end
			end
		end
	end

	return best_unit, best_distance
end
```

If actual pickup-system field differs, adjust after reading live source. Do not guess silently.

- [ ] **Step 4: Add grenade arbitration after existing ammo logic**

Inside `_update_ammo` hook, after existing ammo decision and before perf finish, add:

```lua
	local eligible_for_grenade, grenade_state = _eligible_for_grenade_pickup(unit)
	if not eligible_for_grenade then
		_log("grenade_pickup_skip_ineligible:" .. tostring(unit), "grenade pickup skipped: no charge-based grenade ability")
		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
		return
	end

	if grenade_state.current > _bot_grenade_threshold() then
		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
		return
	end

	local grenade_pickup, grenade_distance = _best_nearby_grenade_pickup(self, unit)
	if not grenade_pickup then
		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
		return
	end

	local humans_ok_for_grenade = _all_eligible_humans_above_grenade_threshold(
		self._side and self._side.valid_human_units,
		_human_grenade_threshold()
	)

	if not humans_ok_for_grenade then
		_log("grenade_pickup_defer:" .. tostring(unit), "grenade pickup deferred to human reserve")
		if perf_t0 then
			_perf.finish("ammo_policy.update_ammo", perf_t0)
		end
		return
	end

	pickup_component.ammo_pickup = grenade_pickup
	pickup_component.ammo_pickup_distance = grenade_distance or 0
	pickup_component.ammo_pickup_valid_until = (_fixed_time and _fixed_time() or 0) + 5
	pickup_component.needs_ammo = true
	_log("grenade_pickup_allow:" .. tostring(unit), "grenade pickup permitted: eligible humans stocked")
	_log("grenade_pickup_bind:" .. tostring(unit), "grenade pickup bound into ammo slot")
```

Keep explicit ammo-pickup order early return unchanged.

- [ ] **Step 5: Run targeted tests and iterate until green**

Run:
```bash
make test TESTS=tests/ammo_policy_spec.lua
```
Expected: PASS.

- [ ] **Step 6: Commit implementation**

```bash
git add scripts/mods/BetterBots/ammo_policy.lua tests/ammo_policy_spec.lua
git commit -m "feat(v0.11.0): add grenade pickup policy"
```

### Task 3: Add settings and UI wiring

**Files:**
- Modify: `scripts/mods/BetterBots/settings.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Test: `tests/settings_spec.lua`

- [ ] **Step 1: Add default values and getters in `settings.lua`**

Add setting IDs/defaults near existing ammo policy settings:

```lua
local HUMAN_GRENADE_RESERVE_THRESHOLD_SETTING_ID = "bot_human_grenade_reserve_threshold"
```

Add defaults:

```lua
	bot_human_grenade_reserve_threshold = 100,
```

Add getter:

```lua
function M.human_grenade_reserve_threshold()
	return _number_setting(HUMAN_GRENADE_RESERVE_THRESHOLD_SETTING_ID, DEFAULTS.bot_human_grenade_reserve_threshold) / 100
end
```

Use project’s actual helper naming/style if `_number_setting` already differs.

- [ ] **Step 2: Expose settings in `BetterBots_data.lua`**

Add one numeric widget in pickup settings block beside ammo settings:

```lua
					make_numeric("bot_human_grenade_reserve_threshold", { 0, 100 }, 5),
```

If existing labels/localization are required, add matching localization entries in same task instead of leaving broken IDs.

- [ ] **Step 3: Add or extend settings tests**

Add focused assertions in `tests/settings_spec.lua`:

```lua
it("returns human grenade reserve threshold from settings", function()
	mod:get = function(_, id)
		if id == "bot_human_grenade_reserve_threshold" then
			return 100
		end
	end

	assert.equals(1.0, Settings.human_grenade_reserve_threshold())
end)
```

- [ ] **Step 4: Run focused settings tests**

Run:
```bash
make test TESTS=tests/settings_spec.lua
```
Expected: PASS.

- [ ] **Step 5: Commit settings wiring**

```bash
git add scripts/mods/BetterBots/settings.lua scripts/mods/BetterBots/BetterBots_data.lua tests/settings_spec.lua
if rg -n "bot_human_grenade_reserve_threshold" scripts/mods/BetterBots/BetterBots_localization.lua >/dev/null; then
  git add scripts/mods/BetterBots/BetterBots_localization.lua
fi
git commit -m "feat(v0.11.0): add grenade pickup settings"
```

### Task 4: Update docs and run full verification

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `README.md`
- Modify: `AGENTS.md` (only if doc-check requires it)

- [ ] **Step 1: Update architecture and planning docs**

Make these concrete edits:

- `docs/dev/architecture.md`
  - update `ammo_policy.lua` description from ammo-only to ammo + grenade pickup arbitration
- `docs/dev/roadmap.md`
  - move `#89` out of open v0.11.0 backlog into implemented/closed state
- `docs/dev/status.md`
  - mark `#89` implemented in v0.11.0 snapshot
- `README.md`
  - add grenade pickup policy mention only if pickup policies are already summarized there
- `AGENTS.md`
  - update only if test counts or file inventory text changed materially; they should not for this issue

- [ ] **Step 2: Run targeted and full verification**

Run:
```bash
make test TESTS=tests/ammo_policy_spec.lua
make test TESTS=tests/settings_spec.lua
make test
make doc-check
```
Expected:
- targeted specs PASS
- full suite PASS
- `make doc-check` PASS

- [ ] **Step 3: Fix any doc-count drift revealed by `make doc-check`**

If `make doc-check` fails on stale issue tables or counts, update the named files and rerun:

```bash
make doc-check
```
Expected: PASS.

- [ ] **Step 4: Commit docs + final verification state**

```bash
git add docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md README.md AGENTS.md
if git diff --cached --quiet; then
  echo "No doc changes staged"
else
  git commit -m "docs(v0.11.0): document grenade pickup policy"
fi
```

### Task 5: Final integration checkpoint

**Files:**
- Inspect only

- [ ] **Step 1: Review final diff**

Run:
```bash
git status --short
git diff --stat HEAD~3..HEAD
```
Expected: only `#89` code/tests/docs commits in working tree, no stray edits.

- [ ] **Step 2: Record acceptance evidence**

Capture final verification commands/results in handoff note or final response:

```text
make test TESTS=tests/ammo_policy_spec.lua  -> PASS
make test TESTS=tests/settings_spec.lua     -> PASS
make test                                   -> PASS
make doc-check                              -> PASS
```

- [ ] **Step 3: Commit any leftover fixup if needed**

```bash
git add -A
git commit -m "fix(v0.11.0): tighten grenade pickup edge cases"
```

Only do this if verification forced a real code/doc fix after prior commits.

---

## Self-review

- Spec coverage: covered source constraints, ammo-slot piggyback approach, human-first defer rule, settings, logging, tests, docs, and final verification.
- Placeholder scan: removed vague implementation language except one explicit note to adjust pickup-system field only after reading source; that is intentional because source name must be verified before coding.
- Type consistency: setting IDs, getter names, and grenade ability API names match spec text.
