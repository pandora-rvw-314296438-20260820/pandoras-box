#!/usr/bin/env bash
set -Eeuo pipefail
TARGET_CODESPACE="pandora-apk-phone-local-r7pgjj7jjvjvfxg54"
PORT=9114
APK_NAME="pandora-phone-local-${base}.apk"
EXPECTED_SHA256="497ce08beb987e1704d096d9b4d942df03da495fdd8a76794f84c5cbd5a55ba8"
EXPECTED_SIZE="119958129"
RESULT_BRANCH="build/phone-local-ai-public-link-ef373c82-20260920"
OUT=".pandora-public-link"
mkdir -p "$OUT"
: > "$OUT/handoff.log"

publish() {
  git config user.name "Pandora Public Link Verifier"
  git config user.email "pandora-public-link@users.noreply.github.com"
  git add -f "$OUT"
  git commit -m "build(android): verify public Qwen3 APK link" >>"$OUT/handoff.log" 2>&1 || true
  git push --force origin "HEAD:refs/heads/$RESULT_BRANCH" >>"$OUT/handoff.log" 2>&1 || true
}
trap publish EXIT

{
  gh auth status
  gh codespace ports visibility "$PORT:public" -c "$TARGET_CODESPACE"
  gh codespace ports -c "$TARGET_CODESPACE" > "$OUT/ports.txt"
  URL="https://$TARGET_CODESPACE-$PORT.app.github.dev/$APK_NAME"
  : > "$OUT/public-head.txt"
  ok=0
  for i in $(seq 1 12); do
    curl -L --silent --show-error --head "$URL" > "$OUT/public-head.txt" || true
    code="$(awk '/^HTTP\//{c=$2} END{print c}' "$OUT/public-head.txt")"
    size="$(awk 'BEGIN{IGNORECASE=1} /^content-length:/{gsub("\r","",$2); s=$2} END{print s}' "$OUT/public-head.txt")"
    echo "attempt=$i code=$code size=$size url=$URL" >> "$OUT/handoff.log"
    if [[ "$code" = "200" && "$size" = "$EXPECTED_SIZE" ]]; then ok=1; break; fi
    sleep 5
  done
  python3 - "$OUT/status.json" "$URL" "$ok" <<'PY'
import json,sys,datetime
path,url,ok=sys.argv[1:]
json.dump({
 "outcome":"passed" if ok=="1" else "failed",
 "sourceSha":"ef373c82d436ae06fd459b5356272bcab84bcc66",
 "apkSha256":"497ce08beb987e1704d096d9b4d942df03da495fdd8a76794f84c5cbd5a55ba8",
 "apkSizeBytes":119958129,
 "qwen3AcceptanceSha256":"1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6",
 "publicUrl":url,
 "verifiedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat()
},open(path,"w"),indent=2)
PY
  test "$ok" = "1"
} >> "$OUT/handoff.log" 2>&1
