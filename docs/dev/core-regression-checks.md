# Core Regression Checks

Use this when reviewing a fresh in-game log for regressions, and before any major
release. The goal is to separate real regressions from ordinary coverage gaps.
No single mission exercises every bot class, weapon family, grenade, pickup, and
safety rule, so report each area as `pass`, `partial`, `not exercised`,
`suspicious`, or `fail`.

## Baseline Commands

Run these first against the latest log unless the user names a specific run:

```bash
./bb-log summary 0
./bb-log warnings 0
./bb-log errors 0
./bb-log rules 0
./bb-log events summary 0
./bb-log events rules 0
```

Then run the focused combat checks:

```bash
./bb-log raw "charge consumed|fallback queued|fallback blocked|grenade queued|grenade releasing|grenade aim|grenade held|grenade blocked" 0
./bb-log raw "bot weapon:" 0 | rg -o "action=[a-z_]+" | sort | uniq -c | sort -nr
./bb-log raw "normalized shoot scratchpad inputs|close-range hipfire|zoom_shoot|suppressed stale shoot|anti-armor ranged family|close-range ranged family" 0
./bb-log raw "melee special prelude|melee direct special|armed shotgun|spent shotgun|queued rippergun|queued ranged bash" 0
./bb-log raw "smart-tag pickup|assigned ordered mule pickup|assigned proactive mule pickup|blocked pocketable|cleared stale mule pickup|pickup completed|stim" 0
./bb-log raw "hazard_prop|aoe_threat|daemonhost|danger_zone|movement safety|ledge" 0
```

Pipes are for local shell use only. If `bb-log raw` returns too much output,
start with the summary commands and narrow the raw pattern to one feature area.

## Reporting Template

Use this shape for future "check regressions" answers:

```text
Core regression check for <log/run>:
- Clean boot/log health:
- Abilities:
- Grenades/blitzes:
- Ranged, ADS, hipfire:
- Melee and weapon specials:
- Targeting and type switching:
- Pickups and pocketables:
- Movement and hazards:
- Coverage gaps:
- Actionable issues:
```

Do not call `not exercised` a regression. A feature is `suspicious` when the
log contains its setup conditions but not the expected follow-through. A feature
is `fail` when logs show the wrong action, a crash/warning, repeated timeout, or
an explicit invalid-state reason that contradicts visible game state.

## 1. Clean Boot And Log Health

Always check this before interpreting gameplay.

Expected evidence:

- `./bb-log warnings 0` has no BetterBots warnings.
- `./bb-log errors 0` has no Lua errors, script errors, or crash lines.
- `./bb-log summary 0` shows `BB warnings: 0` and `Error lines: 0`.
- Startup appears once per process, with no duplicate hook/re-hook spam.
- JSONL event log is present if event logging is enabled.

Red flags:

- `hook install failed`, `rehook active`, duplicate `hook_require`, or startup
  traceback.
- `Script Error`, `Lua Stack`, `Crash`, or repeated DMF warnings.
- Event log missing when it should be enabled for validation.

## 2. Template Ability Activation

This covers normal combat abilities that can be fired through vanilla bot
ability input once BetterBots removes the whitelist and supplies metadata.

Expected evidence:

- `./bb-log rules 0` shows useful true rules, not only hold/block rules.
- Raw logs include `fallback queued for <ability>` followed by
  `charge consumed for <ability>`.
- `./bb-log events summary 0` shows consumes for the bot slots that have
  ability-capable builds.
- `./bb-log events rules 0` shows both expected approvals and expected holds.

Core abilities to keep exercising over time:

- Veteran: Voice of Command / shout, Executioner's Stance, stealth.
- Zealot: dash, shroud/invisibility, relic item path.
- Psyker: overcharge stance, shout, force-field item path.
- Ogryn: taunt, charge, gunlugger.
- Arbites: stance, charge, drone item path, if the DLC/build is present.
- Hive Scum: Broker abilities / stimm field, only when owned and available.

Healthy blocks:

- Safe-state holds with no enemies or no ally pressure.
- Melee-range grenade/blitz blocks.
- Peril-window blocks for Psyker abilities.
- Team-cooldown blocks followed by later successful casts.
- Daemonhost or hazard suppression when the target is unsafe.

