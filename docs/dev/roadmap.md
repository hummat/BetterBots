# Roadmap

## Vision

Make Darktide bots as capable as VT2's modded bots (Grimalackt's Bot Improvements - Combat). Start with ability activation (already shipped), then add smart trigger heuristics, safety guards, and general behavior improvements.

## What's shipped

### v0.1.0 (2026-03-05)
- Tier 1 + Tier 2 ability activation for all 6 classes (whitelist removal + meta_data injection)
- Tier 3 item-based abilities (zealot relic, force field, drone — initial implementation)
- Runtime diagnostics (condition/enter/charge trace hooks, debug logging)
- Generic trigger: `enemies_in_proximity() > 0`

### v0.2.0 (2026-03-06)
- Sub-module refactor: `heuristics.lua`, `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25)
- Per-career threat heuristics (#2): 18 functions (14 combat + 4 item) with per-ability activate/hold rules
- 142 unit tests via busted

### v0.3.0 (2026-03-07)
- Tier 3 reliability fix (#3): all testable item abilities at 100% consume rate
- Structured JSONL event logging (#29) with `bb-log events` analysis subcommands
- Item heuristics: per-ability rules for relic, force field, drone, stimm field

### v0.4.0 (2026-03-08)
- Poxburster targeting (#34), ADS fix (#35), bot sprinting (#36)
- Charge/dash rescue aim (#10): rescue triggers + aim correction for zealot dash, ogryn charge, arbites charge
- 198 unit tests, M3 complete

### v0.5.0 (2026-03-09)
- VFX/SFX bleed fix (#42), smart melee attack selection (#23), ranged fire fix (#31), warp venting (#30)
- Staff charged fire (#43, partial — p4 PASS in-game, p3 untested, p1/p2 need investigation)

### v0.6.0 (2026-03-11)
- Grenade/blitz throw (#4): state machine for 19 templates, profile-driven. Standard/handleless/mine/knives/whistle/missile. Initial support only.
- Staff charged fire complete (#43): all 4 staves PASS — chain-only fire derivation fix for p1 Voidstrike + p2 Purgatus.
- Bot pinging (#16): bots ping elites/specials for human player.
- Distant special penalty (#19): melee target distance penalty for specials.
- Daemonhost avoidance (#17): suppress combat near dormant daemonhosts.
- 305 unit tests

### v0.7.0 (2026-03-12)
- Batch 2 shipped: grenade heuristics + Psyker blitz follow-up (#4), hazard-aware abilities (#21), boss engagement refinement (#18), tiered log levels (#40), healing deferral implementation (#39), player-tag smart-target response (#48), and follow-up validation/logging cleanup.

### v0.7.1 (2026-03-14)
- P0/P1 stabilization: animation crash guard (#50), ammo threshold (#51), melee horde bias (#52), Assail void throws (#61), grenade misaim (#62), unarmed defer, smart blitz targeting, ADS fire fix. Repo cleanup (scrapers migrated to hadrons-blessing). 461 tests.

### v0.8.0 (2026-03-16)
- Default class-diverse bot profiles (#45): 4-class loadouts with per-slot settings, Tertium compat, cosmetic overrides.
- Full talent enrichment (#63): ~30 talents per class from hadrons-blessing builds, including abilities, keystones, and stat nodes. Bot-optimized build selection (Voice of Command veteran, Electro Shriek psyker, Gun-Lugger ogryn).
- Weapon blessings and perks (#63 phase 2): 2 T4 blessings + 1-2 T4 perks per weapon via synthetic `get_item_instance` overrides. First mod to construct blessed weapons without player backend profiles.
- Settings control surface (#6): category checkboxes, 4 behavior presets, feature gates, veteran semantic stance/shout gate.
- Heuristic dispatch refactor (#60), grenade fallback logging (#59), toggle safety audit (#57).
- Log throttle collision fix: 19 per-bot debug log keys were silently dropping multi-bot messages. Convention updated in AGENTS.md + logging.md.
- 518 unit tests.

### v0.9.0 (2026-04-02)
- Combat-aware engagement leash (#47): coherency-anchored melee leash with already-engaged, under-attack, ranged-foray, and post-charge-grace overrides. 700+ override events validated.
- Non-veteran profile crash fix (#65): `set_profile` hook blocks lossy network-sync overwrite on 1.11.x.
- Mastiff-pounced priority (#55): score boost for pounced enemies + fix for zero-score gate when bot has no slot.
- Poxburster push (#54): bypass `_should_push` outnumbered gate for poxbursters.
- Rumbler VFX timing gap (#53): pre-call hook on loadout init.
- Healing deferral validated (#39): health station deferral confirmed in-game.
- Parser-level ability input validation: `_action_input_is_bot_queueable` in shared_rules.lua fixes 1.11.x action input rejection for combat abilities.
- Event log JSON fix: `_json_safe_number` sanitizes infinity/NaN before cjson.encode.
- Debug logging: set_profile guard, record_charge, per-bot poxburster keys.
- 579 unit tests via busted.

## Planned batches

Issues are tracked on [GitHub](https://github.com/hummat/BetterBots/issues).

### v0.9.0 — "Combat Awareness"

*Theme: bots perceive and react to combat situations better.*

| # | Issue | Notes |
|---|-------|-------|
| 65 | **P0: non-veteran profiles CTD on 1.11.0** | **Done.** `set_profile` hook blocks lossy network-sync overwrite. Validated on 1.11.3. |
| 54 | Push poxbursters | **Done.** Bypass `_should_push` outnumbered gate for poxburster breed + push logging. |
| 55 | Prioritize mastiff-pounced enemies | **Done.** Score boost for immobilized targets. Fixed `score=0` gate bug (pounced enemies have no bot slot). Validated with 80+ pounce events. |
| 53 | Rumbler VFX timing gap | **Done.** Pre-call hook on loadout init restored (crash was from profiles, not VFX). |
| 47 | Combat-aware engagement leash | **Done.** Coherency-anchored leash: stickiness-limit extension, post-charge grace (validated), under-attack/ranged-foray overrides. 700+ override events in-game. |
| 39 | Healing deferral | **Done.** Validated: 80+ health station deferral events. Correct no-defer when human at full health. |
| — | Parser-level input validation | **Done.** `_action_input_is_bot_queueable` in shared_rules.lua: check parser sequence_configs before action handler validation. Fixes 1.11.x action input rejection. |
| — | Event log JSON fix | **Done.** `_json_safe_number` sanitizes `math.huge`/`NaN` before `cjson.encode`. |

### v0.9.1 — Hotfix (user-reported regressions)

*Theme: fix regressions and behavior issues reported on Nexus after v0.9.0.*

| # | Issue | Notes |
|---|-------|-------|
| 67 | **P0: hook_require clobbering** | **Done.** April 7 logs show the consolidated `bt_bot_melee_action` hook install and repeated `melee choice ...` lines, confirming the clobbering regression is fixed. |
| 68 | **P1: Veteran class swap with other mods** | `resolve_profile` yield guard checks `archetype != "veteran"` — fails when Tertium assigns a real veteran. DMF hook order flips with extra mods. Fix: check `profile.character_id` instead. |
| 73 | **P1: exception-safe shared state mutation** | **Done.** Wrapped the temporary shared-state mutations in restore-on-error guards. Kept as defensive hardening; reopen only on actual repro. |
| 69 | P2: Mastiff-pinned target fixation | **Done.** Validated in run `0`: friendly companion-pin penalties fired in both melee and ranged scoring. |
| 70 | P2: Arbites whistle ignores dog position | **Done.** Validated in run `0`: invalid whistles were held and valid whistles still consumed charges. |
| 71 | P2: Ogryn grenade mid-horde | **Done.** April 7 event log shows `grenade_ogryn_frag_block_melee_range` below 4m and `grenade_ogryn_frag_horde` only above 4m. |
| 72 | P3: Configurable ammo policy | **Done.** April 7 logs exercised both the lowered ranged fire gate and ammo pickup decisions in runtime. |

### v0.10.0 — "Team Coordination"

*Theme: bots coordinate with each other, protect interacting allies, and direct companions deliberately.*

| # | Issue | Notes |
|---|-------|-------|
| 14 | Ability cooldown staggering | **Done + validated** in `console-2026-04-11-17.41.41`: textbook timeline at 17:50:09–17:50:18 — vet shout records `aoe_shout` at t0, two psyker shouts suppressed at Δ=2 s and Δ=4 s (`fallback suppressed psyker_shout (team_cd:aoe_shout)`), third psyker attempt at Δ=8 s fires through normally after the 6 s window expires. Two integration bugs found and fixed in `d890695`: variant talent name vs semantic_key in `TeamCooldown.record()`, and missing `is_suppressed` check in `ability_queue.lua` fallback path (the dominant activation path in solo play). Closed. |
| 37 | Objective-aware ability activation (P1) | **Done + validated** in `console-2026-04-11-16.51`: `veteran_voc_protect_interactor` queued 4× and `ogryn_charge_block_protecting_interactor` held 7× during the same run. Both the activate-defensively and suppress-aggressive sides confirmed. Closed. |
| 7 | Revive-with-ability (P1) | **Done + validated** in `console-2026-04-11-16.51`: 5 `revive_candidate observed` lines (psyker × 4, vet × 1; both `knocked_down` and `netted` interaction types) plus `revive ability skipped (psyker_shout can_use_ability=false)` proving the full hook → identity → ability check chain executes. Closed. |
| 49 | Arbites companion-command smart tag | **Done + validated.** 42+ `companion-tagged` events across 2 sessions plus `bot 5 companion-tagged renegade_netgunner (reason: opportunity_target_enemy)` in the latest run, with `already_tagged` dedup firing as expected. Closed. |
| 81 | Expand settings surface | **Done + validated** in `console-2026-04-11-16.51`: startup log line `settings: preset=balanced, sprint_dist=12, chase_range=18, tag_bonus=3, horde_bias=4, smart_targeting=true, dh_avoidance=true` resolves all 7 spec values. Always-emit-all-values mode landed in `ed9f12b`. Closed. |
| 83 | Settings UI: reorganize groups, factory functions, visual polish | **Done.** All 8 checklist items complete across `962a384`, `c7c9954`, `5695e1f`, `ed9f12b`. Group split, slot dropdown factory + deep-copy, Testing preset moved last, slider tooltip pattern, "Max" string fix, slot grouping with descriptions, gold/citrine group headers, event_log/perf_timing show_widgets gating. Plus golden mod_name with U+E048 mastery glyph. Closed. |

### v0.11.0 — "Combat Execution" (final polish batch)

*Theme: small, high-ROI polish. Trivial wins and one teammate-feel feature.*

| # | Issue | Notes |
|---|-------|-------|
| 32 | Mule item pickup | Implemented on branch. New `mule_pickup.lua` activates vanilla book-carry flow by mirroring `inventory_slot_name -> slot_name` and setting `bots_mule_pickup` on the side-mission book pickup templates. Tomes/scriptures are always enabled; grimoires are gated behind a new BetterBots toggle that defaults off and also blocks grimoire pickup orders while disabled. |
| 44 | Human-likeness tuning (Tier A) | Implemented on branch. The old checkbox is replaced by split timing/leash profiles: `human_likeness.lua` now resolves `off/fast/medium/slow/custom` timing into BotSettings reaction times plus defensive/opportunistic jitter buckets, while `engagement_leash.lua` reads `off/light/medium/strong/custom` pressure-leash scaling instead of the old fixed half-leash model. Grenade/blitz timing, aim tuning, and dodge tuning remain out of scope. |
| 82 | Perf low-hanging fruit audit | Implemented on branch. Final low-risk pass only: `ability_queue.lua` now caches one-shot `AbilityTemplates` injection instead of requiring/injecting on every fallback tick, and `target_selection.lua` now memoizes same-frame smart-tag, companion-pin, and slot-ammo lookups inside the hot per-target scoring path. Intentionally no fresh `/bb_perf` headline claim yet; this closes the remaining cheap cleanup without reopening medium-risk items like `build_context()` table reuse. |
| 87 | Sustained fire for flamers and held-fire weapons | Implemented on branch. New `sustained_fire.lua` observes queued `weapon_action` inputs, arms per-unit sustained state for supported full-auto / stream paths, and injects required raw hold inputs through `BotUnitInput._update_actions` until the path goes stale or clears. Covered: flamer, Purgatus, recon lasguns, autoguns, autopistol, dual autopistols, bolter hipfire, heavy stubbers, and rippergun braced fire. Scope remains execution-only; ADS/brace choice still belongs to #41. |
| 89 | Bot grenade pickup heuristic | Implemented on branch. `ammo_policy.lua` now piggybacks the vanilla `pickup_component.ammo_pickup` slot for nearby `small_grenade` refills, but only for charge-based grenade users at or below the configured bot grenade threshold. Human grenade reserve is always respected (no bot desperation override), cooldown-only blitz users are ignored, and deferred grenade pickups do not block bots from still taking ammo. |
| 90 | Melee/ranged target type hysteresis | Implemented on branch. New `target_type_hysteresis.lua` wraps perception-layer `bot_target_selection_template.bot_default`, recomputes vanilla melee/ranged scores, and only flips `target_enemy_type` when the opposite mode clears both a `0.10 * max(abs(scores), 1)` margin and a small current-type momentum bonus. BT remains untouched; scope is strictly target-type stabilization. Debug verification uses `target_type_flip:<unit>` logs. |
| 91 | Bot weakspot aim MVP | Implemented on branch. `ranged_meta_data.lua` now injects vanilla-style `aim_at_node = { 'j_head', 'j_spine' }` for lasguns, autoguns, bolters, and stub revolvers when the template leaves `attack_meta_data.aim_at_node` unset. Existing `aim_at_node` values still win, and vanilla `target_breed.override_bot_target_node` behavior is unchanged. Per-breed weakspot map (Mauler/Crusher/Bulwark) remains deferred to `#92`. |
| 93 | Grenade ballistic arc fix | Implemented on branch. `grenade_fallback.lua` now resolves projectile locomotion data from the equipped grenade weapon template and mirrors vanilla `Trajectory.angle_to_hit_moving_target(...)` solving for supported gravity-affected manual-physics projectile families. Covered: standard grenades, handleless grenades, Ogryn grenade throws, and zealot throwing knives. Flat fallback remains for `broker_missile`, psyker knives, whistle, smite, chain lightning, and mines. |

