#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ARTIFACT_DIR="$ROOT/.pandora-codespace-artifact"
BUILD_DIR="$ROOT/.pandora-mobile-codespace-build"
LOG="$ARTIFACT_DIR/build.log"
FLUTTER_VERSION="3.47.0"
EXPECTED_APP_VERSION="0.4.0-rc.4+11"
LLAMA_CPP_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
ANDROID_PLATFORM="android-36"
ANDROID_BUILD_TOOLS="36.0.0"
ANDROID_NDK="29.0.13113456"
ANDROID_CMAKE="3.31.6"
CMDLINE_TOOLS_REV="11076708"
BUILD_DONE=0

mkdir -p "$ARTIFACT_DIR"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

SOURCE_SHA="$(git rev-parse HEAD)"
SOURCE_TREE="$(git rev-parse HEAD^{tree})"

write_status() {
  local phase="$1"
  local outcome="$2"
  local detail="$3"
  python3 - "$ARTIFACT_DIR/status.json" "$phase" "$outcome" "$detail" "$SOURCE_SHA" "$SOURCE_TREE" <<'PY'
import json, sys, datetime
path, phase, outcome, detail, sha, tree = sys.argv[1:]
payload = {
    "phase": phase,
    "outcome": outcome,
    "detail": detail,
    "source_sha": sha,
    "source_tree_sha": tree,
    "physical_device_verified": False,
    "local_inference_verified": False,
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY
}

publish_evidence() {
  local evidence_branch="build/phone-local-ai-evidence-${SOURCE_SHA:0:12}-20260920"
  local release_tag="phone-local-ai-${SOURCE_SHA:0:12}-20260920"
  local release_title="Pandora phone-local APK ${SOURCE_SHA:0:12}"
  local apk="$ARTIFACT_DIR/pandora-phone-local-${SOURCE_SHA}.apk"

  set +e
  git -C "$ROOT" config user.name "Pandora Build Evidence"
  git -C "$ROOT" config user.email "pandora-build-evidence@users.noreply.github.com"
  git -C "$ROOT" checkout -B "$evidence_branch" "$SOURCE_SHA"

  find "$ARTIFACT_DIR" -maxdepth 1 -type f ! -name '*.apk' -print0 |
    xargs -0 -r git -C "$ROOT" add -f
  if ! git -C "$ROOT" diff --cached --quiet; then
    git -C "$ROOT" commit -m "build(android): exact-source phone-local evidence ${SOURCE_SHA:0:12}"
    git -C "$ROOT" push --force origin "HEAD:refs/heads/$evidence_branch"
  fi

  if [[ -s "$apk" ]] && command -v gh >/dev/null 2>&1; then
    gh release delete "$release_tag" --repo pandora-rvw-314296438-20260820/pandoras-box --yes >/dev/null 2>&1 || true
    git -C "$ROOT" tag -d "$release_tag" >/dev/null 2>&1 || true
    git -C "$ROOT" push origin ":refs/tags/$release_tag" >/dev/null 2>&1 || true
    gh release create "$release_tag" "$apk"       --repo pandora-rvw-314296438-20260820/pandoras-box       --target "$SOURCE_SHA"       --title "$release_title"       --notes-file "$ARTIFACT_DIR/manifest.txt"       --draft
  fi
  set -e
}

finish() {
  rc=$?
  if [[ "$BUILD_DONE" != "1" ]]; then
    write_status "build" "failed" "Exact-source Codespaces Android compilation failed; see build.log."
  fi
  if ! pgrep -f "python3 -m http.server 9114" >/dev/null 2>&1; then
    nohup python3 -m http.server 9114 --directory "$ARTIFACT_DIR" >"$ARTIFACT_DIR/http.log" 2>&1 &
  fi
  publish_evidence
  exit 0
}
trap finish EXIT

write_status "bootstrap" "running" "Preparing pinned Android/Flutter toolchain."

echo "SOURCE_SHA=$SOURCE_SHA"
echo "SOURCE_TREE=$SOURCE_TREE"
echo "Codespace compilation only. No local model inference is executed here."

sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn.list.save
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl git unzip xz-utils zip libglu1-mesa \
  openjdk-17-jdk-headless python3 ninja-build

export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
export PATH="$JAVA_HOME/bin:$PATH"

FLUTTER_HOME="$HOME/flutter-$FLUTTER_VERSION"
if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
  rm -rf "$FLUTTER_HOME"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"
flutter config --no-analytics
flutter --version

export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
  tmpdir="$(mktemp -d)"
  curl -fsSL \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_REV}_latest.zip" \
    -o "$tmpdir/cmdline-tools.zip"
  unzip -q "$tmpdir/cmdline-tools.zip" -d "$tmpdir/unpacked"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$tmpdir/unpacked/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -rf "$tmpdir"
