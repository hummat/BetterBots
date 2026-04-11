# Objective-Aware Ability Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bots detect allies performing objective interactions and adjust ability activation — lowering defensive thresholds, suppressing charges near interactors, and increasing grenade eagerness.

**Architecture:** New context fields in `build_context()` populated by a side-wide teammate scan (3 detection paths: minigame state, sustained interaction, luggable carry). About 12 heuristic functions get early-return interaction branches. No BT modifications, no new modules.

**Tech Stack:** Lua (DMF mod framework), busted test runner

**Spec:** `docs/superpowers/specs/2026-04-08-objective-aware-activation-design.md`

---

### Task 1: Add context field defaults

**Files:**
- Modify: `tests/test_helper.lua:28-67` (make_context defaults)
- Modify: `scripts/mods/BetterBots/heuristics.lua:126-156` (build_context initialization)

- [ ] **Step 1: Add defaults to test_helper.make_context**

In `tests/test_helper.lua`, add the 5 new fields after `in_hazard = false` (line 58):

```lua
		in_hazard = false,
		ally_interacting = false,
		ally_interaction_type = nil,
		ally_interacting_unit = nil,
		ally_interacting_distance = nil,
		ally_interaction_profile = nil,
```

- [ ] **Step 2: Add defaults to build_context initialization**

In `scripts/mods/BetterBots/heuristics.lua`, add the same 5 fields to the context table after `in_hazard = false` (line 155):

```lua
		in_hazard = false,
		ally_interacting = false,
		ally_interaction_type = nil,
		ally_interacting_unit = nil,
		ally_interacting_distance = nil,
		ally_interaction_profile = nil,
```

- [ ] **Step 3: Run tests to verify no regressions**

Run: `make test`
Expected: All existing tests PASS (655 tests). New fields default to false/nil so nothing changes.

- [ ] **Step 4: Commit**

```bash
git add tests/test_helper.lua scripts/mods/BetterBots/heuristics.lua
git commit -m "feat(#37): add ally_interacting context field defaults"
```

---

