# Heuristics Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `scripts/mods/BetterBots/heuristics.lua` into DMF-safe context/class/grenade modules without changing the public `Heuristics` API or game behavior.

**Architecture:** `scripts/mods/BetterBots/BetterBots.lua` remains the only loader of BetterBots-local modules via `mod:io_dofile`. The new leaf modules export pure tables/functions and optional `init({...})` hooks; the thin `heuristics.lua` orchestrator initializes them, merges exported template/item/grenade maps, keeps testing-profile overrides plus the public `build_context()` / `resolve_decision()` / `evaluate_*()` API, and delegates shared context work to `heuristics_context.lua`.

**Tech Stack:** Lua, busted, DMF `mod:io_dofile`, repo doc inventories, `make check-ci`

---

## Preconditions

- Execute this only after Batch 1 in [2026-04-16-pre-v1-0-0-test-refactor.md](/run/media/matthias/1274B04B74B032F9/git/BetterBots/docs/superpowers/plans/2026-04-16-pre-v1-0-0-test-refactor.md) is merged.
- Pin all extraction steps to source commit `e4fc545e3332a870090518cf6541348c874e6f1f` so later commits do not shift source ranges mid-plan.
- Do not add `require("scripts/mods/BetterBots/...")` or `dofile("scripts/mods/BetterBots/...")` inside leaf modules. Runtime loading must stay in `BetterBots.lua`.

## File Map

### New source files

- Create: `scripts/mods/BetterBots/heuristics_context.lua`
  - Shared engine-facing helpers: `build_context`, `normalize_grenade_context`, `enemy_breed`, dormant-daemonhost-safe monster helper.
- Create: `scripts/mods/BetterBots/heuristics_veteran.lua`
  - Veteran thresholds, stealth heuristic, shout/stance semantic dispatch.
- Create: `scripts/mods/BetterBots/heuristics_zealot.lua`
  - Dash, stealth, relic heuristics and thresholds.
- Create: `scripts/mods/BetterBots/heuristics_psyker.lua`
  - Shout, stance, force-field heuristics and thresholds.
- Create: `scripts/mods/BetterBots/heuristics_ogryn.lua`
  - Charge, taunt, gunlugger heuristics and thresholds.
- Create: `scripts/mods/BetterBots/heuristics_arbites.lua`
  - Stance, charge, shout, drone heuristics and thresholds.
- Create: `scripts/mods/BetterBots/heuristics_hive_scum.lua`
  - Focus, rage, stimm-field heuristics.
- Create: `scripts/mods/BetterBots/heuristics_grenade.lua`
  - All grenade/blitz preset tables and tactical evaluators.

### Existing source files

- Modify: `scripts/mods/BetterBots/heuristics.lua`
  - Thin dispatch/orchestrator only.
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
  - Load new heuristics submodules and pass them into `Heuristics.init({...})`.

### Tests

- Modify: `tests/test_helper.lua`
  - Add split-aware heuristics dependency loader.
- Modify: `tests/heuristics_spec.lua`
  - Stop partial direct `Heuristics.init({...})`; use split helper.
- Modify: `tests/resolve_decision_spec.lua`
  - Same.
- Modify: `tests/settings_spec.lua`
  - Same.
- Modify: `tests/grenade_fallback_spec.lua`
  - Same for the local `normalize_grenade_context` / Assail block.
- Modify: `tests/startup_regressions_spec.lua`
  - Assert split heuristics modules load through `mod:io_dofile` and are wired into `Heuristics.init({...})`.

### Docs

- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/debugging.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/validation-tracker.md`

## Batch 2 Exit Target

- Source module count: `40 -> 48`
- Test count after Batch 1: `1030 -> 1031`
- Public API preserved:
  - `Heuristics.init`
  - `Heuristics.build_context`
  - `Heuristics.normalize_grenade_context`
  - `Heuristics.resolve_decision`
  - `Heuristics.evaluate_heuristic`
  - `Heuristics.evaluate_item_heuristic`
  - `Heuristics.evaluate_grenade_heuristic`
  - `Heuristics.enemy_breed`
- `make check-ci` passes unchanged

---

### Task 1: Create `heuristics_context.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_context.lua`
- Test: `scripts/mods/BetterBots/heuristics_context.lua`

- [ ] **Step 1: Create the context module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1,530p'
	printf '\n'
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1140,1153p'
	cat <<'EOF'

return {
	init = function(deps)
		_fixed_time = deps.fixed_time
		_decision_context_cache = deps.decision_context_cache
		_super_armor_breed_cache = deps.super_armor_breed_cache
		_armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
		_resolve_preset = deps.resolve_preset
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_daemonhost_breed_names = deps.shared_rules and deps.shared_rules.DAEMONHOST_BREED_NAMES
		_daemonhost_state = deps.shared_rules and deps.shared_rules.daemonhost_state
		_is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled or function()
			return true
		end

		_interacting_cache_t = nil
		_interacting_cache_side = nil
		for i = #_interacting_units, 1, -1 do
			_interacting_units[i] = nil
			_interacting_profiles[i] = nil
			_interacting_types[i] = nil
		end
	end,
	build_context = build_context,
	normalize_grenade_context = normalize_grenade_context,
	enemy_breed = _enemy_breed,
	is_monster_signal_allowed = _is_monster_signal_allowed,
}
EOF
} > scripts/mods/BetterBots/heuristics_context.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_context.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_context.lua
tail -n 40 scripts/mods/BetterBots/heuristics_context.lua
```

Expected:

- top of file starts with the copied module locals and helper definitions
- tail of file ends with the `return { ... }` export block
- no truncated function bodies

