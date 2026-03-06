# Handoff

## Current Task
Validate and tune per-career threat heuristics in-game (#2 implementation complete), then move to ability suppression (#11) or Tier 3 reliability (#3).

## Agent
Claude Opus 4.6 (Claude Code)

## What's Done Since Last Handoff
- **Refactored** `BetterBots.lua` into sub-modules: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25/#26 merged)
- **Per-career heuristics** (#2): 13 per-template functions in `heuristics.lua` with rich perception context (`build_context()`)
- **Unit tests**: 95 tests via busted covering heuristics, meta_data, resolve_decision
- **Debug commands**: `/bb_state`, `/bb_decide`, `/bb_brain` for in-game diagnostics
- **CI**: busted runs in CI pipeline

## Decisions Made
- Mod name: `BetterBots`, lives in `$GIT_ROOT/BetterBots`, symlinked into Darktide `mods/` dir
- Approach: Hook `bt_bot_conditions.can_activate_ability` to remove Fatshark's hardcoded whitelist
- Tier 1 (whitelist-only): templates with existing `ability_meta_data`
- Tier 2 (meta_data injection): templates lacking `ability_meta_data`, injected at load time
- Tier 3 (item-based): zealot_relic/force_field/drone use item wield/use fallback sequence
- Heuristics are per-template (not per-class): `TEMPLATE_HEURISTICS` lookup table + special-case for `veteran_combat_ability` (class_tag branching)
- `resolve_decision()` centralizes nil→fallback: unknown templates fall back to `num_nearby > 0`, unknown veteran variants fall back to vanilla logic
- Context is cached per-frame per-unit via `_decision_context_cache`
- `ability_meta_data` is bot-only metadata — safe to inject globally
- Veteran VoC vs Stance detection uses `class_tag` from `ability_template_tweak_data`, with ability name fallback
- Debug logging gated by mod setting, throttled to 2s per unique key

## Changes (cumulative)
- `BetterBots.mod` — DMF mod descriptor
- `scripts/mods/BetterBots/BetterBots.lua` — main: hooks, condition patch, fallback queue
- `scripts/mods/BetterBots/heuristics.lua` — 13 per-template heuristics + `build_context()` + `resolve_decision()`
- `scripts/mods/BetterBots/meta_data.lua` — ability_meta_data injection
- `scripts/mods/BetterBots/item_fallback.lua` — Tier 3 item wield/use/unwield state machine
- `scripts/mods/BetterBots/debug.lua` — debug commands + context/state snapshot helpers
- `scripts/mods/BetterBots/BetterBots_data.lua` — mod options
- `scripts/mods/BetterBots/BetterBots_localization.lua` — display strings
- `tests/test_helper.lua` — make_context(), mock factories, engine stubs
- `tests/heuristics_spec.lua` — 80 tests for all 13 heuristic functions
- `tests/meta_data_spec.lua` — 7 tests for injection/overrides/idempotency
- `tests/resolve_decision_spec.lua` — 8 tests for nil→fallback paths

## Open Questions
- **Heuristic tuning**: All thresholds are initial guesses from tactics docs — need in-game validation. Debug commands (`/bb_decide`) exist for this.
- **Tier 3 reliability**: Force field ~13%, drone ~21%. Root cause unclear (overlapping item fallbacks, slot churn, stage timeout interactions under heavy combat).
- **Force-field/drone instant profiles**: Should they be disabled by default?
- **Zealot Dash targeting**: Dash is directional — bot may dash in place without proper target selection.
- **Ogryn Charge end condition**: `done_when_arriving_at_destination = true` untested — may get stuck.
- **Ability spam vs conservation**: Heuristics add gates but cooldown padding / team-level coordination (#14) not yet implemented.

## Key Files in Decompiled Source
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` — the whitelist gate
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua` — BT leaf
- `scripts/settings/breed/breed_actions/bot_actions.lua` — action_data for BT nodes
- `scripts/extension_systems/ability/player_unit_ability_extension.lua` — ability system internals

## Current Status
- v0.1.0 published on Nexus (2026-03-05)
- Issue #2 implementation complete, needs in-game validation and GitHub close
- Issue #1 closed (Tier 2 validated)
- All P1 issues: #2 (done), #3 (Tier 3 reliability), #10 (charge to rescue), #11 (ability suppression)

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 | GPT-5 | Initial investigation, bot AI audit, ability flow mapping |
| 2026-03-04 | Claude Opus 4.6 | Created mod, README, docs, debug logging, Tertium4Or5 crash fix |
| 2026-03-04 | GPT-5 | Startup crash fix, runtime patching hardening, Tier 2 metadata |
| 2026-03-04 | GPT-5 | Item fallback improvements, force-field/relic timing, validation guards |
| 2026-03-05 | GPT-5 | Tier 1/2 validation complete, Tier 3 hardening, ratio metrics |
| 2026-03-05 | Claude Opus 4.6 | v0.1.0 Nexus release, README restructure, blitz inventory (#4), 6 tactics docs, docs-first policy |
| 2026-03-05 | GPT-5 | Handoff continuity, tomorrow plan |
| 2026-03-06 | Claude Opus 4.6 | Refactor into sub-modules (#25/#26), unit tests (95), per-career heuristics (#2), debug commands |
| 2026-03-06 | Claude Opus 4.6 | Reviewed #2 status — implementation complete, updated STATUS.md and HANDOFF.md |
