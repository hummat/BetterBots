# Weapon Specials And Brain Burst Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BetterBots special-attack logic family-specific and talent-aware: de-prioritize redundant manual Brain Burst when `psyker_smite_on_hit` is equipped, split melee special policies by actual weapon family, and add a first-pass ranged special loader for shotgun special shells.

**Architecture:** Keep the Brain Burst change in the existing grenade heuristic path, keep melee special sequencing inside `melee_attack_choice.lua`, and add one small ranged-special module beside `weapon_action.lua` rather than burying shotgun logic in `sustained_fire.lua`. Extend context only where a verified source fact is currently missing from BetterBots state (`target_is_bomber`), and keep mauls / Ogryn melee specials / shield block-charge families explicitly out of scope for this pass.

**Tech Stack:** Lua 5.5, busted, DMF hook modules, local `../Darktide-Source-Code/` decompiled source, Makefile, git

---

## Verified Audit Findings

- `scripts/mods/BetterBots/melee_attack_choice.lua` currently conflates Veteran 1H `powersword_*` and Zealot 2H `powersword_2h_*` because the matcher uses the broad prefix `powersword_`.
- Current powered melee resolver misses a real action-kind path: Zealot 2H `powersword_2h_p1_*` templates contain one `kind = "toggle_special"` action in addition to `toggle_special_with_block`.
- `psyker_smite_on_hit` is not a vague proc. Decompiled source shows `smite_chance = 1`, `cooldown = 12`, `proc_events.on_hit`, and the proc explicitly excludes bombers. Manual Brain Burst should therefore be de-prioritized, not shut off, and bomber handling must stay live.
- Chain / thunder hammer / power sword usage should be target-value logic, not “overuse is always good.” Keep `_can_activate_special()` intact.
- Power mauls, Ogryn clubs/uppercuts, slab shields, and other “special_action starts a sweep/block_windup” families are real, but they are a second-pass resolver problem, not part of the first shipment.

## Scope Boundaries

**In scope for this pass**
- `psyker_smite_on_hit` Brain Burst carve-out, including bomber preservation
- Melee family split for `powersword_*`, `powersword_2h_*`, `forcesword_*`, `forcesword_2h_*`, `thunderhammer_*`, and chain families
- First-pass ranged special support for `ranged_load_special` shotguns only: `shotgun_p1_m1/m2/m3`, `shotgun_p4_m1/m2`
- Logging needed to validate shotgun special-shell spend quality

**Explicitly out of scope for this pass**
- Power mauls, riot/power shields, slab shield special-charge behavior
- Ogryn club / cleaver / shovel / pickaxe uppercuts and fold specials
- Rippergun specials
- Bayonet / pistol-whip / bash-style ranged specials
- Cooldown-aware tracking of whether `psyker_smite_on_hit` is presently available; this pass is talent-aware de-prioritization, not exact proc-state modeling

## File Map

**Existing production files to modify**
- `scripts/mods/BetterBots/heuristics_context.lua`
- `scripts/mods/BetterBots/heuristics_grenade.lua`
- `scripts/mods/BetterBots/melee_attack_choice.lua`
- `scripts/mods/BetterBots/weapon_action.lua`
- `scripts/mods/BetterBots/BetterBots.lua`

**New production file**
- `scripts/mods/BetterBots/ranged_special_action.lua`

**Existing tests to modify**
- `tests/heuristics_spec.lua`
- `tests/melee_attack_choice_spec.lua`
- `tests/startup_regressions_spec.lua`

**New test file**
- `tests/ranged_special_action_spec.lua`

**Docs to update when implementation lands**
- `docs/classes/psyker.md`
- `docs/classes/psyker-tactics.md`
- `docs/dev/roadmap.md`
- `docs/dev/debugging.md`
- `docs/dev/architecture.md`
- `README.md`
- `AGENTS.md`

---