### Task 2: Interaction scan loop + classification table + wiring

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua:1-6` (module-local deps)
- Modify: `scripts/mods/BetterBots/heuristics.lua:1799-1807` (init function)
- Modify: `scripts/mods/BetterBots/heuristics.lua` (after coherency loop, around line 281)
- Modify: `scripts/mods/BetterBots/BetterBots.lua:255-262` (Heuristics.init call — debug deps only)
- Modify: `tests/heuristics_spec.lua` (build_context describe block, around line 1822)

- [ ] **Step 1: Write failing tests for interaction scan**

Append to `tests/heuristics_spec.lua` inside the existing `describe("build_context", ...)` block (after line 1880). These tests exercise `build_context` directly by mocking engine globals. The `side_system` is mocked via `Managers.state.extension.system()` (not `Heuristics.init`) because `build_context` looks it up dynamically.

Tests use helper functions to reduce boilerplate. For the priority test, use Vector3-like tables `{x=N, y=0, z=0}` so distance computation works.

```lua
		describe("ally interaction scan", function()
			local side_player_units

			-- Helper: mock side_system via Managers global
			local function setup_side_system(units)
				side_player_units = units
				local original_system = _G.Managers.state.extension.system
				_G.Managers.state.extension.system = function(_, system_name)
					if system_name == "side_system" then
						return {
							side_by_unit = setmetatable({}, {
								__index = function()
									return {
										valid_player_units = side_player_units,
									}
								end,
							}),
						}
					end
					return original_system(_, system_name)
				end
			end)

			it("returns defaults when no allies interacting", function()
				side_player_units = { "hazard_bot" }
				local bb = { perception = {} }
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = nil,
				})
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_false(context.ally_interacting)
				assert.is_nil(context.ally_interaction_profile)
			end)

			it("detects shield profile via interacting character state", function()
				local ally_unit = "ally_scanner"
				side_player_units = { "hazard_bot", ally_unit }
				_G.POSITION_LOOKUP[ally_unit] = "ally_pos"
				_G.ALIVE = { mastiff = true, [ally_unit] = true }

				script_unit_extensions = script_unit_extensions or {}
				script_unit_extensions[ally_unit] = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "interacting" }
							end
							if component_name == "interacting_character_state" then
								return { interaction_template = "scanning" }
							end
							if component_name == "inventory" then
								return { wielded_slot = "slot_primary" }
							end
							return {}
						end,
						breed = function()
							return { name = "human" }
						end,
					},
				}

				local mock_side_system = {
					side_by_unit = {
						hazard_bot = {
							valid_player_units = side_player_units,
						},
					},
				}
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = mock_side_system,
				})

				local bb = { perception = {} }
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_true(context.ally_interacting)
				assert.equals("shield", context.ally_interaction_profile)
				assert.equals("scanning", context.ally_interaction_type)
				assert.equals(ally_unit, context.ally_interacting_unit)
			end)

			it("detects shield profile via minigame character state", function()
				local ally_unit = "ally_decoder"
				side_player_units = { "hazard_bot", ally_unit }
				_G.POSITION_LOOKUP[ally_unit] = "ally_pos"
				_G.ALIVE = { mastiff = true, [ally_unit] = true }

				script_unit_extensions = script_unit_extensions or {}
				script_unit_extensions[ally_unit] = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "minigame" }
							end
							if component_name == "inventory" then
								return { wielded_slot = "slot_primary" }
							end
							return {}
						end,
						breed = function()
							return { name = "human" }
						end,
					},
				}

				local mock_side_system = {
					side_by_unit = {
						hazard_bot = {
							valid_player_units = side_player_units,
						},
					},
				}
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = mock_side_system,
				})

				local bb = { perception = {} }
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_true(context.ally_interacting)
				assert.equals("shield", context.ally_interaction_profile)
				assert.equals("minigame", context.ally_interaction_type)
			end)

			it("detects escort profile via luggable wielded slot", function()
				local ally_unit = "ally_carrier"
				side_player_units = { "hazard_bot", ally_unit }
				_G.POSITION_LOOKUP[ally_unit] = "ally_pos"
				_G.ALIVE = { mastiff = true, [ally_unit] = true }

				script_unit_extensions = script_unit_extensions or {}
				script_unit_extensions[ally_unit] = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "walking" }
							end
							if component_name == "inventory" then
								return { wielded_slot = "slot_luggable" }
							end
							return {}
						end,
						breed = function()
							return { name = "human" }
						end,
					},
				}

				local mock_side_system = {
					side_by_unit = {
						hazard_bot = {
							valid_player_units = side_player_units,
						},
					},
				}
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = mock_side_system,
				})

				local bb = { perception = {} }
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_true(context.ally_interacting)
				assert.equals("escort", context.ally_interaction_profile)
			end)

			it("skips self in valid_player_units", function()
				side_player_units = { "hazard_bot" }
				local mock_side_system = {
					side_by_unit = {
						hazard_bot = {
							valid_player_units = side_player_units,
						},
					},
				}
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = mock_side_system,
				})

				local bb = { perception = {} }
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_false(context.ally_interacting)
			end)

			it("ignores non-shield interaction types", function()
				local ally_unit = "ally_looting"
				side_player_units = { "hazard_bot", ally_unit }
				_G.POSITION_LOOKUP[ally_unit] = "ally_pos"
				_G.ALIVE = { mastiff = true, [ally_unit] = true }

				script_unit_extensions = script_unit_extensions or {}
				script_unit_extensions[ally_unit] = {
					unit_data_system = {
						read_component = function(_, component_name)
							if component_name == "character_state" then
								return { state_name = "interacting" }
							end
							if component_name == "interacting_character_state" then
								return { interaction_template = "ammunition" }
							end
							if component_name == "inventory" then
								return { wielded_slot = "slot_primary" }
							end
							return {}
						end,
						breed = function()
							return { name = "human" }
						end,
					},
				}

				local mock_side_system = {
					side_by_unit = {
						hazard_bot = {
							valid_player_units = side_player_units,
						},
					},
				}
				Heuristics.init({
					fixed_time = function()
						return current_fixed_t
					end,
					decision_context_cache = {},
					super_armor_breed_cache = {},
					ARMOR_TYPE_SUPER_ARMOR = 6,
					is_testing_profile = function()
						return false
					end,
					resolve_preset = function()
						return "balanced"
					end,
					side_system = mock_side_system,
				})

				local bb = { perception = {} }
				local context = Heuristics.build_context("hazard_bot", bb)
				assert.is_false(context.ally_interacting)
			end)
		end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: New tests FAIL because `build_context` does not populate `ally_interacting` yet.

- [ ] **Step 3: Add module-local deps and classification table**

