# #31 Ranged `attack_meta_data` Injection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-derive and inject `attack_meta_data` for player ranged weapons so bots can fire weapons whose action input names don't match the hardcoded fallback chain in `bt_bot_shoot_action`.

**Architecture:** New module `ranged_meta_data.lua` following `melee_meta_data.lua` pattern. Validates the vanilla fallback chain per-template, injects corrections only where it would produce invalid inputs. Derivation scans `action_inputs` for button mappings (`action_one_pressed`, `action_two_hold`) and cross-references with `actions` via `start_input`.

**Tech Stack:** Lua, busted (unit tests), DMF mod framework

**Key reference files:**
- `scripts/mods/BetterBots/melee_meta_data.lua` — sibling module to mirror
- `tests/melee_meta_data_spec.lua` — test pattern to follow
- `scripts/mods/BetterBots/BetterBots.lua:695-697` — integration hook point
- Decompiled: `../Darktide-Source-Code/scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua:34-80` — the fallback chain we're fixing

---

### Task 1: Vanilla fallback resolution + validation

**Files:**
- Create: `scripts/mods/BetterBots/ranged_meta_data.lua`
- Create: `tests/ranged_meta_data_spec.lua`

**Step 1: Write the failing tests**

```lua
-- tests/ranged_meta_data_spec.lua
local RangedMetaData = dofile("scripts/mods/BetterBots/ranged_meta_data.lua")

local function noop_debug_log() end

-- Helper: build a minimal ranged weapon template
local function make_ranged_template(opts)
	opts = opts or {}
	local actions = opts.actions or {}
	local action_inputs = opts.action_inputs or {}
	return {
		keywords = opts.keywords or { "ranged" },
		actions = actions,
		action_inputs = action_inputs,
	}
end

describe("ranged_meta_data", function()
	before_each(function()
		RangedMetaData.init({
			mod = { echo = function() end },
			patched_weapon_templates = {},
			debug_log = noop_debug_log,
		})
	end)

	describe("resolve_vanilla_fallback", function()
		it("returns action start_inputs when actions exist", function()
			local t = make_ranged_template({
				actions = {
					action_shoot = { start_input = "shoot_pressed" },
					action_zoom = { start_input = "zoom" },
					action_shoot_zoomed = { start_input = "zoom_shoot" },
				},
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot_pressed", fb.fire_action_input)
			assert.equals("zoom", fb.aim_action_input)
			assert.equals("zoom_shoot", fb.aim_fire_action_input)
		end)

		it("falls back to hardcoded strings when actions missing", function()
			local t = make_ranged_template({ actions = {} })
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
			assert.equals("zoom", fb.aim_action_input)
			assert.equals("zoom_shoot", fb.aim_fire_action_input)
		end)

		it("falls back when action exists but start_input is nil", function()
			local t = make_ranged_template({
				actions = { action_shoot = { kind = "shoot_hit_scan" } },
			})
			local fb = RangedMetaData._resolve_vanilla_fallback(t)
			assert.equals("shoot", fb.fire_action_input)
		end)
	end)

	describe("needs_injection", function()
		it("returns false when fire input is valid", function()
			local t = make_ranged_template({
				actions = { action_shoot = { start_input = "shoot_pressed" } },
				action_inputs = { shoot_pressed = { input_sequence = {} } },
			})
			assert.is_false(RangedMetaData._needs_injection(t))
		end)

		it("returns true when fire input is invalid", function()
			local t = make_ranged_template({
				actions = { action_shoot = {} },
				action_inputs = { shoot_charge = { input_sequence = {} } },
			})
			assert.is_true(RangedMetaData._needs_injection(t))
		end)

		it("returns true when action_shoot missing and no shoot input", function()
			local t = make_ranged_template({
				actions = { rapid_left = { start_input = "shoot_pressed" } },
				action_inputs = { shoot_pressed = { input_sequence = {} } },
			})
			assert.is_true(RangedMetaData._needs_injection(t))
		end)
	end)
end)
```

**Step 2: Write minimal implementation to make tests pass**

