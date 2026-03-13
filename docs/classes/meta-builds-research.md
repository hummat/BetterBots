# Darktide Endgame Meta Builds Research (Havoc 30-40)

> Compiled 2026-03-06 from Games Lantern (20 builds), Reddit/Steam/Fatshark Forums, and decompiled source v1.10.7.
> Updated 2026-03-09 with balance patch data, breakpoint tables, community tools, and additional builds.
> Validated 2026-03-09: 12 GL builds machine-scraped (scraper now in `hadrons-blessing` repo) — full talent trees, perks, blessings corrected.
> Bot tags updated 2026-03-11: removed stale `BOT:NO_DODGE` (bots dodge natively), `BOT:NO_PERIL_MGT` (BetterBots v0.5.0 overheat bridge), `BOT:ABILITY_MISSING` (all abilities have heuristics). New tags: `BOT:ABILITY_UNVALIDATED` (DLC-blocked), `BOT:NO_BLITZ` (blitz unsupported), `BOT:DODGE_CENTRIC_PLAYSTYLE` (build relies on dodge-chaining beyond vanilla bot capability).
> Talent classification fixed 2026-03-11: split `Keystones:` into `Ability:` (combat ability + hex_frame modifiers) and `Keystones:` (actual passive keystones from circular_frame, identified via decompiled talent tree). Previous scraper mapped hex_frame → "keystone" but hex_frame = ability section on GL.
> Purpose: inform bot AI ability/weapon profiles for BetterBots mod.
> Cross-references: `classes/*.md` (ability templates), `classes/*-tactics.md` (heuristic rules), `knowledge/` (game system data)

---

## Class Tier Ranking (Havoc 40)

| Tier | Class | Notes |
|------|-------|-------|
| S | Hive Scum | Crazy mobility, high DPS, unlimited ammo, ranged immunity via Desperado |
| S | Psyker | Jack of all trades, bubble shield is S-tier team support |
| A | Veteran | Weakest individually but Voice of Command + Survivalist = best team support |
| A | Ogryn | Taunt + boss damage, toughness regen issues at highest difficulty |
| B | Arbites | Strong stagger/tank but selfish, lacks team synergy vs Ogryn |
| C | Zealot | Controversial; some tier lists put at A. Chorus is S-tier ability but class competes with Hive Scum for melee slot |

---

## Meta Team Composition (Havoc 40)

**Standard meta comp:**
1. **Veteran** -- Voice of Command, Survivalist, Plasma Gun (special sniper + ammo generator)
2. **Zealot** -- Chorus of Spiritual Fortitude, Blazing Piety, Relic Blade/Duelling Sword + Flamer (frontline + team toughness)
3. **Psyker** -- Telekine Shield (Dome), Warp Siphon, Brain Rupture, Inferno Staff (support + horde clear)
4. **Ogryn** -- Loyal Protector (Taunt), Heavy Hitter, Pickaxe + Heavy Stubber (tank + boss damage)

**Alternative 4th slot:** Second Zealot (Chorus), Arbites (Break the Line), or Hive Scum (Enhanced Desperado)

---

## VETERAN

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Voice of Command** | `veteran_combat_ability` | S | `stance_pressed` | AoE stagger + team buffs. Dominates Havoc meta. |
| **Executioner's Stance** | `veteran_combat_ability` | B | `stance_pressed` | +25% ranged damage, +25% weakspot for 5s. High skill floor. |
| **Infiltrate** | `veteran_stealth_combat_ability` | B | `stance_pressed` | Stealth for repositioning/revives. Less team value than VoC. |

Note: VoC and Executioner's share `veteran_combat_ability` template -- need `class_tag` detection to branch.

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Krak Grenade** | `veteran_krak_grenade` (no `ability_template`) | Default for Havoc. One-shots Crushers/Bulwarks. |
| **Shredder Frag** | `veteran_frag_grenade` (no `ability_template`) | Better with single-target ranged (plasma). Crowd control + bleed. |
| **Smoke Grenade** | `veteran_smoke_grenade` (no `ability_template`) | Niche damage avoidance. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Weapon Specialist** | Most popular. Attack speed buff, flexible melee/ranged hybrid. |
| **Focus Target** | Alternative for boss-focused play. Faster boss kills. |
| **Marksman's Focus** | Ranged-only builds. Less common in Havoc. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Maccabian Mk IV Duelling Sword | Achlys Mk VI Power Sword, Power Falchion |
| Ranged | M35 Magnacore Mk II Plasma Gun | Locke Mk IIb Spearhead Boltgun, Accatran Mk XIV Recon Lasgun |

**Available melee archetypes:** Combat Axes, Combat Knives, Combat Swords, Power Swords, Chain Axes, Chain Swords, Power Mauls
**Available ranged archetypes:** Autoguns, Lasguns, Stub Revolvers, Autopistols, Las Pistols, Bolt Pistols, Bolters, Plasma Guns, Shotguns

### Build Archetypes

1. **VoC Plasma** (most popular): Voice of Command + Weapon Specialist + Duelling Sword + Plasma Gun + Krak
2. **VoC Bolter**: Voice of Command + Weapon Specialist + Duelling Sword + Boltgun + Shredder Frag
3. **Stealth Operative**: Infiltrate + Combat Blade + Recon Lasgun
4. **Executioner Sniper**: Executioner's Stance + Focus Target + Heavy Sword + Helbore Lasgun

### Community Builds (Games Lantern)