In `scripts/mods/BetterBots/heuristics.lua`, add after the existing module-locals (after line 6, `local _resolve_preset`):

```lua
local _debug_log
local _debug_enabled

local SHIELD_INTERACTION_TYPES = {
	scanning = true,
	setup_decoding = true,
	setup_breach_charge = true,
	revive = true,
	rescue = true,
	pull_up = true,
	remove_net = true,
	health_station = true,
	servo_skull = true,
	servo_skull_activator = true,
}
```

- [ ] **Step 4: Implement the interaction scan in build_context**

In `scripts/mods/BetterBots/heuristics.lua`, add after the `target_is_super_armor` block (around line 281), before the cache write (`_decision_context_cache[unit] = ...`):

```lua
	local side_system = Managers and Managers.state and Managers.state.extension
		and Managers.state.extension:system("side_system")
	if side_system then
		local side = side_system.side_by_unit[unit]
		local player_units = side and side.valid_player_units
		if player_units then
			local best_distance_sq = math.huge
			for i = 1, #player_units do
				local ally_unit = player_units[i]
				if ally_unit ~= unit and (not ALIVE or ALIVE[ally_unit]) then
					local ally_data = ScriptUnit.has_extension(ally_unit, "unit_data_system")
					if ally_data then
						local profile = nil
						local interaction_type = nil

						local char_state = ally_data:read_component("character_state")
						local state_name = char_state and char_state.state_name

						if state_name == "minigame" then
							profile = "shield"
							interaction_type = "minigame"
						elseif state_name == "interacting" then
							local interacting_state = ally_data:read_component("interacting_character_state")
							local template = interacting_state and interacting_state.interaction_template
							if template and SHIELD_INTERACTION_TYPES[template] then
								profile = "shield"
								interaction_type = template
							end
						end

						if not profile then
							local inventory = ally_data:read_component("inventory")
							if inventory and inventory.wielded_slot == "slot_luggable" then
								profile = "escort"
								interaction_type = "luggable"
							end
						end

						if profile then
							local ally_position = POSITION_LOOKUP and POSITION_LOOKUP[ally_unit]
							local dist_sq = math.huge
							if unit_position and ally_position and ally_position.x then
								local dx = ally_position.x - unit_position.x
								local dy = ally_position.y - unit_position.y
								local dz = ally_position.z - unit_position.z
								dist_sq = dx * dx + dy * dy + dz * dz
							end

							if not context.ally_interacting or dist_sq < best_distance_sq then
								best_distance_sq = dist_sq
								context.ally_interacting = true
								context.ally_interaction_type = interaction_type
								context.ally_interacting_unit = ally_unit
								context.ally_interacting_distance = dist_sq < math.huge and math.sqrt(dist_sq) or nil
								context.ally_interaction_profile = profile
							end
						end
					end
				end
			end

			if context.ally_interacting and _debug_enabled and _debug_enabled() then
				_debug_log(
					"interaction_scan:" .. tostring(unit),
					_fixed_time(),
					context.ally_interaction_profile
						.. " ("
						.. tostring(context.ally_interaction_type)
						.. ") dist="
						.. string.format("%.1f", context.ally_interacting_distance or -1),
					5
				)
			end
		end
	end
```

**Key design choices:**
- `side_system` is looked up dynamically via `Managers.state.extension:system()` — NOT cached in `init()`. `init()` runs at module load time before extension systems exist. `build_context()` only runs during gameplay when `side_system` is guaranteed alive.
- `not context.ally_interacting or dist_sq < best_distance_sq` — the first found ally is always accepted (since `ally_interacting` starts false), subsequent allies replace only if closer. This avoids the `math.huge < math.huge` dead-code bug.
- `ally_position.x` check (not `type() ~= "string"`) — idiomatic Lua duck-typing for Vector3 presence.

- [ ] **Step 5: Wire side_system and debug deps into init**

In `scripts/mods/BetterBots/heuristics.lua`, update the `init` function (around line 1800):

```lua
	init = function(deps)
		_fixed_time = deps.fixed_time
		_decision_context_cache = deps.decision_context_cache
		_super_armor_breed_cache = deps.super_armor_breed_cache
		_armor_type_super_armor = deps.ARMOR_TYPE_SUPER_ARMOR
		_is_testing_profile = deps.is_testing_profile
		_resolve_preset = deps.resolve_preset
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
	end,
```

