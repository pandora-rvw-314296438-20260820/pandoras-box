#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
BUILD_SOURCE_SHA="${VERCEL_GIT_COMMIT_SHA:-$(git rev-parse HEAD)}"
APP_SOURCE_SHA="1707e31b5c24fb72156e68260efc2de93157b6a7"
APP_VERSION="0.4.0-rc.4+11"
WORK="${TMPDIR:-/tmp}/pandora-apk-${BUILD_SOURCE_SHA:0:12}"
TOOLS="$WORK/tools"
BUILDAPP="$WORK/buildapp"
OUT="$ROOT/dist-apk"

rm -rf "$WORK" "$OUT"
mkdir -p "$TOOLS" "$OUT"

export CI=true
export PUB_CACHE="$WORK/pub-cache"
export GRADLE_USER_HOME="$WORK/gradle"
export ANDROID_SDK_ROOT="$TOOLS/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"

echo "Installing portable Temurin JDK 17"
curl --fail --location --retry 4 --retry-delay 2 "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk" -o "$TOOLS/jdk.tar.gz"
mkdir -p "$TOOLS/jdk"
tar -xzf "$TOOLS/jdk.tar.gz" -C "$TOOLS/jdk" --strip-components=1
export JAVA_HOME="$TOOLS/jdk"
export PATH="$JAVA_HOME/bin:$PATH"

echo "Resolving current Flutter stable archive"
curl --fail --location --retry 4 --retry-delay 2 "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" -o "$TOOLS/flutter-releases.json"
FLUTTER_ARCHIVE="$(node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const hash=x.current_release.stable;
const r=x.releases.find(v=>v.hash===hash && v.channel==="stable");
if(!r) process.exit(2);
process.stdout.write(r.archive);
' "$TOOLS/flutter-releases.json")"
curl --fail --location --retry 4 --retry-delay 2 "https://storage.googleapis.com/flutter_infra_release/releases/$FLUTTER_ARCHIVE" -o "$TOOLS/flutter.tar.xz"
tar -xJf "$TOOLS/flutter.tar.xz" -C "$TOOLS"
export PATH="$TOOLS/flutter/bin:$PATH"

flutter --version
dart --version
java -version

echo "Installing Android command-line tools"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
curl --fail --location --retry 4 --retry-delay 2 "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$TOOLS/android-cmdline.zip"
unzip -q "$TOOLS/android-cmdline.zip" -d "$ANDROID_SDK_ROOT/cmdline-tools"
mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"

mkdir -p "$BUILDAPP"
cd "$BUILDAPP"
flutter create --platforms=android --org com.banataosystems --project-name pandora_mobile .

cp -R "$ROOT/apps/pandora-mobile/platform/android/." android/
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" analysis_options.yaml

python3 "$ROOT/apps/pandora-mobile/tool/configure_validation_android.py" android/app/src/main/AndroidManifest.xml

cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded

flutter build apk --release --dart-define=PANDORA_SOURCE_REVISION="$APP_SOURCE_SHA" --dart-define=PANDORA_APP_VERSION="$APP_VERSION"

APK="$BUILDAPP/build/app/outputs/flutter-apk/app-release.apk"
test -s "$APK"
APK_SHA256="$(sha256sum "$APK" | awk '{print $1}')"
APK_SIZE="$(stat -c '%s' "$APK")"
APK_NAME="Pandora-${APP_VERSION//+/-}-${APP_SOURCE_SHA:0:12}-Kabukicho.apk"
cp "$APK" "$OUT/$APK_NAME"

cat > "$OUT/receipt.json" <<EOF
{
  "app_source_sha": "$APP_SOURCE_SHA",
  "builder_source_sha": "$BUILD_SOURCE_SHA",
  "app_version": "$APP_VERSION",
  "apk_file": "$APK_NAME",
  "apk_sha256": "$APK_SHA256",
  "apk_size_bytes": $APK_SIZE,
  "vision_feed": "Kabukicho / CamStreamer",
  "build_lane": "Vercel Git exact-source"
}
EOF

cat > "$OUT/index.html" <<EOF
<!doctype html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pandora Android exact-source build</title></head>
<body>
<h1>Pandora Android</h1>
<p>App source: <code>$APP_SOURCE_SHA</code></p>
<p>Builder commit: <code>$BUILD_SOURCE_SHA</code></p>
<p>SHA-256: <code>$APK_SHA256</code></p>
<p><a href="/$APK_NAME">Download APK</a></p>
<p><a href="/receipt.json">Build receipt</a></p>
</body>
</html>
EOF

echo "PANDORA_APK_READY app_source_sha=$APP_SOURCE_SHA builder_sha=$BUILD_SOURCE_SHA apk=$APK_NAME sha256=$APK_SHA256 size=$APK_SIZE"
