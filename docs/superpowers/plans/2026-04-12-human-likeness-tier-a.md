# Human-Likeness Tier A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bots feel less robotic by adding combat-ability activation jitter, reducing opportunity-target reaction times, and restoring challenge-aware melee engage conservatism.

**Architecture:** Add a focused `human_likeness.lua` module that owns Tier A tuning constants and helper logic, then wire it into the existing queue and leash modules. Keep heuristics pure; timing stays in `ability_queue.lua`, pressure-based chase scaling stays in `engagement_leash.lua`, and reaction-time tuning patches the loaded `BotSettings` singleton.

**Tech Stack:** Lua, busted, BetterBots module wiring, Darktide bot settings and melee/action hooks

---

## File Map

- Create: `scripts/mods/BetterBots/human_likeness.lua`
  - patch `BotSettings.opportunity_target_reaction_times`
  - classify emergency rules for jitter bypass
  - compute jitter delay and challenge-pressure leash scaling
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
  - add pending jitter state for combat abilities
  - clear/apply delayed queueing
- Modify: `scripts/mods/BetterBots/engagement_leash.lua`
  - shrink BetterBots leash under high challenge pressure
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
  - load and wire `human_likeness.lua`
  - patch bot settings on startup
- Create: `tests/human_likeness_spec.lua`
  - unit tests for settings patch, bypass classification, leash scaling
- Modify: `tests/ability_queue_spec.lua`
  - jitter scheduling/bypass/cancel tests
- Modify: `tests/engagement_leash_spec.lua`
  - challenge-pressure leash tests
- Modify: `README.md`
  - update test count if needed after new spec file lands
- Modify: `AGENTS.md`
  - update `make test` count and test list if new spec file lands
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`

### Task 1: Add Failing Human-Likeness Unit Tests

**Files:**
- Create: `tests/human_likeness_spec.lua`
- Modify: `tests/ability_queue_spec.lua`
- Modify: `tests/engagement_leash_spec.lua`

- [ ] **Step 1: Write failing tests for the new helper module**

Create `tests/human_likeness_spec.lua` with:

```lua
local HumanLikeness = dofile("scripts/mods/BetterBots/human_likeness.lua")

