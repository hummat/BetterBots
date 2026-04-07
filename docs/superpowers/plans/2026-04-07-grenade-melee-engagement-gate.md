# Grenade Melee-Engagement Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent bots from starting committed grenade/blitz swap-and-throw or swap-and-place sequences while an enemy is already in melee range, and prevent single-target grenade throws from firing while the bot is surrounded, without changing crowd-control grenade behavior or no-swap/fast opt-out paths.

**Architecture:** Keep the policy in `heuristics.lua`, not in `grenade_fallback.lua`. Add one shared close-melee helper and call it from the committed-throw heuristic families (`_grenade_horde`, `_grenade_defensive`, `_grenade_mine`, `_grenade_priority_target`). Add a second block inside `_grenade_priority_target` only for crowd-pressure on single-target throws such as rock/krak/missile. Keep explicit opt-outs for paths that do not have the same exposure cost (`psyker_smite`, `zealot_throwing_knives`).

**Tech Stack:** Lua (DMF mod), busted tests via `make test`, repo docs in `docs/dev/`

---

## File Map

- Modify: `scripts/mods/BetterBots/heuristics.lua`
  - Add the shared melee-engagement block helper.
  - Reuse it in the committed grenade/blitz heuristic helpers.
  - Add opt-out flags for no-swap or fast special cases.
- Modify: `tests/heuristics_spec.lua`
  - Add regression coverage for shared close-range blocking and priority-only crowd-pressure blocking.
  - Prove opt-out paths still work.
- Modify: `docs/dev/status.md`
  - Mark `#71` implemented on `dev/v0.9.1`, pending in-game validation.
- Modify: `docs/dev/roadmap.md`
  - Move `#71` from open hotfix item to implemented/pending validation.
- Modify: `docs/dev/known-issues.md`
  - Replace the active `#71` issue entry with a fixed-on-branch note.

## Task 1: Add Regression Tests First

**Files:**
- Modify: `tests/heuristics_spec.lua`

- [ ] **Step 1: Add failing grenade melee-engagement tests**

Insert the following cases inside the `describe("evaluate_grenade_heuristic", function()` block near the existing grenade tests:

```lua
		it("blocks horde grenades in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_box",
				helper.make_context({
					num_nearby = 6,
					challenge_rating_sum = 3.5,
					target_enemy = "poxwalker",
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("blocks priority grenades under crowd pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"ogryn_grenade_friend_rock",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 10,
				})
			)
			assert.is_false(result)
			assert.matches("priority_melee_pressure", rule)
		end)

		it("blocks krak grenades in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_krak_grenade",
				helper.make_context({
					num_nearby = 2,
					target_enemy = "crusher",
					target_is_elite_special = true,
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("keeps defensive smoke available under crowd pressure", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"veteran_smoke_grenade",
				helper.make_context({
					num_nearby = 4,
					ranged_count = 2,
					toughness_pct = 0.25,
					target_enemy = "gunner",
					target_enemy_distance = 8,
				})
			)
			assert.is_true(result)
			assert.matches("pressure", rule)
		end)

		it("blocks shock mine only in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"adamant_shock_mine",
				helper.make_context({
					num_nearby = 5,
					challenge_rating_sum = 3.5,
					elite_count = 3,
					target_enemy = "rager",
					target_enemy_distance = 3,
				})
			)
			assert.is_false(result)
			assert.matches("melee_range", rule)
		end)

		it("keeps shock mine available under crowd pressure when not in melee range", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"adamant_shock_mine",
				helper.make_context({
					num_nearby = 5,
					challenge_rating_sum = 3.5,
					elite_count = 3,
					target_enemy = "rager",
					target_enemy_distance = 8,
				})
			)
			assert.is_true(result)
			assert.matches("elite_pack", rule)
		end)

		it("keeps zealot throwing knives opted out of the melee gate", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"zealot_throwing_knives",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "gunner",
					target_is_elite_special = true,
					target_enemy_distance = 7,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)

		it("keeps Smite opted out of the melee gate", function()
			local result, rule = Heuristics.evaluate_grenade_heuristic(
				"psyker_smite",
				helper.make_context({
					num_nearby = 4,
					target_enemy = "trapper",
					target_is_elite_special = true,
					target_enemy_distance = 7,
					peril_pct = 0.50,
				})
			)
			assert.is_true(result)
			assert.matches("priority", rule)
		end)
```

