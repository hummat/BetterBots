# Human-Likeness Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old one-bit human-likeness toggle with two profile-driven settings surfaces: one for timing hesitation and one for pressure-based melee caution, each with hidden `custom` controls.

**Architecture:** Move human-likeness from a single feature gate to two resolved configuration accessors in `settings.lua`. `human_likeness.lua` becomes a pure consumer of resolved timing/leash configs, `ability_queue.lua` consumes bucket-aware jitter delays, and `BetterBots_data.lua` exposes two dropdowns with `custom`-only sliders.

**Tech Stack:** Lua, DMF settings widgets, busted, stylua, luacheck, lua-language-server

---

## File Structure

- Modify: `scripts/mods/BetterBots/settings.lua`
  - Replace `enable_human_likeness` with the new profile defaults and config accessors.
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
  - Replace the checkbox UI with two dropdowns and hidden `custom` sub-widgets.
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
  - Add labels/tooltips for the dropdowns, preset values, and `custom` sliders.
- Modify: `scripts/mods/BetterBots/human_likeness.lua`
  - Replace fixed constants with resolved timing/leash configs; classify rules into timing buckets.
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
  - Use bucket-aware jitter delays instead of one global range.
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
  - Remove the old feature-gate wiring and refresh `BotSettings` whenever timing settings change.
- Modify: `tests/settings_spec.lua`
  - Add migration/config-resolution coverage for the new profile settings.
- Modify: `tests/human_likeness_spec.lua`
  - Add timing-bucket and profile-resolution tests.
- Modify: `tests/ability_queue_spec.lua`
  - Add defensive/opportunistic jitter timing tests.
- Modify: `tests/startup_regressions_spec.lua`
  - Assert the new setting IDs are wired and the old checkbox wiring is removed.
- Modify: `docs/dev/architecture.md`
  - Update the human-likeness section to describe split profiles and bucketed timing.
- Modify: `docs/dev/roadmap.md`
  - Update issue `#44` notes to reflect the new profile model.
- Modify: `README.md`
  - Update settings/feature descriptions if they mention the old checkbox.
- Modify: `AGENTS.md`
  - Update settings/testing text if it still names the old checkbox.

### Task 1: Lock Down Settings And Migration Behavior

**Files:**
- Modify: `tests/settings_spec.lua`
- Modify: `scripts/mods/BetterBots/settings.lua`
- Test: `tests/settings_spec.lua`

- [ ] **Step 1: Write the failing settings tests**

Add these tests to `tests/settings_spec.lua`:

```lua
	describe("human-likeness profiles", function()
		it("defaults timing and leash profiles to medium", function()
			Settings.init(mock_mod({}))

			assert.equals("medium", Settings.human_timing_profile())
			assert.equals("medium", Settings.pressure_leash_profile())
		end)

		it("migrates legacy enable_human_likeness=false to off when new profiles are unset", function()
			Settings.init(mock_mod({
				enable_human_likeness = false,
			}))

			assert.equals("off", Settings.human_timing_profile())
			assert.equals("off", Settings.pressure_leash_profile())
		end)

		it("prefers explicit timing and leash profiles over the legacy checkbox", function()
			Settings.init(mock_mod({
				enable_human_likeness = false,
				human_timing_profile = "fast",
				pressure_leash_profile = "strong",
			}))

			assert.equals("fast", Settings.human_timing_profile())
			assert.equals("strong", Settings.pressure_leash_profile())
		end)

		it("resolves medium timing config", function()
			Settings.init(mock_mod({ human_timing_profile = "medium" }))

			local config = Settings.resolve_human_timing_config()

			assert.are.same({
				enabled = true,
				reaction_min = 2,
				reaction_max = 4,
				defensive_jitter_min_s = 0.10,
				defensive_jitter_max_s = 0.25,
				opportunistic_jitter_min_s = 0.25,
				opportunistic_jitter_max_s = 0.70,
			}, config)
		end)

		it("resolves off timing config", function()
			Settings.init(mock_mod({ human_timing_profile = "off" }))

			local config = Settings.resolve_human_timing_config()

			assert.is_false(config.enabled)
			assert.equals(10, config.reaction_min)
			assert.equals(20, config.reaction_max)
			assert.equals(0, config.defensive_jitter_min_s)
			assert.equals(0, config.opportunistic_jitter_max_s)
		end)

		it("resolves strong pressure leash config", function()
			Settings.init(mock_mod({ pressure_leash_profile = "strong" }))

			local config = Settings.resolve_pressure_leash_config()

			assert.are.same({
				enabled = true,
				start_rating = 8,
				full_rating = 24,
				scale_multiplier = 0.50,
				floor_m = 6,
			}, config)
		end)

		it("uses medium pressure defaults when custom slider values are invalid", function()
			Settings.init(mock_mod({
				pressure_leash_profile = "custom",
				pressure_leash_start_rating = 40,
				pressure_leash_full_rating = 20,
			}))

			local config = Settings.resolve_pressure_leash_config()

			assert.equals(12, config.start_rating)
			assert.equals(30, config.full_rating)
			assert.equals(0.65, config.scale_multiplier)
			assert.equals(7, config.floor_m)
		end)

		it("uses medium timing defaults when custom slider values are invalid", function()
			Settings.init(mock_mod({
				human_timing_profile = "custom",
				human_timing_reaction_min = "bad",
				human_timing_reaction_max = "worse",
			}))

			local config = Settings.resolve_human_timing_config()

			assert.equals(2, config.reaction_min)
			assert.equals(4, config.reaction_max)
		end)

		it("uses custom timing slider values when valid", function()
			Settings.init(mock_mod({
				human_timing_profile = "custom",
				human_timing_reaction_min = 1,
				human_timing_reaction_max = 5,
				human_timing_defensive_jitter_min_ms = 80,
				human_timing_defensive_jitter_max_ms = 180,
				human_timing_opportunistic_jitter_min_ms = 200,
				human_timing_opportunistic_jitter_max_ms = 900,
			}))

			local config = Settings.resolve_human_timing_config()

			assert.equals(1, config.reaction_min)
			assert.equals(5, config.reaction_max)
			assert.are.equal(0.08, config.defensive_jitter_min_s)
			assert.are.equal(0.18, config.defensive_jitter_max_s)
			assert.are.equal(0.20, config.opportunistic_jitter_min_s)
			assert.are.equal(0.90, config.opportunistic_jitter_max_s)
		end)

		it("uses custom pressure leash slider values when valid", function()
			Settings.init(mock_mod({
				pressure_leash_profile = "custom",
				pressure_leash_start_rating = 14,
				pressure_leash_full_rating = 34,
				pressure_leash_scale_percent = 75,
				pressure_leash_floor_m = 9,
			}))

			local config = Settings.resolve_pressure_leash_config()

			assert.equals(14, config.start_rating)
			assert.equals(34, config.full_rating)
			assert.equals(0.75, config.scale_multiplier)
			assert.equals(9, config.floor_m)
		end)
	end)
```