Red flags:

- Ability decisions approve, but `charge consumed` never appears.
- `fallback queued` repeats for the same ability without consume or cleanup.
- No true ability decisions during a combat-heavy mission with eligible bots.
- Support abilities fire only for ally wounds/corruption with no enemy pressure,
  unless the heuristic explicitly intends that.
- Dash, charge, stealth, or shout abilities fire into daemonhost/hazard danger
  zones after safety suppression should apply.

## 3. Item Ability Fallback

This covers Tier 3 abilities that require wield/use/unwield sequencing instead
of a direct combat ability input.

Expected evidence:

- `fallback item queued ...` for the item ability.
- Stage progression through wield/use/unwield or equivalent item events.
- `charge consumed for <ability>` or a logged successful completion.
- No repeated `slot_locked`, `missing_slot`, or timeout loop.

Feature coverage:

- Zealot relic.
- Psyker force field.
- Arbites drone.
- Hive Scum stimm field, when available.

Red flags:

- Item fallback starts but never reaches use/consume.
- Item fallback finishes only by timeout or profile rotation.
- `fallback item blocked` repeats in a situation where the item is visibly
  equipped and ready.

## 4. Grenades And Blitzes

This is the highest-risk combat surface because it crosses inventory state,
weapon slot switching, aiming, charge timing, and target safety.

Expected evidence:

- `grenade queued wield`, `grenade queued aim_hold`, `grenade releasing`, and
  `charge consumed for <grenade_or_blitz>`.
- Aim diagnostics such as `grenade aim ballistic` or flat/direct aim.
- Holds that match context, such as `grenade_krak_hold`,
  `grenade_fire_hold`, `grenade_smite_hold`, or peril/melee/no-LOS blocks.
- `./bb-log events rules 0` shows true approvals for equipped blitzes in
  appropriate fights.

Families to keep exercising:

- Veteran krak and frag/smoke style grenades.
- Zealot fire grenade, stun grenade, throwing knives.
- Psyker smite, assail/throwing knives, chain lightning.
- Ogryn frag, box, rock.
- Arbites whistle and mines.

Red flags:

- Wield/aim/release stages appear but no charge is consumed.
- `grenade aim unavailable (no_los)` dominates in a test where the bot clearly
  has line of sight.
- `lost target`, `dead target`, or `unwield timeout` repeats across several
  attempts.
- Blitzes fire at enemies inside daemonhost danger radius when ranged/blitz
  suppression should apply.
- Psyker blitzes ignore peril or keep holding through high peril.

## 5. Ranged Fire, ADS, And Hipfire

This covers basic shooting, scoped shooting, charge shooting, and the weapon
family rules that decide when ranged targeting remains preferable.

Expected evidence:

- `bot weapon:` action counts include `shoot`, `shoot_pressed`,
  `shoot_charge`, `zoom`, `zoom_shoot`, and `zoom_release` when the roster has
  suitable weapons.
- `normalized shoot scratchpad inputs` appears for weapons whose scratchpad
  input mapping needs repair.
- `close-range hipfire suppressed ADS` appears for weapons that should avoid
  scoped firing at short range.
- `close-range ranged family kept ranged target type` appears for weapons that
  should keep firing at close range instead of forcing melee.
- `anti-armor ranged family kept ranged target type` appears for weapons such
  as bolter/plasma/kickback-style anti-armor guns against armored targets.

Weapon coverage to rotate into release soaks:

- ADS-capable precise weapons.
- Close-range hipfire weapons.
- Plasma/staff/charge-fire weapons.
- Bolter-like anti-armor weapons.
- Ogryn kickback/thumper/rumbler/rippergun/stubber families.
- Shotguns.

Red flags:

- ADS-capable weapons never log `zoom` or `zoom_shoot` in a ranged-heavy run.
- Charge-fire weapons never log `shoot_charge`.
- Hipfire-only or close-range weapons repeatedly enter ADS at short distance.
- Stale aim/unaim suppression appears without normal follow-up fire.
- Ranged target type is dropped against targets the weapon family is meant to
  handle at range.

## 6. Sustained And Stream Fire

This covers weapons that should hold fire inputs rather than tap once.

