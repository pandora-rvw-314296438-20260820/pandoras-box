
#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_SHA="1707e31b5c24fb72156e68260efc2de93157b6a7"
FLUTTER_SHA="4cf24164269a5ebf0c16a028a00727d0e77bbb05"
EXPECTED_APP_VERSION="0.4.0-rc.4+11"
REPO="pandora-rvw-314296438-20260820/pandoras-box"
BUILD_BRANCH="build/codespace-apk-1707e31b-20260919"
TAG="pandora-mobile-1707e31b-kabukicho"
APK_NAME="Pandora-0.4.0-rc.4-11-1707e31b-Kabukicho.apk"
WORKSPACE="$(git rev-parse --show-toplevel)"
LOG="$WORKSPACE/.devcontainer/build.log"
STATUS="$WORKSPACE/.devcontainer/build-status.json"
TAIL="$WORKSPACE/.devcontainer/build-tail.log"
STEP="bootstrap"
APK_SHA=""
APK_SIZE=""
RELEASE_URL=""
DOWNLOAD_URL=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export GH_TOKEN="$GITHUB_TOKEN"

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
  tail -n 240 "$LOG" > "$TAIL" || true
  python3 - "$STATUS" "$status" "$code" "$STEP" "$SOURCE_SHA" "$APK_SHA" "$APK_SIZE" "$RELEASE_URL" "$DOWNLOAD_URL" "$STARTED_AT" <<'PY'
import json,sys,datetime
path,status,code,step,source,sha,size,release_url,download_url,started=sys.argv[1:]
payload={
  "schema":"pandora.codespace-apk-build.v3",
  "status":status,
  "exitCode":int(code),
  "step":step,
  "sourceSha":source,
  "apkSha256":sha or None,
  "apkSizeBytes":int(size) if size else None,
  "releaseUrl":release_url or None,
  "downloadUrl":download_url or None,
  "startedAtUtc":started,
  "finishedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),
}
open(path,"w",encoding="utf-8").write(json.dumps(payload,indent=2)+"\n")
PY
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    put_receipt ".devcontainer/build-status.json" "$STATUS" "chore: record exact Pandora APK build status" || true
    put_receipt ".devcontainer/build-tail.log" "$TAIL" "chore: record exact Pandora APK build diagnostics" || true
  fi
  exit "$code"
}
trap record_status EXIT

STEP="install-host-tools"
sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn.sources
sudo find /etc/apt/sources.list.d -maxdepth 1 -type f -iname '*yarn*' -delete 2>/dev/null || true
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl unzip zip xz-utils libglu1-mesa git python3 openjdk-17-jdk ca-certificates gh

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export FLUTTER_ROOT="$HOME/flutter"
export PATH="$FLUTTER_ROOT/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

STEP="install-android-sdk"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd /tmp
curl -fL --retry 4 -o android-cmdline.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
echo "4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583  android-cmdline.zip" | sha256sum -c -
rm -rf /tmp/android-cmdline
mkdir -p /tmp/android-cmdline
unzip -q android-cmdline.zip -d /tmp/android-cmdline
rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
mv /tmp/android-cmdline/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"

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

STEP="resolve-lockfile"
cd "$BUILD"
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

STEP="verify-formatter"
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
flutter analyze

STEP="test"
flutter test --reporter expanded

STEP="build-apk"
test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION"
APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
test -f "$APK"

STEP="verify-apk"
AAPT="$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt"
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner"
ZIPALIGN="$ANDROID_SDK_ROOT/build-tools/36.0.0/zipalign"
"$AAPT" dump badging "$APK" | tee /tmp/badging.txt
"$AAPT" dump permissions "$APK" | tee /tmp/permissions.txt
grep -Fq "package: name='com.banataosystems.pandora_mobile'" /tmp/badging.txt
grep -Fq "versionCode='11'" /tmp/badging.txt
grep -Fq "versionName='0.4.0-rc.4'" /tmp/badging.txt
if grep -Eiq 'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW' /tmp/permissions.txt; then
  echo "Unexpected sensitive Android permission detected." >&2
  exit 1
fi
"$APKSIGNER" verify --verbose --print-certs "$APK"
"$ZIPALIGN" -c -v 4 "$APK" >/tmp/zipalign.txt
grep -Fq "Verification successful" /tmp/zipalign.txt
APK_SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
APK_SIZE="$(stat -c '%s' "$APK")"

STEP="publish-github-prerelease"
DOWNLOAD_DIR=/tmp/pandora-apk-download
rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"
cp "$APK" "$DOWNLOAD_DIR/$APK_NAME"
RECEIPT="$DOWNLOAD_DIR/apk-receipt.txt"
cat > "$RECEIPT" <<EOF
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

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DOWNLOAD_DIR/$APK_NAME" "$RECEIPT" --repo "$REPO" --clobber
else
  gh release create "$TAG" \
    "$DOWNLOAD_DIR/$APK_NAME" "$RECEIPT" \
    --repo "$REPO" \
    --target "$SOURCE_SHA" \
    --prerelease \
    --title "Pandora Android validation candidate — Kabukicho" \
    --notes "Exact-source Android validation candidate from $SOURCE_SHA. Includes workspace/Batalla/chat fixes and Kabukicho Vision Intelligence. Production release=false; physical device verification=false."
fi
RELEASE_URL="$(gh release view "$TAG" --repo "$REPO" --json url --jq .url)"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APK_NAME"

STEP="complete"
echo "PANDORA_APK_READY source=$SOURCE_SHA sha256=$APK_SHA size=$APK_SIZE download=$DOWNLOAD_URL"