### v1.0.0 — "Bot Identity"

*Theme: bots feel like teammates, not automatons. VT2 Bot Improvements parity. Mechanical polish + talent awareness.*

| # | Issue | Notes |
|---|-------|-------|
| 13 | Navmesh validation for charges | GwNav raycast before committing charge direction. VT2 reference values available. Darktide uses navigation destination vector, not `aim_position`. Moved from v0.11.0 — research-heavy, better paired with weapon-family work. |
| 24 | Healing item management | Medicae discipline, healing item distribution, stim usage. Three independent subsystems. |
| 33 | Weapon special actions | Parry, heavy sweep, racking slide. Input mechanism trivial; decision logic (when to parry) is the work. |
| 38 | Talent-aware behavior | Zealot Martyrdom PoC: suppress healing, adjust heuristic thresholds. Framework for future keystones (Scrier's Gaze peril, Carapace Armor stacks). Detection via `talent_extension:talents()`. |
| 41 | Weapon-aware ADS vs hip-fire | Dynamic `ranged_gestalt` per weapon family. Per-weapon aim data alongside `attack_meta_data`. Moved from v0.11.0 — wide blast radius across ranged code, pairs with weapon-family taxonomy. |
| 86 | Tier 3 revive cover (extends #7) | Extend pre-revive activation to item-based defensives: Psyker Telekine Shield, Zealot Relic, Arbites Nuncio-Aquila drone (+30% revive speed with `adamant_drone_buff_talent`). Requires parallel resolution branch through `item_fallback.lua`. 2026-04-11 audit confirmed combat-ability whitelist is complete; Tier 3 is the remaining gap. |
| 92 | Per-breed weakspot aim map (follow-up to #91) | MVP #91 randomizes head/spine via `attack_meta_data` for all humanoid breeds, which is correct for ~80% but wrong for several elites: Mauler helmet glances, Crusher carapace front rending-resistant (back-of-head is the weakspot), Bulwark shield-front exposure. Hook `BtBotShootAction._set_new_aim_target` (per-target acquisition, cheap) and override `scratchpad.aim_at_node` from a `{[breed_name] = aim_node}` table. Depends on #91 (MVP injection layer) + #41 (weapon-family classifier — skip override on weapons where breed weakspot doesn't matter). Per-breed node names need verification from `breeds/*` source. Filed 2026-04-11. |

### Post-1.0 — "Intelligence Architecture"

*Theme: architectural upgrades and research-track items. Not scoped for a release — each is a mini-project.*

| # | Issue | Notes |
|---|-------|-------|
| 22 | Utility-based ability scoring | Replace boolean heuristics with spline-interpolated utility curves. Darktide has native `utility.lua` + `bot_utility_considerations.lua` — framework exists, needs wiring. Architectural upgrade. |
| 28 | Built-in bot profile management | Absorb Tertium4Or5 functionality. Profile selection + loadout preset support. Only pursue if upstream remains unpatched. |
| 56 | Communication wheel response | React to com wheel commands (battle cry → aggression boost, need help → converge). `Vo.on_demand_vo_event` hook for detection. ForTheEmperor compat. |
| 80 | Grenade/blitz tactical evaluator | Shared grenade/blitz decision object, family-specific targeting/placement, Arbites dog vs `Lone Wolf` split, and execution-time revalidation tied to original tactical intent. Planning docs: `docs/superpowers/specs/2026-04-08-grenade-blitz-tactical-evaluator-design.md`, `docs/superpowers/plans/2026-04-08-grenade-blitz-tactical-evaluator.md`. References `#49` (companion command smart tag) and is intentionally narrower than `#22`. |
| 84 | User-authored bot profiles | Integration with hadrons-blessing for user-defined bot builds. Design-heavy, no concrete scope yet. |
| 85 | Refactor combat ability identity | Separate `template_name` from `ability_name` semantics. Tech debt cleanup, no user-visible value. |
| 88 | Deployable crate carry + deploy (ammo + medical) | Bots walk past `pocketable` form crates — cannot carry, cannot deploy. Full vanilla use pipeline for *deployed* crates (see `#39`/`#72`), but no detection, carry, or deploy action for carryable form. Shared pocketable-pickup primitive with `#24` stim section. Design work: deploy-location heuristic (coherency anchor, objective markers, ally resource needs). Filed 2026-04-11 after `#32` triage exposed the gap. |
| 96 | Bridge explicit smart-tag item interactions into bot pickup/drop orders | Shared bridge issue, not an item-family issue. VT2 precedent is explicit pickup orders via item-ping/social-wheel response; Darktide has `BotOrder` backend plus smart-tag interaction backend but no obvious equivalent Lua UI sender. Scope: route explicit non-enemy smart-tag interaction into bot pickup/drop assignment for supported families; queue after `#24` and `#88`. |

### Validation-gated — slot into any batch when testable

| # | Issue | Blocker |
|---|-------|---------|
| 8 | Hive Scum ability support | DLC-blocked (Hive Scum / `broker` archetype not owned) |
| 17 | Daemonhost avoidance | Code + tests shipped v0.6.0. First real DH spawn on 2026-04-11 exposed a grenade/blitz-path gap; heuristic carve-out staged in `03ce4fd`+`ffe7c6b`. Re-validation on next DH spawn. |

## Design principles

1. **Don't break what works.** Vanilla bot combat (melee, shoot, revive, rescue, follow) must remain functional. Every change is additive.
2. **Per-ability, not per-class.** Trigger heuristics are per ability template, not per archetype. A Zealot with Dash needs different rules than a Zealot with Stealth.
3. **Precise triggers, eager usage.** Bots should use abilities frequently but only when the trigger conditions genuinely apply. Community consensus (VT2 and Darktide) strongly favors maximizing ability uptime — conservation frustrates players more than occasional misfires. Heuristics should be confident, not rare.
4. **Observable.** Debug logging traces every activation decision. If a bot does something wrong, the log should explain why.

## Research basis

Heuristics and feature ideas are sourced from:
- **VT2 Bot Improvements - Combat** (Grimalackt) — per-career threat thresholds, revive-with-ability, elite pinging, boss engagement, melee selection
- **VT2 Bot Improvements - Impulse Control** (Squatting-Bear) — ability suppression, anti-waste conditions
- **VT2 decompiled source** — 14-level BT, utility-based scoring, 90+ considerations, item management
- **Darktide community** (Fatshark forums, Steam, Reddit) — prioritized pain points
- **Darktide decompiled source** (v1.10.7) — untapped perception signals, blackboard data, cover system, formation logic
- **Per-class tactics docs** (`docs/classes/*-tactics.md`) — community-sourced USE WHEN / DON'T USE / proposed bot rules

See `docs/related-mods.md` for detailed mod analysis and `docs/classes/*-tactics.md` for per-ability heuristics.

## Milestone history

1. **M1 (v0.1.0):** Tier 1 + Tier 2 abilities activate in solo play. Published on Nexus.
2. **M2 (v0.2.0–v0.3.0):** Per-career threat heuristics + Tier 3 reliability + structured event logging.
3. **M3 (v0.4.0):** Ability quality + bot fixes — suppression, charge rescue, Psyker overcharge, revive protection, poxburster targeting, ADS fix, bot sprinting.
4. **M4 (v0.5.0):** Ability polish + weapon fixes — VFX/SFX bleed, melee/ranged meta_data, warp venting, staff charged fire (partial).
5. **M5 (v0.6.0):** Scope expansion — grenade/blitz, staff charged fire complete, bot pinging, daemonhost avoidance, distant special penalty.
6. **M5-batch2 (v0.7.0):** Grenade heuristics + Psyker blitz, ping anti-spam, hazard-aware abilities, boss engagement, healing deferral, player-tag response.
7. **v0.7.1:** P0/P1 stabilization — animation crash guard, ammo threshold, melee horde bias, Assail void throws, grenade misaim. 461 tests.
