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

## 3. Tertium 6 (KristopherPrime) — MEDIUM

**What it does:** Fork of Tertium 5 (temporary, pending upstream update). Supports all 6 classes including Arbites and Hive Scum. Adds player character + 5 bots. Named "temporary" by author.

**Source:** [Nexus Mods #725](https://www.nexusmods.com/warhammer40kdarktide/mods/725)

### Key findings

- Fixes the Arbites/Hive Scum crash in Tertium 5's `fetch_all_profiles` path
- Same `attack_meta_data` injection approach as Tertium 5
- No ability-related code — strictly weapons + profiles
- Recommended alternative when Tertium 5 crashes on newer classes

### Relevance to BetterBots

- Drop-in replacement for Tertium 5 when testing Arbites/Hive Scum bots
- No conflicts with BetterBots
- Monitors same mod settings pattern for bot slot → profile mapping

---

## 4. fancy_bots (Aussiemon) — MEDIUM

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

## 5. bot_spawner (Aussiemon) — LOW

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

## 6. SoloPlay — LOW

**What it does:** Enables solo play sessions with configurable mission, difficulty, and modifiers.

**Source:** [Nexus Mods #176](https://www.nexusmods.com/warhammer40kdarktide/mods/176) (installed locally, indirect dependency)

### Key findings

- `boot_singleplayer_session()` → `change_mechanism()` → `trigger_event("all_players_ready")` is the session lifecycle
- Hooks `StateMainMenu.update`, `DifficultyManager`, `PacingManager`, `PickupSystem`
- No bot AI, behavior tree, or ability code whatsoever

### Relevance to BetterBots

Confirms SoloPlay is purely session infrastructure — BetterBots has clean separation.

---

## 7. VT2 Decompiled Source — Bot Ability System — MEDIUM-HIGH

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

---

## 8. Bot Improvements - Combat (Grimalackt, VT2) — HIGH

**What it does:** Comprehensive VT2 bot behavior overhaul. Hooks `BTConditions.can_activate` per-career to replace vanilla ability triggers with threat-value-based heuristics. Also improves melee attack selection, revive behavior, elite pinging, boss engagement, and line-of-fire reactions.

**Source:** [GitHub (Fatshark-hosted)](https://github.com/fatshark-mods/bot_improvements_combat) — original Steam Workshop listing removed for guideline violations, but repo is public.

### Key findings

**Per-career ability trigger overrides (7 of 12 careers):**

The mod hooks `BTConditions.can_activate[career_name]` for each career it modifies. Careers not listed use vanilla logic.

| Career | Trigger condition | Threat threshold | Notes |
|--------|------------------|-----------------|-------|
| `dr_ironbreaker` | Threat sum within 8m | 50 (vanilla: 15) | Low stamina adds +15 pre-threat. Elites/targeting bot get 1.25x multiplier. |
| `es_mercenary` | Threat sum within 7m, scaled by group health | 35 × health_multiplier (min 6) | Group health = weighted average of nearby ally health. Healthier team = higher threshold. |
| `es_huntsman` | Stealth-based, context-aware | N/A | Fires when: prioritized ally needs rescue, low stamina, or targeting threat≥8 enemy. |
| `we_maidenguard` | Dash toward target, navmesh-validated | N/A | Dashes at threat≥8 targets (specials) or when low stamina. Min 9m, max 12m. Validates navmesh ray before committing. Stores aim_position. |
| `we_shade` | Stealth, context-aware | N/A | Same priority logic as Huntsman: rescue, low stamina, or threat≥12. |
| `wh_captain` | Threat sum within 7m | 30 | Similar to Ironbreaker pattern. Low stamina adds +15. |
| `bw_unchained` | Threat sum within 4m + overcharge | 35 (10 if low health) | Always fires at critical overcharge. Only counts enemies targeting bot. |

**Unchanged careers:** `dr_slayer`, `dr_ranger`, `bw_adept`, `wh_zealot`, `es_knight`, `es_questingknight` — use vanilla `can_activate` from `bt_bot_conditions.lua`.

**Revive-with-ability system:**

Injects a `BTBotActivateAbilityAction` node *before* the revive interact node in the BT:
```lua
BotBehaviors.default[3][3] = {
    "BTBotActivateAbilityAction",
    name = "use_ability",
    condition = "can_activate_ability_revive",
    condition_args = { "activate_ability" },
    action_data = BotActions.default.use_ability
}
BotBehaviors.default[3][4] = {
    "BTBotInteractAction",
    name = "do_revive",
    action_data = BotActions.default.revive
}
```

Custom condition `can_activate_ability_revive` fires ability when enemies threaten the bot during revive. Excludes dash/movement abilities (`we_maidenguard`, `dr_slayer`, `es_knight`, `wh_zealot`, `bw_adept`) and ranged abilities (`shoot_ability` category).

**Melee attack selection improvements:**

Hooks `BTBotMeleeAction._choose_attack` with utility-based scoring:
- +1 for single-target attacks when not outnumbered
- +8 for penetrating attacks vs armored targets
- Falls back to `DEFAULT_ATTACK_META_DATA` when weapon lacks it

**Other improvements:**
- Elite pinging: bots ping elites targeting them (LOS check, 2s cooldown, network RPC)
- Boss engagement: only engages bosses when <2 nearby enemies or boss is targeting bot
- Stop chasing: ignores enemies >18.7m away
- Line-of-fire: ignores gunner fire lines when attacker→victim distance >11.8m

### Relevance to BetterBots

**Directly applicable patterns:**

1. **Threat-value thresholds** — The core pattern BetterBots should adopt. Current `enemies_in_proximity() > 0` is too aggressive. Per-class threat thresholds with configurable base values would be a major improvement.

2. **Stamina-as-urgency** — Low stamina reduces threat threshold across all careers. Maps to Darktide's toughness system: bots should be more willing to use abilities when toughness is low.

3. **Revive-with-ability** — BT node injection pattern for using ability to secure a revive. Directly applicable to Darktide bots (e.g., Veteran Stealth before reviving, Zealot charge to reach downed ally).

4. **Career exclusion from revive-ability** — Smart filtering: don't use dash/movement abilities for revive security, only defensive/stealth abilities. Same logic needed for Darktide's charge vs stance abilities.

**Key differences from Darktide context:**
- VT2's `threat_value` field exists on breed data; Darktide may use a different field name — verify against decompiled source
- VT2's `proximite_enemies` is a blackboard field; Darktide equivalent is `perception_component.enemies_in_proximity`
- VT2's stamina system uses fatigue percentage; Darktide uses toughness

---

## 9. Bot Improvements - Impulse Control (Squatting-Bear, VT2) — LOW-MEDIUM

**What it does:** Prevents bots from wasting consumables and abilities at bad times. Suppresses charge/dash abilities when not near enemies, prevents item waste.

**Source:** [GitHub](https://github.com/Squatting-Bear/vermintide-mods) (directory: `bots_impulse_control`), [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=1477499789)

### Relevance to BetterBots

Complementary angle — suppression conditions rather than activation triggers. Relevant for Tier 2 two-step abilities (aim→hold→release) where bad timing wastes the cooldown. Lower priority than Grimalackt's mod but worth referencing if adding "don't fire near ledges" or "don't charge when no enemies ahead" guards.
