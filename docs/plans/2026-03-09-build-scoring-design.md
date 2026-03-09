# Build Scoring System — Design Doc

Date: 2026-03-09
Status: Approved
Mod version baseline: v0.4.0

## Goal

Build a rating methodology and tooling to evaluate Darktide loadouts (talents, weapons, perks, blessings, curios) across 7 dimensions. First use: audit the 20 curated GL builds in `docs/classes/meta-builds-research.md`.

## Deliverables

### 1. Scoring Rubric (`docs/knowledge/build-scoring-rubric.md`)

7 dimensions, each scored 1–5, total /35:

| Dimension | Type | 1 | 3 | 5 |
|-----------|------|---|---|---|
| Perk Optimality | Mechanical | Wrong stat or T1-T2 | Right stats, T3 | T4 perks matching weapon role |
| Blessing Synergy | Qualitative | Blessings contradict or weak-tier | Decent combo, not optimal | Best-in-slot combo for archetype |
| Talent Coherence | Qualitative | Scattered points, no archetype | Recognizable archetype, 2-3 wasted points | Tight 30-point build, every node serves gameplan |
| Breakpoint Relevance | Mechanical | Perks/blessings miss key thresholds | Hits some breakpoints | Hits the breakpoints that matter (Crusher/Mauler/special oneshots) |
| Curio Efficiency | Mechanical | Random perks, no DR stacking | Standard toughness/health, generic DR | Optimized for class weakness |
| Role Coverage | Qualitative | One-dimensional | Covers 2/3 roles (horde, elite, sustain) | Full: horde + elite + sustain + team utility |
| Difficulty Scaling | Qualitative | Falls apart above Havoc 20 | Viable Havoc 30, struggles at 40 | Proven Havoc 40, handles all modifiers |

Letter grades:
- S: 32-35
- A: 27-31
- B: 22-26
- C: 17-21
- D: <17

Includes per-class notes (e.g. Zealot values sustain more because melee-forward) and scorecard template.

### 2. JSON Data File (`scripts/build-scoring-data.json`)

Structured lookup tables extracted from knowledge base:

- **Perk catalog**: stat name → T1-T4 values, melee vs ranged availability (from `perks-curios.md`)
- **Blessing catalog**: weapon → valid blessings + tier values (from `weapon-blessings.md`)
- **Enemy HP breakpoints**: key enemies × difficulty tiers (from `enemy-stats.md`)
- **Curio perk ratings**: per-class tier list of optimal curio perks
- **Weapon role tags**: horde-clear / elite-killer / hybrid / support per weapon archetype

### 3. Scoring Script (`scripts/score-build.mjs`)

Consumes JSON output from `extract-build.mjs` (or hand-written build JSON).

**Mechanical checks (automated):**
- Perk validation: do perks exist for this weapon type? what tier? match weapon role?
- Blessing validation: do these blessings exist for this weapon? what tier?
- Curio check: are curio perks class-optimal?
- Breakpoint check: simplified threshold comparison (weapon base damage + perk modifiers vs enemy HP). NOT the full 13-stage damage pipeline.

**Output:** scorecard JSON with mechanical scores for dimensions 1, 4, 5 + raw data for qualitative scoring (dimensions 2, 3, 6, 7) applied in conversation.

**Does NOT automate:** talent coherence, blessing synergy, role coverage, difficulty scaling — these require judgment.

## Bot-Awareness Flags

Appended to each scorecard. Track where build assumptions break for bots.

| Flag | Trigger |
|------|---------|
| `BOT:NO_DODGE` | Build relies on dodge for damage/survival (Quickness, dodge-crit) |
| `BOT:NO_WEAKSPOT` | Build relies on weakspot hits (Sniper's Focus, weakspot-kill regen) |
| `BOT:NO_PERIL_MGT` | Build requires manual peril management (overcharge stance, glass cannon) |
| `BOT:NO_POSITIONING` | Build requires deliberate positioning (backstab, flanking, cover) |
| `BOT:NO_BLOCK_TIMING` | Build relies on perfect blocks (Arbites perfect-block synergies) |
| `BOT:AIM_DEPENDENT` | Build effectiveness scales with aim precision (Helbore, plasma sniping) |
| `BOT:ABILITY_OK` | BetterBots can trigger the ability correctly |
| `BOT:ABILITY_MISSING` | BetterBots can't trigger this (blitz, weapon special, parry) |

Flag set tracks BetterBots capabilities as of v0.4.0. Update when new features ship.

## Data Flow

```
extract-build.mjs (scrape GL)
        ↓
    build.json (or hand-written)
        ↓
score-build.mjs + build-scoring-data.json
        ↓
    scorecard.json (mechanical scores + raw data)
        ↓
    manual review (qualitative scores + bot flags)
        ↓
    annotated build rating
```

## Breakpoint Strategy

Simplified threshold checks using our source data, not the full 13-stage damage pipeline:
- Enemy HP from `enemy-stats.md` (per difficulty)
- Weapon base damage from weapon templates
- Perk multipliers from `perks-curios.md`
- Compare: does (base × perk modifier) exceed HP threshold for key enemies?

This is approximate but sufficient for scoring "is this perk choice good?" For precise breakpoint math, the community tool at [dt.wartide.net](https://dt.wartide.net/calc/) exists (open-source Wasm engine: [manshanko/dtmath-wit](https://github.com/manshanko/dtmath-wit), MIT, could integrate later).

## Out of Scope

- Full damage pipeline reimplementation
- Talent tree graph parser
- Auto-scrape + auto-score pipeline
- Bot-optimal loadout generation (later project, uses this as input)
- Web UI / community-facing tool

## Dependencies

- `scripts/extract-build.mjs` — existing GL scraper, outputs build JSON
- `docs/knowledge/` — complete knowledge base (perks, blessings, buffs, enemies)
- Node.js — no additional npm packages needed (pure JSON lookups)
