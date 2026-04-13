#!/usr/bin/env bash
# Verify documentation claims against code and GitHub issue state.
# Catches stale heuristic function counts and closed-but-listed-open issues.
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

for f in AGENTS.md docs/dev/debugging.md; do
  # Match lines like "18 per-template heuristic functions" or "18 `_can_activate_*` heuristic functions"
  while IFS= read -r match; do
    claimed=$(echo "$match" | grep -oP '\b\d+(?=\s+(per-template\s+)?heuristic\s+function)')
    if [[ -n "$claimed" && "$claimed" != "$actual_heuristic_count" ]]; then
      err "$f claims $claimed heuristic functions, code has $actual_heuristic_count"
    fi
  done < <(grep -nP '\d+\s+(per-template\s+)?heuristic\s+function' "$f" 2>/dev/null || true)
done

ok "heuristic function count: $actual_heuristic_count"

# ── 2. GitHub issue state vs docs ────────────────────────────────────────────

# NOTE: In CI, ensure GH_TOKEN or GITHUB_TOKEN is exported for issue state checks.
if command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1; then
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
  echo " info: gh CLI not available or not authenticated — skipping issue state checks"
fi

# ── 3. Module count + name parity ────────────────────────────────────────────

# Every *.lua file under scripts/mods/BetterBots/ must be mentioned by basename
# in both README.md (repo layout block) and AGENTS.md (mod file structure block).
# Catches the drift where new modules ship without being listed in user-facing docs.

actual_module_count=$(find scripts/mods/BetterBots -maxdepth 1 -name '*.lua' | wc -l | tr -d ' ')

for f in README.md AGENTS.md; do
  while IFS= read -r match; do
    claimed=$(echo "$match" | grep -oP '\b\d+(?=\s+modules?\b)')
    if [[ -n "$claimed" && "$claimed" != "$actual_module_count" ]]; then
      err "$f claims $claimed modules, repo has $actual_module_count"
    fi
  done < <(grep -nP '\b\d+\s+modules?\b' "$f" 2>/dev/null || true)
done

missing_in_readme=()
missing_in_agents=()
for module_file in scripts/mods/BetterBots/*.lua; do
  base=$(basename "$module_file")
  grep -qF "$base" README.md || missing_in_readme+=("$base")
  grep -qF "$base" AGENTS.md  || missing_in_agents+=("$base")
done
if ((${#missing_in_readme[@]} > 0)); then
  err "README.md repo layout missing modules: ${missing_in_readme[*]}"
fi
if ((${#missing_in_agents[@]} > 0)); then
  err "AGENTS.md mod file structure missing modules: ${missing_in_agents[*]}"
fi

ok "module count: $actual_module_count (parity verified across README + AGENTS)"

# ── 4. Test count + spec name parity ─────────────────────────────────────────

# Every tests/*_spec.lua file must be mentioned in AGENTS.md (the test list).
# Test count claims in README + AGENTS.md must match the live busted run.

missing_specs=()
for spec_file in tests/*_spec.lua; do
  [ -f "$spec_file" ] || continue
  base=$(basename "$spec_file")
  grep -qF "$base" AGENTS.md || missing_specs+=("$base")
done
if ((${#missing_specs[@]} > 0)); then
  err "AGENTS.md test list missing specs: ${missing_specs[*]}"
fi

# Resolve a busted runner the same way the Makefile does, then count "X successes"
busted_bin="$(command -v busted 2>/dev/null || command -v lua-busted 2>/dev/null || true)"
if [[ -z "$busted_bin" ]]; then
  busted_bin="$(ls /usr/lib/luarocks/rocks-*/busted/*/bin/busted 2>/dev/null | head -n 1 || true)"
  [[ -n "$busted_bin" ]] && busted_bin="lua $busted_bin"
fi

if [[ -n "$busted_bin" && -d tests ]]; then
  # shellcheck disable=SC2086
  test_output=$($busted_bin 2>&1 || true)
  actual_test_count=$(echo "$test_output" | grep -oP '\b\d+(?=\s+successes\b)' | tail -1)
  if [[ -n "$actual_test_count" ]]; then
    for f in README.md AGENTS.md; do
      while IFS= read -r match; do
        claimed=$(echo "$match" | grep -oP '\b\d+(?=\s+(unit\s+)?tests?\b)')
        if [[ -n "$claimed" && "$claimed" != "$actual_test_count" ]]; then
          err "$f claims $claimed tests, busted reports $actual_test_count (line: $match)"
        fi
      done < <(grep -nP '\b\d+\s+(unit\s+)?tests?\b' "$f" 2>/dev/null || true)
    done
    ok "test count: $actual_test_count (parity verified across README + AGENTS)"
  else
    warn "could not parse busted success count; skipping test count parity"
  fi
else
  echo " info: busted not available — skipping test count parity"
fi

# ── 5. Audited mock helper enforcement ───────────────────────────────────────

# Current hard enforcement is scoped to audited ScriptUnit extension families.
# Specs must route these through tests/test_helper.lua builders rather than
# ad-hoc table literals. This catches regressions where impossible engine APIs
# get reintroduced into the suite.

audited_extension_regex='unit_data_system|ability_system|action_input_system|perception_system|smart_tag_system|companion_spawner_system|coherency_system|talent_system'

direct_assignment_matches=$(rg -nP "\b(${audited_extension_regex})\s*=\s*\{" tests/*_spec.lua 2>/dev/null || true)
if [[ -n "$direct_assignment_matches" ]]; then
  err "audited ScriptUnit extension mocks must use tests/test_helper.lua builders, found ad-hoc table literals:
$direct_assignment_matches"
fi

direct_return_matches=$(rg -nUP "has_extension\\s*=\\s*function[\\s\\S]{0,220}\"(${audited_extension_regex})\"[^\\n]*then\\s*\\n\\s*return\\s*\\{" tests/*_spec.lua 2>/dev/null || true)
if [[ -n "$direct_return_matches" ]]; then
  err "audited ScriptUnit.has_extension mocks must not return raw table literals for audited systems:
$direct_return_matches"
fi

extension_return_matches=$(rg -nUP "extension\\s*=\\s*function[\\s\\S]{0,220}\"(${audited_extension_regex})\"[^\\n]*then\\s*\\n\\s*return\\s*\\{" tests/*_spec.lua 2>/dev/null || true)
if [[ -n "$extension_return_matches" ]]; then
  err "audited ScriptUnit.extension mocks must not return raw table literals for audited systems:
$extension_return_matches"
fi

ok "audited ScriptUnit extension mocks route through shared builders"

# ── 6. Summary ───────────────────────────────────────────────────────────────

echo ""
if ((errors > 0)); then
  echo "doc-check: $errors error(s), $warnings warning(s)"
  exit 1
elif ((warnings > 0)); then
  echo "doc-check: $warnings warning(s), 0 errors"
  exit 1
else
  echo "doc-check: all checks passed"
  exit 0
fi
