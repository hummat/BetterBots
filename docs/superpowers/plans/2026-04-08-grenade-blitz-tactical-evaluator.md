# Grenade/Blitz Tactical Evaluator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade BetterBots grenade/blitz reasoning from coarse yes/no heuristics into a shared tactical evaluator that picks better targets, placement modes, and execution rules across direct-impact, AoE, defensive, mine, and whistle families.

**Architecture:** Keep `heuristics.lua` as the grenade entry point, but move family-specific tactical reasoning into a dedicated `grenade_tactical_evaluator.lua` module. Extend `bot_targeting.lua` with family-specific candidate resolvers, then carry a structured grenade decision object through `grenade_fallback.lua` so revalidation preserves the original tactical reason instead of recomputing a generic boolean mid-sequence.

**Tech Stack:** Lua, DMF hooks, BetterBots module wiring in `BetterBots.lua`, busted unit tests, `make test`, `make check`

---

## File Structure

**Create:**

- `scripts/mods/BetterBots/grenade_tactical_evaluator.lua`
  - Shared grenade/blitz tactical evaluator
  - Decision object construction
  - Family-specific scoring
  - Revalidation helpers for `grenade_fallback.lua`
- `tests/grenade_tactical_evaluator_spec.lua`
  - Unit tests for decision selection, placement mode, Arbites split, and revalidation helpers

**Modify:**

- `scripts/mods/BetterBots/BetterBots.lua`
  - Load/wire the new tactical evaluator module
  - Provide dependencies and cross-module references
- `scripts/mods/BetterBots/heuristics.lua`
  - Extend grenade context
  - Delegate grenade evaluation to the tactical evaluator
  - Preserve existing settings-driven profile handling
- `scripts/mods/BetterBots/bot_targeting.lua`
  - Replace flat grenade resolver with family-specific candidate resolvers
- `scripts/mods/BetterBots/grenade_fallback.lua`
  - Store grenade decision object in state
  - Revalidate against original tactical reason
  - Support limited retargeting where safe
- `tests/grenade_fallback_spec.lua`
  - Assert decision-object storage and family-specific revalidation behavior
- `tests/heuristics_spec.lua`
  - Assert grenade heuristic entry points return evaluator-backed reasons and Arbites dog/no-dog splits
- `docs/dev/architecture.md`
  - Document the tactical evaluator module and grenade decision contract
- `docs/dev/debugging.md`
  - Document new grenade debug/event signals and validation workflow
- `docs/dev/status.md`
  - Add implementation status note once complete

**Reference only:**

- `docs/superpowers/specs/2026-04-08-grenade-blitz-tactical-evaluator-design.md`
- GitHub issues `#80`, `#49`, `#22`

### Task 1: Scaffold The Tactical Evaluator Module

