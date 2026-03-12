# Architecture

## Scope

This mod targets bot ability activation in three paths:

1. Template-based abilities (`combat_ability_action.template_name ~= "none"`).
2. Item-based abilities (`combat_ability_action.template_name == "none"` with an equipped combat-ability item).
3. Grenade/blitz abilities (equipped grenade-ability items driven through explicit input sequences).

## Vanilla bot ability flow

1. `bot_behavior_tree.lua` runs `activate_combat_ability`.
2. `bt_bot_conditions.can_activate_ability` hard-gates most templates.
3. `BtBotActivateAbilityAction` queues bot input for ability templates only.
4. If `combat_ability_action.template_name == "none"`, vanilla exits early.

## Mod behavior

`scripts/mods/BetterBots/BetterBots.lua` does twenty-four things:

1. Injects missing `ability_meta_data` for Tier 2 templates (via `meta_data.lua`).
2. Overrides selected template metadata (`veteran_*`) to use bot-valid inputs.
3. Replaces `can_activate_ability` on both `bt_bot_conditions` and `bt_conditions` so templates with valid metadata can pass (via `condition_patch.lua`).
4. Adds a fallback in `BotBehaviorExtension:update` (via `ability_queue.lua` for Tier 1/2; `item_fallback.lua` for Tier 3):
   - template fallback: queue ability action input directly on `combat_ability_action`
   - item fallback: queue explicit `weapon_action` sequence (`combat_ability` wield + cast follow-ups + unwind)
   - item sequence selection is profile-driven (shared profile catalog + per-ability priority order)
5. Adds state-transition recovery:
   - hook `ActionCharacterStateChange.finish`
   - if bot combat ability did not reach wanted character state, schedule a fast fallback retry
6. Adds queue-level weapon-switch protection for item abilities (via `weapon_action.lua`):
   - hook `PlayerUnitActionInputExtension.bot_queue_action_input`
   - block bot `weapon_action:wield` while protected item abilities are active/in-sequence
7. Adds `wield_slot` redirect for item abilities (via `weapon_action.lua`):
   - redirects non-combat-ability wield calls back to `slot_combat_ability` during item sequences (prevents cancel loop)
   - exempts pending/active interactions so relic slot locking cannot override `slot_unarmed` on interaction entry
8. Guards against overheat crash (via `weapon_action.lua`):
   - prevents crash when bots wield plasma guns with nested threshold config
9. Guards against perils achievement crash (via `weapon_action.lua`):
   - skips `WeaponSystem.queue_perils_of_the_warp_elite_kills_achievement` when `account_id` is nil (bot crash guard)
10. Per-template heuristics (via `heuristics.lua`):
    - `evaluate_heuristic(template_name, context, opts)` for template-path abilities
    - `evaluate_item_heuristic(ability_name, context, opts)` for item-path abilities
    - `standard/testing` behavior profile: testing mode applies a narrow leniency override after heuristic evaluation across template, item, and grenade/blitz heuristics so bots produce validation events faster without bypassing hard safety/resource guards
    - `enemy_breed` export for breed classification
11. Settings surface (`settings.lua`):
    - resolves DMF settings for behavior profile and coarse feature gates
    - gates Tier 1, Tier 2, Tier 3, and grenade/blitz activations in central paths instead of scattering checks across individual heuristics
12. Structured JSONL event logging (`event_log.lua`):
    - opt-in via mod setting (`enable_event_log`)
    - emits decision, queued, consumed, blocked, item_stage, snapshot events to `./dump/betterbots_events_<timestamp>.jsonl`
    - events carry `attempt_id` for cross-event correlation (decision → queued → consumed)
    - buffered with periodic flush (15s or 500 events); survives hot-reload via load-time recovery
