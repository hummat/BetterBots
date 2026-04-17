# Class-Level Regression Invariants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen three weak regression classes with narrow, test-only invariants at the owning seams: pre-queue suppression, profile schema preservation, and hot-reload state recovery.

**Architecture:** Keep each invariant in the existing spec that owns the relevant seam. Treat the recently added historical-bug pins as starting points, then reshape them into class-level assertions. Allow tiny local helper refactors only when the same setup is reused inside the same spec or across two specs. Avoid new generic test harnesses and avoid production changes unless a stronger invariant exposes a real defect.

**Tech Stack:** Lua 5.5, busted, StyLua, Makefile, git

---

### Task 1: Ability Queue Pre-Queue Suppression Invariant

**Files:**
- Modify: `tests/ability_queue_spec.lua`
- Test: `tests/ability_queue_spec.lua`

- [ ] **Step 1: Rewrite the historical team-cooldown regression as a class-level pre-queue invariant**

Update the existing exact-bug pin so the test name and assertions describe the seam property instead of the historical incident.

```lua
it("does not queue fallback input after a pre-queue suppression gate fires", function()
	saved_script_unit = _G.ScriptUnit
	saved_require = require

	local queued_inputs = 0
	local emitted_events = {}
	local recorded_team_key

	local ability_extension = test_helper.make_player_ability_extension({
		can_use_ability = function()
			return true
		end,
		action_input_is_currently_valid = function()
			return true
		end,
		_equipped_abilities = {
			combat_ability = {
				name = "veteran_combat_ability_shout",
				ability_template_tweak_data = { class_tag = "squad_leader" },
			},
		},
	})

	local action_input_extension = test_helper.make_player_action_input_extension({
		bot_queue_action_input = function()
			queued_inputs = queued_inputs + 1
		end,
		action_input_parsers = {
			combat_ability_action = {
				_ACTION_INPUT_SEQUENCE_CONFIGS = {
					veteran_combat_ability = {
						combat_ability_pressed = {},
					},
				},
			},
		},
	})

	local unit_data_extension = test_helper.make_player_unit_data_extension({
		combat_ability_action = { template_name = "veteran_combat_ability" },
	})

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
			return nil
		end,
		extension = function(_, system_name)
			if system_name == "ability_system" then
				return ability_extension
			end
			if system_name == "action_input_system" then
				return action_input_extension
			end
			return nil
		end,
	}

	rawset(_G, "require", function(path)
		if path == "scripts/settings/ability/ability_templates/ability_templates" then
			return {
				veteran_combat_ability = {
					ability_meta_data = {
						activation = { action_input = "combat_ability_pressed" },
					},
				},
			}
		end
		if path == "scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions" then
			return {}
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
			return 10
		end,
		equipped_combat_ability = function()
			return ability_extension, ability_extension._equipped_abilities.combat_ability
		end,
		equipped_combat_ability_name = function()
			return "veteran_combat_ability_shout"
		end,
		is_suppressed = function()
			return false
		end,
		fallback_state_by_unit = {},
		fallback_queue_dumped_by_key = {},
		DEBUG_SKIP_RELIC_LOG_INTERVAL_S = 20,
		shared_rules = SharedRules,
	})

	AbilityQueue.wire({
		Heuristics = {
			resolve_decision = function()
				return true, "veteran_voc_surrounded", { num_nearby = 3 }
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
		EventLog = {
			is_enabled = function()
				return true
			end,
			next_attempt_id = function()
				error("queued event must not allocate attempt ids after suppression")
			end,
			emit = function(event)
				emitted_events[#emitted_events + 1] = event
			end,
		},
		EngagementLeash = {
			is_movement_ability = function()
				return false
			end,
		},
		TeamCooldown = {
			is_suppressed = function(_unit, team_key)
				recorded_team_key = team_key
				return true, "team_cd:aoe_shout"
			end,
		},
		CombatAbilityIdentity = {
			resolve = function()
				return { semantic_key = "veteran_combat_ability_shout" }
			end,
		},
		HumanLikeness = {
			should_bypass_ability_jitter = function()
				return true
			end,
		},
		is_combat_template_enabled = function()
			return true
		end,
	})

	AbilityQueue.try_queue("bot_unit", { perception = {} })

	assert.equals("veteran_combat_ability_shout", recorded_team_key)
	assert.equals(0, queued_inputs)
	assert.same({}, emitted_events)
end)
```

- [ ] **Step 2: Run the targeted spec and verify the new/reshaped invariant fails for the right reason**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ability_queue_spec.lua
```

Expected:
- Either one failing assertion in the new invariant because the queue path still leaks through
- Or all green, proving the class-level invariant is already satisfied and only the spec text/shape changed

- [ ] **Step 3: Apply the minimal fix only if the stronger invariant exposes a real code-path leak**

If the new assertion fails because the fallback path still queues or emits after suppression, patch `scripts/mods/BetterBots/ability_queue.lua` at the suppression branch to return before:

```lua
action_input_extension:bot_queue_action_input(...)
```

and before:

```lua
_EventLog.next_attempt_id()
_EventLog.emit({...})
```

If the stronger invariant passes immediately, do not touch production code.

- [ ] **Step 4: Re-run the targeted spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ability_queue_spec.lua
```

