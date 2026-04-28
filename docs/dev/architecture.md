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

`scripts/mods/BetterBots/BetterBots.lua` coordinates these module-level behaviors:

1. Injects missing `ability_meta_data` for Tier 2 templates (via `meta_data.lua`).
2. Overrides selected template metadata (`veteran_*`) to use bot-valid inputs.
3. Replaces `can_activate_ability` on both `bt_bot_conditions` and `bt_conditions` so templates with valid metadata can pass (via `condition_patch.lua`).
4. Adds a fallback in `BotBehaviorExtension:update` (via `update_dispatcher.lua` coordinating `ability_queue.lua` for Tier 1/2 and `grenade_fallback.lua` for grenade/blitz paths):
   - per-frame order is stable: perf sync → session-start event → ability queue → grenade fallback → ping/companion updates → event-log flush → snapshot emit
   - template fallback: queue ability action input directly on `combat_ability_action`
   - item fallback: queue explicit `weapon_action` sequence (`combat_ability` wield + cast follow-ups + unwind)
   - item sequence selection is profile-driven (shared profile catalog + per-ability priority order)
5. Tracks charge consumption + state-transition recovery:
   - `charge_tracker.lua` wraps `PlayerUnitAbilityExtension.use_ability_charge` for bot-only consumed events, semantic-key routing, team-cooldown recording, and grenade/item fallback completion
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
10. Per-template heuristics (via thin `heuristics.lua` dispatcher + split heuristic modules):
    - `evaluate_heuristic(template_name, context, opts)` for template-path abilities
    - `evaluate_item_heuristic(ability_name, context, opts)` for item-path abilities
    - `evaluate_grenade_heuristic(grenade_template_name, context, opts)` for grenade/blitz abilities
    - `heuristics_context.lua` owns `build_context()` and shared target/breed/resource helper functions
    - `heuristics_veteran.lua`, `heuristics_zealot.lua`, `heuristics_psyker.lua`, `heuristics_ogryn.lua`, `heuristics_arbites.lua`, `heuristics_hive_scum.lua`, and `heuristics_grenade.lua` own the per-career and grenade/blitz trigger rules
    - `combat_ability_identity.lua` separates engine template identity (`ability_component.template_name`) from semantic ability identity (`ability_name` / `semantic_key`) so shared templates such as Veteran shout vs stance can route to different heuristics/settings without changing template-based engine lookups
    - `testing/aggressive/balanced/conservative` behavior presets: per-template threshold tables control when abilities fire (aggressive = early, conservative = emergency-only). Testing mode applies a narrow leniency override after heuristic evaluation so bots produce validation events faster without bypassing hard safety/resource guards
    - `enemy_breed` export for breed classification
11. Settings surface (`settings.lua`):
    - resolves DMF settings for behavior profile (testing/aggressive/balanced/conservative) and category/feature gates
    - **Category gates** replace the old tier-level gates: abilities are gated by category (stances, charges, shouts, stealth, deployables, grenades) via `is_combat_template_enabled` / `is_item_ability_enabled` / `is_grenade_enabled`
    - **Semantic combat-ability gate**: shared templates resolve through `combat_ability_identity.lua`; Veteran shout routes to `enable_shouts`, Veteran stance/base/unknown falls back to `enable_stances` for settings compatibility, while engine metadata/input validation remains keyed by template name
    - **Feature gates**: optional bot behaviors (sprint, pinging, special_penalty, poxburster, melee_improvements, ranged_improvements, team_cooldown) gated via `is_feature_enabled(feature_name)` → `FEATURE_GATES` map → `mod:get(setting_id)`. `melee_improvements` covers both armor/horde attack selection and supported melee weapon specials; `ranged_improvements` covers ADS/charged-fire improvements plus supported shotgun special-shell preloads, rippergun bayonet rewrites, and direct ranged-bash/pistol-whip rewrites. Disabling all gates + all categories reverts to vanilla bot behavior.
    - **BT enter gate**: the generated BT selector (`bt_bot_selector_node.lua`) inlines condition logic, bypassing the `condition_patch` gate. `BtBotActivateAbilityAction.enter` hook provides a last-resort gate for both combat and grenade abilities.
    - **DI pattern**: `init(deps)` receives `{ mod = mod }` from `BetterBots.lua`; all `mod:get()` calls are deferred to runtime so leaf modules can be unit-tested without a live DMF instance
    - Settings are reactive without restart: all gates call `mod:get()` on each evaluation, reading the current DMF setting value directly rather than caching
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
    - blocks `weapon_action` inputs (except `wield`) for warp weapons at the configurable `warp_weapon_peril_threshold` slider (default ≥99% peril)
    - prevents Scrier's Gaze overcharge explosions by stopping warp weapon attacks at critical peril
    - the same shared threshold is also used by Assail crowd-burst followups in `grenade_fallback.lua`
    - bots cannot manually vent — no BT node for warp charge venting (`should_reload` checks ammo, not peril); bots rely on passive auto-vent (3s delay, tiered decay rates)
