#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP_DIR="$ROOT/tools/pandora-vulkan-benchmark"
LLAMA_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
BUILD_SOURCE_SHA="$(git rev-parse HEAD)"
ANDROID_HOME="$HOME/android-sdk"
GRADLE_VERSION="8.11.1"
NDK_VERSION="27.2.12479018"
STATUS_DIR="$ROOT/artifacts/pandora-vulkan-benchmark"
STATUS_FILE="$STATUS_DIR/build-status.txt"
ERROR_FILE="$STATUS_DIR/build-error-tail.txt"

publish_status() {
  local phase="$1"
  local detail="$2"
  mkdir -p "$STATUS_DIR"
  {
    echo "phase=$phase"
    echo "detail=$detail"
    echo "source_sha=$BUILD_SOURCE_SHA"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STATUS_FILE"

  (
    cd "$ROOT"
    git config user.name "Pandora Codespace Builder"
    git config user.email "pandora-codespace-builder@users.noreply.github.com"
    git add artifacts/pandora-vulkan-benchmark/build-status.txt
    if [ -f "$ERROR_FILE" ]; then
      git add artifacts/pandora-vulkan-benchmark/build-error-tail.txt
    fi
    git commit -m "build: Vulkan benchmark status $phase [skip ci]" || true
    git push origin HEAD:chatgpt/vulkan-benchmark-20260919 || true
  ) >/tmp/pandora-status-publish.log 2>&1 || true
}

on_error() {
  local code="$?"
  local line="$1"
  trap - ERR
  if [ -f /tmp/pandora-gradle-build.log ]; then
    tail -n 500 /tmp/pandora-gradle-build.log > "$ERROR_FILE" || true
  fi
  publish_status "failed" "exit=$code line=$line"
  exit "$code"
}
trap 'on_error $LINENO' ERR

rm -f "$ERROR_FILE"
publish_status "started" "Codespace builder started"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openjdk-17-jdk curl unzip git build-essential ninja-build \
  libvulkan-dev glslc spirv-headers spirv-tools

rm -rf "$APP_DIR/app/src/main/cpp/vulkan-headers"
mkdir -p "$APP_DIR/app/src/main/cpp/vulkan-headers/include"
cp -a /usr/include/vulkan "$APP_DIR/app/src/main/cpp/vulkan-headers/include/"
cp -a /usr/include/spirv "$APP_DIR/app/src/main/cpp/vulkan-headers/include/"
test -f "$APP_DIR/app/src/main/cpp/vulkan-headers/include/vulkan/vulkan.hpp"
test -f "$APP_DIR/app/src/main/cpp/vulkan-headers/include/spirv/unified1/spirv.hpp"

publish_status "toolchain" "Installing Android SDK and Gradle"

mkdir -p "$ANDROID_HOME/cmdline-tools"
curl -fsSL \
  "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
  -o /tmp/android-commandline-tools.zip
rm -rf /tmp/android-commandline-tools
mkdir -p /tmp/android-commandline-tools
unzip -q /tmp/android-commandline-tools.zip -d /tmp/android-commandline-tools
mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
cp -a /tmp/android-commandline-tools/cmdline-tools/. "$ANDROID_HOME/cmdline-tools/latest/"

export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null || true
sdkmanager \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "ndk;$NDK_VERSION" \
  "cmake;3.22.1"

GRADLE_HOME="$HOME/gradle-$GRADLE_VERSION"
if [ ! -x "$GRADLE_HOME/bin/gradle" ]; then
  curl -fsSL "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" -o /tmp/gradle.zip
  unzip -q /tmp/gradle.zip -d "$HOME"
fi
export PATH="$GRADLE_HOME/bin:$PATH"

GLSLC_PATH="$(command -v glslc)"
SPIRV_CONFIG="$(find /usr -name SPIRV-HeadersConfig.cmake -print -quit)"
test -n "$GLSLC_PATH"
test -n "$SPIRV_CONFIG"
export GLSLC_PATH
export SPIRV_HEADERS_DIR="$(dirname "$SPIRV_CONFIG")"

publish_status "source" "Fetching exact llama.cpp $LLAMA_SHA"

rm -rf "$APP_DIR/app/src/main/cpp/llama.cpp"
git clone --filter=blob:none https://github.com/ggml-org/llama.cpp.git "$APP_DIR/app/src/main/cpp/llama.cpp"
git -C "$APP_DIR/app/src/main/cpp/llama.cpp" checkout "$LLAMA_SHA"
test "$(git -C "$APP_DIR/app/src/main/cpp/llama.cpp" rev-parse HEAD)" = "$LLAMA_SHA"

publish_status "building" "Gradle assembleDebug with GGML_VULKAN=ON"

cd "$APP_DIR"
set +e
gradle --no-daemon :app:assembleDebug --stacktrace 2>&1 | tee /tmp/pandora-gradle-build.log
GRADLE_RC="\${PIPESTATUS[0]}"
set -e
if [ "$GRADLE_RC" -ne 0 ]; then
  tail -n 500 /tmp/pandora-gradle-build.log > "$ERROR_FILE"
  trap - ERR
  publish_status "failed" "gradle_exit=$GRADLE_RC"
  exit "$GRADLE_RC"
fi

mkdir -p dist
cp app/build/outputs/apk/debug/app-debug.apk dist/Pandora-Vulkan-Benchmark.apk
sha256sum dist/Pandora-Vulkan-Benchmark.apk | tee dist/Pandora-Vulkan-Benchmark.apk.sha256

cat > dist/build-metadata.txt <<EOF
repository=pandora-rvw-314296438-20260820/pandoras-box
source_sha=$BUILD_SOURCE_SHA
branch=chatgpt/vulkan-benchmark-20260919
llama_cpp_sha=$LLAMA_SHA
abi=arm64-v8a
ggml_vulkan=ON
EOF

publish_status "publishing" "Publishing APK to GitHub prerelease"

cd "$ROOT"
TAG="pandora-vulkan-benchmark-$(echo "$BUILD_SOURCE_SHA" | cut -c1-8)"

gh auth status
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" \
    "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk" \
    "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk.sha256" \
    "$APP_DIR/dist/build-metadata.txt" \
    --clobber
else
  gh release create "$TAG" \
    "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk" \
    "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk.sha256" \
    "$APP_DIR/dist/build-metadata.txt" \
    --target "$BUILD_SOURCE_SHA" \
    --prerelease \
    --title "Pandora Vulkan Benchmark $(echo "$BUILD_SOURCE_SHA" | cut -c1-8)" \
    --notes "Standalone Android Vulkan/GPU-offload benchmark. Uses llama.cpp $LLAMA_SHA."
fi

trap - ERR
rm -f "$ERROR_FILE"
publish_status "success" "release_tag=$TAG"