- [ ] **Step 4: Commit the new context module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_context.lua
git commit -m "refactor(heuristics): extract context module"
```

Expected: one-file commit containing only `heuristics_context.lua`.

---

### Task 2: Create `heuristics_veteran.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_veteran.lua`
- Test: `scripts/mods/BetterBots/heuristics_veteran.lua`

- [ ] **Step 1: Create the veteran module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	cat <<'EOF'
local _combat_ability_identity

EOF
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '531,732p'
	cat <<'EOF'

return {
	init = function(deps)
		assert(deps.combat_ability_identity, "heuristics_veteran: combat_ability_identity dep required")
		_combat_ability_identity = deps.combat_ability_identity
	end,
	template_heuristics = {
		veteran_stealth_combat_ability = _can_activate_veteran_stealth,
	},
	heuristic_thresholds = {
		veteran_stealth_combat_ability = VETERAN_STEALTH_THRESHOLDS,
	},
	evaluate_veteran_combat_ability = function(
		conditions,
		unit,
		blackboard,
		scratchpad,
		condition_args,
		action_data,
		is_running,
		ability_extension,
		context,
		preset
	)
		local identity = _resolve_combat_identity("veteran_combat_ability", ability_extension)
		local threshold_table = (identity.semantic_key == "veteran_combat_ability_shout")
			and VETERAN_VOC_THRESHOLDS or VETERAN_STANCE_THRESHOLDS
		local thresholds = threshold_table[preset] or threshold_table.balanced

		return _can_activate_veteran_combat_ability(
			conditions,
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running,
			ability_extension,
			context,
			thresholds
		)
	end,
}
EOF
} > scripts/mods/BetterBots/heuristics_veteran.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_veteran.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_veteran.lua
tail -n 40 scripts/mods/BetterBots/heuristics_veteran.lua
```

Expected:

- file starts with `local _combat_ability_identity`
- tail contains `template_heuristics`, `heuristic_thresholds`, and `evaluate_veteran_combat_ability`

- [ ] **Step 4: Commit the veteran module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_veteran.lua
git commit -m "refactor(heuristics): extract veteran module"
```

Expected: one-file commit containing only `heuristics_veteran.lua`.

---

### Task 3: Create `heuristics_zealot.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_zealot.lua`
- Test: `scripts/mods/BetterBots/heuristics_zealot.lua`

- [ ] **Step 1: Create the zealot module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '733,859p'
	printf '\n'
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1330,1379p'
	cat <<'EOF'

return {
	template_heuristics = {
		zealot_dash = _can_activate_zealot_dash,
		zealot_targeted_dash = _can_activate_zealot_dash,
		zealot_targeted_dash_improved = _can_activate_zealot_dash,
		zealot_targeted_dash_improved_double = _can_activate_zealot_dash,
		zealot_invisibility = _can_activate_zealot_invisibility,
	},
	heuristic_thresholds = {
		zealot_dash = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash_improved = ZEALOT_DASH_THRESHOLDS,
		zealot_targeted_dash_improved_double = ZEALOT_DASH_THRESHOLDS,
		zealot_invisibility = ZEALOT_INVISIBILITY_THRESHOLDS,
	},
	item_heuristics = {
		zealot_relic = _can_activate_zealot_relic,
	},
	item_thresholds = {
		zealot_relic = ZEALOT_RELIC_THRESHOLDS,
	},
}
EOF
} > scripts/mods/BetterBots/heuristics_zealot.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_zealot.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_zealot.lua
tail -n 40 scripts/mods/BetterBots/heuristics_zealot.lua
```

Expected:

- top contains zealot threshold tables/functions
- tail contains zealot `template_heuristics` plus relic `item_heuristics`

- [ ] **Step 4: Commit the zealot module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_zealot.lua
git commit -m "refactor(heuristics): extract zealot module"
```

Expected: one-file commit containing only `heuristics_zealot.lua`.

---

### Task 4: Create `heuristics_psyker.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_psyker.lua`
- Test: `scripts/mods/BetterBots/heuristics_psyker.lua`

- [ ] **Step 1: Create the psyker module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '860,955p'
	printf '\n'
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1380,1422p'
	cat <<'EOF'

return {
	template_heuristics = {
		psyker_shout = _can_activate_psyker_shout,
		psyker_overcharge_stance = _can_activate_psyker_stance,
	},
	heuristic_thresholds = {
		psyker_shout = PSYKER_SHOUT_THRESHOLDS,
		psyker_overcharge_stance = PSYKER_STANCE_THRESHOLDS,
	},
	item_heuristics = {
		psyker_force_field = _can_activate_force_field,
		psyker_force_field_improved = _can_activate_force_field,
		psyker_force_field_dome = _can_activate_force_field,
	},
	item_thresholds = {
		psyker_force_field = FORCE_FIELD_THRESHOLDS,
		psyker_force_field_improved = FORCE_FIELD_THRESHOLDS,
		psyker_force_field_dome = FORCE_FIELD_THRESHOLDS,
	},
}
EOF
} > scripts/mods/BetterBots/heuristics_psyker.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_psyker.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_psyker.lua
tail -n 40 scripts/mods/BetterBots/heuristics_psyker.lua
```

Expected:

- top contains psyker shout/stance helpers
- tail contains force-field `item_heuristics` and thresholds

- [ ] **Step 4: Commit the psyker module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_psyker.lua
git commit -m "refactor(heuristics): extract psyker module"
```

Expected: one-file commit containing only `heuristics_psyker.lua`.

---

### Task 5: Create `heuristics_ogryn.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_ogryn.lua`
- Test: `scripts/mods/BetterBots/heuristics_ogryn.lua`

- [ ] **Step 1: Create the ogryn module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '956,1139p'
	cat <<'EOF'

return {
	template_heuristics = {
		ogryn_charge = _can_activate_ogryn_charge,
		ogryn_charge_increased_distance = _can_activate_ogryn_charge,
		ogryn_taunt_shout = _can_activate_ogryn_taunt,
		ogryn_gunlugger_stance = _can_activate_ogryn_gunlugger,
	},
	heuristic_thresholds = {
		ogryn_charge = OGRYN_CHARGE_THRESHOLDS,
		ogryn_charge_increased_distance = OGRYN_CHARGE_THRESHOLDS,
		ogryn_taunt_shout = OGRYN_TAUNT_THRESHOLDS,
		ogryn_gunlugger_stance = OGRYN_GUNLUGGER_THRESHOLDS,
	},
}
EOF
} > scripts/mods/BetterBots/heuristics_ogryn.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_ogryn.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_ogryn.lua
tail -n 40 scripts/mods/BetterBots/heuristics_ogryn.lua
```

Expected:

- top contains ogryn thresholds/functions
- tail contains charge/taunt/gunlugger export tables

