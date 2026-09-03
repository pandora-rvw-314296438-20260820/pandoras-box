
#!/usr/bin/env bash
set -euo pipefail

SOURCE_SHA="${VERCEL_GIT_COMMIT_SHA:-${PANDORA_SOURCE_REVISION:-}}"
FLUTTER_VERSION="3.47.0"
APP_VERSION="$(awk '/^version:/{print $2; exit}' apps/pandora-mobile/pubspec.yaml)"
WORK_ROOT="${PWD}/.pandora-vercel-web"
FLUTTER_ROOT="${WORK_ROOT}/flutter"
BUILD_ROOT="${WORK_ROOT}/app"
OUTPUT_ROOT="${PWD}/public/pandora-web"

if [[ -z "$SOURCE_SHA" || ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Exact 40-character source SHA is required for Pandora web production build.' >&2
  exit 1
fi

if command -v git >/dev/null 2>&1 && [[ -d .git ]]; then
  test "$(git rev-parse HEAD)" = "$SOURCE_SHA"
fi

rm -rf "$WORK_ROOT" "$OUTPUT_ROOT"
mkdir -p "$WORK_ROOT" "$OUTPUT_ROOT"

archive="${WORK_ROOT}/flutter.tar.xz"
curl --fail --silent --show-error --location \
  "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  --output "$archive"
tar -xJf "$archive" -C "$WORK_ROOT"
export PATH="${FLUTTER_ROOT}/bin:${PATH}"
flutter --version --machine | grep -Fq "\"frameworkVersion\":\"${FLUTTER_VERSION}\""

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"
flutter create --platforms=web --org com.banataosystems --project-name pandora_mobile . >/dev/null
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R "${OLDPWD}/apps/pandora-mobile/lib" ./lib
cp -R "${OLDPWD}/apps/pandora-mobile/test" ./test
cp -R "${OLDPWD}/apps/pandora-mobile/assets" ./assets
cp "${OLDPWD}/apps/pandora-mobile/pubspec.yaml" ./pubspec.yaml
cp "${OLDPWD}/apps/pandora-mobile/pubspec.lock" ./pubspec.lock
cp "${OLDPWD}/apps/pandora-mobile/analysis_options.yaml" ./analysis_options.yaml
cp pubspec.lock pubspec.lock.expected
flutter pub get --enforce-lockfile >/dev/null
cmp pubspec.lock.expected pubspec.lock
flutter build web --release \
  --base-href /pandora-web/ \
  --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
  --dart-define=PANDORA_APP_VERSION="$APP_VERSION"
cp -R build/web/. "$OUTPUT_ROOT/"

web_tree_sha256="$(find "$OUTPUT_ROOT" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
cat > "${OUTPUT_ROOT}/pandora-web-release-manifest.txt" <<EOF
source_sha=${SOURCE_SHA}
app_version=${APP_VERSION}
flutter_version=${FLUTTER_VERSION}
web_tree_sha256=${web_tree_sha256}
artifact_class=production-candidate
production_release=true
EOF

test -s "${OUTPUT_ROOT}/index.html"
test -s "${OUTPUT_ROOT}/main.dart.js"
grep -Fq '<base href="/pandora-web/">' "${OUTPUT_ROOT}/index.html"
printf 'PANDORA_WEB_RELEASE source_sha=%s app_version=%s flutter_version=%s web_tree_sha256=%s\n' \
  "$SOURCE_SHA" "$APP_VERSION" "$FLUTTER_VERSION" "$web_tree_sha256"
