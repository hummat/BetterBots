#!/usr/bin/env node
// Score Darktide build data (output of extract-build.mjs) against build-scoring-data.json.
// Perk parsing/scoring, blessing validation, curio scoring, and CLI scorecard output.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_PATH = join(__dirname, "build-scoring-data.json");

let _data = null;

function loadData() {
  if (!_data) {
    _data = JSON.parse(readFileSync(DATA_PATH, "utf-8"));
  }
  return _data;
}

const SLOT_TO_KEY = {
  melee: "melee_perks",
  ranged: "ranged_perks",
  curio: "curio_perks",
};

/**
 * Parse a perk string from the GL scraper into structured form.
 *
 * Supported formats:
 *   "10-25% Damage (Flak Armoured)"  → { min: 0.10, max: 0.25, name: "Damage (Flak Armoured)" }
 *   "+1-2 Stamina"                   → { min: 1, max: 2, name: "Stamina" }
 *   "+5% Toughness"                  → { min: 0.05, max: 0.05, name: "Toughness" }
 *   "25% Damage (Flak Armoured)"     → { min: 0.25, max: 0.25, name: "Damage (Flak Armoured)" }
 *   "+15-20% DR vs Gunners"          → { min: 0.15, max: 0.20, name: "DR vs Gunners" }
 *
 * Returns null if the string cannot be parsed.
 */
export function parsePerkString(str) {
  // Pattern 1: range with percent — "10-25% Name" or "+10-25% Name"
  let m = str.match(/^\+?(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)%\s+(.+)$/);
  if (m) {
    return {
      min: parseFloat(m[1]) / 100,
      max: parseFloat(m[2]) / 100,
      name: m[3],
    };
  }

  // Pattern 2: single percent — "+5% Name" or "25% Name"
  m = str.match(/^\+?(\d+(?:\.\d+)?)%\s+(.+)$/);
  if (m) {
    const val = parseFloat(m[1]) / 100;
    return { min: val, max: val, name: m[2] };
  }

  // Pattern 3: flat range — "+1-2 Name"
  m = str.match(/^\+(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)\s+(.+)$/);
  if (m) {
    return {
      min: parseFloat(m[1]),
      max: parseFloat(m[2]),
      name: m[3],
    };
  }

  // Pattern 4: single flat — "+5 Name"
  m = str.match(/^\+(\d+(?:\.\d+)?)\s+(.+)$/);
  if (m) {
    const val = parseFloat(m[1]);
    return { min: val, max: val, name: m[2] };
  }

  return null;
}

/**
 * Look up a perk by name and value in the scoring data, determine its tier.
 *
 * @param {string} name   - Perk display name (e.g. "Damage (Flak Armoured)")
 * @param {number} value  - The perk's numeric value (decimal for percentages)
 * @param {string} slot   - "melee", "ranged", or "curio"
 * @returns {{ name: string, tier: number, value: number } | null}
 */
export function scorePerk(name, value, slot) {
  const data = loadData();
  const key = SLOT_TO_KEY[slot];
  if (!key) return null;

  const catalog = data[key];
  if (!catalog) return null;

  const perkDef = catalog[name];
  if (!perkDef) return null;

  const tiers = perkDef.tiers; // [T1, T2, T3, T4]
  let bestTier = 1;
  let bestDist = Math.abs(value - tiers[0]);

  for (let i = 1; i < tiers.length; i++) {
    const dist = Math.abs(value - tiers[i]);
    if (dist < bestDist) {
      bestDist = dist;
      bestTier = i + 1; // 1-indexed
    }
  }

  return { name, tier: bestTier, value };
}

/**
 * Score all perks on a weapon/curio.
 *
 * Uses the MAX value from the perk string range (the T4 end of what the GL
 * scraper reports) to determine the tier for each perk.
 *
 * Scoring (1-5):
 *   5: All perks T4
 *   4: All T3-T4
 *   3: Mix of T2-T4, or average tier ~2.5
 *   2: T1-T2 perks
 *   1: Missing perks, unparseable, or completely unknown
 *
 * @param {{ name: string, perks: string[] }} weapon
 * @param {string} slot - "melee", "ranged", or "curio"
 * @returns {{ score: number, perks: Array<{ name: string, tier: number, value: number } | null> }}
 */