- [ ] **Step 4: Commit the ogryn module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_ogryn.lua
git commit -m "refactor(heuristics): extract ogryn module"
```

Expected: one-file commit containing only `heuristics_ogryn.lua`.

---

### Task 6: Create `heuristics_arbites.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_arbites.lua`
- Test: `scripts/mods/BetterBots/heuristics_arbites.lua`

- [ ] **Step 1: Create the arbites module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	cat <<'EOF'
local _is_monster_signal_allowed

EOF
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1154,1268p'
	printf '\n'
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1423,1448p'
	cat <<'EOF'

return {
	init = function(deps)
		assert(deps.is_monster_signal_allowed, "heuristics_arbites: is_monster_signal_allowed dep required")
		_is_monster_signal_allowed = deps.is_monster_signal_allowed
	end,
	template_heuristics = {
		adamant_stance = _can_activate_adamant_stance,
		adamant_charge = _can_activate_adamant_charge,
		adamant_shout = _can_activate_adamant_shout,
	},
	heuristic_thresholds = {
		adamant_stance = ADAMANT_STANCE_THRESHOLDS,
		adamant_charge = ADAMANT_CHARGE_THRESHOLDS,
		adamant_shout = ADAMANT_SHOUT_THRESHOLDS,
	},
	item_heuristics = {
		adamant_area_buff_drone = _can_activate_drone,
	},
	item_thresholds = {
		adamant_area_buff_drone = DRONE_THRESHOLDS,
	},
}
EOF
} > scripts/mods/BetterBots/heuristics_arbites.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_arbites.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_arbites.lua
tail -n 40 scripts/mods/BetterBots/heuristics_arbites.lua
```

Expected:

- top contains `local _is_monster_signal_allowed`
- tail contains arbites export tables plus drone item exports

- [ ] **Step 4: Commit the arbites module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_arbites.lua
git commit -m "refactor(heuristics): extract arbites module"
```

Expected: one-file commit containing only `heuristics_arbites.lua`.

---

### Task 7: Create `heuristics_hive_scum.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_hive_scum.lua`
- Test: `scripts/mods/BetterBots/heuristics_hive_scum.lua`

- [ ] **Step 1: Create the hive-scum module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1269,1329p'
	printf '\n'
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1449,1467p'
	cat <<'EOF'

return {
	template_heuristics = {
		broker_focus = _can_activate_broker_focus,
		broker_punk_rage = _can_activate_broker_rage,
	},
	item_heuristics = {
		broker_ability_stimm_field = _can_activate_stimm_field,
	},
}
EOF
} > scripts/mods/BetterBots/heuristics_hive_scum.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_hive_scum.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_hive_scum.lua
tail -n 40 scripts/mods/BetterBots/heuristics_hive_scum.lua
```

Expected:

- top contains broker/stimm heuristic functions
- tail contains hive-scum export tables

- [ ] **Step 4: Commit the hive-scum module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_hive_scum.lua
git commit -m "refactor(heuristics): extract hive scum module"
```

Expected: one-file commit containing only `heuristics_hive_scum.lua`.

---

### Task 8: Create `heuristics_grenade.lua`

**Files:**
- Create: `scripts/mods/BetterBots/heuristics_grenade.lua`
- Test: `scripts/mods/BetterBots/heuristics_grenade.lua`

- [ ] **Step 1: Create the grenade module from the pinned monolith ranges**

Run:

```bash
SOURCE_SHA=e4fc545e3332a870090518cf6541348c874e6f1f

{
	cat <<'EOF'
local _is_monster_signal_allowed

EOF
	git show ${SOURCE_SHA}:scripts/mods/BetterBots/heuristics.lua | sed -n '1523,1847p'
	cat <<'EOF'

return {
	init = function(deps)
		assert(deps.is_monster_signal_allowed, "heuristics_grenade: is_monster_signal_allowed dep required")
		_is_monster_signal_allowed = deps.is_monster_signal_allowed
	end,
	grenade_heuristics = GRENADE_HEURISTICS,
}
EOF
} > scripts/mods/BetterBots/heuristics_grenade.lua
```

- [ ] **Step 2: Syntax-check the new file**

Run:

```bash
lua -e "assert(loadfile('scripts/mods/BetterBots/heuristics_grenade.lua'))"
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Verify extraction boundaries before commit**

Run:

```bash
sed -n '1,40p' scripts/mods/BetterBots/heuristics_grenade.lua
tail -n 40 scripts/mods/BetterBots/heuristics_grenade.lua
```

Expected:

- top contains `local _is_monster_signal_allowed`
- tail contains `GRENADE_HEURISTICS` export block

- [ ] **Step 4: Commit the grenade module**

Run:

```bash
git add scripts/mods/BetterBots/heuristics_grenade.lua
git commit -m "refactor(heuristics): extract grenade module"
```

Expected: one-file commit containing only `heuristics_grenade.lua`.

---

### Task 9: Add split-aware test loader and switch heuristics-facing specs

**Files:**
- Modify: `tests/test_helper.lua`
- Modify: `tests/heuristics_spec.lua`
- Modify: `tests/resolve_decision_spec.lua`
- Modify: `tests/settings_spec.lua`
- Modify: `tests/grenade_fallback_spec.lua`
- Test: `tests/heuristics_spec.lua`
- Test: `tests/resolve_decision_spec.lua`
- Test: `tests/settings_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Add a split-aware loader to `tests/test_helper.lua`**

Apply this patch:

```diff
@@
 function M.make_conditions(vanilla_result)
 	return {
 		_can_activate_veteran_ranger_ability = function()
 			return vanilla_result
 		end,
 	}
 end
@@
 local function _copy_table(source)
 	local result = {}
 	if source then
 		for k, v in pairs(source) do
 			result[k] = v
 		end
 	end
 	return result
 end
