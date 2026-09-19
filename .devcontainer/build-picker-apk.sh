#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_SHA="a5d5b60551e5c4f02c8aa14c8af4d8b3a268b082"
LLAMA_CPP_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
FLUTTER_SHA="4cf24164269a5ebf0c16a028a00727d0e77bbb05"
BUILD_BRANCH="build/picker-a5d5-codespace-compose-20260919"
WORKSPACE="$(git rev-parse --show-toplevel)"
LOG="$WORKSPACE/.devcontainer/build.log"
LIVE="$WORKSPACE/.devcontainer/live-status.json"
STATUS="$WORKSPACE/.devcontainer/build-status.json"
TAIL="$WORKSPACE/.devcontainer/build-tail.log"
OUTPUT="$WORKSPACE/.devcontainer/output"
STEP="bootstrap"
APK_SHA=""
APK_SIZE=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$OUTPUT"
exec > >(tee "$LOG") 2>&1

git -C "$WORKSPACE" config user.name "Pandora GitHub-hosted Builder"
git -C "$WORKSPACE" config user.email "pandora-builder@users.noreply.github.com"

checkpoint() {
  local state="$1"
  local step_name="$2"
  local detail="${3:-}"
  python3 - "$LIVE" "$state" "$step_name" "$detail" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$STARTED_AT" <<'PY'
import json,sys,datetime
path,state,step,detail,source,sha,size,started=sys.argv[1:]
payload={
  "schema":"pandora.github-hosted-build-live.v1",
  "state":state,
  "step":step,
  "detail":detail,
  "sourceSha":source,
  "apkSha256":sha or None,
  "apkSizeBytes":int(size) if size else None,
  "startedAtUtc":started,
  "updatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),
}
open(path,"w",encoding="utf-8").write(json.dumps(payload,indent=2)+"\n")
PY
  git -C "$WORKSPACE" add .devcontainer/live-status.json
  if ! git -C "$WORKSPACE" diff --cached --quiet; then
    git -C "$WORKSPACE" commit -m "build: checkpoint $step_name" >/dev/null || true
    git -C "$WORKSPACE" push origin "HEAD:$BUILD_BRANCH" >/tmp/pandora-checkpoint-push.log 2>&1 || true
  fi
}

step() {
  STEP="$1"
  checkpoint "running" "$STEP" ""
}

finish() {
  local code=$?
  trap - EXIT
  local state="failed"
  if [ "$code" -eq 0 ]; then state="success"; fi
  tail -n 240 "$LOG" > "$TAIL" || true
  python3 - "$STATUS" "$state" "$code" "$STEP" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$STARTED_AT" <<'PY'
import json,sys,datetime
path,state,code,step,source,sha,size,started=sys.argv[1:]
payload={
  "schema":"pandora.github-hosted-apk-build.v1",
  "status":state,
  "exitCode":int(code),
  "step":step,
  "sourceSha":source,
  "apkSha256":sha or None,
  "apkSizeBytes":int(size) if size else None,
  "startedAtUtc":started,
  "finishedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),
}
open(path,"w",encoding="utf-8").write(json.dumps(payload,indent=2)+"\n")
PY
  checkpoint "$state" "$STEP" "exitCode=$code"
  git -C "$WORKSPACE" add .devcontainer/build-status.json .devcontainer/build-tail.log .devcontainer/live-status.json
  if ! git -C "$WORKSPACE" diff --cached --quiet; then
    git -C "$WORKSPACE" commit -m "build: record picker APK result" >/dev/null || true
  fi
  git -C "$WORKSPACE" push origin "HEAD:$BUILD_BRANCH" >/tmp/pandora-final-push.log 2>&1 || true
  exit "$code"
}
trap finish EXIT

checkpoint "running" "bootstrap" "builder-entered"

step "verify-host"
command -v git
command -v curl
command -v python3
command -v unzip
if ! java -version 2>&1 | grep -Eq '"17[.]'; then
  sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn.sources
  sudo find /etc/apt/sources.list.d -maxdepth 1 -type f -iname '*yarn*' -delete 2>/dev/null || true
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
fi
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
java -version

step "install-android-sdk"
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd /tmp
rm -f android-cmdline.zip
curl -fL --retry 4 -o android-cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
echo "4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583  android-cmdline.zip" | sha256sum -c -
rm -rf /tmp/android-cmdline "$ANDROID_SDK_ROOT/cmdline-tools/latest"
mkdir -p /tmp/android-cmdline
unzip -q android-cmdline.zip -d /tmp/android-cmdline
mv /tmp/android-cmdline/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;29.0.13113456" "cmake;3.31.6"

step "install-flutter"
export FLUTTER_ROOT="$HOME/flutter"
rm -rf "$FLUTTER_ROOT"
git clone --filter=blob:none https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
git -C "$FLUTTER_ROOT" checkout --detach "$FLUTTER_SHA"
test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_SHA"
export PATH="$FLUTTER_ROOT/bin:$PATH"
flutter --version
flutter config --no-analytics
flutter config --android-sdk "$ANDROID_SDK_ROOT"

step "checkout-exact-source"
EXACT=/tmp/pandora-exact
rm -rf "$EXACT"
git -C "$WORKSPACE" cat-file -e "$SOURCE_SHA^{commit}"
git -C "$WORKSPACE" worktree add --detach "$EXACT" "$SOURCE_SHA"
test "$(git -C "$EXACT" rev-parse HEAD)" = "$SOURCE_SHA"
grep -Fq 'activity.startActivityForResult(intent, MODEL_PICK_REQUEST)' \
  "$EXACT/apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraLocalAiChannel.kt"
