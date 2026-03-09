import { describe, it } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { parsePerkString, scorePerk, scoreWeaponPerks, scoreBlessings, scoreCurios, generateScorecard } from "./score-build.mjs";

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

  it("returns valid=null for weapon with null blessings in data", () => {
    const weapon = {
      name: "Voidstrike Staff",
      blessings: [{ name: "Something", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, null);
    assert.deepEqual(result.blessings, []);
  });

  it("returns valid=null for unknown weapon", () => {
    const weapon = {
      name: "Totally Unknown Weapon XYZ",
      blessings: [{ name: "Something", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, null);
    assert.deepEqual(result.blessings, []);
  });

  it("validates all blessings and sets valid=true when all known", () => {
    const weapon = {
      name: "M35 Magnacore Mk II Plasma Gun",
      blessings: [
        { name: "Rising Heat", description: "..." },
        { name: "Gets Hot!", description: "..." },
      ],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, true);
    assert.equal(result.blessings.length, 2);
    assert.ok(result.blessings.every((b) => b.known === true));
  });

  it("sets valid=false when any blessing is unknown", () => {
    const weapon = {
      name: "M35 Magnacore Mk II Plasma Gun",
      blessings: [
        { name: "Rising Heat", description: "..." },
        { name: "Fake One", description: "..." },
      ],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, false);
  });

  it("fuzzy matches weapon name (data key substring of weapon name)", () => {
    const weapon = {
      name: "Improvised Mk I Shivs",
      blessings: [{ name: "Uncanny Strike", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.valid, true);
    assert.equal(result.blessings[0].known, true);
  });

  it("includes internal name in blessing result", () => {
    const weapon = {
      name: "M35 Magnacore Mk II Plasma Gun",
      blessings: [{ name: "Rising Heat", description: "..." }],
    };
    const result = scoreBlessings(weapon);
    assert.equal(result.blessings[0].internal, "crit_chance_scaled_on_heat");
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

  it("returns perk details with rating", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+15-20% DR vs Gunners"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.equal(result.perks.length, 1);
    assert.equal(result.perks[0].name, "DR vs Gunners");
    assert.equal(result.perks[0].rating, "optimal");
    assert.ok(result.perks[0].tier >= 1 && result.perks[0].tier <= 4);
  });

  it("rates universal_avoid perks as avoid", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+5-20% Curio Drop Chance"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.equal(result.perks[0].rating, "avoid");
  });

  it("rates class good perks as good", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+6-12% Stamina Regeneration"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.equal(result.perks[0].rating, "good");
  });

  it("rates unknown perks as neutral", () => {
    const curios = [
      { name: "Blessed Bullet", perks: ["+6-12% Revive Speed"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.equal(result.perks[0].rating, "neutral");
  });

  it("scores multiple curios together", () => {
    const curios = [
      { name: "C1", perks: ["+15-20% DR vs Gunners", "+4-5% Toughness"] },
      { name: "C2", perks: ["+15-20% DR vs Snipers", "+3-4% Combat Ability Regen"] },
    ];
    const result = scoreCurios(curios, "veteran");
    assert.ok(result.score >= 4);
    assert.equal(result.perks.length, 4);
  });
});

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

  it("includes weapon slot from data lookup", () => {
    const build = {
      title: "Slot Test",
      class: "veteran",
      weapons: [
        { name: "M35 Magnacore Mk II Plasma Gun", perks: [], blessings: [] },
      ],
      curios: [],
      talents: { active: [], inactive: [] },
    };
    const card = generateScorecard(build);
    assert.equal(card.weapons[0].slot, "ranged");
  });

  it("defaults slot to null for unknown weapon", () => {
    const build = {
      title: "Unknown Weapon",
      class: "veteran",
      weapons: [
        { name: "Totally Fake Weapon XYZ", perks: [], blessings: [] },
      ],
      curios: [],
      talents: { active: [], inactive: [] },
    };
    const card = generateScorecard(build);
    assert.equal(card.weapons[0].slot, null);
  });

  it("includes qualitative and bot_flags fields", () => {
    const build = {
      title: "Structure Test",
      class: "zealot",
      weapons: [],
      curios: [],
      talents: { active: [], inactive: [] },
    };
    const card = generateScorecard(build);
    assert.ok(card.qualitative !== undefined);
    assert.equal(card.qualitative.blessing_synergy, null);
    assert.equal(card.qualitative.talent_coherence, null);
    assert.equal(card.qualitative.breakpoint_relevance, null);
    assert.equal(card.qualitative.role_coverage, null);
    assert.equal(card.qualitative.difficulty_scaling, null);
    assert.deepEqual(card.bot_flags, []);
  });
});

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