export function scoreWeaponPerks(weapon, slot) {
  if (!weapon.perks || weapon.perks.length === 0) {
    return { score: 1, perks: [] };
  }

  const scored = [];
  for (const perkStr of weapon.perks) {
    const parsed = parsePerkString(perkStr);
    if (!parsed) {
      scored.push(null);
      continue;
    }
    const result = scorePerk(parsed.name, parsed.max, slot);
    scored.push(result);
  }

  const valid = scored.filter((p) => p !== null);
  if (valid.length === 0) {
    return { score: 1, perks: scored };
  }

  const avgTier = valid.reduce((sum, p) => sum + p.tier, 0) / valid.length;

  // Map average tier to 1-5 score
  // T4 avg → 5, T3-T4 avg → 4, T2-T3 avg → 3, T1-T2 avg → 2, below → 1
  let score;
  if (avgTier >= 4) {
    score = 5;
  } else if (avgTier >= 3) {
    score = 4;
  } else if (avgTier >= 2) {
    score = 3;
  } else if (avgTier >= 1) {
    score = 2;
  } else {
    score = 1;
  }

  return { score, perks: scored };
}

/**
 * Normalize a weapon name for fuzzy matching: lowercase, collapse whitespace.
 */
function normalizeName(name) {
  return name.toLowerCase().replace(/\s+/g, " ").trim();
}

/**
 * Find a weapon in the data by name, using fuzzy matching.
 *
 * Matching strategy (in order):
 *   1. Exact match on key
 *   2. Substring: data key contained in weapon name or vice versa
 *   3. Word containment: all words of the shorter name appear in the longer name
 *
 * @param {string} weaponName
 * @returns {{ key: string, entry: object } | null}
 */
function findWeapon(weaponName) {
  const data = loadData();
  const weapons = data.weapons;
  if (!weapons) return null;

  // Exact match first
  if (weapons[weaponName]) {
    return { key: weaponName, entry: weapons[weaponName] };
  }

  const normalized = normalizeName(weaponName);
  const inputWords = normalized.split(" ");

  for (const [key, entry] of Object.entries(weapons)) {
    const normKey = normalizeName(key);

    // Substring match
    if (normalized.includes(normKey) || normKey.includes(normalized)) {
      return { key, entry };
    }

    // Word containment: all words of the shorter name appear in the longer,
    // and at least 50% of the longer name's words are matched (prevents false
    // positives on short generic inputs like "Gun" or "Mk II").
    const keyWords = normKey.split(" ");
    const shorter = keyWords.length <= inputWords.length ? keyWords : inputWords;
    const longer = keyWords.length <= inputWords.length ? inputWords : keyWords;
    if (shorter.length >= 2 && shorter.every((w) => longer.includes(w))) {
      const matchRatio = shorter.length / longer.length;
      if (matchRatio >= 0.5) {
        return { key, entry };
      }
    }
  }

  return null;
}

/**
 * Validate blessings on a weapon against the scoring data.
 *
 * @param {{ name: string, blessings: Array<{ name: string, description: string }> }} weapon
 * @returns {{ valid: boolean|null, blessings: Array<{ name: string, known: boolean, internal: string|null }> }}
 */
export function scoreBlessings(weapon) {
  const found = findWeapon(weapon.name);

  // Unknown weapon — can't validate
  if (!found) {
    return { valid: null, blessings: [] };
  }

  const blessingData = found.entry.blessings;

  // Weapon exists but has no blessing data (null)
  if (blessingData === null || blessingData === undefined) {
    return { valid: null, blessings: [] };
  }

  const results = [];
  for (const blessing of weapon.blessings) {
    const match = blessingData[blessing.name];
    results.push({
      name: blessing.name,
      known: !!match,
      internal: match ? match.internal : null,
    });
  }

  const allKnown = results.every((b) => b.known);
  return { valid: allKnown, blessings: results };
}

