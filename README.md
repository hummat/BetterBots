# BetterBots

[![CI](https://github.com/hummat/BetterBots/actions/workflows/ci.yml/badge.svg)](https://github.com/hummat/BetterBots/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![Nexus Mods](https://img.shields.io/badge/Nexus-BetterBots-orange)](https://www.nexusmods.com/warhammer40kdarktide/mods/745)

A [Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework) mod that enables bot combat abilities in Solo Play. Aims to bring VT2-level bot ability usage to Darktide.

Darktide has a complete bot ability system built into the behavior tree, but Fatshark hardcoded a whitelist that only allows two abilities. This mod removes that gate and injects missing metadata so the existing infrastructure handles the rest.

> **Solo Play only.** Darktide uses dedicated servers — mods cannot affect gameplay on Fatshark's servers. This mod only works when you host locally via the [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176) mod. It does **not** work in public matchmaking or any other online mode.

## Highlights

- Bot-optimized class profiles with curated builds (weapons, talents, blessings, perks)
- Pre-revive defensive abilities: bots pop dash / shout / stealth before reviving downed allies
- Objective-aware activation: bots protect allies interacting with pickups, scriptures, grimoires
- Team ability cooldown staggering to prevent simultaneous activations
- Ammo awareness: bots defer ammo pickups when humans are low
- Engagement leash: bots stay in combat longer using coherency-based ranges
- Healing deferral: bots let humans heal first at health stations and med-crates
- Mule pickup: bots carry scriptures/tomes; grimoires are opt-in
- Arbites Cyber-Mastiff smart-tag steers the dog onto priority targets
- Sustained fire support for flamer, Purgatus, recon/autogun, bolter, autopistol, heavy stubber, and rippergun braced fire paths
- Human-likeness timing and pressure-leash profiles (auto-scale with difficulty by default)
- 4 aggression presets (testing / aggressive / balanced / conservative)
- Slider controls for sprint distance, special chase penalty, player tag response, melee horde bias
- Smart targeting, daemonhost avoidance, and poxburster safety toggles
- Comprehensive busted test suite

## What bots can do with this mod

**Stance abilities:**
- Veteran: Executioner's Stance / Voice of Command
- Psyker: Scrier's Gaze
- Ogryn: Point-Blank Barrage
- Arbites: Castigator's Stance
- Hive Scum: Enhanced Desperado / Rampage (DLC-blocked for validation)

**Dash / shout / stealth abilities:**
- Veteran: Infiltrate (stealth)
- Zealot: Fury of the Faithful (dash), Shroudfield (stealth)
- Ogryn: Bull Rush (charge), Loyal Protector (taunt)
- Psyker: Venting Shriek (shout)
- Arbites: Break the Line (charge), Arbites Shout

**Item-based abilities:**
- Zealot: Bolstering Prayer (relic) — activates when allies need toughness
- Psyker: Telekine Shield (all 3 variants) — deploys under sustained fire
- Arbites: Nuncio-Aquila (drone) — launches when allies are hurt and enemies nearby

**Grenade / blitz support:**
- Standard grenades: frag, krak, smoke, fire, shock, cluster, friend rock, flash, tox
- Zealot: Throwing Knives
- Arbites: Remote Detonation (whistle), Shock Mine
- Psyker: Assail, Smite, Chain Lightning
- Hive Scum: Missile Launcher (DLC-blocked for validation)

**Smart trigger conditions:**
Bots use 18 per-ability heuristic functions split across class-specific modules plus dedicated grenade/blitz evaluators — based on enemy count, threat level, health/toughness, distance, ally state, and more. Each ability has specific activate/block conditions tuned per preset.

**Bot combat behavior:**
- Sprint to catch up, rescue allies, and traverse
- Daemonhost avoidance (combat + sprint suppression near dormant DH)
- Elite/special pinging with LOS checks and tag hold logic
- Arbites companion (dog) targeting via smart tags
- Boss engagement self-defense exception
- Poxburster safe targeting (close-range fire suppression)
- Distant special melee chase penalty (prefer ranged)
- Target-type hysteresis (reduces melee/ranged swap thrash on close scores)
- Melee attack selection (lights into hordes, heavies into armor)
- Smart blitz targeting from bot perception
- Pre-revive defensive ability activation
- Team ability cooldown staggering
- Coherency-anchored engagement leash

**Bot profiles and equipment:**
- Per-slot class selection (veteran, zealot, psyker, ogryn)
- Curated weapon/talent/blessing/perk builds per class
- Weapon quality scaling (auto scales with difficulty, or manual override)
- ADS fix for Tertium 5/6 bots
- Warp charge venting for Psyker staves
- VFX/SFX bleed suppression

**In-game settings:**
- Aggression preset: testing / aggressive / balanced / conservative
- Ability category toggles: stances, charges, shouts, stealth, deployables, grenades
- Sprint catch-up distance (slider, 0 = disable)
- Special chase penalty range (slider, 0 = disable)
- Player tag response strength (slider, 0 = ignore pings)
- Melee horde light bias (slider, 0 = vanilla attack selection)
- Smart blitz targeting toggle
- Daemonhost avoidance toggle
- Poxburster safe targeting toggle
- Bot ranged ammo threshold and human ammo reserve threshold
- Human-likeness timing and pressure-leash profiles (auto / manual / custom)
- Healing deferral mode + thresholds
- Bot grimoire pickup toggle
- Bot profiles: class per slot, weapon quality
- Diagnostics: info/debug/trace log levels, JSONL event log, `/bb_perf` timing

## Roadmap

See the [full roadmap](docs/dev/roadmap.md) for details and GitHub issue links.

**Ability activation**
- [x] Stance, dash, charge, shout, stealth abilities (all 6 classes)
- [x] Item-based abilities (relic, force field, drone)
- [x] Smart per-ability trigger heuristics (18 functions)
- [x] Safety guards (revive protection, suppression, warp peril block)
- [x] Grenade / blitz support (all templates)
- [x] Settings surface (presets, category toggles, per-feature sliders)
- [x] Pre-revive defensive ability activation
- [x] Team ability cooldown staggering
- [ ] Hive Scum validation (DLC-blocked)

**Bot combat behavior**
- [x] Charge/dash to rescue disabled allies
- [x] Bot sprinting (configurable distance)
- [x] Daemonhost avoidance (togglable)
- [x] Bot pinging of elites/specials
- [x] Arbites companion (dog) targeting
- [x] Boss engagement discipline
- [x] Poxburster targeting
- [x] Distant special chase penalty (configurable range)
- [x] Coherency-anchored engagement leash
- [x] Human-likeness timing and pressure-leash profiles
- [x] Target-type hysteresis (reduces melee/ranged swap thrash)
- [x] Smart blitz targeting (togglable)
- [x] Objective-aware activation (protect interacting allies)
- [x] Pre-revive defensive ability activation
- [x] Arbites companion-command smart tag
- [ ] Weapon/enemy-aware ADS vs hip-fire

**Bot equipment and profiles**
- [x] Bot-optimized class profiles with curated builds
- [x] ADS fix for Tertium 5/6 bots
- [x] Ranged weapon fixes (plasma gun, staves)
- [x] Bot warp charge venting
- [x] Sustained fire support for held-fire ranged paths
- [x] VFX/SFX bleed suppression
- [x] Smart melee attack selection (armor-aware, configurable bias)
- [x] Weakspot aim MVP for finesse firearms
- [x] Ballistic aim for manual-physics grenade families
- [x] Ammo awareness (bot + human thresholds)
- [x] Grenade refill pickup heuristic
- [x] Healing deferral
- [x] Mule scripture/tome pickup (grimoires opt-in)

**Planned for v1.0.0 (final release)**
- [ ] Navmesh validation for charge/dash abilities
- [ ] Per-breed weakspot aim map (Mauler, Crusher, Bulwark)
- [ ] Talent-aware bot behavior (Zealot Martyrdom, Psyker Warp Siphon, Venting Shriek, Veteran VoC)
- [ ] Close-range weapon-family classifier (Purgatus, flamer, shotgun, stubber)
- [ ] Melee activated specials (power sword, thunder hammer, force sword)
- [ ] Pocketable pickup primitive + medicae/stim/med-kit discipline
- [ ] Deployable crate carry and deploy (ammo + medical)
- [ ] Tier 3 revive cover (Telekine Shield, Relic, Nuncio-Aquila drone)
- [ ] Communication wheel response (ForTheEmperor compat)
- [ ] Smart-tag item interaction bridge
- [ ] Unified non-book resource arbitration

**Post-1.0 (may never ship)**
- Utility-based ability scoring (architectural)
- Built-in bot profile management (Tertium4Or5 replacement)
- Grenade/blitz tactical evaluator
- User-authored bot profiles

See [Status Snapshot](docs/dev/status.md) and [Validation Tracker](docs/dev/validation-tracker.md) for detailed evidence.

## Requirements

- [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)
- [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)
- [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176)
- [Tertium 5](https://www.nexusmods.com/warhammer40kdarktide/mods/183) or [Tertium 6](https://www.nexusmods.com/warhammer40kdarktide/mods/725) (recommended — for non-veteran bot classes)

## Install

**From Nexus (recommended):**
1. Extract `BetterBots.zip` into your Darktide `mods/` folder.
2. Add `BetterBots` in `mods/mod_load_order.txt` below `dmf`.
3. Re-patch mods with `toggle_darktide_mods.bat` (Windows) or `handle_darktide_mods.sh` (Linux).

**From source:**
1. Clone or copy this repo into your Darktide `mods/` directory as `mods/BetterBots`.
2. Add `BetterBots` in `mods/mod_load_order.txt` below `dmf`.
3. Re-patch mods.

Mods are disabled after each game update, so re-patching is required again.

## Quick verification

1. Launch Solo Play.
2. Start a mission (`/solo`).
3. Confirm in game chat:
   - `BetterBots loaded`
   - `BetterBots: injected meta_data for ...` (one line per injected template)

## Companion mod compatibility

BetterBots works standalone (vanilla bots are all veterans), but bot class diversity requires a Tertium mod.

**Tertium 5** — the original. Some versions crash when encountering Arbites/Hive Scum archetypes it doesn't recognize.

**Tertium 6 (temporary)** — a fork by KristopherPrime that supports all 6 classes and player + 5 bots. If Tertium 5's crash affects you, try Tertium 6 instead.

Both are optional/recommended, not hard-required.

## Developer tooling

This repo is configured for local Lua lint/format/type diagnostics:

- `luacheck` via `.luacheckrc`
- `stylua` via `.stylua.toml`
- `lua-language-server` diagnostics via `.luarc.json`
- a repo-local `bin/luacheck` compatibility wrapper for the known Lua 5.5 mismatch

The repo does not modify your shell `PATH`. Use `make tool-info` to see the
exact tool paths and fallbacks the Make targets will use on this machine.

Commands:

| Target | Description |
|--------|-------------|
| `make deps` | Install git hooks (conventional commits) |
| `make lint` | Run luacheck |
| `make format` | Format with StyLua |
| `make format-check` | Check formatting (dry run) |
| `make lsp-check` | Run lua-language-server diagnostics |
| `make patch-check` | Verify decompiled Darktide engine anchors against the current local checkout |
| `make patch-check-refresh` | `git pull --ff-only` the decompiled Darktide checkout, then verify engine anchors |
| `make check` | Auto-format, then run lint + lsp + tests + doc checks |
| `make check-ci` | Non-mutating CI gate: format-check + lint + lsp + tests + doc checks |
| `make test` | Run busted tests |
| `make tool-info` | Show which tool binaries and fallbacks will run |
| `make package` | Build Nexus-ready `BetterBots.zip` |
| `make release VERSION=X.Y.Z` | Patch-check-refresh + check + package + tag + push + upload ZIP |

After cloning, run `make deps` to install the commit-msg hook.

`make lint` always uses the repo's `bin/luacheck` wrapper. `make test` tries, in
order: `busted`, `lua-busted`, then Arch's `/usr/lib/luarocks/.../busted`
runner.

CI runs `make check-ci` on every push to `main` and on pull requests.
Patch-day validation is separate on purpose: run `make patch-check-refresh` after updating `../Darktide-Source-Code`.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for development setup, code style, and PR process.

## Docs

- [Architecture](docs/dev/architecture.md)
- [Status Snapshot](docs/dev/status.md)
- [Known Issues and Risks](docs/dev/known-issues.md)
- [Debugging and Testing](docs/dev/debugging.md)
- [Logging and Diagnostics](docs/dev/logging.md)
- [Manual Test Plan](docs/dev/test-plan.md)
- [Roadmap](docs/dev/roadmap.md)
- [Validation Tracker](docs/dev/validation-tracker.md)
- [Related Mods](docs/related-mods.md)
- [Meta Builds Research](docs/classes/meta-builds-research.md)

### Bot system internals (from decompiled source)

- [Behavior Tree](docs/bot/behavior-tree.md) — full node hierarchy and conditions
- [Combat Actions](docs/bot/combat-actions.md) — melee, shoot, ability activation
- [Perception and Targeting](docs/bot/perception-targeting.md) — scoring, gestalt weights
- [Navigation](docs/bot/navigation.md) — pathfinding, follow, teleport, formation
- [Input System](docs/bot/input-system.md) — input routing, ActionInputParser
- [Profiles and Spawning](docs/bot/profiles-spawning.md) — loadouts, weapon templates

### Class ability references

Per-class docs with internal template names, input actions, cooldowns, talent interactions, and bot implementation notes.
Each class also has a tactics doc with community-sourced heuristics for when/how to use each ability:

- [Veteran](docs/classes/veteran.md) | [Tactics](docs/classes/veteran-tactics.md)
- [Zealot](docs/classes/zealot.md) | [Tactics](docs/classes/zealot-tactics.md)
- [Psyker](docs/classes/psyker.md) | [Tactics](docs/classes/psyker-tactics.md)
- [Ogryn](docs/classes/ogryn.md) | [Tactics](docs/classes/ogryn-tactics.md)
- [Arbites](docs/classes/arbites.md) (DLC) | [Tactics](docs/classes/arbites-tactics.md)
- [Hive Scum](docs/classes/hive-scum.md) (DLC) | [Tactics](docs/classes/hive-scum-tactics.md)

## Repository layout

```text
BetterBots.mod                    # DMF entry point
bb-log                            # Log analysis CLI
scripts/mods/BetterBots/          # Mod source
  BetterBots.lua                  #   Orchestrator: init, module wiring, BT hooks
  condition_patch.lua             #   BT condition evaluation + vent hysteresis + DH suppression
  ability_queue.lua               #   Fallback combat ability activation (Tier 1/2)
  charge_tracker.lua              #   use_ability_charge dispatch: consumed events, team cooldown, fallback completion
  combat_ability_identity.lua     #   Semantic ability identity (shout vs stance, etc.)
  heuristics.lua                  #   Thin public API + dispatcher for split heuristic modules
  heuristics_context.lua          #   Shared context builder + target/breed helper functions
  heuristics_veteran.lua          #   Veteran ability heuristics
  heuristics_zealot.lua           #   Zealot ability heuristics
  heuristics_psyker.lua           #   Psyker ability heuristics
  heuristics_ogryn.lua            #   Ogryn ability heuristics
  heuristics_arbites.lua          #   Arbites ability heuristics
  heuristics_hive_scum.lua        #   Hive Scum ability heuristics
  heuristics_grenade.lua          #   Grenade/blitz tactical evaluators
  meta_data.lua                   #   ability_meta_data injection at load time
  gestalt_injector.lua            #   Default bot_gestalts injection for ADS-capable bot profiles
  item_fallback.lua               #   Tier 3 item wield/use/unwield state machine
  grenade_fallback.lua            #   Grenade throw state machine (wield/aim/throw/unwield)
  update_dispatcher.lua           #   BotBehaviorExtension.update dispatcher ordering and gating
  settings.lua                    #   Presets, category/feature gates, slider readers
  bot_profiles.lua                #   Bot-optimized class profiles per slot
  bot_targeting.lua               #   Shared perception target resolver + helpers
  sprint.lua                      #   Bot sprint injection (catch-up, rescue, traversal)
  target_selection.lua            #   Player tag boost, special chase penalty, boss engagement
  target_type_hysteresis.lua      #   Perception-layer melee/ranged type stabilization
  melee_meta_data.lua             #   Armor-aware melee attack_meta_data injection
  melee_attack_choice.lua         #   Melee attack-choice: light bias into unarmored hordes
  ranged_meta_data.lua            #   Per-family ranged attack_meta_data injection
  weapon_action.lua               #   Overheat bridge, vent translation, peril guard, ADS fix
  sustained_fire.lua              #   Held-input bridge for sustained-fire ranged weapons
  ping_system.lua                 #   Bot elite/special pinging
  companion_tag.lua               #   Arbites Cyber-Mastiff companion-command smart tag
  smart_targeting.lua             #   Precision blitz target seeding from perception
  poxburster.lua                  #   Poxburster targeting + close-range suppression
  human_likeness.lua              #   Tier A teammate-feel tuning
  engagement_leash.lua            #   Coherency-anchored melee engagement range
  healing_deferral.lua            #   Defer health stations/med-crates to humans
  ammo_policy.lua                 #   Bot ammo + grenade pickup policy
  mule_pickup.lua                 #   Book mule pickup + grimoire opt-in guard
  team_cooldown.lua               #   Team-level ability cooldown staggering
  revive_ability.lua              #   Pre-revive defensive ability activation
  vfx_suppression.lua             #   Bot VFX/SFX bleed suppression
  animation_guard.lua             #   Animation crash guard for bot-only item paths
  airlock_guard.lua               #   Airlock teleport crash guard
  event_log.lua                   #   Structured JSONL event logging
  debug.lua                       #   Debug commands (/bb_state, /bb_decide, /bb_brain)
  log_levels.lua                  #   Tiered debug log level constants
  perf.lua                        #   Per-hook runtime recorder + /bb_perf
  shared_rules.lua                #   Shared rule tables (daemonhost breeds, rescue charges)
  BetterBots_data.lua             #   Mod options / widget definitions
  BetterBots_localization.lua     #   Display strings
tests/                            # Unit tests (busted)
scripts/hooks/                    # Git hooks (conventional commits)
scripts/release.sh                # Release automation
docs/                             # Architecture, class refs, status, roadmap
.github/
  workflows/                      # CI, release, label sync
  ISSUE_TEMPLATE/                 # Bug report, feature request
  CONTRIBUTING.md                 # Dev setup + guidelines
  PULL_REQUEST_TEMPLATE.md
  labels.yml                      # Issue labels (auto-synced)
  dependabot.yml                  # GH Actions auto-updates
```

## License

[MIT](LICENSE)
