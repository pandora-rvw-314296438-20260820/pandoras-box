#!/usr/bin/env bash
set -u

ROOT="/workspaces/pandoras-box"
if [ ! -d "$ROOT/.git" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$ROOT" || exit 1
mkdir -p .devcontainer

trigger="${1:-unknown}"
printf '%s trigger=%s rev=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$trigger" "${PANDORA_BUILDER_REV:-unset}" >> .devcontainer/kick-history.log

nohup bash -c '
  exec 9>/tmp/pandora-local-ai-picker-build.lock
  flock -n 9 || exit 0
  cd /workspaces/pandoras-box || exit 1
  bash .devcontainer/build-picker-apk.sh
' >> .devcontainer/kick.log 2>&1 &

exit 0