**Files:**
- Create: `scripts/mods/BetterBots/grenade_tactical_evaluator.lua`
- Create: `tests/grenade_tactical_evaluator_spec.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Test: `tests/grenade_tactical_evaluator_spec.lua`

- [ ] **Step 1: Write the failing evaluator-shape tests**

```lua
describe("grenade_tactical_evaluator", function()
	local Evaluator

	before_each(function()
		Evaluator = dofile("scripts/mods/BetterBots/grenade_tactical_evaluator.lua")
	end)

	it("builds a structured decision for direct-impact grenades", function()
		local decision = Evaluator.evaluate("veteran_krak_grenade", {
			target_enemy = "crusher",
			target_enemy_distance = 12,
			target_is_elite_special = true,
			target_is_super_armor = true,
			num_nearby = 1,
			preset = "balanced",
		})

		assert.is_table(decision)
		assert.equal("veteran_krak_grenade", decision.template)
		assert.equal("target_unit", decision.placement_mode)
		assert.equal("abort_on_target_loss", decision.commit_policy)
		assert.equal("priority_pick", decision.reason)
	end)

	it("splits arbites whistle behavior when the companion is missing", function()
		local decision = Evaluator.evaluate("adamant_whistle", {
			companion_unit = nil,
			target_enemy = "gunner",
			target_enemy_distance = 8,
			preset = "balanced",
		})

		assert.is_false(decision.should_activate)
		assert.equal("grenade_whistle_block_no_companion", decision.rule)
	end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL in `tests/grenade_tactical_evaluator_spec.lua` because `grenade_tactical_evaluator.lua` does not exist yet.

- [ ] **Step 3: Write the minimal evaluator skeleton**

```lua
local M = {}

local FAMILY_BY_TEMPLATE = {
	veteran_krak_grenade = "direct_impact",
	veteran_frag_grenade = "aoe_lethal",
	veteran_smoke_grenade = "aoe_control",
	adamant_shock_mine = "placeable_denial",
	adamant_whistle = "companion_command",
}

local function _decision(template, family, fields)
	return {
		should_activate = fields.should_activate == true,
		template = template,
		family = family,
		intent_score = fields.intent_score or 0,
		reason = fields.reason,
		rule = fields.rule or fields.reason,
		target_unit = fields.target_unit,
		placement_mode = fields.placement_mode,
		placement_position = fields.placement_position,
		commit_policy = fields.commit_policy or "revalidate_until_release",
		confidence = fields.confidence or "medium",
	}
end

function M.evaluate(template, context)
	local family = FAMILY_BY_TEMPLATE[template]
	if not family then
		return _decision(template, "unknown", {
			should_activate = false,
			rule = "grenade_unknown_template",
			confidence = "low",
		})
	end

	if template == "adamant_whistle" and not context.companion_unit then
		return _decision(template, family, {
			should_activate = false,
			rule = "grenade_whistle_block_no_companion",
			commit_policy = "abort_on_target_loss",
		})
	end

	if template == "veteran_krak_grenade" and context.target_enemy and context.target_enemy_distance >= 4 then
		return _decision(template, family, {
			should_activate = true,
			reason = "priority_pick",
			target_unit = context.target_enemy,
			placement_mode = "target_unit",
			commit_policy = "abort_on_target_loss",
			confidence = "high",
		})
	end

	return _decision(template, family, {
		should_activate = false,
		rule = "grenade_hold",
	})
end

return M
```

- [ ] **Step 4: Load and wire the module in `BetterBots.lua`**

```lua
local GrenadeTacticalEvaluator = mod:io_dofile("BetterBots/scripts/mods/BetterBots/grenade_tactical_evaluator")
assert(GrenadeTacticalEvaluator, "BetterBots: failed to load grenade_tactical_evaluator module")
```

```lua
GrenadeTacticalEvaluator.init({
	mod = mod,
})
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS for the new `tests/grenade_tactical_evaluator_spec.lua` coverage and no startup regression from loading the new module.

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/grenade_tactical_evaluator.lua tests/grenade_tactical_evaluator_spec.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(grenades): scaffold tactical evaluator module"
```

### Task 2: Add Family-Specific Candidate Resolvers

**Files:**
- Modify: `scripts/mods/BetterBots/bot_targeting.lua`
- Modify: `tests/grenade_tactical_evaluator_spec.lua`
- Test: `tests/grenade_tactical_evaluator_spec.lua`

- [ ] **Step 1: Write the failing candidate-resolver tests**

```lua
it("prefers cluster anchors for aoe families", function()
	local target = BotTargeting.resolve_cluster_anchor({
		target_enemy = "rager",
		priority_target_enemy = "gunner",
		opportunity_target_enemy = "trapper",
		urgent_target_enemy = nil,
	})

	assert.equal("rager", target)
end)

it("prefers priority targets for direct-impact families", function()
	local target = BotTargeting.resolve_direct_target({
		target_enemy = "rager",
		priority_target_enemy = "crusher",
		opportunity_target_enemy = "trapper",
		urgent_target_enemy = nil,
	})

	assert.equal("crusher", target)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL because `resolve_cluster_anchor` and `resolve_direct_target` do not exist.

- [ ] **Step 3: Implement explicit resolvers in `bot_targeting.lua`**

```lua
local function _first_present(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if value then
			return value
		end
	end
end

function M.resolve_direct_target(source)
	return _first_present(
		source and source.priority_target_enemy,
		source and source.opportunity_target_enemy,
		source and source.urgent_target_enemy,
		source and source.target_enemy
	)
end

function M.resolve_cluster_anchor(source)
	return _first_present(
		source and source.target_enemy,
		source and source.priority_target_enemy,
		source and source.opportunity_target_enemy,
		source and source.urgent_target_enemy
	)
end

function M.resolve_defensive_zone_target(source)
	return _first_present(
		source and source.priority_target_enemy,
		source and source.target_enemy,
		source and source.opportunity_target_enemy
	)
end

function M.resolve_companion_target(source)
	return _first_present(
		source and source.priority_target_enemy,
		source and source.opportunity_target_enemy,
		source and source.urgent_target_enemy,
		source and source.target_enemy
	)
end
```

- [ ] **Step 4: Update the evaluator to consume the new resolvers**

```lua
local target = _bot_targeting.resolve_direct_target(context)
```

```lua
local anchor = _bot_targeting.resolve_cluster_anchor(context)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS with explicit family-specific target ordering.

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/bot_targeting.lua scripts/mods/BetterBots/grenade_tactical_evaluator.lua tests/grenade_tactical_evaluator_spec.lua
git commit -m "feat(grenades): add family-specific target resolvers"
```

### Task 3: Extend Grenade Context And Delegate Heuristics

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `tests/heuristics_spec.lua`
- Modify: `tests/grenade_tactical_evaluator_spec.lua`
- Test: `tests/heuristics_spec.lua`

- [ ] **Step 1: Write the failing heuristic-delegation tests**

```lua
it("delegates adamant_shock_mine to the tactical evaluator", function()
	local ok, rule = Heuristics.evaluate_grenade_heuristic("adamant_shock_mine", {
		num_nearby = 6,
		challenge_rating_sum = 4.0,
		target_enemy = "mauler",
		preset = "balanced",
	})

	assert.is_true(ok)
	assert.equal("hold_point_denial", rule)
end)

it("keeps whistle blocked when the dog is absent even if a target exists", function()
	local ok, rule = Heuristics.evaluate_grenade_heuristic("adamant_whistle", {
		companion_unit = nil,
		target_enemy = "gunner",
		target_enemy_distance = 10,
		preset = "balanced",
	})

	assert.is_false(ok)
	assert.equal("grenade_whistle_block_no_companion", rule)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL because `evaluate_grenade_heuristic()` still returns the old hardcoded rules.

- [ ] **Step 3: Extend `build_context()` with evaluator-needed fields**

```lua
context.last_grenade_attempt_age = nil
context.last_grenade_failure_reason = nil
context.has_companion = context.companion_unit ~= nil
context.primary_direct_target = nil
context.primary_cluster_anchor = nil
context.primary_companion_target = nil
```

```lua
if _bot_targeting then
	context.primary_direct_target = _bot_targeting.resolve_direct_target(context)
	context.primary_cluster_anchor = _bot_targeting.resolve_cluster_anchor(context)
	context.primary_companion_target = _bot_targeting.resolve_companion_target(context)
end
```

- [ ] **Step 4: Delegate `evaluate_grenade_heuristic()` to the evaluator**

```lua
local decision = _grenade_tactical_evaluator.evaluate(grenade_template_name, context)
local can_activate = decision.should_activate
local rule = decision.rule or decision.reason or "grenade_hold"
return _apply_behavior_profile(can_activate, rule, context, opts), rule
```

Use the real two-value form in implementation:

```lua
local can_activate = decision.should_activate == true
local rule = decision.rule or decision.reason or "grenade_hold"
context.grenade_decision = decision
context.preset = saved_preset
return _apply_behavior_profile(can_activate, rule, context, opts)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS for `tests/heuristics_spec.lua` grenade paths while non-grenade combat heuristics remain unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua tests/grenade_tactical_evaluator_spec.lua
git commit -m "feat(grenades): delegate grenade heuristics to tactical evaluator"
```

### Task 4: Carry Decision Objects Through `grenade_fallback.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Modify: `tests/grenade_fallback_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write the failing fallback-state tests**

```lua
it("stores the tactical decision on sequence start", function()
	GrenadeFallback.try_queue(unit, blackboard)

	local state = _grenade_state_by_unit[unit]
	assert.is_table(state.decision)
	assert.equal("priority_pick", state.decision.reason)
	assert.equal("target_unit", state.decision.placement_mode)
end)

it("aborts direct-impact throws when the original target is lost", function()
	advance_to_stage("wait_aim")
	_current_decision = {
		should_activate = true,
		template = "veteran_krak_grenade",
		reason = "priority_pick",
		placement_mode = "target_unit",
		target_unit = "enemy_1",
		commit_policy = "abort_on_target_loss",
	}
	_current_context.target_enemy = nil

	GrenadeFallback.try_queue(unit, blackboard)

	assert.equal(nil, _grenade_state_by_unit[unit].stage)
	assert.truthy(find_debug_log("grenade aim aborted"))
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL because the grenade state does not store or use a tactical decision object yet.

- [ ] **Step 3: Save the decision object in grenade state**

```lua
state.decision = decision
state.commit_policy = decision.commit_policy
state.reason = decision.reason
state.target_unit = decision.target_unit
state.placement_mode = decision.placement_mode
```

- [ ] **Step 4: Revalidate against the original tactical reason**

```lua
local revalidated, revalidate_rule = _revalidate_grenade_decision(state.decision, context)
if not revalidated then
	_emit_grenade_event("blocked", unit, state.grenade_name, state, fixed_t, {
		reason = "revalidation",
		rule = revalidate_rule,
	})
	_reset_state(unit, state, fixed_t + RETRY_COOLDOWN_S)
	return
end
```

```lua
if state.decision and state.decision.commit_policy == "abort_on_target_loss" and not state.decision.target_unit then
	return false, "grenade_revalidate_target_lost"
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS with grenade state preserving tactical intent across `wield -> wait_aim -> wait_throw`.

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua tests/grenade_fallback_spec.lua
git commit -m "feat(grenades): carry tactical decisions through fallback state"
```

### Task 5: Implement Placement Modes And Arbites Split

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_tactical_evaluator.lua`
- Modify: `tests/grenade_tactical_evaluator_spec.lua`
- Test: `tests/grenade_tactical_evaluator_spec.lua`

- [ ] **Step 1: Write the failing family-behavior tests**

```lua
it("uses cluster placement for aoe lethal grenades", function()
	local decision = Evaluator.evaluate("adamant_grenade", {
		target_enemy = "rager",
		primary_cluster_anchor = "rager",
		num_nearby = 6,
		challenge_rating_sum = 4.0,
		elite_count = 2,
		preset = "balanced",
	})

	assert.is_true(decision.should_activate)
	assert.equal("target_cluster", decision.placement_mode)
	assert.equal("horde_clear", decision.reason)
end)

it("uses self_feet placement for mines when enemies are collapsing on the bot", function()
	local decision = Evaluator.evaluate("adamant_shock_mine", {
		target_enemy = "mauler",
		num_nearby = 6,
		challenge_rating_sum = 4.0,
		target_enemy_distance = 3,
		preset = "balanced",
	})

	assert.is_true(decision.should_activate)
	assert.equal("self_feet", decision.placement_mode)
	assert.equal("hold_point_denial", decision.reason)
end)

it("disables whistle decisions for lone-wolf arbites contexts", function()
	local decision = Evaluator.evaluate("adamant_whistle", {
		companion_unit = nil,
		has_companion = false,
		target_enemy = "gunner",
		preset = "balanced",
	})

	assert.is_false(decision.should_activate)
	assert.equal("grenade_whistle_block_no_companion", decision.rule)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL because the evaluator still returns only the minimal skeleton decisions.

- [ ] **Step 3: Implement family-specific scoring branches**

```lua
local function _eval_aoe_lethal(template, context)
	if context.num_nearby >= 4 and context.challenge_rating_sum >= 2.0 then
		return _decision(template, "aoe_lethal", {
			should_activate = true,
			reason = "horde_clear",
			target_unit = context.primary_cluster_anchor,
			placement_mode = "target_cluster",
			commit_policy = "revalidate_until_release",
			confidence = "high",
		})
	end

	return _decision(template, "aoe_lethal", {
		should_activate = false,
		rule = "grenade_hold",
	})
end
```

```lua
local function _eval_placeable_denial(template, context)
	if context.num_nearby >= 5 and context.challenge_rating_sum >= 3.0 then
		return _decision(template, "placeable_denial", {
			should_activate = true,
			reason = "hold_point_denial",
			placement_mode = "self_feet",
			commit_policy = "strict",
			confidence = "high",
		})
	end

	return _decision(template, "placeable_denial", {
		should_activate = false,
		rule = "grenade_hold",
	})
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: PASS with family-specific placement mode and Arbites dog/no-dog split covered.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/grenade_tactical_evaluator.lua tests/grenade_tactical_evaluator_spec.lua
git commit -m "feat(grenades): add placement modes and arbites split"
```

### Task 6: Add Observability And Docs

**Files:**
- Modify: `scripts/mods/BetterBots/grenade_fallback.lua`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/debugging.md`
- Modify: `docs/dev/status.md`
- Modify: `tests/grenade_fallback_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Write the failing observability test**

```lua
it("emits placement mode and tactical reason in grenade events", function()
	GrenadeFallback.try_queue(unit, blackboard)

	local queued = _event_emissions[#_event_emissions]
	assert.equal("priority_pick", queued.reason)
	assert.equal("target_unit", queued.placement_mode)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL because grenade events do not yet carry tactical fields.

- [ ] **Step 3: Add tactical fields to grenade events and debug logs**

```lua
_emit_grenade_event("queued", unit, grenade_name, state, fixed_t, {
	rule = decision.rule,
	reason = decision.reason,
	placement_mode = decision.placement_mode,
	commit_policy = decision.commit_policy,
})
```

```lua
_debug_log(
	"grenade_decision:" .. tostring(unit),
	fixed_t,
	"grenade decision "
		.. tostring(grenade_name)
		.. " reason="
		.. tostring(decision.reason)
		.. " placement="
		.. tostring(decision.placement_mode)
)
```

- [ ] **Step 4: Update architecture and debugging docs**

```md
- `grenade_tactical_evaluator.lua` — shared grenade/blitz decision object builder, family scoring, and revalidation helpers
```

```md
| `grenade decision <template> reason=<reason> placement=<mode>` | Tactical evaluator output for a queued grenade/blitz |
| `placement_mode=<mode>` in JSONL | Machine-readable placement choice for grenade validation |
```

- [ ] **Step 5: Run tests and the full quality gate**

Run: `make test`
Expected: PASS for grenade evaluator, fallback, and heuristic specs.

Run: `make check`
Expected: PASS for format, lint, LSP, tests, and doc checks.

- [ ] **Step 6: Commit**

```bash
git add scripts/mods/BetterBots/grenade_fallback.lua docs/dev/architecture.md docs/dev/debugging.md docs/dev/status.md tests/grenade_fallback_spec.lua
git commit -m "docs(grenades): document tactical evaluator and validation signals"
```

## Self-Review

### Spec coverage

- Shared evaluator object: covered by Tasks 1, 3, 4
- Family-specific target/placement logic: covered by Tasks 2 and 5
- Arbites dog vs no-dog split: covered by Tasks 1, 3, and 5
- Settings integration: covered in Task 3 delegation and Task 6 observability, with reserve-policy extension expected during implementation in `grenade_tactical_evaluator.lua`
- Observability: covered by Task 6
- Explicit linkage to `#49` and `#22`: covered in docs/issues, not implementation logic

### Placeholder scan

- No `TODO`, `TBD`, or "implement later" placeholders remain
- All code-change steps include concrete snippets
- All test steps name exact files and expected behavior

### Type consistency

- Decision object fields are consistently named `template`, `reason`, `rule`, `target_unit`, `placement_mode`, `commit_policy`, `confidence`
- Arbites split consistently uses `companion_unit` / `has_companion`
- Resolver naming is consistent across evaluator and tests

Plan complete and saved to `docs/superpowers/plans/2026-04-08-grenade-blitz-tactical-evaluator.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
