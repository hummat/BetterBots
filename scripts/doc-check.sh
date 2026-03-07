#!/usr/bin/env bash
# Verify documentation claims against code and GitHub issue state.
# Catches stale counts, closed-but-listed-open issues, and phantom percentages.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

errors=0
warnings=0

err()  { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN:  $*" >&2; warnings=$((warnings + 1)); }
ok()   { echo "  ok:  $*"; }

# ── 1. Heuristic function count ──────────────────────────────────────────────

actual_heuristic_count=$(grep -c '^local function _can_activate_' scripts/mods/BetterBots/heuristics.lua)

for f in AGENTS.md docs/DEBUGGING.md; do
  # Match lines like "18 per-template heuristic functions" or "18 `_can_activate_*` heuristic functions"
  # but NOT "117 tests for all 18 heuristic functions" (avoid test-count lines)
  while IFS= read -r match; do
    claimed=$(echo "$match" | grep -oP '\b\d+(?=\s+(per-template\s+)?heuristic\s+function)')
    if [[ -n "$claimed" && "$claimed" != "$actual_heuristic_count" ]]; then
      err "$f claims $claimed heuristic functions, code has $actual_heuristic_count"
    fi
  done < <(grep -nP '\d+\s+(per-template\s+)?heuristic\s+function' "$f" 2>/dev/null || true)
done

ok "heuristic function count: $actual_heuristic_count"

# ── 2. Per-file test counts ──────────────────────────────────────────────────

if [ -d tests ]; then
  total_tests=0
  for spec in tests/*_spec.lua; do
    [ -f "$spec" ] || continue
    base=$(basename "$spec")
    count=$(grep -cP '^\s*it\(' "$spec")
    total_tests=$((total_tests + count))

    # Check AGENTS.md and DEBUGGING.md for stale per-file counts
    for doc in AGENTS.md docs/DEBUGGING.md; do
      match=$(grep -P "$base.*#\s*\d+" "$doc" 2>/dev/null || true)
      if [[ -n "$match" ]]; then
        claimed=$(echo "$match" | grep -oP '\d+(?=\s+test)')
        if [[ -n "$claimed" && "$claimed" != "$count" ]]; then
          err "$doc claims $claimed tests in $base, actual: $count"
        fi
      fi
    done
  done

  # Check total test count
  for doc in AGENTS.md docs/STATUS.md; do
    match=$(grep -oP '\d+(?=\s+unit tests|\s+tests via busted)' "$doc" 2>/dev/null | head -1 || true)
    if [[ -n "$match" && "$match" != "$total_tests" ]]; then
      err "$doc claims $match total tests, actual: $total_tests"
    fi
  done

  ok "test counts: $total_tests total"
fi

# ── 3. Stale percentages in docs ─────────────────────────────────────────────

# META_BUILDS_RESEARCH excluded: its ~nn% are community stats, not code claims
for doc in AGENTS.md docs/STATUS.md docs/ROADMAP.md; do
  matches=$(grep -nP '~\d+%' "$doc" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    while IFS= read -r line; do
      warn "$doc has approximate percentage (may be stale): $line"
    done <<< "$matches"
  fi
done

# ── 4. GitHub issue state vs docs ────────────────────────────────────────────

if command -v gh >/dev/null 2>&1 && gh api user --jq .login >/dev/null 2>&1; then
  closed_issues=$(gh issue list --state closed --limit 100 --json number --jq '.[].number' 2>/dev/null || true)

  if [[ -n "$closed_issues" ]]; then
    # Only check lines in active-work sections (tables with issue numbers as task items)
    # Pattern: "| <number> |" at start of table row — these are the P1/P2/P3 task tables
    for doc in docs/ROADMAP.md docs/STATUS.md; do
      [ -f "$doc" ] || continue
      while IFS= read -r num; do
        # Match table rows where the issue number is the task ID column
        # Require issue number >= 4 to skip tier numbers (1/2/3) in status tables
        [[ "$num" -lt 4 ]] && continue
        matches=$(grep -nP "^\|\s*${num}\s*\|" "$doc" 2>/dev/null || true)
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          if echo "$line" | grep -qiP '~~|shipped|closed|\bDone\b'; then
            continue
          fi
          warn "$doc lists closed issue #$num as active task: $line"
        done <<< "$matches"
      done <<< "$closed_issues"
    done

    # Also check "Next Steps" / "Known Blockers" sections for closed issue references
    doc="docs/STATUS.md"
    if [ -f "$doc" ]; then
      in_next_steps=false
      while IFS= read -r line; do
        if echo "$line" | grep -qiP '^##\s*Next\s*Steps|^##\s*Known\s*Blockers'; then
          in_next_steps=true
          continue
        fi
        if echo "$line" | grep -qP '^##'; then
          in_next_steps=false
          continue
        fi
        if $in_next_steps; then
          while IFS= read -r num; do
            if echo "$line" | grep -qP "\(#${num}\)|#${num}\b"; then
              if ! echo "$line" | grep -qiP '~~|closed|\bDone\b'; then
                warn "$doc lists closed issue #$num in active section: $line"
              fi
            fi
          done <<< "$closed_issues"
        fi
      done < "$doc"
    fi
  fi

  ok "GitHub issue state cross-check done"
else
  warn "gh CLI not available or not authenticated — skipping issue state checks"
fi

# ── 5. Summary ───────────────────────────────────────────────────────────────

echo ""
if ((errors > 0)); then
  echo "doc-check: $errors error(s), $warnings warning(s)"
  exit 1
elif ((warnings > 0)); then
  echo "doc-check: $warnings warning(s), 0 errors"
  exit 0
else
  echo "doc-check: all checks passed"
  exit 0
fi