fi
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager \
  "platform-tools" \
  "platforms;${ANDROID_PLATFORM}" \
  "build-tools;${ANDROID_BUILD_TOOLS}" \
  "ndk;${ANDROID_NDK}" \
  "cmake;${ANDROID_CMAKE}"

write_status "materialize" "running" "Materializing exact Pandora Android source and pinned llama.cpp."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
flutter create \
  --platforms=android \
  --org com.banataosystems \
  --project-name pandora_mobile \
  .

cp -R "$ROOT/apps/pandora-mobile/platform/android/." ./android/

rm -rf android/llama.cpp
git init -q android/llama.cpp
git -C android/llama.cpp remote add origin https://github.com/ggml-org/llama.cpp.git
git -C android/llama.cpp fetch --depth 1 origin "$LLAMA_CPP_SHA"
git -C android/llama.cpp checkout -q --detach FETCH_HEAD
test "$(git -C android/llama.cpp rev-parse HEAD)" = "$LLAMA_CPP_SHA"

mkdir -p android/app/src/main/kotlin/com/arm/aichat/internal
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/AiChat.kt \
  android/app/src/main/kotlin/com/arm/aichat/AiChat.kt
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt \
  android/app/src/main/kotlin/com/arm/aichat/InferenceEngine.kt
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt \
  android/app/src/main/kotlin/com/arm/aichat/internal/InferenceEngineImpl.kt

rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml

python3 "$ROOT/apps/pandora-mobile/tool/configure_validation_android.py" \
  android/app/src/main/AndroidManifest.xml
python3 "$ROOT/apps/pandora-mobile/tool/configure_local_ai_android.py" \
  android/app/build.gradle.kts \
  android/gradle.properties

test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

write_status "verify" "running" "Running analyzer and focused local-routing tests before APK compilation."

set +e
flutter analyze >"$ARTIFACT_DIR/flutter-analyze.log" 2>&1
ANALYZE_RC=$?
flutter test test/core/local_ai/pandora_local_ai_router_test.dart --reporter expanded \
  >"$ARTIFACT_DIR/local-ai-router-test.log" 2>&1
ROUTER_TEST_RC=$?
set -e

printf '%s\n' "$ANALYZE_RC" >"$ARTIFACT_DIR/flutter-analyze.exit"
printf '%s\n' "$ROUTER_TEST_RC" >"$ARTIFACT_DIR/local-ai-router-test.exit"

if [[ "$ANALYZE_RC" -ne 0 || "$ROUTER_TEST_RC" -ne 0 ]]; then
  echo "Pre-build verification failed: analyze=$ANALYZE_RC router_test=$ROUTER_TEST_RC" >&2
  exit 1
fi

write_status "compile" "running" "Building arm64 debug APK from exact source."

flutter build apk --debug \
  --target-platform android-arm64 \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION"

APK="$BUILD_DIR/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$APK"
cp "$APK" "$ARTIFACT_DIR/pandora-phone-local-${SOURCE_SHA}.apk"

