# BetterBots

[![CI](https://github.com/hummat/BetterBots/actions/workflows/ci.yml/badge.svg)](https://github.com/hummat/BetterBots/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![Nexus Mods](https://img.shields.io/badge/Nexus-BetterBots-orange)](https://www.nexusmods.com/warhammer40kdarktide/mods/745)

A [Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework) mod that enables bot combat abilities in Solo Play. Aims to bring VT2-level bot ability usage to Darktide.

Darktide has a complete bot ability system built into the behavior tree, but Fatshark hardcoded a whitelist that only allows two abilities. This mod removes that gate and injects missing metadata so the existing infrastructure handles the rest.

> **Solo Play only.** Darktide uses dedicated servers — mods cannot affect gameplay on Fatshark's servers. This mod only works when you host locally via the [Solo Play](https://www.nexusmods.com/warhammer40kdarktide/mods/176) mod. It does **not** work in public matchmaking or any other online mode.

## v0.7.0 highlights

- Grenade/blitz heuristics are now live, including Psyker Assail, Smite, and Chain Lightning support
- Bots react to player tags, hazards, bosses targeting them, and poxbursters near human players
- New in-game settings surface: `standard/testing` profile, tier toggles, grenade/blitz toggle, healing deferral controls
- Tiered logging and optional JSONL/perf diagnostics for post-run validation

## What bots can do with this mod

**Stance abilities (reliable):**
- Veteran: Executioner's Stance / Voice of Command
- Psyker: Scrier's Gaze
- Ogryn: Point-Blank Barrage
- Arbites: Castigator's Stance
- Hive Scum: Enhanced Desperado / Rampage

**Dash / shout / stealth abilities (reliable):**
- Veteran: Infiltrate (stealth)
- Zealot: Fury of the Faithful (dash), Shroudfield (stealth)
- Ogryn: Bull Rush (charge), Loyal Protector (taunt)
- Psyker: Venting Shriek (shout)
- Arbites: Break the Line (charge)

**Item-based abilities (reliable):**
- Zealot: Bolstering Prayer (relic) — activates when allies need toughness
- Psyker: Telekine Shield (all 3 variants) — deploys under sustained fire
- Arbites: Nuncio-Aquila (drone) — launches when allies are hurt and enemies nearby

**Grenade / blitz support (reliable):**
- Standard grenades: frag, krak, smoke, fire, shock, cluster, friend rock, flash, tox
- Zealot: Throwing Knives
- Arbites: Remote Detonation (whistle), Shock Mine
- Psyker: Assail, Smite, Chain Lightning
- Hive Scum: Missile Launcher (DLC-blocked for validation)

**Smart trigger conditions:**
Bots use per-ability heuristics to decide when to activate — based on enemy count, threat level, health/toughness, distance, and ally state. 15 of 18 trigger functions validated in-game (12 combat + 3 item); 1 N/A (cut content), 2 DLC-blocked.

**In-game settings and diagnostics:**
- `standard` / `testing` behavior profile
- Tier 1 / Tier 2 / Tier 3 / grenade-blitz enable toggles
- Healing deferral mode + thresholds
- `Info / Debug / Trace` log levels
- Optional JSONL event log and `/bb_perf` runtime timing

## Roadmap

See the [full roadmap](docs/dev/roadmap.md) for details and GitHub issue links.

**Ability activation**
- [x] Stance, dash, charge, shout, stealth abilities (all 6 classes)
- [x] Item-based abilities (relic, force field, drone)
- [x] Smart per-ability trigger heuristics
- [x] Safety guards (revive protection, suppression, warp peril block)
- [x] Grenade / blitz support
- [~] Ability settings surface (partial: profile + tier/grenade toggles shipped; full per-ability toggles still open)
- [ ] Hive Scum validation (DLC-blocked)

**Bot combat behavior**
- [x] Charge/dash to rescue disabled allies
- [x] Bot sprinting
- [x] Daemonhost avoidance
- [x] Bot pinging of elites/specials
- [x] Boss engagement discipline
- [x] Poxburster targeting
- [x] Stop chasing distant specials

**Bot weapon/equipment fixes**
- [x] Fix ADS for Tertium 5/6 bots
- [x] Fix ranged weapons (plasma gun etc.) for Tertium 5/6
- [x] Bot warp charge venting
- [x] Suppress bot VFX/SFX bleed to human player
- [x] Smart melee attack selection (armor-aware)
- [x] Tiered logging + event/perf diagnostics
- [ ] Weapon/enemy-aware ADS vs hip-fire

**Long-term**
- [ ] Utility-based ability scoring
- [ ] Healing item management
- [ ] Weapon special actions (parry, bayonet)

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

Commands:

| Target | Description |
|--------|-------------|
| `make deps` | Install git hooks (conventional commits) |
| `make lint` | Run luacheck |
| `make format` | Format with StyLua |
| `make format-check` | Check formatting (dry run) |
| `make lsp-check` | Run lua-language-server diagnostics |
| `make check` | Run all of the above |
| `make test` | Run busted tests (if `tests/` exists) |
| `make package` | Build Nexus-ready `BetterBots.zip` |
| `make release VERSION=X.Y.Z` | Check + package + tag + push + upload ZIP |

After cloning, run `make deps` to install the commit-msg hook.

CI runs `make check` on every push to `main` and on pull requests.

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
scripts/mods/BetterBots/          # Mod source
  BetterBots.lua                  #   Orchestrator: init, module loading, update tick
  condition_patch.lua             #   Ability condition evaluation + vent hysteresis fix
  ability_queue.lua               #   Fallback combat ability activation loop
  weapon_action.lua               #   Weapon hooks: overheat bridge, vent, peril guard, _may_fire
  poxburster.lua                  #   Poxburster targeting + close-range suppression
  vfx_suppression.lua             #   Bot VFX/SFX bleed suppression
  heuristics.lua                  #   18 per-ability trigger functions + context builder
  meta_data.lua                   #   ability_meta_data injection at load time
  item_fallback.lua               #   Tier 3 item wield/use/unwield state machine
  melee_meta_data.lua             #   Armor-aware melee attack_meta_data injection
  ranged_meta_data.lua            #   Per-family ranged attack_meta_data injection
  event_log.lua                   #   Structured JSONL event logging
  debug.lua                       #   Debug commands (/bb_state, /bb_decide, /bb_brain)
  BetterBots_data.lua             #   Mod options / widget definitions
  BetterBots_localization.lua     #   Display strings
tests/                            # Unit tests (busted)
bb-log                            # Log analysis CLI
scripts/extract-build.mjs         # GamesLantern build scraper (Playwright)
scripts/hooks/                    # Git hooks (conventional commits)
scripts/release.sh                # Release automation
docs/                             # Architecture, class refs, status
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
