#!/usr/bin/env bash
set -euo pipefail
SOURCE_SHA="$VERCEL_GIT_COMMIT_SHA"
PRODUCT_BASE_SHA="771461eb623b708dc52df335fc7ce061aa65d360"
FLUTTER_VERSION="3.47.0"
ROOT="$PWD"
WORK="$ROOT/.apollo-android-runtime"
FLUTTER_ROOT="$WORK/flutter"
SDK="$WORK/android-sdk"
APP="$WORK/app"
OUT="$ROOT/verification-output"
REPORT="$OUT/report.txt"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT/screenshots" "$OUT/artifacts"
touch "$REPORT"
log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
pass() { log "PASS $*"; }
fail() { log "FAIL $*"; exit 1; }
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "exact source SHA missing"
[[ "$(git rev-parse HEAD)" == "$SOURCE_SHA" ]] || fail "checkout SHA mismatch"
PRODUCT_TREE="$(git rev-parse "$SOURCE_SHA:apps/pandora-mobile")"
BASE_TREE="$(git rev-parse "$PRODUCT_BASE_SHA:apps/pandora-mobile")"
[[ "$PRODUCT_TREE" == "$BASE_TREE" ]] || fail "mobile product tree changed in verification branch"
pass "mobile product tree identical to canonical main: $PRODUCT_TREE"
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$FLUTTER_VERSION-stable.tar.xz" -o "$WORK/flutter.tar.xz"
tar -xJf "$WORK/flutter.tar.xz" -C "$WORK"
git config --global --add safe.directory "$FLUTTER_ROOT"
export PATH="$FLUTTER_ROOT/bin:$PATH"
ACTUAL_FLUTTER="$(flutter --version --machine | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(JSON.parse(d).frameworkVersion||""));')"
[[ "$ACTUAL_FLUTTER" == "$FLUTTER_VERSION" ]] || fail "Flutter version mismatch"
pass "Flutter $FLUTTER_VERSION"
if command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1 | grep -Eq '"17[.]'; then
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
else
  curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" -o "$WORK/jdk17.tar.gz"
  mkdir -p "$WORK/jdk17"
  tar -xzf "$WORK/jdk17.tar.gz" -C "$WORK/jdk17" --strip-components=1
  JAVA_HOME="$WORK/jdk17"
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | tee "$OUT/java-version.txt"
pass "JDK 17"
mkdir -p "$SDK/cmdline-tools"
curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$WORK/android-tools.zip"
python3 -m zipfile -e "$WORK/android-tools.zip" "$WORK/android-tools"
mv "$WORK/android-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
chmod -R u+rx "$SDK/cmdline-tools/latest/bin"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$SDK/emulator:$PATH"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-35;google_apis;x86_64" | tee "$OUT/sdkmanager.txt"
flutter config --android-sdk "$SDK" >/dev/null
pass "Android SDK and emulator image"
mkdir -p "$APP"
cd "$APP"
flutter create --platforms=android --org com.banataosystems --project-name pandora_mobile . >/dev/null
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile | tee "$OUT/flutter-pub-get.txt"
python3 - <<'PYLOCK'
from pathlib import Path
if Path("pubspec.lock").read_bytes() != Path("pubspec.lock.expected").read_bytes():
    raise SystemExit("canonical lockfile changed")
PYLOCK
flutter analyze | tee "$OUT/flutter-analyze.txt"
pass "flutter analyze exact product source"
flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" | tee "$OUT/production-apk-build.txt"
APK="$(find build/app/outputs/flutter-apk -name '*arm64-v8a-release.apk' -o -name 'app-release.apk' | head -1)"
[[ -n "$APK" && -s "$APK" ]] || fail "production arm64 APK missing"
APK_SHA="$(sha256sum "$APK" | awk '{print $1}')"
APK_SIZE="$(stat -c%s "$APK")"
cp "$APK" "$OUT/artifacts/pandora-mobile-$SOURCE_SHA-arm64.apk"
pass "production APK sha256=$APK_SHA size=$APK_SIZE"
python3 - <<'PY'
from pathlib import Path
p=Path('pubspec.yaml')
s=p.read_text()
needle='dev_dependencies:\n'
addition='  integration_test:\n    sdk: flutter\n'
if addition not in s:
    s=s.replace(needle, needle+addition, 1)
p.write_text(s)
PY
mkdir -p integration_test
cp "$ROOT/verification/apollo_chat/runtime_test.dart" integration_test/apollo_chat_runtime_test.dart
flutter pub get | tee "$OUT/integration-pub-get.txt"
echo no | avdmanager create avd -n pandora_apollo_api35 -k "system-images;android-35;google_apis;x86_64" -d pixel_7 >/dev/null
"$SDK/emulator/emulator" -avd pandora_apollo_api35 -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data -gpu swiftshader_indirect -accel off -memory 2048 -cores 2 >"$OUT/emulator.log" 2>&1 &
EMU_PID=$!
trap 'kill "$EMU_PID" >/dev/null 2>&1 || true' EXIT
BOOTED=0
for n in $(seq 1 180); do
  kill -0 "$EMU_PID" >/dev/null 2>&1 || { cat "$OUT/emulator.log"; fail "emulator exited before boot"; }
  if adb devices | grep -q 'emulator-' && [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then BOOTED=1; break; fi
  sleep 2
done
[[ "$BOOTED" == "1" ]] || { cat "$OUT/emulator.log"; fail "emulator boot timeout"; }
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell settings put secure show_ime_with_hard_keyboard 1 || true
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0
adb shell wm size | tee "$OUT/wm-size.txt"
adb shell wm density | tee "$OUT/wm-density.txt"
pass "Android emulator API 35 booted"
flutter test integration_test/apollo_chat_runtime_test.dart -d emulator-5554 --reporter expanded | tee "$OUT/android-runtime-test.txt"
pass "Android runtime interaction acceptance"
PACKAGE="com.banataosystems.pandora_mobile"
for name in initial under-floating-header keyboard-open composer-grown keyboard-closed reading-position-keyboard landscape; do
  if adb shell run-as "$PACKAGE" test -s "cache/apollo-$name.png" 2>/dev/null; then
    adb exec-out run-as "$PACKAGE" cat "cache/apollo-$name.png" > "$OUT/screenshots/$name.png"
  fi
done
adb exec-out screencap -p > "$OUT/screenshots/final-device.png" || true
cat > "$OUT/artifact-manifest.json" <<EOF
{"verification_branch_sha":"$SOURCE_SHA","canonical_product_base_sha":"$PRODUCT_BASE_SHA","mobile_product_tree_sha":"$PRODUCT_TREE","flutter_version":"$FLUTTER_VERSION","android_runtime":{"device":"Android emulator API 35 x86_64 software acceleration","status":"PASS"},"production_apk":{"file":"artifacts/pandora-mobile-$SOURCE_SHA-arm64.apk","sha256":"$APK_SHA","size_bytes":$APK_SIZE,"abi":"arm64-v8a","mode":"release"}}
EOF
cat > "$OUT/index.html" <<EOF
<!doctype html><meta charset="utf-8"><title>Apollo Android verification</title><h1>Apollo Android verification: PASS</h1><p>Verification SHA: <code>$SOURCE_SHA</code></p><p>Canonical mobile tree: <code>$PRODUCT_TREE</code></p><p>APK SHA-256: <code>$APK_SHA</code></p><p><a href="report.txt">Report</a> | <a href="artifact-manifest.json">Manifest</a> | <a href="artifacts/pandora-mobile-$SOURCE_SHA-arm64.apk">APK</a></p>
EOF
pass "all Apollo acceptance checks completed"
