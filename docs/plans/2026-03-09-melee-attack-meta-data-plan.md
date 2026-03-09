# Melee Attack Meta Data Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-derive and inject `attack_meta_data` for all melee weapons so bots use heavy attacks vs armored targets and sweeps vs hordes.

**Architecture:** New module `melee_meta_data.lua` scans `WeaponTemplates` at load time, traverses each melee weapon's action graph to find light/heavy attack damage profiles, classifies them by cleave (arc) and armor effectiveness (penetrating), and injects the resulting `attack_meta_data` table. No hooks on gameplay code — the existing `_choose_attack` scoring in `bt_bot_melee_action.lua` already handles the rest.

**Tech Stack:** Lua (Darktide DMF mod), busted (tests)

**Design doc:** `docs/plans/2026-03-09-melee-attack-meta-data-design.md`

---

### Task 1: Classification helpers — test + implement

**Files:**
- Create: `tests/melee_meta_data_spec.lua`
- Create: `scripts/mods/BetterBots/melee_meta_data.lua`

This task creates the module skeleton and the pure classification functions.

**Background — damage profile structure:**
- `cleave_distribution.attack` is `{min, max}` — use `[2]` (max) for arc classification
- `armor_damage_modifier.attack[armored_type]` is `{min, max}` — use `[2]` for penetrating
- Thresholds: arc=0 if cleave max ≤ 2, arc=1 if ≤ 9, arc=2 if > 9. Penetrating if armor max ≥ 0.5.

**Step 1: Write failing tests**

```lua
-- tests/melee_meta_data_spec.lua
local MeleeMetaData = dofile("scripts/mods/BetterBots/melee_meta_data.lua")

local ARMORED = 2

local function noop_debug_log() end

local function make_damage_profile(cleave_max, armored_max)
	return {
		cleave_distribution = {
			attack = { cleave_max * 0.5, cleave_max },
		},
		armor_damage_modifier = {
			attack = {
				[ARMORED] = { armored_max * 0.5, armored_max },
			},
		},
	}
end

describe("melee_meta_data", function()
	before_each(function()
		MeleeMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
			ARMOR_TYPE_ARMORED = ARMORED,
		})
	end)

	describe("classify_arc", function()
		it("returns 0 for no cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(0.001, 0)))
		end)

		it("returns 0 for single cleave", function()
			assert.equals(0, MeleeMetaData._classify_arc(make_damage_profile(2, 0)))
		end)

		it("returns 1 for light to medium cleave", function()
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(4, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(6, 0)))
			assert.equals(1, MeleeMetaData._classify_arc(make_damage_profile(9, 0)))
		end)

		it("returns 2 for large and big cleave", function()
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(10.5, 0)))
			assert.equals(2, MeleeMetaData._classify_arc(make_damage_profile(12.5, 0)))
		end)

		it("returns 0 for nil damage profile", function()
			assert.equals(0, MeleeMetaData._classify_arc(nil))
		end)

		it("returns 0 for missing cleave_distribution", function()
			assert.equals(0, MeleeMetaData._classify_arc({}))
		end)
	end)

	describe("classify_penetrating", function()
		it("returns false for low armor modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.426), ARMORED))
		end)

		it("returns true for high armor modifier", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.675), ARMORED))
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.33), ARMORED))
		end)

		it("returns true at exact threshold", function()
			assert.is_true(MeleeMetaData._classify_penetrating(make_damage_profile(0, 0.5), ARMORED))
		end)

		it("returns false for nil damage profile", function()
			assert.is_false(MeleeMetaData._classify_penetrating(nil, ARMORED))
		end)

		it("returns false for missing armor_damage_modifier", function()
			assert.is_false(MeleeMetaData._classify_penetrating({}, ARMORED))
		end)

		it("returns false for nil armored_type", function()
			assert.is_false(MeleeMetaData._classify_penetrating(make_damage_profile(0, 1.0), nil))
		end)
	end)
end)
```

**Step 2: Run tests — expect FAIL**

```bash
make test
```

Expected: FAIL — `melee_meta_data.lua` doesn't exist yet.

**Step 3: Write module skeleton with classification helpers**

