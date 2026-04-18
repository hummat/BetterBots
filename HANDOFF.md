## Current State

- Branch: `dev/v1.0.0`
- Sprint 1 is code-complete in repo docs.
- `#13` and `#92` are labeled `needs-testing` on GitHub.
- `#86` remains deferred; only the timing investigation is done.

## This Session

- Fixed `#13` validator geometry:
  - targeted Zealot dash validates against the actual enemy target, not just nav destination
  - rescue charges validate against the explicit ally aim point
  - directional charges still fall back to `navigation_extension:destination()` when no better endpoint exists
- Reordered fallback rescue aim so aim is applied before nav validation.
- Added regression coverage for both bugs.
- Synced docs to the corrected behavior.

## Verification

- `make check` passes
- latest local result before handoff:
  - `1134 successes / 0 failures / 0 errors / 0 pending`

## Next Steps

1. Run in-game verification for `#13` and `#92`.
2. If validation passes, decide whether to close or relabel `#13` / `#92`.
3. Start Sprint 2 (`#38`) after Sprint 1 field verification is done.
