# Sprint 2 Keystone MVP

**Date:** 2026-04-18
**Status:** Approved
**Scope:** talent-aware MVP for the shipped Zealot, Psyker, and Veteran bot builds without widening Sprint 2 into the deferred post-1.0 keystone pass

## Problem

Sprint 1 exposed talent state to heuristics via `context.talents` and `context.current_stacks`, but the shipped bot builds still behave as if those talents do not matter.

That gap shows up in three concrete places:
- Zealot Martyrdom builds still follow generic healing and Shroudfield panic rules, which fights the intended low-health payoff.
- Psyker Venting Shriek / Warp Siphon builds still use a generic shout-peril threshold, which spends peril too early and ignores the vent-on-shout modifier.
- Veteran Voice of Command + Focus Target builds rely on the current ping path implicitly; the repo has not yet verified whether the Veteran bot consistently becomes the tagger that actually applies the Focus Target debuff.

The roadmap narrowed Sprint 2 to shipped-roster coverage only. The broader `#38` issue body is still useful as proof of concept and follow-up seed, but it is stale for release scope: it includes pocketable health pickup behavior and Scrier's Gaze tuning that the roadmap explicitly deferred post-1.0.

## Goal

Ship a narrow, talent-aware behavior pass that:
- respects Martyrdom's low-health value in the live healing and stealth seams we can actually control,
- makes Psyker shout behavior talent-aware without turning Sprint 2 into a generic peril-framework refactor,
- verifies the Veteran Focus Target path and applies only a narrow ping fix if validation shows the existing tag flow is insufficient.

## Non-Goals

- No profile-ID-specific logic
- No Scrier's Gaze tuning in Sprint 2
- No pocketable medkit / wound-cure pickup support
- No generic keystone framework
- No broad `weapon_action.lua` or target-selection rewrite unless the tests prove the heuristic seam cannot express the behavior

## Constraints

- Talent-aware behavior must degrade cleanly when `context.talents` is absent.
- Sprint 2 is still MVP scope. `#38` is the proof of concept for later keystone follow-ups, not a mandate to ship the whole backlog now.
- BetterBots documentation says new behavior must be verifiable from logs in a single mission. Sprint 2 changes need explicit `_debug_log` confirmation points.

## Approach

Implement the Sprint 2 rules at the seams that already own the behavior, using small local talent helpers instead of a new shared module for the first pass.

Why local helpers instead of a new `talent_policy.lua`:
- the initial consumers are only `heuristics_zealot.lua`, `heuristics_psyker.lua`, `healing_deferral.lua`, and possibly `ping_system.lua`
- the repo already warns against unnecessary module sprawl and loader churn
- if Sprint 3 or post-1.0 work adds more consumers, the repeated helper shapes will make the extraction point obvious

### 1. Zealot Martyrdom

**Files:** `scripts/mods/BetterBots/heuristics_zealot.lua`, `scripts/mods/BetterBots/healing_deferral.lua`

Talent-aware rule:
- if the bot has `zealot_martyrdom`, treat low health as a value state rather than an unconditional stealth panic trigger

Concrete behavior:
- suppress medicae station claiming for Martyrdom bots
- suppress medical-crate claiming for Martyrdom bots
- leave pocketable health untouched because the live bot path is still dead
- in Shroudfield heuristics, remove the pure `health_pct < threshold` emergency branch for Martyrdom bots
- keep the toughness-pressure, overwhelm, and ally-aid branches intact

Rationale:
- Martyrdom's value comes from staying wounded
- Shroudfield still has valid defensive use for Martyrdom bots, but it should trigger from pressure, not from low health alone

Expected rule outcomes:
- low health + low pressure: hold stealth
- low health + low toughness / crowd pressure: still use stealth
- human healing deferral settings remain intact for non-Martyrdom bots

### 2. Psyker Venting Shriek / Warp Siphon

**File:** `scripts/mods/BetterBots/heuristics_psyker.lua`

Talent-aware rules:
- if the bot has peril-value talents such as `psyker_damage_based_on_warp_charge` or `psyker_warp_glass_cannon`, preserve more peril before using shout as a vent
- if the bot has `psyker_shout_vent_warp_charge`, treat Venting Shriek as the preferred emergency vent valve

