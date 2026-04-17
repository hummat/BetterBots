# Class-Level Regression Invariants

**Date:** 2026-04-17
**Status:** Approved
**Scope:** test-only hardening of three historically weak bug classes

## Problem

The recent audit showed that BetterBots now catches many exact historical regressions, but class-level coverage is still uneven.

Strong areas already exist:
- hook registration / hot-reload install idempotency
- audited mock API surfaces
- many concrete tactical regressions with dedicated specs

Weak areas remain:
- caller/helper integration bugs, where a helper exists but a live call site forgets to use it
- profile schema preservation bugs, where gameplay mutation accidentally drops non-gameplay/UI fields
- session-state recovery bugs, where hot reload preserves hooks but leaves stateful modules inert until a fresh engine transition

The problem is not “missing more one-off bug pins.” The problem is that these three failure classes still rely too much on individual historical regressions rather than broad invariants.

## Goal

Add three narrow, class-level test invariants that raise confidence in the weak areas without building a fake-engine meta-framework.

## Non-Goals

- No production behavior changes unless a new invariant exposes a real bug
- No generic “test framework for everything”
- No attempt to encode semantic engine drift in unit tests
- No replacement for Solo Play smoke validation

## Approach

Add one focused invariant to each existing spec surface that already owns the relevant seam.

### 1. Pre-Queue Suppression Invariant

**File:** `tests/ability_queue_spec.lua`

**Invariant:** once a suppression gate returns `true`, the fallback path must not call `bot_queue_action_input`.

This is broader than the historical team-cooldown bug. Team cooldown remains the concrete trigger used in the spec, but the property under test is queue blocking at the last integration seam before input dispatch.

Why this file:
- `ability_queue.lua` is the live fallback queue path
- historical regressions in this class were caller-side integration mistakes, not helper-module logic bugs

What to assert:
- the semantic key reaches the suppression gate
- suppression aborts queueing
- the assertion is framed as “no queue after suppression,” not just “Veteran shout special case”

### 2. Profile Schema Preservation Invariant

**File:** `tests/bot_profiles_spec.lua`

**Invariant:** resolving a vanilla bot profile may mutate gameplay fields in place, but it must preserve a curated non-gameplay/UI subtree.

The preserved subtree is intentionally narrow and source-driven:
- `visual_loadout`
- `loadout_item_ids`
- `loadout_item_data`
- cosmetic loadout slots used by the UI contract

Why this file:
- this is where the profile mutation logic lives
- the historical crash came from preserving gameplay successfully while silently dropping UI/cosmetic structure

What to assert:
- the incoming profile table is mutated in place, not replaced
- the curated UI/cosmetic tables keep identity
- required cosmetic slots still exist after mutation

### 3. Stateful Hot-Reload Recovery Invariant

**File:** `tests/startup_regressions_spec.lua`

**Invariant:** bootstrap after hot reload must restore session-scoped EventLog-style behavior without waiting for `on_game_state_changed` to refire.

This is intentionally scoped to the real bootstrap seam, not to internal module helpers. The property is that reload restores working state from load-time context.

Why this file:
- startup regressions already own bootstrap wiring and hot-reload idempotency
- the historical failure happened even though hooks remained installed

What to assert:
- event logging is re-enabled on load when the setting is on and alive bots already exist
- post-load emission works immediately
- no fresh game-state transition is needed to recover functionality

## Helper Policy

Tiny helper refactors are allowed only if they remove repeated setup across at least two invariants.

Rules:
- prefer local helpers inside the owning spec file
- only promote helpers into `tests/test_helper.lua` if at least two specs genuinely share them
- do not introduce a generic assertion framework

## Testing Strategy

1. Add or reshape the invariant spec first
2. Run the targeted spec file and verify the new case fails if the behavior is absent
3. Implement the minimal code only if the invariant exposes a real gap
4. Re-run the targeted spec
5. Re-run the touched spec files together, then run `make check-ci` if any production code changed

Primary commands:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ability_queue_spec.lua
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/bot_profiles_spec.lua
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/startup_regressions_spec.lua
```

## Risks

- **Over-abstraction in tests:** mitigated by keeping one invariant per owning spec and avoiding shared test frameworks
- **False confidence from over-mocked invariants:** mitigated by anchoring each invariant at the highest realistic seam already present in the repo
- **Spec drift into exact-bug pinning again:** mitigated by phrasing assertions as properties of the seam, not of a single historical incident

## Success Criteria

The change is successful if:
- each weak bug class has one explicit invariant at the correct seam
- the invariants stay test-only unless they expose a real bug
- the repo gains broader regression protection without more fake-engine sprawl
