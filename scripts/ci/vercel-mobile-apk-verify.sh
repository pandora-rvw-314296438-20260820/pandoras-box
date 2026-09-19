#!/usr/bin/env bash
set -euo pipefail

CANONICAL_SOURCE_SHA=100430e90bb5740ca14cfce8ef035be0baf17d07
EXPECTED_APPS_TREE=1007c05400b0a4552dc2c7382f1d5556eb29a096
FLUTTER_VERSION=3.47.0
EXPECTED_APP_VERSION=0.4.0-rc.4+11

test "$(git rev-parse HEAD:apps)" = "$EXPECTED_APPS_TREE"
mkdir -p .vercel-tools vercel-apk-output
export HOME="$PWD/.vercel-home"
mkdir -p "$HOME"

curl -fsSL "https://api.adoptium.net/v3/binary/version/jdk-17.0.20%2B8/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk17.tar.gz
mkdir -p .vercel-tools/jdk17
tar -xzf /tmp/jdk17.tar.gz --strip-components=1 -C .vercel-tools/jdk17
export JAVA_HOME="$PWD/.vercel-tools/jdk17"
export PATH="$JAVA_HOME/bin:$PATH"
java -version

curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.0-stable.tar.xz" -o /tmp/flutter.tar.xz
tar -xJf /tmp/flutter.tar.xz -C .vercel-tools
export PATH="$PWD/.vercel-tools/flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/.vercel-tools/flutter"
flutter config --no-analytics
flutter --version

mkdir -p .vercel-tools/android-sdk/cmdline-tools
curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" -o /tmp/android-tools.zip
python3 - <<'PY'
import zipfile
zipfile.ZipFile('/tmp/android-tools.zip').extractall('/tmp/android-tools')
PY
mv /tmp/android-tools/cmdline-tools .vercel-tools/android-sdk/cmdline-tools/latest
chmod -R u+rx .vercel-tools/android-sdk/cmdline-tools/latest/bin
export ANDROID_SDK_ROOT="$PWD/.vercel-tools/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'

rm -rf .pandora-mobile-build
mkdir .pandora-mobile-build
cd .pandora-mobile-build
flutter create --platforms=android,web --org com.banataosystems --project-name pandora_mobile .
cp -R ../apps/pandora-mobile/platform/android/. ./android/
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R ../apps/pandora-mobile/lib ./lib
cp -R ../apps/pandora-mobile/test ./test
cp -R ../apps/pandora-mobile/assets ./assets
cp -R ../apps/pandora-mobile/platform ./platform
cp ../apps/pandora-mobile/pubspec.yaml ./pubspec.yaml
cp ../apps/pandora-mobile/pubspec.lock ./pubspec.lock
cp ../apps/pandora-mobile/analysis_options.yaml ./analysis_options.yaml
python3 ../apps/pandora-mobile/tool/configure_validation_android.py android/app/src/main/AndroidManifest.xml

cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

flutter analyze 2>&1 | tee ../vercel-apk-output/flutter-analyze.log
flutter test --reporter expanded 2>&1 | tee ../vercel-apk-output/flutter-test.log

test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"
flutter build apk --debug \
  --dart-define=PANDORA_SOURCE_REVISION="$CANONICAL_SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION" \
  2>&1 | tee ../vercel-apk-output/flutter-build.log

cd ..
cp .pandora-mobile-build/build/app/outputs/flutter-apk/app-debug.apk vercel-apk-output/pandora-debug.apk
APK_SHA="$(sha256sum vercel-apk-output/pandora-debug.apk | awk '{print $1}')"
APK_SIZE="$(stat -c '%s' vercel-apk-output/pandora-debug.apk)"
{
  echo "canonical_source_sha=$CANONICAL_SOURCE_SHA"
  echo "source_apps_tree=$EXPECTED_APPS_TREE"
  echo "harness_commit_sha=$VERCEL_GIT_COMMIT_SHA"
  echo "flutter_version=$FLUTTER_VERSION"
  echo "java_version=17.0.20+8"
  echo "android_platform=android-36"
  echo "android_build_tools=36.0.0"
  echo "app_version=$EXPECTED_APP_VERSION"
  echo "android_package=com.banataosystems.pandora_mobile"
  echo "artifact_class=validation-candidate"
  echo "production_release=false"
  echo "physical_device_verified=false"
  echo "apk_sha256=$APK_SHA"
  echo "apk_size_bytes=$APK_SIZE"
} > vercel-apk-output/pandora-mobile-artifact-manifest.txt

printf '<!doctype html><meta charset="utf-8"><title>Pandora Android validation</title><h1>Pandora Android validation</h1><p>Canonical source: %s</p><p>Apps tree: %s</p><p>APK SHA-256: %s</p><ul><li><a href="/pandora-debug.apk">APK</a></li><li><a href="/pandora-mobile-artifact-manifest.txt">Manifest</a></li><li><a href="/flutter-analyze.log">Analyze log</a></li><li><a href="/flutter-test.log">Test log</a></li><li><a href="/flutter-build.log">Build log</a></li></ul>' "$CANONICAL_SOURCE_SHA" "$EXPECTED_APPS_TREE" "$APK_SHA" > vercel-apk-output/index.html
