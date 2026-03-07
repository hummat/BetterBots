# Darktide Endgame Meta Builds Research (Havoc 30-40)

> Compiled 2026-03-06 from Games Lantern (20 builds), Reddit/Steam/Fatshark Forums, and decompiled source v1.10.7.
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

---

## ARBITES

### Combat Abilities (ranked by meta usage)

| Ability | Template | Meta Tier | Input | Role |
|---------|----------|-----------|-------|------|
| **Break the Line** | `adamant_charge` | S | `aim_pressed` -> `aim_released` | Forward dash + cone stagger. +25% damage, +50% impact for 6s. |
| **Nuncio-Aquila** | `adamant_shout` / `adamant_shout_improved` | A | `shout_pressed` -> `shout_released` | Damage reduction, toughness regen, revive speed in AoE. |
| **Castigator's Stance** | `adamant_stance` | B | `stance_pressed` | Emergency toughness. Long CD, selfish. Melee-focused. |

Drone: `adamant_area_buff_drone` (no `ability_template` -- Tier 3 item, ~21% reliability)

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
| Zealot | Chorus (Relic) | Tier 3 | PASS but item-based, reliability issues |
| Psyker | Dome (Force Field) | Tier 3 | ~13% reliability |
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

## SOURCES

### Build Databases
- [GamesLantern Builds](https://darktide.gameslantern.com/builds) (20 builds scraped)
- [GamesLantern Weapon Tier List](https://darktide.gameslantern.com/tier-lists/weapons/9fdc4e6f-1a61-4543-b067-f13c5fd6abdc)
- [GamesLantern Class Tier List](https://darktide.gameslantern.com/tier-lists/classes/a0c4386d-47f6-4aa2-a597-8a0a04fde7c3)

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