describe("human_likeness", function()
	it("patches opportunity target reaction times to 2-5", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({})
		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(2, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(5, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("treats rescue and panic style rules as jitter bypass", function()
		HumanLikeness.init({})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("ogryn_charge_ally_aid"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("zealot_relic_panic"))
		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_hazard"))
		assert.is_false(HumanLikeness.should_bypass_ability_jitter("veteran_shout_mixed_pack"))
	end)

	it("shrinks leash only when challenge pressure rises", function()
		HumanLikeness.init({})

		assert.equals(20, HumanLikeness.scale_engage_leash(20, 0))
		assert.is_true(HumanLikeness.scale_engage_leash(20, 20) < 20)
		assert.equals(10, HumanLikeness.scale_engage_leash(20, 30))
	end)
end)
```

- [ ] **Step 2: Write failing ability-queue jitter tests**

Append to `tests/ability_queue_spec.lua`:

```lua
	describe("combat ability jitter", function()
		it("schedules delayed queueing for non-emergency rules", function()
			local queued_inputs = 0
			local fixed_t = 10
			local state_by_unit = {}
			local action_input_extension = {
				bot_queue_action_input = function()
					queued_inputs = queued_inputs + 1
				end,
				_action_input_parsers = {
					combat_ability_action = {
						_ACTION_INPUT_SEQUENCE_CONFIGS = {
							psyker_shout = {
								shout_pressed = {},
							},
						},
					},
				},
			}
			local ability_extension = {
				can_use_ability = function()
					return true
				end,
				action_input_is_currently_valid = function()
					return true
				end,
			}
			local unit_data_extension = {
				read_component = function(_, component_name)
					if component_name == "combat_ability_action" then
						return { template_name = "psyker_shout" }
					end
				end,
			}

			local saved_script_unit = _G.ScriptUnit
			local saved_require = require
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
					return {
						psyker_shout = {
							ability_meta_data = {
								activation = { action_input = "shout_pressed" },
							},
						},
					}
				end
				return saved_require(path)
			end)

			AbilityQueue.init({
				mod = { echo = function() end, dump = function() end },
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return fixed_t
				end,
				equipped_combat_ability = function()
					return ability_extension, { name = "psyker_shout" }
				end,
				equipped_combat_ability_name = function()
					return "psyker_shout"
				end,
				is_suppressed = function()
					return false
				end,
				fallback_state_by_unit = state_by_unit,
				fallback_queue_dumped_by_key = {},
				DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
				shared_rules = SharedRules,
			})
			AbilityQueue.wire({
				Heuristics = {
					resolve_decision = function()
						return true, "psyker_shout_mixed_pack", {}
					end,
				},
				MetaData = { inject = function() end },
				ItemFallback = {
					try_queue_item = function() end,
					reset_item_sequence_state = function() end,
				},
				Debug = {
					bot_slot_for_unit = function()
						return 1
					end,
					context_snapshot = function(context)
						return context
					end,
					fallback_state_snapshot = function(state)
						return state
					end,
				},
				EventLog = { is_enabled = function() return false end },
				EngagementLeash = { is_movement_ability = function() return false end },
				TeamCooldown = { is_suppressed = function() return false end },
				CombatAbilityIdentity = { resolve = function() return nil end },
				HumanLikeness = {
					should_bypass_ability_jitter = function()
						return false
					end,
					random_ability_jitter_delay = function()
						return 1.0
					end,
				},
				is_combat_template_enabled = function()
					return true
				end,
			})

			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(0, queued_inputs)
			assert.equals(11, state_by_unit.bot_unit.pending_ready_t)

			fixed_t = 11
			AbilityQueue.try_queue("bot_unit", {})
			assert.equals(1, queued_inputs)

			_G.ScriptUnit = saved_script_unit
			rawset(_G, "require", saved_require)
		end)
	end)
```

- [ ] **Step 3: Write failing engage-leash pressure tests**

Append to `tests/engagement_leash_spec.lua`:

```lua
	describe("challenge pressure scaling", function()
		it("shrinks leash under higher challenge pressure", function()
			local HumanLikeness = {
				scale_engage_leash = function(leash, pressure)
					if pressure >= 30 then
						return leash * 0.5
					end
					return leash
				end,
			}

			EngagementLeash.init({
				debug_log = function() end,
				debug_enabled = function()
					return false
				end,
				fixed_time = function()
					return 0
				end,
				perf = nil,
				is_enabled = function()
					return true
				end,
				HumanLikeness = HumanLikeness,
				Heuristics = {
					build_context = function()
						return { challenge_rating_sum = 30 }
					end,
				},
			})

			local leash, _ = EngagementLeash.compute_effective_leash(make_unit("bot"), nil, make_breed(), false, 0)
			assert.equals(6, leash)
		end)
	end)
```

- [ ] **Step 4: Run focused failing tests**

Run:

```bash
make test TESTS=tests/human_likeness_spec.lua
make test TESTS=tests/ability_queue_spec.lua
make test TESTS=tests/engagement_leash_spec.lua
```

Expected:
- `human_likeness_spec.lua` fails because file/functions do not exist
- queue/leash specs fail on missing jitter/scaling behavior

### Task 2: Implement `human_likeness.lua`

**Files:**
- Create: `scripts/mods/BetterBots/human_likeness.lua`
- Test: `tests/human_likeness_spec.lua`

- [ ] **Step 1: Create the helper module**

Create `scripts/mods/BetterBots/human_likeness.lua`:

```lua
local M = {}

local OPPORTUNITY_REACTION_MIN = 2
local OPPORTUNITY_REACTION_MAX = 5
local ABILITY_JITTER_MIN_S = 0.3
local ABILITY_JITTER_MAX_S = 1.5
local START_CHALLENGE_VALUE = 10
local MAX_CHALLENGE_VALUE = 30
local MIN_LEASH_FLOOR = 6

local _patched_bot_settings = setmetatable({}, { __mode = "k" })

local function _contains(haystack, needle)
	return haystack and string.find(haystack, needle, 1, true) ~= nil
end

function M.init(_) end

function M.patch_bot_settings(bot_settings)
	if not bot_settings or _patched_bot_settings[bot_settings] then
		return
	end

	local times = bot_settings.opportunity_target_reaction_times
	local normal = times and times.normal
	if normal then
		normal.min = OPPORTUNITY_REACTION_MIN
		normal.max = OPPORTUNITY_REACTION_MAX
	end

	_patched_bot_settings[bot_settings] = true
end

function M.should_bypass_ability_jitter(rule)
	if not rule then
		return false
	end

	return _contains(rule, "ally_aid")
		or _contains(rule, "panic")
		or _contains(rule, "last_stand")
		or _contains(rule, "hazard")
end

function M.random_ability_jitter_delay()
	return math.lerp(ABILITY_JITTER_MIN_S, ABILITY_JITTER_MAX_S, math.random())
end

function M.scale_engage_leash(effective_leash, challenge_rating_sum)
	local lerp_t = (challenge_rating_sum - START_CHALLENGE_VALUE) / (MAX_CHALLENGE_VALUE - START_CHALLENGE_VALUE)

	if lerp_t <= 0 then
		return effective_leash
	end

	local challenge_leash = math.max(MIN_LEASH_FLOOR, effective_leash * 0.5)
	if lerp_t >= 1 then
		return challenge_leash
	end

	return math.lerp(effective_leash, challenge_leash, lerp_t * lerp_t)
end

return M
```

- [ ] **Step 2: Run helper-module tests**

Run:

```bash
make test TESTS=tests/human_likeness_spec.lua
```

Expected: PASS

### Task 3: Wire Human-Likeness Into Bot Startup

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Test: `tests/human_likeness_spec.lua`

- [ ] **Step 1: Load and wire the module**

Add near other module loads:

```lua
local HumanLikeness = mod:io_dofile("BetterBots/scripts/mods/BetterBots/human_likeness")
assert(HumanLikeness, "BetterBots: failed to load human_likeness module")
```

Pass it in `AbilityQueue.wire({...})` and `EngagementLeash.init({...})` / `wire` paths.

- [ ] **Step 2: Patch BotSettings on load**

Add a `hook_require` block or startup mutation:

```lua
mod:hook_require("scripts/settings/bot/bot_settings", function(BotSettings)
	HumanLikeness.patch_bot_settings(BotSettings)
end)
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
make test TESTS=tests/human_likeness_spec.lua
```

Expected: PASS

### Task 4: Add Combat-Ability Jitter To `ability_queue.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
- Modify: `tests/ability_queue_spec.lua`

- [ ] **Step 1: Extend module dependencies**

Add local dependency slot:

```lua
local _HumanLikeness
```

Wire it:

```lua
	_HumanLikeness = deps.HumanLikeness
```

- [ ] **Step 2: Add pending-jitter state helpers**

Near the top of the file:

```lua
local function _clear_pending_jitter(state)
	state.pending_rule = nil
	state.pending_template_name = nil
	state.pending_action_input = nil
	state.pending_ready_t = nil
end
```

- [ ] **Step 3: Apply jitter before queueing**

Insert after team-cooldown suppression and before rescue-aim / queue call:

```lua
	local bypass_jitter = _HumanLikeness and _HumanLikeness.should_bypass_ability_jitter(rule)

	if not bypass_jitter and _HumanLikeness then
		local pending_matches = state.pending_rule == rule
			and state.pending_template_name == ability_template_name
			and state.pending_action_input == action_input

		if not pending_matches then
			state.pending_rule = rule
			state.pending_template_name = ability_template_name
			state.pending_action_input = action_input
			state.pending_ready_t = fixed_t + _HumanLikeness.random_ability_jitter_delay()
			return
		end

		if fixed_t < state.pending_ready_t then
			return
		end
	end
```

Then clear pending state just before actual queue:

```lua
	_clear_pending_jitter(state)
	action_input_extension:bot_queue_action_input(ability_component_name, action_input, nil)
```

Also clear pending state on false decision paths:

```lua
		_clear_pending_jitter(state)
```

- [ ] **Step 4: Run focused queue tests**

Run:

```bash
make test TESTS=tests/ability_queue_spec.lua
```

Expected: PASS

### Task 5: Restore Challenge-Aware Pressure Shrink In `engagement_leash.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/engagement_leash.lua`
- Modify: `tests/engagement_leash_spec.lua`

- [ ] **Step 1: Add module dependencies**

Add locals:

```lua
local _HumanLikeness
local _Heuristics
```

Wire in `init(deps)`:

```lua
	_HumanLikeness = deps.HumanLikeness
	_Heuristics = deps.Heuristics
```

- [ ] **Step 2: Apply challenge-pressure scaling**

At the end of `compute_effective_leash`, replace:

```lua
	return math.min(base, cap), "base"
```

with:

```lua
	local effective = math.min(base, cap)
	if _HumanLikeness and _Heuristics then
		local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
		local context = blackboard and _Heuristics.build_context(unit, blackboard)
		local pressure = context and context.challenge_rating_sum or 0
		effective = _HumanLikeness.scale_engage_leash(effective, pressure)
	end

	return effective, "base"
```

- [ ] **Step 3: Run focused leash tests**

Run:

```bash
make test TESTS=tests/engagement_leash_spec.lua
```

Expected: PASS

### Task 6: Update Docs And Test Counts

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Document the new module**

Add `human_likeness.lua` to architecture/module docs with:

```md
- human-likeness tuning: patches opportunity-target reaction times, adds combat-ability activation jitter, and shrinks melee leash under high challenge pressure
```

- [ ] **Step 2: Update roadmap and status**

Change `#44` entry in `docs/dev/roadmap.md` to implemented-on-branch wording.
Add matching status note in `docs/dev/status.md`.

- [ ] **Step 3: Update test count references**

Increment busted count by one spec file across `README.md` and `AGENTS.md`.

- [ ] **Step 4: Run doc check**

Run:

```bash
make doc-check
```

Expected: PASS

### Task 7: Full Verification

**Files:**
- Modify: none

- [ ] **Step 1: Run targeted human-likeness tests**

Run:

```bash
make test TESTS=tests/human_likeness_spec.lua
make test TESTS=tests/ability_queue_spec.lua
make test TESTS=tests/engagement_leash_spec.lua
```

Expected: PASS

- [ ] **Step 2: Run full suite**

Run:

```bash
make test
```

Expected: PASS

- [ ] **Step 3: Record clean branch state**

Run:

```bash
git status --short
```

Expected: only intended tracked changes remain.

## Self-Review

- Spec coverage: reaction-time patch, combat-only jitter, emergency bypass, and challenge-pressure leash scaling each have dedicated implementation + test tasks.
- Placeholder scan: all tasks include concrete code or exact commands.
- Type consistency: uses existing module init/wire pattern and existing `state` / `challenge_rating_sum` names already present in repo.
