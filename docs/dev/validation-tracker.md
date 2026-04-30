# In-Game Validation Tracker

## Purpose

Track manual Darktide validation runs with consistent evidence so issue decisions are based on logs, not memory.

## Active Scope

1. Tier 1 ability validation (baseline)
2. Tier 2 ability validation (`#1`)
3. Tier 3 item-ability fallback validation (`#3`)
4. Regression sanity checks (revive/rescue/navigation/basic combat)
5. v1.0.0 release-validation queue (Sprint 1-6 code is landed on `dev/v1.0.0`; live runs still needed before release)

## Current v1.0.0 Validation Queue (2026-04-18)

- Sprint 2: confirm Martyrdom healing suppression, Shroudfield low-health carve-out, talent-aware Venting Shriek peril preservation, and Focus Target tag ownership in a real mission.
- Sprint 3: confirm close-range ranged families keep ranged target type without breaking Purgatus charge-fire, and melee specials still arm correctly in live combat for both powered and chain-family rules.
- Sprint 4: confirm supported pocketables are carried, wielded, consumed/deployed, and logged cleanly under both success and uncertain-end cases.
- Sprint 5: confirm com-wheel requests reset cleanly between missions, smart-tag orders only fire on real tag set/override events, and explicit ammo tags still cover grenade-refill bots.
- Sprint 6: cold-boot both load orders, grep raw logs for DMF warnings / parser noise, and re-check that the metadata guards restore original values on disable.

## Run Entry Template

Use one block per in-game session:

```text
Run ID:
Date (local):
Date (UTC):
Git commit:
Log file:
Bot lineup / abilities:
Map + difficulty:

Tier 2 evidence:
- <ability_template>: PASS/FAIL/UNKNOWN
  - visual: yes/no
  - charge consumed log: yes/no
  - key lines / timestamps:

Tier 3 evidence:
- <ability_template>: PASS/FAIL/UNKNOWN
  - visual: yes/no
  - charge consumed log: yes/no
  - blocked-switch / retry logs seen: yes/no
  - key lines / timestamps:

Regression checks:
- fresh launch / startup load: PASS/FAIL/UNKNOWN
- second mission without restart: PASS/FAIL/UNKNOWN
- duplicate startup spam: yes/no
- template/item/grenade smoke all observed: yes/no
- revive/rescue: PASS/FAIL/UNKNOWN
- navigation/pathing: PASS/FAIL/UNKNOWN
- basic combat loop: PASS/FAIL/UNKNOWN
- Lua errors: yes/no (+ first traceback line if yes)

Conclusion:
- promote issue state / next fix target:
```

## Recorded Runs

### Run 2026-04-29-post-v1-validation-rollup

```text
Run ID: 2026-04-29-post-v1-validation-rollup
Date (local): 2026-04-29
Date (UTC): 2026-04-29
Git commit: dev/post-v1.0 April 29 validation branch
Log files:
- console-2026-04-29-16.32.07-a435de8b-052f-4722-89b6-60c12c07c3a9.log
- console-2026-04-29-16.58.08-db4d37bd-80f0-4296-91c1-d15b5c5a0e50.log
- console-2026-04-29-17.10.48-79271f1d-b285-428d-82a3-5f42e970f3b9.log
- console-2026-04-29-17.58.08-8271338f-2e3d-413f-9bda-b7f2fa277afd.log
- console-2026-04-29-18.20.42-2637bc0d-fa9c-4ef1-81ac-948f5e33f7bb.log
- console-2026-04-29-18.46.59-5cba60d0-4e7b-472c-9070-8ea2d4fa4159.log
- console-2026-04-29-19.11.14-595beab0-65b3-4115-9dcd-9a8514037073.log

Regression checks:
- BetterBots warnings: no in latest checked run (`./bb-log warnings` = none)
- Lua errors: no in latest checked run (`./bb-log errors` = none)

#108 human revive priority:
- PASS
  - key lines / timestamps: `17:14:31.929 ... [bot=2] human revive priority assigned ... reason=mission_critical distance=4.1089`
  - follow-up pathing/interaction: `17:14:32.034 ... sprint START (ally_rescue)`, `17:14:33.178 ... shield (revive) dist=10.9`, and `17:14:33.289 ... grenade blocked: interacting with [Unit '#ID[f888cbd0f5a35360]']`
  - repeat evidence: second revive-pressure window at `17:18:55.294` assignment, `17:18:55.338` ally-rescue sprint, `17:18:55.565` shield, and `17:18:55.790` interacting block on the same human unit
  - note: the log does not print a literal vanilla `do_revive` marker, but the assignment -> ally-rescue sprint -> shield/interacting sequence validates the BetterBots seam and shows vanilla interaction ownership took over

#106 perf cap:
- PASS
  - mission-end `bb-perf:auto` totals across April 29: `116.5`, `79.3`, `98.1`, `90.2`, `90.1`, `102.2`, `95.7 us/bot/frame`
  - median: `95.7 us/bot/frame`
  - worst run: `116.5 us/bot/frame`
  - `ability_queue + grenade_fallback` stayed below 50% in the checked runs; worst checked share was the 18:46 run at `(3161 + 422) / 7715 = 46.4%`

#100 scenario harness:
- PASS for MVP live spawn/logging
  - key lines / timestamps: `bb-log events scenarios` showed three `mauler_weakspot` runs (`mauler_weakspot:49788`, `:82096`, `:112923`), each with 10 `scenario_spawn` rows for `renegade_executor` at distance 22 and `scenario_result status=spawned`
  - follow-up: do not hold the MVP issue open for scenario-library quality; track useful new scenarios separately

#17 daemonhost avoidance:
- NOT VALIDATED
  - April 29 logs only show context dumps with `target_is_dormant_daemonhost = false`
  - no decisive first-action `ability allowed against daemonhost ... stage=<N> aggro_state=<state> dormant=<bool>` or `melee/ranged suppressed (... daemonhost ...)` marker was found
  - next useful action is a targeted daemonhost scenario if spawning one is reliable, not more random log review

#92 per-breed weakspot:
- DEPRIORITIZED
  - Mauler scenario validated the important behavior: anti-armor ranged target type above 12m, melee fallback below 12m, no heavy-stubber bash loop, and hard-armor knife blocks
  - remaining generic `weakspot aim selected` proof is too niche to chase manually

Conclusion:
- Close `#108`, `#106`, and `#100`.
- Keep `#17` open until a targeted daemonhost scenario or future live spawn produces the decisive first-action state line.
- Do not spend more manual validation time on `#92` unless the scenario harness makes it cheap.
```

### Run 2026-04-29-mauler-weakspot-scenario-01

```text
Run ID: 2026-04-29-mauler-weakspot-scenario-01
Date (local): 2026-04-29
Date (UTC): 2026-04-29
Git commit: 833e140
Log file: console-2026-04-29-19.11.14-595beab0-65b3-4115-9dcd-9a8514037073.log
Bot lineup / abilities: validation roster with bolter, heavy stubber, krak grenade, Ogryn frag, and Zealot throwing knives present
Map + difficulty: `/bb_scenario mauler_weakspot 22 10` targeted scenario smoke

Regression checks:
- fresh launch / startup load: UNKNOWN
- duplicate startup spam: no evidence in summary
- BetterBots warnings: no (`./bb-log summary` = `BB warnings: 0`)
- Lua errors: no (`./bb-log summary` = `Error lines: 0`)

Scenario harness / #100 evidence:
- Scenario command distance/count: PASS
  - key lines / timestamps: three `mauler_weakspot` runs spawned 10 `renegade_executor` units at distance 22 (`mauler_weakspot:49788`, `mauler_weakspot:82096`, `mauler_weakspot:112923`)

Sprint 1 / #92 evidence:
- Mauler anti-armor ranged target type: PASS
  - key lines / timestamps: `anti-armor ranged family kept ranged target type (family=bolter, breed=renegade_executor, distance=24.94)` and `family=heavystubber ... distance=24.19` at 19:13:29, with repeated keep-ranged markers above the 12m minimum
- Close hard-armor melee fallback: PASS
  - key lines / timestamps: `anti-armor ranged target skipped (reason=distance_below_min, weapon=bolter_p1_m1, ... distance=12.00, min_distance=12.00, chosen=melee)` plus `bot 5 switch_melee entered` at 19:13:37; equivalent heavy-stubber skip/switch at 19:13:37 and 19:14:40
- Heavy-stubber ranged bash loop regression: PASS
  - key lines / timestamps: no `queued ranged bash` marker found in the checked raw log
- Mauler weakspot override: PARTIAL PASS
  - key lines / timestamps: `weakspot override applied (breed=renegade_executor, node=j_spine)` at 19:13:29 and 19:14:05
  - remaining gap: no `weakspot aim selected` marker in this run; Mauler spine override is not enough to close generic weakspot validation

Grenade / blitz evidence:
- Zealot knives blocked against Maulers: PASS
  - key lines / timestamps: repeated `grenade held zealot_throwing_knives (rule=grenade_knives_block_hard_armor, ... breed=renegade_executor, ...)`
  - negative evidence: no `grenade queued wield for zealot_throwing_knives`, `ability blitz activated zealot_throwing_knives`, `bot weapon ... zealot_throwing_knives`, or release line found
- Veteran krak against Maulers: PASS
  - key lines / timestamps: 7 `veteran_krak_grenade` consumes in `./bb-log summary`, with repeated `grenade releasing toward ... target_breed=renegade_executor`
- Ogryn frag against Mauler packs: PASS
  - key lines / timestamps: 1 `ogryn_grenade_frag` consume in `./bb-log summary`, with `grenade releasing toward ... target_breed=renegade_executor` at 19:13:34