```lua
-- scripts/mods/BetterBots/ranged_meta_data.lua
local _mod -- luacheck: ignore 231
local _patched_set
local _debug_log

local function resolve_vanilla_fallback(weapon_template)
	local actions = weapon_template.actions or {}
	local aim_action = actions["action_zoom"] or {}
	local attack_action = actions["action_shoot"] or {}
	local aim_attack_action = actions["action_shoot_zoomed"] or {}
	return {
		fire_action_input = attack_action.start_input or "shoot",
		aim_action_input = aim_action.start_input or "zoom",
		aim_fire_action_input = aim_attack_action.start_input or "zoom_shoot",
	}
end

local function is_valid_input(weapon_template, input_name)
	local action_inputs = weapon_template.action_inputs
	return action_inputs ~= nil and action_inputs[input_name] ~= nil
end

local function needs_injection(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	return not is_valid_input(weapon_template, fallback.fire_action_input)
end

return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
	end,
	inject = function() end,
	_resolve_vanilla_fallback = resolve_vanilla_fallback,
	_needs_injection = needs_injection,
}
```

**Step 3: Run tests**

Run: `busted tests/ranged_meta_data_spec.lua`
Expected: 6 passing

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/ranged_meta_data.lua tests/ranged_meta_data_spec.lua
git commit -m "feat(#31): add ranged vanilla fallback resolution and validation"
```

---

### Task 2: Fire/aim input derivation

**Files:**
- Modify: `scripts/mods/BetterBots/ranged_meta_data.lua`
- Modify: `tests/ranged_meta_data_spec.lua`

**Step 1: Write the failing tests**

Add to `tests/ranged_meta_data_spec.lua` inside the main `describe` block:

```lua
	describe("find_fire_input", function()
		it("finds single action_one_pressed input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					reload = { input_sequence = {
						{ input = "weapon_reload_pressed", value = true },
					} },
				},
				actions = {
					action_shoot_hip = { start_input = "shoot_pressed" },
				},
			})
			local input, action = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_pressed", input)
			assert.equals("action_shoot_hip", action)
		end)

		it("disambiguates multiple candidates preferring shoot_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					shoot_charge = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_shoot_hip = { start_input = "shoot_pressed" },
					action_charge_direct = { start_input = "shoot_charge" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_pressed", input)
		end)

		it("disambiguates preferring shoot_charge when no shoot_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_charge = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
					shoot_braced = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					action_charge_direct = { start_input = "shoot_charge" },
					-- shoot_braced has no matching action start_input
				},
			})
			local input, action = RangedMetaData._find_fire_input(t)
			assert.equals("shoot_charge", input)
			assert.equals("action_charge_direct", action)
		end)

		it("filters out hold_input entries", function()
			local t = make_ranged_template({
				action_inputs = {
					trigger_explosion = { input_sequence = {
						{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
					} },
				},
				actions = {
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)

		it("filters chain-only inputs without matching start_input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_braced = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {
					-- No action has start_input = "shoot_braced"
					action_shoot_charged = { kind = "shoot_hit_scan" },
				},
			})
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)

		it("returns nil when no action_inputs", function()
			local t = make_ranged_template({ actions = {} })
			local input, _ = RangedMetaData._find_fire_input(t)
			assert.is_nil(input)
		end)
	end)

	describe("find_aim_input", function()
		it("finds action_two_hold input", function()
			local t = make_ranged_template({
				action_inputs = {
					zoom = { input_sequence = {
						{ input = "action_two_hold", value = true },
					} },
				},
				actions = {
					action_zoom = { start_input = "zoom" },
				},
			})
			local input, action = RangedMetaData._find_aim_input(t)
			assert.equals("zoom", input)
			assert.equals("action_zoom", action)
		end)

		it("returns nil when no action_two_hold input", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {},
			})
			local input, _ = RangedMetaData._find_aim_input(t)
			assert.is_nil(input)
		end)

		it("ignores action_two_hold release (value=false)", function()
			local t = make_ranged_template({
				action_inputs = {
					brace_release = { input_sequence = {
						{ input = "action_two_hold", value = false },
					} },
				},
				actions = {
					action_unbrace = { start_input = "brace_release" },
				},
			})
			local input, _ = RangedMetaData._find_aim_input(t)
			assert.is_nil(input)
		end)
	end)

	describe("find_aim_fire_input", function()
		it("finds input with hold_input and action_one_pressed", function()
			local t = make_ranged_template({
				action_inputs = {
					trigger_explosion = { input_sequence = {
						{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
					} },
				},
				actions = {
					action_explode = { start_input = "trigger_explosion" },
				},
			})
			local input, action = RangedMetaData._find_aim_fire_input(t)
			assert.equals("trigger_explosion", input)
			assert.equals("action_explode", action)
		end)

		it("returns nil when no hold_input entries", function()
			local t = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = {},
			})
			local input, _ = RangedMetaData._find_aim_fire_input(t)
			assert.is_nil(input)
		end)
	end)
