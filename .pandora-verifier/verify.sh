#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SOURCE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_TREE="$(git -C "$ROOT" rev-parse HEAD^{tree})"
OUT="$PWD/proof"
TOOLS="$PWD/.vercel-tools"
HOME_DIR="$PWD/.vercel-home"
BUILD="$PWD/.plp-android-build"

FLUTTER_VERSION="3.47.0"
EXPECTED_APP_VERSION="0.4.0-rc.14+21"
EXPECTED_PACKAGE="com.banataosystems.pandora.plp"
EXPECTED_LABEL="PLP Pandora Enterprise"
LLAMA_CPP_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
LOCAL_MODEL_NAME="Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
LOCAL_MODEL_SHA256="1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6"
EXPECTED_PRODUCTION_SIGNER_SHA256="ba4c1df95b0f0858bb510dab90b412dd18724205f5ff3dfbb7c7c56c9931202e"
APK_FILENAME="PLP-Pandora-Enterprise.apk"
ANDROID_CMDLINE_REV="11076708"

if [[ -n "${VERCEL_GIT_COMMIT_SHA:-}" ]]; then
  test "$SOURCE_SHA" = "$VERCEL_GIT_COMMIT_SHA"
fi

rm -rf "$OUT" "$TOOLS" "$BUILD" "$HOME_DIR"
mkdir -p "$OUT" "$TOOLS" "$HOME_DIR"
export HOME="$HOME_DIR"

python3 "$ROOT/apps/pandora-mobile/tool/test_configure_plp_android.py"
python3 "$ROOT/apps/pandora-mobile/tool/test_plp_enterprise_isolation.py"

curl -fsSL   "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"   -o /tmp/pandora-flutter.tar.xz
tar -xJf /tmp/pandora-flutter.tar.xz -C "$TOOLS"
export PATH="$TOOLS/flutter/bin:$PATH"
git config --global --add safe.directory "$TOOLS/flutter"
flutter config --no-analytics >/dev/null
flutter --version | tee "$OUT/flutter-version.log"

curl -fsSL   "https://api.adoptium.net/v3/binary/version/jdk-17.0.20%2B8/linux/x64/jdk/hotspot/normal/eclipse"   -o /tmp/pandora-jdk17.tar.gz
mkdir -p "$TOOLS/jdk"
tar -xzf /tmp/pandora-jdk17.tar.gz -C "$TOOLS/jdk"
JAVA_HOME="$(find "$TOOLS/jdk" -mindepth 1 -maxdepth 1 -type d -name 'jdk-*' | head -n 1)"
test -n "$JAVA_HOME"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | tee "$OUT/java-version.log"
java -version 2>&1 | grep -Eq 'version "17\.'

export ANDROID_SDK_ROOT="$TOOLS/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
curl -fsSL   "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_REV}_latest.zip"   -o /tmp/pandora-android-cli.zip
rm -rf /tmp/pandora-android-cli
mkdir -p /tmp/pandora-android-cli
unzip -q /tmp/pandora-android-cli.zip -d /tmp/pandora-android-cli
mv /tmp/pandora-android-cli/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

set +o pipefail
yes | sdkmanager --licenses >/dev/null
set -o pipefail
sdkmanager   "platform-tools"   "platforms;android-36"   "build-tools;36.0.0"   "ndk;29.0.13113456"   "cmake;3.31.6"

mkdir -p "$BUILD"
cd "$BUILD"
flutter create   --platforms=android   --org com.banataosystems   --project-name pandora_mobile   .

cp -R "$ROOT/apps/pandora-mobile/platform/android/." ./android/

git init -q android/llama.cpp
git -C android/llama.cpp remote add origin https://github.com/ggml-org/llama.cpp.git
git -C android/llama.cpp fetch --depth 1 origin "$LLAMA_CPP_SHA"
git -C android/llama.cpp checkout -q --detach FETCH_HEAD
test "$(git -C android/llama.cpp rev-parse HEAD)" = "$LLAMA_CPP_SHA"

mkdir -p android/app/src/main/kotlin/com/arm/aichat/internal
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/AiChat.kt   android/app/src/main/kotlin/com/arm/aichat/AiChat.kt
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt   android/app/src/main/kotlin/com/arm/aichat/InferenceEngine.kt
cp android/llama.cpp/examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt   android/app/src/main/kotlin/com/arm/aichat/internal/InferenceEngineImpl.kt
python3 "$ROOT/apps/pandora-mobile/tool/patch_inference_engine_android.py"   android/app/src/main/kotlin/com/arm/aichat/internal/InferenceEngineImpl.kt   android/app/src/main/kotlin/com/arm/aichat/InferenceEngine.kt

rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp -R "$ROOT/apps/pandora-mobile/platform" ./platform
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml

python3 "$ROOT/apps/pandora-mobile/tool/configure_validation_android.py"   android/app/src/main/AndroidManifest.xml
python3 "$ROOT/apps/pandora-mobile/tool/configure_local_ai_android.py"   android/app/build.gradle.kts   android/gradle.properties
python3 "$ROOT/apps/pandora-mobile/tool/configure_plp_android.py"   android/app/build.gradle.kts   android/app/src/main/AndroidManifest.xml   android/app/src/main/kotlin

