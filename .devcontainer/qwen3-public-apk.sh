#!/usr/bin/env bash
set -Eeuo pipefail
TARGET_CODESPACE="pandora-apk-phone-local-r7pgjj7jjvjvfxg54"
SOURCE_SHA="ef373c82d436ae06fd459b5356272bcab84bcc66"
APK_NAME="pandora-phone-local-ef373c82d436ae06fd459b5356272bcab84bcc66.apk"
EXPECTED_SHA256="497ce08beb987e1704d096d9b4d942df03da495fdd8a76794f84c5cbd5a55ba8"
EXPECTED_SIZE="119958129"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/$APK_NAME"
SERVE_DIR="/tmp/pandora-qwen3-apk"
OUT_APK="$SERVE_DIR/$APK_NAME"
STATUS_DIR=".pandora-qwen3-public-handoff"
RESULT_BRANCH="build/phone-local-ai-qwen3-public-handoff-ef373c82-20260920"
PORT=9114

mkdir -p "$SERVE_DIR" "$STATUS_DIR"
: > "$STATUS_DIR/handoff.log"

publish_status() {
  set +e
  git config user.name "Pandora Qwen3 APK Handoff"
  git config user.email "pandora-qwen3-apk@users.noreply.github.com"
  git add -f "$STATUS_DIR"
  git commit -m "build(android): verify Qwen3 APK public handoff ef373c82" >>"$STATUS_DIR/handoff.log" 2>&1
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$STATUS_DIR/handoff.log" 2>&1
  set -e
}
trap publish_status EXIT

{
  echo "Copying exact verified APK; no inference runs here."
  gh auth status
  gh codespace cp -e -c "$TARGET_CODESPACE" "remote:$REMOTE_APK" "$OUT_APK"

  ACTUAL_SHA="$(sha256sum "$OUT_APK" | awk '{print $1}')"
  ACTUAL_SIZE="$(stat -c '%s' "$OUT_APK")"
  echo "sha=$ACTUAL_SHA size=$ACTUAL_SIZE"
  test "$ACTUAL_SHA" = "$EXPECTED_SHA256"
  test "$ACTUAL_SIZE" = "$EXPECTED_SIZE"

  nohup python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$SERVE_DIR" >"$STATUS_DIR/http.log" 2>&1 &
  sleep 3
  curl --fail --silent --show-error --head "http://127.0.0.1:$PORT/$APK_NAME" > "$STATUS_DIR/local-head.txt"

  gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" > "$STATUS_DIR/visibility.txt" 2>&1
  gh codespace ports -c "$CODESPACE_NAME" > "$STATUS_DIR/ports.txt" 2>&1

  PUBLIC_URL="https://$CODESPACE_NAME-$PORT.app.github.dev/$APK_NAME"
  OK=0
  for i in $(seq 1 20); do
    CODE="$(curl -L --silent --show-error --output /dev/null --write-out '%{http_code}' "$PUBLIC_URL" || true)"
    echo "attempt=$i http=$CODE url=$PUBLIC_URL" >> "$STATUS_DIR/public-check.txt"
    if [[ "$CODE" = "200" ]]; then
      OK=1
      break
    fi
    sleep 3
  done
  test "$OK" = "1"

  python3 - "$STATUS_DIR/status.json" "$PUBLIC_URL" "$ACTUAL_SHA" "$ACTUAL_SIZE" <<'PY'
import json,sys,datetime
path,url,sha,size=sys.argv[1:]
json.dump({
  "outcome":"passed",
  "sourceSha":"ef373c82d436ae06fd459b5356272bcab84bcc66",
  "apkSha256":sha,
  "apkSizeBytes":int(size),
  "qwen3Sha256":"1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6",
  "publicUrl":url,
  "httpVerified":True,
  "generatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(path,"w"),indent=2)
PY
} >> "$STATUS_DIR/handoff.log" 2>&1
