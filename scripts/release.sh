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
  - Requires: git, zip, gh
  - Runs: make check, make package, creates/pushes annotated tag.
  - CI handles GitHub release creation; script uploads ZIP artifact.
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
require_cmd zip
require_cmd gh

require_clean_git

TAG="v$VERSION_ARG"

echo "Release: $TAG"
echo "Running checks..."
make check

echo "Building package..."
make package

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists locally: $TAG"
else
  git tag -a "$TAG" -m "$TAG"
fi

echo "Pushing commit + tag..."
git push
git push origin "$TAG"

echo "Waiting for GitHub release to be created by CI..."
for i in $(seq 1 12); do
  if gh release view "$TAG" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "BetterBots.zip"; then
  echo "BetterBots.zip already attached by CI — skipping upload."
else
  echo "Uploading BetterBots.zip to release..."
  gh release upload "$TAG" BetterBots.zip --clobber
fi

echo "Done. Release: https://github.com/hummat/BetterBots/releases/tag/$TAG"
