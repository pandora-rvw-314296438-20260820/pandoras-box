#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_CODESPACE="pandora-apk-phone-local-9b682e35-pgv447759jc96xg"
EXPECTED_SHA256="db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f"
EXPECTED_SIZE="119940817"
APK_NAME="pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/$APK_NAME"
SERVE_DIR="/tmp/pandora-public-apk"
OUT="$SERVE_DIR/$APK_NAME"
STATUS_DIR=".pandora-public-handoff"
STATUS_FILE="$STATUS_DIR/status.json"
LOG_FILE="$STATUS_DIR/handoff.log"
RESULT_BRANCH="build/phone-local-ai-public-handoff-9b682e35-20260920"
PORT=9114
mkdir -p "$SERVE_DIR" "$STATUS_DIR"
: > "$LOG_FILE"

publish() {
  git config user.name "Pandora Public APK Handoff"
  git config user.email "pandora-apk-handoff@users.noreply.github.com"
  git add -f "$STATUS_DIR"
  git commit -m "build(android): verify public APK handoff 9b682e35" >>"$LOG_FILE" 2>&1 || true
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$LOG_FILE" 2>&1 || true
}
trap publish EXIT

{
  echo "Artifact handoff only; no model inference."
  gh codespace cp -e -c "$SOURCE_CODESPACE" "remote:$REMOTE_APK" "$OUT"
  ACTUAL_SHA="$(sha256sum "$OUT" | awk '{print $1}')"
  ACTUAL_SIZE="$(stat -c '%s' "$OUT")"
  test "$ACTUAL_SHA" = "$EXPECTED_SHA256"
  test "$ACTUAL_SIZE" = "$EXPECTED_SIZE"

  nohup python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$SERVE_DIR" >/tmp/pandora-apk-http.log 2>&1 &
  sleep 3
  curl --fail --silent --show-error --head "http://127.0.0.1:$PORT/$APK_NAME" > "$STATUS_DIR/local-head.txt"

  set +e
  gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" > "$STATUS_DIR/visibility.txt" 2>&1
  VIS_RC=$?
  gh codespace ports -c "$CODESPACE_NAME" > "$STATUS_DIR/ports.txt" 2>&1
  PORTS_RC=$?
  set -e

  PUBLIC_URL="https://$CODESPACE_NAME-$PORT.app.github.dev/$APK_NAME"
  PUBLIC_HTTP=""

  if [[ "$VIS_RC" -eq 0 ]]; then
    for i in $(seq 1 12); do
      set +e
      HTTP_CODE="$(curl -L --silent --show-error --output /dev/null --write-out '%{http_code}' "$PUBLIC_URL")"
      CURL_RC=$?
      set -e
      echo "attempt=$i rc=$CURL_RC http=$HTTP_CODE url=$PUBLIC_URL" >> "$STATUS_DIR/public-check.txt"
      if [[ "$CURL_RC" -eq 0 && "$HTTP_CODE" =~ ^2 ]]; then
        PUBLIC_HTTP="$HTTP_CODE"
        break
      fi
      sleep 5
    done
  fi

  python3 - "$STATUS_FILE" "$ACTUAL_SHA" "$ACTUAL_SIZE" "$VIS_RC" "$PORTS_RC" "$PUBLIC_URL" "$PUBLIC_HTTP" <<'PY'
import json,sys,datetime
sha,size,vis,ports,url,http=sys.argv[2:]
ok=(sha=="db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f"
    and size=="119940817" and vis=="0" and http.startswith("2"))
json.dump({
  "outcome":"passed" if ok else "failed",
  "sourceSha":"9b682e3593afc2c0f53630d6ec95454d886afbe9",
  "apkSha256":sha,
  "apkSizeBytes":int(size),
  "port":9114,
  "visibilityCommandRc":int(vis),
  "portsCommandRc":int(ports),
  "publicUrl":url,
  "publicHttpStatus":int(http) if http else None,
  "generatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(sys.argv[1],"w"),indent=2)
PY
  cat "$STATUS_FILE"
} >>"$LOG_FILE" 2>&1
