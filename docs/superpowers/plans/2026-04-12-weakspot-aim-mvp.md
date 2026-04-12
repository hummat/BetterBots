# Weakspot Aim MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject vanilla-style head-or-spine aim metadata for BetterBots' finesse-ranged allowlist without touching breed-specific aiming or runtime shoot logic.

**Architecture:** Extend the existing ranged metadata injection pass in `ranged_meta_data.lua` so it can recognize a narrow family allowlist and merge `aim_at_node = { "j_head", "j_spine" }` into `attack_meta_data` when that field is absent. Prove behavior with unit tests that cover allowlist hits, preserve paths, and coexistence with existing ranged-input corrections.

**Tech Stack:** Lua, busted, Darktide weapon template metadata, BetterBots ranged metadata injection layer

---

## File Map

- Modify: `scripts/mods/BetterBots/ranged_meta_data.lua`
  - add allowlist helpers
  - add weakspot metadata injection
  - preserve existing input-fallback behavior
- Modify: `tests/ranged_meta_data_spec.lua`
  - add allowlist family fixtures and assertions
  - verify non-overwrite and coexistence behavior
- Modify: `docs/dev/architecture.md`
  - document the new `aim_at_node` injection behavior in `ranged_meta_data.lua`
- Modify: `docs/dev/roadmap.md`
  - move `#91` from planned note to implemented-on-branch note
- Modify: `docs/dev/status.md`
  - record implementation progress for v0.11.0 batch

### Task 1: Add Failing Tests For Weakspot Metadata Injection

**Files:**
- Modify: `tests/ranged_meta_data_spec.lua`
- Test: `tests/ranged_meta_data_spec.lua`

- [ ] **Step 1: Write the failing tests**

Add these cases near the existing `describe("inject", ...)` block:

```lua
		it("injects weakspot aim nodes for allowlisted ranged families", function()
			local templates = {
				lasgun = make_ranged_template({
					keywords = { "ranged", "lasgun", "p1" },
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = { input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						} },
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.same({ "j_head", "j_spine" }, templates.lasgun.attack_meta_data.aim_at_node)
		end)

		it("merges weakspot aim nodes into existing attack_meta_data", function()
			local template = make_ranged_template({
				keywords = { "ranged", "autogun", "p2" },
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					zoom = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
					zoom_shoot = { input_sequence = {
						{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
					} },
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
					action_zoom = { start_input = "zoom" },
					action_shoot_zoomed = { start_input = "zoom_shoot" },
				},
			})
			template.attack_meta_data = { aim_data = { min_distance = 5 } }

			RangedMetaData.inject({ autogun = template })

			assert.equals(5, template.attack_meta_data.aim_data.min_distance)
			assert.same({ "j_head", "j_spine" }, template.attack_meta_data.aim_at_node)
		end)

		it("preserves existing aim_at_node values", function()
			local template = make_ranged_template({
				keywords = { "ranged", "bolter", "p1" },
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
				},
			})
			template.attack_meta_data = { aim_at_node = "j_neck" }

			RangedMetaData.inject({ bolter = template })

			assert.equals("j_neck", template.attack_meta_data.aim_at_node)
		end)

		it("skips weakspot injection for non-allowlisted ranged weapons", function()
			local templates = {
				autopistol = make_ranged_template({
					keywords = { "ranged", "autopistol", "p1" },
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						zoom = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						zoom_shoot = { input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						} },
					},
					actions = {
						action_shoot = { start_input = "shoot_pressed" },
						action_zoom = { start_input = "zoom" },
						action_shoot_zoomed = { start_input = "zoom_shoot" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.autopistol.attack_meta_data)
		end)

		it("combines fire-input correction with weakspot aim injection", function()
			local templates = {
				stubrevolver = make_ranged_template({
					keywords = { "ranged", "stub_pistol", "p1" },
					action_inputs = {
						shoot_charge = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = {
						action_shoot = { kind = "shoot_hit_scan" },
						action_charge_direct = { start_input = "shoot_charge" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			assert.equals("shoot_charge", templates.stubrevolver.attack_meta_data.fire_action_input)
			assert.same({ "j_head", "j_spine" }, templates.stubrevolver.attack_meta_data.aim_at_node)
		end)
```

- [ ] **Step 2: Run the targeted test file to verify failure**

Run:

```bash
make test TESTS=tests/ranged_meta_data_spec.lua
```

Expected: FAIL on missing `aim_at_node` injection assertions.

- [ ] **Step 3: Commit the failing-test checkpoint**

```bash
git add tests/ranged_meta_data_spec.lua
git commit -m "test: cover weakspot aim metadata injection"
```

### Task 2: Implement Weakspot Allowlist Injection

**Files:**
- Modify: `scripts/mods/BetterBots/ranged_meta_data.lua`
- Test: `tests/ranged_meta_data_spec.lua`

