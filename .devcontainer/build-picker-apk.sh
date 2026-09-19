#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_SHA="a5d5b60551e5c4f02c8aa14c8af4d8b3a268b082"
LLAMA_CPP_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
FLUTTER_SHA="4cf24164269a5ebf0c16a028a00727d0e77bbb05"
REPO="pandora-rvw-314296438-20260820/pandoras-box"
BUILD_BRANCH="fix/local-ai-picker-codespace-build-20260919"
TAG="pandora-local-ai-picker-a5d5b605"
ASSET="Pandora-Local-AI-picker-a5d5b605.apk"
WORKSPACE="$(git rev-parse --show-toplevel)"
LOG="$WORKSPACE/.devcontainer/build.log"
STATUS="$WORKSPACE/.devcontainer/build-status.json"
TAIL="$WORKSPACE/.devcontainer/build-tail.log"
STEP="bootstrap"
APK_SHA=""
APK_SIZE=""
RELEASE_URL=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export GH_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
BUILD_ID="picker-a5d5-20260919"
CALLBACK_NONCE="$PANDORA_BUILD_NONCE"
test -n "$CALLBACK_NONCE"
CALLBACK_URL="https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-local-ai-build-callback-20260919"
TUNNEL_URL=""

report_status() {
  r_status="$1"
  r_step="$2"
  r_code="$3"
  r_tunnel="${4:-}"
  python3 - "$BUILD_ID" "$r_status" "$r_step" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$r_tunnel" "$r_code" <<'PY' >/tmp/pandora-build-report.json
import json,sys
build_id,status,step,source,sha,size,tunnel,code=sys.argv[1:]
print(json.dumps({
  "build_id": build_id,
  "status": status,
  "step": step,
  "source_sha": source,
  "apk_sha256": sha or None,
  "apk_size_bytes": int(size) if size else None,
  "tunnel_url": tunnel or None,
  "detail": "exitCode=" + code,
}))
PY
  curl -fsS -X POST "$CALLBACK_URL" \
    -H "x-pandora-build-nonce: $CALLBACK_NONCE" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/pandora-build-report.json >/dev/null || true
}

exec > >(tee "$LOG") 2>&1

put_receipt() {
  remote_path="$1"
  local_file="$2"
  message="$3"
  [ -s "$local_file" ] || return 0
  encoded="$(base64 -w0 "$local_file")"
  existing="$(gh api "repos/$REPO/contents/$remote_path?ref=$BUILD_BRANCH" --jq .sha 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    gh api --method PUT "repos/$REPO/contents/$remote_path" \
      -f message="$message" -f content="$encoded" -f branch="$BUILD_BRANCH" -f sha="$existing" >/dev/null
  else
    gh api --method PUT "repos/$REPO/contents/$remote_path" \
      -f message="$message" -f content="$encoded" -f branch="$BUILD_BRANCH" >/dev/null
  fi
}

record_status() {
  code=$?
  trap - EXIT
  status="failed"
  if [ "$code" -eq 0 ]; then status="success"; fi
  tail -n 200 "$LOG" > "$TAIL" || true
  python3 - "$STATUS" "$status" "$code" "$STEP" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$RELEASE_URL" "$STARTED_AT" <<'PY'
import json,sys,datetime
path,status,code,step,source,sha,size,url,started=sys.argv[1:]
payload={
  "schema":"pandora.codespace-apk-build.v1",
  "status":status,
  "exitCode":int(code),
  "step":step,
  "sourceSha":source,
  "apkSha256":sha or None,
  "apkSizeBytes":int(size) if size else None,
  "releaseUrl":url or None,
  "startedAtUtc":started,
  "finishedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),
}
open(path,"w",encoding="utf-8").write(json.dumps(payload,indent=2)+"\n")
PY
  report_status "$status" "$STEP" "$code" "$TUNNEL_URL" || true
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    put_receipt ".devcontainer/build-status.json" "$STATUS" "chore: record exact local AI APK build status" || true
    put_receipt ".devcontainer/build-tail.log" "$TAIL" "chore: record exact local AI APK build diagnostics" || true
  fi
  exit "$code"
}
trap record_status EXIT
report_status "running" "bootstrap" 0 ""

STEP="install-host-tools"
sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn.sources
sudo find /etc/apt/sources.list.d -maxdepth 1 -type f -iname '*yarn*' -delete 2>/dev/null || true
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip zip xz-utils libglu1-mesa git python3 openjdk-17-jdk ca-certificates

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export FLUTTER_ROOT="$HOME/flutter"
export PATH="$FLUTTER_ROOT/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

STEP="install-android-sdk"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd /tmp
curl -fL --retry 4 -o android-cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
echo "4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583  android-cmdline.zip" | sha256sum -c -
rm -rf /tmp/android-cmdline
mkdir -p /tmp/android-cmdline
unzip -q android-cmdline.zip -d /tmp/android-cmdline
mv /tmp/android-cmdline/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;29.0.13113456" "cmake;3.31.6"