### Task 1: Brain Burst Talent-Aware Carve-Out

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics_context.lua`
- Modify: `scripts/mods/BetterBots/heuristics_grenade.lua`
- Modify: `tests/heuristics_spec.lua`
- Modify: `tests/test_helper.lua`
- Modify: `docs/classes/psyker.md`
- Modify: `docs/classes/psyker-tactics.md`
- Modify: `docs/dev/roadmap.md`

- [ ] **Step 1: Add red tests for the new Brain Burst rules**

Extend `tests/heuristics_spec.lua` near the existing `psyker_smite` cases with these cases:

```lua
it("de-prioritizes manual Brain Burst on ordinary elite/special targets when psyker_smite_on_hit is equipped", function()
	local result, rule = Heuristics.evaluate_grenade_heuristic(
		"psyker_smite",
		helper.make_context({
			talents = { psyker_smite_on_hit = 1 },
			target_enemy = "trapper",
			target_is_elite_special = true,
			target_enemy_distance = 12,
			peril_pct = 0.50,
		})
	)
	assert.is_false(result)
	assert.matches("proc_cover", rule)
end)

it("keeps manual Brain Burst live for bombers even when psyker_smite_on_hit is equipped", function()
	local result, rule = Heuristics.evaluate_grenade_heuristic(
		"psyker_smite",
		helper.make_context({
			talents = { psyker_smite_on_hit = 1 },
			target_enemy = "poxburster",
			target_is_elite_special = true,
			target_is_bomber = true,
			target_enemy_distance = 12,
			peril_pct = 0.50,
		})
	)
	assert.is_true(result)
	assert.matches("priority", rule)
end)

it("keeps manual Brain Burst live for super-armor when psyker_smite_on_hit is equipped", function()
	local result, rule = Heuristics.evaluate_grenade_heuristic(
		"psyker_smite",
		helper.make_context({
			talents = { psyker_smite_on_hit = 1 },
			target_enemy = "crusher",
			target_is_super_armor = true,
			target_enemy_distance = 12,
			peril_pct = 0.50,
		})
	)
	assert.is_true(result)
	assert.matches("super_armor", rule)
end)
```

- [ ] **Step 2: Run the targeted heuristics spec and confirm it fails**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/heuristics_spec.lua
```

Expected:
- the proc-cover case fails because `_grenade_smite` has no `psyker_smite_on_hit` branch
- the bomber-preservation case fails because the current heuristic still treats bombers like ordinary elite/special priority targets

- [ ] **Step 3: Add the missing target context bit**

In `scripts/mods/BetterBots/heuristics_context.lua`, add `target_is_bomber` to the default context and populate it from the target breed tags:

```lua
	target_is_bomber = false,
```

and:

```lua
			context.target_is_bomber = _is_tagged(tags, "bomber")
```

Mirror the same default in `tests/test_helper.lua` so spec contexts stay aligned with runtime contexts:

```lua
		target_is_bomber = false,
```

Do not add a generic `target_breed_tags` blob. This pass only needs one verified flag that BetterBots does not already expose.

- [ ] **Step 4: Implement the Brain Burst carve-out in `_grenade_smite`**

Add a tiny local helper in `scripts/mods/BetterBots/heuristics_grenade.lua`:

```lua
local function _has_talent(context, talent_name)
	local talents = context and context.talents or nil
	return type(talents) == "table" and talents[talent_name] ~= nil
end
```

Then add a de-prioritization branch inside `_grenade_smite` after `is_hard_target` / `is_explicit_priority_target` are resolved:

```lua
	local has_smite_on_hit = _has_talent(context, "psyker_smite_on_hit")

	if
		has_smite_on_hit
		and context.target_is_elite_special
		and not context.target_is_bomber
		and not context.target_is_super_armor
		and not _is_monster_signal_allowed(context)
		and not is_explicit_priority_target
	then
		return false, "grenade_smite_block_proc_cover"
	end
```

Rules for this first pass:
- keep current peril / melee-pressure / range guards
- keep bombers live because the proc explicitly excludes them
- keep super-armor and monsters live
- keep explicit long-range priority targets live
- do **not** add guessed proc-cooldown modeling