if grep -Fq 'intent.resolveActivity(activity.packageManager)' \
  "$EXACT/apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraLocalAiChannel.kt"; then
  echo "Stale resolveActivity picker guard still present." >&2
  exit 41
fi

step "materialize-flutter-project"
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
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/AiChat.kt" \
  "$BUILD/android/app/src/main/kotlin/com/arm/aichat/AiChat.kt"
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt" \
  "$BUILD/android/app/src/main/kotlin/com/arm/aichat/InferenceEngine.kt"
cp "$BUILD/android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt" \
  "$BUILD/android/app/src/main/kotlin/com/arm/aichat/internal/InferenceEngineImpl.kt"

rm -rf "$BUILD/lib" "$BUILD/test" "$BUILD/assets"
cp -R "$EXACT/apps/pandora-mobile/lib" "$BUILD/lib"
cp -R "$EXACT/apps/pandora-mobile/test" "$BUILD/test"
cp -R "$EXACT/apps/pandora-mobile/assets" "$BUILD/assets"
cp -R "$EXACT/apps/pandora-mobile/platform" "$BUILD/platform"
cp "$EXACT/apps/pandora-mobile/pubspec.yaml" "$BUILD/pubspec.yaml"
cp "$EXACT/apps/pandora-mobile/pubspec.lock" "$BUILD/pubspec.lock"
cp "$EXACT/apps/pandora-mobile/analysis_options.yaml" "$BUILD/analysis_options.yaml"

python3 "$EXACT/apps/pandora-mobile/tool/configure_validation_android.py" \
  "$BUILD/android/app/src/main/AndroidManifest.xml"
python3 "$EXACT/apps/pandora-mobile/tool/configure_local_ai_android.py" \
  "$BUILD/android/app/build.gradle.kts" \
  "$BUILD/android/gradle.properties"

step "resolve-lockfile"
cd "$BUILD"
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

step "test-local-router"
flutter test test/core/local_ai/pandora_local_ai_router_test.dart --reporter expanded

step "build-arm64-apk"
mkdir -p "$HOME/.gradle"
cat > "$HOME/.gradle/gradle.properties" <<'EOF'
org.gradle.daemon=false
org.gradle.workers.max=2
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m -Dfile.encoding=UTF-8
EOF
export CMAKE_BUILD_PARALLEL_LEVEL=2
flutter build apk --debug \
  --target-platform android-arm64 \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION=0.4.0-rc.4+11
APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
test -f "$APK"

step "verify-apk"
AAPT="$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt"
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner"
ZIPALIGN="$ANDROID_SDK_ROOT/build-tools/36.0.0/zipalign"
"$AAPT" dump badging "$APK" | tee /tmp/badging.txt
grep -Fq "package: name='com.banataosystems.pandora_mobile'" /tmp/badging.txt
grep -Fq "versionCode='11'" /tmp/badging.txt
grep -Fq "versionName='0.4.0-rc.4'" /tmp/badging.txt
grep -Fq "native-code: 'arm64-v8a'" /tmp/badging.txt
"$APKSIGNER" verify --verbose --print-certs "$APK" | tee /tmp/signing.txt
"$ZIPALIGN" -c -v 4 "$APK" >/tmp/zipalign.txt
grep -Fq "Verification successful" /tmp/zipalign.txt
unzip -l "$APK" >/tmp/apk-files.txt
grep -Fq 'lib/arm64-v8a/libai-chat.so' /tmp/apk-files.txt
grep -Fq 'lib/arm64-v8a/libllama.so' /tmp/apk-files.txt
grep -Fq 'lib/arm64-v8a/libggml.so' /tmp/apk-files.txt
APK_SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
APK_SIZE="$(stat -c '%s' "$APK")"
checkpoint "running" "verify-apk-complete" "sha256=$APK_SHA size=$APK_SIZE"

step "publish-local-port"
mkdir -p "$OUTPUT"
cp -f "$APK" "$OUTPUT/Pandora-Local-AI-picker-a5d5b605.apk"
cp -f /tmp/badging.txt "$OUTPUT/badging.txt"
cp -f /tmp/signing.txt "$OUTPUT/signing.txt"
cp -f /tmp/zipalign.txt "$OUTPUT/zipalign.txt"
cat > "$OUTPUT/manifest.txt" <<EOF
source_sha=$SOURCE_SHA
llama_cpp_sha=$LLAMA_CPP_SHA
flutter_sha=$FLUTTER_SHA
apk_sha256=$APK_SHA
apk_size_bytes=$APK_SIZE
android_package=com.banataosystems.pandora_mobile
version_code=11
version_name=0.4.0-rc.4
abi=arm64-v8a
picker_fix=direct_ACTION_OPEN_DOCUMENT_launch
github_hosted_execution=github_codespaces
EOF

nohup python3 -m http.server 9114 --bind 0.0.0.0 --directory "$OUTPUT" >/tmp/pandora-apk-http.log 2>&1 &
sleep 2
curl -fsS http://127.0.0.1:9114/manifest.txt >/tmp/pandora-apk-manifest-readback.txt

STEP="complete"
checkpoint "success" "complete" "sha256=$APK_SHA size=$APK_SIZE"
echo "PANDORA_APK_READY source=$SOURCE_SHA sha256=$APK_SHA size=$APK_SIZE"
