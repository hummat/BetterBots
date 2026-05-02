# Debugging and Testing

## Debug tools available

### DMF built-in (already available)

| Tool | Usage | Notes |
|------|-------|-------|
| `mod:echo(msg, ...)` | Print to chat + log file | What we use now. Configurable output modes (0-7). |
| `mod:error(msg, ...)` | Red alert + log | For serious errors. Plays notification sound. |
| `mod:warning(msg, ...)` | Warning level | For unexpected but non-fatal conditions. |
| `mod:debug(msg, ...)` | Debug level | Disabled by default in DMF. We use our own `_debug_log()` instead. |
| `mod:dump(table, name, depth)` | Dump table to log | Recursively prints table with depth limit. Handles circular refs. |
| `mod:dtf(table, name, depth)` | Dump table to JSON file | Exports to `./dump/table_name.json`. Alias: `mod:dump_to_file()`. |
| `mod:pcall(func, ...)` | Safe call with stack trace | Wraps in `xpcall` + `Script.callstack()`. Errors logged, no crash. |
| `mod:command(name, desc, func)` | Register `/name` chat command | Runtime debugging commands. Per-mod namespace. |
| `mod:persistent_table(id, default)` | Table survives hot reload | For debug state across `Ctrl+Shift+R` reloads. |

### Community tools

