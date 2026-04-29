# Weakspot Aim MVP Design

Date: 2026-04-12
Issue: #91

## Problem

Vanilla bot ranged aim resolves target bone through:

1. `target_breed.override_bot_target_node`
2. `scratchpad.aim_at_node` from `weapon_template.attack_meta_data`
3. fallback `"j_spine"`

In practice, nearly every ranged weapon falls through to `"j_spine"`, so bots aim center mass and waste finesse scaling, weakspot blessings, and weakspot-oriented perk value. The documented vanilla exception is `high_bot_lasgun_killshot.lua`, which already uses:

```lua
aim_at_node = {
	"j_head",
	"j_spine",
}
```

That establishes two useful facts:

- the engine already supports a table of candidate aim nodes
- random head/spine selection is already a shipped vanilla pattern for bot shooting

The gap is not engine capability. The gap is missing metadata on the weapons BetterBots actually gives to bots.

## Decision

Implement strict `#91` MVP only:

- inject `attack_meta_data.aim_at_node = { "j_head", "j_spine" }`
- only for a narrow finesse-weapon allowlist
- only when `attack_meta_data.aim_at_node` is currently unset

No breed-specific overrides, no runtime shoot hook, no ADS changes, and no attempt to distinguish front/back armor weakspots. Those remain follow-up work in `#92` and `#41`.

## Weapon Scope

Initial MVP allowlist was exactly:

- lasguns
- autoguns
- stub revolvers
- bolters

This was expanded on 2026-04-29 to align weakspot eligibility with the later
anti-armor ranged policy: plasma guns, bolt pistols, and heavy stubbers now
join the original finesse set.

This should be identified from weapon template family signals already present on the template, primarily keywords. The design goal is family-level targeting without hardcoding every individual mark.

Explicitly out of scope for the initial MVP:

- staffs
- autopistols
- bolt pistols
- shotpistols
- flamers
- plasma guns
- shotguns
- thrown weapons and grenades

## Rationale

This slice is worth shipping because it is:

- small: one metadata injection layer, no BT or action-node surgery
- low risk: it reuses the vanilla `aim_at_node` contract instead of inventing new aiming behavior
- testable: unit tests can prove allowlist behavior and merge semantics without in-game heuristics
- composable: `#92` can later refine special breeds without replacing this layer

Trying to fold `#92` into this MVP would drag in breed-by-breed research, node validation, and special-case policy for enemies where head aim is wrong or inconsistent. That is separate work and should stay separate.

## Scope

### In scope

- `ranged_meta_data.lua` allowlist detection
- `attack_meta_data.aim_at_node` injection for eligible ranged families
- tests covering family allowlist, skip paths, and non-overwrite behavior

### Out of scope

- per-breed weakspot maps (`#92`)
- runtime hooks in `BtBotShootAction`
- `aim_at_node_charged` work
- ADS or hip-fire family logic (`#41`)
- balance tuning for hit probability, recoil, or fire cadence

## Architecture

Keep this entirely inside `scripts/mods/BetterBots/ranged_meta_data.lua`.

Add two small helpers:

1. family detection helper
   - returns true for templates in the MVP allowlist
   - prefers keyword-based detection so all marks in a family are covered
   - may fall back to template-name pattern only where keyword coverage is insufficient

2. weakspot injection helper
   - if template is allowlisted and `attack_meta_data.aim_at_node == nil`, set:

```lua
{
	"j_head",
	"j_spine",
}
```

This should run in the existing `inject(WeaponTemplates)` pass, alongside the current ranged metadata correction logic.

## Merge Rules

The weakspot injection must obey these rules:

1. Never overwrite an existing `attack_meta_data.aim_at_node`.
2. If `attack_meta_data` already exists for other reasons, merge only the missing `aim_at_node` field.
3. If `attack_meta_data` does not exist and the weapon otherwise needs no ranged-input correction, create a minimal table containing only `aim_at_node`.
4. Leave non-allowlisted ranged weapons unchanged.

This preserves compatibility with future vanilla metadata and with any weapon templates that already define a specific target node.

## Detection Rules

Preferred family signals:

- `lasgun` keyword
- `autogun` keyword
- `bolter` keyword
- `stub_pistol` keyword for the two stub revolver templates BetterBots can hand to bots

`stub_pistol` is intentionally narrower than a generic "pistol" check, but still broader than enumerating individual template names. It keeps the MVP simple while avoiding bolt pistol and autopistol spillover.

If implementation discovers an ambiguity that cannot be cleanly resolved from keywords alone, the fallback is a narrow template-name check for the affected family only. Do not expand beyond the roadmap allowlist.

## Logging

No new dedicated debug spam.

The existing `ranged attack_meta_data patch installed (...)` summary log may count these injections as part of the injection/patch totals. That is enough for MVP. No new per-weapon log lines are needed.

## Tests

Extend `tests/ranged_meta_data_spec.lua` with coverage for:

1. allowlisted weapon with no `attack_meta_data`
   - injection creates `attack_meta_data.aim_at_node`
   - value equals `{ "j_head", "j_spine" }`

2. allowlisted weapon with existing `attack_meta_data`
   - merge adds `aim_at_node`
   - existing fields stay intact

3. allowlisted weapon with existing `aim_at_node`
   - field is preserved, not overwritten

4. non-allowlisted ranged weapon
   - no weakspot injection occurs

5. existing ranged-input correction path plus allowlisted family
   - both corrections can coexist in one injected/merged table

The tests should not try to simulate actual headshot outcomes. That belongs to in-game validation, not unit tests.

## Docs To Update After Implementation

- `docs/dev/roadmap.md` — move `#91` from planned to implemented-on-branch state
- `docs/dev/status.md` — record implementation status for v0.11.0 batch
- `docs/dev/architecture.md` — note the new weakspot metadata injection behavior in `ranged_meta_data.lua`
- `docs/bot/vanilla-capabilities.md` and/or `docs/bot/combat-actions.md` if the repo wants explicit "BetterBots now overrides vanilla center-mass default for allowlisted families"

## Acceptance Criteria

- Allowlisted ranged weapon families gain `attack_meta_data.aim_at_node = { "j_head", "j_spine" }` when unset.
- Existing `aim_at_node` values are preserved.
- Non-allowlisted ranged weapons are unchanged.
- Existing ranged fire/aim metadata fixes still behave the same.
- Unit tests cover allowlist hit, skip, merge, and preserve cases.
- Scope remains strict MVP `#91`, with no breed-specific logic folded in.
