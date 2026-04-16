# Known Issues and Risks

## Current v0.11.0 release-candidate blockers

1. `#17` daemonhost avoidance still needs another live spawn after the 2026-04-15 stage-aware dormant-daemonhost fix. Earlier logs proved daemonhosts spawn dormant, but BetterBots was only consulting `aggro_state`, so by the time bots reacted the target often already looked `aggroed`. The code now treats daemonhost `stage != aggroed` as authoritative when the field is available; the next real spawn needs to show the new `dormant_daemonhost` suppression lines.
2. `#32` mule pickup no longer crashes on stale units, and the current branch now overrides vanilla's nearby-human suppression for auto-mule books, but there is still no live tome/scripture pickup confirmation in the current branch logs.
3. `#82` perf audit code is in and fresh `/bb_perf` captures now exist on the current branch, but the latest real mission-end samples are still `99.1 us/bot/frame` and `109.3 us/bot/frame`, so the original `<80 us/bot/frame` target is still unmet.
4. `#90` target-type hysteresis still needs another live combat run. The 2026-04-15 log proved the symptom layer is real (`230` `wrong slot ...` / `switch_* entered` lines) while the perception-layer hysteresis never fired (`0` `type flip` / `type hold`), and 2026-04-16 debugging traced that to startup order: if `bot_target_selection_template` was already loaded before BetterBots registered `hook_require`, the math-layer wrapper never installed. The current branch now eagerly patches already-loaded target-selection templates and keeps the BT-side opposite-type switch debounce, but it still needs live confirmation that `type hold` / `type flip` and `target_type_hysteresis.post_process` actually appear in mission logs.

## High severity