**Note:** `side_system` is NOT wired through init — it's looked up dynamically in `build_context()` because `init()` runs at module load time before extension systems exist.

- [ ] **Step 6: Wire debug deps in BetterBots.lua**

In `scripts/mods/BetterBots/BetterBots.lua`, update the `Heuristics.init` call (around line 255). Add `debug_log` and `debug_enabled`:

```lua
Heuristics.init({
	fixed_time = _fixed_time,
	decision_context_cache = _decision_context_cache_by_unit,
	super_armor_breed_cache = _super_armor_breed_flag_by_name,
	ARMOR_TYPE_SUPER_ARMOR = ARMOR_TYPE_SUPER_ARMOR,
	is_testing_profile = Settings.is_testing_profile,
	resolve_preset = Settings.resolve_preset,
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
})
```

**Note:** `side_system` is NOT passed here — `Heuristics.init` runs at module load time (line 255 of BetterBots.lua), before extension systems exist. The `side_system` is looked up dynamically inside `build_context()` which only runs during gameplay.

- [ ] **Step 7: Run tests**

Run: `make test`
Expected: All tests PASS including the new interaction scan tests.

- [ ] **Step 8: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua scripts/mods/BetterBots/BetterBots.lua tests/heuristics_spec.lua
git commit -m "feat(#37): add interaction scan to build_context with 3-path detection"
```

---

### Task 3: Defensive ability interaction branches + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua` (7 heuristic functions)
- Modify: `tests/heuristics_spec.lua` (new test cases per heuristic)

- [ ] **Step 1: Write failing tests for defensive interaction branches**

Add to `tests/heuristics_spec.lua`. Place each test group inside (or after) the existing describe block for that ability:

```lua
	describe("interaction protection — defensive abilities", function()
		it("ogryn_taunt activates with ally interacting and 1 enemy", function()
			local ok, rule = evaluate("ogryn_taunt_shout", ctx({
				ally_interacting = true,
				num_nearby = 1,
				toughness_pct = 0.50,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("ogryn_taunt blocks protect_interactor when too fragile", function()
			local ok, rule = evaluate("ogryn_taunt_shout", ctx({
				ally_interacting = true,
				num_nearby = 1,
				toughness_pct = 0.15,
				health_pct = 0.20,
			}))
			assert.is_false(ok)
			assert.matches("too_fragile", rule)
		end)

		it("ogryn_taunt does not protect with 0 enemies", function()
			local ok, _ = evaluate("ogryn_taunt_shout", ctx({
				ally_interacting = true,
				num_nearby = 0,
				toughness_pct = 0.80,
			}))
			assert.is_false(ok)
		end)

		it("force_field activates with ally interacting and ranged enemies", function()
			local ok, rule = Heuristics.evaluate_item_heuristic("psyker_force_field", ctx({
				ally_interacting = true,
				ranged_count = 1,
				num_nearby = 1,
				target_enemy = "enemy",
				toughness_pct = 0.80,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("force_field activates with ally interacting and 2+ melee", function()
			local ok, rule = Heuristics.evaluate_item_heuristic("psyker_force_field", ctx({
				ally_interacting = true,
				ranged_count = 0,
				num_nearby = 2,
				target_enemy = "enemy",
				toughness_pct = 0.80,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("zealot_relic activates with ally interacting and allies in coherency", function()
			local ok, rule = Heuristics.evaluate_item_heuristic("zealot_relic", ctx({
				ally_interacting = true,
				allies_in_coherency = 1,
				num_nearby = 1,
				target_enemy = "enemy",
				toughness_pct = 0.80,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("drone activates at lowered team_horde threshold with ally interacting", function()
			local ok, rule = Heuristics.evaluate_item_heuristic("adamant_area_buff_drone", ctx({
				ally_interacting = true,
				allies_in_coherency = 2,
				num_nearby = 3,
				toughness_pct = 0.80,
			}))
			assert.is_true(ok)
			assert.matches("team_horde", rule)
		end)

		it("drone does NOT activate at lowered threshold without ally interacting", function()
			local ok, _ = Heuristics.evaluate_item_heuristic("adamant_area_buff_drone", ctx({
				ally_interacting = false,
				allies_in_coherency = 2,
				num_nearby = 3,
				toughness_pct = 0.80,
			}))
			assert.is_false(ok)
		end)

		it("stimm_field activates unconditionally with ally interacting", function()
			local ok, rule = Heuristics.evaluate_item_heuristic("broker_ability_stimm_field", ctx({
				ally_interacting = true,
				allies_in_coherency = 1,
				num_nearby = 0,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("adamant_shout activates with ally interacting and 1 enemy", function()
			local ok, rule = evaluate("adamant_shout", ctx({
				ally_interacting = true,
				num_nearby = 1,
				toughness_pct = 0.80,
			}))
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)

		it("veteran_voc activates with ally interacting and 1 enemy", function()
			local ok, rule = evaluate("veteran_combat_ability", ctx({
				ally_interacting = true,
				num_nearby = 1,
				toughness_pct = 0.80,
			}), {
				ability_extension = {
					_equipped_abilities = {
						combat_ability = {
							ability_template_tweak_data = { class_tag = "squad_leader" },
							name = "shout",
						},
					},
				},
				conditions = {
					_can_activate_veteran_ranger_ability = function()
						return false
					end,
				},
			})
			assert.is_true(ok)
			assert.matches("protect_interactor", rule)
		end)
	end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — heuristic functions do not check `ally_interacting` yet.

- [ ] **Step 3: Implement defensive branches**

**Ogryn Taunt** (`_can_activate_ogryn_taunt`, around line 785). Add after the `too_fragile` block (line 788), before the existing `ally_aid` rule:

```lua
	if context.ally_interacting and context.num_nearby >= 1 and context.toughness_pct > 0.30 then
		return true, "ogryn_taunt_protect_interactor"
	end