- [ ] **Step 2: Run the focused heuristic suite and confirm the new tests fail**

Run:

```bash
make test TEST_FILES='tests/heuristics_spec.lua'
```

Expected:

```text
busted exits non-zero and reports at least one new grenade melee-engagement assertion failing
```

- [ ] **Step 3: Keep the red-green target small**

Do not edit any runtime files yet. Confirm the failure is only in the newly added melee-gate assertions before moving on.

Run:

```bash
make test TEST_FILES='tests/heuristics_spec.lua'
```

Expected:

```text
FAIL with only the new shared close-range and priority-only crowd-pressure cases failing
```

## Task 2: Implement the Shared Heuristic Gate

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Test: `tests/heuristics_spec.lua`

- [ ] **Step 1: Add the shared melee-engagement helper**

Insert this helper above `_grenade_horde(...)`:

```lua
local function _grenade_blocked_by_melee_engagement(context, rule_prefix, opts)
	opts = opts or {}

	if opts.skip_melee_engagement_block then
		return false, nil
	end

	local target_distance = context.target_enemy_distance
	if target_distance and target_distance < 4 then
		return true, rule_prefix .. "_block_melee_range"
	end

	return false, nil
end
```

- [ ] **Step 2: Reuse the shared close-range helper in the committed grenade families**

Apply the helper at the top of `_grenade_horde(...)`, `_grenade_defensive(...)`, and `_grenade_mine(...)`:

```lua
local function _grenade_horde(context, min_nearby, min_challenge, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_HORDE_PRESETS[preset] or GRENADE_HORDE_PRESETS.balanced
	local adj_nearby = min_nearby + t.nearby_offset
	local adj_challenge = min_challenge + t.challenge_offset
	if context.num_nearby >= adj_nearby and context.challenge_rating_sum >= adj_challenge then
		return true, rule_prefix .. "_horde"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_defensive(context, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_DEFENSIVE_PRESETS[preset] or GRENADE_DEFENSIVE_PRESETS.balanced
	if context.target_ally_needs_aid and context.num_nearby >= 2 then
		return true, rule_prefix .. "_ally_aid"
	end

	if context.ranged_count >= (2 + t.count_offset) and context.toughness_pct < (0.50 + t.toughness_offset) then
		return true, rule_prefix .. "_pressure"
	end

	if context.num_nearby >= (4 + t.count_offset) and context.toughness_pct < (0.35 + t.toughness_offset) then
		return true, rule_prefix .. "_pressure"
	end

	return false, rule_prefix .. "_hold"
end

local function _grenade_mine(context, rule_prefix, preset)
	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix)
	if blocked then
		return false, blocked_rule
	end

	local t = GRENADE_MINE_PRESETS[preset] or GRENADE_MINE_PRESETS.balanced
	if context.elite_count >= (3 + t.elite_offset) then
		return true, rule_prefix .. "_elite_pack"
	end

	if context.num_nearby >= (5 + t.density_offset) and context.challenge_rating_sum >= 3.0 then
		return true, rule_prefix .. "_hold_point"
	end

	return false, rule_prefix .. "_hold"
end
```

- [ ] **Step 3: Reuse the helper in `_grenade_priority_target(...)` with explicit opt-outs**

Change the helper signature and the opt-out call sites:

