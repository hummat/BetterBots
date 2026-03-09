# Darktide Endgame Meta Builds Research (Havoc 30-40)

> Compiled 2026-03-06 from Games Lantern (20 builds), Reddit/Steam/Fatshark Forums, and decompiled source v1.10.7.
> Updated 2026-03-09 with balance patch data, breakpoint tables, community tools, and additional builds.
> Purpose: inform bot AI ability/weapon profiles for BetterBots mod.
> Cross-references: `CLASS_*.md` (ability templates), `CLASS_*_TACTICS.md` (heuristic rules)

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

**Veteran Squad Leader** (seventhcodex)
- Voice of Command, Shredder Frag, Survivalist aura, Focus Target keystone
- Melee: Lawbringer Mk IIb Power Falchion -- Cranial Grounding, Heatsink
- Ranged: M35 Magnacore Mk II Plasma Gun -- Rising Heat, Gets Hot!
- Curios: 2x +Toughness, 1x +Health; Sniper/Gunner resistance
- Playstyle: Team support through CC and coherency buffs

**Guardian's Spec Ops Sergeant** (Guardian)
- Focus Target keystone, Krak Grenade + Grenade Tinkerer
- Melee: Catachan Mk III Combat Blade -- Flesh Tearer, Lacerate (+Unyielding)
- Ranged: Accatran Mk XII Recon Lasgun -- Headhunter, Infernus (+Unyielding)
- Curios: 3x +Toughness; Stamina Regen, Combat Ability Regen
- Playstyle: Battle tempo director, eliminate ranged threats, Krak for armor

**Karnak HM Auric Maelstrom** (updated)
- Voice of Command, Weapon Specialist keystone
- Melee: Achlys Mk VI Power Sword -- Slaughterer, Cycler
- Ranged: Zarona Mk IIa Quickdraw Stub Revolver -- Hand-Cannon, Surgical
- Curios: 3x +Toughness; Combat Ability Regen, Gunner DR
- Playstyle: "Lazy man's 1-build-wonder." Revolver for specials, Power Sword for everything else.

**Auric Maelstrom Plasma** (community)
- Voice of Command, Weapon Specialist keystone
- Melee: Catachan Mk III Combat Blade / Rashad Mk X Chain Sword
- Ranged: M35 Magnacore Mk II Plasma Gun -- Rising Heat, Gets Hot!
- Curios: 2x +Toughness, 1x +Health; Combat Ability Regen
- Playstyle: Plasma charged shots for elites/specials, uncharged for hordes. VoC for panic/support.

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

**Spicy's Meta Havoc 40 Zealot** (randomspicy)
- Blades of Faith, Beacon of Purity aura
- Talents: Good Balance, Enduring Faith, Stalwart, Backstabber, Chorus, Infectious Zeal, Righteous Warrior, Purge the Unclean, Thy Wrath be Swift, Abolish Blasphemers
- Melee: Munitorum Mk X Relic Blade -- Heatsink, Cranial Grounding
- Ranged: Artemia Mk III Purgation Flamer -- Blaze Away, Penetrating Flame
- Curios: 2x +Toughness, 1x +Health; Combat Ability Regen, Gunner DR
- Playstyle: "Pick out Elites, hold the line, give ranged characters space"

**Fatmangus Zealot Stealth** (dopeslinker)
- Shroudfield
- Melee: Munitorum Mk II Relic Blade -- Wrath, Overload (+Flak required for H40 Captain one-shots)
- Ranged: Locke Mk III Spearhead Boltgun -- Pinning Fire, Puncture
- Curios: 3x +Health; Revive Speed, Gunner DR

**Go Go Gadget Daemonhost Impregnator** (Harelike abhuman)
- Shroudfield, Martyrdom keystone (-5 wounds = +40% melee damage, +32.5% toughness DR, +20% melee speed)
- Melee: Crucis Mk II Thunder Hammer -- Thrust, Slaughterer
- Ranged: Locke Mk IIb Spearhead Boltgun -- Pinning Fire, Shattering Impact
- Curios: 3x +Wounds, +Health, +Toughness, Gunner DR

