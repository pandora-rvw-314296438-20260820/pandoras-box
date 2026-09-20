#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_CODESPACE="pandora-apk-phone-local-r7pgjj7jjvjvfxg54"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/pandora-phone-local-ef373c82d436ae06fd459b5356272bcab84bcc66.apk"
APK_NAME="pandora-phone-local-ef373c82d436ae06fd459b5356272bcab84bcc66.apk"
EXPECTED_SHA256="497ce08beb987e1704d096d9b4d942df03da495fdd8a76794f84c5cbd5a55ba8"
EXPECTED_SIZE="119958129"
WORK="/tmp/pandora-storage-handoff"
APK="$WORK/$APK_NAME"
STATUS_DIR=".pandora-storage-handoff"
RESULT_BRANCH="build/phone-local-ai-storage-handoff-ef373c82-20260920"
TOKEN_ENDPOINT="https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-flutter-test-repair-20260830"
UPLOAD_BASE="https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/upload/sign/pandora-apk-public"
PUBLIC_URL="https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/public/pandora-apk-public/$APK_NAME"

mkdir -p "$WORK" "$STATUS_DIR"
: > "$STATUS_DIR/handoff.log"

publish_status() {
  set +e
  git config user.name "Pandora APK Storage Handoff"
  git config user.email "pandora-apk-storage@users.noreply.github.com"
  git add -f "$STATUS_DIR"
  git commit -m "build(android): verify static Qwen3 APK handoff" >>"$STATUS_DIR/handoff.log" 2>&1
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$STATUS_DIR/handoff.log" 2>&1
  set -e
}
trap publish_status EXIT

{
  echo "Transport only; no inference."
  rm -f "$APK"
  gh codespace cp -e -c "$SOURCE_CODESPACE" "remote:$REMOTE_APK" "$APK"

  ACTUAL_SHA="$(sha256sum "$APK" | awk '{print $1}')"
  ACTUAL_SIZE="$(stat -c '%s' "$APK")"
  echo "copied_sha=$ACTUAL_SHA copied_size=$ACTUAL_SIZE"
  test "$ACTUAL_SHA" = "$EXPECTED_SHA256"
  test "$ACTUAL_SIZE" = "$EXPECTED_SIZE"

  TOKEN_JSON="$(curl --fail --silent --show-error --retry 3 --retry-all-errors -X POST     -H 'content-type: application/json'     --data '{}'     "$TOKEN_ENDPOINT")"
  TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<<"$TOKEN_JSON")"
  test -n "$TOKEN"

  UPLOAD_URL="$UPLOAD_BASE/$APK_NAME?token=$TOKEN"
  curl --fail --silent --show-error     --retry 5 --retry-all-errors --retry-delay 2     --connect-timeout 30 --max-time 900     -X PUT     -H 'Expect:'     -H 'x-upsert: true'     -H 'content-type: application/vnd.android.package-archive'     -H 'cache-control: public, max-age=31536000, immutable'     --data-binary @"$APK"     "$UPLOAD_URL" > "$STATUS_DIR/upload-response.json"

  for i in $(seq 1 20); do
    CODE="$(curl -L --silent --show-error --output /dev/null --write-out '%{http_code}' "$PUBLIC_URL" || true)"
    echo "public_attempt=$i code=$CODE" >> "$STATUS_DIR/handoff.log"
    if [[ "$CODE" = "200" ]]; then break; fi
    sleep 3
  done
  test "$CODE" = "200"

  curl --fail --silent --show-error --head "$PUBLIC_URL" > "$STATUS_DIR/public-head.txt"
  curl --fail --silent --show-error -H 'Range: bytes=0-1' "$PUBLIC_URL" > "$STATUS_DIR/magic.bin"
  MAGIC="$(xxd -p "$STATUS_DIR/magic.bin" | tr -d '\n')"
  test "$MAGIC" = "504b"

  REMOTE_SIZE="$(awk 'BEGIN{IGNORECASE=1} /^content-length:/{gsub("\r","",$2); print $2}' "$STATUS_DIR/public-head.txt" | tail -1)"
  test "$REMOTE_SIZE" = "$EXPECTED_SIZE"

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
  "staticStorage":True,
  "verifiedMagic":"504b",
  "verifiedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(path,"w"),indent=2)
PY

  echo "STATIC_URL=$PUBLIC_URL"
} >>"$STATUS_DIR/handoff.log" 2>&1
