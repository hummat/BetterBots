# Build Scoring System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a 7-dimension scoring rubric + JSON data + CLI script to rate Darktide loadouts, then audit all 20 curated GL builds.

**Architecture:** JSON lookup tables (`build-scoring-data.json`) extracted from knowledge base docs. CLI script (`score-build.mjs`) consumes build JSON from `extract-build.mjs` and scores 3 mechanical dimensions (perks, curios, breakpoints). Rubric doc covers all 7 dimensions for manual + automated use. Tests via `node:test`.

**Tech Stack:** Node.js ESM (.mjs), `node:test` + `node:assert` (built-in, no deps), JSON data files.

**Design doc:** `docs/plans/2026-03-09-build-scoring-design.md`

---

## Task 1: Create perk catalog in JSON data file

**Files:**
- Create: `scripts/build-scoring-data.json`

**Context:** The `extract-build.mjs` scraper outputs perk strings like `"10-25% Damage (Flak Armoured)"` or `"+1-2 Stamina"`. We need a lookup from display patterns → stat + T1-T4 values. Source: `docs/knowledge/perks-curios.md`.

**Step 1: Create the JSON data file with perk catalog**

The file has three top-level sections for perks: `melee_perks`, `ranged_perks`, `curio_perks`. Each entry maps a display name pattern to its stat key and T1-T4 values.

```json
{
  "melee_perks": {
    "Damage (Unarmoured)": { "stat": "unarmored_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Damage (Flak Armoured)": { "stat": "armored_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Damage (Unyielding)": { "stat": "resistant_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Damage (Maniacs)": { "stat": "berserker_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Damage (Carapace)": { "stat": "super_armor_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Damage (Infested)": { "stat": "disgustingly_resilient_damage", "tiers": [0.10, 0.15, 0.20, 0.25] },
    "Critical Hit Chance": { "stat": "critical_strike_chance", "tiers": [0.02, 0.03, 0.04, 0.05] },
    "Critical Hit Damage": { "stat": "critical_strike_damage", "tiers": [0.04, 0.06, 0.08, 0.10] },
    "Stamina": { "stat": "stamina_modifier", "tiers": [1, 1.25, 1.5, 2] },
    "Weakspot Damage": { "stat": "weakspot_damage", "tiers": [0.04, 0.06, 0.08, 0.10] },
    "Damage": { "stat": "damage", "tiers": [0.01, 0.02, 0.03, 0.04] },
    "Finesse": { "stat": "finesse_modifier_bonus", "tiers": [0.01, 0.02, 0.03, 0.04] },
    "Power Level": { "stat": "power_level_modifier", "tiers": [0.01, 0.02, 0.03, 0.04] },
    "Impact": { "stat": "impact_modifier", "tiers": [0.05, 0.06, 0.07, 0.08] },
    "Block Efficiency": { "stat": "block_cost_multiplier", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "Damage (Elites)": { "stat": "damage_vs_elites", "tiers": [0.04, 0.06, 0.08, 0.10] },
    "Damage (Hordes)": { "stat": "damage_vs_horde", "tiers": [0.04, 0.06, 0.08, 0.10] },
    "Damage (Specialists)": { "stat": "damage_vs_specials", "tiers": [0.04, 0.06, 0.08, 0.10] },
    "Sprint Efficiency": { "stat": "sprinting_cost_multiplier", "tiers": [0.06, 0.09, 0.12, 0.15] }
  },
  "ranged_perks": {
    "...same armor-type damage perks...": "...same values...",
    "Reload Speed": { "stat": "reload_speed", "tiers": [0.05, 0.07, 0.085, 0.10] }
  },
  "curio_perks": {
    "Toughness": { "stat": "toughness", "tiers": [0.02, 0.03, 0.04, 0.05] },
    "Health": { "stat": "health", "tiers": [0.02, 0.03, 0.04, 0.05] },
    "Combat Ability Regen": { "stat": "combat_ability_cooldown", "tiers": [0.01, 0.02, 0.03, 0.04] },
    "Revive Speed": { "stat": "revive_speed", "tiers": [0.06, 0.08, 0.10, 0.12] },
    "Block Efficiency": { "stat": "block_efficiency", "tiers": [0.06, 0.08, 0.10, 0.12] },
    "Stamina Regeneration": { "stat": "stamina_regen", "tiers": [0.06, 0.08, 0.10, 0.12] },
    "Sprint Efficiency": { "stat": "sprint_efficiency", "tiers": [0.06, 0.09, 0.12, 0.15] },
    "Corruption Resistance": { "stat": "corruption_resistance", "tiers": [0.06, 0.09, 0.12, 0.15] },
    "Grimoire Corruption Resist": { "stat": "grimoire_corruption", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Gunners": { "stat": "dr_gunners", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Snipers": { "stat": "dr_snipers", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Flamers": { "stat": "dr_flamers", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Bombers": { "stat": "dr_bombers", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Mutants": { "stat": "dr_mutants", "tiers": [0.05, 0.10, 0.15, 0.20] },
    "DR vs Pox Hounds": { "stat": "dr_hounds", "tiers": [0.05, 0.10, 0.15, 0.20] }
  }
}
```