Concrete behavior:
- keep the existing surround / low-toughness / priority-target triggers
- raise the effective "high peril" shout threshold when peril-value talents are present
- raise it further when the improved vent-on-shout modifier is present, because the shout can safely cash out more peril in one activation
- keep low-peril block behavior for low-value situations

Rationale:
- Sprint 2 should be talent-aware, not build-ID-aware
- the same talents should shape behavior for any external profile that equips them
- the existing heuristic seam is enough unless tests show that generic warp-weapon behavior still burns peril before shout decisions matter

Out of scope for Sprint 2:
- no Scrier's Gaze stance tuning
- no generic peril-preservation policy in `weapon_action.lua` yet

### 3. Veteran Voice of Command + Focus Target

**File:** `scripts/mods/BetterBots/ping_system.lua` only if needed

Validation target:
- verify whether the current bot ping flow lets the Veteran bot become the tagger often enough for `veteran_improved_tag` to matter

Important engine fact:
- Focus Target only procs when the Veteran is the actual tagger, not merely when the enemy is tagged by someone else

Implementation posture:
- do not change anything if the current contextual tag path already lets the Veteran claim fresh tags reliably enough
- if the Veteran loses too many valid Focus Target opportunities because `ping_system.lua` skips already-tagged targets too aggressively, make the narrowest possible change there

Likely narrow contingency:
- allow a Veteran Focus Target bot to refresh or assert its own contextual tag on a qualifying elite/special under a stricter rule than the general ping flow, rather than rewriting target scoring

Non-goal:
- no broad `target_selection.lua` retune in Sprint 2

## Testing Strategy

Drive the work with targeted specs at the owning seams.

### Zealot / Psyker

Primary spec surface: `tests/heuristics_spec.lua`

Add cases that prove:
- Martyrdom suppresses the health-only Shroudfield emergency path while preserving pressure-based activation
- Psyker peril-value talents raise the shout high-peril threshold
- improved vent-on-shout talent biases the shout toward higher-peril vent behavior without breaking existing surround / toughness rules

### Healing deferral

Primary spec surface: `tests/healing_deferral_spec.lua`

Add cases that prove:
- Martyrdom bots defer health stations even when they would normally qualify
- Martyrdom bots defer med-crates on the live deployable seam
- non-Martyrdom bots still follow the user-configured thresholds

### Veteran ping validation

Primary spec surface: `tests/ping_system_spec.lua`

Add or adjust cases that prove either:
- the current contextual tag path already produces a valid Veteran-owned tag path for fresh targets, or
- the contingency logic permits a Focus Target Veteran to claim a valid tag when the generic "already tagged" skip would otherwise suppress the buff path

## Logging

Sprint 2 additions must produce confirmation logs only when the new policy actually changes behavior.

Required logs:
- `healing_station:<unit>` / `healing_deployable:<unit>` message should state when Martyrdom defers healing specifically because the bot is preserving its wounded state
- `zealot_stealth_*` result strings should distinguish Martyrdom low-health suppression from ordinary stealth holds
- `psyker_shout_*` result strings should distinguish talent-shaped peril preservation from the generic threshold path
- if Veteran contingency is needed, ping logs should make it obvious when a Focus Target-specific override claimed or refreshed a tag

## Risks

- **False confidence from build-only tuning:** mitigated by keying off talents, not profile names
- **Overfitting the Psyker threshold numbers:** mitigated by keeping the change narrow and covered by heuristic seam tests
- **Veteran churn for little gain:** mitigated by treating Veteran as verification-first and only patching `ping_system.lua` if a concrete seam failure exists
- **Module churn:** mitigated by keeping Sprint 2 helper logic local unless follow-up work creates a real shared abstraction need

## Success Criteria

The change is successful if:
- Martyrdom bots stop grabbing live healing resources and stop firing Shroudfield from low health alone
- Psyker shout behavior preserves more peril when peril-value talents are present and still vents decisively when the vent-on-shout talent is equipped
- Veteran Focus Target is either validated as already functional enough or improved by a narrow ping-path fix
- all changes are covered by targeted busted specs and confirmed through stable debug signals