**Holy Gains Havoc 40** (charname)
- Martyrdom implied
- Melee: Tigrus Mk XV Heavy Eviscerator -- Wrath, Bloodthirsty (990 first target damage)
- Ranged: Godwyn-Branx Mk IV Bolt Pistol -- Lethal Proximity, Puncture
- Curios: 3x +1 Wound; Stamina Regen, Toughness, DR
- Playstyle: "Not meta but viable and fun." Chains heavy specials to dismantle Crusher groups.

**Zealot Infodump No Stealth Auric** (Razgriz)
- Fury of the Faithful, Blazing Piety keystone
- Blitz: Stunstorm / Immolation / Blades of Faith (player choice)
- Aura: Benediction or Beacon of Purity
- Talents: Anoint in Blood, Purge the Unclean, Backstabber, Scourge, Dance of Death, Duellist, Redoubled Zeal, Punishment, Invocation of Death, Prime Target, Restoring Faith, Second Wind, Enduring Faith, Good Balance, Thy Wrath be Swift, Until Death, Holy Revenant
- Melee: Maccabian Mk IV Duelling Sword -- Uncanny Strike, Riposte (+Flak, +Unyielding)
- Ranged: Agripinaa Mk VIII Braced Autogun -- Inspiring Barrage, Speedload (+Flak, +Maniacs)
- Curios: 3x +Health; Sniper/Gunner/Tox Flamer DR, Corruption Resistance
- Playstyle: "Defense > Offense in Darktide." Mobile, versatile.

**Zealot Infodump Stealth Auric** (Razgriz)
- Shroudfield, Inexorable Judgement keystone
- Blitz: Blades of Faith
- Melee: Catachan Mk III Combat Blade -- Flesh Tearer, Lacerate (+Flak, +Unyielding)
- Ranged: Zarona Mk IIa Quickdraw Stub Revolver -- Hand-Cannon, Surgical
- Curios: 3x +Health; Sniper/Gunner/Tox Flamer DR
- Playstyle: Stealth spam with Invocation of Death. Combat Blade heavy attack speed during stealth is "broken".

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

**Gandalf: Melee Wizard** (nomalarkey)
- Scrier's Gaze, Psykinetic's Aura
- Talents: Warp Ghost, Warp Splitting, One with the Warp, Warp Rider, Brain Rupture, Kinetic Flayer, Mettle, Disrupt Destiny, Empathic Evasion, Vulnerable Minds, Just a Dream, By Crack of Bone
- Melee: Covenant Mk VI Blaze Force Greatsword -- Blazing Spirit, Shred
- Ranged: Equinox Mk III Voidblast Force Staff -- Warp Nexus, Warp Flurry
- Curios: 3x +Toughness; Combat Ability Regen, Stamina Regen, Sprint Efficiency

**Electrodominance Havoc 40 Scrier Smiter** (Magnafanta)
- Scrier's Gaze implied
- Melee: Covenant Mk VIII Blaze Force Greatsword -- Momentum, Deflector
- Ranged: Nomanus Mk VI Electrokinetic Force Staff -- Warp Flurry, Warp Nexus
- Curios: 2x +Toughness, 1x +Health; Gunner DR, Corruption Resistance
- WARNING: "DO NOT use this build for Final Toll condition!"

