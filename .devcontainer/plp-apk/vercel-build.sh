#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
export PANDORA_SOURCE_ROOT="$ROOT"
export PANDORA_SOURCE_SHA="${VERCEL_GIT_COMMIT_SHA:-$(git rev-parse HEAD)}"
export PANDORA_SOURCE_TREE="$(git rev-parse HEAD^{tree})"

bash "$ROOT/.devcontainer/plp-apk/build.sh"

rm -rf "$ROOT/public"
mkdir -p "$ROOT/public/chunks" "$ROOT/public/evidence"
cp "$ROOT/dist/PLP-Pandora-Enterprise-manifest.txt" "$ROOT/public/"
cp "$ROOT/dist/android-badging.txt" "$ROOT/public/evidence/"
cp "$ROOT/dist/android-permissions.txt" "$ROOT/public/evidence/"
cp "$ROOT/dist/android-signing.txt" "$ROOT/public/evidence/"
split -b 45000000 -d -a 3 --additional-suffix=.bin   "$ROOT/dist/PLP-Pandora-Enterprise.apk"   "$ROOT/public/chunks/PLP-Pandora-Enterprise.part-"
find "$ROOT/public/chunks" -type f -name '*.bin' -print0 | sort -z | xargs -0 sha256sum   > "$ROOT/public/PLP-Pandora-Enterprise-chunks.sha256"
printf '%s
' '<!doctype html><meta charset="utf-8"><title>PLP Pandora Enterprise APK</title><h1>PLP Pandora Enterprise APK artifact</h1>'   > "$ROOT/public/index.html"