```lua
-- scripts/mods/BetterBots/melee_meta_data.lua
local _mod
local _patched_set
local _debug_log
local _armored_type

local DEFAULT_MELEE_RANGE = 2.5
local CLEAVE_ARC_1_THRESHOLD = 2
local CLEAVE_ARC_2_THRESHOLD = 9
local PENETRATING_THRESHOLD = 0.5

local function classify_arc(damage_profile)
	if not damage_profile or not damage_profile.cleave_distribution then
		return 0
	end
	local cleave = damage_profile.cleave_distribution.attack
	if not cleave then
		return 0
	end
	local max_cleave = cleave[2] or cleave[1] or 0
	if max_cleave > CLEAVE_ARC_2_THRESHOLD then
		return 2
	elseif max_cleave > CLEAVE_ARC_1_THRESHOLD then
		return 1
	else
		return 0
	end
end

local function classify_penetrating(damage_profile, armored_type)
	if not damage_profile or not armored_type then
		return false
	end
	local am = damage_profile.armor_damage_modifier
	if not am or not am.attack then
		return false
	end
	local armored_lerp = am.attack[armored_type]
	if not armored_lerp then
		return false
	end
	local max_modifier = armored_lerp[2] or armored_lerp[1] or 0
	return max_modifier >= PENETRATING_THRESHOLD
end

local function inject(WeaponTemplates) -- luacheck: ignore 212
	-- placeholder
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
		_armored_type = deps.ARMOR_TYPE_ARMORED
	end,
	inject = inject,
	_classify_arc = classify_arc,
	_classify_penetrating = classify_penetrating,
}
```

**Step 4: Run tests — expect PASS**

```bash
make test
```

Expected: all classification tests pass.

**Step 5: Commit**

```bash
git add tests/melee_meta_data_spec.lua scripts/mods/BetterBots/melee_meta_data.lua
git commit -m "feat(#23): add melee damage profile classification helpers"
```

---

### Task 2: Injection function — test + implement

**Files:**
- Modify: `tests/melee_meta_data_spec.lua`
- Modify: `scripts/mods/BetterBots/melee_meta_data.lua`

This task adds the action graph traversal and injection loop.

**Background — action graph traversal:**

The path from weapon template to damage profile is:
1. Find the action with `start_input = "start_attack"` (the entry-point action)
2. Read `action.allowed_chain_actions["light_attack"].action_name` → action name
3. Look up `weapon_template.actions[action_name].damage_profile` → damage profile table
4. Same for `"heavy_attack"`

**Step 1: Add injection tests to spec file**

Add this helper at the top of the spec (after the existing helpers):

```lua
local function make_weapon_template(keywords, light_dp, heavy_dp)
	local actions = {
		action_melee_start_left = {
			start_input = "start_attack",
			allowed_chain_actions = {},
		},
	}
	if light_dp then
		actions.action_melee_start_left.allowed_chain_actions.light_attack = {
			action_name = "action_left_light",
		}
		actions.action_left_light = { damage_profile = light_dp }
	end
	if heavy_dp then
		actions.action_melee_start_left.allowed_chain_actions.heavy_attack = {
			action_name = "action_left_heavy",
		}
		actions.action_left_heavy = { damage_profile = heavy_dp }
	end
	return {
		keywords = keywords,
		actions = actions,
	}
end
```

Add this `describe` block inside the main `describe`:

```lua
	describe("inject", function()
		it("injects attack_meta_data for melee weapon with light and heavy", function()
			local light_dp = make_damage_profile(6, 0.3)
			local heavy_dp = make_damage_profile(0.001, 1.0)
			local templates = {
				sword = make_weapon_template({ "melee", "combat_sword" }, light_dp, heavy_dp),
			}

			MeleeMetaData.inject(templates)

			local meta = templates.sword.attack_meta_data
			assert.is_table(meta)
			assert.is_table(meta.light_attack)
			assert.equals(1, meta.light_attack.arc)
			assert.is_false(meta.light_attack.penetrating)
			assert.equals(2.5, meta.light_attack.max_range)
			assert.is_table(meta.heavy_attack)
			assert.equals(0, meta.heavy_attack.arc)
			assert.is_true(meta.heavy_attack.penetrating)
		end)

		it("generates correct action_inputs sequences", function()
			local templates = {
				sword = make_weapon_template(
					{ "melee" },
					make_damage_profile(6, 0.3),
					make_damage_profile(0.001, 1.0)
				),
			}

			MeleeMetaData.inject(templates)

			local light_inputs = templates.sword.attack_meta_data.light_attack.action_inputs
			assert.equals(2, #light_inputs)
			assert.equals("start_attack", light_inputs[1].action_input)
			assert.equals(0, light_inputs[1].timing)
			assert.equals("light_attack", light_inputs[2].action_input)

			local heavy_inputs = templates.sword.attack_meta_data.heavy_attack.action_inputs
			assert.equals("start_attack", heavy_inputs[1].action_input)
			assert.equals("heavy_attack", heavy_inputs[2].action_input)
		end)

		it("handles weapon with only light attack", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)

			assert.is_table(templates.sword.attack_meta_data)
			assert.is_table(templates.sword.attack_meta_data.light_attack)
			assert.is_nil(templates.sword.attack_meta_data.heavy_attack)
		end)

		it("skips non-melee weapons", function()
			local templates = {
				gun = make_weapon_template({ "ranged", "lasgun" }, make_damage_profile(0, 0), nil),
			}

			MeleeMetaData.inject(templates)

			assert.is_nil(templates.gun.attack_meta_data)
		end)

		it("does not overwrite existing attack_meta_data", function()
			local existing = { custom = { arc = 99 } }
			local template = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil)
			template.attack_meta_data = existing
			local templates = { sword = template }

			MeleeMetaData.inject(templates)

			assert.equals(existing, templates.sword.attack_meta_data)
		end)

		it("is idempotent for the same table", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
			}

			MeleeMetaData.inject(templates)
			local first_meta = templates.sword.attack_meta_data

			MeleeMetaData.inject(templates)
			assert.equals(first_meta, templates.sword.attack_meta_data)
		end)

		it("handles weapon with no start_attack action", function()
			local templates = {
				broken = {
					keywords = { "melee" },
					actions = {
						some_action = { start_input = "other_input" },
					},
				},
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)

		it("handles weapon with no allowed_chain_actions", function()
			local templates = {
				broken = {
					keywords = { "melee" },
					actions = {
						action_start = { start_input = "start_attack" },
					},
				},
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)

		it("skips non-table entries in WeaponTemplates", function()
			local templates = {
				sword = make_weapon_template({ "melee" }, make_damage_profile(6, 0.3), nil),
				_version = 42,
			}

			assert.has_no.errors(function()
				MeleeMetaData.inject(templates)
			end)
			assert.is_table(templates.sword.attack_meta_data)
		end)
	end)
```