**Veteran Squad Leader** (seventhcodex) — [GL link](https://darktide.gameslantern.com/builds/9a565016-bd70-4fe0-8c82-1080bc73412e/veteran-squad-leader)
- Ability: Voice of Command (modifiers: Duty and Honour)
- Keystones: Focus Target
- Notables: Shredder Frag Grenade
- Aura: Survivalist
- Talents: Exploit Weakness, Skirmisher, Desperado, Reciprocity, Serrated Blade, Trench Fighter Drill, Catch a Breath, Exhilarating Takedown, Grenade Tinkerer, Born Leader, Demolition Stockpile, Superiority Complex, Tactical Awareness, Confirmed Kill, Close Order Drill, Longshot, Precision Strikes, Bring it Down, Iron Will, Focus Target, Redirect Fire
- Stats: Toughness ×2, Stamina, Melee Damage, Ranged Damage
- Melee: Lawbringer Mk IIb Power Falchion -- Cranial Grounding, Heatsink (+Flak, +Maniacs)
- Ranged: M35 Magnacore Mk II Plasma Gun -- Rising Heat, Gets Hot! (+Maniacs, +Unyielding)
- Curios: 2x Blessed Bullet +Toughness, 1x +Health; Sniper DR, Gunner DR
- Playstyle: VoC is the core tool: "Use this reflexively and often — the best practice is *preventing* damage, not replenishing toughness after the fact." Shield team during pushes through hordes or into open spaces. Duty and Honour converts VoC into +50 overheal for team. Shredder Frag is CC, not damage: "toss nearest the toughest targets in a horde (ragers, maulers, crushers) — a tool you can and *should* abuse for every tough encounter." Plasma Gun: Gets Hot is "the PG's anchor blessing," ~8s reload, ~4s full vent, 3 charged shots before venting. Focus Target: prioritize toughest enemy first, always max stacks on monstrosities.
- **Rating: S (33/35)** — Perk: 5, Blessing: 5, Talent: 5, Breakpoint: 4, Curio: 5, Role: 5, Difficulty: 4 | Bot: BOT:AIM_DEPENDENT, BOT:ABILITY_OK

**Assault Veteran** (Graf) — [GL link](https://darktide.gameslantern.com/builds/a0461ea4-4701-473d-ba0d-cb8b91fd3479/assault-veteran)
- Ability: Infiltrate (modifiers: Hunter's Resolve)
- Keystones: Weapons Specialist
- Notables: Shredder Frag Grenade
- Aura: Survivalist
- Talents: Demolition Team, Exploit Weakness, Out For Blood, Skirmisher, Desperado, Reciprocity, Agile Engagement, Trench Fighter Drill, Catch A Breath, Grenade Tinkerer, Demolition Stockpile, Field Improvisation, Superiority Complex, Tactical Awareness, Confirmed Kill, Close Order Drill, Bring It Down, Iron Will, Weapons Specialist, Always Prepared, One Motion
- Stats: Toughness ×2, Stamina, Melee Damage
- Melee: Lawbringer Mk IIb Power Falchion -- Energy Leakage, Cranial Grounding (+Flak, +Maniacs)
- Ranged: M35 Magnacore Mk II Plasma Gun -- Gets Hot!, Rising Heat (+Carapace, +Unyielding)
- Curios: 2x Blessed Bullet +Toughness, 1x +Health; Combat Ability Regen, Gunner DR, Stamina Regen
- Playstyle: "Vanguard style — frontliner/backline diver depending on team comp." "You see horde, you melee horde. You see Crusher/Bulwark/Reaper you shoot. Any specialist you shoot in the face with extreme prejudice." Infiltrate for "cheeky rat" plays — stealth revives, backline dives, or cosplaying the Undertaker. Hunter's Resolve over Low Profile: "you already gave aggro to teammates after popping ability, so tank a bit like a man." Can swap to VoC + Duty and Honour "but you'll be locked to the frontline completely."
- **Rating: A (29/35)** — Perk: 5, Blessing: 5, Talent: 4, Breakpoint: 4, Curio: 4, Role: 4, Difficulty: 3 | Bot: BOT:NO_POSITIONING, BOT:ABILITY_OK

**Slinking Veteran** (dopeslinker) — [GL link](https://darktide.gameslantern.com/builds/a0d307bf-c6b5-4270-9492-e142e61d2722/slinking-veteran)
- Ability: Executioner's Stance (modifiers: Marksman, The Bigger They Are)
- Keystones: Marksman's Focus
- Notables: Shredder Frag Grenade
- Aura: Survivalist
- Talents: Demolition Team, Catch A Breath, Kill Zone, Shock Trooper, Exhilarating Takedown, Demolition Stockpile, Field Improvisation, Superiority Complex, Tactical Awareness, Confirmed Kill, Close Order Drill, Longshot, Precision Strikes, Bring It Down, Fully Loaded, Iron Will, Marksman's Focus, Tunnel Vision, Long Range Assassin, One Motion
- Stats: Toughness ×2, Stamina, Stamina Regen, Melee Damage, Ranged Damage
- Melee: Catachan Mk VII "Devil's Claw" Sword -- Rampage, Wrath (+Flak, +Unarmoured)
- Ranged: Lucius Mk IV Helbore Lasgun -- Hot-Shot, Surgical (+Carapace, +Unyielding)
- Curios: 1x +Toughness, 1x +Health, 1x +Stamina; Revive Speed, Stamina Regen
- Playstyle: Minimal author prose. Ranged sniper — Executioner's + Marksman's Focus for elite/special deletion at range. Helbore charged shots one-shot most specials. Talent swap note: can drop Exhilarating Takedown/One Motion/Longshot for Grenadier with Shredder Frag, or take Krak/Smoke + Grenade Tinkerer.
- **Rating: A (28/35)** — Perk: 5, Blessing: 4, Talent: 5, Breakpoint: 5, Curio: 3, Role: 3, Difficulty: 3 | Bot: BOT:AIM_DEPENDENT, BOT:NO_WEAKSPOT, BOT:ABILITY_OK

---

## ZEALOT

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Chorus of Spiritual Fortitude** | (no `ability_template` -- Tier 3 item: `preacher_relic`) | S | wield/use sequence | Relic pulses toughness, overheals to +100, pushes enemies including bosses. Best team ability. |
| **Fury of the Faithful (Dash)** | `zealot_dash` | A | `aim_pressed` -> `aim_released` | Forward dash + damage buff. Good aggressive frontline. |
| **Shroudfield (Stealth)** | `zealot_invisibility` | B | `stance_pressed` | Stealth for repositioning/revives. Single-target offense. |

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Blades of Faith** | `zealot_throwing_knives` (no `ability_template`) | Meta choice. Throwing knives for picking specialists/elites at range. |
| **Stunstorm Grenade** | `zealot_shock_grenade` (no `ability_template`) | 8s stun in 8m. Panic button / CC. |
| **Immolation Grenade** | `zealot_fire_grenade` (no `ability_template`) | Area denial fire (friendly fire safe). Chokepoints. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Blazing Piety** | Most popular. Crit stacking. Standard for Chorus builds. |
| **Inexorable Judgement** | More economical with Shroudfield. |
| **Martyrdom** | Niche. Low-health damage scaling. Thunder hammer boss builds. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Maccabian Mk IV Duelling Sword, Munitorum Mk X Relic Blade | Crucis Mk II Thunder Hammer, Tigrus Mk XV Heavy Eviscerator |
| Ranged | Artemia Mk III Purgation Flamer | Godwyn-Branx Mk IV Bolt Pistol |

**Available melee archetypes:** Combat Axes, Combat Knives, Combat Swords, Power Mauls (2H), Chain Swords, Chain Axes, Thunder Hammers (2H), Power Swords (2H)
**Available ranged archetypes:** Autoguns, Shotguns, Stub Revolvers, Las Pistols, Bolt Pistols, Flamers, Bolters, Lasguns

### Build Archetypes

1. **Chorus Crit** (most popular): Chorus + Blazing Piety + Relic Blade + Flamer + Blades of Faith
2. **Chorus Duelling**: Chorus + Blazing Piety + Duelling Sword + Flamer/Bolt Pistol
3. **Stealth Assassin**: Shroudfield + Inexorable Judgement + Combat Blade + Bolt Pistol
4. **Martyrdom Boss Killer**: Dash + Martyrdom + Thunder Hammer + Flamer

### Community Builds (Games Lantern)

**Spicy's Meta Havoc 40 Zealot** (randomspicy) — [GL link](https://darktide.gameslantern.com/builds/9ede2ba5-850b-41d0-9325-4f42cddf9836/spicys-meta-havoc-40-zealot)
- Ability: Chorus of Spiritual Fortitude (modifiers: Ecclesiarch's Call)
- Keystones: Blazing Piety
- Notables: Blades of Faith
- Aura: Beacon of Purity
- Talents: Scourge, Backstabber, Purge the Unclean, Anoint in Blood, Enduring Faith, Second Wind, Duellist, Until Death, Holy Revenant, Thy Wrath be Swift, Good Balance, Faithful Frenzy, Sustained Assault, Invocation of Death, Blazing Piety, Stalwart, Righteous Warrior, Infectious Zeal, Providence, Abolish Blasphemers, Prime Target, Against the Odds
- Stats: Melee Damage ×2, Toughness DR, Toughness
- Melee: Munitorum Mk X Relic Blade -- Heatsink, Cranial Grounding (+Carapace, +Melee Elites)
- Ranged: Artemia Mk III Purgation Flamer -- Blaze Away, Penetrating Flame (+Carapace, +Flak)
- Curios: 2x Blessed Bullet +Toughness, 1x +Health; Combat Ability Regen, Gunner DR, Block Efficiency, Stamina Regen
- Playstyle: "Your role is to pick out Elites, hold the line, and give ranged characters space." "In Havoc, your squad doesn't benefit from you zipping around and surviving while they struggle with heretics. Get involved!" "This is when you become a support character. Stay with the squad, kill what's ailing them." "Live with the team, die with the team!" Relic Blade: "best weapon for swarms with great cleave, while still offering excellent single-target damage — can safely chain attacks where other weapons force block+retreat." Flamer: "unrivaled mixed crowd damage with unstoppable AOE." Sprint-charge heavy for guaranteed high single-target strike attack. Book (Chorus) cooldown is longer now: "be selective but don't save it like a medipack."
- **Rating: S (32/35)** — Perk: 5, Blessing: 5, Talent: 5, Breakpoint: 4, Curio: 3, Role: 5, Difficulty: 5 | Bot: BOT:ABILITY_OK

**Fatmangus Zealot Stealth** (dopeslinker) — [GL link](https://darktide.gameslantern.com/builds/a0d300f6-9d15-4766-bab5-76122e9477f7/fatmangus-zealot-stealth-version)
- Ability: Shroudfield (modifiers: Master Crafted Shroudfield, Invigorating Revelation)
- Keystones: Inexorable Judgement
- Notables: Blades of Faith
- Aura: Beacon of Purity
- Talents: Backstabber, Purge the Unclean, Second Wind, Restoring Faith, Bleed for the Emperor, Duellist, Shield of Contempt, Until Death, Holy Revenant, Thy Wrath be Swift, Good Balance, Faith's Fortitude, Sustained Assault, Pious Cut-Throat, Inexorable Judgement, Inebriate's Poise, The Master's Retribution, Riposte, Providence, Hubris, Time to Kill
- Stats: Toughness DR, Melee Damage, Toughness, Movement Speed
- Melee: Munitorum Mk II Relic Blade -- Wrath, Overload (+Flak, +Unyielding)
- Ranged: Locke Mk III Spearhead Boltgun -- Pinning Fire, Puncture (+Maniacs, +Unyielding)
- Curios: 3x +Health; Revive Speed, Gunner DR, Stamina Regen
- Playstyle: Minimal author prose. Stealth assassin. Talent swap options: Master's Retribution for Perfectionist/Eternal/Faithful Frenzy/Abolish Blasphemers/Unseen Blade. Breakpoint note: "You need +Flak on your Relic Blade to one shot H40 Captains."
- **Rating: B (26/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 4, Curio: 3, Role: 3, Difficulty: 3 | Bot: BOT:NO_POSITIONING, BOT:ABILITY_OK


**Holy Gains Havoc 40** (charname) — [GL link](https://darktide.gameslantern.com/builds/9d2b5a53-1975-4850-8041-0bc911ac4efc/holy-gains-havoc-40)
- Ability: Fury of the Faithful (modifiers: Redoubled Zeal, Unrelenting Fury)
- Keystones: Martyrdom
- Notables: Stunstorm Grenade
- Aura: Benediction
- Talents: Disdain, Purge the Unclean, Enduring Faith, Second Wind, Restoring Faith, Until Death, Holy Revenant, Good Balance, Enemies Within Enemies Without, Faithful Frenzy, Martyr's Purpose, Faith's Fortitude, Martyrdom, I Shall Not Fall, Maniac, Sustained Assault, Restorative Verses, Providence, Abolish Blasphemers, Prime Target, Against the Odds
- Stats: Melee Damage ×2, Toughness DR, Toughness
- Melee: Tigrus Mk XV Heavy Eviscerator -- Wrath, Bloodthirsty (+Unyielding, +Carapace)
- Ranged: Godwyn-Branx Mk IV Bolt Pistol -- Lethal Proximity, Puncture (+Flak, +Maniacs)
- Curios: 3x Blessed Bullet +Wounds; Combat Ability Regen, Stamina Regen, Gunner DR
- Playstyle: Minimal author prose. "Not meta but after buffs to Martyrdom and Eviscerators it's viable and fun." Bloodthirsty on Eviscerator to chain heavy specials and dismember Crusher packs. Tigrus Mk III also fun but lacks crusher one-shots.
- **Rating: A (28/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 4, Curio: 4, Role: 4, Difficulty: 3 | Bot: BOT:ABILITY_OK

**Zealot Infodump No Stealth Auric** (Razgriz) — [GL link](https://darktide.gameslantern.com/builds/9a4fa304-0b88-4cf8-827a-d0435327a8c3/zealot-infodump-no-stealth-auric)
- Ability: Fury of the Faithful (modifiers: Redoubled Zeal)
- Keystones: Blazing Piety
- Notables: Immolation Grenade
- Aura: Beacon of Purity
- Talents: Blood Redemption, Scourge, Backstabber, Purge the Unclean, Anoint in Blood, Enduring Faith, Second Wind, Bleed for the Emperor, Dance of Death, Duellist, Shield of Contempt, Until Death, Holy Revenant, Thy Wrath be Swift, Good Balance, Sustained Assault, Invocation of Death, Blazing Piety, Unseen Blade, Blinded by Blood, Providence, Prime Target
- Stats: Melee Damage ×2, Toughness DR, Toughness
- Melee: Maccabian Mk IV Duelling Sword -- Uncanny Strike, Riposte (+Flak, +Unyielding)
- Ranged: Agripinaa Mk VIII Braced Autogun -- Inspiring Barrage, Speedload (+Flak, +Maniacs)
- Curios: 3x Blessed Bullet +Health; Sniper DR, Gunner DR, Tox Flamer DR, Corruption Resistance
- Playstyle: Full guide. "Defense > Offense in Darktide. Always prioritize defensive talents." "Zealot's strength comes from the ability to weasel out of impossible situations — guaranteed death for any other class." Duelling Sword with Uncanny Strike + Riposte: "annihilates any enemy regardless of armor — Crushers and Maulers die in 3 seconds with buffs active. This weapon is BROKEN." Braced Autogun with Inspiring Barrage: "having 10x the average toughness regen throughout the match is better than ~15-20% more ranged damage — effectively removes non-elite shooters as a threat." On FotF: Redoubled Zeal for reset on kill within 5s. Curios: Health > Toughness at high skill because "burst damage instantly zeros toughness regardless of stack size — Health is a buffer against bad luck."
- **Rating: A (30/35)** — Perk: 5, Blessing: 5, Talent: 5, Breakpoint: 4, Curio: 3, Role: 4, Difficulty: 4 | Bot: BOT:DODGE_CENTRIC_PLAYSTYLE, BOT:ABILITY_OK

---

## PSYKER

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Telekine Shield (Dome)** | (no `ability_template` -- Tier 3 item: `psyker_shield`) | S | wield/use sequence | Blocks ranged+melee, toughness regen inside dome, +50% toughness DR on dissipate. |
| **Venting Shriek** | `psyker_shout` | A | `shout_pressed` -> `shout_released` | AoE damage + peril vent. Best with Creeping Flames (soulblaze through walls). |
| **Scrier's Gaze** | `psyker_overcharge_stance` | B | `stance_pressed` | +10% damage, +20% crit, suppression immunity. Risk of overcharge (#27). |

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Brain Rupture** | `psyker_smite` (no `ability_template`) | Meta default. High single-target damage. Slow charge. |
| **Smite** | (no `ability_template`) | Crowd control chain-stun. Area lockdown. |
| **Assail** | `psyker_throwing_knives` (no `ability_template`) | Mobile stun + damage. |
| **Chain Lightning** | `psyker_chain_lightning` (no `ability_template`) | AoE damage. Less popular at highest difficulty. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Warp Siphon** | Most popular. Warp charge stacking. Standard for Dome builds. |
| **Empowered Psionics** | Alternative for soulblaze/staff builds. |
| **Disrupt Destiny** | Niche. Crit-focused Assail builds. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Deimos Mk IV Blaze Force Sword | Covenant Mk VIII Blaze Force Greatsword, Obscurus Mk 2 Blaze Force Sword |
| Ranged | Rifthaven Mk II Inferno Force Staff | Equinox Mk III Voidblast Force Staff, Nomanus Mk VI Electrokinetic Force Staff |

**Available melee archetypes:** Combat Axes, Combat Swords, Combat Knives, Force Swords, Force Swords (2H), Chain Swords, Chain Axes, Power Mauls
**Available ranged archetypes:** Autoguns, Lasguns, Force Staffs (4 variants), Las Pistols, Bolt Pistols, Stub Revolvers, Shotguns, Autopistols

### Build Archetypes

1. **Bubble Support** (most popular): Telekine Shield (Dome) + Warp Siphon + Brain Rupture + Inferno Staff + Blaze Force Sword
2. **Soulblaze DPS**: Venting Shriek + Empowered Psionics + Brain Rupture + Inferno Staff
3. **Scrier Gun Psyker**: Scrier's Gaze + Warp Siphon + Assail + Voidblast Staff
4. **Smite Controller**: Venting Shriek + Warp Siphon + Smite + Surge/Trauma Staff

### Community Builds (Games Lantern)

**Gandalf: Melee Wizard** (nomalarkey) — [GL link](https://darktide.gameslantern.com/builds/9da62e0d-1e0f-4d9b-adca-a60b3809dd98/gandalf-melee-wizard-updated-for-bound-by-duty)
- Keystones: Disrupt Destiny (+ Lingering Influence modifier)
- Ability: Scrier's Gaze (modifiers: Precognition, Warp Unbound)
- Notables: Kinetic Flayer, Brain Rupture
- Aura: Psykinetic's Aura
- Talents: Mettle, Perilous Combustion, Battle Meditation, Perfect Timing, Prescience, Malefic Momentum, One with the Warp, Empathic Evasion, Warp Rider, Kinetic Deflection, Disrupt Destiny, Lingering Influence, Lightning Speed, Warp Splitting, Souldrinker, Warp Expenditure, Warp Ghost
- Stats: Movement Speed, Toughness ×2, Melee Damage, Stamina, Toughness DR, Critical Chance
- Melee: Covenant Mk VI Blaze Force Greatsword -- Blazing Spirit, Shred (+Unyielding, +Carapace)
- Ranged: Equinox Mk III Voidblast Force Staff -- Warp Nexus, Warp Flurry (+Carapace, +Flak)
- Curios: 3x Blessed Bullet +Toughness; Combat Ability Regen, Stamina Regen, Sprint Efficiency
- Playstyle: "Play like a crit Zealot — a warp-fueled murder-hobo." Melee-primary, staff only for emergency CC "when the director flips out and it's not safe to just chop and dodge." Spam Scrier's Gaze aggressively: "You aren't going to 'waste' this ability even if you only secure a few kills. It still makes you stronger, more safe, and with the reduced cooldown it will be right back." Warp Ghost keeps peril intentionally high for Warp Splitting/Warp Rider buffs. 60%+ crit during Scrier's → Soulblaze on everything → toughness regen loop is self-sustaining. Use heavy attacks to one-shot, slide-cancel for chains. Sword special staggers + auto-kills specials via Kinetic Flayer in mixed hordes.
- **Rating: B (26/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 3, Curio: 3, Role: 4, Difficulty: 3 | Bot: BOT:ABILITY_OK

**Electrodominance Havoc 40 Scrier Smiter** (Magnafanta) — [GL link](https://darktide.gameslantern.com/builds/9fe8da5a-85d2-4193-a584-e47a6a8b5135/electrodominance-havoc-40-scrier-smiter)
- Keystones: Empowered Psionics
- Ability: Scrier's Gaze (modifiers: Precognition, Warp Unbound)
- Notables: Smite, Enfeeble
- Aura: Psykinetic's Aura
- Talents: Soulstealer, Quietude, Mettle, Perilous Combustion, Perfect Timing, Kinetic Presence, Wildfire, One with the Warp, Warp Rider, Puppet Master, Empowered Psionics, Bio-Lodestone, Psychic Leeching, Charged Up, Souldrinker, Immaterial Focus
- Stats: Toughness ×2, Ranged Damage, Melee Damage, Stamina, Toughness DR, Peril Resistance, Critical Chance
- Melee: Covenant Mk VIII Blaze Force Greatsword -- Momentum, Deflector (+Flak)
- Ranged: Nomanus Mk VI Electrokinetic Force Staff -- Warp Flurry, Warp Nexus (+Unyielding, +Carapace)
- Curios: 2x Blessed Bullet +Toughness, 1x +Health; Gunner DR, Corruption Resistance
- Playstyle: Minimal author prose. WARNING: "DO NOT use this build for Final Toll condition!" Scrier's Gaze + Electro Staff + Smite CC. Greatsword with Momentum/Deflector for melee survivability.
- **Rating: A (28/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 4, Curio: 4, Role: 4, Difficulty: 3 | Bot: BOT:ABILITY_OK

**Electro Shriek Big Damage** (Mizumelon) — [GL link](https://darktide.gameslantern.com/builds/9ff2a0e7-4008-4f0d-a00c-25b16773c9e0/electro-shriek-big-damage-psykers-squishy-just-delete-everything)
- Ability: Venting Shriek (modifiers: Becalming Eruption, Creeping Flames)
- Keystones: Warp Siphon
- Notables: Kinetic Flayer, Brain Rupture
- Aura: Psykinetic's Aura
- Talents: Quietude, Mettle, Perilous Combustion, Perfect Timing, Seer's Presence, Wildfire, One with the Warp, Solidity, Warp Rider, Warp Siphon, Essence Harvest, Psychic Vampire, Warp Battery, Souldrinker, Empyric Resolve, Penetration of the Soul, Vulnerable Minds
- Stats: Toughness DR ×2, Toughness ×2, Ranged Damage, Stamina, Critical Chance
- Melee: Covenant Mk VIII Blaze Force Greatsword -- Shred, Wrath (+Infested, +Unarmoured)
- Ranged: Nomanus Mk VI Electrokinetic Force Staff -- Warp Nexus, Warp Flurry (+Flak, +Unyielding)
- Curios: 2x Blessed Bullet +Toughness, 1x +Stamina; Combat Ability Regen, Gunner DR
- Playstyle: "Simple — half charge almost everything. Not much difference in DPS between full charge and half charge. Full charge monstrosities/bosses, half charge everything else." At critical peril, face thickest horde/monster and Venting Shriek — Creeping Flames soulblaze "can normally delete most hordes on your screen." Soulblaze scales exponentially with stacks: 3 stacks = single digits, 6 = 50+, 9 = 120+, 12 = 200+ per tick. Kill elites near monsters to stack soulblaze on them. Melee is emergency only: push first to stagger, then block, then attack. Slide+reload for mobility, slide+half-charge for 180° zaps. Staff is "aimbot weapon" — sweep screen to find targets. Empyric Resolve mandatory: "without this, the staff feels like a peril hog." Quietude over Soulstealer for solo boss scenarios with no adds.
- **Rating: A (31/35)** — Perk: 5, Blessing: 4, Talent: 5, Breakpoint: 4, Curio: 4, Role: 5, Difficulty: 4 | Bot: BOT:ABILITY_OK

---

## OGRYN

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Loyal Protector (Taunt)** | `ogryn_taunt_shout` | S | `shout_pressed` -> `shout_released` | Taunts 12m for 15s. Boss aggro + Valuable Distraction damage amp. 50s CD. |
| **Bull Rush (Indomitable)** | `ogryn_charge` | A | `aim_pressed` -> `aim_released` | Charge through enemies. Counts as dodging (blocks dogs/nets/bullets). 30s CD. |
| **Point-Blank Barrage** | `ogryn_gunlugger_stance` | B | `stance_pressed` | +25% fire rate, +65% reload, +15% close damage for 10s. 80s CD = conservative. |

Charge variants: `ogryn_charge_cooldown_reduction`, `ogryn_charge_damage`, `ogryn_charge_increased_distance`, `ogryn_charge_bleed`

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Big Friendly Rock** | `ogryn_grenade_friend_rock` (no `ability_template`) | Default meta. One-shots Pox Hounds, Poxbursters, Mutants, gunners. 4 charges, 45s CD. |
| **Frag Bomb** | `ogryn_grenade_frag` (no `ability_template`) | Single nuke for emergency / boss ledging. 1 charge. |
| **Bombs Away** | `ogryn_grenade_box` / `ogryn_grenade_box_cluster` (no `ability_template`) | Area control + horde clear. 3 charges. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Heavy Hitter** | ~80% of builds. Damage scaling. Unstoppable + Don't Feel a Thing. |
| **Feel No Pain** | Learning/survival. 25% toughness regen with Toughest modifier. |
| **Burst Limiter Override** | Ranged specialist. Essential for sustained-fire builds. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Brunt's Basher Mk IIIb Bully Club, Borovian/Branx Mk Ia Delver's Pickaxe | Orox Mk II Battle Maul & Slab Shield, Krourk Mk IV Cleaver |
| Ranged | Lorenz Mk VI Rumbler | Achlys Mk II/VII Heavy Stubber, Foe-Rend Mk V Ripper Gun |

**Available melee archetypes:** Ogryn Clubs, Ogryn Powermauls, Ogryn Powermaul + Shield, Ogryn Pickaxes (2H), Ogryn Combat Blades
**Available ranged archetypes:** Ogryn Thumpers, Ogryn Rippergun, Ogryn Gauntlets, Ogryn Heavy Stubbers

### Build Archetypes

1. **Taunt Tank** (most popular): Loyal Protector + Heavy Hitter + Pickaxe + Heavy Stubber + Big Friendly Rock
2. **Shield Tank**: Loyal Protector + Heavy Hitter + Battle Maul & Slab Shield + Rumbler + Frag Bomb
3. **Bull Rush Melee**: Bull Rush + Heavy Hitter + Bully Club + Ripper Gun + Big Friendly Rock
4. **Dakka Ogryn**: Point-Blank Barrage + Burst Limiter Override + Pickaxe + Heavy Stubber

### Community Builds (Games Lantern)

**Mister E's Explodegryn** (Mister E) — [GL link](https://darktide.gameslantern.com/builds/9e632ca3-292b-4721-af64-2230bca819bf/mister-es-explodegryn)
- Ability: Loyal Protector (modifiers: Valuable Distraction, No Pain)
- Keystones: Burst Limiter Override
- Notables: Bombs Away
- Talents: Smash 'Em, Steady Grip, Heavyweight, Reloaded and Ready, Coward Culling, Soften Them Up, Pacemaker, Ammo Stash, Burst Limiter Override, Maximum Firepower, Bruiser, Get Stuck In, Payback Time, Big Boom, Unstoppable Momentum, No Hurting Friends, Fire Away, Pumped Up, Keep Shooting, Back Off
- Stats: Toughness ×3, Reload, Toughness DR, Ranged Damage
- Melee: Achlys Mk I Power Maul -- Power Surge, Skullcrusher (+Carapace, +Flak)
- Ranged: Lorenz Mk VI Rumbler -- Shattering Impact, Adhesive Charge (+Carapace, +Unyielding)
- Curios: 3x Blessed Bullet +Toughness; Combat Ability Regen, Gunner DR, Stamina Regen
- Playstyle: "Possibly the strongest build in Havoc 2.0? Club lesser enemies for easy stacks, when things get hot, use taunt to group and drag enemies into tight formation, then delete with multiple grenade shots." Boss combo: melee x4 → shoot grenade into boss → taunt so boss is staggered when grenades explode for massive damage. "Run with a vet for ammo regen and a chorus zealot for perma stagger to bosses for maximum damage and survivability."
- **Rating: A (29/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 4, Curio: 4, Role: 4, Difficulty: 4 | Bot: BOT:ABILITY_OK


**Havoc 40 Ogryn Shield Tank** (Jay-Brodi) — [GL link](https://darktide.gameslantern.com/builds/a006d28e-3024-4c8b-b73f-b57383335a8a/dec-2025-havoc-40-ogryn-shield-tank-build-for-the-liluns)
- Ability: Loyal Protector (modifiers: Valuable Distraction, No Pain)
- Keystones: Feel No Pain
- Notables: Frag Bomb
- Talents: The Best Defence, Smash 'Em, Heavyweight, Bonebreaker's Aura, Slam, Soften Them Up, Batter, Hard Knocks, Feel No Pain, Implacable, Delight in Destruction, Toughest, Bruiser, No Stopping Me, No Pushover, Attention Seeker, No Hurting Friends, Focused Fighter, Brutish Strength, Strongman, Strike True
- Stats: Toughness ×3, Toughness DR, Melee Damage
- Melee: Orox Mk II Battle Maul & Slab Shield -- Brutal Momentum, Skullcrusher (+Carapace, +Flak)
- Ranged: Lorenz Mk VI Rumbler -- Adhesive Charge, Shrapnel (+Carapace, +Unyielding)
- Curios: 3x Blessed Bullet +Toughness; Gunner DR, Combat Ability Regen, Corruption Resistance
- Playstyle: Minimal on-page prose — all strategy in linked YouTube videos. Shield-wall frontliner with Feel No Pain + Toughest for permanent toughness regen. Debuff shield variant focused on elite/boss suppression.
- **Rating: A (31/35)** — Perk: 5, Blessing: 4, Talent: 5, Breakpoint: 3, Curio: 4, Role: 5, Difficulty: 5 | Bot: BOT:ABILITY_OK

**Shovel Ogryn** (dopeslinker) — [GL link](https://darktide.gameslantern.com/builds/a0e74df0-681b-49b1-bcbd-0483d2c0e12a/shovel-ogryn-2)
- Ability: Bull Rush (modifiers: Indomitable, Stomping Boots)
- Keystones: Heavy Hitter
- Notables: Big Friendly Rock, That One Didn't Count
- Talents: The Best Defence, Smash 'Em, Heavyweight, Bonebreaker's Aura, Slam, Soften Them Up, Batter, Delight in Destruction, Heavy Hitter, Just Getting Started, Bruiser, No Pushover, No Hurting Friends, For the Lil'uns, Pumped Up, Frenzied Blows, Beat Them Back, Impactful, Dedicated Practice, Strike True
- Stats: Toughness ×2, Rending, Toughness DR ×2, Melee Damage
- Melee: Brute-Brainer Mk III Latrine Shovel -- Skullcrusher, Thunderous (+Flak, +Unyielding)
- Ranged: Foe-Rend Mk V Ripper Gun -- Inspiring Barrage, Blaze Away (+Flak, +Maniacs)
- Curios: 1x +Health, 2x +Toughness; Revive Speed, Health, Gunner DR
- Playstyle: Minimal prose. Bull Rush melee brawler. Shovel for horde/elite, Rock for specials. Boss tech: "Stunlock Chaos Spawn/Daemonhost by charging into them then H1 > L1 > Punch repeat." Inspiring Barrage Ripper Gun "is epic and balanced." Swap Beat Them Back/Frenzied Blows/For the Lil'Uns/That One Didn't Count for Steady Grip if using Heavy Stubber/Grenade Gauntlet/Kickback.
- **Rating: B (25/35)** — Perk: 5, Blessing: 3, Talent: 4, Breakpoint: 4, Curio: 3, Role: 3, Difficulty: 3 | Bot: BOT:ABILITY_OK

---

## ARBITES

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Break the Line** | `adamant_charge` | S | `aim_pressed` -> `aim_released` | Forward dash + cone stagger. +25% damage, +50% impact for 6s. |
| **Nuncio-Aquila** | `adamant_area_buff_drone` (no `ability_template` — Tier 3 item) | A | wield/use sequence | Damage reduction, toughness regen, revive speed in AoE. |
| **Castigator's Stance** | `adamant_stance` | B | `stance_pressed` | Emergency toughness. Long CD, selfish. Melee-focused. |

Drone: `adamant_area_buff_drone` (no `ability_template` -- Tier 3 item, 100% reliability post-fix)

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Voltaic Shock Mine** | `shock_mine` (no `ability_template`) | Meta with Lone Wolf passive recharge. Chokepoint control. 2 charges. |
| **Cyber-Mastiff** | `adamant_whistle` (**only blitz with `ability_template`**) | Pounces elites/specials. Always pair with Remote Detonation. |
| **Arbites Grenade** | `adamant_grenade` (no `ability_template`) | Quick throw, can stagger/ledge bosses. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Forceful** | Most popular for melee. +5% impact, +2.5% DR per stagger stack (10 max). |
| **Execution Order** | Universal. 150% multiplicative damage bonus. Best with crit weapons. |
| **Terminus Warrant** | Avoid. Stacks lost on cleave. Needs buffs. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Branx Mk III Arbites Shock Maul | Branx Mk VI Shock Maul & Suppression Shield, Atrox Mk VII Tactical Axe |
| Ranged | Exaction Mk VIII Exterminator Shotgun | Godwyn-Branx Mk IV Bolt Pistol, Locke Mk IIb Spearhead Boltgun |

**Available melee archetypes:** Combat Axes, Power Mauls, Power Maul + Shield, Power Mauls (2H), Chain Swords
**Available ranged archetypes:** Autoguns, Shotguns, Stub Revolvers, Autopistols, Bolt Pistols, Bolters, Shotpistol + Shield

### Build Archetypes

1. **Melee Lone Wolf** (most popular): Break the Line + Forceful + Shock Maul + Exterminator Shotgun + Voltaic Shock Mine
2. **Immortal Provost**: Break the Line + Forceful + Shock Maul & Shield + Bolt Pistol + Shock Mine
3. **Cyber-Mastiff Hunter**: Nuncio-Aquila + Execution Order + Shock Maul + Exterminator Shotgun + Cyber-Mastiff
4. **Armor Support**: Nuncio-Aquila + Forceful + Shield + Shotgun

### Community Builds (Games Lantern)

**Execution Order Nuncio-Aquila** (fatherlyfigure) — [GL link](https://darktide.gameslantern.com/builds/9f35c673-7c83-4bd1-9d77-a25d7b19984d/execution-order-nuncio-aquila-arbites)
- Ability: Nuncio-Aquila (modifiers: Inspiring Recitation, Fear of Justice)
- Keystones: Execution Order
- Notables: Voltaic Shock Mine
- Talents: Part of the Squad, Execution Order, Man and Cyber-Mastiff, Withering Fire, Up Close, Force of Will, Walk it Off, Arbitrator Armour, Ammo Belt, Suppression Protocols, Imposing Force, Hold the Line, Plasteel Plates, Arbites Revelatum, Shield Plates, Malocator, No Lenience, Keeping Protocol, Zealous Dedication, Unleashed Brutality, Justified Measures, Suppression Force, Concussive, Target the Weak
- Stats: Toughness DR, Cleave
- Melee: Branx Mk VI Shock Maul & Suppression Shield -- High Voltage, Confident Strike (+Maniacs, +Carapace)
- Ranged: Judgement Mk IV Subductor Shotpistol & Riot Shield -- Full Bore, Fire Frenzy (+Maniacs, +Flak)
- Curios: 2x Gilded Inquisitorial Rosette, 1x Scrap of Scripture; +Toughness, Gunner DR, Health
- Playstyle: Roleplay-flavored prose, minimal mechanical strategy. "By the Lex, I bring judgment." Frontline shield tank. Target purple-marked (condemned) enemies for Execution Order procs: 50% CDR for 8s, 15% toughness replenishment, 10% rending for 8s, plus Keeping Protocol stacking damage/resistance. Shield Plates + Walk It Off for passive toughness regen. Aim for weakspots with Shock Maul for stagger.
- **Rating: A (27/35)** — Perk: 5, Blessing: 3, Talent: 4, Breakpoint: 3, Curio: 4, Role: 4, Difficulty: 4 | Bot: BOT:NO_BLOCK_TIMING, BOT:ABILITY_OK

**Arby's OP Melee Meta Havoc 40** (B-To-The-Ryan) — [GL link](https://darktide.gameslantern.com/builds/9f6108ec-d547-448f-b847-38fc0e21ccce/arbys-op-melee-meta-havoc-40)
- Ability: Break the Line (modifiers: Commendation from Condemnation, Targeted Brutality)
- Keystones: Forceful
- Notables: Voltaic Shock Mine
- Talents: Forceful, Breaking Dissent, Hammer of Judgement, Up Close, Force of Will, Walk it Off, Arbitrator Armour, Suppression Protocols, Lone Wolf, Will of the Lex, Targets Acquired, Arbites Vigilant, Hold the Line, Plasteel Plates, Arbites Revelatum, Soulguilt Scan, Drive Them Back, Zealous Dedication, Street Smarts, Monstrosity Hunter, The Emperor's Fist, Justified Measures, Concussive, Target the Weak
- Stats: Toughness DR, Impact
- Melee: Branx Mk III Arbites Shock Maul -- High Voltage, Relentless Strikes (+Flak, +Carapace)
- Ranged: Exaction Mk III Exterminator Shotgun -- Deathspitter, Sustained Fire (+Flak, +Maniacs)
- Curios: 3x Blessed Bullet +Toughness; Combat Ability Regen, Revive Speed, Stamina Regen
- Playstyle: "Strictly dogless melee — probably the most no-brainer meta for Havoc-40." "Mostly light spam with maul, heavy+light combos for armor/bosses (always aim for heads to proc passive nodes). Keep spamming lights, shoving for cleave into hordes, constantly charging into packs to stagger lock, then go ham." Mines on chokepoints or "for those pesky armies of crushers/maulers/ragers — mines just totally negate/surpass them." "You're the frontliner, the tank just like Ogryn. You need to be constantly in heretics' faces to upkeep Forceful stacks." Forceful over Execution Order: "stagger locking/being more tanky is of more value in Havoc-40's."
- **Rating: A (28/35)** — Perk: 5, Blessing: 3, Talent: 5, Breakpoint: 4, Curio: 3, Role: 4, Difficulty: 4 | Bot: BOT:ABILITY_OK


**BUSTED Havoc 40** (charname) — [GL link](https://darktide.gameslantern.com/builds/9f510b13-dfcc-4e7e-9850-7b868f140477/busted-havoc-40)
- Ability: Castigator's Stance
- Keystones: Execution Order
- Notables: Remote Detonation (Cyber-Mastiff)
- Talents: Part of the Squad, Execution Order, Up Close, Force of Will, Voltaic Mandibles Augment, Walk it Off, True Grit, Arbitrator Armour, Imposing Force, Hold the Line, Plasteel Plates, Arbites Revelatum, Soulguilt Scan, No Escape, Weight of the Lex, Malocator, Keeping Protocol, Zealous Dedication, Go Get 'Em, Street Smarts, Monstrosity Hunter, The Emperor's Fist, Canine Morale, Justified Measures, Concussive, Target the Weak
- Stats: Toughness DR, Cleave
- Melee: Branx Mk III Arbites Shock Maul -- Execution, High Voltage (+Carapace, +Unyielding)
- Ranged: Exaction Mk III Exterminator Shotgun -- Deathspitter, Execution (+Flak, +Maniacs)
- Curios: 3x Blessed Bullet +Toughness; Combat Ability Regen, Stamina Regen, Revive Speed, Gunner DR
- Playstyle: Minimal prose. "Almost immortal, very safe, good damage." Castigator's Stance over Break the Line: "doesn't require any talent points in ability modifier nodes — Break the Line needs Commendation from Condemnation and Targeted Brutality to really outclass it, so Castigator's frees two extra talent points for strong nodes." Cyber-Mastiff + Execution on both weapons for damage spikes.
- **Rating: A (27/35)** — Perk: 5, Blessing: 3, Talent: 4, Breakpoint: 4, Curio: 3, Role: 4, Difficulty: 4 | Bot: BOT:ABILITY_OK, BOT:NO_BLITZ

---

## HIVE SCUM (Broker)

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Enhanced Desperado** | `broker_focus` | S | `stance_pressed` | Infinite ammo, ranged immunity, highlight enemies. Kill extends +1s. 45s CD. |
| **Frenzied Rampage** | `broker_punk_rage` | A | `stance_pressed` | +50% melee strength, +20% attack speed, +25% DR for 10s. 30s CD. |
| **Stimm Supply** | (no `ability_template` -- Tier 3 item: `broker_stimm_field`) | B | wield/use sequence | Place medical crate, share stimm effects. 30s CD. Niche support. |

Syringe: `broker_ability_syringe` (pocketable item, 15-75s CD)

### Blitz/Grenades

| Blitz | Template | When to Use |
|-------|----------|-------------|
| **Chem Grenade** | `broker_tox_grenade` (no `ability_template`) | Meta default. Boss damage, area denial. |
| **Boom Bringer (Rocket)** | `broker_missile_launcher` (no `ability_template`) | Burst damage alternative. |
| **Flash Grenade** | `broker_flash_grenade` (no `ability_template`) | Weak without Pocket Toxin talent. |

### Keystones

| Keystone | Usage |
|----------|-------|
| **Float Like a Butterfly** | 40% melee crit chance. Dodge-heavy survivability. Standard for gunslinger. |
| **Pickpocket** | Never run out of ammo. Essential for ranged builds. |
| **Hyper-Critical** | Enhanced damage output for crit builds. |

### Weapon Meta

| Slot | S-Tier | A-Tier |
|------|--------|--------|
| Melee | Improvised Mk I Shivs | Achlys Mk VIII Combat Axe, Chirurgeon's Mk IV Bone Saw |
| Ranged | Branx Mk VIII Dual Stub Pistols | Vraks Mk V Infantry Autogun, Branx Mk III Dual Autopistols, Ius Mk IV Shredder Autopistol, Branx Mk II Needle Pistol |

**Available melee archetypes:** Dual Shivs, Combat Axes, Combat Swords, Crowbars, Chain Axes, Chain Swords, Saws, Combat Knives
**Available ranged archetypes:** Dual Autopistols, Shotguns, Stub Revolvers, Autoguns, Dual Stub Pistols, Autopistols, Needle Pistols, Bolt Pistols

### Stimm Lab Configuration (meta)

**Cooldown-focused path:** Kalma I -> II -> III -> IV -> V (lower right)
- 50% increased cooldown regeneration when active
- Combined with 12% curio combat ability regen = 62% total
- Maximizes Enhanced Desperado uptime

### Build Archetypes

1. **Gunslinger** (most popular): Enhanced Desperado + Float Like a Butterfly + Shivs + Dual Stub Pistols + Chem Grenade
2. **Autogun Gunslinger**: Enhanced Desperado + Pickpocket + Shivs + Infantry Autogun + Chem Grenade
3. **Melee Rampage**: Frenzied Rampage + Float Like a Butterfly + Shivs + Dual Autopistols + Chem Grenade
4. **Chemist Support**: Stimm Supply + Shivs + Needle Pistol + Chem Grenade (niche)

### Community Builds (Games Lantern)

**Crackhead John Wick** (Sanloms) — [GL link](https://darktide.gameslantern.com/builds/a077be66-a1c9-4623-aa8c-3ce4af979bbd/crackhead-john-wick-high-havoc-build)
- Ability: Enhanced Desperado (modifiers: Pick Your Targets)
- Keystones: Float Like a Butterfly, Vulture's Mark, Hyper-Critical, Pickpocket
- Notables: Chem Grenade
- Talents: Sticky Hands, In Your Face, Precision Violence, Voice of Tertium, Float Like a Butterfly, Speedloader, Anarchist, Nimble, Jittery, Swift Endurance, Unload, Vulture's Mark, Calling for a Time Out, 'Tis But a Scratch, Hive City Brawler, Hyper-Critical, Punching Above One's Weight, The Sweet Spot, Vulture's Push, Vulture's Dodge, Gang Tough, Burst of Energy, Pickpocket
- Stats: Toughness ×2, Critical Chance, Melee Damage
- Melee: Improvised Mk I Shivs -- Uncanny Strike, Precognition (+Carapace)
- Ranged: Branx Mk VIII Dual Stub Pistols -- Run 'n' Gun, Speedload (+Flak)
- Curios: 3x Blessed Bullet +Toughness; Health, Gunner DR
- Playstyle: "Primary job is taking out Specials, Disablers and Ranged Elites almost as fast as they appear, keeping them off your team." Weakest vs monstrosities. Knives for carapace/captains/mutants/monstrosities — long dodge distance makes you "extremely slippery." Pistols: "extremely high weakspot damage (over 2x vs bodyshots) — aim for heads." "Rarely use braced fire mode, just hip fire 99% of the time." Run 'n' Gun makes pistols "go from inaccurate to becoming lasers." "Take advantage of instant reload on Enhanced Desperado — use up your current magazine before activating." "This class lives and dies by your ability to dodge — probably the hardest class in the game."
- **Rating: S (33/35)** — Perk: 5, Blessing: 5, Talent: 5, Breakpoint: 4, Curio: 4, Role: 5, Difficulty: 5 | Bot: BOT:ABILITY_UNVALIDATED

**Reginald's Melee Build** (Reginald) — [GL link](https://darktide.gameslantern.com/builds/a07c16c1-4370-4657-9f6b-33e714ca67c5/reginalds-melee-build)
- Ability: Frenzied Rampage (modifiers: Pulverising Strikes, Forge's Bellow, Boiling Blood)
- Keystones: Float Like a Butterfly, Chemical Dependency, Hyper-Critical, Pickpocket
- Notables: Chem Grenade
- Aura: Gunslinger Improved
- Talents: A Tertium Welcome, Precision Violence, Float Like a Butterfly, Nimble, Jittery, Swift Endurance, 'Tis But a Scratch, Hive City Brawler, Battering Strikes, Sample Collector, Extra Pouches, Chemical Dependency, Hyper-Critical, Punching Above One's Weight, Chem Enhanced, Chem Fortified, Gang Tough, Burst of Energy, Pickpocket
- Stats: Toughness ×2, Critical Chance, Melee Damage, Potent Tox
- Melee: Chirurgeon's Mk IV Bone Saw -- Decimator, Shock & Awe (+Unyielding, +Flak)
- Ranged: Branx Mk VIII Dual Stub Pistols -- Pinning Fire, Run 'n' Gun (+Flak, +Maniacs)
- Curios: 2x +Stamina, 1x +Toughness; Revive Speed, Gunner DR, Stamina Regen
- Playstyle: Minimal prose. "Cycle between chems and ability unless we need a big burst of output. 75s on a stim is too long, the 10s less here makes a big difference." "Pistols are a sidearm. Saw mulches once it gets going."
- **Rating: B (26/35)** — Perk: 5, Blessing: 4, Talent: 4, Breakpoint: 3, Curio: 3, Role: 4, Difficulty: 3 | Bot: BOT:ABILITY_UNVALIDATED

**The Chemist** (Reginald) — [GL link](https://darktide.gameslantern.com/builds/a0aaf6c0-6b02-4472-b679-1a93866ad0a2/the-chemist)
- Ability: Stimm Supply (modifiers: Fast Acting Stimms, Booby Trap)
- Keystones: Float Like a Butterfly, Chemical Dependency, Hyper-Critical, Pickpocket
- Notables: Boom Bringer
- Aura: Gunslinger Improved
- Talents: A Tertium Welcome, Precision Violence, Float Like a Butterfly, Nimble, Slippery Customer, Jittery, Swift Endurance, 'Tis But a Scratch, Hive City Brawler, Battering Strikes, Sample Collector, Extra Pouches, Chemical Dependency, Hyper-Critical, Punching Above One's Weight, Chem Enhanced, Chem Fortified, Gang Tough, Burst of Energy, Pickpocket
- Stats: Toughness ×2, Critical Chance, Melee Damage, Potent Tox
- Melee: Chirurgeon's Mk IV Bone Saw -- Decimator, Shock & Awe (+Unyielding, +Flak)
- Ranged: Branx Mk II Needle Pistol -- Run 'n' Gun, Stripped Down (+Unyielding, +Carapace)
- Curios: 2x +Stamina, 1x +Toughness; Revive Speed, Gunner DR, Stamina Regen
- Playstyle: Minimal prose — single sentence on page. Anti-special, anti-elite, anti-boss versatile build. "Updated slightly from the video based on recent refinements."
- **Rating: B (25/35)** — Perk: 5, Blessing: 3, Talent: 4, Breakpoint: 3, Curio: 3, Role: 4, Difficulty: 3 | Bot: BOT:ABILITY_UNVALIDATED

**Stimmtec: Will It Blend?** (ThetaZer0) — [GL link](https://darktide.gameslantern.com/builds/a083151c-9fc9-4e84-9c27-cee4720e0ada/stimmtec-will-it-blend-hive-scum-blender-build)
- Ability: Frenzied Rampage (modifiers: Pulverising Strikes, Channelled Aggression, Boiling Blood)
- Keystones: Float Like a Butterfly
- Notables: Boom Bringer
- Aura: Gunslinger Improved
- Talents: A Tertium Welcome, Precision Violence, Float Like a Butterfly, Nimble, Swift Endurance, Adrenaline Frenzy, 'Tis But a Scratch, Hive City Brawler, Hyper-Violence, Toxin Mania, Sample Collector, Extra Pouches, Coated Weaponry, Punching Above One's Weight, The Sweet Spot, Gang Tough, Burst of Energy, Stoked Rage, Adrenaline Unbound
- Stats: Toughness ×2, Critical Chance, Melee Damage, Potent Tox
- Melee: Improvised Mk I Shivs -- Precognition, Uncanny Strike (+Flak)
- Ranged: Branx Mk II Needle Pistol -- Stripped Down, Run 'n' Gun (+Reload Speed, +Unyielding)
- Curios: 1x Blessed Bullet +Toughness, 1x Gilded Mandible +Stamina, 1x Guardian Nocturnus +Stamina; Gunner DR
- Playstyle: "The build you thought bleed Zealot would play like — one of few builds that can actually kill heavies without massive resource dumps." "Pretend you have a brain and try to dodge with good timing (or just mash dodge) for massive crit chance and damage boost." Deploy Rampage during elite-heavy encounters or for toughness recovery — Sample Collector "procs non-stop as you mindlessly slash." "Hyper-Violence is your massive workhorse — if you take it off, DPS will plummet. Don't take Hyper-Critical, it has anti-synergy and will nerf your damage." Needle Pistol: "If it's just a fellow, hit them with yellow, but if it's more than two, hit them with blue." Yellow mode = massive boss DoT, blue = AoE. "Don't be greedy and try to snag Spur V — stimm cooldown becomes ridiculous." Stamina curios maximize Swift Endurance value. No crit blessing needed on shivs: "just a drop in the bucket since you already crit constantly."
- **Rating: A (28/35)** — Perk: 5, Blessing: 5, Talent: 4, Breakpoint: 3, Curio: 5, Role: 3, Difficulty: 3 | Bot: BOT:ABILITY_UNVALIDATED

### Build Scoring Summary

| # | Build | Class | Grade | Score | Bot-Safe? |
|---|-------|-------|-------|-------|-----------|
| 1 | Veteran Squad Leader | Veteran | S | 33/35 | Partial (aim) |
| 2 | Assault Veteran | Veteran | A | 29/35 | Partial (positioning) |
| 3 | Slinking Veteran | Veteran | A | 28/35 | Partial (aim+weakspot) |
| 4 | Spicy's Meta Zealot | Zealot | S | 32/35 | Good |
| 5 | Fatmangus Stealth | Zealot | B | 26/35 | Partial (positioning) |
| 6 | Holy Gains | Zealot | A | 28/35 | Good |
| 7 | Zealot Infodump | Zealot | A | 30/35 | Partial (dodge-centric playstyle) |
| 8 | Gandalf Wizard | Psyker | B | 26/35 | Good |
| 9 | Electrodominance | Psyker | A | 28/35 | Good |
| 10 | Electro Shriek | Psyker | A | 31/35 | Good |
| 11 | Explodegryn | Ogryn | A | 29/35 | Good |
| 12 | Shield Tank | Ogryn | A | 31/35 | Good |
| 13 | Shovel Ogryn | Ogryn | B | 25/35 | Good |
| 14 | Nuncio-Aquila | Arbites | A | 27/35 | Partial (block) |
| 15 | Melee Meta | Arbites | A | 28/35 | Good |
| 16 | BUSTED | Arbites | A | 27/35 | Partial (blitz) |
| 17 | Crackhead JW | Hive Scum | S | 33/35 | Partial (DLC-unvalidated) |
| 18 | Reginald Melee | Hive Scum | B | 26/35 | Partial (DLC-unvalidated) |
| 19 | The Chemist | Hive Scum | B | 25/35 | Partial (DLC-unvalidated) |
| 20 | Stimmtec Blender | Hive Scum | A | 28/35 | Partial (DLC-unvalidated) |

**Grade distribution:** S: 3, A: 12, B: 5 | **Bot-safe:** Good: 10, Partial: 10, Poor: 0

> Scoring methodology and tools migrated to `hadrons-blessing` repo.

---

## CROSS-CLASS PATTERNS

### Ability Usage Archetypes (for bot heuristics)

| Archetype | Classes | Bot trigger |
|-----------|---------|-------------|
| **Stance/buff on engage** | Vet (Exec Stance), Psyker (Scrier's), Hive Scum (Desperado/Rampage) | Activate when combat starts, not preemptively |
| **Team support on pressure** | Vet (VoC), Zealot (Chorus), Psyker (Dome), Ogryn (Taunt) | Activate when team under fire / toughness dropping |
| **Dash/charge to gap-close** | Zealot (Fury), Ogryn (Bull Rush), Arbites (Break the Line) | Close distance to elites/specials or rescue downed allies |
| **Emergency panic button** | Zealot (Stealth), Vet (Infiltrate), Ogryn (Taunt No Pain) | Low health/toughness when surrounded |
| **Cooldown-gated nuke** | Ogryn (PBB at 80s), Hive Scum (Desperado at 45s) | Long CD = conservative, save for high-value moments |

### Most Popular Ability Per Class (Havoc meta)

| Class | #1 Ability | #2 Ability | #3 Ability |
|-------|-----------|-----------|-----------|
| Veteran | Voice of Command | Infiltrate | Executioner's Stance |
| Zealot | Chorus of Spiritual Fortitude | Fury of the Faithful | Shroudfield |
| Psyker | Telekine Shield (Dome) | Venting Shriek | Scrier's Gaze |
| Ogryn | Loyal Protector | Bull Rush | Point-Blank Barrage |
| Arbites | Break the Line | Nuncio-Aquila | Castigator's Stance |
| Hive Scum | Enhanced Desperado | Frenzied Rampage | Stimm Supply |

### Weapon Category Dominance

**Melee S-tier per class:**
- Duelling Sword (Veteran, Zealot -- universal S-tier)
- Shock Maul (Arbites -- class-defining)
- Shivs (Hive Scum -- class-defining, 4/6 builds)
- Pickaxe / Bully Club (Ogryn -- both S-tier)
- Blaze Force Sword (Psyker -- class-defining, 3/3 builds)

**Ranged S-tier per class:**
- Plasma Gun (Veteran -- dominant)
- Purgation Flamer (Zealot -- dominant)
- Inferno Force Staff (Psyker -- dominant)
- Rumbler (Ogryn -- dominant)
- Exterminator Shotgun (Arbites -- dominant)
- Dual Stub Pistols (Hive Scum -- dominant)

### Blessing Frequency (across 20 GL builds)

| Blessing | Occurrences | Slot | Effect |
|----------|-------------|------|--------|
| Uncanny Strike | 5 | Melee | +8% Rending on weak spot hit, stacks 5x |
| Run 'n' Gun | 4 | Ranged | Hipfire while sprinting, +15% close damage |
| Warp Nexus | 3 | Ranged (staff) | +5-20% crit chance based on peril |
| Warp Flurry | 3 | Ranged (staff) | -8.5% charge time on chained secondary, stacks 3x |
| Pinning Fire | 3 | Ranged | +5% strength per stagger, stacks 5x |
| High Voltage | 2 | Melee | +25% damage vs electrocuted enemies |
| Cranial Grounding | 2 | Melee | Toughness on headshot kill |
| Heatsink | 2 | Melee | Heat reduction on hit |

### Curio Meta (universal)

- **2x Toughness + 1x Health** (or 3x Toughness)
- **Priority perks:** Combat Ability Regeneration > Gunner DR > Revive Speed > Stamina Regen
- Combat Ability Regen appears in nearly every build -- abilities should be used frequently when off cooldown

---

## IMPLICATIONS FOR BOT PROFILES

### Ability selection priority

Bots should default to the #1 meta ability per class. For classes where BetterBots already supports the ability:

| Class | Meta #1 | BetterBots tier | Status |
|-------|---------|----------------|--------|
| Veteran | Voice of Command | Tier 1 | PASS -- heuristic exists |
| Zealot | Chorus (Relic) | Tier 3 | PASS (100% post-fix) |
| Psyker | Dome (Force Field) | Tier 3 | PASS (100% post-fix) |
| Ogryn | Taunt | Tier 2 | PASS -- heuristic exists |
| Arbites | Break the Line (Charge) | Tier 2 | PASS -- heuristic exists |
| Hive Scum | Desperado (Focus) | Tier 1 | DLC-blocked |

Key insight: the two most popular abilities (Chorus, Dome) are both Tier 3 item-based -- improving Tier 3 reliability (#3) directly impacts the meta-relevant builds.

### Weapon pairing implications

Bots equipped via Tertium 5/6 should ideally get meta weapon pairings. The most impactful pairing data:
- Every class has ONE clearly dominant ranged weapon
- Melee weapons are more varied but each class has 1-2 dominant picks
- Blessings like Uncanny Strike and Run 'n' Gun appear across multiple classes

### Heuristic tuning signals

- **Combat Ability Regen on curios is universal** -> abilities should be used more liberally (lower thresholds)
- **Cooldown length correlates with conservatism**: 20-30s = use freely, 45-50s = moderate, 80s = save for high-value
- **Team support abilities (VoC, Chorus, Dome, Taunt) trigger on team pressure**, not preemptively
- **Stance/DPS abilities trigger on combat engagement**, not before

---

## COMMUNITY RESOURCES & TOOLS

### Build Planners
- [GamesLantern Build Editor](https://darktide.gameslantern.com/builds) -- Most popular build planner. Full talent trees, weapon selection, blessing/perk assignment.
- [Wartide Breakpoint Calculator](https://wartide.net/) -- Community breakpoint calculator for weapon/talent/blessing combos.
- [Desmos Survivability Calculator](https://www.desmos.com/) -- Community-made survivability modeling (search "Darktide toughness" in Desmos community).

### Datamined References
- [Steam: Enemy Stats Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3062261689) -- Enemy HP, armor types, difficulty scaling.
- [Steam: Curio & Stimm Mechanics](https://steamcommunity.com/sharedfiles/filedetails/?id=3088891271) -- Curio stat ranges, stimm lab mechanics.
- [Dump Stats Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3095221088) -- Weapon stat dumps and datamined values.

### Community Hubs
- **Official Discord** (~130k members) -- `#build-discussion`, `#class-specific` channels
- **r/DarkTide** -- Active build discussion, patch analysis
- **Fatshark Forums** -- Developer interaction, patch notes

### Optimization-Focused YouTube Creators
- **Reginald** -- Hive Scum specialist, melee optimization
- **Mister E.** -- Ogryn specialist, Explodegryn builds
- **Ryken XIV** -- General optimization, tier lists
- **cashcrop_** -- Veteran specialist, plasma/bolter builds
- **Hank** -- Psyker specialist, staff mechanics
- **randomspicy** -- Zealot specialist, Havoc 40 meta
- **Magnafanta** -- Psyker, electrokinetic builds
- **nomalarkey** -- Psyker melee, Scrier's builds
- **Razgriz** -- Zealot infodump guides (comprehensive)
- **TheRatOCE** -- Advanced tech (animation cancels)
- **B-To-The-Ryan** -- Arbites melee builds

### Comprehensive Steam Class Guides
- [The Ogrynomicon](https://steamcommunity.com/sharedfiles/filedetails/?id=3096421088) -- Complete post-rework Ogryn guide
- [Psyker's Atheneum](https://steamcommunity.com/sharedfiles/filedetails/?id=3098711088) -- Full Psyker mechanics + builds
- [Complete Hive Scum Guide](https://darktide.gameslantern.com/user/br1ckst0n/guide/the-complete-hive-scum-operative-guide)
- [Full Arbites Guide](https://darktide.gameslantern.com/user/nrgaa/guide/full-arbites-guide)
- [Complete Post-Rework Ogryn Guide](https://darktide.gameslantern.com/user/nrgaa/guide/complete-post-rework-ogryn-guide)

---

## BREAKPOINT KNOWLEDGE

### Key Enemy HP at Damnation/Auric (from decompiled source v1.10.7)

| Enemy | Role | Armor | HP (Damn) | HP (Auric) |
|-------|------|-------|-----------|------------|
| Poxwalker | horde | disgust_resilient | 300 | 375 |
| Groaner (cultist_melee) | roamer | unarmored | 550 | 688 |
| Dreg Stalker (renegade_melee) | roamer | unarmored | 650 | 815 |
| Scab Shooter (renegade_rifleman) | roamer | unarmored | 400 | 500 |
| Scab Stalker (renegade_assault) | roamer | unarmored | 500 | 625 |
| Dreg Rager (cultist_berzerker) | elite | unarmored | 1500 | 2000 |
| Scab Rager (renegade_berzerker) | elite | armored | 1875 | 2500 |
| Scab Gunner (renegade_gunner) | elite | armored | 1275 | 1700 |
| Scab Mauler (renegade_executor) | elite | super_armor | 2775 | 3700 |
| Crusher (chaos_ogryn_executor) | elite | super_armor | 4875 | 6500 |
| Bulwark (chaos_ogryn_bulwark) | elite | resistant | 3600 | 4800 |
| Pox Hound (chaos_hound) | special | disgust_resilient | 1050 | 1400 |
| Poxburster (chaos_poxwalker_bomber) | special | disgust_resilient | 1050 | 1400 |
| Trapper (renegade_netgunner) | special | berserker | 675 | 900 |
| Mutant (cultist_mutant) | special | berserker | 3000 | 4000 |
| Sniper (renegade_sniper) | special | unarmored | 375 | 500 |

### Difficulty HP Scaling Multipliers

| Transition | Multiplier | Note |
|------------|-----------|------|
| Uprising → Malice | ×1.25 | Small bump |
| Malice → Heresy | ×1.2–1.5 | **Biggest jump** -- many breakpoints break here |
| Heresy → Damnation | ×1.33 | Significant |
| Damnation → Auric | ×1.25–1.5 | Variable by category |

### Key Breakpoint Optimization Targets

1. **One-shot Scab Ragers** (armored, 1875/2500 HP) -- The most common breakpoint target. Determines heavy melee weapon viability.
2. **Two-hit Crushers** (super_armor, 4875/6500 HP) -- Defines "anti-armor" weapons. Thunder hammer activated, pickaxe heavy.
3. **One-shot specials at range** (hound 1050/1400, bomber 1050/1400, trapper 675/900) -- Defines ranged weapon viability.
4. **Horde cleave efficiency** -- damage × targets per swing. Poxwalkers at 300 HP (Damn) are the reference.
5. **Stagger thresholds** -- Can you stagger a Crusher? A Bulwark? Determines defensive viability.

### Calculator Limitations
Community breakpoint calculators typically don't account for class talent multipliers, making source-verified calculations more accurate. The damage pipeline has 13 stages (see decompiled source analysis) — most calculators only model stages 1-5.

---

## TOUGHNESS & SURVIVABILITY META

### Universal Curio Strategy
- **3× Blessed Bullet** (curio type with highest stat rolls)
- **Priority perks:** Combat Ability Regen > Toughness Regen Speed > Gunner DR > Sniper DR > Revive Speed
- Combat Ability Regen appears in nearly every competitive build — abilities should be used frequently

### Toughness Regen Mechanics (from source)
- Base regen: **5 pts/sec** for all classes
- Regen requires coherency: 0 allies = **0 regen**, 1 ally = 50%, 3 allies = 100%
- Regen delay: **3 seconds** after taking damage (modified by buffs)
- Toughness regen speed buffs stack multiplicatively with coherency modifier
- Melee kill recovery: **5% of max toughness** (all classes)

### Dodge/Sprint Toughness Damage Reduction (from source)

| Class | Dodge | Sprint | Sliding |
|-------|-------|--------|---------|
| Zealot | 50% | 50% | 50% |
| Psyker | 50% | 100% | 50% |
| Adamant (Arbites) | 50% | 100% | 50% |
| Veteran | 100% | 100% | 50% |
| Ogryn | 100% | 100% | 100% |
| Broker (Hive Scum) | 100% | 100% | 50% |

### Class-Specific Sustain Strategies
- **Veteran**: Relies on ranged kiting + VoC stagger for breathing room. Weakest passive sustain.
- **Zealot**: Best dodge-tank. 50% toughness DR on dodge/sprint/slide. Until Death prevents lethal hits.
- **Psyker**: Dome provides team toughness + DR. Kinetic Deflection converts peril to toughness. Fragile without abilities.
- **Ogryn**: Highest raw HP (300) and stamina (8). Taunt redirects aggro. No dodge benefit.
- **Arbites**: Forceful keystone gives +25% DR at 10 stagger stacks. Shield blocks everything.
- **Hive Scum**: Desperado grants ranged immunity. Dodge invulnerability loop (Vulture talent) makes melee survivable.

### Community Consensus
**Defense always trumps offense at Havoc/Auric.** The meta universally prioritizes:
1. Toughness curios over health/damage curios
2. Defensive talents before offensive talents
3. Team support abilities over selfish DPS abilities
4. Sustain through engagement (melee kills for toughness) over passive regen

---

## RECENT BALANCE CHANGES (2025-2026)

### Nightmares & Visions (March 2025)
- **Full Ogryn rework**: +14 new talents, new keystone (Burst Limiter Override), rebalanced entire tree
- **Psyker buffs**: Empowered Psionics improvements, staff balance adjustments
- **Weapon balance**: Bolter adjustments, Power Maul buffs, Chain Weapon rework
- Impact: Ogryn meta shifted from Feel No Pain to Heavy Hitter. Psyker staff builds became more viable.

### Bound by Duty (September 2025)
- **Veteran/Zealot/Psyker tree reworks**: More open layouts, better build diversity
- **New weapon**: Power Falchion (Veteran/Zealot)
- **New elite**: Scab Plasma Gunner (renegade_plasma_gunner, 900 base HP)
- **Havoc difficulty**: Replaced old Auric Maelstrom difficulty naming
- Impact: Zealot gained more flexible talent paths. Veteran VoC builds became even more dominant. Power Falchion entered A-tier for melee.

### Hive Scum Launch (December 2025)
- **New class**: Hive Scum (Broker) with 3 abilities, stimm lab system, unique weapon pool
- **Stimm Lab**: Customizable drug effects via progression tree
- Impact: Hive Scum immediately entered S-tier. Enhanced Desperado's ranged immunity + infinite ammo proved dominant.

### Hotfix 1.10.2 (December 2025)
- Hive Scum polish: Stimm interaction fixes, dodge timing adjustments
- Vulture talent dodge invulnerability window tightened slightly

### Patch 1.10.6 (February 2026)
- **Stimm Lab rework**: Rebalanced stimm paths, nerfed Kalma V cooldown reduction
- **Talent adjustments**: Minor Hive Scum talent number changes
- Impact: Stimm lab builds shifted toward balanced paths. Core Hive Scum meta unchanged.

### Patch 1.10.7 (Current — February 2026)
- Minor bug fixes and stability improvements
- No major balance changes from 1.10.6

---

## SOURCES

### Build Databases
- [GamesLantern Builds](https://darktide.gameslantern.com/builds) (20 builds scraped)
- [GamesLantern Weapon Tier List](https://darktide.gameslantern.com/tier-lists/weapons/9fdc4e6f-1a61-4543-b067-f13c5fd6abdc)
- [GamesLantern Class Tier List](https://darktide.gameslantern.com/tier-lists/classes/a0c4386d-47f6-4aa2-a597-8a0a04fde7c3)

### Additional Build Sources (2026-03-09 update)
- [Karnak HM Auric Maelstrom](https://darktide.gameslantern.com/builds/9a60607c-f220-4903-9931-f21cb4cf0785/karnak-hm-updated-auric-maelstrom-pubbing-lazy-mans-1-build-wonder)
- [Auric Maelstrom Damnation+ Plasma](https://darktide.gameslantern.com/builds/9a9d49c9-baed-4fc9-b1c8-606a46d40bae/auric-maelstrom-damnation-plasma-build)
- [Zealot Infodump Stealth Auric](https://darktide.gameslantern.com/builds/9a7a817d-6ef9-49b6-9e1e-c6f1d03b3fec/zealot-infodump-stealth-auric)
- [Spicy's Meta Havoc 40 Zealot](https://darktide.gameslantern.com/builds/9ede2ba5-850b-41d0-9325-4f42cddf9836/spicys-meta-havoc-40-zealot)
- [Zealot Build 2026](https://darktide.gameslantern.com/builds/a0f2da1d-4056-4410-88cd-209997f4f8a6/zealot-build-2026)
- [Darktide Bound by Duty Update](https://www.playdarktide.com/news/bound-by-duty-update)
- [Darktide Beginner's Guide (Bound by Duty)](https://www.gamesear.com/tips-and-guides/darktide-beginners-guide-fun-powerful-build-for-every-class-bound-by-duty-update)

### Specific Builds Referenced
- [Vet Meta Havoc-40](https://darktide.gameslantern.com/builds/9f7e8c2a-c046-4694-8e52-51d39b373505/vet-meta-havoc-40)
- [Spicy's Meta Havoc 40 Zealot](https://darktide.gameslantern.com/builds/9ede2ba5-850b-41d0-9325-4f42cddf9836/spicys-meta-havoc-40-zealot)
- [Novice's Havoc 40 Psyker](https://darktide.gameslantern.com/builds/9eb0384d-c297-4273-9596-d41d7f8f56eb/novices-havoc-40-build-all-rounder)
- [Electrodominance Scrier Smiter](https://darktide.gameslantern.com/builds/9fe8da5a-85d2-4193-a584-e47a6a8b5135/electrodominance-havoc-40-scrier-smiter)
- [Dec 2025 Havoc 40 Ogryn Shield Tank](https://darktide.gameslantern.com/builds/a006d28e-3024-4c8b-b73f-b57383335a8a/dec-2025-havoc-40-ogryn-shield-tank-build-for-the-liluns)
- [Ogryn Havoc 40 META](https://darktide.gameslantern.com/builds/9f01c771-0e60-4ada-8952-f6450b4bb5c1/ogryn-havoc-40-meta)
- [Arby's OP Melee Meta Havoc-40](https://darktide.gameslantern.com/builds/9f6108ec-d547-448f-b847-38fc0e21ccce/arbys-op-melee-meta-havoc-40)
- [Crackhead John Wick](https://darktide.gameslantern.com/builds/a077be66-a1c9-4623-aa8c-3ce4af979bbd/crackhead-john-wick-high-havoc-build)
- [Scum's OP Gunslinger Meta](https://darktide.gameslantern.com/builds/a0b07c83-1d07-4dd8-8f49-e94a659c4fa3/scums-op-gunslinger-meta-h-40)
- [Havoc 40 Arbitrator Meta](https://darktide.gameslantern.com/builds/a0919dc3-7def-43d2-ada9-80b967b3fd18/the-havoc-40-arbitrator-meta-build)

### Guides
- [Steam: Loadouts For Havoc and Auric For All Classes](https://steamcommunity.com/sharedfiles/filedetails/?id=3062261689)
- [Complete Post-Rework Ogryn Guide](https://darktide.gameslantern.com/user/nrgaa/guide/complete-post-rework-ogryn-guide)
- [Full Arbites Guide](https://darktide.gameslantern.com/user/nrgaa/guide/full-arbites-guide)
- [Complete Hive Scum Guide](https://darktide.gameslantern.com/user/br1ckst0n/guide/the-complete-hive-scum-operative-guide)

### Community Discussions
- [Current Havoc Meta? (Steam)](https://steamcommunity.com/app/1361210/discussions/0/597404578618551591/)
- [Best Team Composition for Havoc (Steam)](https://steamcommunity.com/app/1361210/discussions/0/595134792309272177/)
- [VoC vs Executioner's Stance (Steam)](https://steamcommunity.com/app/1361210/discussions/0/734782866781815749/)
- [Rush vs Taunt Ogryn Endgame (Steam)](https://steamcommunity.com/app/1361210/discussions/0/4040357419297549585/)
- [What Zealot Meta? (Steam)](https://steamcommunity.com/app/1361210/discussions/0/592889306000988528/)
- [Favourite Arbites Build (Steam)](https://steamcommunity.com/app/1361210/discussions/0/597405077977747117/)

### Tier Lists
- [Darktide Tier List Dec 2025 (MetaTierList)](https://metatierlist.com/darktide-tier-list/)
- [Class Tier List (Steam)](https://steamcommunity.com/app/1361210/discussions/0/3594464960492636761/)
- [Fatshark Forums Class Tier List](https://forums.fatsharkgames.com/t/my-tier-list-of-the-classes/109863)