| Tool | What it does | Install |
|------|-------------|---------|
| **Modding Tools** (Nexus #312) | Table inspector, variable watcher, enhanced console | Recommended for development |
| **Power DI** (Nexus #281) | Data collection framework, auto-saves to disk | For statistical analysis of bot behavior over time |

### Log file workflow

**Location (Linux/Proton):**
```
/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/
```

**Real-time monitoring:**
```bash
tail -f "<path>/console_logs/console-*.log" | grep --line-buffered "BetterBots\|Script Error\|Lua Stack"
```

**Key log markers to grep:**
- `[MOD][BetterBots]` — our mod's output
- `<<Script Error>>` — Lua errors
- `<<Lua Stack>>` — stack traces
- `<<Crash>>` — engine crashes

**BetterBots-specific log patterns (for grep/rg):**

| Pattern | What it means |
|---------|---------------|
| `fallback queued` | Ability input was sent to the action queue (activation attempt) |
| `fallback held` | Heuristic decided NOT to activate (with rule name + nearby count) |
| `fallback blocked` | Ability on cooldown or action_input invalid (post-activation spam) |
| `blocked lossy network-sync profile overwrite` | `BotPlayer.set_profile` one-shot guard blocked the lossy 1.11+ sync overwrite for a resolved bot profile (#65) |
| `allowed profile update` | `BotPlayer.set_profile` hook passed a later legitimate profile update through after the one-shot guard |
| `charge consumed` | Ability charge was spent (confirmed activation) |
| `post-charge grace started` | Engagement leash recorded a movement-ability charge and started the temporary grace window (#47) |
| `one-shot context dump` | First-time context dump for a template (debug-only) |
| `fallback item queued` | Tier 3 item-ability input sent |
| `fallback item blocked` | Tier 3 sequence failed (timeout, drift, etc.) |
| `unsupported grenade template` | Grenade/blitz heuristic approved a template with no mapped throw profile |
| `grenade queued <input> for <grenade>` | Grenade/blitz stage machine advanced a named input for a specific grenade; use this to distinguish Assail aimed `zoom`/`zoom_shoot` from crowd-burst `shoot` |
| `grenade aim ballistic for <grenade>` / `grenade aim flat fallback for <grenade>` / `grenade aim unavailable for <grenade>` | Aim solver path chosen for the current grenade/blitz; strongest runtime signal for new Assail/area-grenade aiming logic. Aim lines include `bot=`, `target=`, `target_alive=`, and `target_breed=` so no-LOS aborts can be correlated with later throws. `(no_los)` means the target perception reported wall occlusion, so the throw was refused before release. |
| `grenade aim lost dead target for <grenade>` | The grenade/blitz had a target earlier in the sequence, but that unit died before release so BetterBots aborted instead of using a stale aim point |
| `grenade soft-hold ignored after commit` | A grenade/blitz already reached the aimed-throw stage, so a revalidation `*_hold` rule was treated as transient density/context drift and the throw continued; hard `*_block_*` rules still abort |
| `grenade charge query failed for <grenade>` | The live ability extension threw while BetterBots queried grenade/blitz charges; Assail crowd bursts then fail closed as `charges unknown` |
| `grenade retained live precision target for <grenade>` | Precision blitz lost the live perception slot during the handoff but kept the already-resolved still-alive target instead of aborting immediately |
| `grenade burst unavailable for <grenade>` | A depletion-style Assail crowd burst was refused because the live shard count could not be resolved, so BetterBots failed closed instead of guessing |
| `grenade followup stopped at peril for <grenade>` | Assail or another multi-shot blitz stopped its followup chain because the configured shared warp peril line was reached |
| `grenade followup stopped at peril guard for <grenade>` | A multi-shot blitz stopped defensively because the peril stop line was armed but the live peril reading disappeared |
| `voidblast aim fallback` | `forcestaff_p1_m1` had a locked charge anchor but BetterBots had to fall back to vanilla aim because anchor resolution, target-velocity lookup, or direct-look rotation setup failed |
| `restored Voidblast locked target after vanilla _update_aim error` | BetterBots restored `perception_component.target_enemy` after a forced-target `forcestaff_p1_m1` `_update_aim` call threw |
| `voidblast charged fire override` | `forcestaff_p1_m1` forced the charged release input (`trigger_explosion`) even though vanilla was still on the non-ADS `shoot_pressed` path |
| `grenade deferred during active weapon charge` | Grenade fallback refused to interrupt an already-charging non-grenade weapon action, notably Voidblast staff `action_charge` |
| `patched poxburster breed` | Poxburster `not_bot_target` flag removed (#34) |
| `suppressed poxburster target_enemy (` | Bot cleared `target_enemy` when a poxburster was unsafe to shoot (#34) |
| `suppressed poxburster opportunity_target_enemy (` / `suppressed poxburster urgent_target_enemy (` / `suppressed poxburster priority_target_enemy (` | Bot cleared unsafe poxbursters from the secondary perception slots (#34) |
| `pushing poxburster (bypassed outnumbered gate)` | Bot forced the melee push path against a poxburster; key is per-bot via `scratchpad.unit` to avoid throttle collisions (#54) |
| `injected default bot_gestalts` | T5/T6 bot received killshot/linesman gestalts (#35) |
| `bot ADS confirmed (ranged_gestalt=` | Bot entered aim-down-sights with injected gestalt (#35) |
| `bot weapon: bot=` | Template-tagged queued weapon input for `#43` diagnosis; includes bot slot, wielded slot, weapon template, warp template, action, raw_input, target slot, target unit, target liveness, and target breed |
| `combat utility selected` | Debug-only `BtRandomUtilityNode` diagnostic for the bot `in_combat` selector; shows chosen branch/leaf (`combat/shoot`, `follow/successful_follow`, etc.), utility scores, target type/distance, ally distance, and current weapon so hesitation can be localized to utility choice vs action execution. The selector is weighted-random, so the highest utility score does not always win. No-target follow selections are intentionally suppressed, and repeated identical selection/target/weapon tuples are logged once per bot. |
| `stream action queued for` | Direct confirmation that a stream-specific queue input (`shoot_braced`, `trigger_charge_flame`, etc.) actually reached `bot_queue_action_input` successfully (#87) |
| `patched opportunity reaction times` | Human-likeness timing patch applied live (#44) |
| `HumanLikeness: BotSettings.opportunity_target_reaction_times is nil or missing .normal` | Human-likeness timing patch could not bind because the engine settings shape changed |
| `leash scaled` | Human-likeness pressure leash scaling fired in combat (#44) |
| `type flip ` | Target-type hysteresis allowed a real melee/ranged transition at the perception/math layer (#90) |
| `type hold ` | Target-type hysteresis actively suppressed a raw type flip at the perception/math layer (#90) |
| `close-range ranged family kept ranged target type` | Supported close-range ranged family overrode the normal melee fallback and kept the bot in ranged mode (#41 narrow) |
| `anti-armor ranged family kept ranged target type` | Mauler/Bulwark/Crusher target was kept ranged for an explicit anti-armor secondary family (plasma, bolter/bolt pistol, helbore, stub revolver, heavy stubber) despite vanilla `killshot`'s armored-elite ranged penalty (#92 validation path) |
| `anti-armor ranged target skipped` | Mauler/Bulwark/Crusher did not qualify for the anti-armor ranged lift; includes reason, secondary weapon resolution status, distance/min-distance, chosen type, and melee/ranged scores (#92 diagnostic path) |
| `close-range hipfire suppressed ADS` | Supported close-range ranged family stayed in hipfire instead of ADS inside the close-range window (#41 narrow) |
| `melee defend suppressed for attack commit` | BetterBots suppressed vanilla's broad melee block gate so the bot can commit attacks into a high-value armored target when only one or two melee attackers are registered and the current target is not actively attacking the bot |
| `melee special prelude queued before` | Melee special was armed before the chosen attack; the `(family=...)` suffix now distinguishes `powersword_1h`, `powersword_2h`, `forcesword_1h`, `forcesword_2h`, `thunderhammer`, `chain`, `combat_axe_special`, `combat_sword_special`, `combat_knife_jab`, `powermaul`, `ogryn_powermaul`, `ogryn_latrine_shovel`, `ogryn_club_uppercut`, `ogryn_club_fist`, `ogryn_pickaxe`, and `ogryn_combatblade_uppercut` |
| `melee direct special paced` | A direct sweep-style weapon special was still on BetterBots' per-bot reuse timer, so the chosen melee attack was left unwrapped instead of spamming another `special_action` |
| `armed shotgun special for` | Supported shotgun special-shell loader rewrote a queued fire input into `special_action`; line includes template, current target breed, bot slot, and the original fire input |
| `spent shotgun special for` | A previously armed supported shotgun later fired; line includes template, current spend-time target breed, bot slot, and fire input so wasted shells can be distinguished from good spends |
| `queued rippergun bayonet for` | Supported rippergun fire was rewritten into the close-range `stab` input; line includes template, current target breed, bot slot, and original fire input |
| `queued ranged bash for` | Supported close-range heavy-stubber/thumper, direct ranged bash, or pistol-whip fire was rewritten into a weapon-special input; line includes template, current target breed, bot slot, and original fire input |
| `suppressed opposite-type switch ` | BT-side debounce suppressed an immediate melee↔ranged reswitch after `wrong_slot_for_target_type` fired (#90) |
| `resolve_decision cache hit ` | Same-frame `Heuristics.resolve_decision(...)` reuse fired for a bot/template; direct runtime proof for the final `#82` BT↔fallback cache path |
| `weakspot aim selected` | Bot entered `BtBotShootAction` with the head/spine weakspot aim table active while the `Weakspot aim` feature was enabled (#91) |
| `normalized shoot scratchpad inputs` | `BtBotShootAction.enter` repaired stale/default fire, aim-fire, aim, or unaim inputs against the live wielded template before vanilla `_may_fire` validates them; for plasma, expect `fire=shoot_charge, aim_fire=shoot_charge` |
| `suppressed stale shoot aim input` / `suppressed stale shoot unaim input` | `BtBotShootAction` tried to carry old ADS inputs onto a live non-aim weapon after a weapon/context change; BetterBots suppressed the stale queue instead of relying on the parser drop guard |
| `plasma _may_fire blocked` | Plasma was selected for `combat/shoot`, but vanilla `_may_fire` refused to queue `shoot_charge`; includes the first block reason per scratchpad (`obstructed`, `aiming`, `range`, `invalid_input`, etc.) |
| `fixed_time unavailable during bootstrap` | `_fixed_time()` is intentionally returning `0` during bootstrap because the extension manager is not ready yet; one-shot breadcrumb, not a failure |
| `shoot scratchpad normalization skipped` | Bot shoot-action enter hook could not see `unit_data_system` or `visual_loadout_system`; #43 diagnostics are incomplete for that unit |
| `shoot scratchpad normalization skipped for` | One-shot warning counterpart to the debug line above; emitted even with debug logs off so operators can still see why `#43` diagnostics were incomplete |
| `bt_bot_shoot_action hook_require resolved nil` | Abnormal delayed-hook install failure for `BtBotShootAction`; shoot-action diagnostics/hooks are suspect until this is explained |
| `ammo utility unavailable; dead-zone ranged fire detection disabled` | `scripts/utilities/ammo` failed to load, so the dead-zone ranged-fire confirmation log for `#51` is unavailable in this session |
| `ammo pickup success` | Actual pickup interaction completed and bot ammo reserve increased; stronger than `ammo pickup permitted` |
| `grenade pickup permitted: all eligible humans above reserve` | BetterBots reserved a world grenade pickup for the bot because no eligible human grenade user was below reserve; one-shot per bot+pickup reservation episode |
| `grenade pickup bound into ammo slot` | BetterBots attached the reserved world grenade pickup to the ammo-pickup fields so vanilla interaction code can collect it; one-shot per bot+pickup reservation episode |
| `grenade pickup deferred to human reserve` | Bot yielded a nearby world grenade pickup because at least one eligible human grenade user was below reserve; one-shot per bot+pickup defer episode |
| `grenade pickup skipped: ability does not use grenade pickups` | Equipped blitz replenishes via cooldown/passive logic instead of world grenade pickups; one-shot per bot+equipped ability state |
| `grenade pickup skipped: cooldown-based blitz` | Blitz has no grenade charges at all, so world grenade pickup logic does not apply; one-shot per bot+equipped ability state |
| `grenade pickup skipped: no ability extension` | Grenade refill logic could not resolve the bot's `ability_system`; grenade reserve policy did not run |
| `ammo policy skipped: no pickup_component` | `_update_ammo` ran on a bot without a pickup component; ammo/grenade pickup policy did not run for that tick |
| `grenade pickup success` | Actual pickup interaction completed and bot grenade charges increased |
| `grenade blocked during <stage> by <ability> <reason>` | Grenade fallback hit the shared BetterBots slot-lock fast retry instead of idling into a wield timeout |
| `grenade deferred during active weapon charge` | Grenade fallback saw a non-grenade charged weapon action in progress and skipped starting a new grenade/blitz sequence for that tick |
| `grenade held <grenade> (rule=*_block_recent_use` | Non-explosive reuse pacing suppressed a second fire/smoke-style grenade too soon after the last confirmed spend |
| `fallback item blocked <ability> (slot locked by <ability> <reason>)` | Item fallback hit the same shared slot-lock fast retry path |
| `blackboard utility unavailable; mule pickup destination refresh skipped` | Mule live-destination refresh could not load the blackboard helper; reservation metadata patching still ran, but destination refresh became a no-op for that session |
| `battle cry request noted` / `need ammo request noted` / `need health request noted` | Communication-wheel bridge cached a short-lived aggressive override or human-priority resource request |
| `smart-tag pickup routed` / `smart-tag pickup ignored` | Explicit item tag was accepted or rejected after BetterBots reused its normal pickup policy gates; `reason=no_eligible_bot` lines can now include per-bot `detail=bot=<slot>:<reason>` suffixes |
| `queued pocketable wield` / `queued pocketable input` | Carried pocketable state machine advanced into wield/use |
| `pocketable use completed` / `pocketable ended without confirmation` / `pocketable timed out waiting for consume|wield` | Pocketable follow-through either finished, ended ambiguously, or stalled |
| `sprint START/STOP` | Bot sprint state change — only logged for catch_up, ally_rescue, daemonhost_nearby (#36) |
| `hazard_prop triggered` | A fused hazard prop entered vanilla's triggered state; line compares the vanilla AoE threat origin (`POSITION_LOOKUP`) against the broadphase and `c_explosion` positions, plus radius/timer (#107) |
| `hazard_prop buffered threat` | BetterBots emitted an extra buffered AoE threat from the barrel `c_explosion` node when available (#107) |
| `aoe_threat accepted` / `aoe_threat skipped` / `aoe_threat missed` | Vanilla `BotGroup.aoe_threat_created` result per bot. `accepted` means an escape direction was stored, `skipped` means an existing later threat won, and `missed` means vanilla did not store a usable escape direction (#107) |
| `aoe_threat consumed` | `BotUnitInput._update_movement` actually consumed a stored AoE threat and wrote the movement vector; use this to separate threat creation from movement execution (#107) |
| `movement safety blocked` | BetterBots cancelled a pending dodge whose projected endpoint failed nav continuity or dropped too far, used mainly for ledge safety (#107). Logged once per bot/reason per load. Ordinary movement fails open because stairs/downhill pathing can look like a ledge in the coarse endpoint probe. |
| `movement safety steered away from daemonhost` | A bot inside the tighter daemonhost movement radius had movement biased away from a non-aggroed daemonhost (#107/#17). Logged once per bot/strength bucket per load and includes `bucket=<soft|medium|firm>` plus `strength=<N>`. The configurable keepout radius still controls risky action suppression. |
| `daemonhost scan source` / `daemonhost scan candidate` | Trace-only scanner diagnostics for passive/awake daemonhost detection. Source lines show the first observed list size per source; candidate lines show breed, liveness, aggro state, stage, position availability, accepted flag, and rejection reason. |
| `target near daemonhost scan` | Debug-only diagnostic emitted once per bot+target+daemonhost+range bucket when the bot has a current target and BetterBots can see a non-aggroed daemonhost; use it to prove the detector saw the daemonhost even if no suppression fired yet (#17/#107) |
| `skipped ping for <target> (reason: recent_companion_tag)` | Generic pinging backed off because an Arbites bot had just issued a mastiff smart-tag on the same target; use this when checking remaining tag-spam reports |
| `ranged suppressed (daemonhost nearby)` | Close-range daemonhost safety gate fired; bot was inside the tight daemonhost combat radius and refused ranged fire (`#17`). Mixed-target melee is still allowed; direct dormant daemonhost targets still log `melee suppressed (target is dormant daemonhost...)`. |
| `melee suppressed (target is dormant daemonhost, target=<breed> stage=<N> aggro_state=<state> dormant=<bool>)` / `ranged suppressed (...)` | Non-aggroed daemonhost target suppression fired outside the proximity gate; stage-aware when daemonhost `stage` is available, otherwise falls back to `aggro_state` (`#17`) |
| `ranged suppressed (target near dormant daemonhost)` | Bot refused ranged fire at a non-daemonhost target whose position was inside the dormant daemonhost keepout zone (`#17/#107`) |
| `fallback blocked <charge_template> (charge_nav=daemonhost_target_near)` | Charge/dash nav validation refused a launch endpoint inside the dormant daemonhost keepout zone (`#17/#107`) |
| `blocked foreign weapon action <input> while keeping daemonhost_avoidance target=<breed> stage=<N> aggro_state=<state> dormant=true` | Central `weapon_action` queue guard suppressed direct ranged/melee/grenade inputs against a non-aggroed daemonhost target (`#17`) |
| `ability allowed against daemonhost: <ability> (rule=<rule>, target=<breed> stage=<N> aggro_state=<state> dormant=<bool>)` | Ability activation was allowed against a daemonhost; use this with first-action timestamps to distinguish legitimate aggroed fights from dormant misclassification (`#17`) |
| `skipped ping for chaos_daemonhost (reason: dormant_daemonhost)` / `skipped companion tag for chaos_daemonhost (reason: dormant_daemonhost)` / `skipped player-tag boost for chaos_daemonhost (reason: dormant_daemonhost)` | Stage-aware daemonhost avoidance suppressed pinging, mastiff smart-tagging, or human-tag score boosts on a non-aggroed daemonhost (#17) |
| `shield (` / `escort (` | Ally detected in objective interaction — the full line is `<profile> (<interaction_type>) dist=<N>`. Key: `interaction_scan:<unit>`, 5s throttle (#37) |
| `revive candidate observed: <ability> (template=<template>, need_type=<type>)` | Bot selected a rescue destination while carrying a defensive revive ability, before `BtBotInteractAction.enter`. Use this to tell selector/path misses from interact-hook misses. Key: `revive_candidate:<ability>:<unit>` (#7) |
| `revive ability queued: <ability> (interaction=<type>, enemies=<N>)` | Bot fired a defensive ability before starting a rescue interaction. Key: `revive_ability:<ability>:<unit>` (#7) |
| `revive ability skipped (` | Rescue-interaction diagnostics. The throttle key encodes the reason, but the emitted line is always a human-readable `[Bot <slot>] revive ability skipped (...)`. |
| `cleared stale mule pickup ref` | Deleted mule/grimoire pickup ref was sanitized without crashing; source path in message shows which cache/blackboard field was cleaned |

**Preferred: use `bb-log`** (project root):
```bash
bb-log summary        # one-shot overview: counts + top rules + top holds
bb-log activations    # raw fallback queued + charge consumed lines
bb-log rules          # activation counts by rule + consume counts by ability
bb-log holds          # non-idle hold rules (nearby > 0)
bb-log errors         # Script Error / Lua Stack / Crash lines
bb-log tail           # real-time monitoring (grep BetterBots + errors)
bb-log list           # show 10 most recent log files with indices
bb-log raw <pattern>  # arbitrary rg pattern against log
bb-log <cmd> 1        # use second-latest log (0=latest, default)
bb-log events summary # JSONL: event counts + approval rate + per-bot consumes
bb-log events rules   # JSONL: true/false decision counts by ability+rule
bb-log events trace N # JSONL: timeline for bot slot N
bb-log events holds   # JSONL: false decision distribution
bb-log events items   # JSONL: item stage transitions + blocks
bb-log events scenarios  # JSONL: /bb_scenario start/spawn/result rows
bb-log events raw 'jq-filter'  # JSONL: raw jq passthrough
```

For recurring "check for regressions" requests and major-release log reviews,
use `docs/dev/core-regression-checks.md` as the checklist.

**Manual grep recipes** (if bb-log unavailable):
```bash
LOG_DIR="/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"
LATEST=$(ls -1t "$LOG_DIR"/console-*.log | head -n 1)

# Activations only
rg "fallback queued|charge consumed" "$LATEST"

# Active holds (combat, not idle)
rg "fallback held" "$LATEST" | grep -v "nearby=0)"

# Errors only
rg "Script Error|Lua Stack" "$LATEST"
```

**Common mistakes:**
- Do **not** grep `_debug_log` throttle keys like `target_type_flip:<unit>` or `human_likeness_patch`. `_debug_log` prints only the human-readable message, not the key.
- Do **not** grep for `"decision:"` — that pattern doesn't exist in the log. The `"-> true"` pattern does appear in debug decision lines (e.g. `decision veteran_combat_ability -> true (rule=...)`). For activation evidence, prefer `"fallback queued"` / `"charge consumed"` which are unambiguous.

## Current BetterBots debug pattern

```lua
-- Throttled logging gated by mod setting
_debug_log(key, fixed_t, message, min_interval_s, level)
```

- Gated by `enable_debug_logs` mod setting (dropdown: Off / Info / Debug / Trace)
- Omitted `level` defaults to `debug`
- Throttled to 2s per unique key (avoids spam)
- Outputs to chat via `mod:echo("BetterBots DEBUG: " .. message)`

### Runtime commands in BetterBots

These are implemented and intended for targeted diagnostics, not constant spam.

1. `/bb_state`
   - Shows each bot's current ability, cooldown, and fallback state on one line.
   - Includes current template, charges, cooldown, active flag, wielded slot, fallback stage, retry timer, and last charge age.
   - Use this first when something looks off.
2. `/bb_decide`
   - Shows whether each alive bot would use its ability right now, without actually triggering it.
   - Includes the current decision (`true/false`) and rule for each bot.
   - Context snapshots include `target_ally_need_type`, which separates hard disables (`knocked_down`, `ledge`, `netted`, `hogtied`) from soft heal/attention states. Rescue movement and support rules should not spend cooldowns on soft aid alone.
   - Best for threshold tuning or "why didn't it cast?" questions.
   - Do **not** run after every successful cast; run around suspected misses or surprising behavior.
3. `/bb_brain`
   - Writes a deeper bot snapshot to the log via `mod:dump()` (context + selected perception + fallback state).
   - Use only when `/bb_state` + logs are insufficient.
4. `/bb_perf`
   - Shows and resets the current runtime timing window when `Performance timings` is on.
   - Reports total `µs/bot/frame` plus a per-hook breakdown for instrumented BetterBots callbacks.
   - `GameplayStateRun` exit also auto-emits the same report to the console log with `bb-perf:auto:` prefixes, but only when the recording window contains at least one sampled bot frame. Hub-only `GameplayStateRun` transitions are intentionally suppressed so starting a mission does not produce meaningless `0 bot frames` dumps.
   - `ability_queue` now exposes breakdown-only rows for `item_fallback`, `template_setup`, `input_validation`, `decision`, and `queue`; `grenade_fallback` now exposes `stage_machine`, `profile_resolution`, and `launch` in addition to the existing `build_context` and `heuristic` rows.
   - `grenade_fallback` has two breakdown-only sub-tags that partition its idle-path cost: `grenade_fallback.build_context` (the `heuristics.build_context` call in `grenade_fallback.lua`) and `grenade_fallback.heuristic` (the subsequent `evaluate_grenade_heuristic` call). They appear as rows in the tag breakdown but do not contribute to the headline `µs/bot/frame` total because the parent `grenade_fallback` timer already includes them.
   - `target_type_hysteresis.post_process` now appears as a breakdown-only row for the post-vanilla melee/ranged stabilization pass.
   - Do not compare arbitrary mid-mission `/bb_perf` dumps across branches. The command resets the window. For release/perf decisions, compare only mission-end `bb-perf:auto:` totals captured from real missions under the same protocol.
5. `/bb_reset`
   - Resets all BetterBots settings to their defaults and saves them when the DMF save hook is available.
   - Each `mod:set` is `pcall`-wrapped, so a failure on one setting does not abort the loop. On any failure the echo reads `"BetterBots: reset partially failed: <id (err), ...>"`; clean success echoes `"BetterBots: all settings reset to defaults"`.
   - Reopen the mod settings menu if the UI does not immediately redraw after the reset.
6. `/bb_scenarios`, `/bb_scenario <name> [distance] [count]`, and `/bb_scenario_clear`
   - Lists and runs scripted validation spawns for live Solo Play testing.
   - Built-in scenarios: `poxburster_push`, `crusher_pack`, `mauler_weakspot`, `mixed_horde_pressure`, `daemonhost_passive_near`, `daemonhost_aggroed_control`.
   - Optional `distance` overrides the forward spawn distance in meters; optional `count` repeats each scenario spawn and spreads copies sideways. `mixed_horde_pressure` caps repeat count at 2 because its base composition is already 20 spawned units.
   - `poxburster_push` spawns near the first live bot and targets that bot when possible; if no live bot can be resolved, it falls back to the local player.
   - `mixed_horde_pressure` spawns trash, melee, Maulers, a gunner, and a grenadier to exercise ability triggers, grenade/blitz targeting, melee specials, target-type hysteresis, and perf under realistic clutter.
   - `daemonhost_passive_near` spawns `chaos_daemonhost` with `optional_aggro_state = "passive"` and no forced target; use it for `#17` dormant-classifier validation. Useful detection/suppression markers are `daemonhost scan source`, `daemonhost scan candidate`, `target near daemonhost scan`, `movement safety steered away from daemonhost`, `skipped ping for chaos_daemonhost (reason: dormant_daemonhost)`, `melee/ranged suppressed (... daemonhost ... dormant=true)`, `ranged suppressed (target near dormant daemonhost)`, `fallback blocked <charge_template> (charge_nav=daemonhost_target_near)`, `blocked foreign weapon action ... daemonhost_avoidance ... dormant=true`, and `daemonhost_nearby_target`; `ability allowed against daemonhost ... dormant=false` before real aggro is the failure marker.
   - `daemonhost_aggroed_control` spawns an aggroed daemonhost targeting the player; use it as the control case proving BetterBots still allows legitimate daemonhost combat once aggro is real.
   - `/bb_scenario_clear` despawns units created by the scenario harness via `MinionSpawnManager:despawn_minion`.
   - Scenario start/spawn/result rows go to JSONL with requested and resolved distance/count fields and are summarized by `bb-log events scenarios`.

### Practical debug workflow

1. Observe behavior in mission.
2. If behavior looks correct, continue without commands.
3. If behavior looks wrong, run `/bb_state`.
4. If decision logic is unclear, run `/bb_decide` once around the event.
5. If still unclear, run `/bb_brain` once and inspect the dump.
6. Correlate with log lines (`fallback held/queued`, `charge consumed`, `invalid action_input`).

### Perf benchmark protocol (v1.0.0)

Use this protocol for any claim that BetterBots got faster, slower, or is "good enough":

1. Cold boot Darktide. Do not rely on hot-reload.
2. Run Solo Play with a full 4-bot squad on the build you want to measure.
3. Turn on only `Performance timings`. Leave JSONL event logging off and do not run an active debug session that intentionally increases BetterBots logging/work.
4. Play **three** combat-heavy live missions. Ignore hub transitions and ignore ad hoc mid-mission `/bb_perf` snapshots.
5. For each run, record only the mission-end `bb-perf:auto: <N> µs/bot/frame total` line from the raw console log.
6. Use the **median of three** as the headline number. A single run is a spot check, not a benchmark.

v1.0.0 acceptance bar:

- Current validated reference band: `104.9`, `113.8`, and `124.5 µs/bot/frame total`
- Acceptable for release: **median <= `125 µs/bot/frame`** and **no single run > `140 µs/bot/frame`**
- The old `<80 µs/bot/frame` target is retired. It was never tied to a stable mission protocol and is not a credible release gate.

If a future branch misses that bar or produces a real user-visible perf complaint, inspect the dominant buckets first: `ability_queue.decision`, `grenade_fallback`, `sprint.update_movement`, and `ammo_policy.update_ammo`.

### Pre-release verification (required before `make release`)

Static checks (`make check`) and hot-reload testing (`Ctrl+Shift+R`) do **not** surface hook-registration issues, load-order crashes, or DMF warnings. A clean test run is not sufficient to ship to Nexus.

1. **Cold boot** — fully quit Darktide and relaunch. Do not rely on a hot reload.
2. **Run a mission** — booting to the hub is not enough; at least one mission load exercises the full hook chain.
3. **Test both mod load orders** when the change touches shared engine tables (`attack_meta_data`, `ability_meta_data`, breed data). Run once with BetterBots near the top of `mod_load_order.txt` and once with it near the bottom. Sibling mods that pre-mutate shared state (Tertium4Or5, SoloPlay) can mask or reveal crashes depending on order.
4. **Check BetterBots events and warnings**: `./bb-log summary` — verify expected activations, `Error lines: 0`, and `BB warnings: 0`. The summary now includes a DMF warning counter (rehook attempts, hook install failures) and prints a breakdown when non-zero. For more detail: `./bb-log warnings`.
5. Only after both load-order sessions are clean, run `make release VERSION=X.Y.Z` and push to Nexus.

The v0.11.0 release shipped a startup CTD (`ranged_meta_data.lua: attempt to index local 'original_fields'`) that passed all static checks and reproduced only with BetterBots loaded before the sibling mod that pre-set `attack_meta_data`. Dev-side load order masked it. Steps 3 and 5 catch this class of bug.

### Grenade regression shortcut

For item-based grenade regressions, check the grenade state-machine phases before blaming aim, gravity, or heuristics:

1. `grenade queued wield for <grenade>` appears:
   - sequence started, but nothing is proven yet.
2. `grenade wield confirmed, waiting for aim` appears:
   - grenade slot swap succeeded; only **after this** is it reasonable to suspect aim/ballistic logic.
3. `grenade queued <aim_input> for <grenade>` / `grenade releasing toward ...` appears:
   - aim/release phase actually ran.
4. `grenade charge consumed for <grenade>` appears:
   - authoritative success for item-based grenades.

If you instead see repeated `grenade queued wield for <grenade>` plus `blocked foreign weapon action grenade_ability while keeping <grenade> wield`, with no `grenade wield confirmed, waiting for aim`, the blocker is killing the initial `grenade_ability` queue during the grenade `wield` stage. That is a sequence-allowlist bug, not an aim bug.

### Reading context dumps (deep verification)

When debug logging is enabled, BetterBots emits a **one-shot context dump** the first time each ability template is activated in a session. These are written via `mod:dump()` (table → log) and contain the full decision context at the moment of activation.

**What to look for in a dump:**

| Field | Meaning | Trust level |
|-------|---------|-------------|
| `rule` | Which heuristic branch fired (e.g. `ogryn_gunlugger_high_threat`) | High — directly from code |
| `activation_input` | The action_input queued (e.g. `stance_pressed`) | High |
| `challenge_rating_sum` | Aggregate threat score from perception | High — use for tuning |
| `num_nearby` / `elite_count` / `special_count` | Threat composition | High |
| `target_enemy_distance` | Distance to selected target | High |
| `health_pct` / `toughness_pct` / `peril_pct` | Bot survival state | High |
| `target_enemy` | Breed name of selected target | **Medium** — can disagree with aggregates (see below) |
| `target_enemy_type` | `melee` or `ranged` classification | **Medium** — same caveat |

**Perception field inconsistency:** `target_enemy` and `target_enemy_type` reflect the bot's *selected* target (single unit from the BT targeting system), while `challenge_rating_sum`, `num_nearby`, and type counts reflect the *broadphase proximity scan* (all enemies within range). These two sources can disagree — e.g. a poxwalker may be the selected target while the aggregate CR and type counts reflect a nearby Chaos Ogryn. When tuning heuristics, **trust the aggregate fields over the single-target label**.

**Verification workflow with dumps:**

1. Enable debug logging in mod settings.
2. Play through combat encounters.
3. After the session, grep for `one-shot context dump` to find dump entries.
4. For each dump, find the matching `fallback queued` (activation) and `charge consumed` (confirmation) lines nearby in the log.
5. Check whether the `rule` and context fields match what you'd expect for that combat situation.
6. If they don't match, the heuristic thresholds may need tuning — the dump gives you the exact values to adjust against.

## Automated testing

### What's testable outside the game

The sub-module split (`heuristics.lua` dispatcher, `heuristics_context.lua`, the career-specific `heuristics_*.lua` files, `meta_data.lua`, `event_log.lua`, etc.) created clean test seams. The 18 `_can_activate_*` heuristic functions (14 combat + 4 item) are **pure functions** — they take a context table and return `(bool, string)` with zero engine dependencies. The `evaluate_heuristic(template_name, context, opts)` public API exposes them for testing without the ugly internal 10-param dispatch signature. The `event_log` module is independently testable (buffer, flush, lifecycle, false-decision compression).

### Test structure

```
tests/
  test_helper.lua           # make_context(), mock factories, engine stubs
  heuristics_spec.lua       # all 18 heuristic functions (14 combat + 4 item)
  meta_data_spec.lua        # injection, overrides, idempotency
  resolve_decision_spec.lua # centralized nil→fallback paths
  event_log_spec.lua        # buffer, flush, lifecycle, false-decision compression
  sprint_spec.lua           # sprint conditions + daemonhost safety
  target_selection_spec.lua # melee target distance penalty
```

### Running tests

```bash
make tool-info # shows the exact wrappers/binaries this repo will use
make test      # runs busted, lua-busted, or Arch's luarocks path
make check     # auto-formats, then runs lint + lsp + test + doc-check
make check-ci  # non-mutating CI gate: format-check + lint + lsp + test + doc-check
```

`make lint` uses the repo-local `bin/luacheck` wrapper. `make test` does not
depend on shell `PATH` mutation; it falls back to Arch's packaged luarocks
runner when `busted` is not installed globally.

Tests are enforced by CI — `make check-ci` depends on `test`, and CI installs
busted via luarocks.

### Engine stubs

Phase 1 tests need no engine stubs for the pure heuristic functions. The `resolve_decision` tests use a minimal `ScriptUnit` stub (returns nil for all extensions, so `build_context` produces default zeros). See `test_helper.setup_engine_stubs()`.

### Mock fidelity rule

`ScriptUnit.has_extension()` / `ScriptUnit.extension()` test doubles must match the real engine extension class for the unit type under test. Do not give minion/enemy units player-only methods just because the code path is convenient to test.

Verified from decompiled source:

| Extension system | Player API used by BetterBots | Minion API used by BetterBots | Gotcha |
|---|---|---|---|
| `unit_data_system` | `PlayerUnitDataExtension:read_component()` | `MinionUnitDataExtension:breed()`, `faction_name()`, `is_companion()`, `breed_name()`, `breed_size_variation()` | Minions do **not** have `read_component()` |
| `locomotion_system` | `PlayerUnitLocomotionExtension` (player movement internals) | `MinionLocomotionExtension:current_velocity()` | Prefer the exact method the production code calls; do not invent shared component access |

Practical rule:

- Player/bot self units: use player-style `unit_data_system` mocks with `read_component()`.
- Enemy/minion targets: use minion-style `unit_data_system` mocks with `breed()` and no `read_component()`.
- If a code path can handle both, test both paths explicitly.
- Prefer shared builders in `tests/test_helper.lua` over ad-hoc extension tables so impossible method combinations stay impossible in tests too.
- `scripts/doc-check.sh` now fails CI if audited `ScriptUnit` extension families reappear as raw table literals in specs.
- Full audited surface and source-line evidence live in `docs/dev/mock-api-audit.md`.

## What CANNOT be tested outside the game

- Ability actually firing (engine input queue → ActionInputParser → ability system)
- Timing behavior (hold durations, frame-dependent sequences)
- Tier 3 item-ability state machine (weapon extension state, action transitions)
- BT node priority evaluation (full behavior tree context)
- Multiplayer state (not applicable — Solo Play only)

For these, use the existing manual verification workflow: launch game → observe → check logs → update `docs/dev/validation-tracker.md`.

## Fatshark's Testify framework

Darktide has a built-in coroutine-based test framework (`scripts/foundation/utilities/testify.lua`) with bot-specific helpers (`bot_manager_testify.lua`). Features: async test execution, request/response pattern, `TestifyExpect` assertions.

**Not accessible to modders** — requires `GameParameters.testify` launch flag and an external test runner that Fatshark hasn't published. But the architecture (coroutine-based, polling between frames) could be replicated within a mod for integration tests.
