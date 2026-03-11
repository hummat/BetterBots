#!/usr/bin/env node
// Extract Darktide build data from GamesLantern URLs.
// Requires: playwright (npm i playwright)
//
// Usage:
//   node scripts/extract-build.mjs <url>
//   node scripts/extract-build.mjs <url> --json        # raw JSON output
//   node scripts/extract-build.mjs <url> --markdown     # markdown table (default)
//
// Finding builds:
//   The main /builds page only shows the top 20 ranked builds (all classes).
//   Class-specific catalogs live at path-based routes, NOT query params:
//     https://darktide.gameslantern.com/builds/veteran    (not ?class=veteran)
//     https://darktide.gameslantern.com/builds/zealot
//     https://darktide.gameslantern.com/builds/psyker
//     https://darktide.gameslantern.com/builds/ogryn
//     https://darktide.gameslantern.com/builds/arbites
//     https://darktide.gameslantern.com/builds/hive-scum
//   These pages are JS-rendered — WebFetch/curl won't see the listings.
//   To discover builds without a browser, use Google:
//     site:darktide.gameslantern.com/builds veteran

import { chromium } from "playwright";

const USAGE = `Usage: node scripts/extract-build.mjs <gameslantern-build-url> [--json|--markdown]`;

// Slug → display name: "scriers-gaze" → "Scrier's Gaze"
function slugToName(slug) {
  const special = {
    "scriers-gaze": "Scrier's Gaze",
    "psykinetics-aura": "Psykinetic's Aura",
    "marksmans-focus": "Marksman's Focus",
    "vultures-mark": "Vulture's Mark",
    "tis-but-a-scratch": "'Tis But a Scratch",
  };
  if (special[slug]) return special[slug];
  return slug
    .split("-")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

// Known passive keystones by GL slug. On GL, keystones use circular_frame
// (same as regular talents), so we need explicit identification to promote them.
// Source: decompiled talent_settings_*.lua + meta-builds-research.md
const KEYSTONES = new Set([
  // Veteran (internal: Sniper's Focus, Weapon Switch, Focus Target)
  "marksmans-focus", "weapons-specialist", "focus-target",
  // Zealot (internal: Fanatic Rage, Quickness, Martyrdom)
  "blazing-piety", "inexorable-judgement", "martyrdom",
  // Psyker
  "warp-siphon", "empowered-psionics", "disrupt-destiny",
  // Ogryn
  "heavy-hitter", "feel-no-pain", "burst-limiter-override",
  // Arbites (Adamant)
  "forceful", "execution-order", "terminus-warrant", "stance-dance",
  "exterminator", "bullet-rain", "pinning-dog",
  // Hive Scum (Broker)
  "float-like-a-butterfly", "pickpocket", "hyper-critical",
  "vultures-mark", "chemical-dependency", "adrenaline-junkie",
]);

// Frame shape → talent tier.
// hex_frame = ability section (combat ability + modifiers), NOT passive keystones.
// Actual keystones use circular_frame and are promoted via the KEYSTONES set.
function frameTier(href) {
  if (href.includes("hex_frame")) return "ability";
  if (href.includes("square_frame")) return "notable";
  if (href.includes("circular_small")) return "stat";
  if (href.includes("circular_frame")) return "talent";
  return "unknown";
}

async function extractBuild(url) {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    // Use domcontentloaded — networkidle can hang on ad networks
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
    await page.waitForTimeout(3_000);

    // Dismiss cookie consent if present
    try {
      await page.click(".fc-confirm-choices", { timeout: 3_000 });
      await page.waitForTimeout(500);
    } catch {
      // no consent dialog
    }

    // Wait for talent tree SVG to render (some builds may not have one)
    try {
      await page.waitForSelector(".ability-active", { timeout: 10_000 });
    } catch {
      // Talent tree may not be present — continue extracting other data
      console.error("Warning: talent tree not found, extracting other data");
    }

    return await page.evaluate(() => {
      const result = {
        url: window.location.href,
        title: "",
        author: "",
        class: "",
        weapons: [],
        curios: [],
        talents: { active: [], inactive: [] },
        description: "",
      };

      // --- Title & author ---
      const h1 = document.querySelector("h1");
      if (h1) {
        // Title may contain subtitle on next line — take only first line
        const titleText = h1.textContent.trim();
        const firstLine = titleText.split("\n")[0].trim();
        result.title = firstLine;
      }

      const authorEl = document.querySelector('a[href*="/user/"]');
      if (authorEl) result.author = authorEl.textContent.trim();

      // --- Class ---
      // Class is encoded in the archetype model image URL
      const classImg = document.querySelector(
        'img[src*="_model.webp"]'
      );
      if (classImg) {
        const match = classImg.src.match(
          /\/([a-z]+)-[a-z]+_model\.webp/
        );
        if (match) result.class = match[1];
      }
      // Fallback 1: breadcrumb text (e.g. "Arbites Builds")
      if (!result.class) {
        const breadcrumbs = document.querySelectorAll("nav a");
        for (const a of breadcrumbs) {
          const m = a.textContent.match(
            /(Psyker|Veteran|Zealot|Ogryn|Adamant|Arbites|Broker|Hive Scum)\s+Builds/i
          );
          if (m) {
            result.class = m[1].toLowerCase();
            break;
          }
        }
      }
      // Fallback 2: class image URL with broader pattern
      if (!result.class) {
        const anyClassImg = document.querySelector(
          'img[src*="/darktide/"][src*="_model"]'
        );
        if (anyClassImg) {
          const m = anyClassImg.src.match(/\/([^/]+)_model/);
          if (m) result.class = m[1].replace(/-/g, " ");
        }
      }

      // --- Talents ---
      function extractTalents(selector) {
        const nodes = [];
        for (const el of document.querySelectorAll(selector)) {
          const anchor = el.closest("a");
          if (!anchor) continue;
          const href = anchor.getAttribute("href") || "";
          const match = href.match(/\/abilities\/(.+)$/);
          if (!match) continue;
          const frameHref = el.getAttribute("href") || "";
          nodes.push({ slug: match[1], frame: frameHref });
        }
        return nodes;
      }

      result.talents.active = extractTalents(".ability-active");
      result.talents.inactive = extractTalents(".ability-inactive");

      // --- Sections ---
      // Page uses .mt-8.mb-4 headings ("Weapons", "Curios", etc.)
      // followed by sibling content divs until the next heading.
      function getSection(name) {
        const headings = document.querySelectorAll(".mt-8.mb-4");
        for (const h of headings) {
          if (h.textContent.trim() === name) return h;
        }
        return null;
      }

      // --- Weapons & Curios ---
      // Both live in a flex-wrap container immediately after their heading.
      // Each item card is a div.max-w-sm inside that container.
      function parseItemCards(sectionName) {
        const heading = getSection(sectionName);
        if (!heading) return [];

        const container = heading.nextElementSibling;
        if (!container) return [];

        // Weapon cards use max-w-sm, curio cards use max-w-[330px]
        const cards = container.querySelectorAll(
          ':scope > div[class*="max-w"]'
        );
        const items = [];

        for (const card of cards) {
          const text = card.innerText;
          const lines = text
            .split("\n")
            .map((l) => l.trim())
            .filter(Boolean);
          if (lines.length < 2) continue;

          const item = {
            name: lines[0],
            rarity: "",
            perks: [],
            blessings: [],
          };

          const rarities = new Set([
            "Transcendant",
            "Anointed",
            "Profane",
            "Redeemed",
          ]);
          const statBar = /^\[[\d/]+\]%$/;
          const statLabel =
            /^(Warp Resistance|Cleave|Finesse|Defences|Damage|Quell|Charge|Blast|Mobility|Attack Speed|Critical|Stamina|Peril|Dodge|Sprint|Block|Push|First Target|Reload)/;
          const statValue = /^[\d.]+$/;
          const statRange = /^\[[\d. |]+\]$/;

          let i = 1;
          while (i < lines.length) {
            const line = lines[i];

            if (rarities.has(line)) {
              item.rarity = line;
              i++;
              continue;
            }

            // Skip stat bars and labels
            if (
              statBar.test(line) ||
              statLabel.test(line) ||
              statValue.test(line) ||
              statRange.test(line) ||
              line.startsWith("Damage vs ")
            ) {
              i++;
              continue;
            }

            // Perk: "X-Y% Something" or "+X% Something"
            if (line.match(/^\d+-\d+%\s/) || line.match(/^\+\d/)) {
              item.perks.push(line);
              i++;
              continue;
            }

            // Blessing: short capitalized name followed by longer description
            const next = lines[i + 1];
            if (
              line.match(/^[A-Z]/) &&
              line.length < 60 &&
              next &&
              next.length > 15 &&
              !statBar.test(next) &&
              !rarities.has(next)
            ) {
              item.blessings.push({ name: line, description: next });
              i += 2;
              continue;
            }

            i++;
          }

          items.push(item);
        }
        return items;
      }

      result.weapons = parseItemCards("Weapons");
      result.curios = parseItemCards("Curios");

      // --- Description ---
      const descEl = document.querySelector(".darktide-description");
      if (descEl) {
        result.description = descEl.innerText.trim().slice(0, 5000);
      }

      return result;
    });
  } finally {
    await browser.close();
  }
}