Fill in the complete `ranged_perks` (same armor-type entries as melee, plus Reload Speed, minus Impact/Block Efficiency/Sprint Efficiency). All values from `docs/knowledge/perks-curios.md`.

**Step 2: Commit**

```bash
git add scripts/build-scoring-data.json
git commit -m "feat(scoring): add perk catalog to build-scoring-data.json"
```

---

## Task 2: Add blessing catalog and weapon metadata to JSON data

**Files:**
- Modify: `scripts/build-scoring-data.json`

**Context:** Source: `docs/knowledge/weapon-blessings.md`. GL scraper outputs blessing display names (e.g. "Rising Heat", "Gets Hot!"). We need weapon_display_name → valid blessings + role tags.

**Step 1: Add `weapons` section**

Map weapon display names to metadata + valid blessings. Only the 18+ weapons covered in `weapon-blessings.md` need full blessing data. Other weapons get a role tag but no blessing validation.

```json
{
  "weapons": {
    "M35 Magnacore Mk II Plasma Gun": {
      "internal": "plasmagun_p1_m1",
      "slot": "ranged",
      "role": "elite-killer",
      "classes": ["veteran"],
      "blessings": {
        "Rising Heat": { "internal": "crit_chance_scaled_on_heat", "t4": "+10% crit / +10% crit dmg" },
        "Gets Hot!": { "internal": "reduced_overheat_on_critical_strike", "t4": "60% less heat on crit" },
        "Blaze Away": { "internal": "power_bonus_on_continuous_fire", "t4": "+8%/stack (5 stacks)" },
        "Charge Crit": { "internal": "charge_level_increases_critical_strike_chance", "t4": "+5%/stack (max 25%)" }
      }
    }
  }
}
```

Populate for all weapons in `weapon-blessings.md`. For weapons NOT in the blessing catalog, add entry with `"blessings": null` (skip blessing validation).

Role tags per weapon:
- `horde-clear`: flamer, inferno staff, surge staff, rumbler, heavy stubber
- `elite-killer`: plasma gun, helbore, bolt pistol, revolver, pickaxe, thunder hammer
- `hybrid`: power sword, force sword, duelling sword, combat blade, shivs, dual stubs
- `support`: voidstrike staff, equinox staff, shock maul & shield

**Step 2: Commit**

```bash
git add scripts/build-scoring-data.json
git commit -m "feat(scoring): add weapon metadata and blessing catalog"
```

---

## Task 3: Add enemy breakpoints and curio ratings to JSON data

**Files:**
- Modify: `scripts/build-scoring-data.json`

**Context:** Source: `docs/knowledge/enemy-stats.md` for HP tables, game knowledge for curio tier lists.

**Step 1: Add `enemies` section**

Key breakpoint targets only (the enemies players actually optimize for):

```json
{
  "enemies": {
    "crusher": { "armor": "super_armor", "hp": { "damnation": 4875, "auric": 6500 } },
    "mauler": { "armor": "armored", "hp": { "damnation": 2775, "auric": 3700 } },
    "bulwark": { "armor": "resistant", "hp": { "damnation": 3600, "auric": 4800 } },
    "reaper": { "armor": "resistant", "hp": { "damnation": 3000, "auric": 4000 } },
    "renegade_berzerker": { "armor": "armored", "hp": { "damnation": 1875, "auric": 2500 } },
    "sniper": { "armor": "unarmored", "hp": { "damnation": 375, "auric": 500 } },
    "pox_hound": { "armor": "disgustingly_resilient", "hp": { "damnation": 1050, "auric": 1400 } },
    "mutant": { "armor": "berserker", "hp": { "damnation": 3000, "auric": 4000 } },
    "plague_ogryn": { "armor": "resistant", "hp": { "damnation": 40000, "auric": 60000 } }
  }
}
```

