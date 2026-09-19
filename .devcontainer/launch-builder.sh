#!/usr/bin/env bash
set -u
ROOT="/workspaces/pandoras-box"
cd "$ROOT" || exit 1
CALLBACK_URL="https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-local-ai-build-callback-20260919"
NONCE="$PANDORA_BUILD_NONCE"
BUILD_ID="picker-a5d5-20260919"
SOURCE_SHA="a5d5b60551e5c4f02c8aa14c8af4d8b3a268b082"
test -n "$NONCE" || exit 2

report() {
  status="$1"
  step="$2"
  detail="$3"
  python3 - "$BUILD_ID" "$status" "$step" "$SOURCE_SHA" "$detail" <<'PY' >/tmp/launcher-report.json
import json,sys
build_id,status,step,source,detail=sys.argv[1:]
print(json.dumps({
  "build_id":build_id,
  "status":status,
  "step":step,
  "source_sha":source,
  "detail":detail
}))
PY
  curl -fsS -X POST "$CALLBACK_URL" \
    -H "x-pandora-build-nonce: $NONCE" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/launcher-report.json >/dev/null || true
}

report "launcher" "post-create-entered" "launcher-started"

nohup bash "$ROOT/.devcontainer/build-picker-apk.sh" </dev/null >/tmp/pandora-picker-build.log 2>&1 &
pid=$!
echo "$pid" >/tmp/pandora-picker-build.pid
sleep 2
if kill -0 "$pid" 2>/dev/null; then
  report "launcher" "detached-running" "pid-alive"
else
  report "failed" "detached-launch" "pid-died"
  exit 1
fi
exit 0
