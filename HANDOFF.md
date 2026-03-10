# Handoff

## Current Task
Starting M5 development: scope expansion features beginning with #4 (grenade/blitz support). Working on `dev/m5-batch1` branch.

## Agent
Claude Opus 4.6

## Branch
`dev/m5-batch1` (to be created from `main` at `fea78b4`)

## What shipped since last handoff
- v0.5.0 released: #42 VFX/SFX bleed, #23 melee meta_data, #31 ranged meta_data, #30 warp venting, #43 partial staff charged fire
- Major refactor: extracted 5 modules from BetterBots.lua (1455 -> 625 LOC)
- Design doc for #45 (default bot profiles)

## Current state
- `main` is clean at `fea78b4`
- 230 passing unit tests, `make check` green
- All M4 features merged and validated

## M5 scope (planned)
- **#4**: Grenade/blitz support (Phase 1: `adamant_whistle` template path; Phase 2: item-based grenades)
- **#16-#19**: General bot behavior (pinging, daemonhost, boss discipline, special chasing)
- **#39**: Heal deferral

## #4 status
- Issue has full inventory (19 templates), investigation checklist, and two-phase approach
- #3 (Tier 3 reliability) is closed — Phase 2 unblocked
- `adamant_whistle` is the only blitz with `ability_template` — lowest-hanging fruit
- All other blitz abilities are item-based (same Tier 3 mechanism as force field/drone)

## Key Files
- `docs/classes/grenade-inventory.md` — all 19 grenade/blitz templates
- `docs/bot/input-system.md` — input architecture for item-based abilities
- `scripts/mods/BetterBots/item_fallback.lua` — Tier 3 item wield/use/unwield state machine
- `scripts/mods/BetterBots/heuristics.lua` — per-template heuristic functions

## Open Questions
- Does `can_activate_ability` hook already pass `grenade_ability` type through?
- Does `adamant_whistle` work via template path with zero changes?
- What `ability_meta_data` does the BT grenade node expect?
- Can Psyker wielded-blitz (Smite/Chain Lightning/Assail) be queued via `bot_queue_action_input`?

## Log
| When | Agent | Summary |
|------|-------|---------|
| 2026-03-04 – 2026-03-09 | GPT-5 + Claude Opus 4.6 | v0.1.0 – v0.5.0 shipped (see `docs/dev/roadmap.md` for details) |
| 2026-03-10 | Claude Opus 4.6 | Updated handoff, starting M5/#4 planning |