**Step 2: Add `curio_ratings` section**

Per-class tier list. These are qualitative (based on meta consensus + game knowledge):

```json
{
  "curio_ratings": {
    "_universal_optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"],
    "_universal_good": ["Health", "Combat Ability Regen", "Stamina Regeneration", "Corruption Resistance"],
    "_universal_avoid": ["Experience", "Ordo Dockets", "Curio Drop Chance"],
    "veteran": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Combat Ability Regen"], "good": ["Stamina Regeneration", "Toughness"] },
    "zealot": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"], "good": ["Stamina Regeneration", "Sprint Efficiency"] },
    "psyker": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"], "good": ["Combat Ability Regen", "Corruption Resistance"] },
    "ogryn": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"], "good": ["Health", "Block Efficiency"] },
    "arbites": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"], "good": ["Block Efficiency", "Combat Ability Regen"] },
    "hive scum": { "optimal": ["DR vs Gunners", "DR vs Snipers", "Toughness"], "good": ["Combat Ability Regen", "Stamina Regeneration"] }
  }
}
```

**Step 3: Commit**

```bash
git add scripts/build-scoring-data.json
git commit -m "feat(scoring): add enemy breakpoints and curio ratings"
```

---

## Task 4: Create scoring rubric doc

**Files:**
- Create: `docs/knowledge/build-scoring-rubric.md`

**Step 1: Write the rubric**

Content from the approved design doc (`2026-03-09-build-scoring-design.md`), expanded with:
- Full 1-5 scale descriptions for each dimension
- Per-class notes (what each class values more/less)
- Scorecard template (copy-paste for manual use)
- Bot-awareness flag definitions with talent examples
- Letter grade thresholds

The rubric is ~100-150 lines of markdown. Use the design doc tables verbatim, expand each dimension with 2-3 sentences of context. Add a "Per-Class Weights" section noting e.g.:
- Veteran: Role Coverage matters more (team support class)
- Zealot: Difficulty Scaling matters more (melee-forward = squishy at high Havoc)
- Psyker: Breakpoint Relevance less critical (warp damage bypasses armor)
- Ogryn: Perk Optimality matters more (base stats compensate less at high difficulty)

**Step 2: Commit**

```bash
git add docs/knowledge/build-scoring-rubric.md
git commit -m "docs: add build scoring rubric with 7-dimension rating system"
```

---

## Task 5: Create score-build.mjs — perk scoring

**Files:**
- Create: `scripts/score-build.mjs`
- Create: `scripts/score-build.test.mjs`

**Context:** The script reads a build JSON (output of `extract-build.mjs`) and `build-scoring-data.json`, then scores the mechanical dimensions. Start with perk scoring.

**Step 1: Write failing tests for perk parsing and scoring**

```js
import { describe, it } from "node:test";
import { strict as assert } from "node:assert";
import { parsePerkString, scorePerk, scoreWeaponPerks } from "./score-build.mjs";

describe("parsePerkString", () => {
  it("parses percentage range perk", () => {
    const result = parsePerkString("10-25% Damage (Flak Armoured)");
    assert.deepEqual(result, { min: 0.10, max: 0.25, name: "Damage (Flak Armoured)" });
  });

  it("parses plus-prefixed perk", () => {
    const result = parsePerkString("+1-2 Stamina");
    assert.deepEqual(result, { min: 1, max: 2, name: "Stamina" });
  });

  it("parses single-value perk", () => {
    const result = parsePerkString("+5% Toughness");
    assert.deepEqual(result, { min: 0.05, max: 0.05, name: "Toughness" });
  });
});

describe("scorePerk", () => {
  it("returns tier 4 for max value match", () => {
    const result = scorePerk("Damage (Flak Armoured)", 0.25, "melee");
    assert.equal(result.tier, 4);
  });

  it("returns tier 1 for min value match", () => {
    const result = scorePerk("Damage (Flak Armoured)", 0.10, "melee");
    assert.equal(result.tier, 1);
  });

  it("returns null for unknown perk", () => {
    const result = scorePerk("Nonexistent Perk", 0.10, "melee");
    assert.equal(result, null);
  });
});

describe("scoreWeaponPerks", () => {
  it("scores a weapon with T4 perks as 5/5", () => {
    const weapon = {
      name: "Some Melee Weapon",
      perks: ["20-25% Damage (Flak Armoured)", "8-10% Damage (Elites)"],
    };
    const result = scoreWeaponPerks(weapon, "melee");
    assert.equal(result.score, 5);
    assert.equal(result.perks.length, 2);
    assert.ok(result.perks.every((p) => p.tier === 4));
  });
});
```