```

**Veteran VoC** (`_can_activate_veteran_combat_ability`, around line 370, inside `class_tag == "squad_leader"` branch). Add after the `in_hazard` rule (line 375), before `surrounded`:

```lua
		if context.ally_interacting and context.num_nearby >= 1 then
			return true, "veteran_voc_protect_interactor"
		end
```

**Psyker Force Field** (`_can_activate_force_field`, around line 1118). Add after the `no_threats` block (line 1121), before `ally_aid`:

```lua
	if context.ally_interacting and (context.ranged_count >= 1 or context.num_nearby >= 2) then
		return true, "force_field_protect_interactor"
	end
```

**Zealot Relic** (`_can_activate_zealot_relic`, around line 1071). Add after the `block_overwhelmed` check (line 1077), before `team_low_toughness`:

```lua
	if context.ally_interacting and context.allies_in_coherency >= 1 then
		return true, "zealot_relic_protect_interactor"
	end
```

**Arbites Drone** (`_can_activate_drone`, around line 1158). Replace the `team_horde` rule (line 1168) to lower the threshold when ally interacting:

```lua
	local team_horde_threshold = thresholds.team_horde_nearby
	if context.ally_interacting then
		team_horde_threshold = team_horde_threshold - 1
	end
	if context.allies_in_coherency >= 2 and context.num_nearby >= team_horde_threshold then
		return true, "drone_team_horde"
	end
```

**Arbites Shout** (`_can_activate_adamant_shout`, around line 992). Add at the top, before `low_toughness`:

```lua
	if context.ally_interacting and context.num_nearby >= 1 then
		return true, "adamant_shout_protect_interactor"
	end
