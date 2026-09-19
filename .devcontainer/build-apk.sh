
#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_SHA="93c41ecc29d246d948fd6e098fc9bad7ecf73214"
EXPECTED_APP_VERSION="0.4.0-rc.4+11"
LLAMA_CPP_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
APK_NAME="Pandora-Local-AI-mainline-93c41ecc.apk"
WORKSPACE="$(git rev-parse --show-toplevel)"
PUBLIC_DIR="/tmp/pandora-apk-public"
LOG="$PUBLIC_DIR/build.log"
STATUS="$PUBLIC_DIR/build-status.json"
STEP="bootstrap"
APK_SHA=""
APK_SIZE=""
DOWNLOAD_URL=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RELEASE_TAG="pandora-local-ai-mainline-93c41ecc-build"
RELEASE_ID=""
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

publish_release_report() {
  token="${GITHUB_TOKEN:-}"
  repo="${GITHUB_REPOSITORY:-pandora-rvw-314296438-20260820/pandoras-box}"
  if [ -z "$token" ]; then
    echo "GITHUB_TOKEN unavailable; cannot publish build report." >&2
    return 0
  fi

  owner="${repo%%/*}"
  name="${repo#*/}"
  api="${GITHUB_API_URL:-https://api.github.com}"

  existing="$(curl -fsS \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    "$api/repos/$repo/releases/tags/$RELEASE_TAG" 2>/dev/null || true)"
  existing_id="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))' <<<"$existing" 2>/dev/null || true)"
  if [ -n "$existing_id" ]; then
    curl -fsS -X DELETE \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "$api/repos/$repo/releases/$existing_id" >/dev/null || true
  fi

  payload="$(python3 - "$RELEASE_TAG" "$SOURCE_SHA" "$STEP" <<'PY'
import json,sys
tag,source,step=sys.argv[1:]
print(json.dumps({
  "tag_name": tag,
  "target_commitish": source,
  "name": "Pandora Local AI Mainline Build 93c41ecc",
  "body": f"GitHub-hosted Codespaces build report for exact source {source}. Final step: {step}. Validation only.",
  "draft": False,
  "prerelease": True
}))
PY
)"
  release="$(curl -fsS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    -H "Content-Type: application/json" \
    "$api/repos/$repo/releases" --data-binary "$payload" || true)"
  RELEASE_ID="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))' <<<"$release" 2>/dev/null || true)"
  if [ -z "$RELEASE_ID" ]; then
    echo "Could not create GitHub build-report release." >&2
    return 0
  fi

  upload() {
    local file="$1"
    local asset_name="$2"
    local content_type="$3"
    [ -s "$file" ] || return 0
    curl -fsS -X POST \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      -H "Content-Type: $content_type" \
      --data-binary "@$file" \
      "https://uploads.github.com/repos/$owner/$name/releases/$RELEASE_ID/assets?name=$asset_name" \
      >/dev/null || true
  }

  upload "$STATUS" "build-status.json" "application/json"
  upload "$LOG" "build.log" "text/plain"
  upload "$PUBLIC_DIR/apk-receipt.txt" "apk-receipt.txt" "text/plain"
  upload "$PUBLIC_DIR/badging.txt" "badging.txt" "text/plain"
  upload "$PUBLIC_DIR/signing.txt" "signing.txt" "text/plain"
  upload "$PUBLIC_DIR/zipalign.txt" "zipalign.txt" "text/plain"
  upload "$PUBLIC_DIR/permissions.txt" "permissions.txt" "text/plain"
  upload "$PUBLIC_DIR/apk-files.txt" "apk-files.txt" "text/plain"
  if [ -n "$APK_SHA" ] && [ -s "$PUBLIC_DIR/$APK_NAME" ]; then
    upload "$PUBLIC_DIR/$APK_NAME" "$APK_NAME" "application/vnd.android.package-archive"
  fi
}

finish() {
  code=$?
  trap - EXIT
  if [ "$code" -eq 0 ]; then
    write_status "success" "0"
  else
    write_status "failed" "$code"
  fi
  publish_release_report || true
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
"$SDKMANAGER" "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;29.0.13113456" "cmake;3.31.6"
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
grep -Fq "native-code: 'arm64-v8a'" "$PUBLIC_DIR/badging.txt"
unzip -l "$APK" > "$PUBLIC_DIR/apk-files.txt"
grep -Fq 'lib/arm64-v8a/libai-chat.so' "$PUBLIC_DIR/apk-files.txt"
grep -Fq 'lib/arm64-v8a/libllama.so' "$PUBLIC_DIR/apk-files.txt"
grep -Fq 'lib/arm64-v8a/libggml.so' "$PUBLIC_DIR/apk-files.txt"
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
llama_cpp_sha=$LLAMA_CPP_SHA
local_ai_enabled=true
abi=arm64-v8a
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
