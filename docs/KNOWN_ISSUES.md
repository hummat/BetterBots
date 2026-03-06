# Known Issues and Risks

## High severity

1. DMF toggle safety is incomplete.
   - The mod mutates global tables (`AbilityTemplates`, `bt_bot_conditions`).
   - No disable/unload restore path is implemented.
   - Toggling off in-session may require reload/restart to fully restore vanilla behavior.

## Medium severity

1. Tier 3 item fallback timing mismatch.
   - Root cause: `ITEM_SEQUENCE_PROFILES` timing values are out of sync with actual engine action durations.
   - Drone `release_drone`: 0.6s `buffer_time` + 1.3s action `total_time` = 1.9s real time, but mod's `followup_delay` is only 0.24s (regular) / 0.1s (instant).
   - Force field: 0.6s `buffer_time` + 0.6s action = 1.2s, closer to mod's timing but still off.
   - The state machine advances to the next stage before the engine finishes processing the current input.
   - Fix: Adjust `followup_delay` and `unwield_delay` values to match decompiled action durations + buffer times.
   - Drone fix values: regular `followup_delay` ~1.9s, `unwield_delay` ~2.3s; instant `followup_delay` 0.1s (has `dont_queue=true`), `unwield_delay` ~1.1s.

2. Stance cancellation complexity.
   - Tier 1 stances have NO release input defined in their `action_inputs`.
   - `transition = "stay"` creates a one-way hierarchy with no exit path.
   - Stance effects persist via buff system, decoupled from action lifecycle.
   - Early cancellation requires either: (a) injecting release input into templates, or (b) force-stopping via `PlayerUnitAbilityExtension.stop_action()` + manual buff cleanup.

3. BT preemption during revive.
   - BT re-evaluates every frame even while a node is running.
   - Ability activation (priority 8-9) CAN interrupt an in-progress revive (priority 2) if `can_revive` becomes false momentarily.
   - Fix: Check `blackboard.behavior.current_interaction_unit ~= nil` in ability condition to block activation during any active interaction.
   - Estimated fix size: ~5 lines of code in the condition hook.

4. Item fallback is heuristic, not data-driven.
   - Item templates are matched by known action-input shapes (`channel`, `instant_aim_force_field`, etc.).
   - New or changed templates can fail with `fallback item blocked ... unsupported weapon template`.
   - In the latest run, psyker force-field showed mixed behavior after reload (`aim_force_field`/`place_force_field` queued, but no later `charge consumed` line).

5. Per-career heuristics may need threshold tuning.
   - 13 per-template functions replaced the generic `enemies_in_proximity() > 0` trigger.
   - Thresholds are initial guesses from tactics docs — not yet validated in-game.
   - Use `/bb_decide` to inspect live decisions during play.

6. Debug log noise is high during combat.
   - Frequent `fallback blocked ... invalid action_input=...` lines are expected from transient invalid states.
   - This makes it harder to spot real failures quickly.

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

## Current fix direction

1. Add explicit restore-on-disable behavior.
2. Align `ITEM_SEQUENCE_PROFILES` timing with decompiled action durations (#3).
3. Replace heuristic item matching with explicit per-template mapping table.
4. Reduce debug-log noise for expected transient `invalid action_input` states.
5. ~~Add smarter per-ability trigger policies~~ Code complete (#2) — needs in-game validation.
6. Track upstream status of the Tertium4Or5 nil-guard fix and remove local compatibility note once upstreamed.