13. Revive/interaction protection (#20):
    - blocks ability activation when `blackboard.behavior.current_interaction_unit ~= nil`
    - applied in both BT condition hook and fallback path (after in-progress state machines)
14. Ability suppression / impulse control (#11):
    - `_is_suppressed(unit)` checks dodging, falling, lunging, jumping, ladder states, moving platform
    - guards placed after "keep running" fast paths so in-progress abilities (charge mid-lunge) complete normally
15. Warp weapon peril block (#27, via `weapon_action.lua`):
    - blocks `weapon_action` inputs (except `wield`) for warp weapons at ≥97% peril
    - prevents Scrier's Gaze overcharge explosions by stopping warp weapon attacks at critical peril
    - bots cannot manually vent — no BT node for warp charge venting (`should_reload` checks ammo, not peril); bots rely on passive auto-vent (3s delay, tiered decay rates)
16. Poxburster targeting (#34, via `poxburster.lua`):
    - patches `chaos_poxwalker_bomber` breed data to remove `not_bot_target` flag, re-enabling targeting at range
    - hook `BotPerceptionExtension._update_target_enemy` (post-process): suppresses poxburster as target/opportunity/urgent/priority target when within 5m of the bot or within 8m of any human player
17. Healing deferral (#39, via `healing_deferral.lua`):
    - hook `BotBehaviorExtension._update_health_stations` (post-process): clears `needs_health` when any human player is below the configured threshold (default 90%) and the bot is not in the configured emergency override state (default <25%)
    - hook `BotGroup._update_pickups_and_deployables_near_player` (post-process): clears `health_deployable` assignments under the same defer-to-human rule when med-crate deferral is enabled
    - exposes DMF settings for mode (`off`, `health stations only`, `health stations + med-crates`), human-priority threshold, and emergency override; strict mode can disable the emergency override entirely
    - intentionally does not hook pocketable health pickups: the decompiled bot mule path is dead for medkits/wound cures, so BetterBots does not claim unsupported behavior
18. ADS fix for T5/T6 bots (#35):
    - hook `BotBehaviorExtension._init_blackboard_components`: injects default `bot_gestalts` (`ranged = "killshot"`, `melee = "linesman"`) when profile omits them
    - without this, engine falls back to `"none"` gestalt which disables aim-down-sights
19. Bot sprinting (#36, via `sprint.lua`):
    - hook `BotUnitInput._update_movement`: sets `hold_to_sprint`/`sprinting` inputs after vanilla movement
    - sprint conditions: catch-up (>12m from follow target), ally rescue, traversal (no enemies)
    - hard suppression near daemonhosts (<20m) to avoid triggering anger via `sprint_flat_bonus`
20. VFX/SFX bleed fix (#42, via `vfx_suppression.lua`):
    - hook `PlayerUnitAbilityExtension.init`: sets `is_local_unit = false` in the equipped ability effect scripts context for bot units
    - hook `PlayerUnitVisualLoadoutExtension.init`: sets `is_local_unit = false` in the wieldable slot scripts context for bot units
    - hook `CharacterStateMachineExtension.init`: sets `_is_local_unit = false` for bot units
    - prevents first-person VFX/SFX (lunge screen distortion, lunge sounds, shout aim indicator, dash crosshair, item placement previews, Wwise global state) from bleeding into human player's view in Solo Play
21. Melee attack metadata injection (#23, via `melee_meta_data.lua`):
    - hook `WeaponTemplates` require: auto-derives and injects `attack_meta_data` for all melee weapons
    - traverses action graph: `start_attack` → `allowed_chain_actions` → light/heavy action → `damage_profile`
    - classifies `arc` from `cleave_distribution` (0/1/2) and `penetrating` from `armor_damage_modifier[armored]` (threshold ≥ 0.5)
    - enables existing `_choose_attack` scoring: +8 penetrating vs armored, +4 sweep vs hordes
22. Ranged weapon `attack_meta_data` injection (#31, via `ranged_meta_data.lua`):
    - auto-derives `attack_meta_data` for player ranged weapons where `bt_bot_shoot_action`'s hardcoded fallback chain (`action_shoot` → `start_input` → `"shoot"`) produces invalid input names
    - scans `action_inputs` for `action_one_pressed` (fire), `action_two_hold` (aim), `hold_input` combos (aim-fire)
    - cross-references with `actions` via `start_input` to find correct action names
    - only injects when vanilla fallback would fail; standard weapons (lasgun, autogun, bolter, flamer) are skipped
    - fixes plasma gun (`shoot_charge`), force staff (`shoot_pressed` → `rapid_left`), and other exotic fire paths
23. Melee target selection distance penalty (#19, via `target_selection.lua`):
    - hook `BotTargetSelection.slot_weight` during melee scoring
    - penalizes melee score for distant special enemies (>18m) when bot has sufficient ranged ammo (>50%) so ranged engagement wins instead of a long chase (#19)
    - hook `BotTargetSelection.monster_weight` to restore vanilla monster weight when the boss/miniboss blackboard says it is explicitly aggroed on this bot, even if nearby trash would normally zero the weight (#18)
24. Runtime perf measurement (`perf.lua`):
    - central recorder keyed by the `enable_perf_timing` mod setting
    - instruments BetterBots-owned hot hooks and the main bot update slice with per-tag timing buckets
    - `/bb_perf` prints and resets the current recording window instead of toggling recording state

## Why item fallback is needed

Item-based abilities rely heavily on weapon `conditional_state_to_action_input` chains (for example wield -> channel/place).

In `ActionInputParser.action_transitioned_with_automatic_input`, bots early-return, so these automatic chains do not advance for bot-controlled units. Humans get those automatic transitions; bots do not.

Result: item abilities need explicit queued inputs from the mod.

## Ability tiers in this repo

| Tier | Current handling | Notes |
|---|---|---|
| 1 | Whitelist bypass | Templates define usable `ability_meta_data` |
| 2 | Runtime metadata injection | Includes template-specific `wait_action`/`end_condition` where needed |
| 3a | Item-based combat fallback (experimental) | Driven via `weapon_action` sequence probing by action-input names |
| 3b | Grenade/blitz fallback (experimental) | Driven via `grenade_fallback.lua` profiles and explicit grenade-ability input sequences |

## Class ability references

Detailed per-class ability breakdowns (internal IDs, input patterns, cooldowns, talent modifiers, bot usage notes) are in:
- `classes/veteran.md`, `classes/zealot.md`, `classes/psyker.md`, `classes/ogryn.md`, `classes/arbites.md`, `classes/hive-scum.md`

Each doc classifies abilities into the tiers above and includes implementation guidance for bot activation.

## Structured event logging

`event_log.lua` provides machine-readable JSONL output parallel to the text debug log. It is a standalone module with no engine dependencies beyond `Mods.lua.io`, `Mods.lua.os`, and `cjson`.

Key design:
- **Buffer + flush**: Events accumulate in a Lua table, flushed to disk every 15s or 500 events.
- **Wall-clock filenames**: Uses `os.time()` (not simulation `fixed_t`) for unique filenames across missions.
- **attempt_id correlation**: Monotonic counter links decision → queued → consumed chains across both BT and fallback activation paths.
- **Hot-reload recovery**: On `Ctrl+Shift+R`, module state resets but DMF doesn't re-fire `on_game_state_changed`. Load-time code detects alive bots and re-enables logging.
- **False-decision compression**: Tracks skip counts per (bot, ability) to weight false decisions without flooding the file.

Analysis via `bb-log events [summary|rules|holds|items|trace|raw]`. See `docs/dev/logging.md` for event schema.

## Performance analysis

### Current overhead: negligible

The mod piggybacks on data the engine already computes. There are no new per-frame scans, raycasts, or pathfinding queries.

`/bb_perf` now reports the sum of instrumented BetterBots hook time over the current recording window, normalized as `µs/bot/frame` using bot update samples. Recording is controlled by the `enable_perf_timing` setting; the chat command only prints and resets accumulated counters.

**Hot paths (per fixed frame, per bot — ~90 calls/sec total with 3 bots):**

| Path | Cost | Notes |
|---|---|---|
| `build_context()` | ~1 iteration over proximity list + coherency allies | Cached per unit per `fixed_t` — runs once per bot per frame regardless of how many call sites invoke it |
| Heuristic evaluation | ~20 arithmetic comparisons | Pure comparisons on pre-built context table, no allocations, no engine calls |
| `_can_activate_ability` (BT condition) | 1 `require` (cached) + `build_context` + heuristic | Only fires when BT priority selector reaches the ability node — usually short-circuited by higher-priority nodes |
| `_fallback_try_queue_combat_ability` (update hook) | Same as above + state machine checks | Most frames exit early (cooldown not ready, retry timer, or state guard) |
| Event logging (`emit`) | 1 table append per event | Buffered; flush to disk every 15s or 500 events. Off by default. |
| Debug logging (`_debug_log`) | 1 string concat for key + 1 table lookup | Message body only built when debug enabled, but key argument is always evaluated |

**Instrumented perf buckets:**
- `ability_queue`, `grenade_fallback`, `ping_system`, `event_log_flush`, `event_log_snapshot`, `event_log_session_start`
- `condition_patch.can_activate_ability`
- `sprint.update_movement`
- `target_selection.slot_weight`, `target_selection.monster_weight`
- `weapon_action.may_fire`, `weapon_action.bot_queue_action_input`, `weapon_action.wield_slot`
- `healing_deferral.health_stations`, `healing_deferral.health_deployables`
- `poxburster.update_target_enemy`

This is intentionally "sum of instrumented BetterBots hook time", not total process wall time for the whole mod or game frame. Any BetterBots work outside the instrumented hook set is excluded until explicitly wrapped.

**What the mod does NOT do per frame:**
- No new perception scans — reads `perception_extension:enemies_in_proximity()` which the engine already computed
- No raycasts or line-of-sight checks
- No pathfinding or navmesh queries
- No table allocations in the heuristic path (context is reused via cache)

### Known minor waste

`_debug_log` key strings (e.g. `"none:" .. ability_component_name`) are concatenated even when debug is disabled, because Lua evaluates all function arguments before the call. This produces ~90 throwaway strings/sec. Negligible but could be gated behind `if _debug_enabled() then` if profiling ever shows string GC pressure.

### Growth vectors to watch

When implementing these issues, verify the change doesn't add per-frame engine calls:

| Issue | Risk | What to watch |
|---|---|---|
| #4 Grenade/blitz support | **Low** | Same architecture — one more heuristic per bot. Context cache shared. |
| #13 Navmesh validation for charges | **Medium-High** | Navmesh queries (`GwNavQueries`) are expensive. Must not run every frame — gate behind heuristic returning true, then validate once before queueing. Cache negative results with a cooldown. |
| #15 Suppress dodge during ability hold | **Low** | One additional condition check in an existing hook. No new per-frame hook needed. |
| #22 Utility-based ability scoring | **Low-Medium** | If it replaces if/else heuristics with a scoring pass over all abilities, context build is still cached. Scoring itself would be cheap. Risk is if it queries additional engine state per ability. |
| #23 Smart melee attack selection | **Medium** | Could require reading weapon template data per frame. Keep reads cached and avoid per-frame `rawget` chains on large template tables. |
| New per-frame hooks (general) | **Medium** | DMF hook dispatch has non-trivial cost (closure call + argument forwarding + chain-call). Currently 5 hooks on per-frame paths — acceptable. Consolidate logic into fewer hook sites rather than adding one hook per feature if count grows past ~10. |

### Rules for new per-frame code

1. **No new engine queries without caching.** If you need navmesh, raycast, or LoS data, cache results per unit per frame (same pattern as `build_context`).
2. **Gate expensive checks behind cheap ones.** A navmesh query should only run after the heuristic already returned true and all other cheap conditions passed.
3. **Prefer extending `build_context` over adding parallel data-gathering.** New signals (e.g. character state, weapon slot) should be fields on the existing context table, benefiting from the frame cache.
4. **Count your hooks.** Each `mod:hook` / `mod:hook_safe` on a per-frame system adds dispatch overhead. Before adding a new one, check if the logic can live inside an existing hook.
5. **Event logging volume.** If a new event type fires every frame per bot (not just on state transitions), consider sampling or skip-counting like `emit_decision` does for false results.

## Key constraints

- Template path still depends on valid `ability_meta_data.activation.action_input`.
- Some vanilla templates ship metadata that does not match their action-input graph (for example Veteran `stance_pressed` vs actual `combat_ability_pressed`/`combat_ability_released`), so metadata overrides are required.
- Item path is profile-based: it inspects weapon-template `action_inputs`, picks a compatible sequence profile, and runs one shared stage machine.
- Unsupported item templates are skipped with explicit debug logs.

## Item fallback lessons (generalized)

The same reliability rules apply across relic/force-field/drone-style abilities:

1. **Lock by stage, not by one-shot queue**
   - Separate `waiting_wield`, `waiting_start`, `waiting_followup`, `waiting_unwield`, `waiting_charge_confirmation`.
   - Validate slot/template at each stage before queueing input.

2. **Treat parser drift as first-class**
   - Before each queued input, verify the currently active `weapon_action` template still supports that input.
   - If not, abort and retry instead of sending invalid parser input.

3. **Use charge-consume as success signal**
   - Track `use_ability_charge(combat_ability)` for bots per unit.
   - Confirm sequence success via charge consumption, not only via queued inputs.

4. **Support multiple valid input profiles**
   - Some weapons expose both regular and instant cast paths.
   - Keep a prioritized profile list per ability and rotate profile when a full sequence ends without charge consumption.

5. **Prevent BT switch-away during critical item stages**
   - Some abilities are broken by immediate re-wield decisions from other bot nodes.
   - Queue-level filtering of bot `wield` requests is a reliable guardrail for channel/deploy flows.