While editing `tests/settings_spec.lua`, remove the legacy `human_likeness` feature-gate expectations from the existing `describe("is_feature_enabled")` block. `human_likeness` is no longer a feature gate once the split profiles land.

- [ ] **Step 2: Run the settings spec and verify it fails for missing accessors/defaults**

Run:

```bash
busted tests/settings_spec.lua
```

Expected:

- FAIL on missing `human_timing_profile`, `pressure_leash_profile`, or `resolve_*_config` accessors

- [ ] **Step 3: Implement settings defaults, migration, and config accessors**

Update `scripts/mods/BetterBots/settings.lua` with these structural changes:

```lua
local HUMAN_TIMING_PROFILES = {
	off = {
		enabled = false,
		reaction_min = 10,
		reaction_max = 20,
		defensive_jitter_min_s = 0,
		defensive_jitter_max_s = 0,
		opportunistic_jitter_min_s = 0,
		opportunistic_jitter_max_s = 0,
	},
	fast = {
		enabled = true,
		reaction_min = 1,
		reaction_max = 3,
		defensive_jitter_min_s = 0.05,
		defensive_jitter_max_s = 0.15,
		opportunistic_jitter_min_s = 0.15,
		opportunistic_jitter_max_s = 0.45,
	},
	medium = {
		enabled = true,
		reaction_min = 2,
		reaction_max = 4,
		defensive_jitter_min_s = 0.10,
		defensive_jitter_max_s = 0.25,
		opportunistic_jitter_min_s = 0.25,
		opportunistic_jitter_max_s = 0.70,
	},
	slow = {
		enabled = true,
		reaction_min = 3,
		reaction_max = 6,
		defensive_jitter_min_s = 0.15,
		defensive_jitter_max_s = 0.35,
		opportunistic_jitter_min_s = 0.40,
		opportunistic_jitter_max_s = 1.00,
	},
}

local PRESSURE_LEASH_PROFILES = {
	off = {
		enabled = false,
		start_rating = 10,
		full_rating = 30,
		scale_multiplier = 1.0,
		floor_m = 6,
	},
	light = {
		enabled = true,
		start_rating = 16,
		full_rating = 36,
		scale_multiplier = 0.80,
		floor_m = 8,
	},
	medium = {
		enabled = true,
		start_rating = 12,
		full_rating = 30,
		scale_multiplier = 0.65,
		floor_m = 7,
	},
	strong = {
		enabled = true,
		start_rating = 8,
		full_rating = 24,
		scale_multiplier = 0.50,
		floor_m = 6,
	},
}

M.DEFAULTS.human_timing_profile = "medium"
M.DEFAULTS.pressure_leash_profile = "medium"
M.DEFAULTS.human_timing_reaction_min = 2
M.DEFAULTS.human_timing_reaction_max = 4
M.DEFAULTS.human_timing_defensive_jitter_min_ms = 100
M.DEFAULTS.human_timing_defensive_jitter_max_ms = 250
M.DEFAULTS.human_timing_opportunistic_jitter_min_ms = 250
M.DEFAULTS.human_timing_opportunistic_jitter_max_ms = 700
M.DEFAULTS.pressure_leash_start_rating = 12
M.DEFAULTS.pressure_leash_full_rating = 30
M.DEFAULTS.pressure_leash_scale_percent = 65
M.DEFAULTS.pressure_leash_floor_m = 7

local HUMAN_TIMING_PROFILE_OPTIONS = {
	off = true,
	fast = true,
	medium = true,
	slow = true,
	custom = true,
}

local PRESSURE_LEASH_PROFILE_OPTIONS = {
	off = true,
	light = true,
	medium = true,
	strong = true,
	custom = true,
}

local function _copy_config(config)
	local copy = {}
	for key, value in pairs(config) do
		copy[key] = value
	end
	return copy
end

local function _resolve_profile(setting_id, legacy_id, valid_values, default_value)
	if not _mod then
		return default_value
	end

	local explicit_value = _mod:get(setting_id)
	if explicit_value ~= nil then
		if valid_values[explicit_value] then
			return explicit_value
		end
		return default_value
	end

	if _mod:get(legacy_id) == false then
		return "off"
	end

	return default_value
end

function M.human_timing_profile()
	return _resolve_profile("human_timing_profile", "enable_human_likeness", HUMAN_TIMING_PROFILE_OPTIONS, "medium")
end

function M.pressure_leash_profile()
	return _resolve_profile("pressure_leash_profile", "enable_human_likeness", PRESSURE_LEASH_PROFILE_OPTIONS, "medium")
end

function M.resolve_human_timing_config()
	local profile = M.human_timing_profile()
	if profile ~= "custom" then
		return _copy_config(HUMAN_TIMING_PROFILES[profile] or HUMAN_TIMING_PROFILES.medium)
	end

	local fallback = HUMAN_TIMING_PROFILES.medium
	local reaction_min = _read_numeric_setting("human_timing_reaction_min", fallback.reaction_min, 0, 20)
	local reaction_max = _read_numeric_setting("human_timing_reaction_max", fallback.reaction_max, 0, 20)
	local defensive_min_ms = _read_numeric_setting("human_timing_defensive_jitter_min_ms", 100, 0, 1000)
	local defensive_max_ms = _read_numeric_setting("human_timing_defensive_jitter_max_ms", 250, 0, 1000)
	local opportunistic_min_ms = _read_numeric_setting("human_timing_opportunistic_jitter_min_ms", 250, 0, 1500)
	local opportunistic_max_ms = _read_numeric_setting("human_timing_opportunistic_jitter_max_ms", 700, 0, 1500)

	if reaction_min > reaction_max or defensive_min_ms > defensive_max_ms or opportunistic_min_ms > opportunistic_max_ms then
		return _copy_config(fallback)
	end

	return {
		enabled = true,
		reaction_min = reaction_min,
		reaction_max = reaction_max,
		defensive_jitter_min_s = defensive_min_ms / 1000,
		defensive_jitter_max_s = defensive_max_ms / 1000,
		opportunistic_jitter_min_s = opportunistic_min_ms / 1000,
		opportunistic_jitter_max_s = opportunistic_max_ms / 1000,
	}
end

function M.resolve_pressure_leash_config()
	local profile = M.pressure_leash_profile()
	if profile ~= "custom" then
		return _copy_config(PRESSURE_LEASH_PROFILES[profile] or PRESSURE_LEASH_PROFILES.medium)
	end

	local fallback = PRESSURE_LEASH_PROFILES.medium
	local start_rating = _read_numeric_setting("pressure_leash_start_rating", fallback.start_rating, 0, 40)
	local full_rating = _read_numeric_setting("pressure_leash_full_rating", fallback.full_rating, 1, 50)
	local scale_percent = _read_numeric_setting("pressure_leash_scale_percent", 65, 25, 100)
	local floor_m = _read_numeric_setting("pressure_leash_floor_m", fallback.floor_m, 4, 12)

	if full_rating <= start_rating then
		return _copy_config(fallback)
	end

	return {
		enabled = true,
		start_rating = start_rating,
		full_rating = full_rating,
		scale_multiplier = scale_percent / 100,
		floor_m = floor_m,
	}
end
```

