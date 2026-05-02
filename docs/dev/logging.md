# Logging and Diagnostics

## Output channels

BetterBots logs with `mod:echo(...)`. DMF controls where those lines go:

- chat only
- log only
- chat + log
- disabled

Use DMF `Logging Mode = Custom` and set `Echo` to `Log` or `Log & Chat`.

## Log file locations

### Windows

`C:\Users\<your-user>\AppData\Roaming\Fatshark\Darktide\console_logs\console-*.log`

### Linux (Steam Proton, this setup)

`/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/console-*.log`

## Timestamp timezone

Darktide console logs use **UTC timestamps** (`UTC time stamps` header in the log file).

If your system clock is local time (for example `CET`/`CEST`), log times will be offset by your current timezone difference:
- `CET` (winter): local = log + 1h
- `CEST` (summer): local = log + 2h

When comparing in-game events with system time, convert to UTC or account for the offset first.

## Practical workflow (learned during debugging)

1. You can read logs while still in mission; quitting game is not required.
2. Always confirm you are reading the newest `console-*.log`.
3. Toggling a DMF setting only affects runtime after reload.
4. `Ctrl+Shift+R` hot reload requires DMF dev mode enabled.
5. If `DEBUG_FORCE_ENABLED = true` in `BetterBots.lua`, debug lines appear regardless mod setting.
6. When `enable_perf_timing` is on, leaving `GameplayStateRun` auto-emits a `bb-perf:auto:` summary and per-tag breakdown to the console log only if the current recording window contains sampled bot frames. Hub-only transitions are suppressed.

## Useful commands

```bash
LOG_DIR="/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"
LATEST=$(ls -1t "$LOG_DIR" | head -n 1)
rg -n "BetterBots|\\[MOD\\]\\[BetterBots\\]" "$LOG_DIR/$LATEST"
```

Follow live updates for the active file:

```bash
tail -f "$LOG_DIR/$LATEST" | rg --line-buffered "BetterBots|\\[MOD\\]\\[BetterBots\\]"
```

## Key BetterBots log lines

