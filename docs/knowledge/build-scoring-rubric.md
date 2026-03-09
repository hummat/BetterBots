# Build Scoring Rubric

Mod version baseline: v0.4.0

7 dimensions, each scored 1-5, total /35. Mechanical dimensions (1, 4, 5) can be automated; qualitative dimensions (2, 3, 6, 7) require human judgment.

## Dimension Scales

### 1. Perk Optimality (Mechanical)

Does the build use the right perks at the right tiers for its weapon role?

| Score | Description |
|-------|-------------|
| 1 | Wrong stat entirely or T1-T2 perks on both slots. Perks contradict weapon role (e.g. crit chance on a non-crit weapon). |
| 2 | One correct stat at T3, one wasted or mismatched slot. |
| 3 | Right stats for the weapon role, both T3. Functional but not optimized. |
| 4 | Right stats, one T4, one T3. Minor room for improvement. |
| 5 | T4 perks matching weapon role exactly. Both slots serve the build's damage profile. |

### 2. Blessing Synergy (Qualitative)

Do the weapon blessings work together and support the build's archetype?

| Score | Description |
|-------|-------------|
| 1 | Blessings contradict each other or are weak-tier for the weapon. No synergy with talents or playstyle. |
| 2 | One blessing fits, one is filler or low-tier. Minimal interaction between the two. |
| 3 | Decent combo that makes mechanical sense. Not best-in-slot but not wasteful. |
| 4 | Strong synergy, one blessing amplifies the other. Near-optimal for the archetype. |
| 5 | Best-in-slot combo for the archetype. Blessings feed each other and align with talent choices. |

### 3. Talent Coherence (Qualitative)

Does the 30-point talent build form a focused archetype with minimal waste?

| Score | Description |
|-------|-------------|
| 1 | Scattered points across unrelated nodes. No recognizable archetype or keystone plan. |
| 2 | Recognizable direction but 4+ wasted points on filler or contradictory nodes. |
| 3 | Recognizable archetype with 2-3 wasted points. Keystone chosen correctly. |
| 4 | Tight build, 1 arguable node. Clear gameplan from keystone through supporting talents. |
| 5 | Every node serves the gameplan. No wasted points. Keystone, passives, and weapon synergize fully. |

### 4. Breakpoint Relevance (Mechanical)

Do perks and blessings push the build past meaningful damage thresholds?

| Score | Description |
|-------|-------------|
| 1 | Perks and blessings miss all key thresholds. Damage falls short on priority targets at intended difficulty. |
| 2 | Hits one breakpoint (e.g. horde-clear bodyshots) but misses elites. |
| 3 | Hits some breakpoints: either horde thresholds or elite thresholds, not both. |
| 4 | Hits most relevant breakpoints. One gap against a priority target. |
| 5 | Hits the breakpoints that matter: Crusher/Mauler/special oneshots or two-shots at target difficulty. Horde clear is also covered. |

### 5. Curio Efficiency (Mechanical)

Are curio perks and stats chosen to cover the class's weaknesses?

| Score | Description |
|-------|-------------|
| 1 | Random perks with no stacking logic. Stats don't address class weakness. |
| 2 | Generic toughness/health stats, one relevant perk. No coherent DR strategy. |
| 3 | Standard toughness/health with generic DR. Functional survivability but not class-optimized. |
| 4 | Good stat choices with 2 stacking DR perks that address the class's specific vulnerability. |
| 5 | Optimized for class weakness: DR stacking that covers the primary damage intake pattern, stats tuned to the archetype (e.g. stamina for block-heavy, toughness regen for ranged). |

### 6. Role Coverage (Qualitative)

How many combat roles does the build handle?

| Score | Description |
|-------|-------------|
| 1 | One-dimensional: only horde-clear or only single-target. No sustain, no team utility. |
| 2 | Covers one role well and partially covers a second. |
| 3 | Covers 2 of 3 core roles (horde, elite, sustain). Team utility absent. |
| 4 | Covers all 3 core roles. Some team utility (coherency, CC, aggro). |
| 5 | Full coverage: horde + elite + sustain + meaningful team utility. No major gap in any combat phase. |

### 7. Difficulty Scaling (Qualitative)

How well does the build perform as difficulty increases?