1. ~~DMF `hook_require` clobbering~~ **Fixed in v0.9.1** (#67). The melee hooks now install through one consolidated `bt_bot_melee_action` hook, restoring both melee light bias and poxburster push behavior. `#54` and `#74` validated in the 2026-04-11 live run (full push chain at 16:33:12), so the related follow-ups are also closed.

2. ~~Veteran bots replaced by wrong class~~ **Validated and closed** (#68). Run `0` (`console-2026-04-07-15.36.11-a46f7c58-38a2-401c-aefc-1e4e4dfcc9f5.log`) logged preserved external profiles with real `character_id` values for bot slots 1-4, confirming BetterBots yielded to Tertium/SoloPlay profiles instead of overwriting them.

3. ~~Exception-unsafe shared state mutation~~ **Fixed in v0.9.1** (#73). Shared-state mutations now restore on error paths. Keep an eye out for a real vanilla throw repro, but this is no longer an active known issue.

4. ~~Non-veteran bot profiles crash on Darktide 1.11.0 (Warband)~~ **Fixed** (#65). Root cause: `ProfileSynchronizerClient` overwrites the BotPlayer's profile with a JSON-reconstructed version that loses weapon overrides and has talents stripped by `validate_talent_layouts` (new in 1.11). Fix: tag resolved profiles with `is_local_profile = true` (bypasses `unit_templates.lua` validation) and `_bb_resolved = true`, hook `BotPlayer.set_profile` to block the lossy overwrite.

2. ~~DMF toggle safety is incomplete.~~ **Fixed in v0.8.0** (#57): `is_togglable = false`. The mod mutates global singletons (`AbilityTemplates`, `bt_bot_conditions`, `Overheat`, breed data) — DMF's `disable_all_hooks()` cannot revert these. Restart to disable.

2. ~~Bots stop shooting at 50% reserve ammo (#51).~~ **Fixed in v0.7.1**: threshold lowered to 20%. Validated: 270 permitted shots with lowered gate in standard-profile mission.

3. ~~Heavy attack overuse in horde (#52).~~ **Fixed in v0.7.1**: `melee_attack_choice.lua` biases lights into unarmored hordes. Validated: 0 heavies vs unarmored across 2 sessions.

4. ~~Precision blitz targeting (#61).~~ **Fixed in v0.7.1**: charge-lock + pre-flight target check + aim control. Validated: 87 queued → 92 consumed, 0 blind throws, both aimed and fast paths active.

5. ~~Grenade aim direction (#62).~~ **Fixed in v0.7.1**: `_set_bot_aim` drives aim for all throws, pre-flight gate prevents entry without target. Validated: 55 aimed releases all with real targets.

## Medium severity

1. ~~Tier 3 item fallback timing mismatch.~~ **Fixed** (#3): Wield_slot hook redirects to `slot_combat_ability` instead of blocking (prevents cancel loop). Followup delays shortened to 0.35s (aim actions chain immediately). Coherency self-exclusion fixes dead `allies_in_coherency == 0` guards. Validated 8/8 consumes (5 drone, 1 shield, 2 relic).

2. ~~Stance cancellation complexity (#12).~~ **Closed.** Stances have no release input (`transition = "stay"`). Early cancellation would require template injection or `stop_action()` + buff cleanup — decided not to pursue.

3. ~~Mastiff-pinned target fixation~~ **Validated and closed** (#69). Run `0` logged both melee and ranged `friendly companion pin -100` penalties against pinned enemies, confirming bots now de-prioritize already-controlled mastiff targets.

4. ~~Arbites whistle ignores mastiff position~~ **Validated and closed** (#70). Run `0` logged repeated `grenade_whistle_block_companion_far` holds plus successful `adamant_whistle` charge consumes, confirming the mastiff-distance gate blocks empty-space whistles while still allowing valid detonations.

5. ~~Ogryn grenade mid-horde~~ **Validated and closed** (#71). Committed grenade swaps now block when the current target is inside 4m, and single-target throw heuristics also block under crowd pressure. Crowd-control and area-denial grenades are still allowed in dense fights.

6. ~~Ammo threshold dead band~~ **Validated and closed** (#72). Opportunistic ranged fire and ammo pickup onset now share one configurable threshold, and bots only claim ammo when eligible human ammo users are above the configured reserve.

7. BT preemption during revive.
   - BT re-evaluates every frame even while a node is running.
   - Ability activation (priority 8-9) CAN interrupt an in-progress revive (priority 2) if `can_revive` becomes false momentarily.
   - Fix: Check `blackboard.behavior.current_interaction_unit ~= nil` in ability condition to block activation during any active interaction.
   - Estimated fix size: ~5 lines of code in the condition hook.

4. Item fallback is heuristic, not data-driven.
   - Item templates are matched by known action-input shapes (`channel`, `instant_aim_force_field`, etc.).
   - New or changed templates can fail with `fallback item blocked ... unsupported weapon template`.
   - In the latest run, psyker force-field showed mixed behavior after reload (`aim_force_field`/`place_force_field` queued, but no later `charge consumed` line).

5. Per-career heuristics: 15/18 validated (12 combat + 3 item), 1 N/A, 2 Hive Scum DLC-blocked.
   - Production presets shipped in v0.8.0 (#6): per-template threshold tables for aggressive/balanced/conservative, with testing profile for validation. The "testing" preset uses intentionally lenient thresholds; production presets are calibrated per-heuristic.
   - Item heuristics added (#3): zealot_relic, psyker_force_field (3 variants), adamant_area_buff_drone, broker_ability_stimm_field. Replace coarse `enemies_in_proximity > 0` gate with per-ability rules using coherency, toughness, corruption, and ally state.
   - Meta builds research (`docs/classes/meta-builds-research.md`) shows Combat Ability Regeneration is a universal curio perk across all classes — players optimize for maximum ability uptime, suggesting current thresholds may be too conservative even for the "Balanced" preset.
   - Use `/bb_decide` to inspect live decisions during play.

6. ~~Psyker Scrier's Gaze causes warp overcharge explosions.~~ **Fixed** (#27): Warp weapon attacks blocked at ≥97% peril via `bot_queue_action_input` hook. Vent/reload inputs pass through. Root cause: stance itself doesn't explode — explosions only happen when additional peril is generated (warp weapon attacks) while at 100%.

7. Structured event log (JSONL) working directory.
   - Darktide's CWD is `binaries/`, so `./dump/` resolves to `<game-root>/binaries/dump/`.
   - `bb-log events` expects `EVENTS_DIR=./dump` relative to CWD — run from `binaries/` or adjust the path.
   - Hot-reload (`Ctrl+Shift+R`) resets module state; load-time recovery re-enables logging if bots are alive, but unflushed buffer from before reload is lost.

8. Debug log noise reduced — idle-state decisions now invisible.
   - `decision -> false`, `fallback held (nearby=0)`, and `bt gate evaluated` are suppressed.
   - Idle hold counts in `bb-log summary` will show 0 for new runs.
   - See `docs/dev/logging.md` for details and how to re-enable.

## Low severity

1. Perception target vs. aggregate field inconsistency.
   - `target_enemy` / `target_enemy_type` (single BT-selected target) can disagree with `challenge_rating_sum` / `num_nearby` / type counts (broadphase proximity scan).
   - Example: `target_enemy = chaos_poxwalker` with `challenge_rating_sum = 8` and `target_enemy_type = ranged` — the poxwalker is the BT's selected target while the aggregate reflects a nearby Chaos Ogryn.
   - Impact: heuristics that mix single-target and aggregate fields could make inconsistent decisions.
   - Mitigation: prefer aggregate fields (`challenge_rating_sum`, `elite_count`, `target_enemy_distance`) for threshold tuning. Use `target_enemy` only for boolean checks (`target_is_monster`, `target_is_super_armor`).

2. Injected `end_condition` values are simplified.
   - Charge templates use `done_when_arriving_at_destination = true`.
   - Functional, but not fully validated across all talent variants.

## Dependency issues

1. Tertium4Or5 profile selection can still be an external crash point depending on local patch state.
   - Symptom: crash while enumerating personalities/archetypes in Tertium profile collection (`fetch_all_profiles` path).
   - Local validation workaround: nil-guard invalid personality/archetype entries in `mods/Tertium4Or5/scripts/mods/Tertium4Or5/Tertium4Or5.lua`.
   - BetterBots should not vendor this patch; keep it as upstream Tertium4Or5 responsibility and document it as a compatibility note.
   - Release policy: Tertium4Or5 is optional/recommended for better bot profile UX, not required for BetterBots core ability logic.

2. DMF Dev Console/Dev Mode interactions can produce crashes outside this mod's code path.
   - Treat as external until a BetterBots-specific traceback is captured.

3. Vanilla airlock teleport crash when bot count exceeds 4 teleport nodes.
   - Symptom: `door_extension.lua: bad argument #2 to 'has_node' (string expected, got nil)` when entering airlocks.
   - Root cause: Fatshark's `teleport_bots()` indexes a 4-entry node name table without a nil guard. SoloPlay mods that spawn extra bots push the index past the table bounds.
   - BetterBots does not modify bot counts or door/teleport logic. This is a vanilla/SoloPlay issue.
   - Mitigation: `airlock_guard.lua` wraps `teleport_bots` with pcall — un-teleported bots catch up via normal follow behavior.

## Current fix direction

1. ~~Add explicit restore-on-disable behavior.~~ Done (#57) — set `is_togglable = false` instead.
2. ~~Align `ITEM_SEQUENCE_PROFILES` timing with decompiled action durations (#3).~~ Done — validated 100% consume rate.
3. Replace heuristic item matching with explicit per-template mapping table.
4. Reduce debug-log noise for expected transient `invalid action_input` states.
5. ~~Add smarter per-ability trigger policies~~ Done (#2, closed) — 15/18 validated in-game (12 combat + 3 item).
6. Track upstream status of the Tertium4Or5 nil-guard fix and remove local compatibility note once upstreamed.
