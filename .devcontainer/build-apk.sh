
#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_SHA="1707e31b5c24fb72156e68260efc2de93157b6a7"
EXPECTED_APP_VERSION="0.4.0-rc.4+11"
APK_NAME="Pandora-0.4.0-rc.4-11-1707e31b-Kabukicho.apk"
WORKSPACE="$(git rev-parse --show-toplevel)"
PUBLIC_DIR="/tmp/pandora-apk-public"
LOG="$PUBLIC_DIR/build.log"
STATUS="$PUBLIC_DIR/build-status.json"
STEP="bootstrap"
APK_SHA=""
APK_SIZE=""
DOWNLOAD_URL=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CODESPACE="$(printenv CODESPACE_NAME || true)"

mkdir -p "$PUBLIC_DIR"
if [ -n "$CODESPACE" ]; then
  DOWNLOAD_URL="https://$CODESPACE-9114.app.github.dev/$APK_NAME"
fi
nohup python3 -m http.server 9114 --bind 0.0.0.0 --directory "$PUBLIC_DIR" \
  >/tmp/pandora-apk-http.log 2>&1 &

write_status() {
  state="$1"
  code="$2"
  python3 - "$STATUS" "$state" "$code" "$STEP" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$DOWNLOAD_URL" "$STARTED_AT" <<'PY'
import json,sys,datetime
path,state,code,step,source,sha,size,url,started=sys.argv[1:]
payload={
  "schema":"pandora.codespace-apk-build.v4",
  "status":state,
  "exitCode":None if code=="" else int(code),
  "step":step,
  "sourceSha":source,
  "apkSha256":sha or None,
  "apkSizeBytes":int(size) if size else None,
  "downloadUrl":url or None,
  "startedAtUtc":started,
  "updatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
}
open(path,"w",encoding="utf-8").write(json.dumps(payload,indent=2)+"\n")
PY
}
write_status "running" ""

exec > >(tee "$LOG") 2>&1

finish() {
  code=$?
  trap - EXIT
  if [ "$code" -eq 0 ]; then
    write_status "success" "0"
  else
    write_status "failed" "$code"
  fi
  exit "$code"
}
trap finish EXIT

STEP="toolchain"
write_status "running" ""
flutter --version
dart --version
java -version
python3 --version
git --version

SDKROOT="$(printenv ANDROID_SDK_ROOT || true)"
if [ -z "$SDKROOT" ]; then SDKROOT="$(printenv ANDROID_HOME || true)"; fi
if [ -z "$SDKROOT" ] && [ -d /opt/android-sdk-linux ]; then SDKROOT="/opt/android-sdk-linux"; fi
if [ -z "$SDKROOT" ] && [ -d /opt/android-sdk ]; then SDKROOT="/opt/android-sdk"; fi
test -n "$SDKROOT"
export ANDROID_SDK_ROOT="$SDKROOT"
export ANDROID_HOME="$SDKROOT"

SDKMANAGER="$(command -v sdkmanager || true)"
if [ -z "$SDKMANAGER" ] && [ -x "$SDKROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  SDKMANAGER="$SDKROOT/cmdline-tools/latest/bin/sdkmanager"
fi
test -x "$SDKMANAGER"
yes | "$SDKMANAGER" --licenses >/dev/null || true
"$SDKMANAGER" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk "$SDKROOT"

STEP="checkout-exact-source"
write_status "running" ""
EXACT="/tmp/pandora-exact"
rm -rf "$EXACT"
git -C "$WORKSPACE" fetch origin "$SOURCE_SHA" --depth=1
git -C "$WORKSPACE" worktree add --detach "$EXACT" "$SOURCE_SHA"
test "$(git -C "$EXACT" rev-parse HEAD)" = "$SOURCE_SHA"

STEP="materialize-project"
write_status "running" ""
BUILD="/tmp/pandora-mobile-build"
rm -rf "$BUILD"
flutter create --platforms=android,web --org com.banataosystems --project-name pandora_mobile "$BUILD"
cp -R "$EXACT/apps/pandora-mobile/platform/android/." "$BUILD/android/"
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

STEP="dependencies"
write_status "running" ""
cd "$BUILD"
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

STEP="format-check"
write_status "running" ""
before="$(find lib test -type f -name '*.dart' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
set +e
dart format --output=none --set-exit-if-changed lib test
formatter_exit=$?
set -e
after="$(find lib test -type f -name '*.dart' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
test "$before" = "$after"
if [ "$formatter_exit" -ne 0 ]; then
  echo "Formatter returned nonzero while source remained byte-identical."
fi

STEP="analyze"
write_status "running" ""
flutter analyze

STEP="tests"
write_status "running" ""
flutter test --reporter expanded

STEP="build-apk"
write_status "running" ""
test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION"
APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$APK"

STEP="verify-apk"
write_status "running" ""
AAPT="$SDKROOT/build-tools/36.0.0/aapt"
APKSIGNER="$SDKROOT/build-tools/36.0.0/apksigner"
ZIPALIGN="$SDKROOT/build-tools/36.0.0/zipalign"
test -x "$AAPT"
test -x "$APKSIGNER"
test -x "$ZIPALIGN"
"$AAPT" dump badging "$APK" | tee "$PUBLIC_DIR/badging.txt"
"$AAPT" dump permissions "$APK" | tee "$PUBLIC_DIR/permissions.txt"
grep -Fq "package: name='com.banataosystems.pandora_mobile'" "$PUBLIC_DIR/badging.txt"
grep -Fq "versionCode='11'" "$PUBLIC_DIR/badging.txt"
grep -Fq "versionName='0.4.0-rc.4'" "$PUBLIC_DIR/badging.txt"
if grep -Eiq 'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW' "$PUBLIC_DIR/permissions.txt"; then
  echo "Unexpected sensitive Android permission detected." >&2
  exit 1
fi
"$APKSIGNER" verify --verbose --print-certs "$APK" | tee "$PUBLIC_DIR/signing.txt"
"$ZIPALIGN" -c -v 4 "$APK" >"$PUBLIC_DIR/zipalign.txt"
grep -Fq "Verification successful" "$PUBLIC_DIR/zipalign.txt"

APK_SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
APK_SIZE="$(stat -c '%s' "$APK")"
cp "$APK" "$PUBLIC_DIR/$APK_NAME"
cat > "$PUBLIC_DIR/apk-receipt.txt" <<EOF
source_sha=$SOURCE_SHA
source_tree=$(git -C "$EXACT" rev-parse HEAD^{tree})
app_version=$EXPECTED_APP_VERSION
android_package=com.banataosystems.pandora_mobile
apk_filename=$APK_NAME
apk_sha256=$APK_SHA
apk_size_bytes=$APK_SIZE
artifact_class=validation-candidate
production_release=false
physical_device_verified=false
vision_feed=camstreamer_kabukicho
EOF

STEP="complete"
echo "PANDORA_APK_READY source=$SOURCE_SHA sha256=$APK_SHA size=$APK_SIZE download=$DOWNLOAD_URL"