Expected evidence:

- Sustained-fire markers for arming, holding, and clearing the stream state.
- `bot weapon:` actions that include repeated `shoot`/`shoot_pressed` without
  immediate stale cleanup.
- No reload or weapon-switch loop while the target remains valid.

Weapon coverage:

- Recon lasgun / autogun / autopistol style streams.
- Flamer and Purgatus-style streams.
- Stubber and rippergun style sustained fire.
- Any weapon family with custom sustained-fire handling.

Red flags:

- Stream fire arms but never holds.
- Stream fire clears immediately on every attempt despite visible enemies.
- Sustained-fire weapons only tap fire in a dense horde test.

## 7. Melee Selection

This covers the normal melee attack mix and defensive inputs.

Expected evidence:

- `bot weapon:` action counts include `start_attack`, `light_attack`,
  `heavy_attack`, `block`, `block_release`, and ideally `push` in pressure.
- Heavy attacks appear against armored/elites where the weapon rules prefer
  heavy.
- Light attacks still appear in horde/low-armor contexts.
- Defensive actions still occur under pressure and do not permanently suppress
  attacking.

Coverage to rotate:

- Hordes with trash enemies.
- Mixed horde with elites/specials.
- Maulers, crushers, ragers, and other armor pressure.
- Boss or monstrosity pressure, if available.

Red flags:

- Only light attacks in an armor-heavy scenario.
- Only heavy attacks into trash horde.
- `start_attack` appears without light/heavy follow-through.
- Blocks/pushes suppress attacks indefinitely.

## 8. Weapon Specials And Special Attacks

This covers weapon-specific special inputs and prelude rules.

Expected evidence:

- `melee special prelude queued before light_attack` or before
  `heavy_attack` for powered melee weapons.
- `melee direct special` for direct specials.
- `special_action` in `bot weapon:` action counts when a suitable weapon is
  present.
- `armed shotgun` followed by `spent shotgun` for shotgun special shells.
- `queued rippergun` or `queued ranged bash` for Ogryn ranged specials when
  equipped.

Weapon coverage:

- Power sword.
- Thunder hammer.
- Force sword.
- Ogryn shovels and clubs with useful melee specials.
- Shotguns with special shell behavior.
- Rippergun bayonet and thumper/rumbler bash.

Red flags:

- Suitable special-capable weapons never log `special_action`.
- Prelude logs appear but the following light/heavy attack does not.
- Shotgun special arms repeatedly without spend.
- Bash/bayonet specials spam against targets where normal fire or melee is
  expected.

## 9. Targeting And Type Switching

This covers the decision to stay ranged, swap to melee, aim at weakspots, and
avoid bad targets.

Expected evidence:

- Type-switch logs show stable ranged/melee choices for the current weapon and
  target class.
- Anti-armor and close-range family logs keep ranged target type where intended.
- Weakspot aim logs appear for weapons that should exploit weakspots.
- Special-case threats such as poxbursters, mutants, trappers, dogs, bosses,
  and armor packs receive appropriate target priority or suppression.

Red flags:

- Bots constantly flip target type without committing to actions.
- Anti-armor ranged weapons abandon armored targets at useful range.
- Weakspot-capable weapons never use weakspot aim in a weakspot scenario.
- Bots shoot or blitz targets inside passive daemonhost danger radius when the
  suppression rule should prevent it.

## 10. Pickups, Pocketables, And Books

This covers ammo, grenades, stims, medi-packs, ammo crates, scriptures, and
grimoires. Explicit player tags and proactive bot pickups must be interpreted
differently.

Expected evidence:

- Explicit tags route through smart-tag orders.
- Ordered mule pickup materializes into `mule_pickup`.
- Proactive pickup assignment occurs when no human needs the slot or the human
  slot is already full.
- Pocketable pickup blocks defer to humans only when the human can actually use
  the slot.
- Stims/books tagged for bots are not cleared by the human-slot-open deferral.
- `cleared stale mule pickup ref` appears only for genuinely stale/deleted
  pickup references.

Red flags:

- A bot receives `assigned ordered mule pickup` and then immediately
  `blocked pocketable ... human_slot_open`.
