#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_CODESPACE="pandora-apk-phone-local-b78f328c-jrq5xxrxxxr73r9w"
SOURCE_SHA="b78f328c467b7d0f3312d1c88cdbe7c00be2c29d"
EXPECTED_SHA256="2775acce3eb32d2446d6541c4e92a338707d714fe66e0c0a536202f238074565"
EXPECTED_SIZE="119941041"
REPO="pandora-rvw-314296438-20260820/pandoras-box"
TAG="phone-local-ai-b78f328c467b-20260920"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/pandora-phone-local-b78f328c467b7d0f3312d1c88cdbe7c00be2c29d.apk"
OUT_DIR="/tmp/pandora-apk-handoff"
OUT_APK="$OUT_DIR/pandora-phone-local-b78f328c467b7d0f3312d1c88cdbe7c00be2c29d.apk"
STATUS_DIR=".pandora-apk-handoff"
STATUS_FILE="$STATUS_DIR/status.json"
LOG_FILE="$STATUS_DIR/transfer.log"
RESULT_BRANCH="build/phone-local-ai-apk-handoff-b78f328c-20260920"

mkdir -p "$OUT_DIR" "$STATUS_DIR"
: > "$LOG_FILE"

write_status() {
  local outcome="$1"
  local detail="$2"
  local actual_sha="${3:-}"
  local actual_size="${4:-}"
  python3 - "$STATUS_FILE" "$outcome" "$detail" "$actual_sha" "$actual_size" <<'PY'
import json,sys,datetime
json.dump({
  "outcome": sys.argv[2],
  "detail": sys.argv[3],
  "sourceSha": "b78f328c467b7d0f3312d1c88cdbe7c00be2c29d",
  "expectedApkSha256": "2775acce3eb32d2446d6541c4e92a338707d714fe66e0c0a536202f238074565",
  "actualApkSha256": sys.argv[4] or None,
  "actualApkSizeBytes": int(sys.argv[5]) if sys.argv[5] else None,
  "sourceCodespace": "pandora-apk-phone-local-b78f328c-jrq5xxrxxxr73r9w",
  "releaseTag": "phone-local-ai-b78f328c467b-20260920",
  "generatedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat()
}, open(sys.argv[1],"w"), indent=2)
PY
}

publish_status() {
  set +e
  git config user.name "Pandora APK Handoff"
  git config user.email "pandora-apk-handoff@users.noreply.github.com"
  git checkout -B "$RESULT_BRANCH" "$SOURCE_SHA" >>"$LOG_FILE" 2>&1
  git add -f "$STATUS_DIR" >>"$LOG_FILE" 2>&1
  git commit -m "build(android): record APK handoff b78f328c467b" >>"$LOG_FILE" 2>&1
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$LOG_FILE" 2>&1
  set -e
}
trap publish_status EXIT

{
  echo "GitHub-only artifact handoff. No model inference is executed here."
  gh auth status
  rm -f "$OUT_APK"
  gh codespace cp -c "$SOURCE_CODESPACE" "remote:$REMOTE_APK" "$OUT_APK"

  test -s "$OUT_APK"
  ACTUAL_SHA="$(sha256sum "$OUT_APK" | awk '{print $1}')"
  ACTUAL_SIZE="$(stat -c '%s' "$OUT_APK")"
  echo "actual_sha256=$ACTUAL_SHA"
  echo "actual_size=$ACTUAL_SIZE"

  if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA256" ]]; then
    write_status "failed" "Copied APK hash did not match the verified build." "$ACTUAL_SHA" "$ACTUAL_SIZE"
    exit 1
  fi
  if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    write_status "failed" "Copied APK size did not match the verified build." "$ACTUAL_SHA" "$ACTUAL_SIZE"
    exit 1
  fi

  gh release delete "$TAG" --repo "$REPO" --yes >/dev/null 2>&1 || true
  git tag -d "$TAG" >/dev/null 2>&1 || true
  git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true

  gh release create "$TAG" "$OUT_APK"     --repo "$REPO"     --target "$SOURCE_SHA"     --title "Pandora phone-local APK b78f328c467b"     --notes "Exact-source arm64 debug APK. SHA-256: $ACTUAL_SHA. Build evidence: build/phone-local-ai-evidence-b78f328c467b-20260920. Physical-device inference remains unverified."     --draft

  write_status "passed" "Exact verified APK copied from compiler Codespace and published as a draft GitHub Release asset." "$ACTUAL_SHA" "$ACTUAL_SIZE"
} >>"$LOG_FILE" 2>&1
