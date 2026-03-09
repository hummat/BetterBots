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