function formatMarkdown(build) {
  const lines = [];
  lines.push(`# ${build.title || "Untitled Build"}`);
  if (build.author) lines.push(`By **${build.author}**`);
  lines.push(`Class: **${build.class}**`);
  lines.push(`Source: ${build.url}`);
  lines.push("");

  // Talents grouped by tier (uses pre-computed t.tier from post-processing)
  const tiers = { ability: [], keystone: [], notable: [], talent: [], stat: [] };
  for (const t of build.talents.active) {
    const tier = t.tier || frameTier(t.frame);
    tiers[tier] = tiers[tier] || [];
    tiers[tier].push(t.name || slugToName(t.slug));
  }

  lines.push("## Talents");
  lines.push("");
  if (tiers.ability.length) {
    const [abilityName, ...modifiers] = tiers.ability;
    if (modifiers.length) {
      lines.push(`**Ability:** ${abilityName} (modifiers: ${modifiers.join(", ")})`);
    } else {
      lines.push(`**Ability:** ${abilityName}`);
    }
  }
  if (tiers.keystone.length) {
    lines.push(`**Keystones:** ${tiers.keystone.join(", ")}`);
  }
  if (tiers.notable.length) {
    lines.push(`**Notables:** ${tiers.notable.join(", ")}`);
  }
  if (tiers.talent.length) {
    lines.push(`**Talents:** ${tiers.talent.join(", ")}`);
  }
  if (tiers.stat.length) {
    lines.push(`**Stat nodes:** ${tiers.stat.join(", ")}`);
  }
  lines.push(`\nTotal: ${build.talents.active.length}/30`);
  lines.push("");

  // Weapons
  if (build.weapons.length) {
    lines.push("## Weapons");
    for (const w of build.weapons) {
      lines.push(`\n### ${w.name}${w.rarity ? ` (${w.rarity})` : ""}`);
      if (w.perks.length) {
        lines.push("**Perks:**");
        for (const p of w.perks) lines.push(`- ${p}`);
      }
      if (w.blessings.length) {
        lines.push("**Blessings:**");
        for (const b of w.blessings) {
          lines.push(`- **${b.name}**: ${b.description}`);
        }
      }
    }
    lines.push("");
  }

  // Curios
  if (build.curios.length) {
    lines.push("## Curios");
    for (const c of build.curios) {
      lines.push(
        `- **${c.name}**${c.rarity ? ` (${c.rarity})` : ""}: ${c.perks.join(", ")}`
      );
    }
    lines.push("");
  }

  // Description
  if (build.description) {
    lines.push("## Description");
    lines.push(build.description.slice(0, 2000));
    lines.push("");
  }

  return lines.join("\n");
}

// --- Main ---
const args = process.argv.slice(2);
const url = args.find((a) => !a.startsWith("--"));
const format = args.includes("--json") ? "json" : "markdown";

if (!url || !url.includes("gameslantern.com/builds/")) {
  console.error(USAGE);
  process.exit(1);
}

console.error("Extracting build from:", url);
const build = await extractBuild(url);

// Post-process talents: compute tier and promote known keystones
build.talents.active = build.talents.active.map((t) => {
  const baseTier = frameTier(t.frame);
  const tier = baseTier === "talent" && KEYSTONES.has(t.slug) ? "keystone" : baseTier;
  return { ...t, name: slugToName(t.slug), tier };
});
build.talents.inactive = build.talents.inactive.map((t) => {
  const baseTier = frameTier(t.frame);
  const tier = baseTier === "talent" && KEYSTONES.has(t.slug) ? "keystone" : baseTier;
  return { ...t, name: slugToName(t.slug), tier };
});

if (format === "json") {
  console.log(JSON.stringify(build, null, 2));
} else {
  console.log(formatMarkdown(build));
}
