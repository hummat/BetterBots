# Known Issues and Risks

## High severity

1. DMF toggle safety is incomplete.
   - The mod mutates global tables (`AbilityTemplates`, `bt_bot_conditions`).
   - No disable/unload restore path is implemented.
   - Toggling off in-session may require reload/restart to fully restore vanilla behavior.

## Medium severity

1. Item fallback is heuristic, not data-driven.
   - Item templates are matched by known action-input shapes (`channel`, `instant_aim_force_field`, etc.).
   - New or changed templates can fail with `fallback item blocked ... unsupported weapon template`.
   - In the latest run, psyker force-field showed mixed behavior after reload (`aim_force_field`/`place_force_field` queued, but no later `charge consumed` line).

2. Generic activation heuristic can still mistime abilities.
   - Most paths use proximity (`enemies_in_proximity() > 0`) plus cooldown validity.
   - This can still produce low-value casts.

3. Debug log noise is high during combat.
   - Frequent `fallback blocked ... invalid action_input=...` lines are expected from transient invalid states.
   - This makes it harder to spot real failures quickly.

## Low severity

1. Injected `end_condition` values are simplified.
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
2. Replace heuristic item matching with explicit per-template mapping table.
3. Reduce debug-log noise for expected transient `invalid action_input` states.
4. Add smarter per-ability trigger policies (threat/toughness/ally state).
5. Track upstream status of the Tertium4Or5 nil-guard fix and remove local compatibility note once upstreamed.
