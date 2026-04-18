#!/usr/bin/env bash
# Cloud-session setup: clone Darktide decompiled source into a sibling
# directory so CLAUDE.md's `../Darktide-Source-Code/` reference resolves.
# No-op when not in a Claude Code cloud session.

set -eu

LOG=/tmp/bb-cloud-setup.log
exec > >(tee -a "$LOG") 2>&1

echo "[cloud-setup] $(date -Iseconds) SessionStart fired"
echo "[cloud-setup] CLAUDE_CODE_REMOTE=${CLAUDE_CODE_REMOTE:-unset}"
echo "[cloud-setup] CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-unset}"
echo "[cloud-setup] cwd=$(pwd)"

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "[cloud-setup] not in cloud (CLAUDE_CODE_REMOTE != true), exiting 0"
  exit 0
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo "[cloud-setup] CLAUDE_PROJECT_DIR unset, cannot place sibling clone; exiting 0"
  exit 0
fi

PARENT="$(dirname "$CLAUDE_PROJECT_DIR")"
TARGET="$PARENT/Darktide-Source-Code"

if [ -d "$TARGET/.git" ]; then
  echo "[cloud-setup] already present at $TARGET"
else
  echo "[cloud-setup] cloning Aussiemon/Darktide-Source-Code into $TARGET"
  git clone --depth 1 https://github.com/Aussiemon/Darktide-Source-Code.git "$TARGET"
fi

LUA_COUNT=$(find "$TARGET" -name '*.lua' 2>/dev/null | wc -l)
echo "[cloud-setup] done; $LUA_COUNT Lua files at $TARGET"