/**
 * Score curio perks against class-specific ratings.
 *
 * Flattens all perks across all curios, parses each, checks against
 * class optimal/good lists and universal avoid list, then scores 1-5.
 *
 * @param {Array<{ name: string, perks: string[] }>} curios
 * @param {string} className - e.g. "veteran", "zealot"
 * @returns {{ score: number, perks: Array<{ name: string, tier: number, rating: string }> }}
 */
export function scoreCurios(curios, className) {
  const data = loadData();
  const ratings = data.curio_ratings;
  if (!ratings) return { score: 1, perks: [] };

  const classRatings = ratings[className] || {};
  const universalOptimal = ratings._universal_optimal || [];
  const universalGood = ratings._universal_good || [];
  const universalAvoid = ratings._universal_avoid || [];

  const classOptimal = classRatings.optimal || [];
  const classGood = classRatings.good || [];

  // Combine class + universal lists (class-specific takes priority)
  const optimalSet = new Set([...classOptimal, ...universalOptimal]);
  const goodSet = new Set([...classGood, ...universalGood]);
  const avoidSet = new Set(universalAvoid);

  const perkResults = [];

  for (const curio of curios) {
    if (!curio.perks) continue;
    for (const perkStr of curio.perks) {
      const parsed = parsePerkString(perkStr);
      if (!parsed) {
        perkResults.push({ name: perkStr, tier: 0, rating: "neutral" });
        continue;
      }

      const scored = scorePerk(parsed.name, parsed.max, "curio");
      const tier = scored ? scored.tier : 0;

      let rating;
      if (avoidSet.has(parsed.name)) {
        rating = "avoid";
      } else if (optimalSet.has(parsed.name)) {
        rating = "optimal";
      } else if (goodSet.has(parsed.name)) {
        rating = "good";
      } else {
        rating = "neutral";
      }

      perkResults.push({ name: parsed.name, tier, rating });
    }
  }

  if (perkResults.length === 0) {
    return { score: 1, perks: [] };
  }

  // Score 1-5 based on rating + tier combination
  const hasAvoid = perkResults.some((p) => p.rating === "avoid");
  if (hasAvoid) {
    return { score: 1, perks: perkResults };
  }

  const optimalCount = perkResults.filter((p) => p.rating === "optimal").length;
  const goodCount = perkResults.filter((p) => p.rating === "good").length;
  const total = perkResults.length;
  const avgTier = perkResults.reduce((sum, p) => sum + p.tier, 0) / total;
  const desirableRatio = (optimalCount + goodCount) / total;

  let score;
  if (optimalCount === total && avgTier >= 3.5) {
    score = 5;
  } else if (desirableRatio >= 0.8 && avgTier >= 3) {
    score = 4;
  } else if (desirableRatio >= 0.5 && avgTier >= 2.5) {
    score = 3;
  } else {
    score = 2;
  }

  return { score, perks: perkResults };
}

/**
 * Generate a full scorecard for a build.
 *
 * Calls scoreWeaponPerks, scoreBlessings, scoreCurios and assembles the result.
 *
 * @param {{ title: string, class: string, weapons: Array, curios: Array, talents: object }} build
 * @returns {object} Scorecard object
 */
export function generateScorecard(build) {
  const weaponResults = [];
  const perkScores = [];

  for (const weapon of build.weapons || []) {
    const found = findWeapon(weapon.name);
    const slot = found ? found.entry.slot : null;

    // Score perks — use slot from data, or try both catalogs if unknown
    let perkResult;
    if (slot) {
      perkResult = scoreWeaponPerks(weapon, slot);
    } else {
      // Try ranged first, then melee — pick whichever has more resolved perks
      const rangedResult = scoreWeaponPerks(weapon, "ranged");
      const meleeResult = scoreWeaponPerks(weapon, "melee");
      const rangedResolved = rangedResult.perks.filter((p) => p !== null).length;
      const meleeResolved = meleeResult.perks.filter((p) => p !== null).length;
      perkResult = rangedResolved >= meleeResolved ? rangedResult : meleeResult;
    }

    perkScores.push(perkResult.score);

    const blessingResult = scoreBlessings(weapon);

    weaponResults.push({
      name: weapon.name,
      slot,
      perks: perkResult,
      blessings: blessingResult,
    });
  }

  const curioResult = scoreCurios(build.curios || [], build.class);

  // Average perk scores across weapons, or 1 if none
  const perkOptimality =
    perkScores.length > 0
      ? Math.round(perkScores.reduce((a, b) => a + b, 0) / perkScores.length)
      : 1;

  return {
    title: build.title,
    class: build.class,
    perk_optimality: perkOptimality,
    curio_efficiency: curioResult.score,
    weapons: weaponResults,
    curios: curioResult,
    qualitative: {
      blessing_synergy: null,
      talent_coherence: null,
      breakpoint_relevance: null,
      role_coverage: null,
      difficulty_scaling: null,
    },
    bot_flags: [],
  };
}

