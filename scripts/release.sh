#!/usr/bin/env bash
set -euo pipefail

VERSION_ARG="${1:-}"

if [[ "${VERSION_ARG}" == "-h" || "${VERSION_ARG}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  scripts/release.sh VERSION

Example:
  scripts/release.sh 0.2.0

Notes:
  - Requires: git
  - Runs: make check, creates/pushes annotated tag. CI handles GitHub release.
EOF
  exit 0
fi

if [[ -z "$VERSION_ARG" ]]; then
  echo "Usage: scripts/release.sh VERSION" >&2
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

require_clean_git() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree is dirty. Commit or stash changes before releasing." >&2
    exit 2
  fi
}

require_cmd git

require_clean_git

TAG="v$VERSION_ARG"

echo "Release: $TAG"
echo "Running checks..."
make check

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists: $TAG" >&2
  exit 2
fi

git tag -a "$TAG" -m "$TAG"

echo "Pushing commit + tag..."
git push
git push origin "$TAG"

echo "Done. Tag push will trigger release.yml workflow."
