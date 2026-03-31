# Fix #65: Profile Overwrite Guard for Non-Veteran Bots

**Date:** 2026-03-31
**Issue:** [#65](https://github.com/hummat/BetterBots/issues/65) — P0: Non-veteran bot profiles crash on Darktide 1.11.0 (Warband)

## Problem

Non-veteran bot profiles (Zealot, Psyker, Ogryn) cause a native CTD during bot spawn on Darktide 1.11.0+. Veteran and "None" profiles work. Root cause: a lossy JSON roundtrip overwrites the BotPlayer's profile with a degraded reconstruction, creating a mismatch with already-loaded packages.

### Crash chain

1. BetterBots' `add_bot` hook resolves a full profile (archetype table, blessed weapons, curated talents, cosmetics).
2. `BotSynchronizerHost.update()` serializes the profile to JSON via `ProfileUtils.pack_profile()` — this converts archetype to string and nils `loadout`/`visual_loadout`.
3. BotPlayer is created with the correct BetterBots profile; the package synchronizer loads packages from this profile.
4. Profile sync completes: `ProfileSynchronizerClient` calls `player:set_profile(ProfileUtils.unpack_profile(json))` — **overwrites** the BotPlayer's profile with the JSON-reconstructed version.
5. The reconstructed profile has:
   - Loadout regenerated from `loadout_item_data` (lossy: only `{ id = item.name }`, no blessings/perks/base_stats).
   - Talents run through `validate_talent_layouts` + `_validate_talent_items` (new in 1.11) — may strip talents.
6. `unit_templates.lua:local_init` reads the overwritten profile. Items/talents no longer match loaded packages. Native crash (C++ resource assertion, empty Lua callstack).

**Why veteran works:** The reconstruction is functionally identical — same archetype, same talent pool, same item catalog. No mismatch.

### Key 1.11 source locations

| File | Lines | What changed |
|------|-------|--------------|
| `unit_templates.lua` | 334-337, 1037-1040 | New `validate_talent_layouts` call, gated by `not profile.is_local_profile` |
| `profile_utils.lua` | 525-547 | `_convert_profile_from_lookups_to_data` now calls `validate_talent_layouts` + `_validate_talent_items` |
| `talent_layout_parser.lua` | 269-313 | `validate_talent_layouts`: `table.clear` + `table.merge` mutates talents in-place |
| `profile_synchronizer_client.lua` | 107-109 | `player:set_profile(unpack_profile(json))` overwrites BotPlayer profile |

## Solution

Two changes in `bot_profiles.lua`:

### 1. Tag resolved profiles

In `resolve_profile()`, after modifying the profile (after current line 803), set:

```lua
profile.is_local_profile = true   -- engine: bypass validate_talent_layouts in unit_templates.lua
profile._bb_resolved = true       -- mod-owned: guard set_profile hook
```

- `is_local_profile` is only checked in `unit_templates.lua` (two identical blocks). Setting it to `true` skips talent validation for our curated builds. The flag survives JSON serialization (`pack_profile` doesn't strip it).
- `_bb_resolved` is a BetterBots-owned sentinel, separate from the engine flag. Used exclusively in the `set_profile` hook guard.

### 2. Hook `BotPlayer.set_profile`

In `register_hooks()`, add:

```lua
_mod:hook("BotPlayer", "set_profile", function(func, self, profile)
    if self._profile and self._profile._bb_resolved then
        return
    end
    return func(self, profile)
end)
```

Blocks the network-sync overwrite for BetterBots-resolved profiles. Vanilla bots and other mods' profiles pass through unchanged.

## What this does NOT change

- Profile resolution logic (`_resolve_profile_template`) — unchanged.
- Weapon overrides, talents, cosmetics — unchanged.
- Package synchronization — already correct (reads from BotPlayer before overwrite).
- The `add_bot` hook — unchanged.

## Trade-offs

| Concern | Assessment |
|---------|------------|
| `is_local_profile` semantics | Only checked in `unit_templates.lua`. No other engine behavior depends on it. Safe. |
| Blocking `set_profile` | Bot profiles don't change mid-mission in vanilla. If another mod calls `set_profile` on a BetterBots bot, it would be blocked. Acceptable — the alternative (lossless JSON roundtrip) requires matching engine internals that change between patches. |
| Talent validation bypass | Our talents are sourced from real player builds (hadrons-blessing). They're valid by construction. Tree version changes (veteran v28→v29, psyker v13→v15) don't affect our talent selections. |

## Tests

Add to `tests/bot_profiles_spec.lua`:

- `resolve_profile` sets `is_local_profile = true` and `_bb_resolved = true` on swapped profiles.
- `resolve_profile` does NOT set these flags on pass-through profiles (setting="none", Tertium yield, slot overflow).
- `register_hooks` registers both `BotSynchronizerHost.add_bot` and `BotPlayer.set_profile` hooks.

## Follow-up (not part of this fix)

- Check `poxburster.lua` for `side.ai_target_units` → `side.ai_ground_target_units` rename (1.11 API change).
- In-game validation: test Zealot/Psyker/Ogryn profiles on 1.11.x after deploying this fix.