/**
 * Format scorecard as human-readable text.
 */
function formatScorecardText(card) {
  const lines = [];
  lines.push(`=== ${card.title} (${card.class}) ===`);
  lines.push("");
  lines.push("MECHANICAL SCORES:");
  lines.push(`  Perk Optimality:      ${card.perk_optimality}/5`);
  lines.push(`  Curio Efficiency:     ${card.curio_efficiency}/5`);
  lines.push("  Breakpoint Relevance: -/5  (requires qualitative assessment)");
  lines.push("");
  lines.push("WEAPONS:");

  for (const w of card.weapons) {
    const slotTag = w.slot ? `[${w.slot}]` : "[?]";
    lines.push(`  ${slotTag} ${w.name}`);

    // Perks line
    const perkParts = [];
    for (const p of w.perks.perks) {
      if (p === null) {
        perkParts.push("? (unknown)");
      } else {
        perkParts.push(`+${p.name} (T${p.tier}) \u2713`);
      }
    }
    if (perkParts.length > 0) {
      lines.push(`    Perks: ${perkParts.join(", ")}`);
    }

    // Blessings line
    const blessingParts = [];
    for (const b of w.blessings.blessings) {
      blessingParts.push(`${b.name} ${b.known ? "\u2713" : "(?)"}`);
    }
    if (blessingParts.length > 0) {
      lines.push(`    Blessings: ${blessingParts.join(", ")}`);
    }
  }

  lines.push("");
  lines.push("CURIOS:");
  for (const p of card.curios.perks) {
    const tierStr = p.tier > 0 ? `(T${p.tier})` : "(?)";
    const check = p.rating === "avoid" ? "\u2717" : "\u2713";
    lines.push(`  ${p.name} ${tierStr} ${check} ${p.rating}`);
  }

  lines.push("");
  lines.push("QUALITATIVE (fill manually):");
  lines.push("  Blessing Synergy:     _/5");
  lines.push("  Talent Coherence:     _/5");
  lines.push("  Role Coverage:        _/5");
  lines.push("  Difficulty Scaling:   _/5");

  lines.push("");
  lines.push("BOT FLAGS: (fill manually)");
  lines.push("  [ ] BOT:NO_DODGE");
  lines.push("  [ ] BOT:NO_WEAKSPOT");
  lines.push("  [ ] BOT:NO_PERIL_MGT");
  lines.push("  [ ] BOT:NO_POSITIONING");
  lines.push("  [ ] BOT:NO_BLOCK_TIMING");
  lines.push("  [ ] BOT:AIM_DEPENDENT");
  lines.push("  [ ] BOT:ABILITY_OK");
  lines.push("  [ ] BOT:ABILITY_MISSING");

  return lines.join("\n");
}

// CLI entry point — only when executed directly
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      json: { type: "boolean", default: false },
      text: { type: "boolean", default: false },
    },
  });

  const buildPath = positionals[0];
  if (!buildPath) {
    console.error("Usage: node scripts/score-build.mjs <build.json> [--json|--text]");
    process.exit(1);
  }

  const build = JSON.parse(readFileSync(buildPath, "utf-8"));
  const card = generateScorecard(build);

  if (values.text) {
    console.log(formatScorecardText(card));
  } else {
    console.log(JSON.stringify(card, null, 2));
  }
}