16. Poxburster targeting (#34, via `poxburster.lua`):
    - patches `chaos_poxwalker_bomber` breed data to remove `not_bot_target` flag, re-enabling targeting at range
    - hook `BotPerceptionExtension._update_target_enemy` (post-process): suppresses poxburster as target/opportunity/urgent/priority target when within 5m of the bot or within 8m of any human player
17. Elite/special pinging (#16, via `ping_system.lua`):
    - hooks bot perception slots and emits contextual smart tags only for elites/specials/monsters with LOS
    - retains anti-spam behavior (`hold_last_tag`, failure backoff, companion-target carve-outs)
    - Focus Target veterans may override an existing enemy tag once so `enemy_over_here_veteran` can still proc on an already-tagged priority target; non-Focus-Target bots keep the normal `already_tagged` suppression
18. Animation variable guard (#50, via `animation_guard.lua`):
    - hook `AuthoritativePlayerUnitAnimationExtension.anim_event_with_variable_float`
    - for bot units only, degrades invalid animation variable IDs (`nil` / `4294967295`) or lookup failures to a plain `anim_event`, matching vanilla's multi-variable fallback instead of crashing the animation path
19. Smart-target seeding (#61/#62, via `smart_targeting.lua`):
    - hook `SmartTargetingActionModule.fixed_update`
    - swaps bot perception's selected target into `smart_targeting_extension:targeting_data().unit` only for the duration of vanilla `fixed_update()`
    - preserves vanilla sticky-targeting, soft-sticky fallback, and precision-range checks while giving bot-only precision blitzes a real enemy target to aim at
20. Grenade ballistic aim correction (#93, via `grenade_fallback.lua` + `grenade_aim.lua`):
    - replaces flat `set_aim_position` only for supported gravity-affected projectile families in the grenade fallback path
    - resolves projectile locomotion data from the equipped grenade weapon template at runtime, then mirrors vanilla `Trajectory.angle_to_hit_moving_target(...)` solving with target-velocity lead
    - uses `set_aim_rotation` for standard grenades, handleless grenades, Ogryn grenade throws, and zealot throwing knives; preserves flat fallback for near-flat, true-flight, and non-ballistic families
21. Healing deferral (#39, via `healing_deferral.lua`):
    - hook `BotBehaviorExtension._update_health_stations` (post-process): clears `needs_health` when any human player is below the configured threshold (default 90%) and the bot is not in the configured emergency override state (default <25%)
    - when every eligible human is above reserve, the same hook now promotes health-station demand for any damaged non-Martyrdom bot and forces queue number `1`, overriding vanilla's heavier-damage threshold so slightly-damaged or corruption-only bots stop leaving spare medicae charges stranded
    - hook `BotGroup._update_pickups_and_deployables_near_player` (post-process): clears `health_deployable` assignments under the same defer-to-human rule when med-crate deferral is enabled; when humans are above reserve, vanilla's existing `needs_non_permanent_health` flag already gives crates an "any healable damage" onset
    - Martyrdom zealots are an explicit exception to the generic emergency override: when healing deferral is enabled, live station and med-crate seams stay blocked so the bot preserves its low-health keystone value
    - exposes DMF settings for mode (`off`, `health stations only`, `health stations + med-crates`), human-priority threshold, and emergency override; strict mode can disable the emergency override entirely
    - still does not claim generic wound-cure / give-to-ally pocketable behavior; Sprint 4 only ships medicae discipline here, with carried stims/crates handled separately in `pocketable_pickup.lua`
22. Ammo, grenade, and mule pickup policy (#72 / #89 / #32 / #24 / #88, via `ammo_policy.lua` + `mule_pickup.lua` + `pocketable_pickup.lua`):
    - hook `BotBehaviorExtension._update_ammo` (post-process): once every eligible human ammo user is above reserve, any missing ammo amount (`ammo_percentage < 1`) is enough to keep `needs_ammo` true; the configured opportunistic ranged threshold only survives as the desperation fallback while humans still need the resource
    - opportunistic ranged fire threshold (`condition_patch.lua`) and the desperation branch in ammo pickup onset share one DMF numeric setting
    - ammo pickup is blocked unless every eligible human ammo user is above the configured reserve threshold
    - `small_grenade` pickup support piggybacks the same vanilla `pickup_component.ammo_pickup` slot because vanilla never routes `group = "ability"` grenade refills into bot pickup awareness
    - grenade refills bind for charge-based grenade users whenever every eligible human is above the configured reserve threshold; cooldown-only blitz users are ignored
    - grenade refill deferral is human-first with no bot desperation override; when grenade is deferred, existing ammo pickup decisions remain intact
    - explicit ammo pickup orders are preserved
    - `mule_pickup.lua` activates vanilla side-mission book carry by mutating pickup template metadata in place: mirror `inventory_slot_name -> slot_name`, set `bots_mule_pickup = true` for tome/scripture and grimoire each gated by its own BetterBots toggle (tome defaults on, grimoire defaults off)
    - vanilla `BotGroup.init` never builds those slot buckets correctly because it iterates `pairs(Pickups)` over the top-level registry wrapper instead of `Pickups.by_name`; BetterBots backfills missing `_available_mule_pickups[slot_name]` tables during both `BotGroup.init` and live sync so the later pickup broadphase write path cannot nil-index `slot_pocketable`
    - stale-pickup cleanup (dead-unit references) runs unconditionally; tome-blocking and grimoire-blocking only run when their respective toggle is off, so opting in to either pickup type no longer strands dead references in `_available_mule_pickups` / `pickup_component.mule_pickup` / behavior-component interaction targets
    - hook `BotBehaviorExtension._refresh_destination` (post-process): sanitizes live mule state (stale drops for any type; blocked references for whichever type is currently disabled)
    - hook `BotGroup.init`, `BotGroup._update_mule_pickups`, and setting-change sync: backfills missing mule slot caches on construction, then prunes cached reservations and explicit `slot_pocketable` pickup orders immediately when a pickup type is disabled, so bots can fall through to the other type without waiting for the vanilla cache to expire
    - post-processes vanilla `_update_mule_pickups()` assignment to ignore the stock "suppress mule pickup while any human is within ~20m of the book" rule; BetterBots now claims the nearest eligible unassigned book for a bot with a free mule slot and an in-leash follow position, then marks destination refresh so ordinary book pickup can happen in the common nearby-player case
    - `pocketable_pickup.lua` extends the same carry path to supported pocketables (`ammo_cache_pocketable`, `medical_crate_pocketable`, the three combat stims, and `syringe_corruption_pocketable`) by patching `bots_mule_pickup`, mirroring `inventory_slot_name -> slot_name`, and letting vanilla `PocketableInteraction.stop` perform the actual slot insert
    - proactive pocketable assignment is human-first: BetterBots refuses to claim a supported pocketable while any human still has the matching slot open, unless the pickup came from an explicit bot order
    - hook `BotOrder.pickup`: rejects pickup orders for whichever book type is currently disabled, rejects unsupported pocketables entirely, and leaves supported pocketable orders intact when the feature is enabled
    - `update_dispatcher.lua` runs the carried pocketable state machine once the bot already owns the item: combat stims self-use on high-threat entry, the corruption-heal syringe self-uses conservatively when the bot itself needs healing/corruption relief and combat is calm, and ammo/medical crates auto-deploy only when at least two allies are in coherency, no enemy is currently engaged, and the team actually needs the resource
    - `smart_tag_orders.lua` hooks `SmartTagSystem.set_contextual_unit_tag` for first-time item pings and `SmartTagSystem.trigger_tag_interaction` for already-tagged items, then routes explicit item-tag interactions back into the existing `BotOrder.pickup(...)` path instead of inventing a second order system
    - smart-tag routing stays intentionally narrow for the MVP: ammo, world grenade refills, tomes/grimoires, and supported pocketables only; health stations and location-style interactions are ignored
    - the routing layer reuses `MulePickup.should_block_pickup_order(...)` so existing BetterBots policy gates still apply (unsupported pocketables, disabled books, human-slot-open pocketables), selects the nearest eligible live bot on the interactor's side, and is guarded by the `enable_smart_tag_orders` setting plus a class-table hot-reload sentinel on `SmartTagSystem`
22b. Communication-wheel response (#56, via `com_wheel_response.lua` + `settings.lua` + resource policy hooks):
    - hooks `Vo.on_demand_vo_event` through a class-table hot-reload sentinel on `scripts/utilities/vo`, so vanilla and ForTheEmperor wheel events share one cheap Solo Play-safe detection point
    - MVP scope is intentionally narrow: `com_cheer` temporarily overrides the resolved behavior preset to `aggressive`, while `com_need_ammo` and `com_need_health` set short-lived human request flags that `ammo_policy.lua` and `healing_deferral.lua` treat as stronger-than-reserve deferral signals
    - the bridge is user-toggleable (`enable_com_wheel_responses`) and resets its transient request state on `GameplayStateRun` entry so one mission's wheel traffic cannot bleed into the next
    - no fake location/pathing orders ship here; `Need Help`, `location_this_way`, and similar world-marker flows remain out of scope until BetterBots has a real movement-directive layer
23. ADS fix for T5/T6 bots (#35, via `gestalt_injector.lua`):
    - hook `BotBehaviorExtension._init_blackboard_components`: injects default `bot_gestalts` (`ranged = "killshot"`, `melee = "linesman"`) when profile omits them
    - without this, engine falls back to `"none"` gestalt which disables aim-down-sights
24. Bot sprinting (#36, via `sprint.lua`):
    - hook `BotUnitInput._update_movement`: sets `hold_to_sprint`/`sprinting` inputs after vanilla movement
    - sprint conditions: catch-up (>12m from follow target), ally rescue, traversal (no enemies)
    - hard suppression near daemonhosts (<20m) to avoid triggering anger via `sprint_flat_bonus`
25. VFX/SFX bleed fix (#42, via `vfx_suppression.lua`):
    - hook `PlayerUnitAbilityExtension.init`: sets `is_local_unit = false` in the equipped ability effect scripts context for bot units
    - hook `PlayerUnitVisualLoadoutExtension.init`: sets `is_local_unit = false` in the wieldable slot scripts context for bot units
    - hook `CharacterStateMachineExtension.init`: sets `_is_local_unit = false` for bot units
    - prevents first-person VFX/SFX (lunge screen distortion, lunge sounds, shout aim indicator, dash crosshair, item placement previews, Wwise global state) from bleeding into human player's view in Solo Play
26. Melee attack selection bias fix (#52, via `melee_attack_choice.lua`):
    - hook `BtBotMeleeAction.enter` and `BtBotMeleeAction._choose_attack`; export the defend-suppression predicate into `poxburster.lua` so the existing single `_should_defend` hook owns both poxburster push setup and general melee attack-commit suppression
    - adds a light-attack tie/bias for unarmored horde targets so wide-arc heavies stop winning every mixed-trash engagement by default, while armored targets still preserve penetrating heavy preference
    - suppresses vanilla's blunt `num_melee_attackers() > 0` defend gate for low-count pressure against high-value armored commit targets when the current target is not actively attacking the bot
    - also caches weapon-special metadata on enter and prepends `special_action` for supported melee families
    - 1H power swords arm broadly in live combat windows (including multi-target non-elite pressure), Zealot 2H power swords resolve both `toggle_special` and `toggle_special_with_block`, 1H force swords stay targeted at elite/special/monster/super-armor value, 2H force swords instead require at least 10 stored special charges and an unarmored horde window, thunder hammers widen to armored/heavy elites plus captain/monster/boss, chain-family `toggle_special` weapons stay armor/heavy biased, ordinary human/Ogryn power mauls arm for high-health or armored targets, Ogryn `ogryn_club_p1_m2/m3` latrine shovels fold for high-health or armored targets, and direct combat axe/sword/knife plus Ogryn club/pickaxe/combat-blade specials use the same high-value target gate
27. Melee attack metadata injection (#23, via `melee_meta_data.lua`):
    - hook `WeaponTemplates` require: auto-derives and injects `attack_meta_data` for all melee weapons
    - traverses action graph: `start_attack` → `allowed_chain_actions` → light/heavy action → `damage_profile`
    - classifies `arc` from `cleave_distribution` (0/1/2) and `penetrating` from `armor_damage_modifier[armored]` (threshold ≥ 0.5)
    - feeds the BetterBots `_choose_attack` replacement with weapon-specific arc/penetration data instead of leaving bots on the vanilla light-only fallback
    - syncs with `enable_melee_improvements`: disabling the setting removes BetterBots-injected melee metadata from the live weapon templates so bots truly fall back to vanilla behavior
28. Ranged weapon `attack_meta_data` injection (#31, via `ranged_meta_data.lua`):
    - auto-derives `attack_meta_data` for player ranged weapons where `bt_bot_shoot_action`'s hardcoded fallback chain (`action_shoot` → `start_input` → `"shoot"`) produces invalid input names
    - scans `action_inputs` for `action_one_pressed` (fire), `action_two_hold` (aim), `hold_input` combos (aim-fire)
    - syncs with `enable_ranged_improvements`: disabling the setting restores any BetterBots-injected or patched ranged metadata fields on the live weapon templates
29. Sustained-fire hold bridge (#87, via `sustained_fire.lua`):
    - `weapon_action.lua` owns the single `PlayerUnitActionInputExtension.bot_queue_action_input` hook and forwards successful `weapon_action` requests to downstream observers rather than letting multiple modules hook the method independently; `weapon_action_logging.lua` owns diagnostic queue context/logging used by that hook
    - `SustainedFire.observe_queued_weapon_action(...)` remains one observer, and `ranged_special_action.lua` now shares the same seam for shotgun special-shell preload tracking
    - the same hook also exposes a narrow rewrite seam before the queued input is forwarded, so `ranged_special_action.lua` can rewrite supported shotgun fire requests into `special_action` without owning the engine hook itself
    - `BetterBots.lua` owns the single `hook_require("...bot_unit_input")` callback and installs both sprint + sustained-fire hooks together, avoiding DMF same-path clobbering inside one mod
    - `BetterBots.lua` also owns the shared `hook_require("...group/bot_group")` callback for healing deferral + mule pickup and wraps `mod:hook_require` with a duplicate-path guard so same-path registrations fail loudly instead of silently clobbering each other
    - hook `BotUnitInput.update`: cache the live bot unit on the input object so later low-level injection knows which unit it is driving
    - hook `BotUnitInput._update_actions`: inject raw hold inputs (`action_one_hold` for most full-auto/stream paths, `action_two_hold` for Purgatus flame charge) while sustained state is fresh
    - scope is execution-only: it respects the current `attack_meta_data` path choice and does not decide ADS vs hipfire vs brace
    - supported templates: flamer, Purgatus, recon lasguns, infantry autoguns, braced autoguns, autopistol, dual autopistols, bolter hipfire, Ogryn heavy stubbers, and rippergun braced fire
    - cross-references with `actions` via `start_input` to find correct action names
    - only injects when vanilla fallback would fail; standard weapons (lasgun, autogun, bolter, flamer) are skipped
    - also injects vanilla-style `aim_at_node = { "j_head", "j_spine" }` for allowlisted finesse families (lasgun, autogun, bolter, stub revolver) when the template leaves `aim_at_node` unset (#91 MVP)
    - fixes plasma gun (`shoot_charge`), force staff (`shoot_pressed` → `rapid_left`), and other exotic fire paths
29a. Ranged weapon specials (#33 follow-up, via `ranged_special_action.lua` + `weapon_action.lua`):
    - rewrites queued `shoot_pressed` / `zoom_shoot` inputs into `special_action` for the verified `ranged_load_special` shotgun families only (`shotgun_p1_m1/m2/m3`, `shotgun_p4_m1/m2`)
    - rewrites queued close-range rippergun fire into `stab` for `ogryn_rippergun_p1_m1/m2/m3` when the current target is inside the configured bayonet distance and is elite/special/captain/monster/boss or armored/super-armor
    - rewrites queued close-range Ogryn heavy-stubber p1 `shoot` fire into `stab` and thumper `shoot_pressed` fire into `bash` under the same target-value policy, controlled by the separate ranged-bash distance slider
    - rewrites verified one-step human ranged bashes/pistol whips (`autogun_p2`, bolters, bolt pistols, flamer, laspistol, stub revolver, dual autopistols) under the same close-range target-value policy
    - rewrite policy is target-value driven: visible elite/special/captain/monster/boss or armored/super-armor target required; `shotgun_p2_m1`, autogun p3, force-staff stabs, flashlight variants, mauls, and other hold/release or non-combat specials are still out of scope
    - state is tracked per bot unit so BetterBots can log both shell-arm and shell-spend with the current target breed name, which is the validation signal for “loaded and used on something worthwhile” versus “loaded and wasted on trash”
    - rippergun bayonet and direct ranged-bash support are single-step: successful queueing logs `queued rippergun bayonet ...` or `queued ranged bash ...` with template, target breed, bot slot, and original fire input
30. Melee target selection distance penalty (#19, via `target_selection.lua`):
    - hook `BotTargetSelection.slot_weight` during melee scoring
    - penalizes melee score for distant special enemies (>18m) when bot has sufficient ranged ammo (>50%) so ranged engagement wins instead of a long chase (#19)
    - hook `BotTargetSelection.monster_weight` to restore vanilla monster weight when the boss/miniboss blackboard says it is explicitly aggroed on this bot, even if nearby trash would normally zero the weight (#18)
31. Target-type hysteresis (#90, via `target_type_hysteresis.lua`):
    - hooks `BotPerceptionExtension._update_target_enemy` after vanilla target selection writes `perception_component`, leaving BT and weapon actions untouched
    - recomputes melee vs ranged scores with the same `BotTargetSelection` primitives, then applies a small current-type momentum bonus plus a score margin before allowing a type flip
    - stabilizes `perception_component.target_enemy_type` on both full reevaluation and current-target-only rescoring, reducing 0.3 s melee/ranged swap thrash on close scores
    - logs `type flip ...` on real transitions and `type hold ... over raw ...` when hysteresis actively suppresses a raw flip
31a. Per-breed weakspot aim override (#92, via `weakspot_aim.lua`):
    - wraps `BtBotShootAction.enter` to cache the shooter unit on the scratchpad, then uses `_set_new_aim_target` for initial override application and `_aim_position` for live Bulwark/Crusher refresh
    - `weapon_action.lua` owns the `bt_bot_shoot_action` hook_require callback and forwards `BtBotShootAction` into `WeakspotAim.install_on_shoot_action(...)`; BetterBots's duplicate-path guard on `mod:hook_require` forbids a second registration from this module
    - `weapon_action_shoot.lua` normalizes BT shoot scratchpads and suppresses stale `aim` / `unaim` queue inputs when the live `weapon_action` template no longer accepts them, so post-swap melee/warp templates do not inherit old `zoom` traffic from an earlier ranged shoot scratchpad
    - `weapon_action_voidblast.lua` carries the Voidblast (`forcestaff_p1_m1`) charged-shot fixes without stealing weakspot-owned hook slots:
      - `_update_aim` provides scratchpad context plus temporary retarget freezing once a charge anchor exists and restores the forced target even if vanilla `_update_aim` throws
      - `_wanted_aim_rotation` replaces the live `action_charge` torso tracking with a locked target-root anchor plus a short flat-velocity lead while keeping vanilla's straight-look vertical aim
      - `_fire` forces the charged release through `trigger_explosion` when the p1 charge path would otherwise fall back to plain `shoot_pressed`
    - `_set_new_aim_target` post-hook pins `scratchpad.aim_at_node` to a breed-specific node for Scab Mauler (`renegade_executor` → `j_spine`), to `j_head` for Bulwark only when the shield is open or the bot is outside the Bulwark's 70° blocking cone, and provisionally to `j_head` for Crusher only when the bot is in the rear arc
    - an `_aim_position` wrapper re-evaluates the two stateful cases (Bulwark shield exposure, Crusher rear arc) while the target stays locked, so turning or shield-state changes update live instead of going stale for the rest of the burst; when the exposure disappears or the bot retargets away, BetterBots restores the cached baseline so overrides do not leak across targets
    - baseline capture is lazy: the first `apply_override` call snapshots the current `scratchpad.aim_at_node` / `aim_at_node_charged` **before** mutation. An `enter`-level post-hook would be too late because vanilla `enter` calls `_set_new_aim_target` (and therefore our post-hook) before it returns, which on a Mauler-first acquisition would stamp the baseline with the already-overridden `j_spine`
    - Bulwark/Crusher exposure uses the engine's flat-ground block-angle model (`x/y` only, same 0.01 epsilon as `scripts/utilities/attack/block.lua:_calculate_block_angle`) rather than a full 3D angle, so stairs and ledges do not falsely mark a frontal shield as exposed
    - the Crusher path is explicitly provisional: the original "back-of-head node" claim is still not backed by the decompiled rig, so BetterBots does **not** invent a fake node name; it uses rear-arc `j_head` as a documented proxy until live validation or rig evidence says otherwise
    - guards with `Unit.has_node` before assignment; when debug logging is enabled it emits one-shot warnings for Bulwark shield API drift (`weakspot_aim:shield_api_missing:<unit>`) and configured node drift (`weakspot_aim:missing_node:<breed>:<node>`), then falls back to the cached vanilla baseline
    - runtime cost: one breed lookup on target acquisition for all breeds, plus live facing/shield checks only for Bulwark/Crusher while they remain the current target
31b. Charge/dash nav validation (#13, via `charge_nav_validation.lua`):
    - shared validator runs only after a charge/dash heuristic already wants to fire; it is not part of `build_context()` and does not add per-frame GwNav queries
    - validates the launch endpoint the lunge will actually use: explicit ally aim for rescue charges, current targeted-dash enemy position for zealot dash variants, and `BotNavigationExtension:destination()` only as the fallback for directional charges
    - wired into both `BtBotActivateAbilityAction.enter` and `ability_queue.lua`; both paths validate before mutating rescue aim, so a blocked charge does not leave `BotUnitInput` stuck on the ally position
    - caches same-destination failures per bot for 0.5s; a refreshed destination bypasses the cache immediately, preventing repeated queries against an unchanged bad path while still allowing prompt retries after follow-path refresh
    - exposed through the `enable_charge_nav_validation` setting so users have a kill switch if Fatshark changes BotNavigationExtension or GwNav behavior before BetterBots catches up
32. Human-likeness Tier A tuning (#44, via `human_likeness.lua` + queue/leash integration):
    - resolves two DMF-driven profiles in `settings.lua`: `human_timing_profile` (`auto` / `off` / `fast` / `medium` / `slow` / `custom`) and `pressure_leash_profile` (`auto` / `off` / `light` / `medium` / `strong` / `custom`)
    - `auto` resolves independently from current mission difficulty: Sedition/Uprising → `slow`/`light`, Malice → `medium`/`medium`, Heresy → `fast`/`medium`, Damnation/Havoc → `fast`/`strong`
    - patches `BotSettings.opportunity_target_reaction_times.normal` from vanilla `10-20` to the selected timing profile (default medium = `2-4`), restoring the original values when timing is off
    - classifies fallback ability rules into `immediate`, `defensive`, and `opportunistic` jitter buckets; emergency/rescue/hazard rules still bypass jitter, defensive rules use the smaller defensive range, and opportunistic rules use the larger opportunistic range
    - scales BetterBots' effective melee engagement leash from the selected pressure profile (default medium = start at `12`, full at `30`, scale to `65%`, floor `7m`) instead of the old fixed half-leash model
33. Runtime perf measurement (`perf.lua`):
    - central recorder keyed by the `enable_perf_timing` mod setting
    - instruments BetterBots-owned hot hooks and the main bot update slice with per-tag timing buckets
    - `/bb_perf` prints and resets the current recording window instead of toggling recording state
    - `GameplayStateRun` exit auto-dumps the same report to the console log with `bb-perf:auto:` prefixes when the recording window contains sampled bot frames, so mission-end and quit paths leave a perf snapshot even when `/bb_perf` is forgotten without spamming hub-only startup transitions
34. Tiered debug log levels (#40, via `log_levels.lua`):
    - replaces boolean debug toggle with info/debug/trace dropdown
    - `should_log(current_level, call_level)` gates `_debug_log` calls by severity
    - backward-compatible: nil `call_level` defaults to `"debug"`
34a. Combat utility diagnostics (via `debug.lua`):
    - hook `BtRandomUtilityNode.evaluate` only for the bot tree's `in_combat` node and only performs expensive reads after `_debug_enabled()` passes
    - logs the chosen branch/leaf, current utility scores, target type/distance, ally distance, and current weapon so close-range hesitation can be distinguished between utility choice (`follow` vs `combat`) and downstream action execution (`shoot`/`fight_melee`)
35. Shared rule tables (`shared_rules.lua`):
    - single source of truth for `DAEMONHOST_BREED_NAMES` and `RESCUE_CHARGE_RULES`
    - consumed by `condition_patch.lua`, `ability_queue.lua`, and `sprint.lua` to prevent cross-module drift
36. Default class-diverse bot profiles (#45/#63, via `bot_profiles.lua`):
    - hook `BotSynchronizerHost.add_bot`: resolve per-slot class setting → swap archetype, weapons, talents, cosmetics, blessings/perks
    - hook `BotPlayer.set_profile` (#65): block lossy network-sync overwrite for BetterBots-resolved profiles (`_bb_resolved` sentinel). Tags profiles with `is_local_profile = true` to bypass 1.11+ `validate_talent_layouts` in `unit_templates.lua`
37. Coherency-anchored engagement leash (#47, via `engagement_leash.lua`):
    - hook `BtBotMeleeAction._allow_engage`: dynamically inflate `override_engage_range_to_follow_position` based on combat context (already engaged → 20m stickiness, post-charge grace → 20m for 4s, under melee attack → 20m, ranged foray → 20m when ranged enemy targets bot)
    - hook `BtBotMeleeAction._is_in_engage_range`: extend approach range from 6m to 10m when engagement extension conditions hold
    - coherency-scaled base leash: `max(12m, coherency_radius + 4m)` via `UnitCoherencyExtension:current_radius()`, hard cap 25m (30m with always-in-coherency talent)
    - per-bot state in weak-keyed table with 1s coherency cache refresh
38. Team-level ability cooldown staggering (#14, via `team_cooldown.lua`):
    - pure state tracker: records activations per ability category, suppresses same-category activations from other bots within a time window
    - 3 categories: `taunt` (8s window), `aoe_shout` (6s), `dash` (4s) — roughly half the ability cooldown
    - stances and grenades excluded: stances are self-buffs (independent benefit), grenades are consumable charges (no regeneration)
    - emergency overrides bypass suppression: `psyker_shout_high_peril`, `zealot_stealth_emergency`, `ogryn_charge_escape`, any `_ally_aid` rule
    - gated by `enable_team_cooldown`; recording happens in the `use_ability_charge` hook and suppression runs in both `condition_patch._can_activate_ability` and `ability_queue.lua`
    - reset on game state change (hot-reload safe)

## DMF module loading pattern

- Load BetterBots-local modules only in `scripts/mods/BetterBots/BetterBots.lua` via `mod:io_dofile("BetterBots/scripts/mods/BetterBots/<name>")`.
- Do not call `require("scripts/mods/BetterBots/...")` from leaf modules. DMF's in-game loader does not resolve those paths reliably, even if local tests pass.
- Do not call `dofile("scripts/mods/BetterBots/...")` from leaf modules for shared helpers. That path can also fail under DMF resource loading.
- Share common tables/functions by dependency injection through `init({...})` and `wire({...})`. `shared_rules.lua` and `bot_targeting.lua` are the canonical examples.

## Hook registration: consolidation + idempotency

DMF dedupes hook registrations by `(mod, obj, method)`. A second `mod:hook` / `mod:hook_safe` call from the same mod on the same method is silently discarded, and emits `WARNING (hook_save): Attempting to rehook active hook [...]`. Two consequences follow.

**Rule 1: one hook per (obj, method) per mod.** When multiple features need to observe or wrap the same engine method, consolidate them under a single dispatcher hook in `BetterBots.lua`. Each feature module exposes a plain callback (for example `Poxburster.post_update_target_enemy`, `MulePickup.on_refresh_destination`) and the dispatcher pcall-invokes each one in turn. Current consolidated dispatchers:

| Engine method | Features dispatched | Dispatcher location |
|---|---|---|
| `BotPerceptionExtension._update_target_enemy` | `TargetTypeHysteresis`, `Poxburster` | `BetterBots.lua` `_install_bot_perception_extension_hooks` |
| `BotBehaviorExtension._refresh_destination` | `MulePickup`, `ReviveAbility` | `BetterBots.lua` `mod:hook_require(..., bot_behavior_extension)` callback |
| `BtBotMeleeAction` melee hooks | `MeleeAttackChoice`, `Poxburster`, `EngagementLeash` | `BetterBots.lua` `mod:hook_require(..., bt_bot_melee_action)` callback |

**Rule 2: every `hook_require` callback must be idempotent and hot-reload-safe.** DMF re-fires every registered `hook_require` callback whenever any mod calls `require()` on the same path (not just on first load), and `Ctrl+Shift+R` re-executes `BetterBots.lua` from scratch. Unguarded callbacks stack wrappers or retry field replacements on every replay. Guard pattern:

```lua
local SENTINEL = "__bb_<feature>_installed"
mod:hook_require("scripts/extension_systems/.../some_file", function(Target)
    if not Target or rawget(Target, SENTINEL) then return end
    Target[SENTINEL] = true
    -- hook / field mutation here
end)
```

The sentinel string must live on the engine class table (`rawget(Target, SENTINEL)`), not in a module-level Lua local (`setmetatable({}, {__mode="k"})`). Module locals reset when `BetterBots.lua` re-executes on hot reload; the engine class persists. Current callers of this pattern: `poxburster.lua`, `revive_ability.lua`, `ammo_policy.lua`, `weapon_action.lua`, `smart_targeting.lua`, and the two consolidated dispatchers in `BetterBots.lua`.

Regression coverage: `tests/startup_regressions_spec.lua` includes idempotency tests that simulate hot reload by loading the test harness twice with a shared extension table and assert zero new hook registrations on the second load.

**Rule 3: wrap optional pre-hook logic in `pcall` when the original is essential.** When a hook injects optional behavior *before* a critical engine action (revive interaction entry, rescue charge, etc.), an exception in the injected code must not prevent the original from running. A nil-component or unexpected-return error in `try_pre_revive` would otherwise leave a downed ally never rescued. Pattern:

```lua
local ok, err = pcall(M.optional_enhancement, unit, args)
if not ok and _debug_enabled and _debug_enabled() then
    _debug_log("module_error:" .. tostring(unit), _fixed_time(), "error: " .. tostring(err))
end
return orig_function(self, unit, args)
```

This rule applies when the injected logic is *optional enhancement* and the original is *essential gameplay* (revive, rescue, revive-related interactions, perils-of-the-warp achievement guard). Hooks where the injected logic *is* the primary behavior (for example `condition_patch._can_activate_ability` replacing the whitelist) do not need this wrapper — there is no original to protect.

## Where behavior gates belong: three parallel ability paths

When adding a "don't fire X under condition Y" rule, identify which path the activation goes through before placing the gate. The three paths are mutually independent:

| Path | Driven by | Condition layer for new gates |
|---|---|---|
| Template-based combat ability (Tier 1/2) | BT `activate_combat_ability` node → `bt_bot_conditions.can_activate_ability` | `condition_patch._can_activate_ability` (BT condition replacement) and `ability_queue.lua` (fallback) |
| BT melee / ranged actions | `BtBotMeleeAction`, `BtBotShootAction` | BT condition wrappers (`conditions.bot_in_melee_range`, `conditions.has_target_and_ammo_greater_than`) |
| Grenade / blitz (Tier 3b) | `grenade_fallback.lua` state machine, **bypasses BT ability node** | Per-template heuristic in `heuristics.lua` / `heuristics_grenade.lua` |

A wrapper on `bt_bot_conditions.can_activate_ability` does **not** cover melee/ranged BT actions, and neither covers `grenade_fallback`. The 2026-04-11 daemonhost-suppression bug landed because the v0.6.0 fix wrapped melee/ranged BT conditions only — `psyker_smite` then fired on a dormant daemonhost via `grenade_fallback` → heuristic → approve, with zero suppression log lines in the entire session.

Practical guidance:

- A gate that should affect *all three paths* is cleanest in `build_context()` (or a helper read by every per-template heuristic). Heuristics are read by both BT ability activation and `grenade_fallback`, so a context flag covers Tier 1/2/3 in one place.
- If a wrapper "isn't firing", grep the event logs for its dedicated dedup key first. Zero occurrences across a full session usually means the wrapper sits on the wrong path, not a throttle bug.
- For grenade-only or blitz-only rules, keep them in `heuristics_grenade.lua` rather than `condition_patch.lua`.

## Polymorphic change records: consumer-guard rule

The metadata injectors (`ranged_meta_data.lua`, `melee_meta_data.lua`, `meta_data.lua`) record per-template changes as structured records with a `mode` field. Two modes exist today:

- `"replace"` — the injector replaced the whole sub-table because it was empty/missing on first contact.
- `"fields"` — the injector recorded original per-key values for selective restoration. `change.original_fields` is **only** populated for this mode.

Any consumer function that reads mode-specific state (`change.original_fields[key]`, `change.replaced_value`, etc.) must early-return when the field is `nil` *or* when `change.mode` is the wrong mode. v0.11.0 crashed on startup (`ranged_meta_data.lua:342: attempt to index local 'original_fields' (a nil value)`) because `record_original_field` accessed `change.original_fields[key]` without that guard, on a load order where Tertium4Or5 had pre-set `attack_meta_data = {}` and the injector therefore took the replace path. Fixed in v0.11.2.

Rule when adding a new mode or a new consumer: every reader of `change.*` must guard on either the field's presence or `change.mode`. Add a regression spec that injects twice on the same template and exercises both the fresh path and the "already present" path.

## Grenade revalidation hysteresis (`opts.revalidation`)

`grenade_fallback.try_queue` evaluates the grenade heuristic twice per attempt: once at idle to decide "wield a grenade" and once after the aim window to re-check before releasing the throw. Both calls share `_evaluate_grenade_heuristic`. Density-gated templates (`_grenade_horde`, frag/box/fire/adamant) hard-gate at `num_nearby >= N`; across a ~0.5–1s aim window, `num_nearby` fluctuates as enemies move in and out of the bot's 5m proximity radius, so a strict re-check loses every throw to a transient one-enemy dip.

Mitigation: `_evaluate_grenade_heuristic` accepts `opts.revalidation = true`. When set, the dispatcher temporarily mutates `context.num_nearby = num_nearby + 1` for the duration of the call and restores the original value before returning. `grenade_fallback.lua` passes `{ revalidation = true }` only at the aim-window re-check. The relaxation is bounded to one enemy — `0 → 1` is still held, so "threw into empty space" is impossible.

When tuning grenade density thresholds in `heuristics_grenade.lua`, remember the effective revalidation floor is `threshold - 1`, not `threshold`. If you lower frag from 6 to 5, the revalidation check accepts throws at 4 nearby. Raise the initial threshold rather than relaxing the delta if that becomes too permissive. Test coverage: `tests/heuristics_spec.lua` `describe "evaluate_grenade_heuristic"` pins both the relaxation and the empty-context floor.

## Why item fallback is needed

Item-based abilities rely heavily on weapon `conditional_state_to_action_input` chains (for example wield -> channel/place).

In `ActionInputParser.action_transitioned_with_automatic_input`, bots early-return, so these automatic chains do not advance for bot-controlled units. Humans get those automatic transitions; bots do not.

Result: item abilities need explicit queued inputs from the mod.

## Ability tiers in this repo

| Tier | Current handling | Notes |
|---|---|---|
| 1 | Whitelist bypass | Templates define usable `ability_meta_data` |
| 2 | Runtime metadata injection | Includes template-specific `wait_action`/`end_condition` where needed |
| 3a | Item-based combat fallback (experimental) | Driven via `item_fallback.lua` state flow and `item_profiles.lua` sequence probing by action-input names |
| 3b | Grenade/blitz fallback (experimental) | Driven by `grenade_fallback.lua` state flow, `grenade_profiles.lua` input profiles, `grenade_aim.lua` target/ballistic aim helpers, and `grenade_runtime.lua` runtime state/event helpers |

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

`/bb_perf` reports the sum of top-level instrumented BetterBots hook time over the current recording window, normalized as `µs/bot/frame` using bot update samples. Some rows are breakdown-only child tags for diagnosis; these appear in the per-tag table but are excluded from the headline total when their parent hook already includes the same work. Recording is controlled by the `enable_perf_timing` setting; the chat command only prints and resets accumulated counters. The same formatter is also emitted automatically on `GameplayStateRun` exit with the `bb-perf:auto:` prefix when the window contains at least one sampled bot frame.

For v1.0.0 release decisions, BetterBots now treats perf as a mission-end benchmark problem, not a one-off headline chase. The canonical measurement is the mission-end `bb-perf:auto:` total from three combat-heavy Solo Play runs on the same build, with `Performance timings` enabled and other diagnostics quiet. The acceptance bar is **median <= `125 µs/bot/frame` with no single run > `140 µs/bot/frame`**. The old `<80 µs/bot/frame` target is retired because it was never backed by a stable protocol.

**Hot paths (per fixed frame, per bot — ~90 calls/sec total with 3 bots):**

| Path | Cost | Notes |
|---|---|---|
| `build_context()` | ~1 iteration over proximity list + coherency allies | Cached per unit per `fixed_t` — runs once per bot per frame regardless of how many call sites invoke it |
| Heuristic evaluation | ~20 arithmetic comparisons | Pure comparisons on pre-built context table, no allocations, no engine calls |
| `_can_activate_ability` (BT condition) | 1 `require` (cached) + `build_context` + heuristic | Only fires when BT priority selector reaches the ability node — usually short-circuited by higher-priority nodes |
| `_fallback_try_queue_combat_ability` (update hook) | Same as above + state machine checks | Most frames exit early (cooldown not ready, retry timer, `can_use_ability("combat_ability") == false`, or state guard) |
| Event logging (`emit`) | 1 table append per event | Buffered; flush to disk every 15s or 500 events. Off by default. |
| Debug logging (`_debug_log`) | 1 string concat for key + 1 table lookup | Message body only built when debug enabled, but key argument is always evaluated |

**Instrumented perf buckets:**
- `ability_queue`, `grenade_fallback`, `ping_system`, `event_log_flush`, `event_log_snapshot`, `event_log_session_start`
- Breakdown-only child tags: `ability_queue.item_fallback`, `ability_queue.template_setup`, `ability_queue.input_validation`, `ability_queue.decision`, `ability_queue.queue`
- Breakdown-only child tags: `grenade_fallback.build_context`, `grenade_fallback.heuristic`, `grenade_fallback.profile_resolution`, `grenade_fallback.launch`, `grenade_fallback.stage_machine`
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
- No duplicate per-bot daemonhost list scans in sprinting — non-aggroed daemonhost units are cached once per frame per `(side_system, enemy_side_names)` reference before per-bot distance checks (reference equality on `enemy_side_names` is safe because vanilla `Side:relation_side_names` returns a stable cached table per relation)
- No duplicate same-frame human ammo eligibility scan for each bot — ammo policy caches the all-humans-above-threshold result by frame, human unit table, and threshold
- No repeated same-frame suppression component reads per bot — `_is_suppressed(unit)` caches its result by unit and `fixed_t`
- No table allocations in the heuristic path (context is reused via cache)

### Known minor waste

`_debug_log` key strings (e.g. `"none:" .. ability_component_name`) are concatenated even when debug is disabled, because Lua evaluates all function arguments before the call. This produces ~90 throwaway strings/sec. Negligible but could be gated behind `if _debug_enabled() then` if profiling ever shows string GC pressure.

### Growth vectors to watch

When implementing these issues, verify the change doesn't add per-frame engine calls:

| Issue | Risk | What to watch |
|---|---|---|
| #4 Grenade/blitz support | **Low** | Same architecture — one more heuristic per bot. Context cache shared. |
| #13 Charge/dash nav validation | **Implemented** | Keep it as a post-heuristic one-shot check only. Do not move GwNav queries into `build_context()` or other per-frame hooks, and preserve the same-destination negative cache so repeated invalid launches do not spam `ray_can_go`. |
| #15 Suppress dodge during ability hold | **Low** | One additional condition check in an existing hook. No new per-frame hook needed. |
| #22 Utility-based ability scoring | **Low-Medium** | If it replaces if/else heuristics with a scoring pass over all abilities, context build is still cached. Scoring itself would be cheap. Risk is if it queries additional engine state per ability. |
| #23 Smart melee attack selection | **Medium** | Could require reading weapon template data per frame. Keep reads cached and avoid per-frame `rawget` chains on large template tables. |
| New per-frame hooks (general) | **Medium** | DMF hook dispatch has non-trivial cost (closure call + argument forwarding + chain-call). Currently 6 hooks on per-frame paths — acceptable. Consolidate logic into fewer hook sites rather than adding one hook per feature if count grows past ~10. |

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