Expected:
- zero failures and zero errors

- [ ] **Step 5: Commit the ability-queue invariant**

```bash
git add tests/ability_queue_spec.lua scripts/mods/BetterBots/ability_queue.lua
git commit -m "test(ability-queue): broaden pre-queue suppression invariant"
```

If no production file changed, stage only the spec file.

### Task 2: Profile Schema Preservation Invariant

**Files:**
- Modify: `tests/bot_profiles_spec.lua`
- Test: `tests/bot_profiles_spec.lua`

- [ ] **Step 1: Keep the profile test framed as a schema-preservation invariant**

Retain the curated preserved subtree and make sure the test describes the class property:

```lua
it("preserves the curated UI/profile contract subtree during in-place bot profile resolution", function()
	local saved_require = require

	local ok, err = pcall(function()
		local fake_master_items = {
			get_cached = function()
				return {
					zealot_primary = { id = "zealot_primary" },
					zealot_secondary = { id = "zealot_secondary" },
				}
			end,
			get_item_or_fallback = function(item_id)
				return { name = item_id }
			end,
			get_item_instance = function(gear)
				return {
					name = gear.masterDataInstance.id,
					gear_id = gear.masterDataInstance.id,
				}
			end,
		}

		local fake_archetypes = {
			zealot = { name = "zealot", breed = "human" },
		}

		local fake_weapon_templates = {
			powersword_2h_p1_m2 = { base_stats = { damage_stat = {}, finesse_stat = {} } },
			flamer_p1_m1 = { base_stats = { damage_stat = {}, charge_stat = {}, ammo_stat = {} } },
		}

		rawset(_G, "require", function(modname)
			if modname == "scripts/backend/master_items" then
				return fake_master_items
			end
			if modname == "scripts/utilities/local_profile_backend_parser" then
				return {
					parse_profile = function()
						return true
					end,
				}
			end
			if modname == "scripts/settings/archetype/archetypes" then
				return fake_archetypes
			end
			if modname == "scripts/settings/equipment/weapon_templates/weapon_templates" then
				return fake_weapon_templates
			end

			return saved_require(modname)
		end)

		_mock_settings.bot_slot_1_profile = "zealot"

		local profile = {
			archetype = "veteran",
			name_list_id = "veteran_names",
			current_level = 1,
			gender = "male",
			selected_voice = "veteran_male_a",
			visual_loadout = {
				slot_body_face = { id = "vanilla_face_visual" },
				slot_body_hair = { id = "vanilla_hair_visual" },
				slot_gear_head = { id = "vanilla_head_visual" },
			},
			loadout = {
				slot_primary = "bot_combatsword_linesman_p1",
				slot_secondary = "bot_lasgun_killshot",
				slot_body_face = { id = "vanilla_face_loadout" },
				slot_body_hair = { id = "vanilla_hair_loadout" },
				slot_gear_head = { id = "vanilla_head_loadout" },
			},
			loadout_item_ids = {
				slot_body_face = "vanilla_face_id",
				slot_body_hair = "vanilla_hair_id",
				slot_gear_head = "vanilla_head_id",
			},
			loadout_item_data = {
				slot_body_face = { id = "vanilla_face_id" },
				slot_body_hair = { id = "vanilla_hair_id" },
				slot_gear_head = { id = "vanilla_head_id" },
			},
			bot_gestalts = {
				melee = "linesman",
				ranged = "killshot",
			},
			talents = {},
		}

		local resolved, swapped = BotProfiles.resolve_profile(profile)

		assert.is_true(swapped)
		assert.is_true(resolved == profile)
		assert.is_true(resolved.loadout == profile.loadout)
		assert.is_true(resolved.visual_loadout == profile.visual_loadout)
		assert.is_true(resolved.loadout_item_ids == profile.loadout_item_ids)
		assert.is_true(resolved.loadout_item_data == profile.loadout_item_data)
		assert.is_not_nil(resolved.loadout.slot_body_face)
		assert.is_not_nil(resolved.visual_loadout.slot_gear_head)
		assert.is_not_nil(resolved.loadout_item_ids.slot_body_face)
		assert.is_not_nil(resolved.loadout_item_data.slot_body_face)
	end)

	rawset(_G, "require", saved_require)
	assert.is_true(ok, err)
end)
```