grep -Fq "applicationId = \"$EXPECTED_PACKAGE\"" android/app/build.gradle.kts
grep -Fq "namespace = \"$EXPECTED_PACKAGE\"" android/app/build.gradle.kts
grep -Fq "android:label=\"$EXPECTED_LABEL\"" android/app/src/main/AndroidManifest.xml
! grep -R -F 'com.banataosystems.pandora_mobile'   android/app/build.gradle.kts   android/app/src/main/AndroidManifest.xml   android/app/src/main/kotlin

cp pubspec.lock /tmp/plp-pubspec.lock.expected
flutter pub get --enforce-lockfile | tee "$OUT/pub-get.log"
python3 - <<'PY'
from pathlib import Path
expected = Path('/tmp/plp-pubspec.lock.expected').read_bytes()
actual = Path('pubspec.lock').read_bytes()
if expected != actual:
    raise SystemExit('pubspec.lock changed after flutter pub get --enforce-lockfile')
PY

set +e
flutter analyze > "$OUT/flutter-analyze.log" 2>&1
ANALYZE_EXIT=$?
set -e
cat "$OUT/flutter-analyze.log"
if grep -Eq '^[[:space:]]*error[[:space:]]+•' "$OUT/flutter-analyze.log"; then
  exit 31
fi
if [[ "$ANALYZE_EXIT" -ne 0 ]] && ! grep -Fq 'issues found.' "$OUT/flutter-analyze.log"; then
  exit "$ANALYZE_EXIT"
fi

flutter test --reporter expanded   test/core/local_ai/plp_local_router_test.dart   test/core/local_ai/plp_chat_fallback_test.dart   test/features/enterprise/plp_staff_task_action_test.dart   test/features/enterprise/plp_enterprise_home_test.dart   test/features/enterprise/enterprise_vision_demo_contract_test.dart   test/features/operations/operations_room_test.dart   | tee "$OUT/flutter-test.log"

test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"

BUILD_ARTIFACT_CLASS="Owner Test — Android debug signed"
if [[ "${PANDORA_PLP_PRODUCTION_SIGNING:-false}" == "true" ]]; then
  BUILD_ARTIFACT_CLASS="PLP production-signed candidate"
fi

flutter build apk --release   --target=lib/main_plp.dart   --target-platform=android-arm64   --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA"   --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION"   --dart-define=PANDORA_ARTIFACT_CLASS="$BUILD_ARTIFACT_CLASS"   | tee "$OUT/flutter-build.log"

RAW_APK="$BUILD/build/app/outputs/flutter-apk/app-release.apk"
test -f "$RAW_APK"
AAPT="$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt"
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner"
ZIPALIGN="$ANDROID_SDK_ROOT/build-tools/36.0.0/zipalign"
APK="$RAW_APK"
ARTIFACT_CLASS="validation-candidate"
PRODUCTION_SIGNER_VERIFIED="false"

if [[ "${PANDORA_PLP_PRODUCTION_SIGNING:-false}" == "true" ]]; then
  : "${PANDORA_PLP_RELEASE_KEYSTORE_B64:?missing production keystore}"
  : "${PANDORA_PLP_RELEASE_KEYSTORE_PASSWORD:?missing production keystore password}"
  : "${PANDORA_PLP_RELEASE_CERT_SHA256:?missing production signer digest}"
  test "${PANDORA_PLP_RELEASE_CERT_SHA256,,}" = "$EXPECTED_PRODUCTION_SIGNER_SHA256"
  command -v zip >/dev/null
  umask 077
  KEYSTORE="$TOOLS/plp-release.p12"
  UNSIGNED_APK="$BUILD/build/app/outputs/flutter-apk/app-release-unsigned.apk"
  ALIGNED_APK="$BUILD/build/app/outputs/flutter-apk/app-release-aligned.apk"
  SIGNED_APK="$BUILD/build/app/outputs/flutter-apk/app-release-production.apk"
  printf '%s' "$PANDORA_PLP_RELEASE_KEYSTORE_B64" | base64 --decode > "$KEYSTORE"
  test -s "$KEYSTORE"
  cp "$RAW_APK" "$UNSIGNED_APK"
  zip -q -d "$UNSIGNED_APK" 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' >/dev/null 2>&1 || true
  "$ZIPALIGN" -p -f 4 "$UNSIGNED_APK" "$ALIGNED_APK"
  "$APKSIGNER" sign --out "$SIGNED_APK" --ks "$KEYSTORE" --ks-type PKCS12 --ks-pass env:PANDORA_PLP_RELEASE_KEYSTORE_PASSWORD --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true "$ALIGNED_APK"
  rm -f "$KEYSTORE"
  APK="$SIGNED_APK"
  ARTIFACT_CLASS="production-candidate"
  PRODUCTION_SIGNER_VERIFIED="true"
fi

