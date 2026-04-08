# Grenade/Blitz Tactical Evaluator Design

Date: 2026-04-08

## Problem

BetterBots grenade and blitz usage works, but most decisions are still too coarse.

Current behavior is driven by:

- flattened per-tick context from `heuristics.lua`
- a single shared target resolver in `bot_targeting.lua`
- execution-time revalidation in `grenade_fallback.lua`

That is enough for "use grenade or do not use grenade", but it is not enough for:

- choosing between direct-impact, AoE, defensive, placeable, and companion-command tools
- picking a placement point instead of a single unit
- distinguishing "detonate at the dog's position" from "retask the dog to a better enemy"
- preserving the original tactical reason during the wield/aim/release sequence

The result is usable but shallow grenade logic. Bots can still waste tools, pick poor aim anchors, or miss better opportunities because the model is too flat.

## Goals

- Improve grenade/blitz effectiveness, not just frequency
- Improve tactical intelligence across all grenade/blitz families
- Keep the system compatible with existing BetterBots settings
- Reuse as much current infrastructure as possible
- Add enough observability to validate why a grenade was or was not used

## Non-goals

- Replace all ability heuristics in the mod with a full repo-wide utility system
- Absorb Arbites companion-command smart tagging work tracked in `#49`
- Build a heavy map-wide planner with long-lived tactical state

This design is intentionally narrower than `#22` ("Utility-based ability scoring"). It is a grenade/blitz-scoped upgrade, not a global replacement for all ability logic.

## Existing Constraints

### Open issue overlap

- `#49` covers Arbites companion-command smart tags. This issue should reference it, not replace it.
- `#22` is the broader architectural north star. This design is a scoped step in the same direction.

### Arbites build reality

`../hadrons-blessing/data/builds/18-arbites-hyper-carry-dog.json`,
`../hadrons-blessing/data/builds/19-arbites-arbitrator-meta.json`, and
`../hadrons-blessing/data/builds/20-arbites-immortal-provost.json`
show that both `adamant_whistle` and `adamant_shock_mine` matter in real builds.

They also show an important split:

- dog builds use `Remote Detonation`
- some mine builds use `Lone Wolf`, which disables the companion

The design therefore must not assume that all Arbites bots have a live companion.

## Recommended Architecture

Introduce a shared grenade/blitz tactical evaluator that produces a structured decision object.

The system should stop treating grenade usage as:

- `bool should_use`
- one shared target unit

and instead produce:

- `template`
- `intent_score`
- `reason`
- `target_unit`
- `placement_mode`
- `placement_position`
- `commit_policy`
- `confidence`

This object becomes the contract between heuristic evaluation and execution.

## Decision Pipeline

### 1. Situation scan

Extend the current grenade context with bounded tactical summaries:

- top candidate units by role
- local cluster density around those candidates
- ally pressure state
- bot-local danger state
- short-lived memory for failed or recent uses

This remains per-bot and local. No heavy planner.

### 2. Opportunity generation

Generate multiple candidate opportunities rather than a single boolean:

- `horde_clear`
- `priority_pick`
- `interrupt_special`
- `defensive_breathing_room`
- `boss_or_elite_punish`
- `hold_point_denial`
- `companion_retask`

Each opportunity carries a score and an expected execution shape.

### 3. Template-family matching

Each template family consumes only the opportunity types it is good at.

- direct-impact
- AoE lethal
- AoE control or defensive
- placeable denial
- companion command

### 4. Execution contract

`grenade_fallback.lua` should execute a chosen tactical decision, not rediscover intent mid-sequence.

Revalidation should depend on the original tactical reason:

- direct-impact can abort on target loss
- AoE can continue if the cluster still exists
- defensive tools can continue if pressure remains
- whistle can continue only if companion assumptions still hold

## Template Families

### Direct-impact

Examples:

- `veteran_krak_grenade`
- `ogryn_grenade_friend_rock`
- `zealot_throwing_knives`
- `psyker_throwing_knives`
- `broker_missile_launcher`

Primary logic:

- prefer single high-value targets
- score armor, threat, distance, and target persistence
- downscore cluttered melee throws unless the template is intended for that range

### AoE lethal

Examples:

- frag
- fire
- tox
- ogryn explosive grenades
- `adamant_grenade`

Primary logic:

- choose cluster anchors, not just current target
- score density, elite mix, route blockage, and self/team safety

### AoE control / defensive

Examples:

- smoke
- shock
- flash
- smite
- chain lightning

Primary logic:

- score ally rescue and breathing-room value
- allow self-centered or ally-centered placement
- favor pre-collapse timing over late panic use

### Placeable denial

Examples:

- `adamant_shock_mine`

Primary logic:

- prefer feet / near-path / ally-defense-zone placement
- score persistence value, not immediate hit count
- avoid duplicate low-value drops in the same area

### Companion command

Examples:

- `adamant_whistle`

Primary logic:

- treat whistle detonation and companion command as related but distinct
- score dog state, dog distance, current dog assignment quality, and retask value
- avoid whistles that only pull the dog off acceptable work

This lane must explicitly reference `#49` for smart-tag companion command work.

## Arbites Split

Arbites logic should branch early:

### Dog present

- whistle logic enabled
- companion-aware reasoning enabled
- reference `#49` for smart-tag direction of the dog

### Lone Wolf / no dog

- whistle path disabled
- grenade and mine logic still active
- no companion assumptions in context or scoring

## Settings Integration

Existing settings should remain the user-facing control surface.

The main change is interpretation:

- aggressiveness should modulate tactical score thresholds
- reserve policy should modulate charge conservation
- family-level doctrine should decide whether a bot spends freely or keeps a charge in reserve

## Observability

The design requires new logging and event fields.

At minimum:

- chosen opportunity type
- chosen target or placement mode
- cluster or pressure score
- retask reason
- abort reason
- commit reason

Without these signals, in-game validation will be guesswork.

## Phased Rollout

### Phase 1: Shared evaluator skeleton

- define decision object
- extend context
- add family-specific candidate resolvers

### Phase 2: Placement and targeting

- direct-target resolver
- cluster-anchor resolver
- defensive-zone resolver
- mine placement doctrine

### Phase 3: Execution contract

- store decision object in grenade state
- revalidate against original reason
- allow limited retargeting where appropriate

### Phase 4: Arbites split

- dog-present whistle logic
- no-dog / Lone Wolf path
- reference `#49` integration points

### Phase 5: Settings and reserves

- aggressiveness thresholds
- reserve policy
- family-level doctrine

### Phase 6: Logging and tests

- event schema updates
- unit tests for scoring, placement selection, and revalidation paths
- in-game validation checklist

## Acceptance Criteria

- Bots select different tactical targets for direct-impact, AoE, defensive, mine, and whistle templates
- AoE grenades use cluster-aware placement instead of always following `target_enemy`
- Mines use deliberate placement doctrine rather than enemy-unit mimicry
- Arbites whistle logic distinguishes dog-present vs no-dog states
- The new issue references `#49` and `#22` instead of duplicating them
- Logs make the chosen grenade/blitz reason and placement mode visible in one session

## GitHub Issue Shape

The unified issue should be framed as:

- title: grenade/blitz tactical evaluation upgrade
- scope: all grenade/blitz families
- linked issues: `#49`, `#22`
- non-goal: full repo-wide utility-system replacement

The issue should be one parent issue with phased tasks, not a vague umbrella.
