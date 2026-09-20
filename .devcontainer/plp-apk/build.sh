#!/usr/bin/env bash
set -euo pipefail

if [ -n "${PANDORA_SOURCE_ROOT:-}" ]; then
  ROOT="$PANDORA_SOURCE_ROOT"
else
  ROOT="$(git rev-parse --show-toplevel)"
fi
cd "$ROOT"

mkdir -p dist
LOG="$ROOT/dist/plp-apk-build.log"
exec > >(tee "$LOG") 2>&1

echo "PANDORA_PLP_APK_BUILD stage=starting"
SOURCE_SHA="${PANDORA_SOURCE_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"
SOURCE_TREE="${PANDORA_SOURCE_TREE:-$(git rev-parse HEAD^{tree} 2>/dev/null || echo archive)}"
test -n "$SOURCE_SHA"
APP_VERSION="$(awk '/^version:/{print $2; exit}' apps/pandora-mobile/pubspec.yaml)"
FLUTTER_VERSION="3.47.0"
BUILD_ROOT="$ROOT/.plp-apk-build"
TOOLS_ROOT="$HOME/.pandora-plp-apk-tools"
FLUTTER_ROOT="$TOOLS_ROOT/flutter"
ANDROID_ROOT="$TOOLS_ROOT/android-sdk"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$TOOLS_ROOT" "$ROOT/dist"

echo "PANDORA_PLP_APK_BUILD stage=toolchain source_sha=$SOURCE_SHA"

if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl unzip xz-utils
fi

if command -v javac >/dev/null 2>&1; then
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
else
  JAVA_HOME="$TOOLS_ROOT/jdk17"
  if [ ! -x "$JAVA_HOME/bin/javac" ]; then
    rm -rf "$JAVA_HOME"
    mkdir -p "$JAVA_HOME"
    curl -fL --retry 3 --retry-delay 2 "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" -o "$TOOLS_ROOT/jdk17.tar.gz"
    tar -xzf "$TOOLS_ROOT/jdk17.tar.gz" -C "$JAVA_HOME" --strip-components=1
    rm -f "$TOOLS_ROOT/jdk17.tar.gz"
  fi
  export JAVA_HOME
fi
export PATH="$JAVA_HOME/bin:$PATH"
java -version

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  rm -rf "$FLUTTER_ROOT" "$TOOLS_ROOT/flutter-download"
  curl -fL --retry 3 --retry-delay 2     "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$FLUTTER_VERSION-stable.tar.xz"     -o "$TOOLS_ROOT/flutter.tar.xz"
  tar -xJf "$TOOLS_ROOT/flutter.tar.xz" -C "$TOOLS_ROOT"
  rm -f "$TOOLS_ROOT/flutter.tar.xz"
fi
export PATH="$FLUTTER_ROOT/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_ROOT"
flutter --disable-analytics >/dev/null 2>&1 || true
flutter --version

SDKMANAGER="$ANDROID_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  rm -rf "$ANDROID_ROOT"
  mkdir -p "$ANDROID_ROOT/cmdline-tools"
  curl -fL --retry 3 --retry-delay 2     "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"     -o "$TOOLS_ROOT/android-cmdline.zip"
  unzip -q "$TOOLS_ROOT/android-cmdline.zip" -d "$ANDROID_ROOT/cmdline-tools"
  mv "$ANDROID_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_ROOT/cmdline-tools/latest"
  rm -f "$TOOLS_ROOT/android-cmdline.zip"
fi
export ANDROID_SDK_ROOT="$ANDROID_ROOT"
export ANDROID_HOME="$ANDROID_ROOT"
export PATH="$ANDROID_ROOT/cmdline-tools/latest/bin:$ANDROID_ROOT/platform-tools:$PATH"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" "platforms;android-36" "build-tools;36.0.0" "platform-tools"

echo "PANDORA_PLP_APK_BUILD stage=materialize"
cd "$BUILD_ROOT"
flutter create   --platforms=android   --org com.banataosystems   --project-name pandora_mobile   .

cp -R "$ROOT/apps/pandora-mobile/platform/android/." ./android/
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp -R "$ROOT/apps/pandora-mobile/platform" ./platform
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml
python3 "$ROOT/apps/pandora-mobile/tool/configure_validation_android.py"   android/app/src/main/AndroidManifest.xml

cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
test "$(sha256sum pubspec.lock.expected | cut -d ' ' -f1)" = "$(sha256sum pubspec.lock | cut -d ' ' -f1)"

echo "PANDORA_PLP_APK_BUILD stage=analyze"
flutter analyze

echo "PANDORA_PLP_APK_BUILD stage=test_variant"
flutter test --reporter expanded test/features/enterprise/plp_enterprise_variant_test.dart

echo "PANDORA_PLP_APK_BUILD stage=test_mobile"
flutter test --reporter compact

echo "PANDORA_PLP_APK_BUILD stage=build"
flutter build apk --debug   --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA"   --dart-define=PANDORA_APP_VERSION="$APP_VERSION"   --dart-define=PANDORA_ENTERPRISE_WORKSPACE=plp-boracay

APK="$BUILD_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
test -f "$APK"
AAPT="$ANDROID_ROOT/build-tools/36.0.0/aapt"
APKSIGNER="$ANDROID_ROOT/build-tools/36.0.0/apksigner"
test -x "$AAPT"
test -x "$APKSIGNER"

"$AAPT" dump badging "$APK" > "$ROOT/dist/android-badging.txt"
"$AAPT" dump permissions "$APK" > "$ROOT/dist/android-permissions.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK" > "$ROOT/dist/android-signing.txt"

grep -Fq "package: name='com.banataosystems.pandora_mobile'" "$ROOT/dist/android-badging.txt"
grep -Fq "versionCode='11'" "$ROOT/dist/android-badging.txt"
grep -Fq "versionName='0.4.0-rc.4'" "$ROOT/dist/android-badging.txt"
if grep -Eiq 'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW' "$ROOT/dist/android-permissions.txt"; then
  echo "Unexpected sensitive Android permission detected." >&2
  exit 1
fi

OUT="$ROOT/dist/PLP-Pandora-Enterprise.apk"
cp "$APK" "$OUT"
APK_SHA="$(sha256sum "$OUT" | cut -d ' ' -f1)"
APK_SIZE="$(stat -c '%s' "$OUT")"

cat > "$ROOT/dist/PLP-Pandora-Enterprise-manifest.txt" <<EOF
source_sha=$SOURCE_SHA
source_tree=$SOURCE_TREE
enterprise_workspace=plp-boracay
app_version=$APP_VERSION
android_package=com.banataosystems.pandora_mobile
flutter_version=$FLUTTER_VERSION
artifact_class=plp-enterprise-validation-candidate
production_release=false
physical_device_verified=false
apk_sha256=$APK_SHA
apk_size_bytes=$APK_SIZE
analyze=pass
plp_variant_test=pass
mobile_test_suite=pass
android_badging=pass
android_permissions=pass
android_signature=pass
EOF

rm -rf "$BUILD_ROOT"
touch "$ROOT/dist/BUILD_SUCCESS"

echo "PANDORA_PLP_APK_BUILD stage=done source_sha=$SOURCE_SHA apk_sha256=$APK_SHA apk_size_bytes=$APK_SIZE"
