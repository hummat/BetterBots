# Handoff

## Current Task
Create a Darktide mod that makes bots use their combat abilities (ults/specials) in Solo Play.

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

## Changes
- `BetterBots.mod` — DMF mod descriptor
- `scripts/mods/BetterBots/BetterBots.lua` — core logic: meta_data injection + condition hook + debug trace hooks
- `scripts/mods/BetterBots/BetterBots_data.lua` — mod options (togglable + debug logs checkbox)
- `scripts/mods/BetterBots/BetterBots_localization.lua` — display name/description + debug setting label
- `mods/mod_load_order.txt` — added `BetterBots` after `Tertium4Or5`
- `<Darktide>/mods/Tertium4Or5/scripts/mods/Tertium4Or5/Tertium4Or5.lua` — patched nil guard for personality/archetype lookup crash (upstream bug, not committed to this repo)

## Open Questions
- **Zealot Dash targeting:** The dash is directional/targeted. Even if activation works, the bot needs a target to dash toward. The BT node's `_start_ability` doesn't handle target selection — the bot may dash in place or random direction.
- **Ogryn Charge end condition:** Added `done_when_arriving_at_destination = true` but untested — bot may get stuck in charge state if destination logic doesn't match.
- **Ability spam:** Bots will fire abilities whenever off cooldown and enemies are nearby. May need cooldown padding or smarter heuristics (health threshold, enemy count, ally proximity).
- **Grenade abilities (Tier 3):** Fundamentally different architecture needed. No `ability_template` → no `template_name` → no entry into the existing BT path. Would need a custom BT node or direct item wield/use approach.
- **Compatibility with game patches:** Each Darktide update may change `bt_bot_conditions`, `AbilityTemplates`, or the BT structure. Mod needs re-validation after patches.
- **DMF `require()` caching:** We use `require()` to get `AbilityTemplates` and `bt_bot_conditions` — verify these return the same singleton tables the game uses (they should, but untested).

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
- Late-session hot-reload (`20:13:20` UTC) confirms new hooks are installed (`ActionCharacterStateChange.finish`, `PlayerUnitActionInputExtension.bot_queue_action_input`), but the same file stops at `20:13:43` UTC, so post-reload combat evidence for the weapon-switch lock is still missing
- Class docs are aligned with decompiled reality where previously mismatched:
  - `psyker_shout` and `zealot_invisibility` documented as metadata-injection paths (not vanilla Tier 1-with-meta)
  - Zealot grenades documented as Tier 3/out of current scope
  - Veteran metadata mismatch (`stance_pressed` vs `combat_ability_pressed`/`combat_ability_released`) documented explicitly
- Frequent `fallback blocked ... invalid action_input=...` log lines are expected transient validity checks but currently noisy
- Tertium4Or5 personality crash fixed locally; bots selectable again in dropdown

## Next Steps
- Stabilize psyker force-field item sequence (timing/inputs) until post-reload runs show repeatable `charge consumed`
- Capture a fresh combat log after the `20:13:20`-style hook install point and verify:
  - `blocked weapon switch while keeping ...` appears while relic/force-field are in protected stages
  - relic hold duration remains intact under close-range pressure
  - force-field success rate improves (fewer `finished without charge consume`)
- Reduce debug noise for expected transient `invalid action_input` states
- Add smarter trigger conditions: health/toughness thresholds, enemy count scaling, ability-specific logic (P1.1)
- Investigate Tier 3 (grenade) approach: search decompiled source for how grenade item wield/use works (P2.1)
- Consider adding mod options (via `_data.lua` widgets) to toggle individual ability classes on/off (P1.3)
- Publish to Nexus Mods once stable

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
