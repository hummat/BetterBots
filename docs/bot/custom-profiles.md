# Custom Bot Profiles

BetterBots does not have an in-game profile editor. The manual route is to edit
`scripts/mods/BetterBots/bot_profile_templates.lua`, reload the mod, and let the existing profile resolver do the
same checks it uses for the built-in bot templates.

This is still source editing, so it is easy to break with a typo. A bad weapon path usually falls back to the vanilla
bot profile with a warning. A bad talent key is worse: Darktide's profile parser can crash when a talent key does not
exist for that class. Copy exact strings from the generated reference instead of translating names yourself.

## Files

| File | Purpose |
| --- | --- |
| `scripts/mods/BetterBots/bot_profile_templates.lua` | The actual bot class templates used at runtime. |
| `docs/bot/profile-authoring-reference.md` | Generated lookup tables for weapon paths, talent keys, perk paths, and blessing paths. |
| `scripts/profile-authoring-reference.py` | Regenerates the lookup tables from a local [`hadrons-blessing`](https://github.com/hummat/hadrons-blessing) checkout. |

Regenerate the reference after updating [`hadrons-blessing`](https://github.com/hummat/hadrons-blessing):

```bash
make profile-authoring-reference
```

## Editing A Profile

1. Open `scripts/mods/BetterBots/bot_profile_templates.lua`.
2. Pick the class entry under `M.DEFAULT_PROFILE_TEMPLATES`.
3. Change only one part at a time: weapons, weapon overrides, or talents.
4. Copy exact paths and keys from `docs/bot/profile-authoring-reference.md`.
5. If you are editing from a source checkout, run the local checks before launching:

```bash
make test
make doc-check
```

Manual edits are local source edits. Updating the mod from Nexus or replacing the checkout can overwrite them.

## Weapon Example

Weapon paths go into the `loadout` table:

```lua
loadout = {
	slot_primary = "content/items/weapons/player/melee/powersword_p1_m2",
	slot_secondary = "content/items/weapons/player/ranged/plasmagun_p1_m1",
},
```

The left side is fixed: `slot_primary` is melee and `slot_secondary` is ranged. The right side must be a full item
path from the generated `Weapon loadout paths` table.

## Perk And Blessing Example

Perks and blessings live under `weapon_overrides`:

```lua
weapon_overrides = {
	slot_secondary = {
		traits = {
			_trait_override(_trait_id("plasmagun_p1", "crit_chance_scaled_on_heat")),
			_trait_override(_trait_id("plasmagun_p1", "reduced_overheat_on_critical_strike")),
		},
		perks = {
			_perk_override(_perk_id("ranged_common", "wield_increase_armored_damage")),
			_perk_override(_perk_id("ranged_common", "wield_increase_resistant_damage")),
		},
	},
},
```

The generated reference gives the expanded paths. The helpers above are just shorter forms:

| Helper | Expanded path |
| --- | --- |
| `_trait_id("plasmagun_p1", "crit_chance_scaled_on_heat")` | `content/items/traits/bespoke_plasmagun_p1/crit_chance_scaled_on_heat` |
| `_perk_id("ranged_common", "wield_increase_armored_damage")` | `content/items/perks/ranged_common/wield_increase_armored_damage` |

Blessing display names are not enough. The same in-game blessing family can use different engine paths on different
weapon families, so copy the row for the weapon family you are editing.

## Talent Example

Talents are a flat table of engine keys:

```lua
talents = {
	veteran_combat_ability_stagger_nearby_enemies = 1,
	veteran_krak_grenade = 1,
	veteran_aura_gain_ammo_on_elite_kill_improved = 1,
	veteran_improved_tag = 1,
	veteran_all_kills_replenish_toughness = 1,
},
```

Use keys from the matching class section only. Do not copy a zealot key into a veteran profile, and do not invent a
key from an in-game display name.

## Practical Limits

Human meta builds are not automatically good bot builds. Bots do not animation-cancel, aim, dodge, hold peril, or
use weapon specials like a human player. Prefer simple, durable picks: defensive auras, low-maintenance keystones,
weapons that work with vanilla bot ranged/melee behavior, and blessings that do not depend on precise human timing.

If a profile fails in-game, check `bb-log warnings` first. Profile resolution failures are logged there when
BetterBots can recover.