- Invalid `bot dead` reasons while all bots are visibly alive.
- Bots walk back toward a pickup after teleport/follow, but never take it.
- Books or stims are tag-routed but never become active pickup movement.
- Ammo/grenade pickups starve bots that are actually low.

## 11. Movement, Hazards, And Safety

This covers daemonhosts, barrels, ground danger zones, ledges, and safety
suppression around abilities and ranged attacks.

Expected evidence:

- Hazard props log `hazard_prop triggered` and `hazard_prop buffered threat`
  with a real radius.
- Ground danger zones emit accepted/consumed AOE threat markers.
- Daemonhost scan/candidate logs appear when a passive or awakened-but-not-
  aggroed daemonhost is nearby.
- Bots avoid entering daemonhost danger radius where possible, but do not get
  permanently blocked on stairs or narrow paths.
- Ranged/blitz/dash suppression applies to targets inside daemonhost danger
  radius without disabling all combat elsewhere.

Red flags:

- Barrels explode or start fusing with no hazard prop threat logs.
- Danger-zone markers appear but movement never reacts.
- Daemonhost exists near the bots, but no scan/candidate/suppression markers
  appear.
- Movement avoidance rubber-bands bots backwards or blocks stairs/narrow
  passages.
- Bots dash, sprint, blitz, or throw grenades into passive daemonhost danger
  radius.
- Ledge avoidance blocks stairs, ramps, or ordinary traversal.

## 12. Revive, Rescue, And Objective Protection

This is still core release coverage because many ability rules intentionally
interact with teammate state.

Expected evidence:

- Rescue/revive paths still complete in game.
- Defensive ability logs appear before risky rescue/objective interactions
  when enemies are close.
- `protect_interactor` or equivalent objective-protection rules trigger under
  pressure.
- The bot can leave combat, revive/rescue, then re-enter combat.

Red flags:

- Ability logic prevents rescue/revive movement.
- Support abilities fire repeatedly after the danger is gone.
- Bots abandon revive/rescue due to pickup, hazard, or target switching loops.

## 13. Performance And Hot Path Sanity

Use this after changes touching per-frame scans, targeting, ability decisions,
or movement safety.

Expected evidence:

- `bb-perf:auto` summaries stay in the normal range for the machine and map.
- No one per-frame bucket grows sharply compared to recent known-good runs.
- Extra trace logging is disabled or accounted for when judging performance.
- Debug logs are deduped/throttled and do not emit every frame per bot.

Red flags:

- Ability decisions, hazard scans, pickup scans, or daemonhost scans dominate
  the update budget.
- A false decision path runs every eligible bot frame with no cooldown/backoff.
- Log volume explodes during idle or near-static situations.

## Release Soak Coverage

Before a major release, aim for at least these sessions:

1. Mixed horde pressure: horde plus elites/specials to exercise abilities,
   grenades/blitzes, melee light/heavy selection, targeting, and revives.
2. Weapon-family coverage: roster with ADS, hipfire, charge-fire,
   anti-armor, sustained-fire, powered melee, shotgun, and Ogryn special paths
   where possible.
3. Safety/resource coverage: passive daemonhost, barrels, ground danger zones,
   ledges/stairs, smart-tagged stims/books, ammo/grenade pickups, and at least
   one rescue/revive.

Useful scenario/manual additions:

- Mixed horde with armor and specials.
- Passive daemonhost with an enemy spawned near or inside its danger radius.
- Barrel fuse/explosion near bots.
- Ground danger zone near a target.
- Stairs/ledge traversal near a hazard.
- Smart-tag stim/book while human slot is empty, then with human slot full.
- Mauler/crusher weakspot and anti-armor ranged checks.

## Closure Rule

For each feature area, record one of:

- `pass`: setup and expected follow-through are both visible.
- `partial`: some expected evidence exists, but the run lacks full coverage.
- `not exercised`: roster, weapon, enemy mix, or scenario never triggered it.
- `suspicious`: setup exists, follow-through is missing or contradictory.
- `fail`: wrong behavior is logged or visible and has a concrete repro path.

Only close a regression concern from `pass` evidence. `Partial` is acceptable
for ordinary session notes, but not for closing a bug or release-blocking
concern unless the untested part is explicitly out of scope.
