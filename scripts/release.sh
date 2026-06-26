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
  - Runs: make patch-check-refresh, make check, make package, creates/pushes annotated tag.
  - CI handles GitHub release creation; script uploads ZIP artifact.
EOF
  exit 0
fi

if [[ -z "$VERSION_ARG" ]]; then
  echo "Usage: scripts/release.sh VERSION" >&2
  exit 2
fi

if [[ ! "$VERSION_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be X.Y.Z (got: '$VERSION_ARG')" >&2
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
PACKAGE_ASSET="BetterBots.zip"

release_exists() {
  gh release view "$TAG" >/dev/null 2>&1
}

release_asset_exists() {
  gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "$PACKAGE_ASSET"
}

echo "Release: $TAG"
echo "Running patch drift gate..."
make patch-check-refresh

echo "Running checks..."
make check

if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "make check produced formatter changes. Commit them, then re-run release." >&2
	git --no-pager diff --stat >&2
	exit 2
fi

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
for _ in $(seq 1 12); do
  if release_exists; then
    break
  fi
  sleep 5
done

if ! release_exists; then
  echo "CI did not create release $TAG within timeout. Check the release workflow, then re-run." >&2
  exit 2
fi

echo "Waiting for $PACKAGE_ASSET from CI..."
for _ in $(seq 1 24); do
  if release_asset_exists; then
    echo "$PACKAGE_ASSET already attached by CI; skipping upload."
    echo "Done. Release: https://github.com/hummat/BetterBots/releases/tag/$TAG"
    exit 0
  fi
  sleep 5
done

echo "CI did not attach $PACKAGE_ASSET within timeout; uploading local package..."
upload_log="$(mktemp)"
if gh release upload "$TAG" "$PACKAGE_ASSET" --clobber 2>"$upload_log"; then
  rm -f "$upload_log"
elif grep -q "ReleaseAsset.name already exists" "$upload_log" && release_asset_exists; then
  echo "$PACKAGE_ASSET appeared during upload fallback; treating as success."
  rm -f "$upload_log"
else
  cat "$upload_log" >&2
  rm -f "$upload_log"
  exit 2
fi

echo "Done. Release: https://github.com/hummat/BetterBots/releases/tag/$TAG"
