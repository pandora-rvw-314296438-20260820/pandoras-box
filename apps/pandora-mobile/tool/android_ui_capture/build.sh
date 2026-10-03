#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'Usage: build.sh OUTPUT_DIRECTORY RUNNER_DEBUG_KEYSTORE' >&2
  exit 2
fi
capture_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[[ -n "$sdk_dir" ]] || { echo 'Android SDK path is required.' >&2; exit 2; }
android_jar="$sdk_dir/platforms/android-36/android.jar"
build_tools="$sdk_dir/build-tools/36.0.0"
[[ -f "$android_jar" ]] || { echo 'Android SDK platform 36 android.jar is required.' >&2; exit 2; }
[[ -f "$2" ]] || { echo 'A runner-owned inspector debug keystore is required.' >&2; exit 2; }
for binary in aapt2 d8 zipalign apksigner; do
  [[ -x "$build_tools/$binary" ]] || { echo 'Android build-tools 36.0.0 are required.' >&2; exit 2; }
done
mkdir -p -- "$1"
output_dir="$(cd -- "$1" && pwd)"
scratch_dir="$(mktemp -d "$output_dir/.capture-build.XXXXXX")"
trap 'rm -rf -- "$scratch_dir"' EXIT
mkdir -p "$scratch_dir/classes" "$scratch_dir/dex"

javac --release 8 -classpath "$android_jar" -d "$scratch_dir/classes" \
  "$capture_dir/src/com/banataosystems/pandora/uicapture/CaptureXml.java" \
  "$capture_dir/src/com/banataosystems/pandora/uicapture/CaptureInstrumentation.java"
jar cf "$scratch_dir/classes.jar" -C "$scratch_dir/classes" .
"$build_tools/d8" --lib "$android_jar" --min-api 28 \
  --output "$scratch_dir/dex" "$scratch_dir/classes.jar"
"$build_tools/aapt2" link -o "$scratch_dir/unsigned.apk" \
  --manifest "$capture_dir/AndroidManifest.xml" -I "$android_jar"
zip -q -j "$scratch_dir/unsigned.apk" "$scratch_dir/dex/classes.dex"
"$build_tools/zipalign" -p 4 "$scratch_dir/unsigned.apk" "$scratch_dir/aligned.apk"

# Defaults are Android's public CI/debug signing convention only. A custom
# runner-owned debug key can supply these via environment variables. No key
# material is generated, read into output, copied into source, or logged.
export UI_CAPTURE_STORE_PASSWORD="${UI_CAPTURE_STORE_PASSWORD:-android}"
export UI_CAPTURE_KEY_PASSWORD="${UI_CAPTURE_KEY_PASSWORD:-android}"
"$build_tools/apksigner" sign --ks "$2" \
  --ks-key-alias "${UI_CAPTURE_KEY_ALIAS:-androiddebugkey}" \
  --ks-pass env:UI_CAPTURE_STORE_PASSWORD --key-pass env:UI_CAPTURE_KEY_PASSWORD \
  --out "$output_dir/pandora-ui-capture.apk" "$scratch_dir/aligned.apk"
"$build_tools/apksigner" verify "$output_dir/pandora-ui-capture.apk"
printf '%s\n' "$output_dir/pandora-ui-capture.apk"