Also remove `enable_human_likeness` from `M.DEFAULTS` and remove `human_likeness = "enable_human_likeness"` from `FEATURE_GATES`.

Place the new profile-accessor block after the existing `_read_numeric_setting(...)` helper so the accessors bind to the local helper instead of an accidental global.

- [ ] **Step 4: Re-run the settings spec and verify it passes**

Run:

```bash
busted tests/settings_spec.lua
```

Expected:

- PASS with all new profile tests green

- [ ] **Step 5: Commit the settings backbone**

```bash
git add scripts/mods/BetterBots/settings.lua tests/settings_spec.lua
git commit -m "feat(settings): add human-likeness profile accessors"
```

### Task 2: Replace The DMF Settings Surface

**Files:**
- Modify: `scripts/mods/BetterBots/BetterBots_data.lua`
- Modify: `scripts/mods/BetterBots/BetterBots_localization.lua`
- Modify: `tests/settings_spec.lua`
- Test: `tests/settings_spec.lua`

- [ ] **Step 1: Add failing source-scan tests for the new widget IDs**

Append these assertions to `tests/settings_spec.lua` near the existing UI/source-scan block:

```lua
		it("uses split human-likeness dropdowns with custom sub-widgets", function()
			local handle = assert(io.open("scripts/mods/BetterBots/BetterBots_data.lua", "r"))
			local source = assert(handle:read("*a"))
			handle:close()

			assert.is_truthy(source:find('setting_id = "human_timing_profile"', 1, true))
			assert.is_truthy(source:find('setting_id = "pressure_leash_profile"', 1, true))
			assert.is_truthy(source:find('text = "human_timing_profile_fast", value = "fast"', 1, true))
			assert.is_truthy(source:find('text = "pressure_leash_profile_strong", value = "strong"', 1, true))
			assert.is_truthy(source:find('setting_id = "human_timing_reaction_min"', 1, true))
			assert.is_truthy(source:find('setting_id = "pressure_leash_scale_percent"', 1, true))
			assert.is_nil(source:find('setting_id = "enable_human_likeness"', 1, true))
		end)
```

