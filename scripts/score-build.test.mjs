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

  it("parses single-value without plus prefix", () => {
    const result = parsePerkString("25% Damage (Flak Armoured)");
    assert.deepEqual(result, { min: 0.25, max: 0.25, name: "Damage (Flak Armoured)" });
  });

  it("returns null for unparseable string", () => {
    const result = parsePerkString("Some random text");
    assert.equal(result, null);
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

  it("returns tier 2 for second-tier value", () => {
    const result = scorePerk("Damage (Flak Armoured)", 0.15, "melee");
    assert.equal(result.tier, 2);
  });

  it("returns tier 3 for third-tier value", () => {
    const result = scorePerk("Damage (Flak Armoured)", 0.20, "melee");
    assert.equal(result.tier, 3);
  });

  it("returns null for unknown perk", () => {
    const result = scorePerk("Nonexistent Perk", 0.10, "melee");
    assert.equal(result, null);
  });

  it("returns null for unknown slot", () => {
    const result = scorePerk("Damage (Flak Armoured)", 0.10, "banana");
    assert.equal(result, null);
  });

  it("works with ranged slot", () => {
    const result = scorePerk("Reload Speed", 0.10, "ranged");
    assert.equal(result.tier, 4);
  });

  it("works with curio slot", () => {
    const result = scorePerk("DR vs Gunners", 0.20, "curio");
    assert.equal(result.tier, 4);
  });

  it("finds nearest tier for in-between values", () => {
    // 0.12 is between T1 (0.10) and T2 (0.15), closer to T1
    const result = scorePerk("Damage (Flak Armoured)", 0.12, "melee");
    assert.equal(result.tier, 1);
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

  it("scores a weapon with T1 perks as 2/5", () => {
    const weapon = {
      name: "Some Melee Weapon",
      perks: ["10-10% Damage (Flak Armoured)", "4-4% Damage (Elites)"],
    };
    const result = scoreWeaponPerks(weapon, "melee");
    assert.equal(result.score, 2);
    assert.ok(result.perks.every((p) => p.tier === 1));
  });

  it("scores a weapon with mixed tiers", () => {
    const weapon = {
      name: "Some Melee Weapon",
      perks: ["20-25% Damage (Flak Armoured)", "4-4% Damage (Elites)"],
    };
    const result = scoreWeaponPerks(weapon, "melee");
    // T4 + T1 = average 2.5 → score 3
    assert.equal(result.score, 3);
  });

  it("scores a weapon with no perks as 1/5", () => {
    const weapon = {
      name: "Some Melee Weapon",
      perks: [],
    };
    const result = scoreWeaponPerks(weapon, "melee");
    assert.equal(result.score, 1);
  });

  it("scores a weapon with unparseable perks as 1/5", () => {
    const weapon = {
      name: "Some Melee Weapon",
      perks: ["gibberish text"],
    };
    const result = scoreWeaponPerks(weapon, "melee");
    assert.equal(result.score, 1);
  });
});