Conclusion:
- The anti-armor target-type regression and heavy-stubber bash-loop regression look fixed in this scenario.
- Knife hard-armor blocking is behaving correctly in the log; visual knife-like behavior was not backed by a BetterBots knife queue/release marker.
- Keep `#92` open for a non-Mauler weakspot target that should produce `weakspot aim selected`.
```

### Run 2026-04-22-v1-0-0-followup-02

```text
Run ID: 2026-04-22-v1-0-0-followup-02
Date (local): 2026-04-22
Date (UTC): 2026-04-22
Git commit: local (post corruption-stim pickup follow-up)
Log file: console-2026-04-22-10.46.31-a0fff67f-573b-4d89-9e32-eb3b9675ed14.log
Bot lineup / abilities: current validation-first defaults — Veteran (Voice of Command + Focus Target + precision lasgun + chainsword), Zealot (Fury + Martyrdom + chainaxe + stub revolver), Psyker (Scrier's Gaze + Brain Rupture + electrokinetic staff + force sword), Ogryn (Point-Blank Barrage + Kickback + latrine shovel)
Map + difficulty: live mission test run (exact map/difficulty not recorded in log)

Regression checks:
- fresh launch / startup load: PASS
- duplicate startup spam: no
- BetterBots warnings: no (`./bb-log warnings` = none)
- Lua errors: no

Sprint 2 / #104 evidence:
- Psyker Scrier's Gaze: PASS
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued psyker_overcharge_stance ... (rule=psyker_stance_threat_window_build)` at 10:50:17 / 10:53:38 / 10:55:20, plus `psyker_stance_combat_density_build` at 10:51:45
- Ogryn Point-Blank Barrage: PASS
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued ogryn_gunlugger_stance ... (rule=ogryn_gunlugger_armor_pen_target)` at 10:50:27, `ogryn_gunlugger_ranged_pack` at 10:54:06, and `ogryn_gunlugger_high_threat` at 10:55:19
  - blocking rules observed: `ogryn_gunlugger_block_melee_pressure`, `ogryn_gunlugger_block_target_too_close`, `ogryn_gunlugger_block_low_threat`

Sprint 3 / #103 + #105 evidence:
- Chain-family melee special execution: PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: `chainsword_p1_m1 action=special_action` at 10:50:17 and `chainaxe_p1_m2 action=special_action` at 10:50:19
- Force sword melee special execution: PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: `forcesword_p1_m1 action=special_action` at 10:50:18
- Rippergun close-range ranged hold: PASS
  - visual: unknown
  - key lines / timestamps: repeated `ogryn_rippergun_p1_m2 action=zoom_shoot` / `holding sustained fire inputs` from 10:50:48 onward, with repeated same-window `type hold ranged over raw melee` lines
- `forcestaff_p3_m1` close-range ranged hold: UNKNOWN
  - key lines / timestamps: `forcestaff_p3_m1` did fire (`vent`, `charge`, `shoot_pressed`, later `grenade_ability`), but this run still has no isolated positive keep-ranged marker for the family

Sprint 4 / pocketable carry evidence:
- Combat stim pickup primitive: PASS
  - key lines / timestamps: `assigned proactive mule pickup for syringe_power_boost_pocketable` at 10:52:49 and `mule pickup success: syringe_power_boost_pocketable (bot=5)` at 10:54:24
- Smart-tag item bridge: PARTIAL PASS
  - key lines / timestamps: repeated `smart-tag pickup ignored for syringe_power_boost_pocketable (reason=no_eligible_bot)` from 10:51:34 onward
  - remaining gap: no positive `smart-tag pickup routed ...` line in this run

Other gaps:
- Weakspot aim (`#92`): UNKNOWN
  - no `weakspot aim selected` / `weakspot override applied` line in this run
- Daemonhost avoidance (`#17`): UNKNOWN
  - no real daemonhost spawn; only debug context lines with `target_is_dormant_daemonhost = false`

Conclusion:
- This run is enough to close `#103` and `#104`.
- On a lenient close standard, it is also enough to close `#105`: autopistol already had live proof from the 2026-04-19 smoke run, and this run adds the missing rippergun live evidence.
- This run is still not enough to close `#17`, `#92`, or `#96`, and it does not prove corruption-stim self-use yet.
```

### Run 2026-04-19-v1-0-0-smoke-01

```text
Run ID: 2026-04-19-v1-0-0-smoke-01
Date (local): 2026-04-19
Date (UTC): 2026-04-19
Git commit: local (post weapon_action / weakspot_aim hook conflict fix)
Log file: console-2026-04-19-13.47.30-9f74e98d-a19e-4398-b3bf-93c243233c93.log
Bot lineup / abilities: validation-first lineup used in this run — Veteran (Voice of Command + Focus Target + boltgun + power sword), Zealot (Fury + Martyrdom + heavy eviscerator + autopistol), Psyker (Scrier's Gaze + Brain Rupture + electro staff + force sword), Ogryn (Point-Blank Barrage + armor-pen + rippergun + Bully Club)
Map + difficulty: live mission smoke run

Regression checks:
- fresh launch / startup load: PASS
- duplicate startup spam: no
- BetterBots warnings: no (`./bb-log warnings` = none)
- Lua errors: no

Sprint 2 / #104 evidence:
- Psyker Scrier's Gaze: PARTIAL PASS
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued psyker_overcharge_stance ... (rule=psyker_stance_threat_window_build)` at 13:50:23 / 13:51:37 / 13:55:05, plus `psyker_stance_combat_density_build` at 13:52:21
- Ogryn Point-Blank Barrage: PARTIAL PASS
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued ogryn_gunlugger_stance ... (rule=ogryn_gunlugger_ranged_pack)` at 13:52:12 / 13:54:55 / 13:56:58
  - blocking rules observed: `ogryn_gunlugger_block_melee_pressure`, `ogryn_gunlugger_block_target_too_close`, `ogryn_gunlugger_block_low_threat`
  - remaining gap: no `ogryn_gunlugger_armor_pen_target` confirmation in this run

Sprint 3 / #103 + #105 evidence:
- Powered melee special prelude: PARTIAL PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: repeated `melee special prelude queued before ... (family=powered)` from 13:50:15 onward
- Chain-family melee special prelude: PARTIAL PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: repeated `melee special prelude queued before heavy_attack (family=chain)` and later `light_attack (family=chain)` from 13:51:02 onward
  - remaining gap: current lineup only proves the equipped chain-family path, not all chain subfamilies
- Autopistol close-range ADS suppression: PARTIAL PASS
  - visual: unknown
  - key lines / timestamps: `close-range hipfire suppressed ADS (family=autopistol, distance=7.95)` at 13:51:32
- Rippergun / `forcestaff_p3_m1` close-range ranged hold: UNKNOWN
  - no `close-range ranged family kept ranged target type` line for either family in this run

Brain Burst / psyker_smite follow-up evidence:
- Arbitration hold rules: PARTIAL PASS
  - key lines / timestamps: `grenade_smite_block_melee_pressure`, `grenade_smite_block_melee_range`, and `grenade_smite_block_peril` all observed repeatedly from 13:50:19 onward
  - remaining gap: no clean end-to-end positive execute trace on the intended hard target in this run; multiple `grenade aim aborted after revalidation` lines remain

Other gaps:
- Weakspot aim (`#92`): UNKNOWN
  - no `weakspot aim selected` line in this run

Conclusion:
- The `BtBotShootAction.enter` rehook warning is resolved in a real cold run: 0 BetterBots warnings, 0 Lua errors.
- This run partially validates the validation-first lineup and the post-v0.11.3 follow-up batch, but it is not enough to close `#103`, `#104`, or `#105`.
- Next targeted checks: weakspot aim, rippergun + `forcestaff_p3_m1` close-range hold, and a clean positive Brain Burst execution trace.
```

### Run 2026-04-20-v1-0-0-followup-01

```text
Run ID: 2026-04-20-v1-0-0-followup-01
Date (local): 2026-04-20
Date (UTC): 2026-04-20
Git commit: 0cecb61 (dev/v1.0.0, local dirty)
Log file: console-2026-04-20-18.30.47-c687b3e8-22d8-4beb-b875-379986fd2fd4.log
Bot lineup / abilities: then-current defaults at run time — Veteran (Voice of Command + Focus Target + precision lasgun + power sword), Zealot (Fury + Martyrdom + heavy eviscerator + autopistol), Psyker (Scrier's Gaze + Brain Rupture + electrokinetic staff + force sword), Ogryn (Point-Blank Barrage + armor-pen rippergun + Bully Club)
Map + difficulty: live mission follow-up run

Regression checks:
- fresh launch / startup load: PASS
  - dedicated new console log file for the session
- duplicate startup spam: no
- BetterBots warnings: no (`./bb-log warnings` = none)
- Lua errors: no

Sprint 2 / #104 evidence:
- Psyker Scrier's Gaze: PARTIAL PASS
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued psyker_overcharge_stance ... (rule=psyker_stance_threat_window_build)` at 18:34:20 / 18:35:18 / 18:37:29 / 18:39:07
- Ogryn Point-Blank Barrage: PASS (targeted armor-pen follow-up)
  - visual: unknown
  - charge consumed log: yes
  - key lines / timestamps: `fallback queued ogryn_gunlugger_stance ... (rule=ogryn_gunlugger_armor_pen_target)` at 18:34:46 / 18:36:11
  - blocking rules observed: `ogryn_gunlugger_block_melee_pressure`, `ogryn_gunlugger_block_target_too_close`, `ogryn_gunlugger_block_low_threat`

Sprint 3 / #103 + #105 evidence:
- 1H power sword melee special prelude: PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: repeated `melee special prelude queued before ... (family=powersword_1h)` from 18:34:12 onward
- Chain-family melee special prelude: PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: repeated `melee special prelude queued before ... (family=chain)` from 18:34:21 onward
- 1H force sword melee special prelude: PASS
  - visual: unknown
  - queue log: yes
  - key lines / timestamps: repeated `melee special prelude queued before ... (family=forcesword_1h)` from 18:34:22 onward
- Autopistol close-range ADS suppression: PASS
  - visual: unknown
  - key lines / timestamps: `close-range hipfire suppressed ADS (family=autopistol, distance=9.57)` at 18:33:36
- Rippergun / `forcestaff_p3_m1` close-range ranged hold: UNKNOWN
  - no `close-range ranged family kept ranged target type` line for either family in this run
- Shotgun special-shell support: UNKNOWN
  - no `armed shotgun special for` / `spent shotgun special for` lines in this run

Brain Burst / psyker_smite follow-up evidence:
- Proc-cover suppression: PASS
  - key lines / timestamps: repeated `grenade held psyker_smite (rule=grenade_smite_block_proc_cover, ...)` from 18:33:19 onward, plus `grenade aim aborted after revalidation (rule=grenade_smite_block_proc_cover)` at 18:35:48 / 18:38:11
- Positive executes preserved: PARTIAL PASS
  - key lines / timestamps: `grenade queued wield for psyker_smite (rule=grenade_smite_monster)` at 18:34:49 / 18:35:06, `grenade external action confirmed for psyker_smite` at 18:34:52 (close); `grenade queued wield for psyker_smite (rule=grenade_smite_priority_target)` at 18:35:15 / 18:35:23 / 18:38:03 with `grenade external action confirmed for psyker_smite` at 18:35:26 (mid) / 18:38:05 (far)
  - remaining gap: no explicit bomber-specific confirmation in this run

Other gaps:
- Weakspot aim (`#92`): UNKNOWN
  - no `weakspot aim selected` line in this run despite the Veteran precision-lasgun default swap

Conclusion:
- The new Brain Burst proc-cover carve-out is working in a live run: manual casts are being suppressed by `grenade_smite_block_proc_cover` without removing positive monster / priority-target executes.
- The melee special family split is live for `powersword_1h`, `chain`, and `forcesword_1h`.
- `ogryn_gunlugger_armor_pen_target` now has positive live evidence.
- This run still does not close `#92`, shotgun support validation, or the close-range rippergun / `forcestaff_p3_m1` hold path.
```

### Run 2026-03-05-tier1-01

```text
Run ID: 2026-03-05-tier1-01
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: 7d35dbf (run-time build)
Log file: console-2026-03-05-14.44.43-6d3afdc1-0848-40b4-8e35-951e6e86401a.log
Bot lineup / abilities: Veteran (Voice of Command), Psyker (Scrier's Gaze), Ogryn (Point-Blank Barrage), Arbites (Castigator's Stance)
Map + difficulty: Psykhanium (modded realm), difficulty>=4 in crash locals

Tier 1 evidence:
- veteran_combat_ability: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 14:51:42 / 14:52:09 (`charge consumed for veteran_combat_ability_shout`)
- psyker_overcharge_stance: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 14:51:44 (`charge consumed for psyker_overcharge_stance`)
- ogryn_gunlugger_stance: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 14:51:44 (`charge consumed for ogryn_ranged_stance`)
- adamant_stance: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 14:51:42 (`charge consumed for adamant_stance`)

Regression checks:
- revive/rescue: UNKNOWN
- navigation/pathing: UNKNOWN
- basic combat loop: FAIL (session terminated by Lua crash)
- Lua errors: yes (weapon_system queue_perils_of_the_warp_elite_kills_achievement, nil account_id path)

Conclusion:
- Tier 1 baseline has positive activation evidence for the 4 tested abilities.
- Crash requires defensive guard before further stability validation.
```

### Run 2026-03-05-tier2-01

```text
Run ID: 2026-03-05-tier2-01
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (post nil-account guard)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log
Bot lineup / abilities: Veteran (Voice of Command), Psyker (Venting Shriek), Ogryn (Loyal Protector), Arbites (Break the Line)
Map + difficulty: Hordes/Survival mission

Tier 2 evidence:
- psyker_shout: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 15:05:55, 15:06:21 (`charge consumed for psyker_discharge_shout_improved`)
- ogryn_taunt_shout: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 15:05:57 (`charge consumed for ogryn_taunt_shout`)
- adamant_charge: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 15:05:57, 15:06:14 (`charge consumed for adamant_charge`)
- zealot_dash: UNKNOWN
  - not tested in this run (Veteran was loaded by mistake)

Regression checks:
- revive/rescue: UNKNOWN
- navigation/pathing: UNKNOWN
- basic combat loop: PASS (no crash signature in this log)
- Lua errors: no BetterBots/weapon_system crash traceback seen

Conclusion:
- Tier 2 progress is real for Psyker/Ogryn/Arbites.
- Zealot dash remains unverified and is the next targeted check.
```

### Run 2026-03-05-tier2-02 (player-confirmed Zealot dash)

```text
Run ID: 2026-03-05-tier2-02
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (post nil-account guard)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log (same rolling file)
Bot lineup / abilities: Zealot dash variant equipped (Fury of the Faithful)
Map + difficulty: mission segment in same game session

Tier 2 evidence:
- zealot_dash: PASS
  - visual: yes (player-observed in-game)
  - charge consumed log: yes
  - key lines / timestamps: 15:10:25, 15:10:52, 15:11:46, 15:12:13 (`charge consumed for zealot_targeted_dash_improved_double`)

Regression checks:
- basic combat loop: PASS (no new crash signature in file)

Conclusion:
- Zealot dash is now log-confirmed in the same rolling session log.
```

### Run 2026-03-05-tier2-03 (Tier 2 cleanup)

```text
Run ID: 2026-03-05-tier2-03
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (post nil-account guard)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log (same rolling file)
Bot lineup / abilities: Zealot (Shroudfield), Ogryn (Bull Rush/Indomitable charge path), fillers stable
Map + difficulty: mission segment in same game session

Tier 2 evidence:
- zealot_invisibility: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 15:28:52, 15:29:10, 15:29:49 (`charge consumed for zealot_invisibility_improved`)
- ogryn_charge: PASS
  - visual: yes
  - charge consumed log: yes
  - key lines / timestamps: 15:28:29, 15:28:56, 15:29:46 (`charge consumed for ogryn_charge_increased_distance`)

Regression checks:
- basic combat loop: PASS (no crash signature in log)
- Lua errors: no new crash traceback in this segment

Conclusion:
- Remaining Tier 2 unknowns are resolved.
- Tier 2 is complete for all non-N/A rows.
```

### Run 2026-03-05-tier3-01 (item abilities)

```text
Run ID: 2026-03-05-tier3-01
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (post nil-account guard + item locks)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log (same rolling file)
Bot lineup / abilities: Zealot relic, Psyker force-field dome, Arbites Nuncio-Aquila; Hive Scum unavailable (DLC not owned)
Map + difficulty: mission segment in same game session

Tier 3 evidence:
- zealot_relic: PASS
  - visual: yes
  - charge consumed log: yes
  - blocked-switch / retry logs seen: yes (`blocked weapon switch while keeping zealot_relic ...`)
  - key lines / timestamps: 15:36:07 (`charge consumed for zealot_relic`)
- psyker_force_field_dome: PARTIAL
  - visual: yes
  - charge consumed log: yes (at least one)
  - blocked-switch / retry logs seen: yes (`blocked weapon switch while keeping psyker_force_field_dome sequence`)
  - key lines / timestamps: 15:36:04 (`charge consumed for psyker_force_field_dome`)
- adamant_area_buff_drone: FAIL (this run)
  - visual: no confirmed deploy effect
  - charge consumed log: no
  - blocked-switch / retry logs seen: repeated profile rotation
  - key lines / timestamps: repeated `fallback item finished without charge consume ...` for both `drone_regular` and `drone_instant` (15:35:57 through 15:36:26)
- broker_ability_stimm_field: BLOCKED
  - not testable in current environment (DLC not owned)

Regression checks:
- basic combat loop: PASS (no new crash signature in this segment)
- Lua errors: no new crash traceback in this segment

Conclusion:
- Relic and force-field consume events are confirmed in this run.
- Drone remains the active Tier 3 failure.
- Hive Scum stimm validation is blocked until DLC access exists.
```

### Run 2026-03-05-tier3-02 (item abilities, post drone lock extension)

```text
Run ID: 2026-03-05-tier3-02
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (post adamant_area_buff_drone sequence lock)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log (same rolling file)
Bot lineup / abilities: Zealot relic, Psyker force-field dome, Arbites Nuncio-Aquila
Map + difficulty: mission segment in same game session

Tier 3 evidence:
- zealot_relic: PASS
  - visual: yes
  - charge consumed log: yes (5 observed in this segment extraction)
  - blocked-switch / retry logs seen: yes (sequence + active lock lines present)
  - key lines / timestamps: 15:36:07, 15:37:26, 15:41:12, 15:43:00, 15:44:16 (`charge consumed for zealot_relic`)
- psyker_force_field_dome: PARTIAL
  - visual: yes (player-observed)
  - charge consumed log: yes (5 observed)
  - blocked-switch / retry logs seen: yes (many sequence lock lines)
  - key lines / timestamps: consumes at 15:36:04, 15:37:41, 15:42:20, 15:43:15, 15:44:22; no-charge completions remain frequent (24 observed)
- adamant_area_buff_drone: PARTIAL
  - visual: yes (player-observed at least one Nuncio-Aquila placement)
  - charge consumed log: yes (3 observed)
  - blocked-switch / retry logs seen: yes (sequence lock lines now present)
  - key lines / timestamps: consumes at 15:42:06, 15:42:45, 15:44:50; no-charge completions still dominate (39 observed), with repeated `aim/release` or `instant_aim/instant_release` followed by `finished without charge consume`
- broker_ability_stimm_field: BLOCKED
  - not testable in current environment (DLC not owned)

Regression checks:
- basic combat loop: PASS (no new BetterBots crash signature in this segment)
- Lua errors: no BetterBots traceback tied to this run segment

Conclusion:
- Zealot relic is stable in this run.
- Force-field and Nuncio-Aquila both work intermittently, but reliability is still below acceptable for "set-and-forget" behavior.
- Tier 3 focus should shift from "works at least once" to reliability hardening.
```

### Run 2026-03-05-tier3-03 (post timing patch smoke)

```text
Run ID: 2026-03-05-tier3-03
Date (local): 2026-03-05
Date (UTC): 2026-03-05
Git commit: local (timing/profile update: instant_place_force_field + slower unwield/longer confirmation)
Log file: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log (same rolling file)
Bot lineup / abilities: Zealot relic, Psyker force-field dome, Arbites Nuncio-Aquila
Map + difficulty: mission segment in same game session

Tier 3 evidence:
- zealot_relic: PASS (unchanged; not re-targeted in this slice)
- psyker_force_field_dome: PARTIAL
  - visual: yes (player-observed at least two deployments)
  - charge consumed log: yes (post-patch window contains consumes at 16:01:33, 16:02:00, 16:02:47, 16:03:05)
  - key window metric (from first `instant_place_force_field` onward): 4 consume vs 34 no-charge
- adamant_area_buff_drone: PARTIAL
  - visual: yes (multiple observed deployments)
  - charge consumed log: yes (post-patch window contains consumes at 15:57:29, 15:58:41, 16:01:25, 16:02:35, 16:02:46, 16:03:42, 16:03:46)
  - key window metric (from first `instant_place_force_field` onward): 7 consume vs 26 no-charge

Conclusion:
- Patch is active in runtime logs (`instant_place_force_field` is now queued).
- Force-field and drone both produce post-patch consume evidence.
- Reliability is still mixed, but behavior is acceptable for today’s validation stop.
```

### Run 2026-03-06-heuristics-01

```text
Run ID: 2026-03-06-heuristics-01
Date (local): 2026-03-06
Date (UTC): 2026-03-06
Git commit: e9e7610 (post refactor + heuristics)
Log file: console-2026-03-06-10.38.03-679b7ed4-cec1-49d3-adeb-5299fd03a39b.log
Bot lineup / abilities: Veteran (VoC), Psyker (Venting Shriek), Ogryn (Point-Blank Barrage), Zealot (Shroudfield)
Map + difficulty: mission (standard)

Heuristic validation evidence:
- veteran_combat_ability (VoC): PASS
  - queued: 4 (rule=veteran_voc_surrounded, nearby=4-10)
  - charge consumed: 10 (veteran_combat_ability_shout)
  - hold rules observed: veteran_voc_block_safe_state (13), veteran_voc_hold (3)
  - note: 6 consumes without matching fallback-queue = BT condition path (expected)

- psyker_shout: PASS
  - queued: 10 (rule=psyker_shout_surrounded, nearby=3-7)
  - charge consumed: 11 (psyker_discharge_shout_improved)
  - hold rules observed: psyker_shout_block_low_value (7)

- ogryn_gunlugger_stance: PASS
  - queued: 2 (rule=ogryn_gunlugger_high_threat)
  - charge consumed: 2 (ogryn_ranged_stance)
  - hold rules observed: ogryn_gunlugger_block_melee_pressure (42), block_target_too_close (22), block_low_threat (4)

- zealot_invisibility: PASS
  - queued: 2 (rules: zealot_stealth_overwhelmed nearby=10, zealot_stealth_ally_reposition nearby=8)
  - charge consumed: 2 (zealot_invisibility_improved)
  - hold rules observed: zealot_stealth_hold (64)

Not covered (different bot loadout needed):
- veteran_stealth_combat_ability, veteran_combat_ability (ranger/stance)
- zealot_dash
- psyker_overcharge_stance
- ogryn_charge, ogryn_taunt_shout
- adamant_stance, adamant_charge, adamant_shout
- broker_focus, broker_punk_rage

Regression checks:
- basic combat loop: PASS
- Lua errors: 1 engine error (script_world.lua get_data nil World), not BetterBots

Conclusion:
- 4/13 heuristic functions validated with correct activate + hold behavior
- Hold rules are actively suppressing low-value activations (157 combat holds vs 18 queued)
- Next: swap bot loadouts to cover remaining 9 heuristic functions
```

### Run 2026-03-06-heuristics-02b

```text
Run ID: 2026-03-06-heuristics-02b
Date (local): 2026-03-06
Date (UTC): 2026-03-06
Git commit: 452ed12 (post threshold loosening + log noise reduction)
Log file: console-2026-03-06-13.10.29-496d0373-62c7-4a55-9e45-3224b9dcb189.log
Bot lineup / abilities: Veteran (Executioner's Stance), Zealot (Fury of the Faithful), Psyker (Scrier's Gaze), Ogryn (Indomitable/charge)
Map + difficulty: mission (standard)

Heuristic validation evidence:
- veteran_combat_ability (ranger): PASS
  - queued: 1 (rule=veteran_stance_target_elite_special)
  - charge consumed: 1 (veteran_combat_ability_stance_improved)
  - hold rules observed: veteran_stance_hold (17), veteran_stance_block_surrounded (8)

- zealot_dash: PASS
  - queued: 5 (rules: combat_gap_close ×4, elite_special_gap ×1)
  - charge consumed: 5 (zealot_targeted_dash_improved_double)
  - hold rules observed: zealot_dash_hold (8), zealot_dash_block_target_too_close (4)
  - note: new combat_gap_close trigger is the primary activation rule

- psyker_overcharge_stance: PASS
  - queued: 0 (activated via BT condition path, not fallback)
  - charge consumed: 2 (psyker_overcharge_stance)
  - hold rules observed: psyker_stance_block_peril_window (5), psyker_stance_hold (1)
  - note: bot generates peril via staff attacks; exploded twice from overcharge
  - finding: peril=0 bypass works, but Scrier's Gaze builds peril with no vent ability

- ogryn_charge: PASS
  - queued: 1 (rule=ogryn_charge_ally_aid)
  - charge consumed: 1 (ogryn_charge_increased_distance)
  - hold rules observed: ogryn_charge_block_target_too_close (15), ogryn_charge_hold (10)
  - note: Ogryn stays in melee most of the time, limiting charge opportunities

Regression checks:
- basic combat loop: PASS
- Lua errors: 0 error lines

Conclusion:
- 4/4 targeted heuristics validated with correct rule + hold behavior
- Zealot dash combat_gap_close is the dominant activation path — lenient threshold working
- Psyker stance overcharge explosion is a new known issue — needs peril budget or stance cancellation
- Heuristic validation now at 8/13 PASS
```

### Run 2026-03-07-tier3-final (Tier 3 reliability validation)

```text
Run ID: 2026-03-07-tier3-final
Date (local): 2026-03-07
Date (UTC): 2026-03-07
Git commit: f092be1 (feat/tier3-reliability-heuristics, merged to main as 9d409e8)
Log file: console-2026-03-07-18.53.28-afefc763-305e-4973-9d27-677b17aa17ee.log
Bot lineup / abilities: Zealot (Bolstering Prayer/relic), Psyker (Telekine Shield dome), Arbites (Nuncio-Aquila)
Map + difficulty: mission (standard)

Fixes validated in this run:
- wield_slot hook redirects to slot_combat_ability instead of returning nil (breaks cancel loop)
- followup_delay shortened: force_field_regular 1.2→0.35, drone_regular 1.9→0.35
- build_context excludes self from allies_in_coherency count

Tier 3 evidence:
- zealot_relic: PASS
  - visual: yes
  - charge consumed log: yes (2 consumes at 19:00:58, 19:01:04)
  - key lines: `charge consumed for zealot_relic (charges=1)`
- psyker_force_field_dome: PASS
  - visual: yes
  - charge consumed log: yes (1 consume at 18:59:12)
  - key lines: `charge consumed for psyker_force_field_dome (charges=1)`
- adamant_area_buff_drone: PASS
  - visual: yes (multiple aquila deployments observed)
  - charge consumed log: yes (5 consumes at 18:54:56, 18:56:18, 18:58:03, 18:59:07, 19:00:36)
  - key lines: `charge consumed for adamant_area_buff_drone (charges=1)`
- broker_ability_stimm_field: BLOCKED
  - not testable (DLC not owned)

Reliability: 8 consumed, 0 no-charge completions = 100.0%

Regression checks:
- basic combat loop: PASS
- Lua errors: 1 modding_tools on_unload error (not BetterBots)

Conclusion:
- All three testable Tier 3 abilities at 100% consume rate.
- #3 closed.
```

### Run 2026-03-11-m5batch-01 (M5 batch: grenade, pinging, target selection, daemonhost)

```text
Run ID: 2026-03-11-m5batch-01
Date (local): 2026-03-11
Date (UTC): 2026-03-11
Git commit: a178251 (dev/m5-batch1)
Log files:
  0: console-2026-03-11-17.40.36-...bf048e0d2bd0.log (post wield-block split fix)
  3: console-2026-03-11-15.23.41-...d75639931113.log
  4: console-2026-03-11-14.40.45-...c04eb02d483a.log
Bot lineup / abilities: Veteran (VoC + krak grenade), Zealot (dash + fire grenade),
  Psyker (Scrier's Gaze + chain lightning), + variable 4th
Map + difficulty: mission (standard)

#4 Grenade throw evidence:
- veteran_krak_grenade: PASS
  - charge consumed: yes (5 in log 0)
  - forced unwield timeouts: 0
  - wield lock active: yes (blocked weapon switch during sequence)
  - key lines: 17:42:38 "grenade charge consumed for veteran_krak_grenade"
               17:42:38 "grenade throw complete, slot returned to slot_secondary"
- zealot_fire_grenade: PASS
  - charge consumed: yes (3 in log 0)
  - forced unwield timeouts: 0
  - key lines: 17:42:38 "grenade charge consumed for zealot_fire_grenade"
               17:42:48 "grenade throw complete, slot returned to slot_secondary"
- psyker_chain_lightning: correctly blocked (unsupported blitz template)

#16 Bot pinging evidence:
- PASS
  - 4 ping events in log 0 for cultist_berzerker (elite)
  - multiple bots pinging (bot 2, 4, 5)
  - key lines: 17:43:07 "bot 5 pinged cultist_berzerker (reason: target_enemy)"
               17:43:11 "bot 4 pinged cultist_berzerker (reason: target_enemy)"

#17 Daemonhost avoidance evidence:
- UNVERIFIABLE
  - no daemonhost spawned in any of today's 5 sessions
  - no dh_suppress events in any log

#19 Distant special penalty evidence:
- PASS
  - logs 3-4: 30+ penalty events across chaos_hound, cultist_mutant,
    renegade_netgunner, renegade_flamer, renegade_grenadier, chaos_poxwalker_bomber
  - distance range: 324–3567 dist_sq (18–60m)
  - ammo check working: penalties only when ammo > 0.5
  - key lines: 15:34:51 "penalizing melee score for distant special renegade_netgunner dist_sq=1721"
               14:45:19 "penalizing melee score for distant special renegade_netgunner dist_sq=3567"

Regression checks:
- combat ability activation: PASS (17 fallback queued, 19 consumed in log 0)
- basic combat loop: PASS
- Lua errors: 0 error lines

Conclusion:
- #4 grenade PASS: krak + fire grenades confirmed, full throw cycle with charge consumed
- #16 pinging PASS: bots ping elites during combat
- #17 daemonhost: needs a daemonhost encounter to verify (opportunity-dependent)
- #19 distant specials PASS: penalty firing across 6 special breeds at range
```

## Reliability Snapshot (current)

```text
Source log: console-2026-03-07-18.53.28-afefc763-305e-4973-9d27-677b17aa17ee.log
Git commit: f092be1
Method: success_rate = consume_events / (consume_events + no_charge_completions)

- zealot_relic: 2 success, 0 no-charge => 100.0%
- psyker_force_field_dome: 1 success, 0 no-charge => 100.0%
- adamant_area_buff_drone: 5 success, 0 no-charge => 100.0%
- overall: 8 success, 0 no-charge => 100.0%
```

Historical progression:
- Pre-fix (2026-03-05): relic 100%, force field ~13%, drone ~13%
- Post-timing-patch (2026-03-05): relic 100%, force field ~10%, drone ~21%
- Post-wield-redirect (2026-03-07): all 100%

## Tier 3 Root Cause Analysis (Stage 1 Research, 2026-03-06)

### Problem

Force field (~13%) and drone (~21%) have low success rates despite the item fallback state machine working end-to-end. Zealot relic (100%) works reliably with the same mechanism.

### Root cause: timing mismatch

The mod's `ITEM_SEQUENCE_PROFILES` advance the state machine to the next stage (followup/unwield) before the engine finishes processing the current input. The `followup_delay` and `unwield_delay` values were set too aggressively compared to actual engine action durations.

### Specific timing mismatches

| Ability | Profile | Mod `followup_delay` | Actual time needed | Buffer | Action `total_time` | Gap |
|---------|---------|---------------------|-------------------|--------|---------------------|-----|
| Drone | regular | 0.24s | ~1.9s | 0.6s `buffer_time` | 1.3s | **1.66s too fast** |
| Drone | instant | 0.1s | ~1.0s | 0s (`dont_queue=true`) | 1.0s | **0.9s too fast** |
| Force field | regular | 0.12s | ~1.2s | 0.6s `buffer_time` | 0.6s | **1.08s too fast** |
| Force field | instant | 0.12s | ~0.1s | 0s (`dont_queue=true`) | 0.1s | ~0s (close match) |

### Why "instant" variants perform better

Templates with `dont_queue = true` skip the 0.6s `buffer_time` penalty because the engine processes them immediately rather than queuing them for the next action window. This explains why the drone's instant profile (21.2% post-patch) outperforms its regular profile, and why force field instant is closer to working.

### Proposed fix values

| Ability | Profile | `followup_delay` | `unwield_delay` |
|---------|---------|-----------------|-----------------|
| Drone | regular | ~1.9s | ~2.3s |
| Drone | instant | 0.1s | ~1.1s |
| Force field | regular | ~1.2s | ~1.6s |
| Force field | instant | 0.12s (current) | ~0.5s |

### Why zealot relic works

Zealot relic's action is a simple channel with short duration. The mod's existing timing values happen to align with the engine's processing time, so the state machine stays in sync.

## Current Validation Matrix

Legend: `PASS` = repeated successful evidence in logs and in-game effect, `PARTIAL` = can work but unstable, `UNKNOWN` = not enough evidence.

### Tier 1 (Baseline)

| Ability Template | Status | Evidence Notes |
|---|---|---|
| `veteran_combat_ability` | PASS | run `2026-03-05-tier1-01`: `charge consumed for veteran_combat_ability_shout` |
| `veteran_stealth_combat_ability` | PASS | run H-03: 2 consumes (`veteran_combat_ability_stealth`), `stealth_hold` (37) |
| `psyker_overcharge_stance` | PASS | runs `2026-03-05-tier1-01` + `H-02b`: `charge consumed for psyker_overcharge_stance` (2 in H-02b) |
| `ogryn_gunlugger_stance` | PASS | run `2026-03-05-tier1-01`: `charge consumed for ogryn_ranged_stance` |
| `adamant_stance` | PASS | run `2026-03-05-tier1-01`: `charge consumed for adamant_stance` |
| `broker_focus` | UNKNOWN | not explicitly tracked in current status docs |
| `broker_punk_rage` | UNKNOWN | not explicitly tracked in current status docs |

### Tier 2 (`#1`)

| Ability Template | Status | Evidence Notes |
|---|---|---|
| `zealot_invisibility` | PASS | run `2026-03-05-tier2-03`: `charge consumed for zealot_invisibility_improved` |
| `zealot_dash` | PASS | runs `2026-03-05-tier2-02` + `H-02b`: 5 consumes in H-02b (`zealot_targeted_dash_improved_double`) |
| `ogryn_charge` | PASS | runs `2026-03-05-tier2-03` + `H-02b`: 1 consume in H-02b (`ogryn_charge_increased_distance`) |
| `ogryn_taunt_shout` | PASS | run `2026-03-05-tier2-01`: `charge consumed for ogryn_taunt_shout` |
| `psyker_shout` | PASS | run `2026-03-05-tier2-01`: `charge consumed for psyker_discharge_shout_improved` |
| `adamant_shout` | N/A | internal template present, but not currently exposed as Arbites player-facing ability in live UI |
| `adamant_charge` | PASS | run `2026-03-05-tier2-01`: `charge consumed for adamant_charge` |

### Tier 3 (`#3`)

| Ability Template | Status | Evidence Notes |
|---|---|---|
| `zealot_relic` | PASS | run `2026-03-07-tier3-final`: 2 consumes, 0 failures, 100% rate |
| `psyker_force_field*` | PASS | run `2026-03-07-tier3-final`: 1 consume, 0 failures, 100% rate |
| `adamant_area_buff_drone` | PASS | run `2026-03-07-tier3-final`: 5 consumes, 0 failures, 100% rate |
| `broker_ability_stimm_field` | BLOCKED | DLC not owned in current environment, cannot validate yet |

### Heuristic Validation (post-refactor, #2)

Legend: `PASS` = activated with correct rule + holds observed, `UNTESTED` = not in bot lineup yet.

| Heuristic Function | Template(s) | Status | Run | Rules fired |
|---|---|---|---|---|
| `_can_activate_veteran_combat_ability` (VoC) | `veteran_combat_ability` | PASS | H-01 | `voc_surrounded`, `voc_block_safe_state` |
| `_can_activate_veteran_combat_ability` (ranger) | `veteran_combat_ability` | PASS | H-02b | `stance_target_elite_special`, `stance_hold`, `stance_block_surrounded` |
| `_can_activate_veteran_stealth` | `veteran_stealth_combat_ability` | PASS | H-03 | 2 consumes (`veteran_combat_ability_stealth`); `stealth_hold` (37). Activated under pressure on standard difficulty. |
| `_can_activate_zealot_dash` | `zealot_dash`, `zealot_targeted_dash*` | PASS | H-02b | `combat_gap_close` (4), `elite_special_gap` (1), `dash_hold`, `block_target_too_close` |
| `_can_activate_zealot_invisibility` | `zealot_invisibility` | PASS | H-01 | `stealth_overwhelmed`, `stealth_ally_reposition`, `stealth_hold` |
| `_can_activate_psyker_shout` | `psyker_shout` | PASS | H-01 | `shout_surrounded`, `shout_block_low_value` |
| `_can_activate_psyker_stance` | `psyker_overcharge_stance` | PASS | H-02b | 2 consumes; `block_peril_window` (5), `stance_hold` (1). Bot generates peril via staff/stance — exploded twice from overcharge. See known issues. |
| `_can_activate_ogryn_charge` | `ogryn_charge*` | PASS | H-02b | `ally_aid` (1); `block_target_too_close` (15), `charge_hold` (10). Ogryn stays in melee, limiting charge opportunities. |
| `_can_activate_ogryn_taunt` | `ogryn_taunt_shout` | PASS | H-03 | 5 consumes; `horde_control` (3), `block_low_value` (11). |
| `_can_activate_ogryn_gunlugger` | `ogryn_gunlugger_stance` | PASS | H-01 | `gunlugger_high_threat`, `block_melee_pressure`, `block_target_too_close` |
| `_can_activate_adamant_stance` | `adamant_stance` | PASS | H-03 | 2 consumes; `low_toughness` (1), `block_safe_state` (20), `stance_hold` (27). |
| `_can_activate_adamant_charge` | `adamant_charge` | PASS | H-03 | 6 consumes; `block_target_too_close` (3), `charge_hold` (1). |
| `_can_activate_adamant_shout` | `adamant_shout` | N/A | — | not player-facing |
| `_can_activate_broker_focus` | `broker_focus` | UNTESTED | — | Hive Scum DLC not owned |
| `_can_activate_broker_rage` | `broker_punk_rage` | UNTESTED | — | Hive Scum DLC not owned |

### Item Heuristic Validation (#3)

Legend: `PASS` = activated with correct rule + holds observed, `UNTESTED` = not yet validated in-game.

| Heuristic Function | Ability Name(s) | Status | Run | Rules fired |
|---|---|---|---|---|
| `_can_activate_zealot_relic` | `zealot_relic` | PASS | 2026-03-07-tier3-final | 2 consumes; `self_critical` observed (toughness-gated activation) |
| `_can_activate_force_field` | `psyker_force_field*` | PASS | 2026-03-07-tier3-final | 1 consume; activated under combat pressure |
| `_can_activate_drone` | `adamant_area_buff_drone` | PASS | 2026-03-07-tier3-final | 5 consumes; activated reliably in combat |
| `_can_activate_stimm_field` | `broker_ability_stimm_field` | BLOCKED | — | Hive Scum DLC not owned |

### M5 Batch Validation (2026-03-11)

```text
Run ID: 2026-03-11-m5-batch1
Date (local): 2026-03-11
Date (UTC): 2026-03-11
Git commit: 8cce4bd (post hot-reload)
Log file: console-2026-03-11-18.25.35-84b3f3e9-7c0c-4425-9c6e-3dd118b4a90d.log
Bot lineup / abilities: Arbites (whistle blitz, standard grenades), bots with force staves
Map + difficulty: Standard mission, Tertium 5/6 bots

Staff charged fire (#43):
- p2 Purgatus (trigger_charge_flame): PASS
  - _may_fire swap confirmed: fire=shoot_pressed -> aim_fire=trigger_charge_flame (18:54:54.306)
  - charge override count: 4 (all staves matched, up from 1 pre-fix)
- p3 Surge / p4 Equinox (shoot_charged): PASS
  - _may_fire swap confirmed: fire=shoot_pressed -> aim_fire=shoot_charged (19:15:05.813)
  - p4 already PASS from v0.5.0; p3 uses same input, structurally identical
- p1 Voidstrike (trigger_explosion): PASS
  - _may_fire swap confirmed: fire=shoot_pressed -> aim_fire=trigger_explosion (20:04:16.133, run 2026-03-11-m5-fresh)
  - bot=2, weapon_template=forcestaff_p1_m1

Grenade/blitz (#4):
- Standard grenades (krak, fire): PASS (confirmed in earlier session, 7 charges)
- Zealot knives: PASS (auto-fire observed)
- Adamant whistle: PASS (fresh launch; FAIL after hot-reload)
  - 3/3 activations: charge confirmed
  - action_aim started from aim_pressed, chained to action_order_companion via aim_released
  - Charge consumed ~1s after activation (0.15s throw_delay + 0.3s trigger_time + frame latency)
  - Timestamps: 20:04:18.955→20:04:20.155, 20:04:22.151→20:04:23.348, 20:05:37.444→20:05:38.641
  - Hot-reload failure (previous session): component template_name likely reset to "none" by DMF reload
- Shock mine: UNTESTED (no bot equipped)
- Ogryn cluster grenades: PASS — 3 charges consumed (20:04:18.824, 20:04:22.779, 20:04:26.347)
- Zealot throwing knives: PASS — 8+ charges consumed; wield timeout noise (quick_throw returns to previous slot before our wield detection fires)
```

### Run 2026-03-11-m5-fresh

```text
Run ID: 2026-03-11-m5-fresh
Date (local): 2026-03-11
Date (UTC): 2026-03-11
Git commit: 8cce4bd (fresh launch, no hot-reload)
Log file: console-2026-03-11-20.01.33-7a0c9c5e-47ea-4b35-994c-aca0c09fc50b.log
Bot lineup / abilities: Arbites (whistle), Psyker (smite), Zealot (throwing knives), Ogryn (cluster grenades)
  Bot 2: forcestaff_p1_m1 (Voidblast)
Map + difficulty: Standard mission

Staff charged fire (#43):
- p1 Voidblast (trigger_explosion): PASS
  - _may_fire swap: fire=shoot_pressed -> aim_fire=trigger_explosion (20:04:16.133)
  - bot=2, weapon_template=forcestaff_p1_m1
- All 4 staves now confirmed PASS (p2 Purgatus in earlier session, p3/p4 in earlier session, p1 this session)

Later note (2026-04-23): that p1 signal turned out to be insufficient. A later live log still showed `forcestaff_p1_m1` entering `action_charge` and then falling back to plain `shoot_pressed` / `vent` with no `voidblast ...` confirmation, so the current branch treats p1 as re-validation pending after the live-`action_charge` fix.

Grenade/blitz (#4):
- Adamant whistle: PASS — 3/3 charge confirmed
- Ogryn cluster grenades: PASS — 3 charges consumed
- Zealot throwing knives: PASS — 8+ charges consumed (wield timeout noise, not real failure)
- Shock mine: UNTESTED

Regression checks:
- revive/rescue: PASS
- navigation/pathing: PASS
- basic combat loop: PASS
- Lua errors: no

Conclusion:
- #43 all 4 staves PASS. Issue can be closed.
- #4 whistle PASS on fresh launch. Hot-reload failure is dev-only, not a shipping blocker.
- Zealot knives wield timeout is cosmetic — quick_throw fires before wield detection.
- Shock mine still needs a bot equipped with it.

Bot pinging (#16): PASS (confirmed in earlier session)
Distant special penalty (#19): PASS (confirmed in earlier session)
Daemonhost avoidance (#17): UNVERIFIABLE (no spawn)

Regression checks:
- revive/rescue: PASS
- navigation/pathing: PASS
- basic combat loop: PASS
- Lua errors: no

Conclusion:
- #43 staff p2/p3/p4: promote to PASS. p1 needs dedicated test.
- #4 grenades: PASS. Whistle: FAIL, needs diagnosis.
- Batch overall: ready for merge except whistle (can ship independently).
```

**Template heuristic summary: 12/13 PASS, 1 N/A, 2 Hive Scum DLC-blocked.**
**Item heuristic summary: 3/3 testable PASS, 1 Hive Scum DLC-blocked.**

**Remaining validation runs needed:**

1. **Run H-04** (optional, Hive Scum DLC-gated): Hive Scum (Focus) + Hive Scum (Rage)
   - Covers: `broker_focus`, `broker_punk_rage`

## dev/m5-batch2 Test Plan

Branch: `dev/m5-batch2` | Archived plan: `docs/superpowers/plans/2026-03-12-m5-batch2.md`

### Features under test

| Issue | Feature | What to verify |
|-------|---------|---------------|
| #40 | Tiered log levels | Off→silent; Info→patches only; Debug→decisions; Trace→sprint/suppression per-frame |
| #15 | Dodge suppression | Research-only — close if audit confirms no interaction |
| #34 | Poxburster targeting | Bots shoot at range, suppress when poxburster near human player |
| #16 | Ping anti-spam | Tag holds on one elite until death; no flipping; closer elite triggers escalation |
| #18 | Boss engagement | Vanilla deprioritization preserved; bot fights back when boss targets it |
| #48 | Player-tag smart-target response | Human-tagged elite/special/monster gets a modest target-selection score bonus without yanking bots out of active melee |
| #21 | Hazard abilities | Defensive ability (relic/shout) in fire/gas; no regression to Arbites stance defensive use |
| #39 | Healing deferral | Bot defers health station/med-crate/pickup to human; emergency override at <25% bot HP |
| #4 | Grenade heuristics | Krak→elite only; frag→horde 4+; smoke/shock→pressure tools; Psyker Assail/Smite/Chain Lightning fire with peril gate |

### Pre-test checklist

- [ ] All feature branches merged to `dev/m5-batch2`
- [ ] `make check` PASS on merged branch
- [ ] Bot loadouts cover: standard grenades, krak, smoke, throwing knives, psyker blitz, whistle
- [ ] Mod settings: test each log level setting
- [ ] Mission with mixed enemies (horde + elites + specials) for grenade heuristic validation
- [ ] Mission with hazard zones (fire/gas) for #21 validation

### Current status (2026-03-12)

| Issue | Feature | Status | Evidence / gap |
|-------|---------|--------|----------------|
| #15 | Dodge suppression audit | PASS | Audit-only, closed as not-a-bug |
| #16 | Ping anti-spam | PASS | Ping events seen in early `dev/m5-batch2` run |
| #18 | Boss engagement | PASS | Consume/engagement evidence seen in early `dev/m5-batch2` run |
| #48 | Player-tag smart-target response | PASS | Repeated `boosting score for player-tagged ... +3` lines in run `2026-03-12-m5-batch2-03` |
| #21 | Hazard abilities | PASS | `zealot_relic_hazard` confirmed earlier; `veteran_voc_hazard` observed in latest `dev/m5-batch2` run |
| #34 | Poxburster targeting | PASS | `suppressed poxburster target (near_human_player)` and `(too_close_to_bot)` at `Debug` |
| #39 | Healing deferral | UNKNOWN | No in-mission trigger logged yet |
| #40 | Tiered log levels | PASS | `Info/Debug/Trace` behavior exercised during batch2 validation; startup debug chatter now obeys level gating and event-log-backed post-run validation is usable |
| #4 | Grenade heuristics + Psyker blitz | PASS | Grenades/knives/whistle work; Assail validated on both `shoot` and `zoom -> zoom_shoot`; Smite validated on `charge_power_sticky -> use_power`; Chain Lightning validated on `charge_heavy -> shoot_heavy_hold -> shoot_heavy_hold_release -> action_spread_charged` |

### Run 2026-03-12-m5-batch2-05

```text
Run ID: 2026-03-12-m5-batch2-05
Date (local): 2026-03-12
Date (UTC): 2026-03-12
Git commit: local (post universal testing-profile leniency + Assail dual-path + foreign-input guard)
Log file: console-2026-03-12-20.33.39-6cf09325-5a2b-46e1-81c1-1df9d57d8da9.log
Bot lineup / abilities: included Psyker Assail, Psyker Smite, Veteran shout, Zealot relic, Psyker shield wall
Map + difficulty: mixed-combat mission

Stability:
- Lua errors: no BetterBots-specific error lines
- basic combat loop: PASS

#4 Grenade/blitz:
- psyker_assail: PASS
  - `bb-log summary`: 13 consumes for `psyker_throwing_knives`
  - both paths observed:
    - close/pressure path: `action=shoot`
    - aimed path: `action=zoom` then `action=zoom_shoot`
  - strongest success confirmation:
    - `grenade external action confirmed for psyker_throwing_knives (action=action_rapid_zoomed)`
- psyker_smite: PASS
  - intended sequence observed:
    - `weapon_template=psyker_smite ... action=charge_power_sticky`
    - `weapon_template=psyker_smite ... action=use_power`
  - old `charge_release` parser-noise no longer appears in this run
- guard behavior:
  - stray foreign inputs are now blocked and logged (`blocked foreign weapon action ... while keeping ...`) instead of being queued into the Psyker blitz templates

#40 Tiered log levels:
- PASS
  - debug-level validation logs remain visible and actionable during this run
  - startup debug chatter is gated behind Debug/Trace instead of always echoing at load

Conclusion:
- Assail and Smite are now validated in practice.
- The shared foreign-input guard removed the old Psyker blitz parser-noise path.
- #4 is ready for closure pending a final clean Chain Lightning confirmation.
```

### Run 2026-03-12-m5-batch2-06

```text
Run ID: 2026-03-12-m5-batch2-06
Date (local): 2026-03-12
Date (UTC): 2026-03-12
Git commit: local (post foreign-input guard)
Log file: console-2026-03-12-20.44.32-4a4f2a96-387f-4ab4-9bbf-ddc54b64a498.log
Bot lineup / abilities: included Psyker Chain Lightning
Map + difficulty: mixed-combat mission

Stability:
- Lua errors: no BetterBots-specific error lines
- basic combat loop: PASS

#4 Grenade/blitz:
- psyker_chain_lightning: PASS
  - intended heavy path observed:
    - `charge_heavy`
    - `shoot_heavy_hold`
    - `shoot_heavy_hold_release`
  - strongest success confirmation:
    - `grenade external action confirmed for psyker_chain_lightning (action=action_spread_charged)`
  - stray foreign inputs are blocked and logged instead of leaking into the template:
    - `blocked foreign weapon action charge_release while keeping psyker_chain_lightning wield`

Conclusion:
- Chain Lightning is now validated on the charged crowd-control path.
- With Assail and Smite already validated in the previous run, the Psyker blitz portion of #4 is complete.
```

### Run 2026-03-12-m5-batch2-04

```text
Run ID: 2026-03-12-m5-batch2-04
Date (local): 2026-03-12
Date (UTC): 2026-03-12
Git commit: local (post perf-instrumentation + Smite use_power fix)
Log file: console-2026-03-12-19.26.03-abeda3ac-73d0-4ce4-82c9-341ad6a28ab1.log
Bot lineup / abilities: included Veteran shout, Psyker dome + Smite, Zealot relic
Map + difficulty: mixed-combat mission

Stability:
- Lua errors: no
- basic combat loop: PASS

#21 Hazard abilities:
- PASS
  - `veteran_voc_hazard` observed once in this run
  - `zealot_relic_hazard` continues to appear in the same run

#4 Grenade/blitz:
- psyker_smite: PARTIAL PASS
  - repeated live sequence:
    - `grenade queued charge_power_sticky`
    - `grenade queued use_power`
    - `grenade external action confirmed for psyker_smite (action=action_use_power)`
  - residual issue:
    - intermittent `Could not find matching input_sequence for queued action_input "charge_release" in template "psyker_smite"`
- psyker_force_field_dome: PASS
  - one full confirmed activation:
    - `fallback item queued psyker_force_field_dome input=combat_ability`
    - `aim_force_field`
    - `place_force_field`
    - `charge consumed for psyker_force_field_dome`
    - `fallback item confirmed charge consume ... (rule=force_field_ranged_pressure)`
  - a second dome attempt started in the same run but was not cleanly confirmed to completion from logs alone
- psyker_assail:
  - no in-game evidence yet in this run

Conclusion:
- #21 can be promoted to PASS.
- Dome remains validated.
- Smite now works in practice, but the residual `charge_release` parser-noise keeps the Psyker blitz work short of fully clean.
- #4 remains open for Assail evidence and Smite cleanup.
```

### Run 2026-03-12-m5-batch2-02

```text
Run ID: 2026-03-12-m5-batch2-02
Date (local): 2026-03-12
Date (UTC): 2026-03-12
Git commit: local (post poxburster-debug + item-rule-attribution + grenade cleanup-lock fixes)
Log file: console-2026-03-12-15.24.57-b0aee589-fffe-4c97-9b36-17973ef85b25.log
Bot lineup / abilities: included Zealot relic, Veteran shout, Psyker Chain Lightning
Map + difficulty: mixed-combat mission with hazards and multiple poxbursters

#34 Poxburster targeting:
- PASS
  - `suppressed poxburster target (near_human_player)`
  - `suppressed poxburster target (too_close_to_bot)`

#21 Hazard abilities:
- zealot_relic: PASS
  - visual: yes
  - rule-attributed log: yes
  - key lines: `fallback item queued zealot_relic input=channel (rule=zealot_relic_hazard)`
               `fallback item confirmed charge consume for zealot_relic (profile=channel, rule=zealot_relic_hazard)`
- veteran_combat_ability_shout: PARTIAL
  - visual: yes (general shout use)
  - hazard-specific rule: no
  - key lines: repeated `hazard=true` decisions with `rule=veteran_voc_hold`; no `veteran_voc_hazard` observed

#4 Grenade/blitz:
- zealot_throwing_knives: PASS
- adamant_whistle: PASS
- ogryn_grenade_box_cluster: PASS
- psyker_chain_lightning: FAIL
  - visual: player observed only light-cast behavior
  - strongest log signal: queued `shoot_light_pressed` then `shoot_light_hold_release`
  - no charged-path evidence (`charge_heavy` / `shoot_heavy_hold`) in this run

Regression checks:
- Lua errors: no
- basic combat loop: PASS

Conclusion:
- #34 is validated.
- #21 is partially validated: hazard-triggered relic works, hazard-triggered veteran shout still needs an in-game hit.
- #4 remains open because Chain Lightning is using the light path instead of the charged crowd-control path documented for bot use.
```

### Run 2026-03-12-m5-batch2-03

```text
Run ID: 2026-03-12-m5-batch2-03
Date (local): 2026-03-12
Date (UTC): 2026-03-12
Git commit: local (post Chain Lightning charged-path + relic interaction lock guard fixes)
Log file: console-2026-03-12-17.25.56-9995a2c3-d860-4399-a7fa-5158b17afc61.log
Bot lineup / abilities: included Zealot relic, Veteran shout, Psyker Chain Lightning
Map + difficulty: mixed-combat mission

Stability:
- Lua errors: no
- basic combat loop: PASS

#48 Player-tag smart-target response:
- PASS
  - repeated confirmation lines:
    - `boosting score for player-tagged renegade_grenadier +3`
    - `boosting score for player-tagged cultist_flamer +3`

#21 Hazard abilities:
- zealot_relic: PASS
  - key lines:
    - `fallback item queued zealot_relic input=channel (rule=zealot_relic_hazard)`
    - `fallback item confirmed charge consume for zealot_relic (profile=channel, rule=zealot_relic_hazard)`
- veteran_combat_ability_shout: not re-observed on hazard-specific rule in this run

#4 Grenade/blitz:
- psyker_chain_lightning: PARTIAL
  - charged heavy path observed:
    - `grenade queued wield for psyker_chain_lightning (rule=grenade_chain_lightning_crowd)`
    - `charge_heavy`
    - `shoot_heavy_hold`
    - `shoot_heavy_hold_release`
  - strongest success confirmation:
    - `grenade external action confirmed for psyker_chain_lightning (action=action_spread_charged)`
    - `grenade released cleanup lock without explicit unwield (action confirmed)`
  - gap:
    - many later attempts still end with `grenade released cleanup lock without explicit unwield (slot changed)` and no matching `action confirmed` line, so reliability is still mixed

Relic interaction crash guard:
- PARTIAL
  - no crash reproduced in this run
  - the exact former crash path (interaction entry requesting `slot_unarmed` while relic lock is active) was not directly re-hit, so the guard fix is not yet specifically validated

Conclusion:
- #48 is validated.
- #21 remains partial.
- #4 improves from “light path only” to “charged path confirmed once, but inconsistent.”
- The branch is stable in this run, but the relic interaction fix still needs a direct interaction-state re-test.
```

### Run 2026-03-13-p0-p1-stabilization-01

```text
Run ID: 2026-03-13-p0-p1-stabilization-01
Date (local): 2026-03-13
Date (UTC): 2026-03-13
Git commit: local (exact SHA not captured in run log)
Log file: console-2026-03-13-13.21.23-06323070-33d6-49e5-9e07-a918eea1e556.log
Bot lineup / abilities: 4 Arbites bots; repeated Nuncio-Aquila drone + whistle usage
Map + difficulty: extended mission session (stress run)

Stability:
- Lua errors: no
- basic combat loop: PASS
- startup/load: PASS (`BetterBots loaded`)

#50 Arbites drone crash guard:
- PASS
  - no `Script Error`, `Lua Stack`, or crash lines in the session log
  - repeated successful drone sequences observed:
    - `fallback item queued adamant_area_buff_drone input=combat_ability`
    - `fallback item queued adamant_area_buff_drone input=aim_drone`
    - `fallback item queued adamant_area_buff_drone input=release_drone`
    - `charge consumed for adamant_area_buff_drone (charges=1)`
  - summary counts:
    - 12 consumes for `adamant_area_buff_drone`
    - 12 consumes for `adamant_whistle`
  - note: the specific animation-guard fallback branch did not log in this run, so this is strong no-crash evidence rather than direct proof of the fallback path

#51 Ranged ammo threshold override:
- PARTIAL
  - live-session evidence only:
    - repeated `ranged ammo gate lowered from 0.5 to 0.2`
  - this confirms the override is active in-game, but this run does not prove user-visible ranged behavior across the full 20%-50% reserve window

#61/#62 Precision targeting / grenade aim:
- UNKNOWN
  - not meaningfully exercised in this Arbites-only run

#52 Melee heavy-bias reduction:
- UNKNOWN
  - not evidenced in log and not isolated by this run composition

Conclusion:
- The branch survives an extended 4-Arbites stress run with repeated drone and whistle activations and no crash signature.
- #50 now has strong in-game stability evidence.
- Remaining validation should focus on a mixed lineup that can exercise smart targeting, grenade aim, and melee attack choice.
```

**New issue discovered in H-02b:**

Psyker bot exploded twice from warp overcharge. Scrier's Gaze builds peril while active, and without Venting Shriek (different ability slot) the bot has no way to vent. The `block_peril_window` gate correctly prevents re-activation at high peril, but cannot cancel an active stance. Needs investigation — possible mitigations:
- Block Scrier's Gaze activation if bot lacks a peril vent ability
- Lower the peril ceiling for stance activation (e.g., block above 0.50 instead of 0.90)
- Tie into stance cancellation (#12) to exit early when peril is critical

### Run 2026-04-07-profile-overhaul

```text
Run ID: 2026-04-07-profile-overhaul
Date (local): 2026-04-07
Date (UTC): 2026-04-07
Git commit: 8520485 (dev/v0.9.1)
Log file: (hot-reload session, no dedicated log captured)
Bot lineup / abilities:
  Veteran: Voice of Command + Focus Target + plasma + Devil's Claw
  Zealot: Chorus + Martyrdom keystone + Relic Blade + Flamer + Benediction aura
  Psyker: Venting Shriek + Warp Siphon + Force Greatsword m1 + Voidblast staff p4
  Ogryn: Indomitable charge + Heavy Hitter keystone + Bully Club + Rumbler
Map + difficulty: hot-reload test session

Profile loading:
- PASS
  - all 4 classes loaded successfully after hot-reload
  - user confirmed "works" — bots spawned with correct archetypes and weapons
  - Tertium "None" yield fix (#68): profile.name guard prevents overwriting

Later default-profile swap (2026-04-20):
- The shipped built-in defaults were later retuned for validation coverage and no longer match the April 7 lineup above.
- Current defaults: Veteran = VoC + Focus Target + precision lasgun + chainsword; Zealot = Fury + Martyrdom + chainaxe + stub revolver; Psyker = Scrier's Gaze + Brain Rupture + electrokinetic staff + force sword; Ogryn = Point-Blank Barrage + Kickback + latrine shovel.
- That later swap has static coverage and profile-loading coverage, but it does not yet have a dedicated live mission entry in this tracker.
    Tertium/SoloPlay external profiles (validated in earlier run 0)

Ability activation:
- UNKNOWN
  - hot-reload session confirms profiles load, but abilities need a full
    fresh-launch mission to validate activation with the new talent trees

Regression checks:
- revive/rescue: UNKNOWN
- navigation/pathing: UNKNOWN
- basic combat loop: PASS (bots fighting observed)
- Lua errors: no

Conclusion:
- Bot profile overhaul loads in-game. Full mission validation needed to
  confirm ability activation and talent synergies with the new builds.
- Tertium None yield fix (#68) already validated in earlier session.
```

### Run 2026-04-11-dh-first-spawn

```text
Run ID: 2026-04-11-dh-first-spawn
Date (local): 2026-04-11
Date (UTC): 2026-04-11
Git commit: 74e0d43 (v0.10.0, pre-fix)
Log file: console-2026-04-11-16.51.08-7b0e1b12-f7ec-459e-8dd6-2d556581d8d0.log
JSONL file: betterbots_events_1775926799.jsonl
Bot lineup / abilities:
  Psyker: discharge_shout_improved + smite blitz + forcestaff_p2_m1 + forcesword
  Veteran: combat_ability_shout + krak grenade + lasgun_p3_m2 + combatknife
  Ogryn: charge_increased_distance + grenade_box_cluster + ogryn_rippergun_p1_m1 + ogryn_combatblade
  Zealot: invisibility_improved + zealot_throwing_knives + combatknife + flamer_p1_m1
Map + difficulty: live mission, chaos_daemonhost spawned via monster pacing

#17 Daemonhost avoidance evidence:
- FAIL (GAP EXPOSED)
  - DH spawned 17:01:26
  - 17:02:42.732 bot 5 pinged chaos_daemonhost (reason: target_enemy)
    — bots were already targeting dormant DH from vanilla selection
  - 17:02:42.753 "grenade queued wield for psyker_smite (rule=grenade_smite_priority_target)"
    — psyker_smite approved against dormant DH, no suppression
  - JSONL line 54953 at t=165.71: psyker_smite decision result=true,
    ctx.target_enemy=chaos_daemonhost, target_is_monster=true,
    num_nearby=0, monster_count=0, priority/urgent/opportunity_target_enemy=none
  - 17:02:44.963 smite landed ("grenade external action confirmed for psyker_smite")
  - 17:02:43.827 onward "restoring monster weight for boss targeting bot chaos_daemonhost"
    — post-aggro amplifier (secondary, not the ignition)
  - ZERO dh_suppress_melee / dh_suppress_ranged log lines in the entire session
    — the condition_patch wrappers never fired because they sit on BT
    melee/shoot conditions; grenades and blitzes go through grenade_fallback
    and can_activate_ability, bypassing those wrappers entirely.

Root cause:
- heuristics_context.lua `build_context()` set `target_is_monster=true` for DH
  (vanilla breed tag) with no daemonhost awareness.
- heuristics_grenade.lua `_grenade_priority_target` used `target_is_monster` as a
  green-light priority-target signal without a DH carve-out. Fires for
  smite / psyker knives / vet krak / zealot knives / ogryn rock / broker missile.
- heuristics_grenade.lua `_grenade_assail` monster fast-path same issue.
- heuristics_arbites.lua `_can_activate_adamant_stance` monster_pressure same.
- heuristics_arbites.lua `_can_activate_drone` monster_fight same.

Fix staged (local, not yet pushed, not yet re-validated):
- 03ce4fd fix(heuristics): refuse dormant daemonhost via target_is_dormant_daemonhost (#17)
- ffe7c6b test(heuristics): cover build_context DH flag + patch testing_profile gap (#17)
- Adds ctx.target_is_dormant_daemonhost flag in build_context via global
  aggro_state check against the target breed's perception blackboard.
- Global semantics (not bot-relative): once DH enters aggro_state=aggroed
  on anyone, the whole group commits — trying to run from a triggered DH
  is not a recoverable tactic.
- Gates 5 heuristic sites via shared _is_monster_signal_allowed helper.
- Wires daemonhost_avoidance setting (#81) into Heuristics.init so the
  toggle actually affects the grenade/blitz path (previously only affected
  condition_patch and sprint).
- Tests: 796 → 813 (+17 cases including direct build_context coverage).

Open (deferred, separate issue worth filing):
- How chaos_daemonhost enters bot target_enemy pre-aggro with zero other
  enemies in proximity. Vanilla _is_valid_target requires
  aggroed_minion_target_units[unit]; no code found that writes passive DH
  into that set. Codex cross-review (session 019d7dc0) couldn't trace the
  writer. The heuristic carve-out masks the symptom but doesn't address
  the upstream quirk.

Regression checks:
- revive/rescue: PASS (5 revive_candidate lines observed in session)
- navigation/pathing: PASS
- basic combat loop: PASS (22 veteran shout consumes, 17 psyker shout consumes)
- Lua errors: no

Conclusion:
- #17 suppression gap confirmed and patched. Re-validation with the new
  build is the next gate. Expected shape: *_block_dormant_daemonhost rule
  hits on a DH spawn, no smite/knife/krak/rock/missile fire on dormant DH,
  normal combat resuming once DH aggros on any party member.
- Issue #17 comment posted 2026-04-11 with full evidence.
```

### Run 2026-04-11-poxburster-push

```text
Run ID: 2026-04-11-poxburster-push
Date (local): 2026-04-11
Date (UTC): 2026-04-11
Git commit: 07655a0 (v0.10.0)
Log file: console-2026-04-11-16.16.43-21381d2c-a496-4023-9696-734534acf458.log
Bot lineup: included Arbites (powermaul_p1_m2 / powermaul_p2_m1) and Ogryn
  (ogryn_club_p1_m3) — confirmed via `bot weapon:` debug lines before the
  push event.
Map + difficulty: live mission with poxburster spawn

#54 Poxburster push evidence:
- PASS (full chain at 16:33:12, sub-second window):
  - 16:33:12.312 "suppressed poxburster target_enemy (too_close_to_bot)"
  - 16:33:12.478 "poxburster in push range, keeping target for melee push"
  - 16:33:12.479 "defend gate bypassed for poxburster target"
  - 16:33:12.531 "pushing poxburster (bypassed outnumbered gate)"
- The final line is the instrumentation signal emitted from
  `poxburster._should_push` after the outnumbered-gate bypass returns
  `true, push_action_input`, confirming the end-to-end path:
  close-range suppression → push-range override → defend bypass →
  push action queued.
- `_should_defend` ran before `_should_push` (setting
  `scratchpad._bb_bot_unit`), so the throttle key
  `poxburster_push:<target>:<bot_unit>` had a real unit instead of `nil`.

#74 Poxburster push per-bot discriminator evidence:
- PASS (infrastructure validated):
  - The push line emitted cleanly with the fixed throttle key
    (`poxburster_push:<target>:<bot_unit>` constructed via the
    `scratchpad._bb_bot_unit` capture from `_should_defend` shipped in
    v0.9.1 commits 80459d8 + 773c067).
  - No `nil`-unit collision artifacts, no dropped multi-bot lines.
- Residual UX gap: the printed message itself does not carry a bot
  identifier. The dedup is correct but a human reader still cannot tell
  from `pushing poxburster (bypassed outnumbered gate)` alone which bot
  acted. That is a log-ergonomics improvement, not a bug — captured as
  a future polish item, not a blocker.

Regression checks:
- basic combat loop: PASS
- Lua errors: no

Conclusion:
- #54 closed with full chain evidence.
- #74 closed — throttle discriminator shipped in v0.9.1 and exercised
  in production without collision.
```

### Run 2026-04-13-v0.11.0-combat-execution-01

```text
Run ID: 2026-04-13-v0.11.0-combat-execution-01
Date (local): 2026-04-13
Date (UTC): 2026-04-13
Git commit: d80b934 (pre follow-up logging + hook-guard docs)
Log file: console-2026-04-13-14.10.19-dcbaab88-4b7a-4797-bd74-76e3f399fa32.log
Bot lineup / abilities: mixed live squad including Veteran krak, Ogryn box, Zealot knives, Psyker smite, flamer, and Purgatus staff
Map + difficulty: live mission, combat-heavy session (multiple daemonhost spawns reported by the player)

v0.11.0 evidence:
- #93 grenade ballistic execution: PASS
  - visual: yes (player-confirmed in session)
  - charge consumed log: yes
  - key lines / counts:
    - 11 `grenade charge consumed for veteran_krak_grenade`
    - 6 `grenade charge consumed for ogryn_grenade_box_cluster`
    - 12 `grenade charge consumed for zealot_throwing_knives`
    - repeated `grenade external action confirmed for psyker_smite`
- ammo pickup regression: PASS
  - visual: yes (player-confirmed in session)
  - pickup success log: yes
  - key lines / timestamps:
    - multiple `ammo pickup success: large_clip ...`
    - multiple `ammo pickup success: small_clip ...`
- #87 sustained fire: PARTIAL
  - stream routing log: yes
  - hold confirmation log: no
  - key lines / timestamps:
    - `stream action queued for flamer_p1_m1 via shoot_braced`
    - `stream action queued for forcestaff_p2_m1 via trigger_charge_flame`
    - zero `holding sustained fire inputs`
- #32 mule pickup stability: PARTIAL
  - crash fix signal: yes
  - tome/scripture pickup confirmation: no
  - key lines / timestamps:
    - `cleared stale mule pickup ref`
    - zero live tome/scripture carry confirmation lines
- #89 grenade pickup heuristic: PARTIAL
  - policy log: yes
  - pickup success log: no
  - key lines / timestamps:
    - `grenade pickup permitted ...`
    - `grenade pickup bound into ammo slot`
    - zero `grenade pickup success`
- #90 target-type hysteresis: UNKNOWN
  - key lines / timestamps:
    - zero `type flip ...`
    - zero `type hold ... over raw ...`
- #91 weakspot aim MVP: UNKNOWN
  - key lines / timestamps:
    - zero `weakspot aim selected ...`
- #17 daemonhost avoidance: FAIL
  - dormancy suppression log: no
  - key lines / timestamps:
    - `Spawned monster chaos_daemonhost successfully`
    - repeated `restoring monster weight for boss targeting bot chaos_daemonhost`
    - `bot 5 pinged chaos_daemonhost (reason: target_enemy)`
    - zero `dh_suppress_*` lines

Regression checks:
- revive/rescue: PASS
- navigation/pathing: PASS
- basic combat loop: PASS
- Lua errors: no (error lines = 0)

Conclusion:
- #93 has live throw/consume evidence and is releasable from logs.
- Ammo pickup is fixed in live play.
- #82, #87, #90, #91 remain validation-gated.
- #17 is not closeable from this session; the run is evidence against closure.
```

### Run 2026-04-13-v0.11.0-combat-execution-02

```text
Run ID: 2026-04-13-v0.11.0-combat-execution-02
Date (local): 2026-04-13
Date (UTC): 2026-04-13
Git commit: 2b4574e+ / 4dd9a96+ / 6a4cbe5+ / d80b934 (post sustained-fire hold fix, pickup-success logging, grenade wield unblock)
Log file: console-2026-04-13-15.20.37-656e5a8c-12cf-40a6-935a-4d044c41a745.log
Bot lineup / abilities: mixed live squad including flamer, Purgatus, Veteran krak, Ogryn box, Psyker smite, lasgun weakspot routing
Map + difficulty: live combat-heavy session

v0.11.0 evidence:
- #87 sustained fire: PASS
  - stream routing log: yes
  - hold confirmation log: yes
  - key lines / timestamps:
    - `15:27:02.693 ... stream action queued for forcestaff_p2_m1 via trigger_charge_flame`
    - `15:27:02.693 ... holding sustained fire inputs (bot=2, template=forcestaff_p2_m1, action=trigger_charge_flame)`
    - `15:27:04.820 ... stream action queued for flamer_p1_m1 via shoot_braced`
    - `15:27:04.821 ... holding sustained fire inputs (bot=5, template=flamer_p1_m1, action=shoot_braced)`
  - parser noise:
    - one stray `zoom_release` parser error on `unarmed`; no flamer or Purgatus parser errors
- #89 grenade pickup heuristic: PARTIAL
  - policy log: yes
  - pickup success log: yes
  - key lines / timestamps:
    - `15:32:12.742 ... grenade pickup success: small_clip (bot=5, charges=0->2/12)`
    - `15:33:02.025 ... grenade pickup success: ammo_cache_deployable (bot=5, charges=0->12/12)`
    - `15:33:02.750 ... grenade pickup success: ammo_cache_deployable (bot=4, charges=2->3/3)`
  - remaining gap:
    - still no unambiguous standalone `small_grenade` world pickup confirmation
- #91 weakspot aim MVP: PARTIAL
  - runtime route log: yes
  - key lines / timestamps:
    - `15:26:47.045 ... weakspot aim selected j_head (weapon=lasgun_p3_m2, bot=3)`
  - remaining gap:
    - issue body asked for stronger in-game weakspot efficacy / breakpoint validation
- #93 grenade ballistic execution: PASS
  - key lines / timestamps:
    - repeated `grenade charge consumed for veteran_krak_grenade`
    - `15:27:52.327 ... grenade charge consumed for ogryn_grenade_box_cluster`
    - repeated `grenade external action confirmed for psyker_smite`

Conclusion:
- #87 is closeable from this run.
- #89 gained real runtime evidence, but still does not meet its stricter issue text yet.
- #91 now has live weakspot-routing confirmation and is closeable on the MVP "runtime path proven" standard.
```

### Run 2026-04-15-v0.11.0-tome-regression

```text
Run ID: 2026-04-15-v0.11.0-tome-regression
Date (local): 2026-04-15
Date (UTC): 2026-04-15
Git commit: dev/v0.11.0 working tree after the mule-pickup slot-cache fix (post-`24c6e00` local validation run)
Log file: console-2026-04-15-12.52.04-c4ab46ed-a65e-44d1-9dc4-c3816d070a6b.log
Bot lineup / abilities: mixed live squad including psyker shout, veteran shout, zealot relic, knives, ogryn frag/charge
Map + difficulty: `dm_rise`, Heresy/Hunting Grounds, `side_mission_tome`

v0.11.0 evidence:
- #32 mule pickup stability: PARTIAL
  - post-fix tome mission crash regression: pass
  - tome/scripture pickup confirmation: no
  - key lines / timestamps:
    - `12:53:17.499 ... side_mission(side_mission_tome)`
    - `12:55:21.357 ... cleared stale mule pickup ref (source=behavior_component.interaction_unit)`
    - `12:55:21.357 ... cleared stale mule pickup ref (source=behavior_component.interaction_unit)`
    - `bb-log summary`: `Error lines: 0`
  - remaining gap:
    - zero positive tome/scripture carry or consume lines, so the issue is still not closeable as a pickup feature
- #89 grenade pickup heuristic: PARTIAL
  - pickup success log: yes
  - key lines / timestamps:
    - `12:55:27.267 ... grenade pickup success: small_clip (bot=2, charges=4->6/12)`
    - `12:58:20.743 ... grenade pickup success: small_clip (bot=2, charges=0->2/12)`
  - remaining gap:
    - still no standalone `small_grenade` world pickup confirmation
- #90 target-type hysteresis: UNKNOWN
  - key lines / timestamps:
    - zero `type flip ...`
    - zero `type hold ... over raw ...`
- #17 daemonhost avoidance: UNKNOWN
  - key lines / timestamps:
    - no daemonhost spawn in this run

Conclusion:
- The mule-pickup slot-cache fix survived a live tome mission without reproducing the 2026-04-15 noon crash.
- That is only a regression check, not full #32 closure evidence.
- No additional issue becomes closeable from this run.
```

### Run 2026-04-15-v0.11.0-book-manual-confirmation

```text
Run ID: 2026-04-15-v0.11.0-book-manual-confirmation
Date (local): 2026-04-15
Date (UTC): 2026-04-15
Git commit: dev/v0.11.0 working tree after the mule-pickup success-log hook
Evidence type: direct in-game observation from the operator during live play

v0.11.0 evidence:
- #32 mule pickup stability: PASS
  - behavior confirmation: yes
  - authoritative post-hook log line: no
  - observed behavior:
    - a bot picked up the side-mission book
    - the top-right scripture counter incremented immediately afterward
  - context:
    - the confirming run happened after the repo-level mule-assignment override was already in place
    - BetterBots now also logs `mule pickup success: tome|grimoire (bot=<slot>)`, but that hook landed after the earlier tome-regression run and did not yet have a fresh confirming mission log

Conclusion:
- #32 is closeable from direct in-game confirmation.
- Future regressions should use the new `mule pickup success: ...` line as the authoritative log signal instead of relying on assignment logs or memory.
```

### Run 2026-04-15-v0.11.0-book-success-and-open-gates

```text
Run ID: 2026-04-15-v0.11.0-book-success-and-open-gates
Date (local): 2026-04-15
Date (UTC): 2026-04-15
Git commit: dev/v0.11.0 working tree after mule-pickup success logging, BT-side target-type debounce, and companion-tag churn fixes
Log file: console-2026-04-15-18.01.55-f3aa051f-6f95-4c12-afcc-f66d4839fa59.log
Bot lineup / abilities: mixed live squad including Arbites mastiff, veteran krak grenade, zealot dash, ogryn taunt
Map + difficulty: live tome mission

v0.11.0 evidence:
- #32 mule pickup stability: PASS
  - authoritative success log: yes
  - key lines / timestamps:
    - `18:04:53.480 ... assigned proactive mule pickup for tome`
    - `18:05:16.723 ... mule pickup success: tome (bot=4)`
    - `18:05:16.883 ... cleared stale mule pickup ref (source=behavior_component.interaction_unit)`
- #82 perf low-hanging fruit audit: STILL OPEN
  - key line / timestamp:
    - `18:09:24.214 ... bb-perf:auto: 124.5 µs/bot/frame total (61576 bot frames, 944763 calls, 7665.000 ms total)`
  - conclusion:
    - latest live sample is above the original `<80 µs/bot/frame` target
- #90 target-type hysteresis: STILL OPEN
  - key counts:
    - `92` `switch_melee|switch_ranged entered`
    - `43` `suppressed opposite-type switch ...`
    - `0` `type hold ...`
    - `0` `type flip ...`
  - conclusion:
    - BT-side debounce is firing, but visible switch churn remains high
- #17 daemonhost avoidance: UNKNOWN
  - key lines / timestamps:
    - no daemonhost spawn in this run
    - only debug context probes showed `target_is_dormant_daemonhost = false`

Other confirmations:
- no crashes:
  - `bb-log summary`: `Error lines: 0`
- grenade and ammo pickup regressions stayed green:
  - `18:05:40.128 ... grenade pickup success: small_grenade (bot=2, charges=2->3/3)`
  - `18:05:57.468 ... grenade pickup success: small_grenade (bot=5, charges=0->1/1)`
  - `18:08:35.377 ... grenade pickup success: small_grenade (bot=3, charges=0->3/3)`
  - `18:06:34.661 ... ammo pickup success: ammo_cache_deployable (bot=2, ammo=99%->105%)`
  - `18:06:35.389 ... ammo pickup success: ammo_cache_deployable (bot=5, ammo=77%->100%)`

Conclusion:
- #32 is now closed on authoritative runtime log evidence, not only manual observation.
- #82 remains open.
- #90 remains open.
- #17 still needs a real daemonhost encounter.
```

### Run 2026-04-15-v0.11.0-small-grenade-confirmation

```text
Run ID: 2026-04-15-v0.11.0-small-grenade-confirmation
Date (local): 2026-04-15
Date (UTC): 2026-04-15
Git commit: dev/v0.11.0 working tree after grenade-pickup success logging and sticky reservation fixes
Log file: console-2026-04-15-14.44.35-da4b2a9a-48d4-4aa4-8c7a-4b6d71d03dd5.log
Bot lineup / abilities: mixed live squad including adamant whistle, veteran krak grenade, zealot knives, ogryn frag
Map + difficulty: live combat session

v0.11.0 evidence:
- #89 grenade pickup heuristic: PASS
  - policy log: yes
  - standalone `small_grenade` success log: yes
  - key lines / timestamps:
    - `14:46:59.743 ... grenade pickup permitted: all eligible humans above reserve`
    - `14:46:59.743 ... grenade pickup bound into ammo slot`
    - `14:47:02.024 ... grenade pickup success: small_grenade (bot=3, charges=0->3/3)`
    - `14:48:20.564 ... grenade pickup permitted: all eligible humans above reserve`
    - `14:48:20.564 ... grenade pickup bound into ammo slot`
    - `14:48:23.146 ... grenade pickup success: small_grenade (bot=3, charges=1->3/3)`
  - supporting signals:
    - repeated `grenade pickup skipped: ability does not use grenade pickups` lines in the same run, confirming non-pickup blitz users were excluded from arbitration
    - `bb-log summary`: `Error lines: 1`, but none of the grenade pickup evidence depends on that unrelated error

Conclusion:
- #89 is closeable from this run.
- The previously missing standalone `small_grenade` world-pickup confirmation now exists twice in one live session.
```

### Run 2026-04-15-v0.11.0-daemonhost-regression-03

```text
Run ID: 2026-04-15-v0.11.0-daemonhost-regression-03
Date (local): 2026-04-15
Date (UTC): 2026-04-15
Git commit: f7b3e18+ (stage-aware daemonhost branch before close-range suppression restore)
Log file: console-2026-04-15-18.12.45-1f5fb20f-7bff-4a5a-a0b4-ce39ce25b999.log
Bot lineup / abilities: mixed squad including psyker smite and zealot throwing knives
Map + difficulty: live daemonhost encounter

#17 daemonhost avoidance: FAIL
- sleeping daemonhost spawned:
  - `18:15:26.033 ... Spawned monster chaos_daemonhost successfully`
- bots still used offensive abilities before reliable daemonhost suppression appeared:
  - `18:15:31.776 ... grenade queued wield for psyker_smite (rule=grenade_smite_priority_target)`
  - repeated `grenade charge consumed for zealot_throwing_knives`
- later evidence showed the branch could identify the daemonhost correctly once state had caught up:
  - `18:15:51.353 [target_daemonhost_stage] = 6`
  - `18:15:51.354 [target_is_dormant_daemonhost] = false`
  - `18:15:59.768 ... melee suppressed (target is dormant daemonhost)`
  - `18:15:59.768 ... ranged suppressed (target is dormant daemonhost)`
- conclusion:
  - the stage-aware target gate was not enough
  - offensive abilities were still allowed near a sleeping daemonhost before `target_enemy`/target-state suppression converged

Follow-up fix staged after this run:
- restore a tight close-range daemonhost proximity gate for offensive abilities plus close-range melee/ranged checks
- keep the longer-range target-based dormant-daemonhost carve-out for direct daemonhost targets
```

### Run 2026-04-24-v1.0.0-daemonhost-observation-04

```text
Run ID: 2026-04-24-v1.0.0-daemonhost-observation-04
Date (local): 2026-04-24
Date (UTC): 2026-04-24
Git commit: dev/v1.0.0 after charged-weapon/blitz targeting fixes
Log file: console-2026-04-24-09.15.48-d7fdfcb1-dd40-4a14-b8cd-de990858a54b.log
Bot lineup / abilities: mixed squad; first segment preserved external profiles, second segment used BetterBots profiles
Map + difficulty: live combat session with daemonhost spawn

#17 daemonhost avoidance: INCONCLUSIVE / NOT VALIDATED
- daemonhost spawned:
  - `09:20:00.674 ... Spawned monster chaos_daemonhost successfully`
- bots later targeted and engaged it:
  - `09:22:29.102 ... bot 5 pinged chaos_daemonhost (reason: target_enemy)`
  - `09:22:29.315 ... bot weapon: ... stubrevolver_p1_m2 ... action=grenade_ability ... target_breed=chaos_daemonhost`
  - `09:22:29.315 ... bot weapon: ... lasgun_p3_m3 ... action=zoom_shoot ... target_breed=chaos_daemonhost`
  - `09:22:29.340 ... grenade aim ballistic for veteran_krak_grenade ... target_breed=chaos_daemonhost`
  - `09:22:29.341 ... grenade aim flat fallback for psyker_smite ... target_breed=chaos_daemonhost`
  - `09:22:30.487 ... grenade releasing toward ... target_breed=chaos_daemonhost`
- no `dormant_daemonhost` suppression lines appeared in this encounter
- supporting context only shows BetterBots treating the current target as non-dormant:
  - `09:21:36.777 ... [target_is_dormant_daemonhost] = false`
  - later context snapshots also print `target_is_dormant_daemonhost = false`
- adjacent logs:
  - `console-2026-04-23-16.43.14-de19ea9a-78df-4316-b878-c15036ee76cd.log` spawned daemonhosts at `16:46:06.543` and `16:52:21.380`; bots pinged/restored monster weight for one at `16:47:12-16:47:25`, with no suppression proof
  - `console-2026-04-24-08.21.22-853d01c4-0e56-4784-a2fd-7afb169be015.log` spawned a daemonhost at `08:24:58.361`, with no BetterBots engagement/suppression proof

Conclusion:
- this does not validate #17
- if the daemonhost was already fully aggroed before `09:22:29`, bot commitment was expected
- if it was still dormant or only waking, this is still a daemonhost-avoidance failure
- the text log lacks the decisive first-action `target_daemonhost_stage` / `target_daemonhost_aggro_state` values, so the next validation pass needs those values logged when a daemonhost target/action is allowed or suppressed
- follow-up 2026-04-28: text logging now includes `target=<breed> stage=<N> aggro_state=<state> dormant=<bool>` on dormant melee/ranged suppression and on allowed ability activations against daemonhost targets. The next daemonhost run should use the first `ability allowed against daemonhost` or `*_suppressed (... daemonhost ...)` line as the decisive classifier evidence.
```

### Run 2026-04-16-v0.11.0-target-type-hysteresis-closure

```text
Run ID: 2026-04-16-v0.11.0-target-type-hysteresis-closure
Date (local): 2026-04-16
Date (UTC): 2026-04-16
Git commit: main working tree after the BotPerceptionExtension._update_target_enemy hook fix and consolidated bot_perception_extension install
Log file: console-2026-04-16-17.51.56-7d4a2e9c-1ea7-4dbf-a4f0-0337a9f5cd8a.log
Bot lineup / abilities: mixed live squad including zealot relic, veteran shout, psyker shout, knives, frag grenades
Map + difficulty: live combat session

v0.11.0 evidence:
- #90 target-type hysteresis: PASS
  - math-layer runtime proof: yes
  - perf row: yes
  - key counts:
    - `32` `type flip ...`
    - `46` `type hold ...`
    - `4` `suppressed opposite-type switch ...`
    - `72` `wrong slot ...`
  - key lines / timestamps:
    - `17:55:47.689 ... type hold ranged over raw melee (melee=7.01, ranged=7.00)`
    - `17:55:54.213 ... type flip ranged -> melee`
    - `17:56:39.709 ... bot 3 suppressed opposite-type switch ranged -> melee (elapsed=0.02s)`
    - `18:01:05.447 ... bb-perf:auto: target_type_hysteresis.post_process 143.000 ms total (11473 calls, 12.5 us/call)`
  - conclusion:
    - the hysteresis hook is now running on the correct live path
    - raw melee/ranged flips are being both suppressed and allowed in real play
    - the earlier startup-order / dead-hook failure mode is no longer present

Other confirmations:
- no crashes:
  - `bb-log summary`: `Error lines: 0`
- general perf snapshot:
  - `18:01:05.447 ... bb-perf:auto: 113.8 µs/bot/frame total (80076 bot frames, 1022369 calls, 9111.000 ms total)`

Conclusion:
- #90 is closeable from this run.
```

## Decision Rules

1. Close `#1` only when every Tier 2 row that is not `N/A` is `PASS` in at least one documented run.
2. ~~Keep `#3` open until force-field is no longer `PARTIAL` and drone has explicit `PASS` evidence.~~ **Done** — #3 closed 2026-03-07, all testable Tier 3 at 100%.
3. `BLOCKED` rows are excluded from closure decisions until environment access exists.
4. If a run has conflicting outcomes, keep the stricter status (`PARTIAL`/`FAIL`/`UNKNOWN`) and open a focused fix task.

## Recommended Run Order (4 bots/session)

1. Tier 1 first (baseline):
   - Prioritize single-press stances first (`veteran_combat_ability`, `psyker_overcharge_stance`, `ogryn_gunlugger_stance`, `adamant_stance`), then run Hive Scum variants (`broker_focus`, `broker_punk_rage`) and `veteran_stealth_combat_ability`.
2. Tier 2 second (`#1`):
   - Prioritize currently unknown templates first (`zealot_invisibility`, `ogryn_charge`).
3. Tier 3 third (`#3`):
   - `psyker_force_field*`, `zealot_relic`, `adamant_area_buff_drone`, `broker_ability_stimm_field`.