**Step 2: Run tests — expect FAIL**

```bash
make test
```

Expected: injection tests fail — `inject()` is a placeholder.

**Step 3: Implement injection in `melee_meta_data.lua`**

Replace the placeholder `inject` and add helper functions. The full module becomes:

```lua
-- scripts/mods/BetterBots/melee_meta_data.lua
local _mod
local _patched_set
local _debug_log
local _armored_type

local DEFAULT_MELEE_RANGE = 2.5
local CLEAVE_ARC_1_THRESHOLD = 2
local CLEAVE_ARC_2_THRESHOLD = 9
local PENETRATING_THRESHOLD = 0.5

local function classify_arc(damage_profile)
	if not damage_profile or not damage_profile.cleave_distribution then
		return 0
	end
	local cleave = damage_profile.cleave_distribution.attack
	if not cleave then
		return 0
	end
	local max_cleave = cleave[2] or cleave[1] or 0
	if max_cleave > CLEAVE_ARC_2_THRESHOLD then
		return 2
	elseif max_cleave > CLEAVE_ARC_1_THRESHOLD then
		return 1
	else
		return 0
	end
end

local function classify_penetrating(damage_profile, armored_type)
	if not damage_profile or not armored_type then
		return false
	end
	local am = damage_profile.armor_damage_modifier
	if not am or not am.attack then
		return false
	end
	local armored_lerp = am.attack[armored_type]
	if not armored_lerp then
		return false
	end
	local max_modifier = armored_lerp[2] or armored_lerp[1] or 0
	return max_modifier >= PENETRATING_THRESHOLD
end

local function find_start_action(weapon_template)
	for _, action in pairs(weapon_template.actions or {}) do
		if action.start_input == "start_attack" then
			return action
		end
	end
	return nil
end

local function build_attack_entry(damage_profile, input_name, armored_type)
	return {
		arc = classify_arc(damage_profile),
		penetrating = classify_penetrating(damage_profile, armored_type),
		max_range = DEFAULT_MELEE_RANGE,
		action_inputs = {
			{ action_input = "start_attack", timing = 0 },
			{ action_input = input_name, timing = 0 },
		},
	}
end

local function build_meta_data(weapon_template, armored_type)
	local start_action = find_start_action(weapon_template)
	if not start_action then
		return nil
	end

	local chains = start_action.allowed_chain_actions
	if not chains then
		return nil
	end

	local meta = {}
	local count = 0

	for _, input_name in ipairs({ "light_attack", "heavy_attack" }) do
		local chain = chains[input_name]
		if chain and chain.action_name then
			local action = weapon_template.actions[chain.action_name]
			if action and action.damage_profile then
				meta[input_name] = build_attack_entry(action.damage_profile, input_name, armored_type)
				count = count + 1
			end
		end
	end

	return count > 0 and meta or nil
end

local function has_keyword(weapon_template, keyword)
	for _, kw in ipairs(weapon_template.keywords or {}) do
		if kw == keyword then
			return true
		end
	end
	return false
end

local function inject(WeaponTemplates)
	if _patched_set[WeaponTemplates] then
		return
	end

	local injected = 0
	local skipped = 0

	for name, template in pairs(WeaponTemplates) do
		if type(template) == "table" and has_keyword(template, "melee") then
			if template.attack_meta_data then
				skipped = skipped + 1
			else
				local meta = build_meta_data(template, _armored_type)
				if meta then
					template.attack_meta_data = meta
					injected = injected + 1
				end
			end
		end
	end

	_patched_set[WeaponTemplates] = true
	_debug_log(
		"melee_meta_injection:" .. tostring(WeaponTemplates),
		0,
		"melee attack_meta_data patch installed (injected=" .. injected .. ", skipped=" .. skipped .. ")"
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
		_armored_type = deps.ARMOR_TYPE_ARMORED
	end,
	inject = inject,
	_classify_arc = classify_arc,
	_classify_penetrating = classify_penetrating,
}
```