```

**Stimm Field** (`_can_activate_stimm_field`, around line 1180). Add after the `no_allies` block (line 1183), before `corruption_heal`:

```lua
	if context.ally_interacting then
		return true, "stimm_protect_interactor"
	end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(#37): add interaction protection branches to 7 defensive heuristics"
```

---

### Task 4: Charge suppression near interacting ally + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua` (3 charge heuristic functions)
- Modify: `tests/heuristics_spec.lua`

- [ ] **Step 1: Write failing tests for charge suppression**

```lua
	describe("interaction protection — charge suppression", function()
		it("zealot_dash blocks when ally interacting within 12m", function()
			local ok, rule = evaluate("zealot_dash", ctx({
				ally_interacting = true,
				ally_interacting_distance = 8,
				target_enemy = "enemy",
				target_enemy_distance = 10,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_false(ok)
			assert.matches("block_protecting_interactor", rule)
		end)

		it("zealot_dash does not block when ally interacting beyond 12m", function()
			local ok, rule = evaluate("zealot_dash", ctx({
				ally_interacting = true,
				ally_interacting_distance = 15,
				target_enemy = "enemy",
				target_enemy_distance = 10,
				target_ally_needs_aid = true,
				target_ally_distance = 10,
			}))
			assert.is_true(ok)
			assert.matches("ally_aid", rule)
		end)

		it("zealot_dash overrides ally_aid when protecting interactor", function()
			local ok, rule = evaluate("zealot_dash", ctx({
				ally_interacting = true,
				ally_interacting_distance = 6,
				target_enemy = "enemy",
				target_enemy_distance = 8,
				target_ally_needs_aid = true,
				target_ally_distance = 5,
			}))
			assert.is_false(ok)
			assert.matches("block_protecting_interactor", rule)
		end)

		it("ogryn_charge blocks when ally interacting within 12m", function()
			local ok, rule = evaluate("ogryn_charge", ctx({
				ally_interacting = true,
				ally_interacting_distance = 8,
				target_enemy = "enemy",
				target_enemy_distance = 10,
			}))
			assert.is_false(ok)
			assert.matches("block_protecting_interactor", rule)
		end)

		it("adamant_charge blocks when ally interacting within 12m", function()
			local ok, rule = evaluate("adamant_charge", ctx({
				ally_interacting = true,
				ally_interacting_distance = 8,
				target_enemy = "enemy",
				target_enemy_distance = 10,
			}))
			assert.is_false(ok)
			assert.matches("block_protecting_interactor", rule)
		end)
	end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — charges do not check `ally_interacting` yet.

- [ ] **Step 3: Implement charge suppression**

**Zealot Dash** (`_can_activate_zealot_dash`, around line 506). Add after `block_target_too_close` (line 513), before `block_super_armor`:

```lua
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "zealot_dash_block_protecting_interactor"
	end
```

**Ogryn Charge** (`_can_activate_ogryn_charge`, around line 726). Add after `block_target_too_close` (line 730), before `priority_target`:

```lua
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "ogryn_charge_block_protecting_interactor"
	end
```

**Arbites Charge** (`_can_activate_adamant_charge`, around line 934). Add after `block_target_too_close` (line 938), before `ally_aid`:

```lua
	if context.ally_interacting and (context.ally_interacting_distance or math.huge) <= 12 then
		return false, "adamant_charge_block_protecting_interactor"
	end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(#37): suppress charges within 12m of interacting ally"
```

---

### Task 5: Grenade/blitz threshold adjustments + tests

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics.lua` (4 grenade shared functions)
- Modify: `tests/heuristics_spec.lua`

- [ ] **Step 1: Write failing tests for grenade interaction thresholds**

```lua
	describe("interaction protection — grenade thresholds", function()
		local grenade_heuristic = Heuristics.evaluate_grenade_heuristic

		it("horde grenade activates at lower threshold with ally interacting", function()
			local ok, rule = grenade_heuristic("veteran_frag_grenade", ctx({
				ally_interacting = true,
				num_nearby = 5,
				challenge_rating_sum = 2.5,
				target_enemy_distance = 8,
			}))
			assert.is_true(ok)
			assert.matches("horde", rule)
		end)

		it("horde grenade holds at normal threshold without ally interacting", function()
			local ok, _ = grenade_heuristic("veteran_frag_grenade", ctx({
				ally_interacting = false,
				num_nearby = 5,
				challenge_rating_sum = 2.5,
				target_enemy_distance = 8,
			}))
			assert.is_false(ok)
		end)

		it("chain_lightning activates at lower crowd threshold with ally interacting", function()
			local ok, rule = grenade_heuristic("psyker_chain_lightning", ctx({
				ally_interacting = true,
				num_nearby = 3,
			}))
			assert.is_true(ok)
			assert.matches("crowd", rule)
		end)

		it("chain_lightning holds at normal crowd threshold without ally interacting", function()
			local ok, _ = grenade_heuristic("psyker_chain_lightning", ctx({
				ally_interacting = false,
				num_nearby = 3,
			}))
			assert.is_false(ok)
		end)

		it("defensive grenade activates at lower count with ally interacting", function()
			local ok, rule = grenade_heuristic("veteran_smoke_grenade", ctx({
				ally_interacting = true,
				num_nearby = 3,
				toughness_pct = 0.30,
				target_enemy_distance = 8,
			}))
			assert.is_true(ok)
			assert.matches("pressure", rule)
		end)

		it("mine activates at lower density with ally interacting", function()
			local ok, rule = grenade_heuristic("adamant_shock_mine", ctx({
				ally_interacting = true,
				num_nearby = 4,
				challenge_rating_sum = 3.0,
				target_enemy_distance = 8,
			}))
			assert.is_true(ok)
			assert.matches("hold_point", rule)
		end)

		it("single-target blitz unchanged with ally interacting", function()
			local ok_with, _ = grenade_heuristic("veteran_krak_grenade", ctx({
				ally_interacting = true,
				num_nearby = 1,
				target_enemy_distance = 8,
			}))
			local ok_without, _ = grenade_heuristic("veteran_krak_grenade", ctx({
				ally_interacting = false,
				num_nearby = 1,
				target_enemy_distance = 8,
			}))
			assert.equals(ok_with, ok_without)
		end)
	end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — grenade functions do not check `ally_interacting`.

- [ ] **Step 3: Implement grenade threshold adjustments**

**`_grenade_horde`** (around line 1296). Add `interaction_offset`:

Replace the `adj_nearby` computation:
```lua
	local interaction_offset = context.ally_interacting and 1 or 0
	local adj_nearby = min_nearby + t.nearby_offset - interaction_offset
```

**`_grenade_chain_lightning`** (around line 1467). Add `interaction_offset` to both threshold checks:

```lua
	local interaction_offset = context.ally_interacting and 1 or 0
	if context.num_nearby >= t.crowd - interaction_offset then
		return true, "grenade_chain_lightning_crowd"
	end

	if context.num_nearby >= t.mixed_nearby - interaction_offset and (context.elite_count + context.special_count) >= 1 then
		return true, "grenade_chain_lightning_crowd"
	end
```

**`_grenade_defensive`** (around line 1352). Add `interaction_offset` to both count thresholds:

```lua
	local interaction_offset = context.ally_interacting and 1 or 0
```

Then adjust the two pressure checks:
```lua
	if context.ranged_count >= (2 + t.count_offset - interaction_offset) and context.toughness_pct < (0.50 + t.toughness_offset) then
```
```lua
	if context.num_nearby >= (4 + t.count_offset - interaction_offset) and context.toughness_pct < (0.35 + t.toughness_offset) then
```

**`_grenade_mine`** (around line 1374). Add `interaction_offset` to density threshold:

```lua
	local interaction_offset = context.ally_interacting and 1 or 0
```

Then adjust:
```lua
	if context.num_nearby >= (5 + t.density_offset - interaction_offset) and context.challenge_rating_sum >= 3.0 then
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mods/BetterBots/heuristics.lua tests/heuristics_spec.lua
git commit -m "feat(#37): lower grenade/blitz thresholds when protecting interacting ally"
```

---

### Task 6: Full quality gate

**Files:** None (verification only)

- [ ] **Step 1: Run make check**

Run: `make check`
Expected: format + lint + lsp + test all PASS.

- [ ] **Step 2: Fix any issues found**

If StyLua formatting fails, run `make format` and recommit. If luacheck finds new warnings, fix them.

- [ ] **Step 3: Run test count verification**

Run: `make test 2>&1 | tail -5`
Expected: Around 690-700 tests (655 existing + 35-45 new), 0 failures.

- [ ] **Step 4: Final commit if formatting was needed**

```bash
git add -A && git commit -m "style(#37): format after interaction protection implementation"
```

---

### Task 7: Documentation updates

**Files:**
- Modify: `docs/dev/debugging.md` — add `interaction_scan:` log key
- Modify: `docs/dev/logging.md` — add `interaction_scan:` to throttle key catalog

- [ ] **Step 1: Update debugging.md with new log key**

Add to the log key catalog table:

```
| `interaction_scan:<unit>` | `heuristics.lua` | Ally detected in objective interaction (profile, type, distance) |
```

- [ ] **Step 2: Update logging.md with new throttle key**

Add `interaction_scan:` to the throttle key list.

- [ ] **Step 3: Verify heuristic function count in CLAUDE.md**

Run: `grep -c "_can_activate_" scripts/mods/BetterBots/heuristics.lua`

The count should still be 18 (we added branches to existing functions, not new functions). If unchanged, no CLAUDE.md update needed.

- [ ] **Step 4: Commit**

```bash
git add docs/dev/debugging.md docs/dev/logging.md
git commit -m "docs(#37): add interaction scan log keys to debugging and logging docs"
```
