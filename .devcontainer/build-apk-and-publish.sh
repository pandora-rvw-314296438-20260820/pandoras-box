
#!/usr/bin/env bash
set -euo pipefail

SOURCE_SHA="1707e31b5c24fb72156e68260efc2de93157b6a7"
EXPECTED_APP_VERSION="0.4.0-rc.4+11"
TAG="pandora-mobile-1707e31b-kabukicho"
APK_NAME="Pandora-0.4.0-rc.4-11-1707e31b-Kabukicho.apk"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

test "$(git merge-base "$SOURCE_SHA" HEAD)" = "$SOURCE_SHA"
git diff --quiet "$SOURCE_SHA" -- apps/pandora-mobile supabase/functions

echo "PANDORA_CODESPACE_BUILD source_sha=$SOURCE_SHA"
flutter --version
java -version

SDKROOT="$ANDROID_SDK_ROOT"
if [[ -z "$SDKROOT" ]]; then
  SDKROOT="$ANDROID_HOME"
fi
if [[ -n "$SDKROOT" ]]; then
  SDKMANAGER="$SDKROOT/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$SDKMANAGER" ]]; then
    yes | "$SDKMANAGER" "platforms;android-36" "build-tools;36.0.0" >/dev/null || true
  fi
fi

BUILD_DIR="$ROOT/.pandora-codespace-build"
DIST_DIR="$ROOT/.pandora-apk-dist"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

cd "$BUILD_DIR"
flutter create \
  --platforms=android,web \
  --org com.banataosystems \
  --project-name pandora_mobile \
  .

cp -R "$ROOT/apps/pandora-mobile/platform/android/." ./android/
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "$ROOT/apps/pandora-mobile/lib" ./lib
cp -R "$ROOT/apps/pandora-mobile/test" ./test
cp -R "$ROOT/apps/pandora-mobile/assets" ./assets
cp "$ROOT/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "$ROOT/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "$ROOT/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml

python3 "$ROOT/apps/pandora-mobile/tool/configure_validation_android.py" \
  android/app/src/main/AndroidManifest.xml

cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile
cmp pubspec.lock.expected pubspec.lock

before="$(
  find lib test -type f -name '*.dart' -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | cut -d ' ' -f1
)"
set +e
dart format --output=none --set-exit-if-changed lib test
formatter_exit=$?
set -e
after="$(
  find lib test -type f -name '*.dart' -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | cut -d ' ' -f1
)"
test "$before" = "$after"
if [[ "$formatter_exit" -ne 0 ]]; then
  echo "Formatter returned nonzero while source remained byte-identical; continuing."
fi

flutter analyze
flutter test --reporter expanded

test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION"

flutter build apk --debug \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION"

APK="$BUILD_DIR/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$APK"

if [[ -n "$SDKROOT" ]]; then
  AAPT="$SDKROOT/build-tools/36.0.0/aapt"
  APKSIGNER="$SDKROOT/build-tools/36.0.0/apksigner"
  if [[ -x "$AAPT" && -x "$APKSIGNER" ]]; then
    "$AAPT" dump badging "$APK" > "$DIST_DIR/badging.txt"
    "$AAPT" dump permissions "$APK" > "$DIST_DIR/permissions.txt"
    "$APKSIGNER" verify --verbose --print-certs "$APK" > "$DIST_DIR/signing.txt"
    grep -Fq "package: name='com.banataosystems.pandora_mobile'" "$DIST_DIR/badging.txt"
    grep -Fq "versionCode='11'" "$DIST_DIR/badging.txt"
    grep -Fq "versionName='0.4.0-rc.4'" "$DIST_DIR/badging.txt"
    if grep -Eiq 'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW' "$DIST_DIR/permissions.txt"; then
      echo "Unexpected sensitive Android permission detected." >&2
      exit 1
    fi
  fi
fi

cp "$APK" "$DIST_DIR/$APK_NAME"
APK_SHA256="$(sha256sum "$DIST_DIR/$APK_NAME" | cut -d ' ' -f1)"
APK_SIZE="$(stat -c '%s' "$DIST_DIR/$APK_NAME")"

cat > "$DIST_DIR/apk-receipt.txt" <<EOF
source_sha=$SOURCE_SHA
source_tree=$(git rev-parse "$SOURCE_SHA^{tree}")
build_branch=$(git rev-parse --abbrev-ref HEAD)
build_head=$(git rev-parse HEAD)
app_version=$EXPECTED_APP_VERSION
android_package=com.banataosystems.pandora_mobile
apk_filename=$APK_NAME
apk_sha256=$APK_SHA256
apk_size_bytes=$APK_SIZE
artifact_class=validation-candidate
production_release=false
physical_device_verified=false
vision_feed=camstreamer_kabukicho
EOF

echo "PANDORA_APK_RECEIPT source_sha=$SOURCE_SHA apk_sha256=$APK_SHA256 apk_size_bytes=$APK_SIZE"

python3 - "$DIST_DIR/$APK_NAME" "$DIST_DIR/apk-receipt.txt" "$TAG" <<'PY' || true
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

apk_path, receipt_path, tag = sys.argv[1:]
token = os.environ.get("GITHUB_TOKEN", "")
repo = os.environ.get("GITHUB_REPOSITORY", "")
api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
if not token or not repo:
    raise SystemExit("Codespaces GitHub token/repository context unavailable")

base_headers = {
    "Authorization": "Bearer " + token,
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2026-03-10",
    "User-Agent": "Pandora-Codespaces-APK-Builder/1.0",
}

def request(method, url, payload=None, content_type=None):
    data = None
    headers = dict(base_headers)
    if payload is not None:
        if isinstance(payload, (dict, list)):
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        else:
            data = payload
            headers["Content-Type"] = content_type or "application/octet-stream"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None

try:
    release = request("GET", api + "/repos/" + repo + "/releases/tags/" + tag)
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        raise
    release = request(
        "POST",
        api + "/repos/" + repo + "/releases",
        {
            "tag_name": tag,
            "target_commitish": "1707e31b5c24fb72156e68260efc2de93157b6a7",
            "name": "Pandora Android validation candidate — Kabukicho",
            "body": (
                "Exact-source Android validation candidate from "
                "1707e31b5c24fb72156e68260efc2de93157b6a7. "
                "Includes workspace/Batalla/chat fixes and Kabukicho Vision Intelligence. "
                "Production release=false; physical device verification=false."
            ),
            "draft": False,
            "prerelease": True,
        },
    )

assets = release.get("assets", [])
by_name = {asset.get("name"): asset for asset in assets}
for path in (apk_path, receipt_path):
    name = os.path.basename(path)
    old = by_name.get(name)
    if old and old.get("id"):
        request("DELETE", api + "/repos/" + repo + "/releases/assets/" + str(old["id"]))
    upload_base = release["upload_url"].split("{", 1)[0]
    upload_url = upload_base + "?" + urllib.parse.urlencode({"name": name})
    with open(path, "rb") as handle:
        payload = handle.read()
    request(
        "POST",
        upload_url,
        payload,
        "application/vnd.android.package-archive"
        if name.endswith(".apk")
        else "text/plain",
    )
print("PANDORA_RELEASE_UPLOAD_COMPLETE")
PY

cd "$DIST_DIR"
nohup python3 -m http.server 8080 --bind 0.0.0.0 > "$DIST_DIR/http-server.log" 2>&1 &
echo $! > "$DIST_DIR/http-server.pid"
echo "Pandora APK ready at http://127.0.0.1:8080/$APK_NAME"