+
+function M.make_split_heuristics_deps(overrides)
+	local deps = {
+		fixed_time = function()
+			return 0
+		end,
+		decision_context_cache = {},
+		super_armor_breed_cache = {},
+		ARMOR_TYPE_SUPER_ARMOR = 6,
+		is_testing_profile = function()
+			return false
+		end,
+		resolve_preset = function()
+			return "balanced"
+		end,
+		debug_log = function() end,
+		debug_enabled = function()
+			return false
+		end,
+		combat_ability_identity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua"),
+		context_module = dofile("scripts/mods/BetterBots/heuristics_context.lua"),
+		veteran_module = dofile("scripts/mods/BetterBots/heuristics_veteran.lua"),
+		zealot_module = dofile("scripts/mods/BetterBots/heuristics_zealot.lua"),
+		psyker_module = dofile("scripts/mods/BetterBots/heuristics_psyker.lua"),
+		ogryn_module = dofile("scripts/mods/BetterBots/heuristics_ogryn.lua"),
+		arbites_module = dofile("scripts/mods/BetterBots/heuristics_arbites.lua"),
+		hive_scum_module = dofile("scripts/mods/BetterBots/heuristics_hive_scum.lua"),
+		grenade_module = dofile("scripts/mods/BetterBots/heuristics_grenade.lua"),
+	}
+
+	for key, value in pairs(overrides or {}) do
+		deps[key] = value
+	end
+
+	return deps
+end
+
+function M.init_split_heuristics(heuristics, overrides)
+	heuristics.init(M.make_split_heuristics_deps(overrides))
+	return heuristics
+end
+
+function M.load_split_heuristics(overrides)
+	local heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
+	return M.init_split_heuristics(heuristics, overrides)
+end
```

- [ ] **Step 2: Switch the spec loaders and re-init calls**

Apply these exact edits:

```diff
*** tests/heuristics_spec.lua
@@
-local helper = require("test_helper")
-local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
-local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
-Heuristics.init({ combat_ability_identity = CombatAbilityIdentity })
+local helper = require("test_helper")
+local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
+local Heuristics = helper.load_split_heuristics({
+	combat_ability_identity = CombatAbilityIdentity,
+})

*** tests/resolve_decision_spec.lua
@@
-local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
-local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
+local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
+local fixed_t = 100
+local Heuristics = helper.load_split_heuristics({
+	fixed_time = function()
+		return fixed_t
+	end,
+	decision_context_cache = {},
+	super_armor_breed_cache = {},
+	ARMOR_TYPE_SUPER_ARMOR = 6,
+	combat_ability_identity = CombatAbilityIdentity,
+})
@@
-Heuristics.init({
-	fixed_time = function()
-		return fixed_t
-	end,
-	decision_context_cache = {},
-	super_armor_breed_cache = {},
-	ARMOR_TYPE_SUPER_ARMOR = 6,
-	combat_ability_identity = CombatAbilityIdentity,
-})
+helper.init_split_heuristics(Heuristics, {
+	fixed_time = function()
+		return fixed_t
+	end,
+	decision_context_cache = {},
+	super_armor_breed_cache = {},
+	ARMOR_TYPE_SUPER_ARMOR = 6,
+	combat_ability_identity = CombatAbilityIdentity,
+})

*** tests/settings_spec.lua
@@
-local Settings = dofile("scripts/mods/BetterBots/settings.lua")
-local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
-local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
-local helper = require("tests.test_helper")
+local Settings = dofile("scripts/mods/BetterBots/settings.lua")
+local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
+local helper = require("tests.test_helper")
+local Heuristics = helper.load_split_heuristics({
+	combat_ability_identity = CombatAbilityIdentity,
+})
```

Then run the direct re-init replacements:

```bash
perl -0pi -e 's/Heuristics\.init\(\{/helper.init_split_heuristics(Heuristics, {/g' tests/heuristics_spec.lua
perl -0pi -e 's/Heuristics\.init\(\{/helper.init_split_heuristics(Heuristics, {/g' tests/resolve_decision_spec.lua
perl -0pi -e 's/Heuristics\.init\(\{/helper.init_split_heuristics(Heuristics, {/g' tests/settings_spec.lua
```

Patch the one grenade-fallback block:

```diff
*** tests/grenade_fallback_spec.lua
@@
-			local BotTargeting = dofile("scripts/mods/BetterBots/bot_targeting.lua")
-			local Heuristics = dofile("scripts/mods/BetterBots/heuristics.lua")
-			local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
-			Heuristics.init({
-				combat_ability_identity = CombatAbilityIdentity,
-				decision_context_cache = {},
-				super_armor_breed_cache = {},
-				ARMOR_TYPE_SUPER_ARMOR = "super_armor",
-			})
+			local BotTargeting = dofile("scripts/mods/BetterBots/bot_targeting.lua")
+			local CombatAbilityIdentity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
+			local Heuristics = test_helper.load_split_heuristics({
+				combat_ability_identity = CombatAbilityIdentity,
+				decision_context_cache = {},
+				super_armor_breed_cache = {},
+				ARMOR_TYPE_SUPER_ARMOR = "super_armor",
+			})
```

- [ ] **Step 3: Run the heuristics-facing spec set before touching runtime wiring**

Run:

```bash
busted tests/heuristics_spec.lua tests/resolve_decision_spec.lua tests/settings_spec.lua tests/grenade_fallback_spec.lua
```

Expected: PASS. This run is the guard against hidden helper leakage from the extracted files; any stray direct dependency on monolith-only locals must fail here before runtime wiring changes land.

- [ ] **Step 4: Commit the split-aware test harness**

Run:

```bash
git add tests/test_helper.lua tests/heuristics_spec.lua tests/resolve_decision_spec.lua tests/settings_spec.lua tests/grenade_fallback_spec.lua
git commit -m "test(heuristics): load split modules through helper"
```

Expected: one commit containing only test helper + spec loader changes.

---

### Task 10: Rewrite the dispatcher and wire split modules through `BetterBots.lua`

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Modify: `tests/startup_regressions_spec.lua`
- Test: `tests/startup_regressions_spec.lua`
- Test: `tests/heuristics_spec.lua`
- Test: `tests/resolve_decision_spec.lua`
- Test: `tests/settings_spec.lua`
- Test: `tests/grenade_fallback_spec.lua`

- [ ] **Step 1: Make `BetterBots.lua` load and pass the new modules**

Apply this patch:

```diff
*** scripts/mods/BetterBots/BetterBots.lua
@@
 Settings = mod:io_dofile("BetterBots/scripts/mods/BetterBots/settings")
 assert(Settings, "BetterBots: failed to load settings module")
 