```lua
local function _grenade_priority_target(context, rule_prefix, opts, preset)
	opts = opts or {}

	local blocked, blocked_rule = _grenade_blocked_by_melee_engagement(context, rule_prefix, opts)
	if blocked then
		return false, blocked_rule
	end

	if not opts.skip_priority_melee_pressure_block and context.num_nearby >= 4 then
		return false, rule_prefix .. "_block_priority_melee_pressure"
	end

	if opts.max_peril and context.peril_pct and context.peril_pct >= opts.max_peril then
		return false, rule_prefix .. "_block_peril"
	end

	if opts.block_super_armor and context.target_is_super_armor then
		return false, rule_prefix .. "_block_super_armor"
	end

	local target_distance = context.target_enemy_distance or 0
	local t = GRENADE_PRIORITY_PRESETS[preset] or GRENADE_PRIORITY_PRESETS.balanced
	local min_distance = (opts.min_distance or 0) + t.distance_offset
	local has_priority_target = context.target_is_monster
		or context.target_is_elite_special
		or context.priority_target_enemy ~= nil
		or context.opportunity_target_enemy ~= nil
		or context.urgent_target_enemy ~= nil

	if has_priority_target and target_distance >= min_distance then
		return true, rule_prefix .. "_priority_target"
	end

	if (context.elite_count + context.special_count + context.monster_count) >= 1 then
		return true, rule_prefix .. "_priority_pack"
	end

	return false, rule_prefix .. "_hold"
end
```

Update the opt-out callers:

```lua
local function _grenade_smite(context)
	return _grenade_priority_target(context, "grenade_smite", {
		max_peril = 0.85,
		min_distance = 5,
		skip_melee_engagement_block = true,
		skip_priority_melee_pressure_block = true,
	}, context.preset)
end

	zealot_throwing_knives = function(context)
		return _grenade_priority_target(context, "grenade_knives", {
			min_distance = 5,
			skip_melee_engagement_block = true,
			skip_priority_melee_pressure_block = true,
		}, context.preset)
	end,
```

- [ ] **Step 4: Run the focused heuristic suite and confirm it passes**

Run:

```bash
make test TEST_FILES='tests/heuristics_spec.lua'
```

Expected:

```text
busted exits 0 and reports no failures in tests/heuristics_spec.lua
```

- [ ] **Step 5: Commit the tested heuristic change**

Run:

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "fix(heuristics): block grenade swaps in melee"
```

Expected:

```text
git creates a new commit on dev/v0.9.1 with message: fix(heuristics): block grenade swaps in melee
```

## Task 3: Update Docs And Run Final Verification

**Files:**
- Modify: `docs/dev/status.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/known-issues.md`
- Modify: `docs/superpowers/specs/2026-04-07-grenade-melee-engagement-gate-design.md`

- [ ] **Step 1: Update the status and issue docs**

Apply these content changes:

```md
docs/dev/status.md
- Change `#71 | P2 | Open` to implemented on `dev/v0.9.1`, pending in-game validation.

docs/dev/roadmap.md
- Change the `#71` hotfix row from proposed fix text to implemented on `dev/v0.9.1`, pending in-game validation.

docs/dev/known-issues.md
- Replace the active `#71` issue entry with a fixed-on-branch note that the shared grenade melee-engagement gate now blocks committed grenade swaps in melee and still needs in-game validation.
```

Stage the accepted spec wording cleanup from this planning session as part of the same docs pass:

```bash
git add docs/superpowers/specs/2026-04-07-grenade-melee-engagement-gate-design.md
```

- [ ] **Step 2: Run targeted and full verification**

Run:

```bash
make test TEST_FILES='tests/heuristics_spec.lua'
make check
```

Expected:

```text
tests/heuristics_spec.lua passes and make check completes without formatter, linter, LSP, test, or doc-check errors
```

- [ ] **Step 3: Commit the docs and verification pass**

Run:

```bash
git add docs/dev/status.md docs/dev/roadmap.md docs/dev/known-issues.md docs/superpowers/specs/2026-04-07-grenade-melee-engagement-gate-design.md
git commit -m "docs: update hotfix status for grenade melee gate"
```

Expected:

```text
git creates a new commit on dev/v0.9.1 with message: docs: update hotfix status for grenade melee gate
```

## Self-Review

- Spec coverage: the plan covers the shared close-range gate, the priority-only crowd-pressure block, the opt-out paths, regression tests, and the required hotfix docs.
- Placeholder scan: no `TODO`/`TBD` markers, no unnamed files, and every task has exact commands plus code or content snippets.
- Type consistency: the plan uses one helper name, two opt-out flags (`skip_melee_engagement_block`, `skip_priority_melee_pressure_block`), and one pair of rule suffixes (`_block_melee_range`, `_block_priority_melee_pressure`) throughout.
