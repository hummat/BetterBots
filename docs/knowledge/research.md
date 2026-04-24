# Research & Reference Data

Detailed findings from decompiled source analysis, API research, and implementation investigations.
MEMORY.md has brief summaries — this file has the full details.

## Ability template patterns (from decompiled source)
- Stance abilities: single `stance_pressed` input, instant activation. Tier 1.
- Charge/dash abilities: two-step `aim_pressed` → hold → `aim_released`. Tier 2.
- Shout abilities: `shout_pressed`/`shout_released` pattern. Tier 2.
- Item-based abilities (zealot_relic, force field, drone): no `ability_template` field → Tier 3 fallback.
- Grenades/blitz: no `ability_template` → Tier 3, not yet addressed.

## Bot system docs (added 2026-03-05)
- `docs/bot/behavior-tree.md` — 14-node priority hierarchy, all conditions, blackboard
- `docs/bot/combat-actions.md` — action node lifecycles, utility scoring curves
- `docs/bot/perception-targeting.md` — dual scoring, gestalt weights, 5m broadphase
- `docs/bot/navigation.md` — GwNav, 9-level destination priority, teleport at 40m
- `docs/bot/input-system.md` — two-pathway architecture, ActionInputParser ring buffer
- `docs/bot/profiles-spawning.md` — all vanilla bots = veteran, zero talents, tiered weapons
- Key finding: `enemies_in_proximity()` is too coarse for ability triggers — perception exposes challenge_rating, breed, distance, LoS, health/toughness
- **Perception inconsistency**: `target_enemy`/`target_enemy_type` (BT single-target) can disagree with `challenge_rating_sum`/type counts (broadphase scan). Trust aggregates for heuristic tuning, use single-target only for boolean checks (`target_is_monster`, `target_is_super_armor`). Documented in `docs/dev/known-issues.md`.

## Tactics docs (added 2026-03-05)
- 6 files: `docs/classes/{veteran,zealot,psyker,ogryn,arbites,hive-scum}-tactics.md`
- Community-sourced USE WHEN / DON'T USE / PROPOSED BOT RULES per ability with confidence levels
- Key design findings for #2 implementation:
  - Not a uniform threat-score model — each class needs different signals
  - Psyker: Peril-budget-gated (access via `unit_data_extension:read_component("warp_charge").current_percentage`)
  - Hive Scum: toughness-reactive (both stances activate at < 40% toughness)
  - Ogryn Taunt: ally health awareness (only if Ogryn can survive aggro)
  - Veteran: Voice of Command vs Executioner's Stance share template, need `class_tag` detection
  - Cooldown length matters: 20s (Arbites Charge) = liberal, 80s (Point-Blank Barrage) = conservative

## Stage 1 research findings (2026-03-06)
- `docs/classes/grenade-inventory.md` — 19 grenade/blitz templates mapped. ALL lack `ability_template` (except `adamant_whistle`). Need item-based fallback.
- `docs/classes/character-state-api.md` — full state detection reference. Key: `movement_state.is_dodging`, `lunge_character_state.is_lunging/.is_aiming`, `character_state.state_name`
- Tier 3 root cause: mod's `followup_delay` too short vs actual action durations (drone: 0.24s vs 1.9s needed). Fix values known.
- Stance cancellation (#12): Tier 1 stances have NO release input, `transition="stay"` is one-way. Need template injection or `stop_action()`.
- Revive protection (#20): DONE — `blackboard.behavior.current_interaction_unit ~= nil` blocks ability during any interaction.
- Ability suppression (#11): DONE — `_is_suppressed(unit)` checks dodging, falling, lunging, jumping, ladder, moving platform. Guards placed AFTER "keep running" fast path so in-progress abilities complete.
- Scrier's Gaze fix (#27): DONE — blocks warp weapon attacks at the configurable `warp_weapon_peril_threshold` (default `≥99%`) via `bot_queue_action_input`. Root cause: explosion only on additional peril generation at 100%, not from stance itself.
- Bot venting (#30): NEW — bots can't actively vent warp weapons. BT has vent node but sends wrong action_input ("reload" vs "vent"). Approach: piggyback on existing BT, translate reload→vent in hook.
- 7 issues implementation-ready: #6, #8-T1, #10, #13, #15, #18, #21

## Bot healing architecture (3 independent subsystems)
- **Health stations**: `bot_behavior_extension._update_health_stations()` — has queue system comparing bot vs human damage. Already fairly human-favoring (`bot_dmg < human_dmg * 2` = defer when human has >50% of bot's damage).
- **Deployed med-crates**: `BotGroup._update_pickups_and_deployables_near_player()` → `health_deployable` field. NO human-priority check. 10-15m scan range, `deployable_type == "medical_crate"`.
- **Pocketable pickups** (carried med-kits/wound cures): `BotGroup._update_mule_pickups()` → `mule_pickup` field. NO human-priority check. Bot carries item in inventory slot.
- `_update_health_deployables()` is a RED HERRING — only sets boolean `needs_non_permanent_health`, doesn't scan for pickups.
- Med-kit vs wound cure: different slots (`slot_pocketable` vs `slot_pocketable_small`), different heal types (`heal_types.medkit` = green only, `heal_types.blessing_syringe` = corruption + green).

## Talent detection API
- `talent_extension:talents()` returns `{ talent_name = tier, ... }` — empty for vanilla bots
- `talent_extension:has_special_rule("rule_name")` checks computed special rules from talents
- Martyrdom keystone: talent ID = `zealot_martyrdom`, buff = `zealot_martyrdom_base`. `zealot_martyrdom_grants_ally_power_bonus` is a MODIFIER talent, not the base keystone.
- Only works with Tertium 5/6 — vanilla bots have `talents = {}` always

## API gotchas
- `Health.damage_taken_percent()` does NOT exist. Use `1 - Health.current_health_percent(unit)`.
- `buff_extension:has_buff_name()` does NOT exist. Use `buff_extension:current_stacks("buff_name") > 0`.
- `ScriptUnit.extension(unit, system)` **throws a hard Lua error** if the extension doesn't exist. Use `ScriptUnit.has_extension(unit, system)` in mod code — it returns nil on miss. In BT update tick context, a crash from `.extension()` kills the bot's entire behavior loop for that frame. Rule: always `has_extension` + nil check unless you have a structural guarantee the extension exists.

## Performance
- Current overhead is negligible — mod reads engine-cached data, no new scans/raycasts/pathfinding
- `build_context` (heaviest function) cached per unit per fixed_t, runs once per bot per frame
- Heuristics are pure arithmetic — sub-microsecond
- Full analysis + growth risk matrix documented in `docs/dev/architecture.md` "Performance analysis" section
- **Watch list for perf-sensitive issues**: #13 (navmesh queries — gate behind heuristic, cache negatives), #22 (utility scoring — keep context cache), #23 (melee selection — cache weapon template reads), hook count (consolidate if >10 per-frame hooks)

## Log analysis patterns
- **DO** grep for: `fallback queued`, `fallback held`, `fallback blocked`, `charge consumed`, `fallback item`
- **DO NOT** grep for: `decision:`, `activate.*true` — these patterns don't exist in the log format
- `-> true` DOES appear in debug decision lines (e.g. `decision veteran_combat_ability -> true (rule=...)`)
- Combat activity filter: `rg "BetterBots DEBUG:" <log> | grep -v "nearby=0\|patch\|logging\|loaded\|metadata\|GameplayState\|condition"`
- Activations only: `rg "fallback queued|charge consumed" <log>`
- See `docs/dev/debugging.md` for full grep recipes and log pattern reference
