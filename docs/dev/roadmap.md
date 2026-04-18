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
- Sub-module refactor: thin `heuristics.lua` dispatcher + split `heuristics_context.lua` / `heuristics_*.lua`, plus `meta_data.lua`, `item_fallback.lua`, `debug.lua` (#25)
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
| 68 | **P1: Veteran class swap with other mods** | **Done.** Yield guard now checks `profile.character_id and profile.name` (real backend characters always carry `name`; vanilla bot stubs use `name_list_id` instead), committed in `8520485`. Validated from run `console-2026-04-07-15.36.11`: BetterBots preserved external profiles for bot slots 1–4 with real `character_id` values and logged `allowed profile update (no _bb_resolved sentinel)`. Regression coverage in `tests/bot_profiles_spec.lua`. Closed. |
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

*Theme: small, high-ROI polish. Trivial wins and one teammate-feel feature. `v0.11.0` was released on `2026-04-15`; the remaining live-validation issues are post-release follow-up, not release blockers.*

| # | Issue | Notes |
|---|-------|-------|
| 32 | Mule item pickup | **Closed 2026-04-15.** `mule_pickup.lua` activates the dead vanilla book-carry path by mirroring `inventory_slot_name -> slot_name` and setting `bots_mule_pickup` on the side-mission book pickup templates. Tomes and grimoires each have their own BetterBots toggle (tome defaults on, grimoire defaults off); disabling a toggle also blocks pickup orders and prunes cached references for that type. Stale-unit cleanup runs unconditionally regardless of toggle state (fix on 2026-04-14 after review found the gate was silently skipping stale cleanup when grimoires were enabled). On 2026-04-15 BetterBots also added a post-vanilla mule-assignment override so nearby humans no longer suppress default book pickup. The same day, `console-2026-04-15-18.01.55...` added the authoritative runtime proof: `mule pickup success: tome (bot=4)` followed by stale-ref cleanup. Explicit tag -> pickup-order routing remains separate in `#96`. |
| 44 | Human-likeness tuning (Tier A) | **Closed 2026-04-13.** The old checkbox is replaced by split timing/leash profiles: `human_likeness.lua` now resolves `off/fast/medium/slow/custom` timing into BotSettings reaction times plus defensive/opportunistic jitter buckets, while `engagement_leash.lua` reads `off/light/medium/strong/custom` pressure-leash scaling instead of the old fixed half-leash model. `console-2026-04-13-14.10.19` confirmed the runtime reaction-time patch and pressure leash scaling; jitter remains covered by tests but is not separately logged. Grenade/blitz timing, aim tuning, and dodge tuning remain out of scope. |
| 82 | Perf low-hanging fruit audit | **Closed 2026-04-16.** The low-risk audit is complete. Final branch cuts included same-frame `Heuristics.resolve_decision(...)` reuse between `condition_patch.lua` and `ability_queue.lua`, plus BT-side one-shot `AbilityTemplates` fetch + `_MetaData.inject()` so the BT path stops paying that metadata guard on every `can_activate_ability` evaluation. Closure is based on direct live evidence from `console-2026-04-16-15.35.10...`: `resolve_decision cache hit ...` lines prove the new reuse path is active in-game, and the same log contains a mission-end `bb-perf:auto: 104.9 us/bot/frame total` block. That validates the implementation, but not the original `<80 us/bot/frame` target; any deeper perf work moved to follow-up `#99`. |
| 87 | Sustained fire for flamers and held-fire weapons | **Closed 2026-04-13.** `sustained_fire.lua` now observes queued `weapon_action` inputs, arms per-unit sustained state for supported full-auto / stream paths, and injects required raw hold inputs through `BotUnitInput._update_actions` until the path goes stale or clears. Covered: flamer, Purgatus, recon lasguns, autoguns, autopistol, dual autopistols, bolter hipfire, heavy stubbers, and rippergun braced fire. `console-2026-04-13-15.20.37...` captured both the stream-route markers and the hold confirmation lines (`holding sustained fire inputs`) for Purgatus and flamer. Scope remains execution-only; ADS/brace choice still belongs to #41. |
| 89 | Bot grenade pickup heuristic | **Closed 2026-04-15.** `ammo_policy.lua` piggybacks the vanilla `pickup_component.ammo_pickup` slot for nearby `small_grenade` refills whenever every eligible human is above the configured grenade reserve threshold, while cooldown-only blitz users are excluded from grenade-pickup arbitration. `console-2026-04-15-14.44.35...` now contains the missing standalone world-pickup proof: `grenade pickup permitted`, `grenade pickup bound into ammo slot`, then `grenade pickup success: small_grenade (bot=3, charges=0->3/3)` and again `... (bot=3, charges=1->3/3)`. |
| 90 | Melee/ranged target type hysteresis | **Closed 2026-04-16.** `target_type_hysteresis.lua` now runs on the actual live path by post-processing `BotPerceptionExtension._update_target_enemy`, not by patching the dead `bot_target_selection_template.lua` table. `BetterBots.lua` owns the consolidated `bot_perception_extension` hook so hysteresis and poxburster post-processing do not clobber each other. Closure is based on `console-2026-04-16-17.51.56...`: `32` `type flip ...` lines, `46` `type hold ...` lines, `4` `suppressed opposite-type switch ...` lines, and the mission-end perf row `target_type_hysteresis.post_process 143.000 ms total (11473 calls, 12.5 us/call)`. That resolves the earlier proof gap where the BT-side debounce fired but the math-layer hook never showed up in logs. |
| 91 | Bot weakspot aim MVP | Closed 2026-04-13. `ranged_meta_data.lua` injects vanilla-style `aim_at_node = { 'j_head', 'j_spine' }` for lasguns, autoguns, bolters, and stub revolvers when the template leaves `attack_meta_data.aim_at_node` unset. Existing `aim_at_node` values still win, and vanilla `target_breed.override_bot_target_node` behavior is unchanged. Live runtime confirmation now exists via `weakspot aim selected j_head|j_spine ...`. Per-breed weakspot map (Mauler/Crusher/Bulwark) remains deferred to `#92`. |
| 93 | Grenade ballistic arc fix | **Closed 2026-04-13.** `grenade_fallback.lua` now resolves projectile locomotion data from the equipped grenade weapon template and mirrors vanilla `Trajectory.angle_to_hit_moving_target(...)` solving for supported gravity-affected manual-physics projectile families. `console-2026-04-13-14.10.19` confirmed ballistic aim, queued wield, and charge consumption during live throws; closure used that runtime evidence plus manual gameplay confirmation that the remaining short-throw concern was gone. Covered: standard grenades, handleless grenades, Ogryn grenade throws, and zealot throwing knives. Flat fallback remains for `broker_missile`, psyker knives, whistle, smite, chain lightning, and mines. |

### v1.0.0 — "Bot Identity" (final release)

*Theme: bots feel like teammates, not automatons. VT2 Bot Improvements parity. Mechanical polish + talent awareness + consumable-item coordination.*

**Release framing.** `v1.0.0` is scoped as the terminal release. Post-1.0 work may never ship — the milestone therefore includes everything feasible without architectural rewrites, not just the cheapest wins. Broad-scope follow-ups under individual issues are formally documented as scope-exit (see Post-1.0 section).

**Execution order.** Sprints are a logical dependency ordering, not calendar weeks. Foundation primitives (F1 talent context, F2 pocketable pickup) are load-bearing — F2 unlocks three downstream features on its own.

#### Sprint 1 — Foundations + cheap independent wins

| # | Item | Notes |
|---|------|-------|
| F1 | Talent/buff context extension | Additive fields in `build_context()` — `has_talent()`, `current_stacks()`. Prerequisite for `#38`. Pure additive. |
| 13 | Navmesh charge/dash validation | **Implemented 2026-04-18.** Shared `charge_nav_validation.lua` validates the actual launch endpoint with `NavQueries.ray_can_go(...)` before committing `ogryn_charge`, `adamant_charge`, and zealot dash variants. Zealot dash resolves its targeted enemy from bot perception/smart-targeting, rescue charges validate the explicit ally aim point, and directional charges fall back to `navigation_extension:destination()` when no better endpoint exists. Wired into both `BtBotActivateAbilityAction.enter` and `ability_queue.lua`, with rescue aim applied only after validation passes so a blocked charge cannot leave `BotUnitInput` stuck on the ally position. Same-endpoint failures cache for 0.5s so GwNav queries do not repeat every tick, and the behavior is exposed behind `enable_charge_nav_validation` as a user kill switch. |
| 92 | Per-breed weakspot aim override | Hook `BtBotShootAction._set_new_aim_target` atop the `#91` MVP allowlist in `ranged_meta_data.lua:224`, with live `_aim_position` re-evaluation for the two stateful cases. Implemented in code for Scab Mauler (`j_spine`), Bulwark exposed-head routing (`j_head` only when the shield is open or the bot is outside the 70° blocking cone, using the engine's flat block-angle math), and a **provisional** Crusher rear-arc proxy (`j_head` only when the bot is behind the target). The Crusher path is documented assumption, not rig-verified fact: the original back-of-head claim still lacks a confirmed node name in decompiled source. Independent of `#41`. |
| 86 | Tier 3 revive cover — timing investigation | **Done 2026-04-17.** Scope-exit at the `enter` hook confirmed by two independent investigations. `PlayerCharacterStateInteracting.on_enter` interrupts any in-flight ability/weapon action and force-wields `slot_unarmed`, killing Tier 3 sequences on revive entry. Viable-but-substantial architecture (approach-phase hook via `on_refresh_destination` + gated `can_revive`) documented on the issue and moved to Post-1.0. |

#### Sprint 2 — Keystone-aware layer (shipped-roster coverage)

Not a Zealot-Martyrdom one-liner. BB ships three tuned builds in `bot_profiles.lua`; each needs heuristic touchpoints.

| Build | Talent marker | Touchpoint |
|---|---|---|
| Zealot Martyrdom | `zealot_martyrdom` | Live healing suppression on stations/med-crates + `zealot_invisibility` low-HP panic disable; pocketable wound-cure path stays deferred with F2 |
| Psyker Warp Siphon / glass cannon | `psyker_damage_based_on_warp_charge` + `psyker_warp_glass_cannon` | Raise peril vent threshold to preserve warp-charge-scaled damage |
| Psyker Venting Shriek cadence | `psyker_shout_vent_warp_charge` | Shout as vent-trigger; cooldown shape differs from burst-damage shout |
| Veteran VoC + Focus Target | existing stance path | Verify tag ownership, then narrow ping override so Focus Target can still claim already-tagged priority targets |

Keystone extensions beyond shipped roster (Scrier's Gaze vent suppression, Broker Chemical Dependency / Adrenaline Junkie, Ogryn Carapace Armor) remain post-1.0.

| # | Issue | Notes |
|---|-------|-------|
| 38 | Talent-aware behavior | **Code-complete 2026-04-18; in-game validation pending.** Shipped-roster coverage per table above, implemented as a narrow MVP: Martyrdom keeps live healing seams blocked and disables Shroudfield's low-HP-only panic, Psyker shout preserves more peril when warp-charge damage talents are present and vents later with `psyker_shout_vent_warp_charge`, Veteran Focus Target can override an existing tag once to claim `enemy_over_here_veteran`. Detection via `talent_extension:talents()` + `buff_extension:current_stacks()`. Graceful degrade when talent missing (non-BB profiles). |

#### Sprint 3 — Close-range ranged gap + melee identity

| # | Issue | Notes |
|---|-------|-------|
| 41 (narrow) | Weapon-family close-range classifier | **Code-complete 2026-04-18; in-game validation pending.** Narrow family policy landed in `ranged_meta_data.lua`, then wired into both `target_type_hysteresis.lua` and the vanilla `BtBotShootAction._should_aim` hook. Supported close-range families: flamer, Purgatus (`forcestaff_p2_m1`), shotgun, heavy stubber. Under close pressure those families keep ranged target type instead of falling back to melee, and suppress ADS inside the configured hipfire window. Broad enemy-aware fire cadence stays post-1.0. |
| 33 (narrow) | Activate_special melee | **Code-complete 2026-04-18; in-game validation pending.** `melee_attack_choice.lua` now caches supported weapon-special metadata during `BtBotMeleeAction.enter` and prepends `special_action` before the chosen attack when a powered melee family (`forcesword_`, `powersword_`, `thunderhammer_`) is engaging an elite or specialist and the special is not already active. Ranged specials + `toggle_special` chainaxe energy mgmt stay post-1.0. |

#### Sprint 4 — Pocketable pickup primitive + consumable features

F2 is the real infrastructure bet. One primitive unlocks three downstream features. Per `#24` Mar 8 audit + `#88` body, the shared blocker is a missing BT primitive for pocketable item pickup.

| # | Item | Notes |
|---|------|-------|
| F2 | Pocketable pickup primitive | New module `pocketable_pickup.lua`: BT walk-to-unit + interact + pocket-slot insert. No existing path in bot BT. Load-bearing. |
| 24 (a) | Medicae discipline | Extend `healing_deferral.lua:182` plumbing: corruption-only gate + charge reserve + 80%+ skip. Existing hooks. |
| 24 (b) | Stim usage | Rides F2; trigger = high-threat combat entry. |
| 24 (c) | Med-kit carry + distribute | Rides F2; give-to-ally on ping or <40% threshold. |
| 88 | Deployable crate carry + deploy | Rides F2 for ammo + medical pocketable forms. Existing mule-pickup plumbing (`mule_pickup.lua:64`, `bot_group.lua:1064`, `bt_bot_conditions.lua:287`) carries the carry side. Deploy-location heuristic (coherency anchor + ≥2 allies + resource need + no 15m enemies) is the real design cost. |

#### Sprint 5 — Team coordination + safety

| # | Issue | Notes |
|---|-------|-------|
| 56 | Communication wheel response | React to com wheel commands (battle cry → aggression, need help → converge). `Vo.on_demand_vo_event` hook. ForTheEmperor compat. |
| 96 | Smart-tag item interaction bridge | Route explicit non-enemy smart-tag interactions into bot pickup/drop orders. Sits atop `#24` + `#88` pickup paths — queue after those ship. |
| 97 | Non-book resource arbitration | Unify reserve logic across ammo, grenade refills, medicae, med-crates. Excludes books + still-dead pocketable health paths. Behavior-policy unification, not a hotfix. |
| 101 | Weapon-slot wield timeout on BB-locked swap | Grenade/item fallbacks wait out full 2 s timeout + 2 s retry when `weapon_action.bot_queue_action_input` rejects the wield. Expose lock state; short-circuit with `reason = 'slot_locked'`. Fits coordination-polish neighborhood; not load-bearing. |

#### Sprint 6 — Validation, hardening, release

| # | Issue | Notes |
|---|-------|-------|
| 98 | Sparse metadata hardening | Targeted boundary guards in engine-facing consumers — follow-up to three v0.11.x melee crash fixes (`299eaac`, `ebcb71c`, `15fdd65`). No blanket `pcall`, no broad refactor. |
| 102 | ActionInputParser zoom/unzoom noise | Same family as `#98`: `ranged_meta_data.lua:15` falls back to `"zoom"` when the weapon uses `action_brace` (plasmagun) or has no aim action (flamer, melee). 0–195 engine INFO lines/run. Log hygiene only, not user-visible. |
| 99 | Perf benchmark protocol | Reusable perf harness — acceptance target definition first, then medium-risk hotspot work (`ability_queue.decision`, `grenade_fallback`, `sprint.update_movement`, `ammo_policy.update_ammo`). Current-branch mission-end sample: `104.9 us/bot/frame`. |
| 85 | Combat ability identity refactor | Tech debt, user-invisible — separate `template_name` from `ability_name` semantics. Ship if runway permits; drop first if tight. |
| — | Full cold-boot soak | Both mod load orders, grep DMF warnings in raw console, Auric mission runs. |
| — | Nexus package + changelog + outreach | Release mechanics. |

#### Tier-cut priority if runway tight

Hard cut order (first to drop):

1. `#85` (refactor, user-invisible)
2. `#56` (comm wheel — ForTheEmperor users only)
3. `#96` + `#97` (coordination polish)
4. `#41-narrow` (document Purgatus gap as known issue in Nexus description)
5. `#88` deploy-location heuristic (ship carry without deploy auto-trigger — player ping only)

**Do not cut:** F2 primitive + its three downstream consumable features (`#24a/b/c`, `#88` carry), `#33-narrow` melee identity, `#38` keystone layer, `#13` + `#92` mechanical polish. These are load-bearing for "v1.0.0 was worth shipping."

### Post-1.0 — "Intelligence Architecture" (may never ship)

*Theme: architectural upgrades and research-track items. If post-1.0 happens, each is a mini-project.*

| # | Issue | Notes |
|---|-------|-------|
| 22 | Utility-based ability scoring | Replace boolean heuristics with spline-interpolated utility curves. Darktide has native `utility.lua` + `bot_utility_considerations.lua` — framework exists, needs wiring. Architectural upgrade. |
| 28 | Built-in bot profile management | Absorb Tertium4Or5 functionality. Profile selection + loadout preset support. Only pursue if upstream remains unpatched. |
| 80 | Grenade/blitz tactical evaluator | Shared grenade/blitz decision object, family-specific targeting/placement, Arbites dog vs `Lone Wolf` split, and execution-time revalidation tied to original tactical intent. Planning docs: `docs/superpowers/specs/2026-04-08-grenade-blitz-tactical-evaluator-design.md`, `docs/superpowers/plans/2026-04-08-grenade-blitz-tactical-evaluator.md`. References `#49` and is intentionally narrower than `#22`. |
| 84 | User-authored bot profiles | Integration with hadrons-blessing for user-defined bot builds. Design-heavy, no concrete scope yet. |
| 86 | Tier 3 revive cover | Moved 2026-04-17 after Sprint 1 timing investigation confirmed `BtBotInteractAction.enter` is unusable (engine interrupt on interacting state entry). Viable architecture: approach-phase hook in `revive_ability.on_refresh_destination` + gate `bt_bot_conditions.can_revive` while item sequence mid-flight. Ships instant-variant shield + drone; relic stays excluded (5.6s unwield + slot lock). Full plan on the issue. |

**Broad-scope cuts (scope-exit, captured under parent issues):**

- Broad `#24`: complex healing-item ping negotiation beyond F2 primitive + medicae + basic distribution
- Broad `#33`: ranged weapon specials (bayonet, pistol-whip, racking slide), `toggle_special` chainaxe energy management
- Broad `#41`: full enemy-aware fire cadence, dynamic gestalt per target type
- Broad `#92`: replace the provisional Crusher rear-arc proxy with a rig-verified node or stronger live evidence
- Keystone extensions beyond shipped roster: Scrier's Gaze vent suppression, Broker Chemical Dependency / Adrenaline Junkie, Ogryn Carapace Armor stack mgmt

### Validation-gated — slot into any batch when testable

| # | Issue | Blocker |
|---|-------|---------|
| 8 | Hive Scum ability support | DLC-blocked (Hive Scum / `broker` archetype not owned) |
| 17 | Daemonhost avoidance | Code + tests shipped v0.6.0, but still validation-gated. First real DH spawn on 2026-04-11 exposed a grenade/blitz-path gap; heuristic carve-out staged in `03ce4fd`+`ffe7c6b`. A later 2026-04-15 log still showed bad pre-aggro behavior because BetterBots was only consulting `aggro_state`; the current branch now uses daemonhost `stage` when available and treats any non-aggroed stage as dormant across combat, ping, companion-tag, and player-tag-boost paths. Re-validation on next DH spawn. |

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