"$AAPT" dump badging "$APK" > "$OUT/badging.txt"
"$AAPT" dump permissions "$APK" > "$OUT/permissions.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK" > "$OUT/signing.txt"
SIGNER_SHA="$(grep -m1 'Signer #1 certificate SHA-256 digest:' "$OUT/signing.txt" | sed -E 's/.*digest:[[:space:]]*//; s/://g' | tr '[:upper:]' '[:lower:]')"
test -n "$SIGNER_SHA"
if [[ "$PRODUCTION_SIGNER_VERIFIED" == "true" ]]; then
  test "$SIGNER_SHA" = "$EXPECTED_PRODUCTION_SIGNER_SHA256"
  test "$(grep -Ec '^Signer #[0-9]+ certificate SHA-256 digest:' "$OUT/signing.txt")" = "1"
  ! grep -Eiq 'Android Debug|CN=Android Debug' "$OUT/signing.txt"
  grep -Eq 'Verified using v2 scheme .*: true|Verified using v3 scheme .*: true' "$OUT/signing.txt"
fi
unzip -l "$APK" > "$OUT/apk-files.txt"

grep -Fq "package: name='$EXPECTED_PACKAGE'" "$OUT/badging.txt"
grep -Fq "application-label:'$EXPECTED_LABEL'" "$OUT/badging.txt"
grep -Fq "launchable-activity: name='$EXPECTED_PACKAGE.MainActivity'" "$OUT/badging.txt"
expected_version_name="${EXPECTED_APP_VERSION%%+*}"
expected_version_code="${EXPECTED_APP_VERSION##*+}"
grep -Fq "versionCode='$expected_version_code'" "$OUT/badging.txt"
grep -Fq "versionName='$expected_version_name'" "$OUT/badging.txt"
grep -Fq 'lib/arm64-v8a/' "$OUT/apk-files.txt"
! grep -Eq 'lib/(x86|x86_64|armeabi-v7a)/' "$OUT/apk-files.txt"
! grep -Eiq '\.gguf($|[[:space:]])' "$OUT/apk-files.txt"

if grep -Eiq   'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW'   "$OUT/permissions.txt"; then
  echo 'Unexpected sensitive Android permission detected.' >&2
  exit 32
fi

cp "$APK" "$OUT/$APK_FILENAME"
APK_SHA="$(sha256sum "$OUT/$APK_FILENAME" | cut -d ' ' -f1)"
APK_SIZE="$(stat -c '%s' "$OUT/$APK_FILENAME")"

cat > "$OUT/PLP-Pandora-Enterprise.manifest.txt" <<EOF
source_sha=$SOURCE_SHA
source_tree=$SOURCE_TREE
verification_lane=vercel-pandora-verifier
vercel_git_commit_sha=${VERCEL_GIT_COMMIT_SHA:-unknown}
flutter_version=$FLUTTER_VERSION
java_version=17.0.20+8
app_version=$EXPECTED_APP_VERSION
android_package=$EXPECTED_PACKAGE
application_label=$EXPECTED_LABEL
dart_entrypoint=lib/main_plp.dart
llama_cpp_sha=$LLAMA_CPP_SHA
accepted_local_model_name=$LOCAL_MODEL_NAME
accepted_local_model_sha256=$LOCAL_MODEL_SHA256
local_ai_model_bundled=false
android_platform=android-36
android_build_tools=36.0.0
android_ndk=29.0.13113456
cmake_version=3.31.6
target_abi=arm64-v8a
build_mode=release
artifact_class=$ARTIFACT_CLASS
production_release=false
production_signer_verified=$PRODUCTION_SIGNER_VERIFIED
signer_sha256=$SIGNER_SHA
apk_filename=$APK_FILENAME
apk_sha256=$APK_SHA
apk_size_bytes=$APK_SIZE
signing_evidence_sha256=$(sha256sum "$OUT/signing.txt" | cut -d ' ' -f1)
badging_evidence_sha256=$(sha256sum "$OUT/badging.txt" | cut -d ' ' -f1)
physical_device_verified=false
offline_qwen_acceptance_verified=false
EOF

test "$(sha256sum "$OUT/$APK_FILENAME" | cut -d ' ' -f1)" = "$APK_SHA"

cat > "$OUT/index.html" <<EOF
<!doctype html><meta charset="utf-8">
<title>PLP Pandora Enterprise Android Verification</title>
<h1>PLP Pandora Enterprise Android Verification</h1>
<p>Exact source: <code>$SOURCE_SHA</code></p>
<p>Package: <code>$EXPECTED_PACKAGE</code></p>
<p>APK SHA-256: <code>$APK_SHA</code></p>
<p>APK size: <code>$APK_SIZE</code> bytes</p>
<ul>
<li><a href="/$APK_FILENAME">$APK_FILENAME</a></li>
<li><a href="/PLP-Pandora-Enterprise.manifest.txt">Manifest</a></li>
<li><a href="/badging.txt">Android package evidence</a></li>
<li><a href="/signing.txt">Signing evidence</a></li>
<li><a href="/flutter-analyze.log">Analyze log</a></li>
<li><a href="/flutter-test.log">Test log</a></li>
<li><a href="/flutter-build.log">Build log</a></li>
</ul>
EOF

cat "$OUT/PLP-Pandora-Enterprise.manifest.txt"