- [ ] **Step 2: Run the settings spec and verify the source-scan fails**

Run:

```bash
busted tests/settings_spec.lua
```

Expected:

- FAIL because `BetterBots_data.lua` and localization still contain the old checkbox surface

- [ ] **Step 3: Replace the old checkbox with two dropdowns and hidden custom sliders**

Update `scripts/mods/BetterBots/BetterBots_data.lua` like this:

```lua
{
	setting_id = "human_timing_profile",
	type = "dropdown",
	default_value = DEFAULTS.human_timing_profile,
	options = {
		{ text = "human_timing_profile_off", value = "off", show_widgets = {} },
		{ text = "human_timing_profile_fast", value = "fast", show_widgets = {} },
		{ text = "human_timing_profile_medium", value = "medium", show_widgets = {} },
		{ text = "human_timing_profile_slow", value = "slow", show_widgets = {} },
		{ text = "human_timing_profile_custom", value = "custom", show_widgets = { 1, 2, 3, 4, 5, 6 } },
	},
	sub_widgets = {
		make_numeric("human_timing_reaction_min", { 0, 20 }, 1),
		make_numeric("human_timing_reaction_max", { 0, 20 }, 1),
		make_numeric("human_timing_defensive_jitter_min_ms", { 0, 1000 }, 50),
		make_numeric("human_timing_defensive_jitter_max_ms", { 0, 1000 }, 50),
		make_numeric("human_timing_opportunistic_jitter_min_ms", { 0, 1500 }, 50),
		make_numeric("human_timing_opportunistic_jitter_max_ms", { 0, 1500 }, 50),
	},
},
{
	setting_id = "pressure_leash_profile",
	type = "dropdown",
	default_value = DEFAULTS.pressure_leash_profile,
	options = {
		{ text = "pressure_leash_profile_off", value = "off", show_widgets = {} },
		{ text = "pressure_leash_profile_light", value = "light", show_widgets = {} },
		{ text = "pressure_leash_profile_medium", value = "medium", show_widgets = {} },
		{ text = "pressure_leash_profile_strong", value = "strong", show_widgets = {} },
		{ text = "pressure_leash_profile_custom", value = "custom", show_widgets = { 1, 2, 3, 4 } },
	},
	sub_widgets = {
		make_numeric("pressure_leash_start_rating", { 0, 40 }, 1),
		make_numeric("pressure_leash_full_rating", { 1, 50 }, 1),
		make_numeric("pressure_leash_scale_percent", { 25, 100 }, 5),
		make_numeric("pressure_leash_floor_m", { 4, 12 }, 1),
	},
},
```

Remove the old `enable_human_likeness` widget.

Add localization entries in `scripts/mods/BetterBots/BetterBots_localization.lua` for:

```lua
human_timing_profile = { en = "Ability timing profile" }
human_timing_profile_description = {
	en = "Controls how quickly bots react to opportunities and how much they hesitate before non-urgent ability casts."
}
human_timing_profile_off = { en = "Off" }
human_timing_profile_fast = { en = "Fast" }
human_timing_profile_medium = { en = "Medium" }
human_timing_profile_slow = { en = "Slow" }
human_timing_profile_custom = { en = "Custom" }

pressure_leash_profile = { en = "Pressure caution profile" }
pressure_leash_profile_description = {
	en = "Controls how much melee bots stay tighter to the team when threat pressure rises."
}
pressure_leash_profile_off = { en = "Off" }
pressure_leash_profile_light = { en = "Light" }
pressure_leash_profile_medium = { en = "Medium" }
pressure_leash_profile_strong = { en = "Strong" }
pressure_leash_profile_custom = { en = "Custom" }

human_timing_reaction_min = { en = "Opportunity reaction min" }
human_timing_reaction_min_description = { en = "Minimum opportunity-target reaction time when the timing profile is Custom." }
human_timing_reaction_max = { en = "Opportunity reaction max" }
human_timing_reaction_max_description = { en = "Maximum opportunity-target reaction time when the timing profile is Custom." }
human_timing_defensive_jitter_min_ms = { en = "Defensive jitter min (ms)" }
human_timing_defensive_jitter_min_ms_description = { en = "Minimum hesitation for defensive but non-emergency ability rules." }
human_timing_defensive_jitter_max_ms = { en = "Defensive jitter max (ms)" }
human_timing_defensive_jitter_max_ms_description = { en = "Maximum hesitation for defensive but non-emergency ability rules." }
human_timing_opportunistic_jitter_min_ms = { en = "Opportunistic jitter min (ms)" }
human_timing_opportunistic_jitter_min_ms_description = { en = "Minimum hesitation for opportunistic ability rules." }
human_timing_opportunistic_jitter_max_ms = { en = "Opportunistic jitter max (ms)" }
human_timing_opportunistic_jitter_max_ms_description = { en = "Maximum hesitation for opportunistic ability rules." }

pressure_leash_start_rating = { en = "Pressure start rating" }
pressure_leash_start_rating_description = { en = "Challenge rating where melee caution starts tightening the leash." }
pressure_leash_full_rating = { en = "Pressure full rating" }
pressure_leash_full_rating_description = { en = "Challenge rating where melee caution reaches its full effect." }
pressure_leash_scale_percent = { en = "Full-pressure leash %" }
pressure_leash_scale_percent_description = { en = "Percentage of the base leash kept at full pressure." }
pressure_leash_floor_m = { en = "Minimum leash floor (m)" }
pressure_leash_floor_m_description = { en = "Absolute minimum engage leash allowed by the custom pressure profile." }
```

- [ ] **Step 4: Re-run the settings spec and verify the UI assertions pass**

Run:

```bash
busted tests/settings_spec.lua
```

Expected:

- PASS with the new source-scan assertions green

- [ ] **Step 5: Commit the UI surface**

```bash
git add scripts/mods/BetterBots/BetterBots_data.lua scripts/mods/BetterBots/BetterBots_localization.lua tests/settings_spec.lua
git commit -m "feat(settings): split human-likeness UI profiles"
```

### Task 3: Add Human-Likeness Profile Tests

**Files:**
- Modify: `tests/human_likeness_spec.lua`
- Modify: `scripts/mods/BetterBots/human_likeness.lua`
- Test: `tests/human_likeness_spec.lua`

- [ ] **Step 1: Write the failing human-likeness tests**

Add these tests to `tests/human_likeness_spec.lua`:

```lua
	it("patches opportunity target reaction times from the medium timing profile", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = true,
					reaction_min = 2,
					reaction_max = 4,
					defensive_jitter_min_s = 0.10,
					defensive_jitter_max_s = 0.25,
					opportunistic_jitter_min_s = 0.25,
					opportunistic_jitter_max_s = 0.70,
				}
			end,
			get_pressure_leash_config = function()
				return { enabled = false }
			end,
		})

		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(2, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(4, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("leaves reaction times unchanged when the timing profile is off", function()
		local BotSettings = {
			opportunity_target_reaction_times = {
				normal = { min = 10, max = 20 },
			},
		}

		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = false,
					reaction_min = 10,
					reaction_max = 20,
					defensive_jitter_min_s = 0,
					defensive_jitter_max_s = 0,
					opportunistic_jitter_min_s = 0,
					opportunistic_jitter_max_s = 0,
				}
			end,
			get_pressure_leash_config = function()
				return { enabled = false }
			end,
		})

		HumanLikeness.patch_bot_settings(BotSettings)

		assert.equals(10, BotSettings.opportunity_target_reaction_times.normal.min)
		assert.equals(20, BotSettings.opportunity_target_reaction_times.normal.max)
	end)

	it("classifies emergency rules as immediate timing", function()
		HumanLikeness.init({})

		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("zealot_stealth_emergency"))
		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("ogryn_charge_escape"))
		assert.equals("immediate", HumanLikeness.jitter_bucket_for_rule("psyker_shout_high_peril"))
	end)

	it("classifies survival pressure rules as defensive timing", function()
		HumanLikeness.init({})

		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("veteran_voc_critical_toughness"))
		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("drone_overwhelmed"))
		assert.equals("defensive", HumanLikeness.jitter_bucket_for_rule("force_field_pressure"))
	end)

	it("classifies target-selection rules as opportunistic timing", function()
		HumanLikeness.init({})

		assert.equals("opportunistic", HumanLikeness.jitter_bucket_for_rule("ogryn_charge_priority_target"))
		assert.equals("opportunistic", HumanLikeness.jitter_bucket_for_rule("adamant_charge_density"))
	end)

	it("returns defensive jitter from the timing config", function()
		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = true,
					reaction_min = 2,
					reaction_max = 4,
					defensive_jitter_min_s = 0.10,
					defensive_jitter_max_s = 0.25,
					opportunistic_jitter_min_s = 0.25,
					opportunistic_jitter_max_s = 0.70,
				}
			end,
		})

		local delay = HumanLikeness.random_ability_jitter_delay("veteran_voc_critical_toughness")
		assert.is_true(delay >= 0.10)
		assert.is_true(delay <= 0.25)
	end)

	it("bypasses non-emergency jitter and leash scaling when both profiles are off", function()
		HumanLikeness.init({
			get_timing_config = function()
				return {
					enabled = false,
					reaction_min = 10,
					reaction_max = 20,
					defensive_jitter_min_s = 0,
					defensive_jitter_max_s = 0,
					opportunistic_jitter_min_s = 0,
					opportunistic_jitter_max_s = 0,
				}
			end,
			get_pressure_leash_config = function()
				return {
					enabled = false,
					start_rating = 12,
					full_rating = 30,
					scale_multiplier = 0.65,
					floor_m = 7,
				}
			end,
		})

		assert.is_true(HumanLikeness.should_bypass_ability_jitter("psyker_shout_mixed_pack"))
		assert.equals(20, HumanLikeness.scale_engage_leash(20, 30))
	end)

	it("uses the pressure leash profile to scale engage range", function()
		HumanLikeness.init({
			get_pressure_leash_config = function()
				return {
					enabled = true,
					start_rating = 12,
					full_rating = 30,
					scale_multiplier = 0.65,
					floor_m = 7,
				}
			end,
		})

		assert.equals(20, HumanLikeness.scale_engage_leash(20, 0))
		assert.is_true(HumanLikeness.scale_engage_leash(20, 20) < 20)
		assert.equals(13, HumanLikeness.scale_engage_leash(20, 30))
	end)
```

- [ ] **Step 2: Run the human-likeness spec and verify it fails**

Run:

```bash
busted tests/human_likeness_spec.lua
```

Expected:

- FAIL on missing `jitter_bucket_for_rule` or wrong reaction-time patch values

- [ ] **Step 3: Implement profile-driven human-likeness logic**

Refactor `scripts/mods/BetterBots/human_likeness.lua` around injected config accessors:

```lua
local _get_timing_config
local _get_pressure_leash_config

function M.init(deps)
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
	_get_timing_config = deps.get_timing_config
	_get_pressure_leash_config = deps.get_pressure_leash_config
end

local function _timing_config()
	if _get_timing_config then
		return _get_timing_config()
	end

	return {
		enabled = true,
		reaction_min = 2,
		reaction_max = 4,
		defensive_jitter_min_s = 0.10,
		defensive_jitter_max_s = 0.25,
		opportunistic_jitter_min_s = 0.25,
		opportunistic_jitter_max_s = 0.70,
	}
end

local function _pressure_leash_config()
	if _get_pressure_leash_config then
		return _get_pressure_leash_config()
	end

	return {
		enabled = true,
		start_rating = 12,
		full_rating = 30,
		scale_multiplier = 0.65,
		floor_m = 7,
	}
end

function M.jitter_bucket_for_rule(rule)
	if not rule then
		return "opportunistic"
	end
	if _contains(rule, "ally_aid")
		or _contains(rule, "panic")
		or _contains(rule, "last_stand")
		or _contains(rule, "hazard")
		or _contains(rule, "emergency")
		or _contains(rule, "escape")
		or _contains(rule, "high_peril") then
		return "immediate"
	end
	if _contains(rule, "protect_interactor")
		or _contains(rule, "critical")
		or _contains(rule, "low_health")
		or _contains(rule, "self_critical")
		or _contains(rule, "low_toughness")
		or _contains(rule, "surrounded")
		or _contains(rule, "overwhelmed")
		or _contains(rule, "pressure")
		or _contains(rule, "high_threat")
		or _contains(rule, "ally_reposition") then
		return "defensive"
	end
	return "opportunistic"
end

function M.patch_bot_settings(bot_settings)
	if not bot_settings then
		return
	end

	local times = bot_settings.opportunity_target_reaction_times
	local normal = times and times.normal
	if not normal then
		return
	end

	if not _original_bot_settings[bot_settings] then
		_original_bot_settings[bot_settings] = {
			min = normal.min,
			max = normal.max,
		}
	end

	local config = _timing_config()
	if not config.enabled then
		_restore_original_bot_settings(bot_settings, normal)
		return
	end

	normal.min = config.reaction_min
	normal.max = config.reaction_max
	_patched_bot_settings[bot_settings] = true
end

function M.should_bypass_ability_jitter(rule)
	local config = _timing_config()
	if not config.enabled then
		return true
	end

	return M.jitter_bucket_for_rule(rule) == "immediate"
end

function M.random_ability_jitter_delay(rule)
	local config = _timing_config()
	local bucket = M.jitter_bucket_for_rule(rule)
	local min_s
	local max_s

	if bucket == "defensive" then
		min_s = config.defensive_jitter_min_s
		max_s = config.defensive_jitter_max_s
	else
		min_s = config.opportunistic_jitter_min_s
		max_s = config.opportunistic_jitter_max_s
	end

	return _lerp(min_s, max_s, math.random())
end

function M.scale_engage_leash(effective_leash, challenge_rating_sum)
	local config = _pressure_leash_config()
	if not config.enabled then
		return effective_leash
	end

	local lerp_t = (challenge_rating_sum - config.start_rating) / (config.full_rating - config.start_rating)
	if lerp_t <= 0 then
		return effective_leash
	end

	local challenge_leash = math.max(config.floor_m, effective_leash * config.scale_multiplier)
	if lerp_t >= 1 then
		return challenge_leash
	end

	return _lerp(effective_leash, challenge_leash, lerp_t * lerp_t)
end
```