+local HeuristicsContext = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_context")
+assert(HeuristicsContext, "BetterBots: failed to load heuristics_context module")
+
+local HeuristicsVeteran = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_veteran")
+assert(HeuristicsVeteran, "BetterBots: failed to load heuristics_veteran module")
+
+local HeuristicsZealot = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_zealot")
+assert(HeuristicsZealot, "BetterBots: failed to load heuristics_zealot module")
+
+local HeuristicsPsyker = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_psyker")
+assert(HeuristicsPsyker, "BetterBots: failed to load heuristics_psyker module")
+
+local HeuristicsOgryn = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_ogryn")
+assert(HeuristicsOgryn, "BetterBots: failed to load heuristics_ogryn module")
+
+local HeuristicsArbites = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_arbites")
+assert(HeuristicsArbites, "BetterBots: failed to load heuristics_arbites module")
+
+local HeuristicsHiveScum = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_hive_scum")
+assert(HeuristicsHiveScum, "BetterBots: failed to load heuristics_hive_scum module")
+
+local HeuristicsGrenade = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics_grenade")
+assert(HeuristicsGrenade, "BetterBots: failed to load heuristics_grenade module")
+
 local Heuristics = mod:io_dofile("BetterBots/scripts/mods/BetterBots/heuristics")
 assert(Heuristics, "BetterBots: failed to load heuristics module")
@@
 Heuristics.init({
 	fixed_time = _fixed_time,
 	decision_context_cache = _decision_context_cache_by_unit,
 	super_armor_breed_cache = _super_armor_breed_flag_by_name,
 	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
 	is_testing_profile = Settings.is_testing_profile,
 	resolve_preset = Settings.resolve_preset,
 	debug_log = _debug_log,
 	debug_enabled = _debug_enabled,
 	combat_ability_identity = CombatAbilityIdentity,
 	shared_rules = SharedRules,
 	is_daemonhost_avoidance_enabled = function()
 		return Settings.is_feature_enabled("daemonhost_avoidance")
 	end,
+	context_module = HeuristicsContext,
+	veteran_module = HeuristicsVeteran,
+	zealot_module = HeuristicsZealot,
+	psyker_module = HeuristicsPsyker,
+	ogryn_module = HeuristicsOgryn,
+	arbites_module = HeuristicsArbites,
+	hive_scum_module = HeuristicsHiveScum,
+	grenade_module = HeuristicsGrenade,
 })
```

- [ ] **Step 2: Replace `heuristics.lua` with the thin orchestrator**

Write this exact file:

```lua
local _is_testing_profile
local _context_module
local _veteran_module
local _is_monster_signal_allowed
local _template_heuristics = {}
local _heuristic_thresholds = {}
local _item_heuristics = {}
local _item_thresholds = {}
local _grenade_heuristics = {}

local function _merge_into(dst, src)
	for key, value in pairs(src or {}) do
		dst[key] = value
	end
end

local function _testing_profile_active(opts)
	if opts and opts.preset then
		return opts.preset == "testing"
	end
	if opts and opts.behavior_profile then
		return opts.behavior_profile == "testing"
	end

	return _is_testing_profile and _is_testing_profile() or false
end

local function _testing_profile_override(context)
	if not context then
		return false
	end

	if context.target_ally_needs_aid then
		return true, "testing_profile_ally_aid"
	end

	if _is_monster_signal_allowed and _is_monster_signal_allowed(context) then
		return true, "testing_profile_monster"
	end

	if context.target_is_elite_special or context.special_count > 0 or context.elite_count > 0 then
		return true, "testing_profile_priority"
	end

	if context.num_nearby >= 2 then
		return true, "testing_profile_crowd"
	end

	if context.num_nearby >= 1 and (context.toughness_pct < 0.80 or context.health_pct < 0.80) then
		return true, "testing_profile_pressure"
	end

	return false
end

local function _testing_profile_can_override_rule(rule)
	if rule == nil then
		return true
	end

	rule = tostring(rule)

	if string.find(rule, "_hold", 1, true) then
		return true
	end

	if string.find(rule, "_block_safe", 1, true) then
		return true
	end

	if string.find(rule, "_block_low_value", 1, true) then
		return true
	end

	return false
end

local function _apply_behavior_profile(can_activate, rule, context, opts)
	if can_activate ~= false or not _testing_profile_active(opts) then
		return can_activate, rule
	end

	if not _testing_profile_can_override_rule(rule) then
		return can_activate, rule
	end

	local should_override, override_rule = _testing_profile_override(context)
	if not should_override then
		return can_activate, rule
	end

	if rule then
		return true, tostring(rule) .. "->" .. override_rule
	end

	return true, override_rule
end