- [ ] **Step 1: Add allowlist helpers**

Add near `has_keyword`:

```lua
local WEAKSPOT_AIM_NODES = {
	"j_head",
	"j_spine",
}

local function has_any_keyword(weapon_template, keywords)
	for _, keyword in ipairs(keywords) do
		if has_keyword(weapon_template, keyword) then
			return true
		end
	end

	return false
end

local function should_inject_weakspot_aim(weapon_template)
	return has_any_keyword(weapon_template, {
		"lasgun",
		"autogun",
		"bolter",
		"stub_pistol",
	})
end
```

- [ ] **Step 2: Extend metadata builder to include weakspot aim**

Update `build_meta_data(weapon_template)`:

```lua
	if should_inject_weakspot_aim(weapon_template) then
		meta.aim_at_node = WEAKSPOT_AIM_NODES
		changed = true
	end
```

Place this behind an explicit guard so it only fills missing metadata:

```lua
	if should_inject_weakspot_aim(weapon_template) then
		meta.aim_at_node = WEAKSPOT_AIM_NODES
		changed = true
	end
```

Then preserve merge semantics in `inject()` by relying on the existing:

```lua
if template.attack_meta_data[k] == nil then
	template.attack_meta_data[k] = v
end
```

That means:
- existing `aim_at_node` survives untouched
- missing `aim_at_node` merges into existing `attack_meta_data`
- templates with no prior `attack_meta_data` get a minimal table

- [ ] **Step 3: Export helper for unit-level inspection if needed**

If tests need direct helper coverage, export:

```lua
	_should_inject_weakspot_aim = should_inject_weakspot_aim,
```

Only add this if the test file benefits from direct helper assertions. If integration-style `inject()` coverage is enough, skip this export.

- [ ] **Step 4: Run targeted tests**

Run:

```bash
make test TESTS=tests/ranged_meta_data_spec.lua
```

Expected: PASS

- [ ] **Step 5: Commit implementation checkpoint**

```bash
git add scripts/mods/BetterBots/ranged_meta_data.lua tests/ranged_meta_data_spec.lua
git commit -m "feat: add weakspot aim metadata for finesse weapons"
```

### Task 3: Update Docs For #91

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/status.md`

- [ ] **Step 1: Document module behavior**

Add to `docs/dev/architecture.md` module description for `ranged_meta_data.lua`:

```md
- injects `attack_meta_data.aim_at_node = { "j_head", "j_spine" }` for allowlisted finesse-ranged families (lasgun, autogun, stub revolver, bolter) when vanilla metadata leaves aim-node unset
```

- [ ] **Step 2: Update roadmap entry for #91**

Change the `#91` row in `docs/dev/roadmap.md` from planned wording to implemented-on-branch wording:

```md
| 91 | Bot weakspot aim MVP | Implemented on branch. `ranged_meta_data.lua` injects vanilla-style `{ "j_head", "j_spine" }` aim-node metadata for lasguns, autoguns, stub revolvers, and bolters when `attack_meta_data.aim_at_node` is absent. Breed-specific overrides remain deferred to `#92`. |
```

- [ ] **Step 3: Update status snapshot**

Add under the v0.11.0 next-step list in `docs/dev/status.md`:

```md
- `#91` weakspot aim MVP — implemented on branch: allowlisted finesse-ranged families now get vanilla-style head/spine aim metadata injection; per-breed weakspot mapping remains deferred to `#92`.
```

- [ ] **Step 4: Commit doc checkpoint**

```bash
git add docs/dev/architecture.md docs/dev/roadmap.md docs/dev/status.md
git commit -m "docs: record weakspot aim mvp progress"
```

### Task 4: Full Verification

**Files:**
- Modify: none
- Test: `tests/ranged_meta_data_spec.lua`

- [ ] **Step 1: Run focused automated check**

Run:

```bash
make test TESTS=tests/ranged_meta_data_spec.lua
```

Expected: PASS with the weakspot coverage included.

- [ ] **Step 2: Run broader regression check**

Run:

```bash
make test
```

Expected: PASS for full busted suite.

- [ ] **Step 3: Run doc consistency check**

Run:

```bash
make doc-check
```

Expected: PASS

- [ ] **Step 4: Commit verification checkpoint**

```bash
git add docs/superpowers/plans/2026-04-12-weakspot-aim-mvp.md
git commit -m "docs: add weakspot aim implementation plan"
```

## Self-Review

- Spec coverage: allowlist scope, merge rules, preserve behavior, tests, and doc updates all mapped to tasks above.
- Placeholder scan: no `TODO`, `TBD`, or implicit “write tests later” steps remain.
- Type consistency: uses existing `attack_meta_data`, `aim_at_node`, `inject()`, and `make test` conventions already present in repo.