- `BetterBots loaded`
- `BetterBots DEBUG: logging enabled (level=<debug|trace>)` (`startup:logging`; only appears when debug logs are set to `Debug` or `Trace`)
- `BetterBots DEBUG: fixed_time unavailable during bootstrap; using 0 until extension manager is ready` (one-shot bootstrap breadcrumb from `_fixed_time()`; expected only before `Managers.state.extension.latest_fixed_t` is live)
- `BetterBots DEBUG: settings: preset=..., sprint_dist=..., chase_range=..., tag_bonus=..., horde_bias=..., smart_targeting=..., dh_avoidance=...` (`startup:settings`; concise startup summary, intentionally not a full config dump)
- `patched <bt_bot_conditions|bt_conditions>.can_activate_ability (version=<N>)` (startup patch confirmation for the condition hooks)
- `ability template metadata patch installed (version=<N>, injected=<N>, overridden=<N>)` (startup debug/info confirmation that the ability template metadata patch ran)
- `installed consolidated bt_bot_melee_action hooks (melee_attack_choice, poxburster, engagement_leash)` (startup debug/info confirmation that the shared melee hook callback installed)
- `installed BtBotInteractAction.enter hook` (startup debug/info confirmation for the defensive pre-revive hook)
- `entered GameplayStateRun`
- `bb-perf:auto: ...` (automatic mission-end / quit perf dump; same payload as `/bb_perf` but tagged separately for grepability; omitted when the window contains `0 bot frames`)
- `blocked lossy network-sync profile overwrite` (issue `#65` guard fired; the first lossy `BotPlayer.set_profile` sync was dropped on purpose)
- `allowed profile update (no _bb_resolved sentinel)` (the `BotPlayer.set_profile` hook passed through because the one-shot sentinel was absent or already consumed)
- `preserving external profile for bot slot <N> (character_id=<id>)` (BetterBots yielded to a real Tertium/SoloPlay profile instead of overwriting it; direct validation signal for `#68`)
- `decision ... -> true` (BT condition path activation — includes `hazard=<true|false>` in the debug line)
- `enter ability node ...`
- `fallback queued ...` (template fallback queued)
- `fallback held ...` (heuristic withheld ability — only logged when `num_nearby > 0`)
- `fallback blocked ...` (template fallback rejected)
- `fallback item queued ... (rule=...)` (item fallback queued wield/cast/unwield input with triggering rule)
- `fallback item blocked ...` (unsupported template, no wield input, timeout, etc.)
- `charge consumed for ...` (ability charge spent, strongest success signal)
- `grenade queued wield for <grenade> (rule=<rule>)` (grenade fallback started a throw sequence)
- `grenade held <grenade> (rule=<rule>, nearby=<N>, distance=<d|none>, challenge=<N>, elites=<N>, specials=<N>, monsters=<N>, breed=<breed|none>, peril=<N|nil>)` (grenade/blitz heuristic withheld use for an actionable reason; `rule=*block_recent_use` is the confirmation signal for the non-explosive reuse pacing gate on fire/smoke-type grenades)
- `unsupported grenade template <grenade> (rule=<rule>)` (heuristic approved a grenade/blitz template that BetterBots has no throw profile for)
- `grenade queued <input> for <grenade>` (grenade fallback advanced through the named throw/blitz input; use this to distinguish Assail `zoom`/`zoom_shoot` from the crowd-burst `shoot` path)
- `grenade aim ballistic for <grenade>` / `grenade aim flat fallback for <grenade> (<reason>)` / `grenade aim unavailable for <grenade> (<reason>)` (aim solver confirmation for ballistic vs flat vs failed aim acquisition; debug lines include `bot=`, `target=`, `target_alive=`, `target_alive_source=`, and `target_breed=`)
- `grenade aim lost dead target for <grenade>` (the sequence had a target during approval or handoff, but that unit died before release so BetterBots aborted instead of throwing at a stale position)
- `grenade charge query failed for <grenade> (<error>)` (BetterBots could not read grenade/blitz charges from the live ability extension; Assail crowd bursts will then fail closed as `charges unknown`)
- `grenade retained live precision target for <grenade>` (precision blitz temporarily lost the perception slot after approval, but BetterBots kept the already-resolved still-alive target through the handoff instead of aborting immediately)
- `grenade burst unavailable for <grenade> (charges unknown)` (a depletion-style Assail crowd burst was refused because BetterBots could not confirm the remaining shard count; fail-closed guard against fake one-shot "bursts")
- `grenade releasing toward <unit> via <input> (dist_bucket=<close|mid|far|unknown>)` (throw release with resolved aim target; primary validation signal for aimed grenade/blitz releases; includes the same target identity suffix as aim logs)
- `grenade wield confirmed, waiting for aim` (item grenade actually swapped to `slot_grenade_ability`; this is the visible success signal the docs previously referred to as `grenade_wield_ok`)
- `grenade charge consumed for <grenade> (charges=<N>)` (grenade actually spent a charge; strongest throw confirmation)
- `grenade followup stopped at peril for <grenade> (<peril>)` (multi-shot blitz followup chain stopped because the configured shared warp peril line was reached; direct confirmation for Assail burst stop logic)
- `grenade followup stopped at peril guard for <grenade> (peril unavailable)` (multi-shot blitz followup chain stopped defensively because the shared peril guard was armed but the live peril reading disappeared)
- `voidblast aim fallback (reason=<reason>, bot=<unit>, target=<unit>)` (`forcestaff_p1_m1` had a live charge anchor but BetterBots could not build the override rotation or anchor state, or the anchor target's velocity lookup became unsafe, so `_wanted_aim_rotation` fell back to vanilla aim)
- `restored Voidblast locked target after vanilla _update_aim error (bot=<unit>, target=<unit>)` (`forcestaff_p1_m1` temporarily forced `perception_component.target_enemy`, vanilla `_update_aim` threw, and BetterBots restored the shared target state before rethrowing)
- `voidblast charged fire override (fire=shoot_pressed -> charged_fire=trigger_explosion)` (`forcestaff_p1_m1` charged-fire dispatch corrected a live non-ADS path before `_fire()` queued the actual release input)
- `grenade queued unwield_to_previous after charge confirmation` (BetterBots started explicit post-throw cleanup for bots)
- `grenade throw complete, slot returned to <slot>` (grenade fallback reached cleanup success: the bot left `slot_grenade_ability` and BetterBots reset the sequence with `reason = "slot_returned"`; this does **not** prove the projectile hit anything, and it is weaker than `grenade charge consumed` for confirming a spent throw)
- `grenade forced unwield_to_previous on timeout` (cleanup fallback; indicates normal post-throw unwind did not complete)
- `grenade released cleanup lock without explicit unwield (charge confirmed|timeout)` (templates such as Psyker blitz unwind via normal `wield`, not `unwield_to_previous`)
- `grenade released cleanup lock without explicit unwield (action confirmed)` (external cleanup templates saw their target action, so BetterBots ends the protected sequence immediately)
- `grenade released cleanup lock without explicit unwield (slot changed)` (external cleanup templates left grenade slot through the engine's normal unwind; BetterBots treats that as success)
- `grenade external action confirmed for <grenade> (action=<action_name>)` (non-charge blitz confirmation; useful for Psyker Chain Lightning charged-path validation)
- `ability blitz activated <grenade> on <component> (rule=<rule>) ...` (ability-based blitz path fired directly on the action component instead of through grenade-slot wield)
- `ability blitz complete (charge confirmed|timeout) ...` (ability-based blitz path reached its terminal confirmation or timeout)
- `grenade deferred while unarmed (slot=<slot>, template=<template>)` (grenade fallback refused to start because the bot was currently unarmed)
- `grenade deferred during active weapon charge (weapon=<template>, action=action_charge)` (grenade fallback refused to interrupt a non-grenade charged weapon action such as Voidblast staff charging)
- `grenade blocked during <stage> by <ability> <reason> (held_slot=<slot>)` (grenade fallback hit the shared BetterBots slot-lock fast retry instead of waiting out a full wield timeout)
- `smart targeting using bot perception target <unit> (already_seeded=<true|false>)` (bot smart-target hook ran and fed the precision-target module a concrete target; direct validation signal for `#61`)
- `post-charge grace started (4s)` (engagement leash recorded a movement-ability charge and started the temporary 20m grace window for that bot)
- `restored engagement leash overrides after vanilla error` (the `_allow_engage` hook restored shared singleton state before rethrowing; direct failure-path validation signal for `#73`)
- `restored engagement range after vanilla error` (the `_is_in_engage_range` hook restored shared singleton state before rethrowing; direct failure-path validation signal for `#73`)
- `ranged dead-zone override kept normal shot (ammo=<0.xx>, target=<breed>, weapon=<template>, action=<input>)` (bot fired a normal ranged shot while reserve ammo was in the old 20%-50% dead zone; direct validation signal for `#51`)
- `ranged ammo gate lowered from 0.5 to <threshold>` (BetterBots rewrote the vanilla ranged-ammo condition to the configured threshold; setup signal for `#72`)
- `ranged permitted with lowered ammo gate (threshold=<threshold>)` (bot passed the vanilla ranged condition only because BetterBots lowered the threshold; direct validation signal for `#72`)
- `ammo pickup preserved due to explicit order` (user-issued ammo orders bypassed BetterBots reserve logic; direct validation signal for `#72`)
- `ammo pickup deferred to human (bot <ammo>% > <threshold>%)` (a human ammo user was below reserve, so the bot yielded the pickup instead of topping off. One-shot per bot ammo-policy state episode, not every tick.)
- `ammo pickup permitted: bot desperate (<ammo>% <= <threshold>%) despite human reserve low` (a human was below reserve, but the bot was under its own desperation threshold and was allowed to pick up anyway. One-shot per bot ammo-policy state episode, not every tick.)
- `ammo pickup permitted: all eligible humans above reserve` (decision-level signal only: BetterBots set `pickup_component.needs_ammo = true` because no eligible human ammo user was below reserve; this does **not** prove the bot actually reached and completed the pickup interaction. One-shot per bot ammo-policy state episode, not every tick.)
- `ammo pickup success: <pickup> (bot=<slot>, ammo=<before>%-><after>%)` (actual pickup interaction succeeded and the bot's ammo reserve increased; stronger than `ammo pickup permitted` because it proves the interaction completed)
- `grenade pickup permitted: all eligible humans above reserve` (decision-level signal for grenade refills; BetterBots reserved the pickup for the bot because no eligible human grenade user was below reserve. One-shot per bot+pickup reservation episode, not every tick.)
- `grenade pickup bound into ammo slot` (the chosen grenade pickup was attached to the ammo-pickup fields so vanilla interaction code can collect it. One-shot per bot+pickup reservation episode, not every tick.)
- `released reserved grenade pickup to human reserve` (a previously reserved grenade pickup was explicitly given back because a human now needs it)
- `released reserved grenade pickup after leaving range` (a sticky BetterBots grenade reservation was dropped because the bot drifted beyond the pickup follow range before interaction completed)
- `grenade pickup deferred to human reserve` (the bot yielded a nearby grenade refill because at least one eligible human grenade user was below reserve. One-shot per bot+pickup defer episode, not every tick.)
- `grenade pickup skipped: ability does not use grenade pickups` (the equipped blitz replenishes through cooldown/passive logic instead of world grenade pickups, so grenade refill arbitration is bypassed. One-shot per bot+equipped ability state.)
- `grenade pickup skipped: cooldown-based blitz` (the bot has no grenade charges at all for this blitz path, so grenade refill logic is not applicable. One-shot per bot+equipped ability state.)
- `grenade pickup skipped: no ability extension` (grenade refill logic could not resolve the bot's `ability_system`, so reserve evaluation did not run. One-shot per bot until the missing-extension state changes.)
- `grenade pickup success: <pickup> (bot=<slot>, charges=<before>-><after>/<max>)` (actual pickup interaction succeeded and grenade charges increased; strongest confirmation for grenade refill pickups)
- `melee choice <attack> vs <armored|unarmored> target (crowd=<N>, bucket=<solo|pack|horde>, weapon=<template>)` (interesting `_choose_attack` decision; use to validate `#52` without per-swing spam)
- `melee defend suppressed for attack commit (target=<breed>, attackers=<N>, nearby=<N>, weapon=<template>)` (BetterBots suppressed vanilla's broad `num_melee_attackers() > 0` block gate so a bot can commit attacks into high-value armored melee targets under low-count pressure)
- `state_fail_retry ...` (combat ability state transition failed; fast retry scheduled)
- `blocked weapon switch while keeping ...` (bot `wield` request suppressed during protected relic/force-field stages)
- `blocked foreign weapon action <input> while keeping <grenade> <stage>` (grenade/blitz sequence suppressed a stray `weapon_action` input from another behavior path)
- `blocked foreign weapon action <input> while keeping daemonhost_avoidance target=<breed> stage=<N> aggro_state=<state> dormant=true` (central `weapon_action` queue guard suppressed direct ranged/melee/grenade inputs against a non-aggroed daemonhost target; validation signal for `#17`)
- `_may_fire swap: fire=<input> -> aim_fire=<input>` (`#43` validation; `_may_fire()` swapped fire input for ADS/charge weapon — one-shot per scratchpad)
- `normalized shoot scratchpad inputs (fire=<input>, aim_fire=<input>, aim=<input>, unaim=<input>)` (`#43` validation; `BtBotShootAction.enter` repaired stale/default shoot inputs against the live wielded template before `_may_fire` validates them. For plasma, expect `fire=shoot_charge, aim_fire=shoot_charge`.)
- `bot weapon: bot=<slot> slot=<slot> weapon_template=<template> warp_template=<template> action=<input> raw_input=<raw> target_slot=<slot> target=<unit|none> target_alive=<alive|dead|unknown|none> target_breed=<breed|unknown>` (`#43` validation; template-tagged queued weapon input, keyed by target so suspected ghost-target shots can be separated from normal target changes)
- `combat utility selected ...` (debug-only `BtRandomUtilityNode.evaluate` diagnostic for the bot `in_combat` selector; includes the selected branch/leaf, utility scores, current perception target/type/distance, ally distance, and current weapon. The selector is weighted-random, so the highest utility score does not always win. No-target follow selections are suppressed, and identical selection/target/weapon tuples are logged once per bot.)
- `stream action queued for <template> via <input> (phase=<phase>, bot=<slot>)` (`#87` validation; direct confirmation that a flamer/Purgatus stream-specific queue input actually reached `bot_queue_action_input` successfully)
- `patched opportunity reaction times (min=<N>, max=<N>)` (`#44` validation; startup/runtime confirmation that `BotSettings.opportunity_target_reaction_times.normal` was patched from the selected human-likeness timing profile)
- `HumanLikeness: BotSettings.opportunity_target_reaction_times is nil or missing .normal; reaction-time patch skipped` (one-shot warning that the engine bot-settings API shape changed and the human-likeness timing patch could not bind)
- `leash scaled <base> -> <effective> (pressure=<N>)` (`#44` validation; direct confirmation that pressure-based engagement leash scaling fired in combat)
- `type flip <old> -> <new>` (`#90` math-layer validation; perception hysteresis allowed a real melee/ranged type transition after the opposite mode cleared the margin)
- `close-range ranged family kept ranged target type (family=<family>, distance=<d>, ranged_score=<r>, melee_score=<m>)` (`#41` narrow Sprint 3 override; a supported close-range ranged family kept the bot in ranged mode under point-blank pressure instead of flipping to melee)
- `close-range hipfire suppressed ADS (family=<family>, distance=<d>)` (`#41` narrow Sprint 3 ADS suppression; a supported close-range ranged family stayed in hipfire inside the family policy window)
- `melee special prelude queued before <attack> (family=<family>)` (`#33`/`#103` melee-special identity; BetterBots prepended `special_action` before the chosen melee attack, with the family marker distinguishing powered weapons, chain weapons, direct combat axe/sword/knife specials, power mauls, Ogryn latrine shovels, clubs, pickaxes, and combat blades)
- `melee direct special paced (family=<family>, elapsed=<N>, cooldown=<N>)` (`#33` direct-special pacing; BetterBots left the chosen melee attack unwrapped because a direct sweep-style `special_action` was already queued inside the per-bot reuse window)
- `supported special family missing action metadata (weapon=<template>, family=<family>)` (one-shot debug diagnostic that a supported melee-special template matched BetterBots' family policy but did not expose a resolvable `special_action` action for that family; catches future Fatshark action-kind renames and partial policy additions without silently dropping the feature)
- `queued rippergun bayonet for <template> target=<breed> (bot=<slot>, fire_input=<input>)` (`#33` ranged-special identity; BetterBots rewrote close-range rippergun fire into the bayonet `stab` input for a valuable target)
- `queued ranged bash for <template> target=<breed> (bot=<slot>, fire_input=<input>)` (`#33` ranged-special identity; BetterBots rewrote close-range supported heavy-stubber/thumper, direct ranged bash, or pistol-whip fire into a weapon-special input for a valuable target)
- `type hold <current> over raw <candidate> (melee=<N>, ranged=<N>)` (`#90` math-layer validation; perception hysteresis actively suppressed a raw flip and kept the current type)
- `bot <slot> suppressed opposite-type switch <old> -> <new> (elapsed=<N>s)` (`#90` symptom-layer validation; `wrong_slot_for_target_type` wanted an immediate opposite-type reswitch, but the BT-side debounce suppressed it for a non-priority target)
- `bot <slot> wrong slot for <target_type> target (wielded=<slot>, wanted=<slot>)` (`#90` symptom-layer condition signal; `wrong_slot_for_target_type` fired for the current target type, so the BT wanted a weapon swap)
- `bot <slot> switch_melee entered (wielded=<slot>, wanted=slot_primary, target_type=melee)` / `bot <slot> switch_ranged entered (wielded=<slot>, wanted=slot_secondary, target_type=ranged)` (`#90` action-layer signal; the inventory-switch node actually executed instead of just evaluating the target-type math)
- `anti-armor ranged family kept ranged target type (family=<family>, breed=<breed>, distance=<d>)` (`#92` target-type validation; a Mauler/Bulwark/Crusher stayed ranged for an explicit anti-armor secondary family despite vanilla `killshot`'s armored-elite ranged penalty)
- `anti-armor ranged target skipped (reason=<reason>, weapon=<template>, secondary_status=<status>, breed=<breed>, distance=<d>, min_distance=<d|none>, chosen=<melee|ranged>, melee=<score>, ranged=<score>)` (`#92` target-type diagnostic; a Mauler/Bulwark/Crusher did not qualify for the anti-armor ranged lift, with enough context to distinguish unsupported secondary templates, missing visual-loadout resolution, and too-close policy distance)
- `weakspot aim selected j_head|j_spine (weapon=<template>, bot=<slot>)` (`#91` validation; bot entered `BtBotShootAction` with the head/spine weakspot aim table active while the `Weakspot aim` feature was enabled and selected an actual runtime node)
- `suppressed stale shoot aim input <input> for <template> (bot=<unit>)` / `suppressed stale shoot unaim input <input> for <template> (bot=<unit>)` (`BtBotShootAction` tried to carry an old ADS input onto a live non-aim template after a weapon/context change; BetterBots suppressed the queue before it reached `ActionInputParser`)
- `shoot scratchpad normalization skipped: missing unit_data_system or visual_loadout_system` (one-shot diagnostic from the `BtBotShootAction.enter` hook; BetterBots could not normalize ADS/brace inputs for that bot)
- `BetterBots: shoot scratchpad normalization skipped for <unit> because unit_data_system or visual_loadout_system is missing` (one-shot warning counterpart to the debug line above; emitted even when debug logging is off so operators can see why `#43` diagnostics were incomplete for a bot)
- `BetterBots: bt_bot_shoot_action hook_require resolved nil` (one-shot warning that the engine handed BetterBots a nil `BtBotShootAction` target during delayed hook installation; this is abnormal and should be investigated before trusting any shoot-action diagnostics)
- `BetterBots: ammo utility unavailable; dead-zone ranged fire detection disabled` (one-shot warning that `scripts/utilities/ammo` failed to load, so the dead-zone fire confirmation log for `#51` is unavailable in this session)
- `penalizing melee score for distant special <breed> dist_sq=<N> ammo=<N>` (target selection penalty applied — bot will prefer ranged over chasing)
- `penalizing friendly companion pin <breed> -100` (melee target scoring de-prioritized an enemy already pinned by a friendly mastiff; direct validation signal for `#69`)
- `penalizing ranged target for friendly companion pin -100` (ranged target scoring de-prioritized an enemy already pinned by a friendly mastiff; direct validation signal for `#69`)
- `pushing poxburster (bypassed outnumbered gate)` (poxburster melee hook forced a push; direct validation signal for `#54`)
- `ranged suppressed (daemonhost nearby)` (bot refused ranged fire because it was inside the close daemonhost safety radius; tight proximity gate for `#17`)
- `melee suppressed (target is dormant daemonhost, target=<breed> stage=<N> aggro_state=<state> dormant=<bool>)` (bot refused melee because its current target was a non-aggroed daemonhost outside the proximity gate; stage-aware when daemonhost `stage` is available, otherwise falls back to `aggro_state`; direct validation signal for `#17`)
- `ranged suppressed (target is dormant daemonhost, target=<breed> stage=<N> aggro_state=<state> dormant=<bool>)` (bot refused ranged fire because its current target was a non-aggroed daemonhost outside the proximity gate; stage-aware when daemonhost `stage` is available, otherwise falls back to `aggro_state`; direct validation signal for `#17`)
- `ranged suppressed (target near dormant daemonhost)` (bot refused ranged fire at a non-daemonhost enemy standing inside the dormant daemonhost keepout zone; validation signal for mixed-target `#17/#107` tests)
- `fallback blocked <charge_template> (charge_nav=daemonhost_target_near)` (charge/dash validation refused a launch endpoint inside the dormant daemonhost keepout zone; validation signal for mixed-target `#17/#107` tests)
- `daemonhost scan source source=<ai_target_units|relation_units|spawned_minions> count=<N>` (trace-only scan diagnostic emitted once per source per load, with the first observed list size; use it when a passive daemonhost exists but no later target/proximity suppression marker appears)
- `daemonhost scan candidate source=<source> unit=<unit> breed=<breed> alive=<bool> aggro_state=<state|nil> stage=<N|nil> position=<yes|no> accepted=<bool> reason=<accepted|dead|aggroed>` (trace-only classifier diagnostic emitted once per daemonhost candidate/source/state tuple; distinguishes liveness, breed, stage, aggro, and missing-position rejection)
- `target near daemonhost scan target=<breed> target_unit=<unit> daemonhost=<unit> bucket=<inner|alert|keepout|near|far> target_dh_dist=<N> bot_target_dist=<N|unknown>` (debug-only diagnostic emitted once per bot+target+daemonhost+bucket when BetterBots sees any non-aggroed daemonhost while a bot has a current target; use it to distinguish detector misses from suppression policy misses)
- `ability allowed against daemonhost: <ability> (rule=<rule>, target=<breed> stage=<N> aggro_state=<state> dormant=<bool>)` (ability activation was allowed against a daemonhost; use the first such line in a daemonhost encounter to distinguish normal aggroed combat from dormant misclassification)
- `sprint STOP (daemonhost_nearby)` (bot dropped sprint because it entered daemonhost safety radius; movement-side validation signal for `#17`)
- `patched visual loadout is_local_unit=false for bot (pre-init)` (spawn-time loadout VFX suppression applied before slot scripts initialized; direct validation signal for `#53`)
- `patched ability effect context is_local_unit=false for bot` (ability effect VFX suppression applied for bot-owned ability contexts; VFX validation signal)
- `patched CharacterStateMachine _is_local_unit=false for bot` (state-machine local-unit suppression applied for bot units; VFX/SFX validation signal)
- `restored visual loadout is_local_unit after init error` (visual loadout hook restored shared state before rethrowing; direct failure-path validation signal for `#73`)
- `installed consolidated bt_bot_melee_action hooks (melee_attack_choice, poxburster, engagement_leash)` (the shared `hook_require` callback for `bt_bot_melee_action` was installed; startup validation signal for `#67`)
- `bot <slot> pinged <target> (reason: <reason>)` (ping system — bot pinged an elite/special)
- `bot <slot> ping fail for <target>: <err>` (ping system — ping attempt failed)
- `bot <slot> skipped ping for <target> (reason: already_tagged|no_los|hold_last_tag|companion_tag|recent_companion_tag|dormant_daemonhost)` (ping system — meaningful suppression, one-shot per repeated target/reason; `companion_tag` means an Arbites bot yielded enemy tagging to mastiff smart-tagging instead of issuing a normal ping on the same target, `recent_companion_tag` means another Arbites bot just issued a mastiff command on that enemy so the generic ping path deliberately backs off instead of re-pinging it, and `dormant_daemonhost` means stage-aware daemonhost avoidance blocked the normal ping path)
- `bot <slot> skipped pinging (reason: failure_backoff)` (ping system — previous ping failure is still inside the retry backoff window)
- `bot <slot> companion-tagged <target> (reason: <reason>)` (Arbites mastiff smart-tag — companion command issued on a priority target)
- `bot <slot> skipped companion tag for <target> (reason: no_los|dormant_daemonhost)` (Arbites mastiff smart-tag — meaningful suppression, one-shot per repeated target/reason; non-aggroed daemonhosts never get mastiff command tags while daemonhost avoidance is enabled, using daemonhost `stage` when available)
- `holding existing companion tag on <target> (reason: <reason>)` (Arbites mastiff smart-tag — current companion order preserved through the minimum hold window)
- `skipped player-tag boost for chaos_daemonhost (reason: dormant_daemonhost)` (target selection — human tag no longer boosts a non-aggroed daemonhost into melee target priority while daemonhost avoidance is enabled; stage-aware when daemonhost `stage` is available)
- `suppressed <template> (team_cd:<category>)` (team cooldown staggering — another bot already activated the same category within the suppression window; direct validation signal for `#14`)
- `<profile> (<interaction_type>) dist=<N>` such as `shield (objective) dist=4.2` or `escort (luggable) dist=2.1` (interaction scan — ally detected in objective interaction; throttle key `interaction_scan:<unit>`, 5s interval; direct validation signal for `#37`)
- `revive candidate observed: <ability> (template=<template>, need_type=<type>)` (bot selected a rescue destination while carrying a defensive revive ability; this fires before `BtBotInteractAction.enter` and distinguishes selector/path misses from interact-hook misses for `#7`)
- `revive ability queued: <ability> (interaction=<type>, enemies=<N>)` (bot fired a defensive ability before starting a rescue interaction; for shared veteran template this logs the equipped ability name, e.g. `veteran_combat_ability_shout`)
- `[Bot <slot>] revive ability skipped (...)` with reasons such as `no enemies nearby`, `suppressed: <reason>`, `no unit_data_system extension`, `no ability_system extension`, `missing ability_meta_data.activation`, `activation has no action_input`, `no action_input_system extension`, or `<template> action_input <input> not bot-queueable` (the throttle key encodes the reason, but the emitted text is always the human-readable skip message)
- `combat_ability_identity: unknown template_name '<template>' — returning passthrough identity ...` (`combat_ability_identity.resolve` encountered a template not present in any of the category/cooldown/revive tables; one-shot per unique template per load, gated on debug — fires on Fatshark renames or unclassified abilities)
- `BetterBots: veteran combat ability could not be resolved to shout/stance (class_tag=<tag>, ability_name=<name>). Defaulting to stance gating.` (one-shot `mod:warning` when the Veteran shared template can't disambiguate via class_tag or ability name — operator-visible signal of a new Veteran variant the mod hasn't classified)
- `psyker heuristic context missing talents table; build-aware checks falling back to untuned defaults` / `ogryn heuristic context missing talents table; build-aware checks falling back to untuned defaults` (one-shot debug diagnostics that a build-aware heuristic received a malformed context without `talents`; BetterBots still falls back safely, but the build-specific branches are disabled until the caller/context seed is fixed)
- `cleared stale mule pickup ref (source=<path>)` (`#32`/stale-unit validation; deleted pickup refs were sanitized without touching invalid engine units)
- `mule pickup success: <pickup> (bot=<slot>)` (authoritative `PocketableInteraction.stop(result == "success")` confirmation for side-mission books and supported mule-pocketables such as stims/crates; use this to prove the item was actually inserted, not merely assigned)
- `BetterBots: group_system unavailable; mule pickup live-sync skipped` (one-shot warning that the live mule-sync path could not resolve `group_system`; pickup metadata patching still ran, but live reservation cleanup did not)
- `BetterBots: blackboard utility unavailable; mule pickup destination refresh skipped` (one-shot warning that the blackboard write helper could not be loaded, so mule destination refresh fell back to a no-op for that session)
- `ammo policy skipped: no pickup_component` (debug-only diagnostic that `_update_ammo` ran on a bot without a pickup component, so reserve logic was skipped for that tick)
- `deferred health station to human player` / `deferred medical crate to human player` (healing deferral yielded a medicae station or med-crate because a human player was below the configured reserve)
- `deferred health station to more injured bot` (station-charge-aware bot ordering yielded a scarce medicae charge to a clearly more-injured bot)
- `battle cry request noted: aggressive preset override for <N>s` / `need ammo request noted for <N>s` / `need health request noted for <N>s` (`com_wheel_response.lua` observed the relevant communication-wheel trigger and cached its short-lived override state)
- `smart-tag pickup routed <pickup> to bot <slot> (family=<family>)` / `smart-tag pickup ignored for <pickup> (reason=<reason>[, detail=bot=<slot>:<reason>, ...])` (`smart_tag_orders.lua` accepted or rejected an explicit item tag after reusing the normal BetterBots pickup policy gates; `detail=` is only present when `reason=no_eligible_bot`)
- `queued pocketable wield <input> for <pickup>` / `queued pocketable input <input> for <pickup>` (`pocketable_pickup.lua` advanced the carried-item state machine into wield/use)
- `pocketable use completed for <pickup>` / `pocketable ended without confirmation for <pickup>` / `pocketable timed out waiting for consume` / `pocketable timed out waiting for wield` (carried pocketable follow-through succeeded, ended ambiguously, or stalled)
- `fallback item blocked <ability> (slot locked by <ability> <reason>)` (item fallback hit the shared BetterBots slot-lock fast retry instead of waiting out the normal wield timeout)

## Intentionally suppressed (noise reduction)

The following were removed/throttled to reduce chat spam during testing:

- **`bt gate evaluated`** — removed entirely; redundant with decision log
- **`decision -> false`** — suppressed; BT-path false decisions are no longer logged
- **`fallback held` with `nearby=0`** — suppressed; idle holds produce no log output
- **`blocked (template_name=none)` in BT path** — throttled to 20s (was 2s); expected for item abilities
- **Cached `charge_nav` blocked JSONL events** — suppressed; the first concrete
  failure reason is still emitted, but `cached_<reason>` repeats are console-
  throttled only and do not enter `betterbots_events_*.jsonl`

**Observability impact:** Idle-state bot decisions (no enemies nearby) are completely invisible in new logs. `bb-log summary` `held_idle` counter will show 0 for runs after this change. This is acceptable for combat-focused heuristic tuning but means idle behavior issues won't appear in logs. Re-enable by reverting the guards in `debug.lua:log_ability_decision` and `BetterBots.lua:_fallback_try_queue_combat_ability` if needed.

## Interpreting failures

- `decision -> true` without `charge consumed`:
  - condition passed, but activation pipeline failed later.
- repeated `fallback skipped ... template_name=none`:
  - bot is on item-based combat ability path.
- repeated `fallback item blocked ... unsupported weapon template`:
  - add a new item sequence mapping in `BetterBots.lua`.
- repeated `fallback item continuing charge confirmation ... lost combat-ability wield ...`:
  - another behavior node is switching away during cast/channel; verify whether lock lines (`blocked weapon switch while keeping ...`) are present.
- repeated `grenade queued wield for <grenade> ...` plus `blocked foreign weapon action grenade_ability while keeping <grenade> wield`, with no `grenade wield confirmed, waiting for aim`, `grenade queued <aim_input> for <grenade>`, `grenade releasing toward ...`, or `grenade charge consumed`:
  - the grenade weapon-action blocker is swallowing the **initial** item-grenade `grenade_ability` input during `state.stage == "wield"`.
  - this is an allowlist/sequence bug in `grenade_fallback._expected_weapon_action_input()`, not a ballistic/gravity-aim failure.
  - do not blame the gravity-aware aim path unless the log first reaches `grenade wield confirmed, waiting for aim` and then starts emitting `grenade aim ballistic for <grenade>` / `grenade aim flat fallback for <grenade>`.

## Writing debug logging for new features

Debug logging is **permanent infrastructure**, not throwaway diagnostics. Every feature's logs must survive across releases to catch regressions and validate working state. Never mark logs as "remove after validation."

### Log levels

`enable_debug_logs` is a dropdown in DMF options:

- `Off` — no `_debug_log` output
- `Info` — one-shot patches and confirmations only
- `Debug` — default diagnostic level for ability decisions and state changes
- `Trace` — includes per-frame diagnostics such as sprint traces

Poxburster suppression confirmations are logged at `Debug`, not `Trace`, so normal validation runs can confirm that path.

### Rules

1. **Gate expensive reads behind `_debug_enabled()`**. `read_component()`, `has_extension()`, and string concatenation run on the hot path (multiple bots, every frame). Only pay that cost when debug mode is on.

2. **One-shot dedup for repeated events**. Most bot actions repeat every frame. Use one of two patterns:
   - **Weak-keyed set** for object-keyed dedup (scratchpad, unit): `local _logged = setmetatable({}, { __mode = "k" })`. Entries auto-clear when the key is GC'd (e.g. scratchpad recycled between missions).
   - **String-keyed set** for combo dedup: `local _logged_combos = {}`. Build a key like `bot_slot .. ":" .. template .. ":" .. action` and skip if already seen. Use this when the discriminator is a value, not an object reference.

3. **Throttle key convention**. The first argument to `_debug_log(key, t, msg, interval, level)` is `"feature_tag:" .. discriminator` — e.g. `"may_fire_swap:shoot_charged"`, `"grenade_state:wait_aim"`, `"peril_block:shoot_pressed"`. This key is an internal throttle/dedup identifier only. `_debug_log` prints **only the message**, not the key, so console-log filtering must grep the human-readable message text (for example `_may_fire swap: ...`), not the key string.

   **Per-bot keys are mandatory in per-bot code paths.** `_debug_log` throttles by key — if multiple bots fire the same key in the same frame (same `fixed_t`), only the first bot's message appears. All others are silently dropped. Any `_debug_log` call inside a hook or function that runs per-bot (condition evaluation, ability queue, grenade fallback, etc.) **must** include `.. ":" .. tostring(unit)` in the key. Logs that fire once globally (init patches, startup messages) don't need this. Keep the **message prefix** stable and grep-friendly too, because that is what actually lands in the console log.

4. **Log the confirmation signal**. Each feature should log the event that proves it fired correctly:
   - State machine transition → log the new state and trigger
   - Input swap/translation → log what was swapped and why
   - Suppression/block → log what was blocked and the reason
   - Injection/patch → log once at load time that the patch applied

5. **Don't log no-ops**. Idle paths, false conditions, and expected skips produce no output. If a bot has no enemies nearby and the heuristic returns false, that's not interesting. Only log when something happened.

### Example: one-shot scratchpad logging

```lua
local _logged = setmetatable({}, { __mode = "k" })

-- Inside a hook:
if not _logged[scratchpad] and _debug_enabled() then
    _logged[scratchpad] = true
    _debug_log(
        "feature_tag:" .. tostring(discriminator),
        _fixed_time(),
        "human-readable message with key values"
    )
end
```

### Example: combo-key logging

```lua
local _logged_combos = {}

-- Inside a per-frame hook:
if _debug_enabled() then
    local key = bot_slot .. ":" .. template .. ":" .. action
    if not _logged_combos[key] then
        _logged_combos[key] = true
        _debug_log("feature:" .. key, _fixed_time(), "descriptive message")
    end
end
```

### Updating the log line catalog

When adding new `_debug_log` calls, add the corresponding log line to the "Key BetterBots log lines" section above. Include the prefix pattern and a brief description of when it appears.

## Structured event log (JSONL)

Parallel to debug text logging. Enable via mod setting `Enable event log (JSONL)` (`enable_event_log` in code).

### Output

`./dump/betterbots_events_<timestamp>.jsonl` — one JSON object per line.

**Filename timestamp** uses wall-clock `os.time()` (epoch seconds), not simulation `fixed_t` which resets each mission. This prevents filename collisions across runs.

**Working directory caveat:** Darktide's CWD is `binaries/`, so files land in `<game-root>/binaries/dump/`. The `bb-log events` command expects `EVENTS_DIR=./dump` relative to CWD — run it from the `binaries/` directory or adjust the path.

### Event types

| Event | When | Key fields |
|-------|------|-----------|
| `session_start` | First bot update tick | version, bots[] |
| `decision` | Every heuristic eval | result, rule, source, bot, ctx, skipped_since_last |
| `queued` | Action input sent | input, source, rule, attempt_id |
| `item_stage` | Item state transition | stage, profile, input, attempt_id |
| `consumed` | Charge spent | charges, attempt_id |
| `blocked` | Item sequence failure | reason, stage, profile, attempt_id |
| `snapshot` | Every 30s per bot | cooldown_ready, charges, ctx, item_stage |

For daemonhost investigations, `decision.ctx` now preserves
`target_is_dormant_daemonhost`, `target_daemonhost_aggro_state`, and
`target_daemonhost_stage` when the current target is a daemonhost, so JSONL
traces can distinguish stage-aware pre-aggro suppression from active-fight
self-defense behavior.

### Hot-reload behavior

`Ctrl+Shift+R` resets all module-local state (buffer, file path, enabled flag). DMF does **not** re-fire `on_game_state_changed` for the current state, so the normal `start_session` path doesn't trigger.

**Recovery:** At load time, BetterBots checks if the event log setting is enabled and bots are alive. If so, it re-enables logging and starts a new session file. This means a hot-reload mid-mission produces a new JSONL file (previous buffer is lost if not yet flushed).

### Correlation

Events carry `attempt_id` (monotonic per session) to link decision → queued → consumed chains. `bot` field is the player slot index.

`ctx` is the `Debug.context_snapshot(...)` payload. It includes the combat signals used by heuristics, including `in_hazard` for hazard-aware validation and `target_is_near_dormant_daemonhost` for daemonhost keepout checks.

### Analysis

```bash
bb-log events summary    # counts + approval rate + per-bot consumes
bb-log events rules      # hit rates per ability+rule
bb-log events trace N    # timeline for bot slot N
bb-log events holds      # false decision distribution
bb-log events items      # item sequence success/fail
bb-log events raw FILTER # passthrough to jq
```

### Text-log Consume counter is profile-dependent

`bb-log summary`'s "Consumes by ability" table is built from the text-log `grenade charge consumed` line, which only fires for grenade profiles whose completion signal is auto-unwield (frag, krak, fire, throwing knives, rocks, box, adamant grenades). Profiles whose completion signal is **external action confirmation** — most notably `psyker_smite` via `confirmation_action = "action_use_power"`, plus assail and chain lightning — complete the state machine via the `grenade external action confirmed` path and **never emit a consume line**. Those grenades still fire correctly; they just don't appear in the text-log Consumes table.

**Authoritative counts live in the JSONL event log.** When validating "did this grenade actually fire", use:

```bash
bb-log events raw | grep '"ability":"psyker_smite"' | \
  grep -oE '"event":"(queued|complete|blocked)"' | sort | uniq -c
```

or the equivalent `jq` filter. The `queued` → `complete` ratio tells you whether throws landed or got blocked (usually via `reason=revalidation` when density-gated templates lose the aim-window race).
