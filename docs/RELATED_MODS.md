# Related Mods Analysis

Analysis of Darktide (and VT2) mods relevant to BetterBots, ordered by relevance.

## 1. guarantee_ability_activation (KamiUnitY) — HIGH

**What it does:** Retries combat ability activation when animation locks or state transitions prevent it from firing. Player-only (`viewport_name == "player1"` gated throughout).

**Source:** [Nexus Mods #336](https://www.nexusmods.com/warhammer40kdarktide/mods/336) (installed locally)

### Key findings

**Template categorization tables:**

```lua
-- Dash/charge abilities (two-step aim→release)
IS_DASH_ABILITY = {
    zealot_targeted_dash                 = true,
    zealot_targeted_dash_improved        = true,
    zealot_targeted_dash_improved_double = true,
    ogryn_charge                         = true,
    ogryn_charge_increased_distance      = true,
    adamant_charge                       = true,
}

-- Item-wield abilities (Tier 3 in BetterBots)
IS_WEAPON_ABILITY = {
    zealot_relic               = true,
    psyker_force_field         = true,
    psyker_force_field_dome    = true,
    adamant_area_buff_drone    = true,
    broker_ability_stimm_field = true,
}
```

These lists confirm and extend BetterBots' tier classifications. `adamant_area_buff_drone` and `broker_ability_stimm_field` are Arbites/Hive Scum templates not yet in BetterBots' docs.

**InputService faking (alternative to bot_queue_action_input):**

Hooks `InputService._get` and `InputService._get_simulate` to inject `combat_ability_pressed = true` when a "promise" is active. This is a fundamentally different approach from BetterBots' `action_input_extension:bot_queue_action_input()` path. Could be relevant for Tier 3 item abilities where the normal BT action path doesn't reach.

**Ability failure detection:**

Hooks `ActionCharacterStateChange.finish` to detect when an ability fails to transition character state (e.g., dash didn't enter lunge state). Re-queues the ability on failure. BetterBots could adopt this pattern for bot ability retries.

**ActionBase.start/finish tracking:**

Monitors `ActionBase.start` and `ActionBase.finish` with `ability_type == "combat_ability"` to track hold/release timing and animation cancel reasons (`hold_input_released`, `started_sprint`, `new_interrupting_action`). Relevant for BetterBots' dash hold-duration logic.

### Relevance to BetterBots

- Cross-reference `IS_DASH_ABILITY` / `IS_WEAPON_ABILITY` against class docs
- `ActionCharacterStateChange.finish` hook could detect failed bot activations
- InputService faking is a potential alternative path for Tier 3 abilities
- Player-only gating means zero conflict with BetterBots

---

## 2. Tertium4Or5 (Tertium 5) — MEDIUM

**What it does:** Lets you use your own characters as bots in Solo Play. Injects `attack_meta_data` for ranged weapons so bots can shoot them. Optionally adds a 4th bot.

**Source:** [Nexus Mods #183](https://www.nexusmods.com/warhammer40kdarktide/mods/183) (installed locally, direct dependency)

### Key findings

**`attack_meta_data` injection pattern (lines 7-33):**

```lua
for _, weapon_template in pairs(WeaponTemplates) do
    if table.array_contains(weapon_template.keywords, "ranged") then
        local attack_meta_data = {}
        for action_name, config in pairs(weapon_template.actions) do
            if config.start_input == "shoot" or config.start_input == "shoot_pressed" then
                attack_meta_data.fire_action_name = action_name
            end
            -- ... similar for aim, aim_fire, unaim
        end
        weapon_template.attack_meta_data = attack_meta_data
    end
end
```

This is the exact pattern BetterBots copies for `ability_meta_data`. Iterates templates at load time, scans `actions` for matching `start_input` values, and injects the metadata table the BT expects.

**Profile loading (`fetch_all_profiles` hook, lines 35-84):**

Caches character profiles from the backend with nil guards for missing `archetype` and `personality` data. This is where the crash bug (noted in MEMORY.md) originated — Ogryn/Psyker characters lacking personality metadata.

**Bot slot assignment (`BotSynchronizerHost.add_bot` hook, lines 93-110):**

Maps bot slot number → mod setting dropdown → cached profile. Falls back to default profile if setting is "none" or profile not found.

### Relevance to BetterBots

- Confirms the meta_data injection approach is sound (already adopted)
- Profile caching pattern could be useful if BetterBots needs per-character ability config
- No ability-related code — strictly weapons + profiles

---

## 3. fancy_bots (Aussiemon) — MEDIUM

**What it does:** Replaces bot cosmetics with custom or randomized outfits.

**Source:** [GitHub](https://github.com/Aussiemon/Darktide-Mods), [Nexus Mods #92](https://www.nexusmods.com/warhammer40kdarktide/mods/92)

### Key findings

**Network-level profile manipulation:**

Hooks `BotSynchronizerClient.rpc_add_bot_player` to intercept bot profile JSON at the RPC level. Unpacks profile, clones it, replaces loadout slots, repacks and updates the profile sync client. This is the deepest bot profile manipulation of any mod.

Also hooks `PlayerManager.create_players_from_sync_data` as a second interception point during player sync.

**Loadout slot override (lines 99-117):**

```lua
-- Clones profile, overrides loadout + visual_loadout + loadout_item_ids
for slot_name, item_data in pairs(override_loadout) do
    new_profile.loadout[slot_name] = item_data
    new_profile.visual_loadout[slot_name] = item_data
    loadout_item_ids[slot_name] = item_name .. slot_name
end
```

### Relevance to BetterBots

Critical reference for Tier 3 item-based abilities if they require manipulating `slot_combat_ability` or other equipment slots at the network sync level. Shows the exact APIs: `ProfileUtils.unpack_profile`, `ProfileUtils.pack_profile`, `ProfileUtils.split_for_network`.

---

## 4. bot_spawner (Aussiemon) — LOW

**What it does:** Spawns/despawns bots on demand via keybind or chat command.

**Source:** [GitHub](https://github.com/Aussiemon/Darktide-Mods), [Nexus Mods #27](https://www.nexusmods.com/warhammer40kdarktide/mods/27)

### Key findings

- `BotSpawning.spawn_bot_character(profile_name)` — canonical spawn API
- `BotSpawning.despawn_best_bot()` — canonical despawn API
- `BotCharacterProfiles(item_definitions)` — returns all available bot profiles
- 2-second cooldown between spawns to avoid race conditions

### Relevance to BetterBots

Useful API reference for testing. Not directly needed for ability activation.

---

## 5. SoloPlay — LOW

**What it does:** Enables solo play sessions with configurable mission, difficulty, and modifiers.

**Source:** [Nexus Mods #176](https://www.nexusmods.com/warhammer40kdarktide/mods/176) (installed locally, indirect dependency)

### Key findings

- `boot_singleplayer_session()` → `change_mechanism()` → `trigger_event("all_players_ready")` is the session lifecycle
- Hooks `StateMainMenu.update`, `DifficultyManager`, `PacingManager`, `PickupSystem`
- No bot AI, behavior tree, or ability code whatsoever

### Relevance to BetterBots

Confirms SoloPlay is purely session infrastructure — BetterBots has clean separation.

---

## 6. VT2 Decompiled Source — Bot Ability System — MEDIUM-HIGH

**What it is:** Vermintide 2's decompiled bot behavior tree and ability activation code. VT2 shares the same BT architecture as Darktide. Bots already use career skills in VT2 — analyzing how reveals patterns directly applicable to BetterBots.

**Source:** [GitHub](https://github.com/Aussiemon/Vermintide-2-Source-Code)

### Key findings

**Behavior tree structure (`bt_bot.lua`):**

VT2's BT has two ability nodes at different priority levels:
1. `activate_normal_ability` — uses `BTBotActivateAbilityAction` with `can_activate_ability` condition, switches to melee/career_skill_weapon first
2. `activate_ranged_shot_ability` — uses `BTBotShootAction` for ranged career skills (Bounty Hunter, Waywatcher, Scholar)

The BT explicitly handles `slot_career_skill_weapon` wielding before ability activation — the same pattern BetterBots needs for Tier 3 item abilities.

**Per-career activation heuristics (`bt_bot_conditions.lua`):**

VT2 has **individual `can_activate` functions per career** with sophisticated threat assessment:

- `dr_ironbreaker`: Threat value sum of nearby enemies, activates above threshold 15. Enemies targeting the bot get 1.25x threat multiplier.
- `dr_slayer`: Leap-based — checks ground state, finds high-threat targets (threat_value >= 8) at 7-10m range, validates navmesh reachability, stores aim position.
- `dr_ranger`: Like ironbreaker but factors in health (lower health = lower threshold), ally rescue priority.
- `es_mercenary`: Counts nearby allies, adjusts threat threshold by team proximity percentage, factors in health/wounded state.
- `es_knight`: Charge toward high-threat targets, with aim position and navmesh validation (similar to Slayer).
- `es_huntsman`: Stealth ability, activated on health-scaled threat.
- `we_maidenguard`: Dash ability, stores aim position toward target.
- `we_shade`: Stealth with target proximity check.
- `wh_captain`: AoE ability with ally proximity bonus.
- `wh_zealot`: Low-health threshold trigger.
- `bw_adept`/`bw_unchained`: Overcharge-based conditions.

**Career categories (`ability_check_categories`):**
```lua
activate_ability = {  -- Normal ability path (melee weapon → activate)
    bw_adept, bw_unchained, dr_ironbreaker, dr_ranger, dr_slayer,
    es_huntsman, es_knight, es_mercenary, we_maidenguard, we_shade,
    wh_captain, wh_zealot
},
shoot_ability = {     -- Ranged ability path (aim → shoot)
    bw_scholar, we_waywatcher, wh_bountyhunter
}
```

This two-path split is analogous to Darktide's template-path vs item-path distinction.

**Activate ability action (`bt_bot_activate_ability_action.lua`):**

The VT2 action node has per-career `action_data` with:
- `activation.action` — "instant" or "aim_at_target" (with aim dot threshold 0.995)
- `activation.min_hold_time` — minimum hold duration before release
- `activation.max_distance_sq` — max range for aimed abilities
- `activation.dynamic_target_unit` — re-aim during ability if target moves
- `wait_action.input` — post-activation input (e.g., attack during ability)
- `end_condition` — buff-based, slot-based, or destination-based completion checks
- `is_weapon_ability` — detected by checking `slot_career_skill_weapon` existence

**Bot input system (`player_bot_input.lua`):**

VT2's bot input is simpler than Darktide's:
- `activate_ability()` → sets `_activate_ability = true` → translated to `action_career` + `action_career_hold`
- `release_ability_hold()` → sets `_activate_ability_held = true` → triggers `action_career_release`
- `cancel_ability()` → sends `action_two` to cancel

No `bot_queue_action_input` — VT2 uses direct flag-based input. Darktide's queued action input system is more complex.

### Relevance to BetterBots

**High-value patterns to adopt:**

1. **Per-class activation heuristics** — VT2's threat-based conditions (enemy proximity, threat value, health state, ally rescue priority) are directly applicable. BetterBots currently uses a simple `enemies_in_proximity() > 0` gate. Adopting threat-value thresholds per class would be a significant improvement.

2. **Aimed ability handling** — VT2's `aim_at_target` action with dot-product aiming, navmesh validation, and dynamic target tracking solves the same problem as Darktide's charge/dash abilities. The 0.995 aim dot threshold and repath interval (0.5s) are proven values.

3. **End condition patterns** — Buff-based, slot-based, and destination-based completion checks are more robust than time-based approaches. Could improve BetterBots' hold-duration logic.

4. **Two-path ability categories** — The `activate_ability` vs `shoot_ability` split maps to template-path vs item-path. Worth formalizing this in BetterBots.

**Key differences from Darktide:**
- VT2 uses direct flag-based bot input; Darktide uses queued action input
- VT2 has no `ability_meta_data` concept — per-career action_data is defined in the BT
- VT2's career skills are simpler (mostly instant or aimed); Darktide has more complex multi-step abilities