local function _evaluate_template_heuristic(
	ability_template_name,
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension,
	context
)
	local preset = context.preset or "balanced"

	if ability_template_name == "veteran_combat_ability" then
		return _veteran_module.evaluate_veteran_combat_ability(
			conditions,
			unit,
			blackboard,
			scratchpad,
			condition_args,
			action_data,
			is_running,
			ability_extension,
			context,
			preset
		)
	end

	local fn = _template_heuristics[ability_template_name]
	if not fn then
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = _heuristic_thresholds[ability_template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil

	return fn(context, thresholds)
end

local function resolve_decision(
	ability_template_name,
	conditions,
	unit,
	blackboard,
	scratchpad,
	condition_args,
	action_data,
	is_running,
	ability_extension
)
	local context = _context_module.build_context(unit, blackboard)
	local can_activate, rule = _evaluate_template_heuristic(
		ability_template_name,
		conditions,
		unit,
		blackboard,
		scratchpad,
		condition_args,
		action_data,
		is_running,
		ability_extension,
		context
	)

	if can_activate == nil then
		if ability_template_name == "veteran_combat_ability" then
			can_activate = conditions._can_activate_veteran_ranger_ability(
				unit,
				blackboard,
				scratchpad,
				condition_args,
				action_data,
				is_running
			)
			rule = rule and (tostring(rule) .. "->fallback_veteran_vanilla") or "fallback_veteran_vanilla"
		else
			can_activate = context.num_nearby > 0
			rule = rule and (tostring(rule) .. "->fallback_nearby") or "fallback_nearby"
		end
	end

	local profiled_can_activate, profiled_rule = _apply_behavior_profile(can_activate, rule, context)

	return profiled_can_activate, profiled_rule, context
end

local function evaluate_heuristic(template_name, context, opts)
	opts = opts or {}
	local preset = opts.preset or context.preset or "balanced"
	local saved_preset = context.preset
	context.preset = preset

	if template_name == "veteran_combat_ability" then
		local can_activate, rule = _veteran_module.evaluate_veteran_combat_ability(
			opts.conditions or {},
			opts.unit,
			nil,
			nil,
			nil,
			nil,
			false,
			opts.ability_extension,
			context,
			preset
		)

		context.preset = saved_preset
		return _apply_behavior_profile(can_activate, rule, context, opts)
	end

	local fn = _template_heuristics[template_name]
	if not fn then
		context.preset = saved_preset
		return nil, "fallback_unhandled_template"
	end

	local threshold_table = _heuristic_thresholds[template_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
	local can_activate, rule = fn(context, thresholds)
	context.preset = saved_preset
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

local function evaluate_item_heuristic(ability_name, context, opts)
	local fn = _item_heuristics[ability_name]
	if not fn then
		return false, "unknown_item_ability"
	end

	local preset = (opts and opts.preset) or context.preset or "balanced"
	local threshold_table = _item_thresholds[ability_name]
	local thresholds = threshold_table and (threshold_table[preset] or threshold_table.balanced) or nil
	local can_activate, rule = fn(context, thresholds)
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

local function evaluate_grenade_heuristic(grenade_template_name, context, opts)
	if not context then
		return false, "grenade_no_context"
	end

	local preset = (opts and opts.preset) or context.preset or "balanced"
	local saved_preset = context.preset
	context.preset = preset

	local relaxed_num_nearby = opts and opts.revalidation and type(context.num_nearby) == "number"
	local saved_num_nearby
	if relaxed_num_nearby then
		saved_num_nearby = context.num_nearby
		context.num_nearby = saved_num_nearby + 1
	end

	local fn = _grenade_heuristics[grenade_template_name]
	local can_activate, rule
	if fn then
		can_activate, rule = fn(context)
	elseif context.num_nearby > 0 then
		can_activate, rule = true, "grenade_generic"
	else
		can_activate, rule = false, "grenade_no_enemies"
	end

	if relaxed_num_nearby then
		context.num_nearby = saved_num_nearby
	end

	context.preset = saved_preset
	return _apply_behavior_profile(can_activate, rule, context, opts)
end

return {
	init = function(deps)
		assert(deps.combat_ability_identity, "heuristics: combat_ability_identity dep required")
		assert(deps.context_module, "heuristics: context_module dep required")
		assert(deps.veteran_module, "heuristics: veteran_module dep required")
		assert(deps.zealot_module, "heuristics: zealot_module dep required")
		assert(deps.psyker_module, "heuristics: psyker_module dep required")
		assert(deps.ogryn_module, "heuristics: ogryn_module dep required")
		assert(deps.arbites_module, "heuristics: arbites_module dep required")
		assert(deps.hive_scum_module, "heuristics: hive_scum_module dep required")
		assert(deps.grenade_module, "heuristics: grenade_module dep required")

		_is_testing_profile = deps.is_testing_profile
		_context_module = deps.context_module
		_veteran_module = deps.veteran_module

		_context_module.init({
			fixed_time = deps.fixed_time,
			decision_context_cache = deps.decision_context_cache,
			super_armor_breed_cache = deps.super_armor_breed_cache,
			ARMOR_TYPE_SUPER_ARMOR = deps.ARMOR_TYPE_SUPER_ARMOR,
			resolve_preset = deps.resolve_preset,
			debug_log = deps.debug_log,
			debug_enabled = deps.debug_enabled,
			shared_rules = deps.shared_rules,
			is_daemonhost_avoidance_enabled = deps.is_daemonhost_avoidance_enabled,
		})

		if _veteran_module.init then
			_veteran_module.init({
				combat_ability_identity = deps.combat_ability_identity,
			})
		end

		if deps.arbites_module.init then
			deps.arbites_module.init({
				is_monster_signal_allowed = _context_module.is_monster_signal_allowed,
			})
		end

		if deps.grenade_module.init then
			deps.grenade_module.init({
				is_monster_signal_allowed = _context_module.is_monster_signal_allowed,
			})
		end

		_template_heuristics = {}
		_heuristic_thresholds = {}
		_item_heuristics = {}
		_item_thresholds = {}
		_grenade_heuristics = {}

		_merge_into(_template_heuristics, _veteran_module.template_heuristics)
		_merge_into(_template_heuristics, deps.zealot_module.template_heuristics)
		_merge_into(_template_heuristics, deps.psyker_module.template_heuristics)
		_merge_into(_template_heuristics, deps.ogryn_module.template_heuristics)
		_merge_into(_template_heuristics, deps.arbites_module.template_heuristics)
		_merge_into(_template_heuristics, deps.hive_scum_module.template_heuristics)

		_merge_into(_heuristic_thresholds, _veteran_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.zealot_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.psyker_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.ogryn_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.arbites_module.heuristic_thresholds)
		_merge_into(_heuristic_thresholds, deps.hive_scum_module.heuristic_thresholds)

		_merge_into(_item_heuristics, deps.zealot_module.item_heuristics)
		_merge_into(_item_heuristics, deps.psyker_module.item_heuristics)
		_merge_into(_item_heuristics, deps.arbites_module.item_heuristics)
		_merge_into(_item_heuristics, deps.hive_scum_module.item_heuristics)

		_merge_into(_item_thresholds, deps.zealot_module.item_thresholds)
		_merge_into(_item_thresholds, deps.psyker_module.item_thresholds)
		_merge_into(_item_thresholds, deps.arbites_module.item_thresholds)
		_merge_into(_item_thresholds, deps.hive_scum_module.item_thresholds)

		_merge_into(_grenade_heuristics, deps.grenade_module.grenade_heuristics)

		_is_monster_signal_allowed = _context_module.is_monster_signal_allowed
	end,
	build_context = function(...)
		return _context_module.build_context(...)
	end,
	normalize_grenade_context = function(...)
		return _context_module.normalize_grenade_context(...)
	end,
	resolve_decision = resolve_decision,
	evaluate_heuristic = evaluate_heuristic,
	evaluate_item_heuristic = evaluate_item_heuristic,
	evaluate_grenade_heuristic = evaluate_grenade_heuristic,
	enemy_breed = function(...)
		return _context_module.enemy_breed(...)
	end,
}
```

- [ ] **Step 3: Update the startup regression coverage for split loading**

Add this source-shape test:

```lua
	it("loads split heuristics modules through mod io", function()
		local source = read_file("scripts/mods/BetterBots/BetterBots.lua")

		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_context"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_veteran"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_zealot"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_psyker"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_ogryn"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_arbites"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_hive_scum"%)', 1))
		assert.is_truthy(source:find('mod:io_dofile%("BetterBots/scripts/mods/BetterBots/heuristics_grenade"%)', 1))
	end)
```

Then extend the Batch-1 runtime bootstrap test with these checks:

```lua
		modules.HeuristicsContext = make_runtime_module("HeuristicsContext", install_calls)
		modules.HeuristicsVeteran = make_runtime_module("HeuristicsVeteran", install_calls)
		modules.HeuristicsZealot = make_runtime_module("HeuristicsZealot", install_calls)
		modules.HeuristicsPsyker = make_runtime_module("HeuristicsPsyker", install_calls)
		modules.HeuristicsOgryn = make_runtime_module("HeuristicsOgryn", install_calls)
		modules.HeuristicsArbites = make_runtime_module("HeuristicsArbites", install_calls)
		modules.HeuristicsHiveScum = make_runtime_module("HeuristicsHiveScum", install_calls)
		modules.HeuristicsGrenade = make_runtime_module("HeuristicsGrenade", install_calls)

		local heuristics_init = find_named_call(harness.init_calls, "Heuristics")

		assert.equals(harness.modules.HeuristicsContext, heuristics_init.deps.context_module)
		assert.equals(harness.modules.HeuristicsVeteran, heuristics_init.deps.veteran_module)
		assert.equals(harness.modules.HeuristicsZealot, heuristics_init.deps.zealot_module)
		assert.equals(harness.modules.HeuristicsPsyker, heuristics_init.deps.psyker_module)
		assert.equals(harness.modules.HeuristicsOgryn, heuristics_init.deps.ogryn_module)
		assert.equals(harness.modules.HeuristicsArbites, heuristics_init.deps.arbites_module)
		assert.equals(harness.modules.HeuristicsHiveScum, heuristics_init.deps.hive_scum_module)
		assert.equals(harness.modules.HeuristicsGrenade, heuristics_init.deps.grenade_module)
```

- [ ] **Step 4: Run the runtime + heuristics regression set**

Run:

```bash
busted tests/startup_regressions_spec.lua tests/heuristics_spec.lua tests/resolve_decision_spec.lua tests/settings_spec.lua tests/grenade_fallback_spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit the dispatcher + runtime wiring**

Run:

```bash
git add scripts/mods/BetterBots/heuristics.lua scripts/mods/BetterBots/BetterBots.lua tests/startup_regressions_spec.lua
git commit -m "refactor(heuristics): wire split modules through runtime"
```

Expected: one commit containing only runtime wiring + orchestrator changes.

---

### Task 11: Update docs and run the full gate

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/debugging.md`
- Modify: `docs/dev/status.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `docs/dev/validation-tracker.md`
- Test: `make check-ci`

- [ ] **Step 1: Update the live doc set**

Apply these exact edits:

```diff
*** AGENTS.md
@@
-3. **Condition hook:** Replaces `bt_bot_conditions.can_activate_ability` with per-template heuristics (18 functions in `heuristics.lua`). Each ability has specific activate/block conditions based on health, toughness, peril, enemy composition, distance, and ally state. Unknown templates fall back to `enemies_in_proximity() > 0`.
+3. **Condition hook:** Replaces `bt_bot_conditions.can_activate_ability` with split heuristics modules: `heuristics_context.lua`, `heuristics_veteran.lua`, `heuristics_zealot.lua`, `heuristics_psyker.lua`, `heuristics_ogryn.lua`, `heuristics_arbites.lua`, `heuristics_hive_scum.lua`, `heuristics_grenade.lua`, with thin dispatch in `heuristics.lua`. Each ability still has specific activate/block conditions based on health, toughness, peril, enemy composition, distance, and ally state. Unknown templates still fall back to `enemies_in_proximity() > 0`.
@@
-  heuristics.lua                            # 18 per-template heuristic functions + build_context()
+  heuristics_context.lua                    # build_context(), normalize_grenade_context(), shared monster/armor helpers
+  heuristics_veteran.lua                   # veteran thresholds + stealth + shout/stance semantic dispatch
+  heuristics_zealot.lua                    # zealot dash/stealth/relic heuristics
+  heuristics_psyker.lua                    # psyker shout/stance/force-field heuristics
+  heuristics_ogryn.lua                     # ogryn charge/taunt/gunlugger heuristics
+  heuristics_arbites.lua                   # arbites stance/charge/shout/drone heuristics
+  heuristics_hive_scum.lua                 # hive scum focus/rage/stimm heuristics
+  heuristics_grenade.lua                   # grenade/blitz tactical evaluators
+  heuristics.lua                           # thin dispatch/public API over split heuristic modules

*** README.md
@@
-  heuristics.lua                  #   18 per-ability trigger functions + context builder
+  heuristics_context.lua          #   build_context(), grenade normalization, shared helper state
+  heuristics_veteran.lua          #   veteran shout/stance + stealth heuristics
+  heuristics_zealot.lua           #   zealot dash/stealth/relic heuristics
+  heuristics_psyker.lua           #   psyker shout/stance/force-field heuristics
+  heuristics_ogryn.lua            #   ogryn charge/taunt/gunlugger heuristics
+  heuristics_arbites.lua          #   arbites stance/charge/shout/drone heuristics
+  heuristics_hive_scum.lua        #   hive scum focus/rage/stimm heuristics
+  heuristics_grenade.lua          #   grenade/blitz tactical evaluators
+  heuristics.lua                  #   thin dispatch + public Heuristics API
@@
-Bots use 18 per-ability heuristic functions to decide when to activate — based on enemy count, threat level, health/toughness, distance, ally state, and more. Each ability has specific activate/block conditions tuned per preset.
+Bots use 18 per-ability heuristic functions split by class plus grenade tactical evaluators to decide when to activate — based on enemy count, threat level, health/toughness, distance, ally state, and more. Each ability has specific activate/block conditions tuned per preset.

*** docs/dev/architecture.md
@@
-10. Per-template heuristics (via `heuristics.lua`):
+10. Per-template heuristics (via split modules with thin `heuristics.lua` dispatch):
@@
-    - `evaluate_heuristic(template_name, context, opts)` for template-path abilities
-    - `evaluate_item_heuristic(ability_name, context, opts)` for item-path abilities
-    - `combat_ability_identity.lua` separates engine template identity (`ability_component.template_name`) from semantic ability identity (`ability_name` / `semantic_key`) so shared templates such as Veteran shout vs stance can route to different heuristics/settings without changing template-based engine lookups
+    - `heuristics_context.lua` owns `build_context`, `normalize_grenade_context`, `enemy_breed`, and dormant-daemonhost-safe monster gating
+    - `heuristics_<class>.lua` files own class-specific threshold tables and pure activate/hold rules
+    - `heuristics_grenade.lua` owns grenade/blitz preset tables and tactical evaluators
+    - thin `heuristics.lua` merges exported maps, applies testing-profile overrides, and preserves `evaluate_heuristic(template_name, context, opts)`, `evaluate_item_heuristic(ability_name, context, opts)`, `evaluate_grenade_heuristic(grenade_template_name, context, opts)`, and `resolve_decision(...)`

*** docs/dev/debugging.md
@@
-The sub-module split (heuristics.lua, meta_data.lua, event_log.lua, etc.) created clean test seams. The 18 `_can_activate_*` heuristic functions (14 combat + 4 item) are **pure functions** — they take a context table and return `(bool, string)` with zero engine dependencies. The `evaluate_heuristic(template_name, context, opts)` public API exposes them for testing without the ugly internal 10-param dispatch signature. The `event_log` module is independently testable (buffer, flush, lifecycle, false-decision compression).
+The sub-module split (`heuristics_context.lua`, `heuristics_<class>.lua`, `heuristics_grenade.lua`, `meta_data.lua`, `event_log.lua`, etc.) created clean test seams. The 18 `_can_activate_*` heuristic functions (14 combat + 4 item) still live as **pure functions** in the class split files — they take a context table and return `(bool, string)` with zero engine dependencies. The thin `heuristics.lua` layer preserves the `evaluate_heuristic(template_name, context, opts)` public API so tests do not touch the ugly internal 10-param dispatch signature. The `event_log` module is independently testable (buffer, flush, lifecycle, false-decision compression).

*** docs/dev/status.md
@@
-- **Refactored** into sub-modules: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26)
+- **Refactored** into sub-modules: thin `heuristics.lua` dispatch plus `heuristics_context.lua`, `heuristics_<class>.lua`, `heuristics_grenade.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26, #38 prep)

*** docs/dev/roadmap.md
@@
-- Sub-module refactor: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25)
+- Sub-module refactor: thin `heuristics.lua` dispatch plus `heuristics_context.lua`, `heuristics_<class>.lua`, `heuristics_grenade.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25, #38 prep)
```

Do not run `cp AGENTS.md CLAUDE.md`. `CLAUDE.md` is already a symlink to `AGENTS.md`, so editing `AGENTS.md` updates both files automatically.

Patch the stale validation-tracker references:

```bash
perl -0pi -e 's/heuristics\\.lua:370-378 build_context set target_is_monster=true for DH/heuristics_context.lua build_context set target_is_monster=true for DH/' docs/dev/validation-tracker.md
perl -0pi -e 's/heuristics\\.lua:1491 _grenade_priority_target used target_is_monster as a/heuristics_grenade.lua _grenade_priority_target used target_is_monster as a/' docs/dev/validation-tracker.md
perl -0pi -e 's/heuristics\\.lua:1602 _grenade_assail monster fast-path same issue\\./heuristics_grenade.lua _grenade_assail monster fast-path same issue./' docs/dev/validation-tracker.md
perl -0pi -e 's/heuristics\\.lua:1052 _can_activate_adamant_stance monster_pressure same\\./heuristics_arbites.lua _can_activate_adamant_stance monster_pressure same./' docs/dev/validation-tracker.md
perl -0pi -e 's/heuristics\\.lua:1314 _can_activate_drone monster_fight same\\./heuristics_arbites.lua _can_activate_drone monster_fight same./' docs/dev/validation-tracker.md
```

- [ ] **Step 2: Run the full non-mutating gate**

Run:

```bash
make check-ci
```

Expected:

```text
format-check: PASS
lint: PASS
lsp-check: PASS
test: PASS
doc-check: PASS
```

- [ ] **Step 3: Commit docs plus final verification**

Run:

```bash
git add AGENTS.md CLAUDE.md README.md docs/dev/architecture.md docs/dev/debugging.md docs/dev/status.md docs/dev/roadmap.md docs/dev/validation-tracker.md
git commit -m "docs(heuristics): record split module architecture"
```

Expected: final docs-only commit after `make check-ci` is green.

---

## Self-Review

### Spec coverage

- External review concern 1 fixed: Batch 2 now uses per-class files, not a single `heuristics_combat.lua`.
- External review concern 2 fixed in Batch 1, not repeated here.
- External review concern 3 fixed in Batch 1, not repeated here.
- DMF loader rule preserved: all runtime module loads stay in `BetterBots.lua`; leaf modules receive shared helpers through `init({...})`.
- Test touchpoints are explicit: `tests/test_helper.lua`, `tests/heuristics_spec.lua`, `tests/resolve_decision_spec.lua`, `tests/settings_spec.lua`, `tests/grenade_fallback_spec.lua`, and `tests/startup_regressions_spec.lua`.

### Placeholder scan

- No `TODO`, `TBD`, or “move unchanged” shortcuts remain.
- New module content is specified either by exact pinned extraction commands or exact replacement code blocks.
- Repetitive test rewrites use exact `perl -0pi` replacements rather than vague “update all init calls” wording.

### Type/API consistency

- Runtime deps use `context_module`, `veteran_module`, `zealot_module`, `psyker_module`, `ogryn_module`, `arbites_module`, `hive_scum_module`, and `grenade_module` consistently in `BetterBots.lua`, `heuristics.lua`, and `tests/test_helper.lua`.
- Public `Heuristics` API names remain unchanged.
- Shared monster helper flows one direction only: `heuristics_context.lua` exports `is_monster_signal_allowed`; `heuristics_arbites.lua` and `heuristics_grenade.lua` receive it through `init({...})`.

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-16-heuristics-split.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
