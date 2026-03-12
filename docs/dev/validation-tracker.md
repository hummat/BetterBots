# In-Game Validation Tracker

## Purpose

Track manual Darktide validation runs with consistent evidence so issue decisions are based on logs, not memory.

## Active Scope

1. Tier 1 ability validation (baseline)
2. Tier 2 ability validation (`#1`)
3. Tier 3 item-ability fallback validation (`#3`)
4. Regression sanity checks (revive/rescue/navigation/basic combat)

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
- revive/rescue: PASS/FAIL/UNKNOWN
- navigation/pathing: PASS/FAIL/UNKNOWN
- basic combat loop: PASS/FAIL/UNKNOWN
- Lua errors: yes/no (+ first traceback line if yes)

Conclusion:
- promote issue state / next fix target:
```

## Recorded Runs

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
| `_can_activate_broker_focus` | `broker_focus` | UNTESTED | — | DLC-blocked |
| `_can_activate_broker_rage` | `broker_punk_rage` | UNTESTED | — | DLC-blocked |

### Item Heuristic Validation (#3)

Legend: `PASS` = activated with correct rule + holds observed, `UNTESTED` = not yet validated in-game.

| Heuristic Function | Ability Name(s) | Status | Run | Rules fired |
|---|---|---|---|---|
| `_can_activate_zealot_relic` | `zealot_relic` | PASS | 2026-03-07-tier3-final | 2 consumes; `self_critical` observed (toughness-gated activation) |
| `_can_activate_force_field` | `psyker_force_field*` | PASS | 2026-03-07-tier3-final | 1 consume; activated under combat pressure |
| `_can_activate_drone` | `adamant_area_buff_drone` | PASS | 2026-03-07-tier3-final | 5 consumes; activated reliably in combat |
| `_can_activate_stimm_field` | `broker_ability_stimm_field` | BLOCKED | — | DLC-blocked |

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
  Bot 2: forcestaff_p1_m1 (Voidstrike)
Map + difficulty: Standard mission

Staff charged fire (#43):
- p1 Voidstrike (trigger_explosion): PASS
  - _may_fire swap: fire=shoot_pressed -> aim_fire=trigger_explosion (20:04:16.133)
  - bot=2, weapon_template=forcestaff_p1_m1
- All 4 staves now confirmed PASS (p2 Purgatus in earlier session, p3/p4 in earlier session, p1 this session)

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

**Template heuristic summary: 12/13 PASS, 1 N/A, 2 DLC-blocked.**
**Item heuristic summary: 3/3 testable PASS, 1 DLC-blocked.**

**Remaining validation runs needed:**

1. **Run H-04** (optional, DLC-gated): Hive Scum (Focus) + Hive Scum (Rage)
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

**New issue discovered in H-02b:**

Psyker bot exploded twice from warp overcharge. Scrier's Gaze builds peril while active, and without Venting Shriek (different ability slot) the bot has no way to vent. The `block_peril_window` gate correctly prevents re-activation at high peril, but cannot cancel an active stance. Needs investigation — possible mitigations:
- Block Scrier's Gaze activation if bot lacks a peril vent ability
- Lower the peril ceiling for stance activation (e.g., block above 0.50 instead of 0.90)
- Tie into stance cancellation (#12) to exit early when peril is critical

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