AAPT="$ANDROID_SDK_ROOT/build-tools/$ANDROID_BUILD_TOOLS/aapt"
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/$ANDROID_BUILD_TOOLS/apksigner"
"$AAPT" dump badging "$APK" >"$ARTIFACT_DIR/badging.txt"
"$AAPT" dump permissions "$APK" >"$ARTIFACT_DIR/permissions.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK" >"$ARTIFACT_DIR/signing.txt"

grep -Fq "package: name='com.banataosystems.pandora_mobile'" "$ARTIFACT_DIR/badging.txt"
grep -Fq "versionCode='11'" "$ARTIFACT_DIR/badging.txt"
grep -Fq "versionName='0.4.0-rc.4'" "$ARTIFACT_DIR/badging.txt"

if grep -Eiq \
  'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW' \
  "$ARTIFACT_DIR/permissions.txt"; then
  echo "Unexpected sensitive Android permission detected." >&2
  exit 1
fi

APK_SHA256="$(sha256sum "$APK" | awk '{print $1}')"
APK_SIZE_BYTES="$(stat -c '%s' "$APK")"
BADGING_SHA256="$(sha256sum "$ARTIFACT_DIR/badging.txt" | awk '{print $1}')"
PERMISSIONS_SHA256="$(sha256sum "$ARTIFACT_DIR/permissions.txt" | awk '{print $1}')"
SIGNING_SHA256="$(sha256sum "$ARTIFACT_DIR/signing.txt" | awk '{print $1}')"

cat >"$ARTIFACT_DIR/manifest.txt" <<EOF
source_sha=$SOURCE_SHA
source_tree_sha=$SOURCE_TREE
app_version=$EXPECTED_APP_VERSION
android_package=com.banataosystems.pandora_mobile
flutter_version=$FLUTTER_VERSION
llama_cpp_sha=$LLAMA_CPP_SHA
android_platform=$ANDROID_PLATFORM
android_build_tools=$ANDROID_BUILD_TOOLS
android_ndk=$ANDROID_NDK
android_cmake=$ANDROID_CMAKE
target_platform=android-arm64
native_backend_configured=cpu
local_ai_model_bundled=false
physical_device_verified=false
local_inference_verified=false
gpu_acceleration_verified=false
npu_acceleration_verified=false
apk_sha256=$APK_SHA256
apk_size_bytes=$APK_SIZE_BYTES
android_badging_sha256=$BADGING_SHA256
android_permissions_sha256=$PERMISSIONS_SHA256
android_signing_sha256=$SIGNING_SHA256
flutter_analyze_exit=$ANALYZE_RC
local_ai_router_test_exit=$ROUTER_TEST_RC
EOF

python3 - "$ARTIFACT_DIR/status.json" "$SOURCE_SHA" "$SOURCE_TREE" "$APK_SHA256" "$APK_SIZE_BYTES" "$ANALYZE_RC" "$ROUTER_TEST_RC" <<'PY'
import json, sys, datetime
path, sha, tree, apk_hash, apk_size, analyze_rc, router_rc = sys.argv[1:]
payload = {
    "phase": "build",
    "outcome": "passed",
    "detail": "Exact-source arm64 Android debug APK compiled. Physical-device inference is not yet verified.",
    "source_sha": sha,
    "source_tree_sha": tree,
    "apk_sha256": apk_hash,
    "apk_size_bytes": int(apk_size),
    "flutter_analyze_exit": int(analyze_rc),
    "local_ai_router_test_exit": int(router_rc),
    "native_backend_configured": "cpu",
    "physical_device_verified": False,
    "local_inference_verified": False,
    "gpu_acceleration_verified": False,
    "npu_acceleration_verified": False,
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY

BUILD_DONE=1
echo "Exact-source APK compiled: $APK_SHA256 ($APK_SIZE_BYTES bytes)"
