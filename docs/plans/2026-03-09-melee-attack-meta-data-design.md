# Design: Smart Melee Attack Selection (#23)

## Problem

No melee weapon (bot or player) defines `attack_meta_data` with the melee-specific
fields (`arc`, `penetrating`, `action_inputs`). The `_choose_attack` scoring in
`bt_bot_melee_action.lua` falls back to `DEFAULT_ATTACK_META_DATA` — a single
light attack entry with `arc=0, penetrating=false`. Bots never use heavy attacks
and ignore target armor type entirely.

The scoring logic itself is already armor/horde-aware (+8 for penetrating vs armored,
+4 for sweeps when outnumbered). The gap is purely data.

## Solution

New module `melee_meta_data.lua` — runs once at load time, auto-derives and injects
`attack_meta_data` for all melee `WeaponTemplates`.

### Derivation pipeline (per weapon)

1. Filter `WeaponTemplates` by `keywords` containing `"melee"`
2. Skip weapons that already have `attack_meta_data`
3. Find light/heavy attack actions via the action graph
4. For each attack action, resolve the damage profile from `DamageProfileTemplates`
5. Derive `arc` from `cleave_distribution`:
   - `no_cleave`, `single_cleave` → `arc = 0`
   - `light_cleave`, `double_cleave`, `medium_cleave` → `arc = 1`
   - `large_cleave`, `big_cleave` → `arc = 2`
6. Derive `penetrating` from `armor_damage_modifier[armored].attack`:
   - `>= 0.5` → `penetrating = true`
   - `< 0.5` → `penetrating = false`
7. Hardcode `action_inputs`:
   - Light: `{start_attack, 0}, {light_attack, 0}`
   - Heavy: `{start_attack, 0}, {heavy_attack, 0}`
8. Hardcode `max_range = 2.5` (engine default)

### Integration

- New file: `scripts/mods/BetterBots/melee_meta_data.lua`
- Called from `BetterBots.lua` init, same pattern as `meta_data.inject()`
- Same `require()` mutation approach — mutates cached `WeaponTemplates` table
- Idempotent guard (`_patched_set`) for hot-reload safety

### Scoring (unchanged)

`_choose_attack` already scores:
- `+1` for arc==1 when outnumbered
- `+2` for no-damage + arc>1 when massively outnumbered (>3)
- `+4` for damaging sweep when outnumbered, or focused attack vs single target
- `+8` for penetrating attack vs armored, or any attack vs non-armored

No changes to scoring logic needed.

## Out of scope

- Per-weapon hand-authored tables (fully auto-derived instead)
- `max_range` derivation from action configs
- Weapon special actions (#33)
- Push/shove `attack_meta_data` entries (bots already push via `defense_meta_data`)
- Changes to `_choose_attack` scoring

## Risk

If a weapon uses non-standard action input names (not `start_attack`/`light_attack`/
`heavy_attack`), the bot queues an invalid input. The attack silently fails and the
bot falls back to not attacking — same as current behavior. Detectable via debug logs,
fixable with a per-weapon override table.

## Testing

- Unit tests: cleave→arc mapping, armor modifier→penetrating mapping, injection
  idempotency, existing metadata preservation
- In-game: batch test on `dev/m4-batch1` — verify bots use heavy attacks vs armored
  enemies and sweep attacks vs hordes