| Score | Description |
|-------|-------------|
| 1 | Falls apart above Havoc 20. Core loop breaks under enemy density or damage scaling. |
| 2 | Functional at Havoc 20-25 but struggles with modifiers. |
| 3 | Viable at Havoc 30, struggles at 40. Some modifiers (e.g. lethal enemies, hunting grounds) cause problems. |
| 4 | Comfortable at Havoc 30, viable at 40 with competent play. Most modifiers manageable. |
| 5 | Proven Havoc 40, handles all modifiers. Sustain and damage scale with enemy density rather than against it. |

## Letter Grades

| Grade | Score Range | Meaning |
|-------|-------------|---------|
| S | 32-35 | Meta-defining, no meaningful weakness |
| A | 27-31 | Strong, minor optimization gaps |
| B | 22-26 | Functional, clear room for improvement |
| C | 17-21 | Underperforming, multiple weak dimensions |
| D | <17 | Fundamentally flawed or incoherent |

## Per-Class Weights

Dimensions are weighted equally in the raw score, but class context shifts which dimensions matter most for qualitative assessment:

- **Veteran**: Role Coverage matters more. Team support class with ranged focus; builds that only kill are underusing the kit. Volley Fire and shout builds need team payoff.
- **Zealot**: Difficulty Scaling matters more. Melee-forward means more damage taken; builds that work at Havoc 20 but melt at 40 reveal sustain gaps. DR stacking and toughness regen are load-bearing.
- **Psyker**: Breakpoint Relevance less critical. Warp damage bypasses armor, so the standard breakpoint math (physical damage vs HP) is less decisive. Talent Coherence and peril management matter more.
- **Ogryn**: Perk Optimality matters more. Ogryn base stats compensate less at high difficulty than other classes; perk tiers directly affect viability. Blessing Synergy also elevated since Ogryn weapon pools are smaller.
- **Arbites**: Block Efficiency perks matter (shield class). Role Coverage important since Arbites fills tank + CC; builds that neglect either role waste the class identity.
- **Hive Scum**: Blessing Synergy critical due to bleed/crit stacking builds that live or die on blessing interaction. Curio Efficiency matters since the class is fragile without DR stacking.

## Bot-Awareness Flags

Appended to each scorecard. Track where build assumptions break for bots. Flag set reflects BetterBots capabilities as of v0.4.0.

| Flag | Trigger | Example Talents/Mechanics |
|------|---------|---------------------------|
| `BOT:NO_DODGE` | Build relies on dodge for damage or survival | Quickness, dodge-crit blessings, dodge-count talents |
| `BOT:NO_WEAKSPOT` | Build relies on weakspot hits | Sniper's Focus, weakspot-kill regen, Deadeye |
| `BOT:NO_PERIL_MGT` | Build requires manual peril management | Overcharge stance, Warp Siphon glass cannon, Brain Burst spam |
| `BOT:NO_POSITIONING` | Build requires deliberate positioning | Backstab talents, flanking bonuses, cover-dependent ranged |
| `BOT:NO_BLOCK_TIMING` | Build relies on perfect blocks | Arbites perfect-block synergies, Riposte |
| `BOT:AIM_DEPENDENT` | Effectiveness scales with aim precision | Helbore sniper builds, plasma charged shots, head-popping |
| `BOT:ABILITY_OK` | BetterBots can trigger the ability correctly | Most shouts, charges, stances (Tiers 1-3 supported) |
| `BOT:ABILITY_MISSING` | BetterBots cannot trigger this mechanic | Blitz/grenade, weapon specials, parry, manual combos |

A build with 3+ negative bot flags is poorly suited for bot use without BetterBots improvements targeting those gaps.

## Scorecard Template

Copy-paste for manual scoring:

```
Build: [name]
Class: [class]
Source: [GL link or author]
Difficulty target: Havoc [N]

| Dimension | Score | Notes |
|-----------|-------|-------|
| Perk Optimality | /5 | |
| Blessing Synergy | /5 | |
| Talent Coherence | /5 | |
| Breakpoint Relevance | /5 | |
| Curio Efficiency | /5 | |
| Role Coverage | /5 | |
| Difficulty Scaling | /5 | |
| **Total** | **/35** | |

Grade: [ ]

Bot Flags: [ ]
```