- [ ] **Step 4: Re-run the human-likeness spec and verify it passes**

Run:

```bash
busted tests/human_likeness_spec.lua
```

Expected:

- PASS with bucket classification, patching, and pressure scaling all green

- [ ] **Step 5: Commit the human-likeness refactor**

```bash
git add scripts/mods/BetterBots/human_likeness.lua tests/human_likeness_spec.lua
git commit -m "feat(human-likeness): add timing and leash profiles"
```

### Task 4: Wire The New Timing Model Into Queueing And Startup

**Files:**
- Modify: `tests/ability_queue_spec.lua`
- Modify: `tests/startup_regressions_spec.lua`
- Modify: `scripts/mods/BetterBots/ability_queue.lua`
- Modify: `scripts/mods/BetterBots/BetterBots.lua`
- Test: `tests/ability_queue_spec.lua`
- Test: `tests/startup_regressions_spec.lua`

- [ ] **Step 1: Write failing queue and startup tests**

Add to `tests/ability_queue_spec.lua`:

```lua
	local function run_pending_jitter_rule(rule, delay)
		saved_script_unit = _G.ScriptUnit
		saved_require = require

		local fixed_t = 10
		local state_by_unit = {}
		local action_input_extension = test_helper.make_player_action_input_extension({
			bot_queue_action_input = function() end,
			action_input_parsers = {
				combat_ability_action = {
					_ACTION_INPUT_SEQUENCE_CONFIGS = {
						psyker_shout = {
							shout_pressed = {},
						},
					},
				},
			},
		})
		local ability_extension = test_helper.make_player_ability_extension({
			can_use_ability = function()
				return true
			end,
			action_input_is_currently_valid = function()
				return true
			end,
		})
		local unit_data_extension = test_helper.make_player_unit_data_extension({
			combat_ability_action = { template_name = "psyker_shout" },
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
					return true, rule, {}
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
					return false
				end,
			},
			EngagementLeash = {
				is_movement_ability = function()
					return false
				end,
			},
			TeamCooldown = {
				is_suppressed = function()
					return false
				end,
			},
			CombatAbilityIdentity = {
				resolve = function()
					return nil
				end,
			},
			HumanLikeness = {
				should_bypass_ability_jitter = function()
					return false
				end,
				random_ability_jitter_delay = function(asked_rule)
					assert.equals(rule, asked_rule)
					return delay
				end,
			},
			is_combat_template_enabled = function()
				return true
			end,
		})

		AbilityQueue.try_queue("bot_unit", {})
		return state_by_unit.bot_unit.pending_ready_t
	end

	it("uses defensive jitter for defensive rules", function()
		assert.equals(10.2, run_pending_jitter_rule("veteran_voc_critical_toughness", 0.2))
	end)

	it("uses opportunistic jitter for opportunistic rules", function()
		assert.equals(10.8, run_pending_jitter_rule("ogryn_charge_priority_target", 0.8))
	end)
```

Add to `tests/startup_regressions_spec.lua`:

```lua
	it("refreshes BotSettings when the timing profile changes", function()
		local handle = assert(io.open("scripts/mods/BetterBots/BetterBots.lua", "r"))
		local source = assert(handle:read("*a"))
		handle:close()

		assert.is_truthy(source:find('local TIMING_SETTING_IDS = {', 1, true))
		assert.is_truthy(source:find('human_timing_profile = true', 1, true))
		assert.is_truthy(source:find('human_timing_opportunistic_jitter_max_ms = true', 1, true))
		assert.is_truthy(source:find('if TIMING_SETTING_IDS%[setting_id%] then', 1))
		assert.is_truthy(source:find("HumanLikeness%.patch_bot_settings%(", 1))
		assert.is_nil(source:find('if setting_id == "enable_human_likeness" then', 1, true))
	end)
```

- [ ] **Step 2: Run the targeted specs and verify they fail**

Run:

```bash
busted tests/ability_queue_spec.lua tests/startup_regressions_spec.lua
```

Expected:

- FAIL because the queue still assumes one global jitter range and `BetterBots.lua` still references the old checkbox

- [ ] **Step 3: Implement queue + startup wiring changes**

Update `scripts/mods/BetterBots/ability_queue.lua`:

```lua
	local bypass_jitter = _HumanLikeness and _HumanLikeness.should_bypass_ability_jitter(rule)
	if _HumanLikeness and not bypass_jitter then
		local pending_matches = state.pending_rule == rule
			and state.pending_template_name == ability_template_name
			and state.pending_action_input == action_input

		if not pending_matches then
			state.pending_rule = rule
			state.pending_template_name = ability_template_name
			state.pending_action_input = action_input
			state.pending_ready_t = fixed_t + _HumanLikeness.random_ability_jitter_delay(rule)
			return
		end
```

Update `scripts/mods/BetterBots/BetterBots.lua`:

```lua
HumanLikeness.init({
	debug_log = _debug_log,
	debug_enabled = _debug_enabled,
	get_timing_config = Settings.resolve_human_timing_config,
	get_pressure_leash_config = Settings.resolve_pressure_leash_config,
})
```

Add a helper for timing-setting refresh:

```lua
local TIMING_SETTING_IDS = {
	human_timing_profile = true,
	human_timing_reaction_min = true,
	human_timing_reaction_max = true,
	human_timing_defensive_jitter_min_ms = true,
	human_timing_defensive_jitter_max_ms = true,
	human_timing_opportunistic_jitter_min_ms = true,
	human_timing_opportunistic_jitter_max_ms = true,
}

function mod.on_setting_changed(setting_id)
	if TIMING_SETTING_IDS[setting_id] then
		HumanLikeness.patch_bot_settings(_bot_settings)
	end
end
```

Remove the old `enable_human_likeness` setting-change branch.

- [ ] **Step 4: Re-run the targeted queue/startup specs and verify they pass**

Run:

```bash
busted tests/ability_queue_spec.lua tests/startup_regressions_spec.lua
```

Expected:

- PASS with rule-aware jitter scheduling and new timing-setting refresh wiring

- [ ] **Step 5: Commit the runtime wiring**

```bash
git add scripts/mods/BetterBots/ability_queue.lua scripts/mods/BetterBots/BetterBots.lua tests/ability_queue_spec.lua tests/startup_regressions_spec.lua
git commit -m "feat(human-likeness): wire profile-driven timing"
```

### Task 5: Update Documentation And Run Full Verification

**Files:**
- Modify: `docs/dev/architecture.md`
- Modify: `docs/dev/roadmap.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: full repo verification

- [ ] **Step 1: Update docs to describe split timing/leash profiles**

Make these file-specific updates:

```markdown
- `docs/dev/architecture.md`: replace the old `2-5` / `0.3-1.5s` single-toggle description with the two-profile model, naming the three timing buckets (`immediate`, `defensive`, `opportunistic`) and the separate pressure-leash presets.
- `docs/dev/roadmap.md`: change issue `#44` from “patches opportunity-target reaction times from `10-20` to `2-5` plus `0.3-1.5s` jitter” to “profile-driven timing presets (`off/fast/medium/slow/custom`) plus separate pressure-leash presets (`off/light/medium/strong/custom`).”
- `README.md`: in the Highlights/settings area, replace any single “human-likeness” toggle wording with “timing profile” and “pressure caution profile.”
- `AGENTS.md`: update the module comment for `human_likeness.lua` and the `human_likeness_spec.lua` description so they mention split timing/leash profiles instead of one teammate-feel toggle.
```

- [ ] **Step 2: Run the full quality gate**

Run:

```bash
make check
```

Expected:

- `stylua --check` passes
- `luacheck` passes
- `lua-language-server --check` passes
- `891+` tests pass (update any test-count docs if the suite count changes)
- `doc-check` passes

- [ ] **Step 3: Commit the docs + final integration**

```bash
git add docs/dev/architecture.md docs/dev/roadmap.md README.md AGENTS.md
git commit -m "docs: update human-likeness profile configuration"
```

- [ ] **Step 4: Inspect final history and worktree**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

- clean worktree
- recent commits show settings backbone, UI split, human-likeness refactor, runtime wiring, and docs