Note: `_build_meta_data` is not exported — it's tested indirectly through `inject`.
The `name` variable in the `inject` loop is unused but kept for readability; add `-- luacheck: ignore 213` if linter complains.

**Step 4: Run tests — expect PASS**

```bash
make test
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add tests/melee_meta_data_spec.lua scripts/mods/BetterBots/melee_meta_data.lua
git commit -m "feat(#23): add melee attack_meta_data injection"
```

---

### Task 3: Integrate into BetterBots.lua

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua`

**Background — integration points:**
- `meta_data.lua` pattern: loaded via `mod:io_dofile`, init with deps, `hook_require` for injection
- `ArmorSettings.types` is already imported at line 3 and `ARMOR_TYPES` at line 49
- Weak-keyed `_patched_set` table for idempotency
- `hook_require` on `"scripts/settings/equipment/weapon_templates/weapon_templates"` for lazy injection

**Step 1: Add `_patched_weapon_templates` table**

After line 15 (`_patched_ability_templates`), add:

```lua
local _patched_weapon_templates = setmetatable({}, { __mode = "k" })
```

**Step 2: Load and init MeleeMetaData module**

After the Sprint module load (line 153-154), add:

```lua
local MeleeMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/melee_meta_data")
assert(MeleeMetaData, "BetterBots: failed to load melee_meta_data module")
```

After the Sprint init block, add:

```lua
MeleeMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates,
	debug_log = _debug_log,
	ARMOR_TYPE_ARMORED = ARMOR_TYPES and ARMOR_TYPES.armored,
})
```

**Step 3: Add `hook_require` for WeaponTemplates**

After the existing `hook_require` for AbilityTemplates (line 680-682), add:

```lua
mod:hook_require("scripts/settings/equipment/weapon_templates/weapon_templates", function(WeaponTemplates)
	MeleeMetaData.inject(WeaponTemplates)
end)
```

**Step 4: Run tests**

```bash
make check
```

Expected: all checks pass (format, lint, lsp, tests).

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua
git commit -m "feat(#23): integrate melee attack_meta_data injection into main module"
```

---

### Task 4: Update docs and batch test checklist

**Files:**
- Modify: `docs/ARCHITECTURE.md` — add entry 19 for melee attack_meta_data injection
- Modify: `docs/BATCH_TEST_m4-batch1.md` — add #23 feature and acceptance criteria

**Step 1: Add to ARCHITECTURE.md**

Add entry 19 after entry 18 in the "Mod behavior" section:

```
19. Melee attack metadata injection (#23, via `melee_meta_data.lua`):
    - hook `WeaponTemplates` require: auto-derives and injects `attack_meta_data` for all melee weapons
    - traverses action graph: `start_attack` → `allowed_chain_actions` → light/heavy action → `damage_profile`
    - classifies `arc` from `cleave_distribution` (0/1/2) and `penetrating` from `armor_damage_modifier[armored]` (threshold ≥ 0.5)
    - enables existing `_choose_attack` scoring: +8 penetrating vs armored, +4 sweep vs hordes
```

**Step 2: Update batch test checklist**

Add #23 to the feature table and add acceptance criteria section:

```markdown
| #23 | `feat/23-melee-attack-meta-data` | Smart melee attack selection (armor-aware) | needs-testing |

### #23 — Smart melee attack selection
- [ ] Bot uses heavy attacks against armored enemies (Maulers, Crushers)
- [ ] Bot uses sweeping attacks against hordes (3+ unarmored enemies)
- [ ] Bot still uses light attacks in 1v1 vs unarmored
- [ ] Debug log shows `melee attack_meta_data patch installed (injected=N, skipped=M)` with N > 0
- [ ] No Lua errors in console
- [ ] Melee combat loop still functional (attack → block → push → dodge cycle)
```

**Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md docs/BATCH_TEST_m4-batch1.md
git commit -m "docs: add #23 melee attack_meta_data to architecture and batch test checklist"
```
