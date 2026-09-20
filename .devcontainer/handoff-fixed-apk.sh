#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_CODESPACE="pandora-apk-phone-local-9b682e35-pgv447759jc96xg"
SOURCE_SHA="9b682e3593afc2c0f53630d6ec95454d886afbe9"
EXPECTED_SHA256="db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f"
EXPECTED_SIZE="119940817"
REPO="pandora-rvw-314296438-20260820/pandoras-box"
TAG="phone-local-ai-9b682e3593af-20260920"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
OUT_DIR="/tmp/pandora-apk-handoff"
OUT_APK="$OUT_DIR/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
STATUS_DIR=".pandora-apk-handoff"
STATUS_FILE="$STATUS_DIR/status.json"
LOG_FILE="$STATUS_DIR/transfer.log"
RESULT_BRANCH="build/phone-local-ai-apk-handoff-9b682e35-20260920"
mkdir -p "$OUT_DIR" "$STATUS_DIR"
: > "$LOG_FILE"
write_status() {
  local outcome="$1"; local detail="$2"; local actual_sha="${3:-}"; local actual_size="${4:-}"
  python3 - "$STATUS_FILE" "$outcome" "$detail" "$actual_sha" "$actual_size" <<'PY'
import json,sys,datetime
json.dump({
  "outcome": sys.argv[2],
  "detail": sys.argv[3],
  "sourceSha": "9b682e3593afc2c0f53630d6ec95454d886afbe9",
  "expectedApkSha256": "db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f",
  "actualApkSha256": sys.argv[4] or None,
  "actualApkSizeBytes": int(sys.argv[5]) if sys.argv[5] else None,
  "sourceCodespace": "pandora-apk-phone-local-9b682e35-pgv447759jc96xg",
  "releaseTag": "phone-local-ai-9b682e3593af-20260920",
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
  git commit -m "build(android): record fixed APK handoff 9b682e35" >>"$LOG_FILE" 2>&1
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$LOG_FILE" 2>&1
  set -e
}
trap publish_status EXIT
{
  echo "Artifact handoff only; no model inference."
  gh auth status
  rm -f "$OUT_APK"
  gh codespace cp -e -c "$SOURCE_CODESPACE" "remote:$REMOTE_APK" "$OUT_APK"
  test -s "$OUT_APK"
  ACTUAL_SHA="$(sha256sum "$OUT_APK" | awk '{print $1}')"
  ACTUAL_SIZE="$(stat -c '%s' "$OUT_APK")"
  echo "actual_sha256=$ACTUAL_SHA"
  echo "actual_size=$ACTUAL_SIZE"
  if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA256" || "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    write_status "failed" "Copied APK did not match verified build hash/size." "$ACTUAL_SHA" "$ACTUAL_SIZE"
    exit 1
  fi
  gh release delete "$TAG" --repo "$REPO" --yes >/dev/null 2>&1 || true
  git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true
  gh release create "$TAG" "$OUT_APK"     --repo "$REPO"     --target "$SOURCE_SHA"     --title "Pandora phone-local acceptance candidate 9b682e3593af"     --notes "FIXED PHONE-LOCAL ACCEPTANCE CANDIDATE. Exact source $SOURCE_SHA. APK SHA-256 $ACTUAL_SHA. Context 2048, batch 256, warm diagnostics/recovery hardened. Physical phone inference still requires acceptance."     --prerelease
  write_status "passed" "Verified fixed APK copied and published as private GitHub prerelease." "$ACTUAL_SHA" "$ACTUAL_SIZE"
} >>"$LOG_FILE" 2>&1