**Electro Shriek Big Damage** (Mizumelon)
- Venting Shriek, Brain Rupture blitz, Psykinetic's Aura, Kinetic Flayer keystone
- Talents: Penetration of the Soul, Vulnerable Minds, Perilous Combustion, Wildfire, Seer's Presence, Quietude, Mettle, Souldrinker, One with the Warp, Essence Harvest, Kinetic Deflection, Empyric Resolve, Creeping Flames
- Melee (4 options): Blaze Force Greatsword (Shred+Wrath), Assault Chainsword, Combat Blade, Duelling Sword (Uncanny Strike+Riposte)
- Ranged: Nomanus Mk VI Electrokinetic Force Staff -- Warp Nexus, Warp Flurry (+Flak, +Unyielding)
- Curios: 3x +Toughness; Combat Ability Regen, Gunner DR
- Playstyle: Half-charge staff attacks, trigger Warp Nexus + Warp Flurry, Venting Shriek with Creeping Flames for AoE soulblaze (120+ damage/tick at 9 stacks)

**Auric Maelstrom Voidstrike** (CGEE)
- Venting Shriek, Empowered Psionics keystone
- Blitz: Brain Rupture
- Melee: Deimos Mk IV Blaze Force Sword -- Blazing Spirit, Riposte
- Ranged: Equinox Mk IV Voidstrike Force Staff -- Warp Nexus, Warp Flurry
- Curios: 3x +Toughness; Combat Ability Regen, Gunner DR
- Playstyle: Charged staff for horde clear, Brain Rupture for specials, Venting Shriek for peril management + soulblaze.

**Rat's Trauma Psyker** (TheRatOCE)
- Scrier's Gaze, Disrupt Destiny keystone
- Melee: Obscurus Mk 2 Blaze Force Sword -- Blazing Spirit, Shred
- Ranged: Equinox Mk III Voidblast Force Staff -- Warp Nexus, Warp Flurry
- Curios: 2x +Toughness, 1x +Health; Combat Ability Regen
- Playstyle: Animation cancel tech for higher DPS. Staff secondary for stagger, primary for damage.

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

**Mister E's Explodegryn** (Mister E)
- Taunt ability
- Melee: Achlys Mk I Power Maul -- Power Surge, Skullcrusher
- Ranged: Lorenz Mk VI Rumbler -- Shattering Impact, Adhesive Charge
- Curios: 3x +Toughness
- Playstyle: "Club enemies for stacks, taunt to group, delete with grenades. For bosses: melee x4 -> grenade -> taunt for stagger during explosion."

**Heretic Miner Auric Maelstrom** (community)
- Loyal Protector (Taunt), Heavy Hitter keystone
- Melee: Borovian Mk Ia Delver's Pickaxe -- Haymaker, Thunderous (+Carapace, +Unyielding)
- Ranged: Achlys Mk VII Heavy Stubber -- Pinning Fire, Sustained Fire
- Curios: 3x +Toughness; Combat Ability Regen, Gunner DR
- Playstyle: Pickaxe heavies for elite/boss damage, stubber for suppression + horde. Taunt to group enemies for pickaxe cleave.

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

**Execution Order Nuncio-Aquila** (fatherlyfigure)
- Voltaic Shock Mine, Nuncia Lex aura
- Melee: Branx Mk VI Shock Maul & Suppression Shield -- High Voltage, Confident Strike
- Ranged: Judgement Mk IV Subductor Shotpistol & Riot Shield -- Full Bore, Fire Frenzy
- Curios: 2x Gilded Inquisitorial Rosette, 1x Scrap of Scripture; +Toughness
- Playstyle: Frontline tank, stagger weakpoints for damage buffs and toughness recovery

**Arby's OP Melee Meta Havoc 40** (B-To-The-Ryan)
- Shock Mines blitz
- Melee: Branx Mk III Arbites Shock Maul -- High Voltage, Relentless Strikes (344.9 damage, 20.82 stagger)
- Ranged: Exaction Mk III Exterminator Shotgun -- Deathspitter, Sustained Fire (1046.9 damage)
- Curios: 3x +Toughness; Combat Ability Regen, Revive Speed, Stamina Regen
- Playstyle: "Strictly dogless melee." Constant light attack spam, shock mines for CC.

