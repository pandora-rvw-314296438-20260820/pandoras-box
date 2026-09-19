#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_CODESPACE="pandora-apk-phone-local-qvpqwwvwwr79hxrrq"
SOURCE_SHA="5b2d5aa97c49b67ecb3d7ee935fc3b56b733e8af"
REPO="pandora-rvw-314296438-20260820/pandoras-box"
TAG="phone-local-ai-${SOURCE_SHA:0:12}-20260920"
TITLE="Pandora phone-local APK ${SOURCE_SHA:0:12}"
OUT="/tmp/pandora-phone-local-recovery"
STATUS="/tmp/pandora-phone-local-collector-status.json"

mkdir -p "$OUT"
python3 - "$STATUS" <<'PY'
import json,sys,datetime
json.dump({
  "state":"running",
  "sourceSha":"5b2d5aa97c49b67ecb3d7ee935fc3b56b733e8af",
  "targetCodespace":"pandora-apk-phone-local-qvpqwwvwwr79hxrrq",
  "generatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(sys.argv[1],"w"),indent=2)
PY

gh auth status
rm -rf "$OUT/.pandora-codespace-artifact"
gh codespace cp --recursive -c "$TARGET_CODESPACE"   "remote:/workspaces/pandoras-box/.pandora-codespace-artifact" "$OUT/"

ART="$OUT/.pandora-codespace-artifact"
test -d "$ART"
test -s "$ART/status.json"
test -s "$ART/build.log"

OUTCOME="$(python3 - "$ART/status.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get("outcome",""))
PY
)"

if [[ "$OUTCOME" == "passed" ]]; then
  test -s "$ART/manifest.txt"
  APK="$(find "$ART" -maxdepth 1 -type f -name '*.apk' -print -quit)"
  test -n "$APK"
  test -s "$APK"
  test "$(cat "$ART/flutter-analyze.exit")" = "0"
  test "$(cat "$ART/local-ai-router-test.exit")" = "0"

  gh release delete "$TAG" --repo "$REPO" --yes >/dev/null 2>&1 || true
  git tag -d "$TAG" >/dev/null 2>&1 || true
  git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true

  mapfile -d '' ASSETS < <(find "$ART" -maxdepth 1 -type f -print0)
  gh release create "$TAG" "${ASSETS[@]}"     --repo "$REPO"     --target "$SOURCE_SHA"     --title "$TITLE"     --notes-file "$ART/manifest.txt"     --draft
fi

python3 - "$STATUS" "$OUTCOME" <<'PY'
import json,sys,datetime
json.dump({
  "state":"complete",
  "sourceSha":"5b2d5aa97c49b67ecb3d7ee935fc3b56b733e8af",
  "targetCodespace":"pandora-apk-phone-local-qvpqwwvwwr79hxrrq",
  "buildOutcome":sys.argv[2],
  "generatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(sys.argv[1],"w"),indent=2)
PY
