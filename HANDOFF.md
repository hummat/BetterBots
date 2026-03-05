# Handoff

## Current Task
Implement per-career threat heuristics for ability activation (issue #2). Research phase complete — 6 tactics docs exist with proposed bot rules. Next: map rules to perception signals and implement per-template `can_activate` functions.

## Agent
Claude Opus 4.6 (Claude Code)

## Decisions Made
- Mod name: `BetterBots`, lives in `$GIT_ROOT/BetterBots`, symlinked into Darktide `mods/` dir
- Approach: Hook `bt_bot_conditions.can_activate_ability` to remove Fatshark's hardcoded whitelist (only allowed `veteran_combat_ability` and dead-code `zealot_relic`)
- Tier 1 (whitelist-only): 6 templates already have `ability_meta_data` — just need the gate removed
- Tier 2 (meta_data injection): 7 templates exist but lack `ability_meta_data` — we inject it at load time (same pattern as Tertium4Or5's `attack_meta_data` injection)
- Tier 3 (item-based abilities, grenades): NOT addressed — no `ability_template` field at all, would need a fundamentally different approach (new BT node or item wield/use action)
- Trigger logic: Keep original smart conditions for Veteran (elite/special target) and Zealot Relic (threat assessment); all other abilities fire when `enemies_in_proximity() > 0`
- Tier 2 metadata mapping updated to template-specific inputs:
  - Dash/charge templates use `aim_pressed` + `aim_released` + `min_hold_time` (+ `done_when_arriving_at_destination`)
  - Shout templates use `shout_pressed` + `shout_released` + `min_hold_time`
- Force-field item fallback prefers regular placement (`aim_force_field` -> `place_force_field`) and keeps instant placement as secondary fallback
- Force-field ability profile priority is now explicit (`force_field_regular` first), and `broker_ability_stimm_field` is explicitly mapped to `press_release`
- Zealot relic item fallback channel hold was extended (`wield_previous` delayed from `0.8s` to `4.8s`) to avoid immediate cancel
- Item fallback now validates current `weapon_action` template support before queuing start/followup/unwield inputs; if template/input drift occurs (for example switched back to primary weapon), it retries instead of sending invalid inputs
- Item fallback now uses a shared profile catalog (channel/press-release/force-field/drone), ability-specific profile priority, and per-ability profile rotation when a full sequence completes without observed `charge consumed`
- Item fallback success is now tracked by bot `use_ability_charge(combat_ability)` events per unit, not just by queued input logs
- Added bot combat-ability state transition failure recovery: hook `ActionCharacterStateChange.finish` and schedule a fast fallback retry when wanted state was not reached
- Added queue-level weapon-switch lock for item abilities: hook `PlayerUnitActionInputExtension.bot_queue_action_input` and block bot `weapon_action:wield` while protected abilities are active/in-sequence (currently relic active; relic/force-field sequence stages)
- `zealot_relic` whitelist entry in vanilla code is dead code — the ability has no `ability_template` field so `template_name` stays `"none"` and bails before reaching the whitelist
- `ability_meta_data` is a bot-only metadata field (only consumed by BT bot system, never by player code) — safe to inject
- Melee bots fall back to light-only default metadata when weapon `attack_meta_data` is missing (`bt_bot_melee_action.lua`) — same pattern we exploit for ability injection
- `guarantee_ability_activation` mod is scoped to local player (`player1`) only — does not affect bots
- `Tertium4Or5` patches profile selection and ranged `attack_meta_data` but does not touch bot ability conditions
- Debug logging added with three trace points: condition decision, BT node enter, ability charge consumed — gated by `enable_debug_logs` mod setting, throttled to 2s per key
- Tertium4Or5 personality crash fixed locally (nil guard on `Personalities` lookup in `fetch_all_profiles`)
- Startup crash fix in BetterBots: moved debug hooks for `BtBotActivateAbilityAction` and `PlayerUnitAbilityExtension` behind `mod:hook_require(...)` to avoid early `require()` of ability systems before `NetworkConstants` is initialized
- Condition + template patching now also uses `mod:hook_require(...)` (instance-safe across require store), avoiding single-instance `require()` patch misses
- 2026-03-05: Tier 2 validation is complete for all non-`N/A` rows; tracking moved to `docs/VALIDATION_TRACKER.md` and GitHub issue `#1` was closed.
- 2026-03-05: Tier 3 triage now uses ratio metrics (`consume / (consume + no-charge completion)`) instead of one-off success evidence.
- 2026-03-05: `adamant_area_buff_drone` should use the same sequence-time weapon-switch lock mechanism as relic/force-field.
- 2026-03-05: `force_field_instant` required explicit followup `instant_place_force_field`; aim-only instant path was insufficient.
- 2026-03-05: Release decision: first Nexus release is acceptable as **beta/preview**, not stable; keep Tier 3 reliability issue open.

## Changes
- `BetterBots.mod` — DMF mod descriptor
- `scripts/mods/BetterBots/BetterBots.lua` — core logic: meta_data injection + condition hook + debug trace hooks
- `scripts/mods/BetterBots/BetterBots_data.lua` — mod options (togglable + debug logs checkbox)
- `scripts/mods/BetterBots/BetterBots_localization.lua` — display name/description + debug setting label
- `mods/mod_load_order.txt` — added `BetterBots` after `Tertium4Or5`
- `<Darktide>/mods/Tertium4Or5/scripts/mods/Tertium4Or5/Tertium4Or5.lua` — patched nil guard for personality/archetype lookup crash (upstream bug, not committed to this repo)
- 2026-03-05: `scripts/mods/BetterBots/BetterBots.lua` — added `adamant_area_buff_drone` to sequence switch-lock table; tuned force-field/drone item timings (`start_delay_after_wield`, `followup_delay`, `unwield_delay`, `charge_confirm_timeout`); added `instant_place_force_field` followup to instant force-field profile.
- 2026-03-05: `docs/VALIDATION_TRACKER.md` — added structured run entries for Tier 1/2/3, added ratio-based reliability snapshots (rolling file + post-patch window), and updated tier matrix states.
- 2026-03-05: `docs/STATUS.md` — refreshed with latest rolling-log evidence and current Tier 3 blocker framing.
- 2026-03-05: `README.md` — updated "Current status" to March 5 and beta-scope wording for Tier 3 reliability.
- 2026-03-05: `docs/CLASS_OGRYN.md`, `docs/CLASS_ZEALOT.md`, `docs/CLASS_ARBITES.md` (and related class docs) — aligned in-game names/exposure notes with observed profiles and current live UI.
- 2026-03-05: GitHub issue updates — `#3` commented with latest post-patch evidence (`https://github.com/hummat/BetterBots/issues/3#issuecomment-4006146959`), Tier 3 issue remains open.
- 2026-03-05: Published v0.1.0 on Nexus Mods (https://www.nexusmods.com/warhammer40kdarktide/mods/745)
- 2026-03-05: Added Nexus badge to README, restructured README for dual GitHub/Nexus audience
- 2026-03-05: Created `docs/NEXUS_DESCRIPTION.bbcode` — BBCode source for Nexus mod page description
- 2026-03-05: Fixed CI: replaced `rg` with `find` in Makefile (rg not on GitHub Actions runners)
- 2026-03-05: Rewrote issue #4 body with complete blitz/grenade inventory (18 internal definitions, 6 classes)
- 2026-03-05: Created 6 `docs/CLASS_*_TACTICS.md` files — community-sourced tactical heuristics with USE WHEN / DON'T USE / PROPOSED BOT RULES per ability
- 2026-03-05: Updated issue #2 body to reference tactics docs and revised design constraints (Peril tracking, toughness-reactive, class_tag detection)
- 2026-03-05: Added mandatory docs-first policy to CLAUDE.md — agents must consult local docs before implementing ability work

## Open Questions
- **Zealot Dash targeting:** The dash is directional/targeted. Even if activation works, the bot needs a target to dash toward. The BT node's `_start_ability` doesn't handle target selection — the bot may dash in place or random direction.
- **Ogryn Charge end condition:** Added `done_when_arriving_at_destination = true` but untested — bot may get stuck in charge state if destination logic doesn't match.
- **Ability spam:** Bots will fire abilities whenever off cooldown and enemies are nearby. May need cooldown padding or smarter heuristics (health threshold, enemy count, ally proximity).
- **Grenade abilities (Tier 3):** Fundamentally different architecture needed. No `ability_template` → no `template_name` → no entry into the existing BT path. Would need a custom BT node or direct item wield/use approach.
- **Compatibility with game patches:** Each Darktide update may change `bt_bot_conditions`, `AbilityTemplates`, or the BT structure. Mod needs re-validation after patches.
- **DMF `require()` caching:** We use `require()` to get `AbilityTemplates` and `bt_bot_conditions` — verify these return the same singleton tables the game uses (they should, but untested).
- 2026-03-05: Why does force-field still have low consume ratio despite lock + explicit instant place followup? Candidate causes: overlapping item fallbacks, slot churn, and stage timeout interactions under heavy combat.
- 2026-03-05: Drone no-charge outcomes are skewed toward `drone_instant` in the post-patch window; should `drone_regular` be preferred/forced as temporary reliability mode?
- 2026-03-05: Should force-field/drone instant profiles be disabled by default for beta, or exposed as an advanced option?

## Key Files in Decompiled Source
- `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua` — the whitelist gate (lines 59-100)
- `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_activate_ability_action.lua` — BT node that queues ability input
- `scripts/settings/breed/breed_actions/bot_actions.lua` — action_data for BT ability nodes
- `scripts/extension_systems/behavior/trees/bot/bot_behavior_tree.lua` — BT structure (abilities already in tree)
- `scripts/extension_systems/ability/player_unit_ability_extension.lua` — ability system (NO `is_human_controlled` gates)
- `scripts/extension_systems/input/bot_unit_input.lua` — bot input class (has `get()` method)
- `scripts/extension_systems/input/player_unit_input_extension.lua` — switches between human/bot input
- `scripts/extension_systems/behavior/bot_behavior_extension.lua` — brain update tick (gated on `is_human_controlled`)

## Reference Mods
- **Tertium4Or5** (`mods/Tertium4Or5/`) — hooks `BotSynchronizerHost:add_bot`, injects `attack_meta_data` into weapon templates at load time. Best pattern reference.
- **guarantee_ability_activation** (`mods/guarantee_ability_activation/`) — shows ability state API (`remaining_ability_charges`, cooldown components, `InputService` faking)
- **AbilityGod** (Nexus, no public source) — automates ability activation for player based on thresholds

## Current Status
- 2026-03-05 update:
  - Tier 1 and Tier 2 are complete for currently testable rows (`docs/VALIDATION_TRACKER.md`).
  - Tier 3: `zealot_relic` is stable PASS; `psyker_force_field_dome` and `adamant_area_buff_drone` are PARTIAL with repeated consume evidence but still many no-charge completions.
  - Latest rolling-file snapshot (`console-2026-03-05-14.57.34-...`): force-field `9/69`, drone `10/76`, relic `5/5` (consume/attempt).
  - Post-patch window (from first `instant_place_force_field`): force-field `4/38` (10.5%), drone `7/33` (21.2%).
- Mod loads, injection logs appear, debug logging system functional
- Startup crash signature `attempt to index global 'NetworkConstants'` in `action_handler.lua` (via top-level `require("player_unit_ability_extension")`) has been fixed locally by delayed hooks
- Tier 2 metadata now uses template-specific action inputs with wait/release support and hold timing
- Condition patch now installs via `hook_require` and logs installation diagnostics (`patched bt_bot_conditions.can_activate_ability`)
- In-game casts are confirmed via `charge consumed` logs for:
  - `veteran_combat_ability_stance_improved`
  - `ogryn_charge_increased_distance`
  - `zealot_invisibility_improved`
- `psyker_force_field` charge consumption was observed earlier in run (`17:11:49`, `17:12:37`), but post-reload sequence (`aim_force_field`/`place_force_field`) is currently mixed and not consistently confirmed by later `charge consumed`
- Latest run also showed parser mismatches (queued item input while parser template was non-ability weapon), e.g. `aim_force_field` against `combatknife_*` and `channel`/`wield_previous` against `powersword_*`/`bolter_*`; guard logic added to prevent these invalid queues
- Item fallback now has an explicit `waiting_charge_confirmation` stage; failed full sequences log `fallback item finished without charge consume ...` and rotate profile when alternatives exist (for example force-field regular vs instant)
- Latest long run (`console-2026-03-04-18.58.17-...`) still shows strong Zealot relic success (`charge consumed` repeatedly), but Psyker force-field remains unstable (many `finished without charge consume` versus few successful consumes)
- Class docs are aligned with decompiled reality where previously mismatched:
  - `psyker_shout` and `zealot_invisibility` documented as metadata-injection paths (not vanilla Tier 1-with-meta)
  - Zealot grenades documented as Tier 3/out of current scope
  - Veteran metadata mismatch (`stance_pressed` vs `combat_ability_pressed`/`combat_ability_released`) documented explicitly
- Frequent `fallback blocked ... invalid action_input=...` log lines are expected transient validity checks but currently noisy
- Tertium4Or5 personality crash fixed locally; bots selectable again in dropdown

## Next Steps
- ~~Prepare Nexus beta/preview release~~ DONE (v0.1.0 published 2026-03-05)
- Commit 6 tactics docs + README tactics links + CLAUDE.md docs-first policy (uncommitted)
- Implement per-career threat heuristics (#2): map tactics doc rules to perception signals, implement per-template `can_activate` functions
- Add Peril tracking hook for Psyker bot abilities (new requirement from tactics research)
- Add `class_tag` detection for Veteran Voice of Command vs Executioner's Stance branching
- Stabilize psyker force-field item sequence (#3)
- Stabilize Arbites drone item sequence (#3); test `drone_regular`-first-only
- Reduce debug noise for expected transient `invalid action_input` states
- Investigate Tier 3 (grenade) approach (#4)
- Add mod settings for per-ability toggle (#6)
- Ship conservative defaults for force-field/drone until reliability improves

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 | GPT-5 (Codex CLI) | Initial investigation: audited decompiled bot AI scripts, confirmed ability flow gating points, confirmed existing mods don't touch bot abilities, collected online modding resources |
| 2026-03-04 | Claude Opus 4.6 (Claude Code) | Investigated Darktide bot AI architecture, mapped all ability templates to bot-readiness, created Phase 1 mod with Tier 1+2 support, set up git repo with symlink |
| 2026-03-04 | Claude Opus 4.6 (Claude Code) | Added README + docs (architecture, known issues, test plan, roadmap). Added debug logging system (condition/enter/charge trace points, mod setting toggle, 2s throttle). Fixed Tertium4Or5 personality crash blocking bot selection. Preparing for T1 in-game test. |
| 2026-03-04 | GPT-5 (Codex CLI) | Debugged crash after `guarantee_special_action` spam: root cause was early top-level require of `player_unit_ability_extension` causing `NetworkConstants` nil during mod init. Switched ability debug hooks to `hook_require` delayed hooks to prevent startup-time load crash. |
| 2026-03-04 | GPT-5 (Codex CLI) | Hardened runtime patching: moved `AbilityTemplates` metadata injection and `bt_bot_conditions.can_activate_ability` override to `hook_require` instance-safe patches; updated Tier 2 metadata to template-specific action inputs (`aim_pressed`/`shout_pressed`) with release+hold data; added explicit debug markers for patch installation and gameplay state entry. |
| 2026-03-04 | GPT-5 (Codex CLI) | Latest log snapshot documented: veteran/ogryn/zealot casts confirmed by repeated `charge consumed`; psyker force-field mixed after reload (queueing seen, later consumes not yet repeatable). Added `docs/STATUS.md` and synchronized README/known-issues/handoff state. |
| 2026-03-04 | GPT-5 (Codex CLI) | Aligned class docs with actual template metadata state (Psyker/Zealot/Veteran corrections). |
| 2026-03-04 | GPT-5 (Codex CLI) | Investigated new runtime logs: relic was unwielded too early and force-field had no charge-consume evidence. Updated item fallback to keep regular force-field aim/place as primary and increased relic channel hold before unwield (0.8s -> 4.8s). |
| 2026-03-04 | GPT-5 (Codex CLI) | Found parser-template drift in runtime logs (`aim_force_field`/`channel` queued while parser template was combat knife/sword/bolter). Added per-stage template/input validation in item fallback so invalid queues are skipped/retried instead of being sent. |
| 2026-03-04 | GPT-5 (Codex CLI) | Added immediate follow-up fixes from `RELATED_MODS` comparison: force-field regular-first profile preference, explicit `broker_ability_stimm_field -> press_release` mapping, and combat-ability state-transition fast retry via `ActionCharacterStateChange.finish`. |
| 2026-03-04 | GPT-5 (Codex CLI) | Added queue-level bot weapon-switch lock (`PlayerUnitActionInputExtension.bot_queue_action_input`) to prevent switching away during relic active channel / item-sequence critical stages; awaiting post-reload combat log evidence to validate impact. |
| 2026-03-05 | GPT-5 (Codex CLI) | Validated Tier 1/2 completion; hardened Tier 3 fallback (`adamant_area_buff_drone` lock, force-field instant place followup, timing/timeout tuning); documented ratio-based reliability metrics; updated README/STATUS/VALIDATION tracker; commented issue #3 and marked first Nexus release as beta-ready with Tier 3 caveats. |
| 2026-03-05 | Claude Opus 4.6 (Claude Code) | Published v0.1.0 on Nexus Mods. Restructured README for dual audience. Fixed CI (rg→find). Rewrote issue #4 with complete blitz inventory (18 defs, 6 classes). Researched per-class tactical heuristics via 6 parallel sub-agents; created 6 CLASS_*_TACTICS.md docs. Updated issue #2 with research results and revised design. Added docs-first mandate to CLAUDE.md. |