**Allrounder Massive CC** (community)
- Break the Line, Execution Order keystone
- Melee: Branx Mk VI Shock Maul & Suppression Shield -- High Voltage, Confident Strike
- Ranged: Exaction Mk VIII Exterminator Shotgun -- Deathspitter, Full Bore
- Curios: 3x +Toughness; Combat Ability Regen, Revive Speed
- Playstyle: Shield for survivability, shotgun for CC. Execution Order procs on crit for massive damage spikes.

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

**Crackhead John Wick** (Sanloms)
- Enhanced Desperado, Chem Grenade, Gunslinger aura
- Melee: Improvised Mk I Shivs -- Uncanny Strike, Precognition (+Stamina, +Carapace)
- Ranged: Branx Mk VIII Dual Stub Pistols -- Run 'n' Gun, Speedload (+Flak, +Crit Chance)
- Curios: 3x +Toughness; Gunner DR
- Playstyle: "Primary job is taking out Specials, Disablers and Ranged Elites almost as fast as they appear."

**Reginald's Melee Build** (Reginald)
- Melee: Chirurgeon's Mk IV Bone Saw -- Decimator (+5% Power x10 stacks), Shock & Awe (-60% hit mass on kill)
- Ranged: Branx Mk VIII Dual Stub Pistols -- Pinning Fire, Run 'n' Gun
- Curios: +Stamina, +Toughness; Revive Speed, Gunner DR
- Playstyle: Cycles between chems and ability for burst. Bone saw primary damage.

**The Chemist** (Reginald)
- Melee: Chirurgeon's Mk IV Bone Saw -- Decimator, Shock & Awe
- Ranged: Branx Mk II Needle Pistol -- Run 'n' Gun, Stripped Down (ranged immunity while sprinting >50% stamina)
- Curios: 3x +Stamina/Health/Toughness; Revive Speed, Gunner DR, Stamina Regen
- Playstyle: Anti-special, anti-elite, anti-boss versatile build.

**Stimmtec: Will It Blend?** (ThetaZer0)
- Rampage! ability, Gunslinger Improved aura
- Talents: Coated Weaponry, Adrenaline Frenzy, Hyper-Violence, Stoked Rage, Adrenaline Unbound, Sample Collector, Swift Endurance, Precision Violence, Channelled Aggression
- Melee: Improvised Mk I Shivs -- Precognition, Uncanny Strike (+Stamina, +Flak)
- Ranged: Branx Mk II Needle Pistol -- Stripped Down, Run 'n' Gun (+Reload Speed, +Unyielding)
- Curios: +Toughness; Gunner DR
- Playstyle: Constant crit with toughness regen through melee. Dodge timing key for crit/damage boost. Needle Pistol yellow mode for boss DoT, blue for AoE.

**Big Dom's Havoc 40 Explosive Tox Scum** (Big Dom)
- Melee: Improvised Mk I Shivs -- Uncanny Strike, Flesh Tearer (+Carapace, +Unyielding)
- Ranged: Branx Mk II Needle Pistol -- Hot-Shot, Point Blank (+Flak, +Unyielding)
- Curios: 2x +Toughness, 1x +Stamina; Stamina Regen, Revive Speed

**Melee Poisonous CRIT** (Dakillah)
- Melee: Improvised Mk I Shivs -- Lacerate (4 bleed on non-weakspot), Uncanny Strike
- Ranged: Branx Mk II Needle Pistol -- Desperado, Gloryhunter
- Curios: 1x +Wound, +Health/Toughness; +Toughness
- Playstyle: Bleed/crit melee-focused poison build.

**Immortal Gunslinger** (community)
- Enhanced Desperado, Float Like a Butterfly keystone
- Melee: Improvised Mk I Shivs -- Precognition, Uncanny Strike
- Ranged: Branx Mk III Dual Autopistols -- Run 'n' Gun, Speedload
- Curios: 3x +Toughness; Gunner DR, Stamina Regen
- Playstyle: Vulture's Dodge invulnerability loop. Dodge-attack-dodge cycle makes you nearly unkillable. Autopistols for volume fire during Desperado.

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