- [ ] **Step 2: Run the targeted spec and verify it fails only if the profile contract is actually broken**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/bot_profiles_spec.lua
```

Expected:
- Either one failing assertion on preserved subtree identity/slot presence
- Or all green, proving the current production logic already satisfies the class invariant

- [ ] **Step 3: Apply the minimal production fix only if a curated subtree actually drops**

If the test exposes a real regression in `scripts/mods/BetterBots/bot_profiles.lua`, keep the fix narrow:

```lua
-- preserve the existing non-gameplay/UI subtree; mutate gameplay fields only
profile.visual_loadout = profile.visual_loadout
profile.loadout_item_ids = profile.loadout_item_ids
profile.loadout_item_data = profile.loadout_item_data
```

The real patch should preserve the existing tables rather than recreate them. Do not broaden this into a full profile-schema framework.

- [ ] **Step 4: Re-run the targeted spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/bot_profiles_spec.lua
```

Expected:
- zero failures and zero errors

- [ ] **Step 5: Commit the profile invariant**

```bash
git add tests/bot_profiles_spec.lua scripts/mods/BetterBots/bot_profiles.lua
git commit -m "test(bot-profiles): broaden profile contract invariant"
```

If no production file changed, stage only the spec file.

### Task 3: Startup Hot-Reload Recovery Invariant

**Files:**
- Modify: `tests/startup_regressions_spec.lua`
- Test: `tests/startup_regressions_spec.lua`

- [ ] **Step 1: Keep the EventLog bootstrap case framed as a stateful hot-reload recovery invariant**

Use the real bootstrap harness and assert immediate working behavior after load:

```lua
it("restores session-scoped EventLog behavior on bootstrap after hot reload", function()
	local saved_mods = rawget(_G, "Mods")
	local event_log = dofile("scripts/mods/BetterBots/event_log.lua")

	_G.Mods = {
		lua = {
			io = {
				open = function()
					return nil
				end,
			},
			os = {
				execute = function() end,
				time = function()
					return 123
				end,
			},
		},
	}

	event_log._reset()

	local harness = make_bootstrap_harness({
		Debug = {
			collect_alive_bots = function()
				return { { unit = "bot_unit_1" } }
			end,
		},
		EventLog = event_log,
	})

	harness.mod:set("enable_event_log", true)
	harness:load()

	assert.is_true(event_log.is_enabled())
	event_log.emit({ event = "probe" })
	assert.are.equal(1, #event_log._get_buffer())

	_G.Mods = saved_mods
end)
```

- [ ] **Step 2: Run the targeted spec and verify failure only if bootstrap recovery is absent**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua
```

Expected:
- Either one failing assertion on `event_log.is_enabled()` or buffered emit behavior
- Or all green, proving bootstrap recovery already satisfies the invariant

- [ ] **Step 3: Apply the minimal fix only if bootstrap no longer restores EventLog behavior**

If the invariant fails, patch only the load-time recovery branch in `scripts/mods/BetterBots/BetterBots.lua`:

```lua
-- Re-enable EventLog after hot-reload if we're mid-session.
do
	local alive_bots = Debug.collect_alive_bots()
	if mod:get(EVENT_LOG_SETTING_ID) == true and #alive_bots > 0 then
		EventLog.set_enabled(true)
		EventLog.start_session(_fixed_time())
		_session_start_state.emitted = false
	end
end
```

Do not generalize beyond the real startup seam unless the failing test proves that another session-scoped dependency must move with it.

- [ ] **Step 4: Re-run the targeted spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua
```

Expected:
- zero failures and zero errors

- [ ] **Step 5: Commit the startup invariant**

```bash
git add tests/startup_regressions_spec.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "test(startup): broaden hot-reload recovery invariant"
```

If no production file changed, stage only the spec file.

### Task 4: Final Verification and Integration

**Files:**
- Verify: `tests/ability_queue_spec.lua`
- Verify: `tests/bot_profiles_spec.lua`
- Verify: `tests/startup_regressions_spec.lua`
- Verify if needed: `scripts/mods/BetterBots/ability_queue.lua`
- Verify if needed: `scripts/mods/BetterBots/bot_profiles.lua`
- Verify if needed: `scripts/mods/BetterBots/BetterBots.lua`

- [ ] **Step 1: Run the touched spec set together**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ability_queue_spec.lua tests/bot_profiles_spec.lua tests/startup_regressions_spec.lua
```

Expected:
- zero failures and zero errors

- [ ] **Step 2: If any production file changed, run the non-mutating local gate**

Run:

```bash
make check-ci
```

Expected:
- Lua formatting check clean
- lint clean
- lsp clean
- tests green
- doc-check green

- [ ] **Step 3: Summarize and commit the integration pass**

If the work landed as three separate commits already, skip an extra code commit and only commit any final verification-only doc or test tweaks. Otherwise:

```bash
git add tests/ability_queue_spec.lua tests/bot_profiles_spec.lua tests/startup_regressions_spec.lua scripts/mods/BetterBots/ability_queue.lua scripts/mods/BetterBots/bot_profiles.lua scripts/mods/BetterBots/BetterBots.lua
git commit -m "test(harness): add class-level regression invariants"
```