- [ ] **Step 5: Re-run the heuristics spec and confirm it passes**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/heuristics_spec.lua
```

Expected:
- all `psyker_smite` cases pass, including the new bomber carve-out

- [ ] **Step 6: Update the Psyker docs in the same commit**

Sync these docs:
- `docs/classes/psyker.md`: state that `psyker_smite_on_hit` de-prioritizes manual Brain Burst on ordinary elites/specials but preserves bombers / monsters / super-armor
- `docs/classes/psyker-tactics.md`: add the same tactical note to the Brain Burst section
- `docs/dev/roadmap.md`: update the post-1.0 broad special-work wording so Brain Burst talent-awareness is no longer implied to be untouched

- [ ] **Step 7: Commit**

```bash
git add scripts/mods/BetterBots/heuristics_context.lua scripts/mods/BetterBots/heuristics_grenade.lua tests/heuristics_spec.lua tests/test_helper.lua docs/classes/psyker.md docs/classes/psyker-tactics.md docs/dev/roadmap.md
git commit -m "fix(psyker): de-prioritize manual brain burst with smite-on-hit"
```

---

### Task 2: Split Melee Special Policy By Actual Weapon Family

**Files:**
- Modify: `scripts/mods/BetterBots/melee_attack_choice.lua`
- Modify: `tests/melee_attack_choice_spec.lua`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/debugging.md`

- [ ] **Step 1: Add red tests for family split and the 2H power sword bug**

Extend `tests/melee_attack_choice_spec.lua` using the same `enter_handler` / `choose_attack_handler` harness shape that the existing chain-family tests already use.

Add this exact metadata-resolution case:

```lua
it("resolves powersword_2h specials through enter when the template uses toggle_special", function()
	local MeleeAttackChoice = load_module()
	local enter_handler
	local stub_mod = {
		hook = function(_, _, method_name, handler)
			if method_name == "enter" then
				enter_handler = handler
			end
		end,
	}

	_G.ScriptUnit = {
		has_extension = function()
			return {
				read_component = function(_, component_name)
					if component_name == "inventory" then
						return { wielded_slot = "slot_primary" }
					end
					if component_name == "slot_primary" then
						return { special_active = false }
					end
					return nil
				end,
			}
		end,
	}

	MeleeAttackChoice.init({
		mod = stub_mod,
		debug_log = function() end,
		debug_enabled = function()
			return false
		end,
		fixed_time = function()
			return 13
		end,
		ARMOR_TYPE_ARMORED = ARMORED,
		ARMOR_TYPE_SUPER_ARMOR = SUPER_ARMOR,
	})

	MeleeAttackChoice.install_melee_hooks({})

	local scratchpad = {
		weapon_template = {
			name = "powersword_2h_p1_m1",
			actions = {
				action_toggle_special = {
					start_input = "special_action",
					kind = "toggle_special",
					allowed_chain_actions = {
						start_attack = { chain_time = 0.2 },
					},
				},
			},
		},
	}

	enter_handler(function() end, nil, "bot_unit", nil, nil, scratchpad, nil, 13)

	assert.equals("special_action", scratchpad.special_action_meta.action_input)
	assert.equals("powersword_2h", scratchpad.special_action_meta.family)
end)
```

Then add these concrete wrap/no-wrap cases using the existing `special_action_meta`, `inventory_slot_component`, and `weapon_extension.action_input_is_currently_valid` fixtures already present in this spec:
- a `powersword_1h` no-wrap case: `num_enemies_in_proximity = 1`, unarmored non-elite target, assert the chosen attack still starts with `"start_attack"` rather than `"special_action"`
- a `powersword_1h` wrap case: `num_enemies_in_proximity = 3`, ordinary melee pressure, assert the chosen attack starts with `"special_action"`
- a `forcesword_1h` no-wrap case: ordinary trash target, assert no special prelude
- a `thunderhammer` wrap case: armored elite target, assert special prelude is added
- a `chain` no-wrap case for an unarmored specialist target, plus a wrap case for an armored elite target