```

**Step 2: Implement derivation functions**

Add to `ranged_meta_data.lua` before the `return` block:

```lua
local function find_action_for_input(weapon_template, input_name)
	for action_name, action in pairs(weapon_template.actions or {}) do
		if action.start_input == input_name then
			return action_name, action
		end
	end
	return nil, nil
end

local FIRE_INPUT_PREFERENCE = { "shoot_pressed", "shoot_charge" }

local function find_fire_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}
	local candidates = {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_one_pressed" and first.value == true and not first.hold_input then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					candidates[#candidates + 1] = { input_name = input_name, action_name = action_name }
				end
			end
		end
	end

	if #candidates == 0 then
		return nil, nil
	elseif #candidates == 1 then
		return candidates[1].input_name, candidates[1].action_name
	end

	for _, preferred in ipairs(FIRE_INPUT_PREFERENCE) do
		for _, c in ipairs(candidates) do
			if c.input_name == preferred then
				return c.input_name, c.action_name
			end
		end
	end

	return candidates[1].input_name, candidates[1].action_name
end

local function find_aim_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_two_hold" and first.value == true then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					return input_name, action_name
				end
			end
		end
	end

	return nil, nil
end

local function find_aim_fire_input(weapon_template)
	local action_inputs = weapon_template.action_inputs or {}

	for input_name, input_def in pairs(action_inputs) do
		local seq = input_def.input_sequence
		if seq and #seq > 0 then
			local first = seq[1]
			if first.input == "action_one_pressed" and first.value == true
				and first.hold_input == "action_two_hold" then
				local action_name = find_action_for_input(weapon_template, input_name)
				if action_name then
					return input_name, action_name
				end
			end
		end
	end

	return nil, nil
end
```

Update the `return` block to export all new functions:

```lua
return {
	init = function(deps)
		_mod = deps.mod
		_patched_set = deps.patched_weapon_templates
		_debug_log = deps.debug_log
	end,
	inject = function() end,
	_resolve_vanilla_fallback = resolve_vanilla_fallback,
	_needs_injection = needs_injection,
	_find_fire_input = find_fire_input,
	_find_aim_input = find_aim_input,
	_find_aim_fire_input = find_aim_fire_input,
}
```

**Step 3: Run tests**

Run: `busted tests/ranged_meta_data_spec.lua`
Expected: 17 passing (6 from Task 1 + 11 new)

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/ranged_meta_data.lua tests/ranged_meta_data_spec.lua
git commit -m "feat(#31): add fire/aim/aim-fire input derivation from action_inputs"
```

---

### Task 3: Build, inject, and integration tests

**Files:**
- Modify: `scripts/mods/BetterBots/ranged_meta_data.lua`
- Modify: `tests/ranged_meta_data_spec.lua`

**Step 1: Write the failing tests**

Add to `tests/ranged_meta_data_spec.lua`:

```lua
	describe("inject", function()
		it("injects attack_meta_data for weapon with broken fire input", function()
			-- Force staff pattern: no action_shoot, fire is rapid_left
			local templates = {
				forcestaff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						wield = { input_sequence = {
							{ input = "weapon_extra_pressed", value = true },
						} },
					},
					actions = {
						rapid_left = { start_input = "shoot_pressed", kind = "spawn_projectile" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.forcestaff.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_pressed", meta.fire_action_input)
			assert.equals("rapid_left", meta.fire_action_name)
		end)

		it("sets fire_action_input but keeps fire_action_name default when action_shoot exists", function()
			-- Plasma pattern: action_shoot exists but start_input is nil
			local templates = {
				plasma = make_ranged_template({
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

			local meta = templates.plasma.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_charge", meta.fire_action_input)
			assert.is_nil(meta.fire_action_name) -- action_shoot exists, keep default
		end)

		it("also injects aim fields when aim input is invalid", function()
			local templates = {
				exotic = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
						brace_pressed = { input_sequence = {
							{ input = "action_two_hold", value = true },
						} },
						trigger_explosion = { input_sequence = {
							{ input = "action_one_pressed", value = true, hold_input = "action_two_hold" },
						} },
					},
					actions = {
						rapid_left = { start_input = "shoot_pressed" },
						action_brace = { start_input = "brace_pressed" },
						action_explode = { start_input = "trigger_explosion" },
					},
				}),
			}

			RangedMetaData.inject(templates)

			local meta = templates.exotic.attack_meta_data
			assert.is_table(meta)
			assert.equals("shoot_pressed", meta.fire_action_input)
			assert.equals("brace_pressed", meta.aim_action_input)
			assert.equals("action_brace", meta.aim_action_name)
			assert.equals("trigger_explosion", meta.aim_fire_action_input)
			assert.equals("action_explode", meta.aim_fire_action_name)
		end)

		it("skips weapons where vanilla fallback is valid", function()
			local templates = {
				lasgun = make_ranged_template({
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

			assert.is_nil(templates.lasgun.attack_meta_data)
		end)

		it("skips non-ranged weapons", function()
			local templates = {
				sword = {
					keywords = { "melee", "combat_sword" },
					actions = {},
					action_inputs = {},
				},
			}

			RangedMetaData.inject(templates)

			assert.is_nil(templates.sword.attack_meta_data)
		end)

		it("does not overwrite existing attack_meta_data", function()
			local existing = { fire_action_input = "custom" }
			local template = make_ranged_template({
				action_inputs = {
					shoot_pressed = { input_sequence = {
						{ input = "action_one_pressed", value = true },
					} },
				},
				actions = { rapid_left = { start_input = "shoot_pressed" } },
			})
			template.attack_meta_data = existing
			local templates = { staff = template }

			RangedMetaData.inject(templates)

			assert.equals(existing, templates.staff.attack_meta_data)
		end)

		it("is idempotent for the same table", function()
			local templates = {
				staff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = { rapid_left = { start_input = "shoot_pressed" } },
				}),
			}

			RangedMetaData.inject(templates)
			local first_meta = templates.staff.attack_meta_data

			RangedMetaData.inject(templates)
			assert.equals(first_meta, templates.staff.attack_meta_data)
		end)

		it("skips non-table entries in WeaponTemplates", function()
			local templates = {
				staff = make_ranged_template({
					action_inputs = {
						shoot_pressed = { input_sequence = {
							{ input = "action_one_pressed", value = true },
						} },
					},
					actions = { rapid_left = { start_input = "shoot_pressed" } },
				}),
				_version = 42,
			}

			assert.has_no.errors(function()
				RangedMetaData.inject(templates)
			end)
			assert.is_table(templates.staff.attack_meta_data)
		end)

		it("handles weapon with no derivable fire input", function()
			local templates = {
				broken = make_ranged_template({
					action_inputs = {
						reload = { input_sequence = {
							{ input = "weapon_reload_pressed", value = true },
						} },
					},
					actions = {},
				}),
			}

			assert.has_no.errors(function()
				RangedMetaData.inject(templates)
			end)
			assert.is_nil(templates.broken.attack_meta_data)
		end)
	end)
```

**Step 2: Implement build_meta_data, inject, and has_keyword**

Add to `ranged_meta_data.lua`:

```lua
local function has_keyword(weapon_template, keyword)
	for _, kw in ipairs(weapon_template.keywords or {}) do
		if kw == keyword then
			return true
		end
	end
	return false
end

local function build_meta_data(weapon_template)
	local fallback = resolve_vanilla_fallback(weapon_template)
	local meta = {}
	local changed = false

	if not is_valid_input(weapon_template, fallback.fire_action_input) then
		local fire_input, fire_action = find_fire_input(weapon_template)
		if fire_input then
			meta.fire_action_input = fire_input
			if not (weapon_template.actions or {})["action_shoot"] then
				meta.fire_action_name = fire_action
			end
			changed = true
		end
	end

	if not is_valid_input(weapon_template, fallback.aim_action_input) then
		local aim_input, aim_action = find_aim_input(weapon_template)
		if aim_input then
			meta.aim_action_input = aim_input
			if not (weapon_template.actions or {})["action_zoom"] then
				meta.aim_action_name = aim_action
			end
			changed = true
		end
	end

	if not is_valid_input(weapon_template, fallback.aim_fire_action_input) then
		local aim_fire_input, aim_fire_action = find_aim_fire_input(weapon_template)
		if aim_fire_input then
			meta.aim_fire_action_input = aim_fire_input
			if not (weapon_template.actions or {})["action_shoot_zoomed"] then
				meta.aim_fire_action_name = aim_fire_action
			end
			changed = true
		end
	end

	return changed and meta or nil
end

local function inject(WeaponTemplates)
	if _patched_set[WeaponTemplates] then
		return
	end

	local injected = 0
	local skipped = 0

	for _, template in pairs(WeaponTemplates) do -- luacheck: ignore 213
		if type(template) == "table" and has_keyword(template, "ranged") then
			if template.attack_meta_data then
				skipped = skipped + 1
			else
				local meta = build_meta_data(template)
				if meta then
					template.attack_meta_data = meta
					injected = injected + 1
				end
			end
		end
	end

	_patched_set[WeaponTemplates] = true
	_debug_log(
		"ranged_meta_injection:" .. tostring(WeaponTemplates),
		0,
		"ranged attack_meta_data patch installed (injected=" .. injected .. ", skipped=" .. skipped .. ")"
	)
end
```

Replace the stub `inject` in the return block with the real one, and also export `_needs_injection` (already done) plus `_find_fire_input`, `_find_aim_input`, `_find_aim_fire_input` (already done).

**Step 3: Run tests**

Run: `busted tests/ranged_meta_data_spec.lua`
Expected: 26 passing (17 from Tasks 1-2 + 9 new)

Run: `make check`
Expected: All tests pass, 0 lint warnings

**Step 4: Commit**

```bash
git add scripts/mods/BetterBots/ranged_meta_data.lua tests/ranged_meta_data_spec.lua
git commit -m "feat(#31): add ranged attack_meta_data build and injection"
```

---

### Task 4: Integration in BetterBots.lua + docs

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots.lua:157-216` (module load + init)
- Modify: `scripts/mods/BetterBots/BetterBots.lua:695-697` (hook_require)
- Modify: `docs/dev/architecture.md` (add entry 20)
- Modify: `docs/BATCH_TEST_m4-batch1.md` (add #31)

**Step 1: Load and init the module**

In `BetterBots.lua`, after the `MeleeMetaData` load block (~line 158):

```lua
local RangedMetaData = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ranged_meta_data")
assert(RangedMetaData, "BetterBots: failed to load ranged_meta_data module")
```

After `MeleeMetaData.init({...})` (~line 216):

```lua
RangedMetaData.init({
	mod = mod,
	patched_weapon_templates = _patched_weapon_templates,
	debug_log = _debug_log,
})
```

**Step 2: Add to hook_require**

In the existing `weapon_templates` hook (~line 695-697), add the ranged call:

```lua
mod:hook_require("scripts/settings/equipment/weapon_templates/weapon_templates", function(WeaponTemplates)
	MeleeMetaData.inject(WeaponTemplates)
	RangedMetaData.inject(WeaponTemplates)
end)
```

**Step 3: Update docs**

In `docs/dev/architecture.md`:
- Update the count from "nineteen" to "twenty"
- Add entry 20 describing ranged `attack_meta_data` injection

In `docs/BATCH_TEST_m4-batch1.md`:
- Add #31 to the feature table with `needs-testing` status
- Add acceptance criteria section

**Step 4: Run `make check`**

Run: `make check`
Expected: All tests pass (previous count + 26 new ranged tests), 0 warnings

**Step 5: Commit**

```bash
git add scripts/mods/BetterBots/BetterBots.lua docs/dev/architecture.md docs/BATCH_TEST_m4-batch1.md
git commit -m "feat(#31): integrate ranged attack_meta_data injection into main module"
```

---

### Summary

| Task | Tests | What |
|------|-------|------|
| 1 | 6 | Vanilla fallback resolution + validation |
| 2 | 11 | Fire/aim/aim-fire input derivation |
| 3 | 9 | Build + inject with full integration tests |
| 4 | 0 | Wire into BetterBots.lua + docs |
| **Total** | **26** | |
