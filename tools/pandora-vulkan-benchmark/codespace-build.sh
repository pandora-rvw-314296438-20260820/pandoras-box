#!/usr/bin/env bash
set -euxo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP_DIR="$ROOT/tools/pandora-vulkan-benchmark"
LLAMA_SHA="44be98f057e9f9902a8ee12630e181c7f8ec2953"
ANDROID_HOME="$HOME/android-sdk"
GRADLE_VERSION="8.11.1"
NDK_VERSION="27.2.12479018"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openjdk-17-jdk \
  curl unzip git build-essential ninja-build \
  libvulkan-dev glslc spirv-headers spirv-tools

mkdir -p "$ANDROID_HOME/cmdline-tools"
curl -fsSL \
  "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
  -o /tmp/android-commandline-tools.zip
rm -rf /tmp/android-commandline-tools
mkdir -p /tmp/android-commandline-tools
unzip -q /tmp/android-commandline-tools.zip -d /tmp/android-commandline-tools
mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
cp -a /tmp/android-commandline-tools/cmdline-tools/. \
  "$ANDROID_HOME/cmdline-tools/latest/"

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
  curl -fsSL \
    "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" \
    -o /tmp/gradle.zip
  unzip -q /tmp/gradle.zip -d "$HOME"
fi
export PATH="$GRADLE_HOME/bin:$PATH"

GLSLC_PATH="$(command -v glslc)"
SPIRV_CONFIG="$(find /usr -name SPIRV-HeadersConfig.cmake -print -quit)"
test -n "$GLSLC_PATH"
test -n "$SPIRV_CONFIG"
export GLSLC_PATH
export SPIRV_HEADERS_DIR="$(dirname "$SPIRV_CONFIG")"

rm -rf "$APP_DIR/app/src/main/cpp/llama.cpp"
git clone --filter=blob:none \
  https://github.com/ggml-org/llama.cpp.git \
  "$APP_DIR/app/src/main/cpp/llama.cpp"
git -C "$APP_DIR/app/src/main/cpp/llama.cpp" checkout "$LLAMA_SHA"
test "$(git -C "$APP_DIR/app/src/main/cpp/llama.cpp" rev-parse HEAD)" = "$LLAMA_SHA"

cd "$APP_DIR"
gradle --no-daemon :app:assembleDebug --stacktrace

mkdir -p dist
cp app/build/outputs/apk/debug/app-debug.apk \
  dist/Pandora-Vulkan-Benchmark.apk
sha256sum dist/Pandora-Vulkan-Benchmark.apk \
  | tee dist/Pandora-Vulkan-Benchmark.apk.sha256

SOURCE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
cat > dist/build-metadata.txt <<EOF
repository=pandora-rvw-314296438-20260820/pandoras-box
source_sha=$SOURCE_SHA
branch=chatgpt/vulkan-benchmark-20260919
llama_cpp_sha=$LLAMA_SHA
abi=arm64-v8a
ggml_vulkan=ON
EOF

cd "$ROOT"
TAG="pandora-vulkan-benchmark-$(echo "$SOURCE_SHA" | cut -c1-8)"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
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
      --target "$SOURCE_SHA" \
      --prerelease \
      --title "Pandora Vulkan Benchmark $(echo "$SOURCE_SHA" | cut -c1-8)" \
      --notes "Standalone Android Vulkan/GPU-offload benchmark. Uses llama.cpp $LLAMA_SHA."
  fi
else
  mkdir -p "$ROOT/artifacts/pandora-vulkan-benchmark"
  cp "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk" \
     "$ROOT/artifacts/pandora-vulkan-benchmark/"
  cp "$APP_DIR/dist/Pandora-Vulkan-Benchmark.apk.sha256" \
     "$ROOT/artifacts/pandora-vulkan-benchmark/"
  cp "$APP_DIR/dist/build-metadata.txt" \
     "$ROOT/artifacts/pandora-vulkan-benchmark/"
  git config user.name "Pandora Codespace Builder"
  git config user.email "pandora-codespace-builder@users.noreply.github.com"
  git add artifacts/pandora-vulkan-benchmark
  git commit -m "build: publish Pandora Vulkan benchmark APK [skip ci]"
  git push origin HEAD:chatgpt/vulkan-benchmark-20260919
fi