- [ ] **Step 2: Run the melee spec and confirm the new cases fail**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/melee_attack_choice_spec.lua
```

Expected:
- the `powersword_2h` metadata case fails because `toggle_special` is not allowed today
- family-specific target-policy cases fail because `powered` is still one shared bucket

- [ ] **Step 3: Replace the broad `powered` bucket with explicit family entries**

In `scripts/mods/BetterBots/melee_attack_choice.lua`, replace `SPECIAL_WEAPON_POLICIES` with explicit families:

```lua
local SPECIAL_WEAPON_POLICIES = {
	{
		family = "powersword_1h",
		prefixes = { "powersword_p1_", "powersword_p2_" },
		action_kinds = {
			activate_special = true,
			toggle_special_with_block = true,
		},
	},
	{
		family = "powersword_2h",
		prefixes = { "powersword_2h_" },
		action_kinds = {
			toggle_special = true,
			toggle_special_with_block = true,
		},
	},
	{
		family = "forcesword_1h",
		prefixes = { "forcesword_p1_" },
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "forcesword_2h",
		prefixes = { "forcesword_2h_" },
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "thunderhammer",
		prefixes = { "thunderhammer_" },
		action_kinds = {
			activate_special = true,
		},
	},
	{
		family = "chain",
		prefixes = { "chainaxe_", "chainsword_" },
		action_kinds = {
			toggle_special = true,
		},
	},
}
```

Do **not** remove `_can_activate_special()`.

- [ ] **Step 4: Replace the single target helper with family-specific target-value logic**

Refactor `_is_priority_special_target(...)` so it receives `scratchpad` and dispatches by family:

```lua
local function _is_power_sword_target(scratchpad, target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	local num_nearby = scratchpad and scratchpad.num_enemies_in_proximity or 0

	if target_breed and (target_breed.is_boss or (tags and (tags.monster or tags.captain or tags.elite or tags.special))) then
		return true
	end

	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end

	return num_nearby >= 2
end

local function _is_force_sword_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	return (tags and (tags.elite or tags.special or tags.monster)) or (_super_armor_type ~= nil and target_armor == _super_armor_type)
end

local function _is_thunder_hammer_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	if target_breed and (target_breed.is_boss or (tags and (tags.monster or tags.captain))) then
		return true
	end
	return (tags and tags.elite and target_armor ~= nil and target_armor >= _armored_type) or (_super_armor_type ~= nil and target_armor == _super_armor_type)
end

local function _is_chain_target(target_breed, target_armor)
	local tags = target_breed and target_breed.tags or nil
	if target_breed and (target_breed.is_boss or (tags and (tags.monster or tags.captain))) then
		return true
	end
	if _super_armor_type ~= nil and target_armor == _super_armor_type then
		return true
	end
	return tags and tags.elite and target_armor ~= nil and target_armor >= _armored_type or false
end
```

Use the same helper for 1H and 2H power swords in v1. The structural split matters even if the first-pass target policy is shared.

- [ ] **Step 5: Update the wrap call-site and debug family label**

Change `_maybe_wrap_special_attack(...)` and its caller to pass `scratchpad` into the family dispatcher, and keep the debug log family output truthful:

```lua
chosen, wrapped_special = _maybe_wrap_special_attack(target_breed, target_armor, scratchpad, chosen)
```

When logging, emit the resolved family value rather than the old `"powered"` fallback string.

- [ ] **Step 6: Re-run the melee spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/melee_attack_choice_spec.lua
```

Expected:
- all new family split and target-value tests pass

- [ ] **Step 7: Update roadmap + debugging docs in the same commit**

Sync:
- `docs/dev/roadmap.md`: replace the stale “powered families keep the original elite/specialist trigger” wording with the new family split
- `docs/dev/debugging.md`: document the new special-family debug keys if the log text changes materially

- [ ] **Step 8: Commit**

```bash
git add scripts/mods/BetterBots/melee_attack_choice.lua tests/melee_attack_choice_spec.lua docs/dev/roadmap.md docs/dev/debugging.md
git commit -m "refactor(melee): split weapon special policy by family"
```

---

### Task 3: Add Shotgun Special-Shell Support As A Dedicated Module

**Files:**
- Add: `scripts/mods/BetterBots/ranged_special_action.lua`
- Modify: `scripts/mods/BetterBots/weapon_action.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Add: `tests/ranged_special_action_spec.lua`
- Modify: `tests/startup_regressions_spec.lua`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/debugging.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add red unit tests for the shotgun classifier**

Create `tests/ranged_special_action_spec.lua` with focused cases:

```lua
local RangedSpecialAction = dofile("scripts/mods/BetterBots/ranged_special_action.lua")
local SUPER_ARMOR = 6

local function make_state(opts)
	opts = opts or {}
	return {
		template_name = opts.template_name,
		action_input_is_valid = opts.action_input_is_valid ~= false,
		special_active = opts.special_active == true,
		target_breed_name = opts.target_breed_name or "renegade_gunner",
		target_tags = opts.target_tags or {},
		target_armor = opts.target_armor,
	}
end

describe("ranged_special_action", function()
	it("rewrites a supported shotgun fire input into special_action for armored or priority targets", function()
		local rewritten = RangedSpecialAction.rewrite_weapon_action_input(
			make_state({
				template_name = "shotgun_p1_m1",
				special_active = false,
				target_breed_name = "renegade_captain",
				target_tags = { elite = true },
			}),
			"shoot_pressed",
			nil
		)

		assert.equals("special_action", rewritten)
	end)

	it("does not rewrite unsupported shotgun bash templates", function()
		local rewritten = RangedSpecialAction.rewrite_weapon_action_input(
			make_state({
				template_name = "shotgun_p2_m1",
				special_active = false,
				target_breed_name = "renegade_gunner",
				target_tags = { elite = true },
			}),
			"shoot_pressed",
			nil
		)

		assert.equals("shoot_pressed", rewritten)
	end)

	it("does not rewrite rippergun fire into a shotgun special", function()
		local rewritten = RangedSpecialAction.rewrite_weapon_action_input(
			make_state({
				template_name = "ogryn_rippergun_p1_m1",
				special_active = false,
				target_breed_name = "renegade_gunner",
				target_tags = { elite = true },
			}),
			"shoot_pressed",
			nil
		)

		assert.equals("shoot_pressed", rewritten)
	end)

	it("logs a shotgun special spend against the remembered target breed", function()
		local messages = {}

		RangedSpecialAction.init({
			debug_log = function(_key, _t, message)
				messages[#messages + 1] = message
			end,
			debug_enabled = function()
				return true
			end,
			fixed_time = function()
				return 13
			end,
			bot_slot_for_unit = function()
				return 2
			end,
		})

		local state = make_state({
			template_name = "shotgun_p1_m1",
			special_active = false,
			target_breed_name = "chaos_ogryn_bulwark",
			target_tags = { elite = true },
			target_armor = SUPER_ARMOR,
		})

		assert.equals("special_action", RangedSpecialAction.rewrite_weapon_action_input(state, "shoot_pressed", nil))
		RangedSpecialAction.observe_queued_weapon_action(state, "shoot_pressed")

		assert.matches("chaos_ogryn_bulwark", messages[#messages])
	end)
end)
```

Keep the test harness local to the file. Do not teach `weapon_action_spec.lua` about shotgun-family internals.

- [ ] **Step 2: Run the new spec and confirm it fails**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ranged_special_action_spec.lua
```

Expected:
- file missing or spec failing because the module does not exist yet

- [ ] **Step 3: Create the module and keep it narrowly scoped**

Create `scripts/mods/BetterBots/ranged_special_action.lua` with one responsibility: classify supported shotgun special-shell loading and log spend quality.

Start from this shape:

```lua
local _debug_log
local _debug_enabled
local _fixed_time
local _bot_slot_for_unit

local _armed_units = setmetatable({}, { __mode = "k" })

local SUPPORTED_SPECIAL_SHELL_TEMPLATES = {
	shotgun_p1_m1 = true,
	shotgun_p1_m2 = true,
	shotgun_p1_m3 = true,
	shotgun_p4_m1 = true,
	shotgun_p4_m2 = true,
}

local FIRE_INPUTS = {
	shoot = true,
	shoot_pressed = true,
	shoot_braced = true,
}

local M = {}

function M.init(deps)
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_fixed_time = deps.fixed_time
	_bot_slot_for_unit = deps.bot_slot_for_unit
end

function M.rewrite_weapon_action_input(state, action_input)
	-- return original action_input unless a supported shotgun should load a shell first
end

function M.observe_queued_weapon_action(unit, action_input)
	-- if a previously armed shotgun now fires, emit one spend-quality log keyed by target breed
end

return M
```

Module rules:
- support only the five verified `ranged_load_special` shotgun templates
- do not touch `shotgun_p2_m1`
- do not touch ripperguns
- use weak-key state to avoid permanent per-unit storage

- [ ] **Step 4: Add the pre-queue rewrite seam to `weapon_action.lua`**

Extend `WeaponAction.register_hooks(...)` to accept a new optional dependency:

```lua
local rewrite_weapon_action_input = deps.rewrite_weapon_action_input
```

Then, inside the `bot_queue_action_input` hook and before `func(self, id, action_input, raw_input)`:

```lua
if unit and id == "weapon_action" and rewrite_weapon_action_input then
	local rewritten_input, rewritten_raw_input = rewrite_weapon_action_input(unit, action_input, raw_input)
	action_input = rewritten_input or action_input
	raw_input = rewritten_raw_input
end
```

Do not move shotgun logic into `weapon_action.lua`; the file should only expose the seam.

- [ ] **Step 5: Wire the new module in `BetterBots.lua`**

Load and initialize the module beside `WeaponAction` / `SustainedFire`:

```lua
local RangedSpecialAction = mod:io_dofile("BetterBots/scripts/mods/BetterBots/ranged_special_action")
assert(RangedSpecialAction, "BetterBots: failed to load ranged_special_action module")
```

and:

```lua
RangedSpecialAction.init({
	debug_log = Debug.log,
	debug_enabled = Debug.is_enabled,
	fixed_time = Debug.fixed_time,
	bot_slot_for_unit = Debug.bot_slot_for_unit,
})
```

Then pass both the rewrite seam and a combined observer into `WeaponAction.register_hooks(...)`:

```lua
local function _observe_queued_weapon_action(unit, action_input)
	SustainedFire.observe_queued_weapon_action(unit, action_input)
	RangedSpecialAction.observe_queued_weapon_action(unit, action_input)
end

WeaponAction.register_hooks({
	should_lock_weapon_switch = _should_lock_weapon_switch,
	should_block_wield_input = _should_block_wield_input,
	should_block_weapon_action_input = _should_block_weapon_action_input,
	rewrite_weapon_action_input = RangedSpecialAction.rewrite_weapon_action_input,
	observe_queued_weapon_action = _observe_queued_weapon_action,
	install_weakspot_aim = WeakspotAim.install_on_shoot_action,
})
```

- [ ] **Step 6: Add spend-quality logging**

When a supported shotgun rewrites a fire input into `special_action`, log:

```lua
_debug_log(
	"shotgun_special_arm:" .. tostring(bot_slot) .. ":" .. tostring(template_name),
	_fixed_time(),
	"armed shotgun special for " .. tostring(template_name) .. " target=" .. tostring(target_breed_name)
)
```

When a previously armed supported shotgun later queues a fire input, log:

```lua
_debug_log(
	"shotgun_special_spend:" .. tostring(bot_slot) .. ":" .. tostring(template_name),
	_fixed_time(),
	"spent shotgun special for " .. tostring(template_name) .. " target=" .. tostring(target_breed_name)
)
```

The point of the log is validation, not telemetry volume. One-shot the log per arm/spend event pair.

- [ ] **Step 7: Add startup regression coverage for the new module**

Update `tests/startup_regressions_spec.lua` to:
- stub `modules.RangedSpecialAction`
- add the `mod:io_dofile("BetterBots/scripts/mods/BetterBots/ranged_special_action")` mapping
- assert that `WeaponAction.register_hooks(...)` receives a `rewrite_weapon_action_input` function
- assert the combined observer still keeps `SustainedFire.observe_queued_weapon_action` wired

- [ ] **Step 8: Run targeted specs**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ranged_special_action_spec.lua
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua
```

Expected:
- the new ranged special module spec passes
- startup regression harness passes with the new load/wire seam

- [ ] **Step 9: Update module and test inventories in docs**

Because this task adds a new runtime module and a new spec file, update:
- `docs/dev/architecture.md`
- `README.md`
- `AGENTS.md`
- `docs/dev/debugging.md`

At minimum, document:
- the existence and responsibility of `ranged_special_action.lua`
- the new `shotgun_special_arm` / `shotgun_special_spend` debug patterns
- the extra test file in the test inventory

- [ ] **Step 10: Commit**

```bash
git add scripts/mods/BetterBots/ranged_special_action.lua scripts/mods/BetterBots/weapon_action.lua scripts/mods/BetterBots/BetterBots.lua tests/ranged_special_action_spec.lua tests/startup_regressions_spec.lua docs/dev/architecture.md docs/dev/debugging.md README.md AGENTS.md
git commit -m "feat(ranged): add shotgun special-shell prelude support"
```

---

### Task 4: Final Verification And Validation Notes

**Files:**
- Modify only if validation wording changed during implementation:
  - `docs/dev/status.md`
  - `docs/dev/validation-tracker.md`

- [ ] **Step 1: Run the local quality gate**

Run:

```bash
make check-ci
```

Expected:
- format/lint/LSP/tests/doc checks all pass

- [ ] **Step 2: Prepare in-game validation checklist before launch**

Validation must cover these exact cases:
- Psyker control run **without** `psyker_smite_on_hit`
- Psyker run **with** `psyker_smite_on_hit`
- one explicit bomber Brain Burst check in the talent-enabled run
- one 1H power sword run
- one thunder hammer or chain-family heavy-target run
- one shotgun run with shell-load and shell-spend evidence

- [ ] **Step 3: Capture the exact log evidence after each run**

Run:

```bash
./bb-log summary
./bb-log warnings
./bb-log raw 'grenade_smite'
./bb-log raw 'special_attack'
./bb-log raw 'shotgun_special'
```

Expected runtime markers:
- Brain Burst proc-cover suppression fires on ordinary elites/specials when the talent is present
- bomber Brain Burst still fires
- power sword / thunder hammer / chain family special-prelude logs reflect the new family names
- shotgun special-shell arm/spend logs include target breed names

- [ ] **Step 4: Update validation docs only after live evidence exists**

If the runs are successful, sync:
- `docs/dev/validation-tracker.md`
- `docs/dev/status.md`

Do not pre-emptively mark these issues validated before the mission evidence exists.

---

## Commit Sequence

1. `fix(psyker): de-prioritize manual brain burst with smite-on-hit`
2. `refactor(melee): split weapon special policy by family`
3. `feat(ranged): add shotgun special-shell prelude support`
4. Validation/doc follow-up commit only if live testing changes status tables

## Residual Risk

- The first-pass Brain Burst carve-out is talent-aware, not proc-cooldown-aware. That is acceptable for this scope, but if live play shows “proc was just spent, second elite appears immediately” regressions, that becomes a second-pass buff-state problem.
- Power mauls and Ogryn melee specials are intentionally deferred. Do not “just add one more family” while implementing Task 2.
- The shotgun path depends on a reliable armed/spend signal. If `inventory_slot_component.special_active` does not behave consistently for the supported shotguns, keep the scope and fall back to unit-local arm/spend bookkeeping instead of widening the seam.