STEP="install-flutter"
rm -rf "$FLUTTER_ROOT"
git clone --filter=blob:none https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
git -C "$FLUTTER_ROOT" checkout --detach "$FLUTTER_SHA"
test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_SHA"
flutter --version
flutter config --android-sdk "$ANDROID_SDK_ROOT"

STEP="checkout-exact-source"
EXACT=/tmp/pandora-exact
rm -rf "$EXACT"
git -C "$WORKSPACE" fetch origin "$SOURCE_SHA" --depth=1
git -C "$WORKSPACE" worktree add --detach "$EXACT" "$SOURCE_SHA"
test "$(git -C "$EXACT" rev-parse HEAD)" = "$SOURCE_SHA"

STEP="materialize-flutter-project"
BUILD=/tmp/pandora-mobile-build
rm -rf "$BUILD"
flutter create --platforms=android,web --org com.banataosystems --project-name pandora_mobile "$BUILD"
cp -R "$EXACT/apps/pandora-mobile/platform/android/." "$BUILD/android/"
git init -q "$BUILD/android/llama.cpp"
git -C "$BUILD/android/llama.cpp" remote add origin https://github.com/ggml-org/llama.cpp.git
git -C "$BUILD/android/llama.cpp" fetch --depth 1 origin "$LLAMA_CPP_SHA"
git -C "$BUILD/android/llama.cpp" checkout -q --detach FETCH_HEAD
test "$(git -C "$BUILD/android/llama.cpp" rev-parse HEAD)" = "$LLAMA_CPP_SHA"
mkdir -p "$BUILD/android/app/src/main/kotlin/com/arm/aichat/internal"
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/AiChat.kt" "$BUILD/android/app/src/main/kotlin/com/arm/aichat/AiChat.kt"
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt" "$BUILD/android/app/src/main/kotlin/com/arm/aichat/InferenceEngine.kt"
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt" "$BUILD/android/app/src/main/kotlin/com/arm/aichat/internal/InferenceEngineImpl.kt"
rm -rf "$BUILD/lib" "$BUILD/test" "$BUILD/assets"
cp -R "$EXACT/apps/pandora-mobile/lib" "$BUILD/lib"
cp -R "$EXACT/apps/pandora-mobile/test" "$BUILD/test"
cp -R "$EXACT/apps/pandora-mobile/assets" "$BUILD/assets"
cp -R "$EXACT/apps/pandora-mobile/platform" "$BUILD/platform"
cp "$EXACT/apps/pandora-mobile/pubspec.yaml" "$BUILD/pubspec.yaml"
cp "$EXACT/apps/pandora-mobile/pubspec.lock" "$BUILD/pubspec.lock"
cp "$EXACT/apps/pandora-mobile/analysis_options.yaml" "$BUILD/analysis_options.yaml"
python3 "$EXACT/apps/pandora-mobile/tool/configure_validation_android.py" "$BUILD/android/app/src/main/AndroidManifest.xml"
python3 "$EXACT/apps/pandora-mobile/tool/configure_local_ai_android.py" "$BUILD/android/app/build.gradle.kts" "$BUILD/android/gradle.properties"

STEP="resolve-lockfile"
cd "$BUILD"
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

STEP="test-local-router"
flutter test test/core/local_ai/pandora_local_ai_router_test.dart --reporter expanded

STEP="build-arm64-apk"
flutter build apk --debug --target-platform android-arm64 --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" --dart-define=PANDORA_APP_VERSION=0.4.0-rc.4+11
APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
test -f "$APK"

STEP="verify-apk"
AAPT="$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt"
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner"
ZIPALIGN="$ANDROID_SDK_ROOT/build-tools/36.0.0/zipalign"
"$AAPT" dump badging "$APK" | tee /tmp/badging.txt
grep -Fq "package: name='com.banataosystems.pandora_mobile'" /tmp/badging.txt
grep -Fq "native-code: 'arm64-v8a'" /tmp/badging.txt
"$APKSIGNER" verify --verbose --print-certs "$APK"
"$ZIPALIGN" -c -v 4 "$APK" >/tmp/zipalign.txt
grep -Fq "Verification successful" /tmp/zipalign.txt
APK_SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
APK_SIZE="$(stat -c '%s' "$APK")"

STEP="publish-download-tunnel"
APK_DIR="$(dirname "$APK")"
nohup python3 -m http.server 9114 --bind 127.0.0.1 --directory "$APK_DIR" >/tmp/pandora-apk-http.log 2>&1 &
curl -fL --retry 4 -o /tmp/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /tmp/cloudflared
nohup /tmp/cloudflared tunnel --url http://127.0.0.1:9114 --no-autoupdate >/tmp/cloudflared.log 2>&1 &

for _ in $(seq 1 45); do
  base="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log | head -n1 || true)"
  if [ -n "$base" ]; then
    TUNNEL_URL="$base/app-debug.apk"
    break
  fi
  sleep 1
done
test -n "$TUNNEL_URL"
report_status "success" "download-ready" 0 "$TUNNEL_URL"

STEP="complete"
echo "PANDORA_APK_READY source=$SOURCE_SHA sha256=$APK_SHA size=$APK_SIZE download=$TUNNEL_URL"
