#!/usr/bin/env node
// Score Darktide build data (output of extract-build.mjs) against build-scoring-data.json.
// Currently implements: perk parsing and scoring.
// Future tasks will add blessing scoring, curio scoring, and CLI interface.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

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

    // Word containment: all words of the shorter name appear in the longer
    const keyWords = normKey.split(" ");
    if (keyWords.length <= inputWords.length) {
      if (keyWords.every((w) => inputWords.includes(w))) {
        return { key, entry };
      }
    } else {
      if (inputWords.every((w) => keyWords.includes(w))) {
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
