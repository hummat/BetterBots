# Handoff

## Current Task
Validate the new `#43` force-staff charged-fire fix in-game on `dev/m4-batch1` with template-tagged weapon logs, then decide whether to ship the batch (#42 VFX/SFX bleed fix, #23 melee meta_data, #31 ranged meta_data, #30 warp venting, maybe #43).

## Agent
GPT-5 (Codex CLI)

## Decisions Made
- Mod name: `BetterBots`, lives in `$GIT_ROOT/BetterBots`, symlinked into Darktide `mods/` dir
- Approach: Hook `bt_bot_conditions.can_activate_ability` to remove Fatshark's hardcoded whitelist
- Tier 1/2/3 architecture unchanged from v0.1.0–v0.4.0
- **#30**: Three hooks for warp weapon venting: (1) bridge `warp_charge.current_percentage` into `Overheat.slot_percentage`, (2) fix `should_vent_overheat` hysteresis using `is_running` instead of broken `scratchpad.reloading`, (3) translate `reload` → `vent` in `bot_queue_action_input` for warp weapons
- **#30 ordering fix**: Reload→vent translation must happen BEFORE peril guard (was after — GPT-5 caught this). Peril guard now excludes `"vent"` so venting isn't blocked at critical peril.
- **#43 aim_fire approach**: Overriding `aim_fire_action_input` to `trigger_explosion` does NOT work — the BT's `_fire()` is never called while the bot is in charge mode. The bot cycle is `charge → vent` with no fire step. Needs fundamentally different approach.
- **#43 investigation findings**: Vanilla `attack_meta_data` maps staff aiming to charging (`aim_action_name=action_charge`, `unaim_action_name=action_vent`). `can_charge_shot` is unset on all weapons — BT charge shot system is unused. The `charge` inputs in logs are the AIM system, not the charge shot system.
- 2026-03-09: The previous `#43` diagnosis was incomplete for the current worktree. After commit `74a3ee9`, `scripts/mods/BetterBots/ranged_meta_data.lua` no longer injected staff aim metadata; it only overrode `aim_fire_action_input`.
- 2026-03-09: Force staff families do not share one charged fire input. Decompiled templates show `forcestaff_p1_m1 -> trigger_explosion`, `forcestaff_p2_m1 -> trigger_charge_flame`, `forcestaff_p3_m1 -> shoot_charged`, and `forcestaff_p4_m1 -> shoot_charged`.
- 2026-03-09: Vanilla `BtBotShootAction` has an aim/fire validation mismatch: `_may_fire()` validates `scratchpad.fire_action_input`, but `_fire()` dispatches `aim_fire_action_input` when `scratchpad.aiming_shot == true`.
- 2026-03-09: The old claim "charge -> vent with no fire step" is too broad. Template-tagged log `console-2026-03-09-15.44.58-007993e0-525d-480e-8198-40fb90d375c1.log` shows `forcestaff_p4_m1` queuing `shoot_pressed` after `charge`; the observed failure is wrong aimed input/state, not total absence of fire requests.
- 2026-03-09: Replaced the broader `_start_aiming/_stop_aiming` scratchpad swap with a narrower hook on `BtBotShootAction._may_fire()` that only swaps to `aim_fire_action_input` for the duration of the validation call.
- 2026-03-09: Reinstated template-tagged `bot weapon:` logging in `PlayerUnitActionInputExtension.bot_queue_action_input`; queued weapon inputs now include bot slot, wielded slot, weapon template, and warp template so `shoot_charged` / `trigger_explosion` can be attributed to a specific bot.

## Changes (this session, uncommitted on `dev/m4-batch1`)
- `scripts/mods/BetterBots/BetterBots.lua` — #30: `should_vent_overheat` hysteresis fix, `Overheat.slot_percentage` warp charge bridge, `reload→vent` translation (reordered before peril guard), diagnostic weapon logging (temporary, remove before merge)
- `scripts/mods/BetterBots/ranged_meta_data.lua` — #43: charge override pass in `inject()` overriding `aim_fire_action_input` to `trigger_explosion` for 7 force staff templates; removed diagnostic meta_dump
- `tests/ranged_meta_data_spec.lua` — 3 new tests: charge override for force staves, no-op for lasguns, no-op for plasma
- `AGENTS.md` — test count update (226→229, 28→31)
- 2026-03-09: `scripts/mods/BetterBots/ranged_meta_data.lua` — added `find_aim_action_for_fire()` and changed the `#43` override to derive `aim_action_input/name`, `aim_fire_action_input/name`, and `unaim_action_input/name` from the charge action's chain metadata instead of only swapping `aim_fire_action_input`.
- 2026-03-09: `scripts/mods/BetterBots/BetterBots.lua` — hooked `BtBotShootAction._may_fire()` instead of mutating scratchpad state across the full aim lifecycle; the hook temporarily validates against `aim_fire_action_input` only for that single call.
- 2026-03-09: `scripts/mods/BetterBots/BetterBots.lua` — upgraded temporary `bot weapon:` diagnostics to template-tagged logs (`bot`, `slot`, `weapon_template`, `warp_template`, `action`, `raw_input`) with no throttling so the next in-game run can attribute queued charged inputs.
- 2026-03-09: `tests/ranged_meta_data_spec.lua` — added a targeted test for hold-action derivation and expanded the `#43` spec to assert aim start, aim fire, and unaim metadata together; ranged test count is now 32 and total test count is 230.
- 2026-03-09: `AGENTS.md` — updated automated test counts again (229→230 total, 31→32 ranged tests).
- 2026-03-09: `docs/dev/logging.md` and `docs/dev/debugging.md` — documented the template-tagged `bot weapon:` diagnostic format.

## Open Questions
- **#43 fire step never reached**: BT `bt_bot_shoot_action._fire()` only uses `aim_fire_action_input` when `aiming_shot == true`, and `_should_aim` requires `target_ally_distance <= 8` + `gestalt_behavior.wants_aim == true`. The bot enters charge mode (24× in test session) but the BT never fires while aimed — goes straight to vent. Root cause: either `_may_fire` conditions fail, or the BT exits aim state before reaching fire. Needs deeper investigation of `bt_bot_shoot_action` state machine.
- **#43 alternative approaches**: (a) Hook `_fire()` to force fire while in charge state, (b) Intercept the charge action to inject a fire step, (c) Use a completely different mechanism than aim_fire, (d) Accept that charged projectiles via `shoot_charged` (7×, from weapon auto-transition) are "good enough"
- **`vent_release` on BT leave**: `BtBotReloadAction.leave()` only calls `bot_queue_clear_requests`, doesn't send `vent_release`. Force staff `action_vent` has `stop_input = "vent_release"`. Testing showed no issues (safety net: `fully_vented` auto-transition at 0% peril), but not formally verified.
- **Peril guard stress test**: No `peril_block` entries in any test session — peril never hit 97%. The reorder fix is correct but untested under extreme conditions.
- 2026-03-09: `#43` is still unverified in runtime. No fresh mission was run after the new metadata + aiming-validation patch, so the only hard evidence is code + unit tests.
- 2026-03-09: The narrower `_may_fire()` hook still needs an in-game regression check on ordinary guns (lasgun/bolter/plasma), but the risk is lower now because it no longer mutates scratchpad state outside the validation call.
- 2026-03-09: Fresh in-game evidence is still missing. The code now emits template-tagged weapon logs, but no post-patch mission has been run yet to collect them.

## Key Files in Decompiled Source
- `scripts/extension_systems/behavior/nodes/bt_bot_shoot_action.lua` — BT shoot node: `_should_aim` (line 141), `_fire` (line 605), `_start_aiming` (line 161), `_should_charge` (line 484)
- `scripts/extension_systems/behavior/nodes/bt_bot_reload_action.lua` — BT vent/reload node (34 lines), sets `scratchpad.is_reloading`
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua:462-482` — `should_vent_overheat` with `scratchpad.reloading` bug
- `scripts/extension_systems/behavior/utilities/bot_behavior_tree.lua:155-176` — BT vent node condition_args (start_min=0.5, start_max=0.99, stop=0.1)
- `scripts/utilities/overheat.lua:231-254` — `slot_percentage` and `configuration`
- `scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p1_m1.lua` — charged secondary uses `trigger_explosion`
- `scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p2_m1.lua` — charged secondary uses `trigger_charge_flame`
- `scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p3_m1.lua` — charged secondary uses `shoot_charged`
- `scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p4_m1.lua` — charged secondary uses `shoot_charged`
- `scripts/utilities/action/action_handler.lua` — `action_input_is_currently_valid()` validates chain actions against the running weapon state

## Validation Status
- **#42 VFX/SFX bleed**: PASS (3 sessions)
- **#23 melee meta_data**: PASS (injected=66, heavy_attack logged)
- **#31 ranged meta_data**: PASS (patched=36, shoot_charge/shoot_pressed confirmed)
- **#30 warp venting**: PASS (15 vent translations, zero errors, reorder fix applied)
- **#43 charged staff fire**: PATCHED locally but not re-tested in-game. Previous sessions failed under the old aim-fire-only approach; current code has 230 passing unit tests and a clean `make check`, but no fresh mission evidence yet.
- All sessions: zero Lua errors

## Next Steps
- **Decision**: Ship batch as #42+#23+#31+#30 (shelve #43), or dig deeper into #43
- **If continuing #43**: Run a fresh mission with DMF debug logging enabled and confirm from template-tagged `bot weapon:` lines that the force staff bot queues the correct family-specific charged input (`trigger_explosion`, `trigger_charge_flame`, or `shoot_charged`) rather than `shoot_pressed`.
- **If `#43` passes in-game**: Keep the current charge metadata + aiming-validation patch, update `docs/BATCH_TEST_m4-batch1.md`, and close/update GitHub issue `#43`.
- **If `#43` still fails**: Use the new template-tagged `bot weapon:` lines to separate staff output from plasma/lasgun output before changing the charge logic again.
- **If shipping without `#43`**: Remove diagnostic weapon logging from `BetterBots.lua`, decide whether to keep or revert the new `#43` patch, commit all, merge to main, tag release
- **Update GitHub issues**: #30 (close with implementation details), #43 (update with investigation findings — aim system provides charge cycling, explosions need dedicated logic, aim_fire path doesn't fire)
- **Update MEMORY.md**: Add vanilla `attack_meta_data` field structure findings

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 | GPT-5 | Initial investigation, bot AI audit, ability flow mapping |
| 2026-03-04 | Claude Opus 4.6 | Created mod, README, docs, debug logging, Tertium4Or5 crash fix |
| 2026-03-04 | GPT-5 | Startup crash fix, runtime patching hardening, Tier 2 metadata |
| 2026-03-04 | GPT-5 | Item fallback improvements, force-field/relic timing, validation guards |
| 2026-03-05 | GPT-5 | Tier 1/2 validation complete, Tier 3 hardening, ratio metrics |
| 2026-03-05 | Claude Opus 4.6 | v0.1.0 Nexus release, README restructure, blitz inventory (#4), 6 tactics docs, docs-first policy |
| 2026-03-05 | GPT-5 | Handoff continuity, tomorrow plan |
| 2026-03-06 | Claude Opus 4.6 | Refactor into sub-modules (#25/#26), unit tests (95), per-career heuristics (#2), debug commands |
| 2026-03-06 | Claude Opus 4.6 | Reviewed #2 status — implementation complete, updated STATUS.md and HANDOFF.md |
| 2026-03-09 | Claude Opus 4.6 | #30 warp venting (3 hooks), #43 investigation (aim system = charge cycling, trigger_explosion unreachable via aim_fire), peril guard reorder fix (GPT-5 catch), 229 tests |
| 2026-03-09 | GPT-5 (Codex CLI) | Re-evaluated `#43`, found current handoff/worktree mismatch, patched charge aim metadata plus aimed-fire validation, updated tests/docs, and got `make check` green (230 tests) without in-game revalidation |
| 2026-03-09 | GPT-5 (Codex CLI) | Narrowed the aimed-fire fix from a broad scratchpad swap to a direct `_may_fire()` hook, reran `make check`, and kept the remaining risk to ordinary-gun in-game regression only |
| 2026-03-09 | GPT-5 (Codex CLI) | Reinstated template-tagged `bot weapon:` diagnostics for `#43`, documented the new log format, and prepared the branch for a decisive in-game attribution run |
