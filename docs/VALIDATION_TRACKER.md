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

## Reliability Snapshot (current rolling log)

```text
Source log: console-2026-03-05-14.57.34-ff2ae36c-e683-46b6-9b33-2885b60f2153.log
Snapshot time: ~16:03 UTC segment
Method: success_rate = consume_events / (consume_events + no_charge_completions)

- zealot_relic: 5 success, 0 no-charge => 100.0%
- psyker_force_field_dome: 9 success, 60 no-charge => 13.0%
- adamant_area_buff_drone: 10 success, 66 no-charge => 13.2%
```

```text
Post-patch window (from first `instant_place_force_field` line):
- psyker_force_field_dome: 4 success, 34 no-charge => 10.5%
- adamant_area_buff_drone: 7 success, 26 no-charge => 21.2%
```

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
| `veteran_stealth_combat_ability` | UNKNOWN | not explicitly tracked in current status docs |
| `psyker_overcharge_stance` | PASS | run `2026-03-05-tier1-01`: `charge consumed for psyker_overcharge_stance` |
| `ogryn_gunlugger_stance` | PASS | run `2026-03-05-tier1-01`: `charge consumed for ogryn_ranged_stance` |
| `adamant_stance` | PASS | run `2026-03-05-tier1-01`: `charge consumed for adamant_stance` |
| `broker_focus` | UNKNOWN | not explicitly tracked in current status docs |
| `broker_punk_rage` | UNKNOWN | not explicitly tracked in current status docs |

### Tier 2 (`#1`)

| Ability Template | Status | Evidence Notes |
|---|---|---|
| `zealot_invisibility` | PASS | run `2026-03-05-tier2-03`: `charge consumed for zealot_invisibility_improved` |
| `zealot_dash` | PASS | run `2026-03-05-tier2-02`: `charge consumed for zealot_targeted_dash_improved_double` |
| `ogryn_charge` | PASS | run `2026-03-05-tier2-03`: `charge consumed for ogryn_charge_increased_distance` |
| `ogryn_taunt_shout` | PASS | run `2026-03-05-tier2-01`: `charge consumed for ogryn_taunt_shout` |
| `psyker_shout` | PASS | run `2026-03-05-tier2-01`: `charge consumed for psyker_discharge_shout_improved` |
| `adamant_shout` | N/A | internal template present, but not currently exposed as Arbites player-facing ability in live UI |
| `adamant_charge` | PASS | run `2026-03-05-tier2-01`: `charge consumed for adamant_charge` |

### Tier 3 (`#3`)

| Ability Template | Status | Evidence Notes |
|---|---|---|
| `zealot_relic` | PASS | run `2026-03-05-tier3-01`: `charge consumed for zealot_relic` + weapon-switch lock evidence |
| `psyker_force_field*` | PARTIAL | run `2026-03-05-tier3-03`: post-patch consume evidence present (16:01:33, 16:02:00), but no-charge outcomes still dominate |
| `adamant_area_buff_drone` | PARTIAL | run `2026-03-05-tier3-03`: post-patch consume evidence improved, but still mixed reliability |
| `broker_ability_stimm_field` | BLOCKED | DLC not owned in current environment, cannot validate yet |

### Heuristic Validation (post-refactor, #2)

Legend: `PASS` = activated with correct rule + holds observed, `UNTESTED` = not in bot lineup yet.

| Heuristic Function | Template(s) | Status | Run | Rules fired |
|---|---|---|---|---|
| `_can_activate_veteran_combat_ability` (VoC) | `veteran_combat_ability` | PASS | `2026-03-06-heuristics-01` | `voc_surrounded`, `voc_block_safe_state` |
| `_can_activate_veteran_combat_ability` (ranger) | `veteran_combat_ability` | UNTESTED | — | needs ranger class_tag bot |
| `_can_activate_veteran_stealth` | `veteran_stealth_combat_ability` | UNTESTED | — | — |
| `_can_activate_zealot_dash` | `zealot_dash`, `zealot_targeted_dash*` | UNTESTED | — | activation PASS in Tier 2 run, but pre-heuristic |
| `_can_activate_zealot_invisibility` | `zealot_invisibility` | PASS | `2026-03-06-heuristics-01` | `stealth_overwhelmed`, `stealth_ally_reposition`, `stealth_hold` |
| `_can_activate_psyker_shout` | `psyker_shout` | PASS | `2026-03-06-heuristics-01` | `shout_surrounded`, `shout_block_low_value` |
| `_can_activate_psyker_stance` | `psyker_overcharge_stance` | UNTESTED | — | — |
| `_can_activate_ogryn_charge` | `ogryn_charge*` | UNTESTED | — | — |
| `_can_activate_ogryn_taunt` | `ogryn_taunt_shout` | UNTESTED | — | — |
| `_can_activate_ogryn_gunlugger` | `ogryn_gunlugger_stance` | PASS | `2026-03-06-heuristics-01` | `gunlugger_high_threat`, `block_melee_pressure`, `block_target_too_close` |
| `_can_activate_adamant_stance` | `adamant_stance` | UNTESTED | — | — |
| `_can_activate_adamant_charge` | `adamant_charge` | UNTESTED | — | — |
| `_can_activate_adamant_shout` | `adamant_shout` | N/A | — | not player-facing |
| `_can_activate_broker_focus` | `broker_focus` | UNTESTED | — | DLC-blocked |
| `_can_activate_broker_rage` | `broker_punk_rage` | UNTESTED | — | DLC-blocked |

**Remaining validation runs needed:**

1. **Run H-02**: Veteran (Executioner's Stance/ranger) + Zealot (Dash) + Psyker (Scrier's Gaze) + Ogryn (Bull Rush or Indomitable)
   - Covers: `veteran_combat_ability` (ranger), `zealot_dash`, `psyker_overcharge_stance`, `ogryn_charge`
2. **Run H-03**: Veteran (Stealth) + Ogryn (Loyal Protector/taunt) + Arbites (Stance) + Arbites (Charge)
   - Covers: `veteran_stealth`, `ogryn_taunt`, `adamant_stance`, `adamant_charge`
   - Note: requires Tertium 5/6 for Arbites bots
3. **Run H-04** (optional, DLC-gated): Hive Scum (Focus) + Hive Scum (Rage)
   - Covers: `broker_focus`, `broker_punk_rage`

## Decision Rules

1. Close `#1` only when every Tier 2 row that is not `N/A` is `PASS` in at least one documented run.
2. Keep `#3` open until force-field is no longer `PARTIAL` and drone has explicit `PASS` evidence.
3. `BLOCKED` rows are excluded from closure decisions until environment access exists.
4. If a run has conflicting outcomes, keep the stricter status (`PARTIAL`/`FAIL`/`UNKNOWN`) and open a focused fix task.

## Recommended Run Order (4 bots/session)

1. Tier 1 first (baseline):
   - Prioritize single-press stances first (`veteran_combat_ability`, `psyker_overcharge_stance`, `ogryn_gunlugger_stance`, `adamant_stance`), then run Hive Scum variants (`broker_focus`, `broker_punk_rage`) and `veteran_stealth_combat_ability`.
2. Tier 2 second (`#1`):
   - Prioritize currently unknown templates first (`zealot_invisibility`, `ogryn_charge`).
3. Tier 3 third (`#3`):
   - `psyker_force_field*`, `zealot_relic`, `adamant_area_buff_drone`, `broker_ability_stimm_field`.