**Step 2: Run tests to verify they fail**

```bash
node --test scripts/score-build.test.mjs
```

Expected: FAIL (module not found or functions not exported)

**Step 3: Implement perk parsing and scoring**

In `score-build.mjs`:
- `parsePerkString(str)` — regex to extract min/max values and perk display name from GL scraper output formats
- `scorePerk(name, value, slot)` — look up in data.json, determine tier by matching value to tiers array
- `scoreWeaponPerks(weapon, slot)` — score all perks on a weapon, return 1-5 based on average tier + role match
- Load `build-scoring-data.json` via `JSON.parse(readFileSync(...))`

Scoring logic for Perk Optimality (1-5):
- 5: All perks T4, stats match weapon role
- 4: All T3-T4, stats mostly match
- 3: Mix of T2-T4, or T4 but wrong stat for role
- 2: T1-T2 perks, or mismatched stats
- 1: Missing perks or completely wrong stats

**Step 4: Run tests to verify they pass**

```bash
node --test scripts/score-build.test.mjs
```

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/score-build.mjs scripts/score-build.test.mjs
git commit -m "feat(scoring): add perk parsing and scoring"
```

---

## Task 6: Add blessing and curio scoring

**Files:**
- Modify: `scripts/score-build.mjs`
- Modify: `scripts/score-build.test.mjs`

**Step 1: Write failing tests**

```js
describe("scoreBlessings", () => {
  it("validates known blessing on known weapon", () => {
    const weapon = {
      name: "M35 Magnacore Mk II Plasma Gun",
      blessings: [{ name: "Rising Heat", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, true);
    assert.equal(result.blessings[0].known, true);
  });

  it("flags unknown blessing", () => {
    const weapon = {
      name: "M35 Magnacore Mk II Plasma Gun",
      blessings: [{ name: "Fake Blessing", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.blessings[0].known, false);
  });
});

describe("scoreCurios", () => {
  it("scores optimal curio perks higher", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+15-20% DR vs Gunners", "+4-5% Toughness"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.ok(result.score >= 4);
  });

  it("penalizes XP/docket perks", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+6-10% Experience", "+4-10% Ordo Dockets"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.ok(result.score <= 2);
  });
});
```

**Step 2: Run tests to verify they fail**

```bash
node --test scripts/score-build.test.mjs
```

**Step 3: Implement**

- `scoreBlessings(weapon)` — look up weapon in data.json, check if each blessing name exists in weapon's blessing list. Return `{ valid, blessings: [{ name, known, internal }] }`. Note: this does NOT score synergy (qualitative) — it just validates existence.
- `scoreCurios(curios, className)` — parse each curio perk, check against `curio_ratings[className]`. Score 1-5 based on how many perks are optimal/good/avoid.

Curio scoring logic:
- 5: All perks from class optimal list, T4
- 4: Mix of optimal + good, T3-T4
- 3: Generic good perks, T3+
- 2: Low tier or situational perks
- 1: XP/docket/drop-chance perks

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add scripts/score-build.mjs scripts/score-build.test.mjs
git commit -m "feat(scoring): add blessing validation and curio scoring"
```

---

## Task 7: Add CLI interface and scorecard output

**Files:**
- Modify: `scripts/score-build.mjs`
- Modify: `scripts/score-build.test.mjs`

**Step 1: Write test for full scorecard output**

```js
describe("generateScorecard", () => {
  it("produces scorecard from sample build", () => {
    const build = {
      title: "Test Build",
      class: "veteran",
      weapons: [
        { name: "M35 Magnacore Mk II Plasma Gun", perks: ["20-25% Damage (Unyielding)", "8-10% Damage (Elites)"], blessings: [{ name: "Rising Heat" }, { name: "Gets Hot!" }] },
        { name: "Lawbringer Mk IIb Power Falchion", perks: ["20-25% Damage (Flak Armoured)", "20-25% Damage (Maniacs)"], blessings: [{ name: "Cranial Grounding" }, { name: "Heatsink" }] },
      ],
      curios: [
        { name: "Blessed Bullet", perks: ["+15-20% DR vs Gunners", "+4-5% Toughness"] },
        { name: "Blessed Bullet", perks: ["+15-20% DR vs Snipers", "+4-5% Toughness"] },
        { name: "Blessed Bullet", perks: ["+2-5% Health", "+3-4% Combat Ability Regen"] },
      ],
      talents: { active: [], inactive: [] },
    };
    const card = generateScorecard(build);
    assert.ok(card.title === "Test Build");
    assert.ok(card.perk_optimality >= 1 && card.perk_optimality <= 5);
    assert.ok(card.curio_efficiency >= 1 && card.curio_efficiency <= 5);
    assert.ok(card.weapons.length === 2);
    assert.ok(card.curios);
  });
});
```

**Step 2: Run test, verify fail**

**Step 3: Implement CLI and scorecard**

Add to `score-build.mjs`:
- `generateScorecard(build)` — calls scoreWeaponPerks, scoreBlessings, scoreCurios; assembles scorecard object
- CLI entry point: `node scripts/score-build.mjs <build.json> [--json|--text]`
  - `--json`: raw scorecard JSON (default)
  - `--text`: human-readable formatted output

Text output format:
```
=== Test Build (veteran) ===

MECHANICAL SCORES:
  Perk Optimality:      4/5  — All T4, +Unyielding good for plasma
  Curio Efficiency:     5/5  — DR vs Gunners/Snipers + Toughness, class-optimal
  Breakpoint Relevance: -/5  — (requires qualitative assessment)

WEAPONS:
  [ranged] M35 Magnacore Mk II Plasma Gun
    Perks: +Unyielding (T4) ✓, +Elites (T4) ✓
    Blessings: Rising Heat ✓, Gets Hot! ✓
  [melee] Lawbringer Mk IIb Power Falchion
    Perks: +Flak (T4) ✓, +Maniacs (T4) ✓
    Blessings: Cranial Grounding (?), Heatsink (?)

CURIOS:
  DR vs Gunners (T4) ✓ optimal
  Toughness (T4) ✓ optimal
  DR vs Snipers (T4) ✓ optimal
  Toughness (T4) ✓ optimal
  Health (T4) ✓ good
  Combat Ability Regen (T4) ✓ optimal

QUALITATIVE (fill manually):
  Blessing Synergy:     _/5
  Talent Coherence:     _/5
  Role Coverage:        _/5
  Difficulty Scaling:   _/5

BOT FLAGS: (fill manually)
  [ ] BOT:NO_DODGE
  [ ] BOT:NO_WEAKSPOT
  ...
```

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add scripts/score-build.mjs scripts/score-build.test.mjs
git commit -m "feat(scoring): add CLI interface and scorecard output"
```

---

## Task 8: Create sample build JSON and end-to-end test

**Files:**
- Create: `scripts/sample-build.json`
- Modify: `scripts/score-build.test.mjs`

**Step 1: Create a sample build JSON**

Hand-write a build matching the first GL build in meta-builds-research.md (Veteran Squad Leader by seventhcodex). Use the same format `extract-build.mjs` outputs:

```json
{
  "url": "https://darktide.gameslantern.com/builds/9a565016-...",
  "title": "Veteran Squad Leader",
  "author": "seventhcodex",
  "class": "veteran",
  "weapons": [
    {
      "name": "Lawbringer Mk IIb Power Falchion",
      "rarity": "Transcendant",
      "perks": ["20-25% Damage (Flak Armoured)", "20-25% Damage (Maniacs)"],
      "blessings": [
        { "name": "Cranial Grounding", "description": "..." },
        { "name": "Heatsink", "description": "..." }
      ]
    },
    {
      "name": "M35 Magnacore Mk II Plasma Gun",
      "rarity": "Transcendant",
      "perks": ["20-25% Damage (Maniacs)", "20-25% Damage (Unyielding)"],
      "blessings": [
        { "name": "Rising Heat", "description": "..." },
        { "name": "Gets Hot!", "description": "..." }
      ]
    }
  ],
  "curios": [
    { "name": "Blessed Bullet", "rarity": "", "perks": ["+15-20% DR vs Snipers", "+4-5% Toughness"], "blessings": [] },
    { "name": "Blessed Bullet", "rarity": "", "perks": ["+15-20% DR vs Gunners", "+4-5% Toughness"], "blessings": [] },
    { "name": "Blessed Bullet", "rarity": "", "perks": ["+2-5% Health", "+15-20% DR vs Gunners"], "blessings": [] }
  ],
  "talents": { "active": [], "inactive": [] },
  "description": ""
}
```

**Step 2: Write e2e test**

```js
import { readFileSync } from "node:fs";

describe("end-to-end", () => {
  it("scores sample Veteran Squad Leader build", () => {
    const build = JSON.parse(readFileSync(new URL("./sample-build.json", import.meta.url)));
    const card = generateScorecard(build);
    assert.equal(card.class, "veteran");
    assert.ok(card.perk_optimality >= 3, "Veteran Squad Leader should score well on perks");
    assert.ok(card.curio_efficiency >= 4, "DR stacking curios should score high");
    assert.equal(card.weapons.length, 2);
  });
});
```

**Step 3: Run test, verify pass**

```bash
node --test scripts/score-build.test.mjs
```

**Step 4: Run CLI manually to eyeball output**

```bash
node scripts/score-build.mjs scripts/sample-build.json --text
```

Verify the text output looks correct and matches expected scores.

**Step 5: Commit**

```bash
git add scripts/sample-build.json scripts/score-build.test.mjs
git commit -m "test(scoring): add sample build and e2e test"
```

---

## Task 9: Audit all 20 GL builds

**Files:**
- Modify: `docs/classes/meta-builds-research.md` (add scorecard annotations)

**Context:** This task is manual + assisted. For each of the 20 GL builds in meta-builds-research.md:

**Step 1: Create build JSON files from the existing meta-builds-research.md data**

Each GL build entry has weapon names, perks, blessings, curio info. Hand-write JSON for each (or use extract-build.mjs to re-scrape if GL links still work).

Alternatively, write a small helper that parses the markdown entries into JSON. But given the inconsistent markdown formatting, hand-writing 20 small JSONs may be faster.

**Step 2: Run score-build.mjs on each**

```bash
for f in scripts/builds/*.json; do
  echo "=== $(basename $f) ==="
  node scripts/score-build.mjs "$f" --text
  echo
done
```

**Step 3: Add qualitative scores in conversation**

For each build, I (Claude) apply the qualitative dimensions:
- Blessing Synergy (from weapon-blessings.md knowledge)
- Talent Coherence (from class-talents.md knowledge)
- Role Coverage (from build archetype understanding)
- Difficulty Scaling (from meta knowledge)
- Bot-awareness flags

**Step 4: Annotate meta-builds-research.md**

Add a scorecard summary to each GL build entry:

```markdown
**Veteran Squad Leader** (seventhcodex) — [GL link](...)
- ...existing content...
- **Rating: A (29/35)** — Perk: 4, Blessing: 5, Talent: 4, Breakpoint: 4, Curio: 5, Role: 4, Difficulty: 3
- **Bot flags:** BOT:ABILITY_OK, BOT:AIM_DEPENDENT (plasma)
```

**Step 5: Commit**

```bash
git add docs/classes/meta-builds-research.md scripts/builds/
git commit -m "docs: audit all 20 GL builds with scoring system"
```

---

## Summary

| Task | Deliverable | Effort |
|------|-------------|--------|
| 1 | Perk catalog in JSON | Small |
| 2 | Blessing catalog + weapon metadata | Medium |
| 3 | Enemy breakpoints + curio ratings | Small |
| 4 | Scoring rubric doc | Small |
| 5 | score-build.mjs — perk scoring + tests | Medium |
| 6 | Blessing + curio scoring + tests | Medium |
| 7 | CLI interface + scorecard output | Medium |
| 8 | Sample build + e2e test | Small |
| 9 | Audit all 20 GL builds | Large (manual + automated) |

Tasks 1-4 are pure data/docs. Tasks 5-8 are code. Task 9 is the payoff.
