# syntax=docker/dockerfile:1
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ENV SOURCE_SHA=3f8fe73cbc3387b2fa864122df1fbb2cb0358fb3 \
    SOURCE_TREE=69a44228d0872e0fd181bb3aee98f35925b2f9cc \
    SOURCE_APPS_TREE=d4c330b0e5e8d165443b49db0428f4202f29970c \
    FLUTTER_VERSION=3.47.0 \
    EXPECTED_APP_VERSION=0.4.0-rc.4+11

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git xz-utils unzip python3 coreutils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://api.adoptium.net/v3/binary/version/jdk-17.0.20%2B8/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk17.tar.gz \
    && mkdir -p /opt/jdk \
    && tar -xzf /tmp/jdk17.tar.gz --strip-components=1 -C /opt/jdk \
    && rm /tmp/jdk17.tar.gz

ENV JAVA_HOME=/opt/jdk
ENV PATH="/opt/jdk/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH"

RUN java -version

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.0-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --system --add safe.directory /opt/flutter \
    && flutter config --no-analytics \
    && flutter --version

RUN mkdir -p /opt/android-sdk/cmdline-tools \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" -o /tmp/android-tools.zip \
    && python3 -c "import zipfile; zipfile.ZipFile('/tmp/android-tools.zip').extractall('/tmp/android-tools')" \
    && mv /tmp/android-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip \
    && yes | sdkmanager --licenses >/dev/null || true

RUN sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'

WORKDIR /src
COPY . .

RUN test -f apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart \
    && grep -Fq 'final GlobalKey _headerKey = GlobalKey();' apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart \
    && grep -Fq 'void _scheduleOverlayMeasure()' apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart \
    && grep -Fq 'WidgetsBinding.instance.removeObserver(this);' apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart

RUN rm -rf .pandora-mobile-build \
    && mkdir .pandora-mobile-build \
    && cd .pandora-mobile-build \
    && flutter create --platforms=android,web --org com.banataosystems --project-name pandora_mobile . \
    && cp -R ../apps/pandora-mobile/platform/android/. ./android/ \
    && rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml \
    && cp -R ../apps/pandora-mobile/lib ./lib \
    && cp -R ../apps/pandora-mobile/test ./test \
    && cp -R ../apps/pandora-mobile/assets ./assets \
    && cp -R ../apps/pandora-mobile/platform ./platform \
    && cp ../apps/pandora-mobile/pubspec.yaml ./pubspec.yaml \
    && cp ../apps/pandora-mobile/pubspec.lock ./pubspec.lock \
    && cp ../apps/pandora-mobile/analysis_options.yaml ./analysis_options.yaml \
    && python3 ../apps/pandora-mobile/tool/configure_validation_android.py android/app/src/main/AndroidManifest.xml

RUN cd .pandora-mobile-build \
    && cp pubspec.lock pubspec.lock.expected \
    && flutter pub get --enforce-lockfile \
    && cmp pubspec.lock.expected pubspec.lock

RUN mkdir -p vercel-apk-output \
    && cd .pandora-mobile-build \
    && flutter analyze 2>&1 | tee ../vercel-apk-output/flutter-analyze.log

RUN cd .pandora-mobile-build \
    && flutter test --reporter expanded 2>&1 | tee ../vercel-apk-output/flutter-test.log

RUN cd .pandora-mobile-build \
    && test "$(awk '/^version:/{print $2; exit}' pubspec.yaml)" = "$EXPECTED_APP_VERSION" \
    && flutter build apk --debug \
      --dart-define=PANDORA_SOURCE_REVISION="$SOURCE_SHA" \
      --dart-define=PANDORA_APP_VERSION="$EXPECTED_APP_VERSION" \
      2>&1 | tee ../vercel-apk-output/flutter-build.log

RUN cp .pandora-mobile-build/build/app/outputs/flutter-apk/app-debug.apk vercel-apk-output/pandora-debug.apk \
    && APK_SHA="$(sha256sum vercel-apk-output/pandora-debug.apk | awk '{print $1}')" \
    && APK_SIZE="$(stat -c '%s' vercel-apk-output/pandora-debug.apk)" \
    && { \
      echo "source_sha=$SOURCE_SHA"; \
      echo "source_tree=$SOURCE_TREE"; \
      echo "source_apps_tree=$SOURCE_APPS_TREE"; \
      echo "flutter_version=$FLUTTER_VERSION"; \
      echo "java_version=17.0.20+8"; \
      echo "android_platform=android-36"; \
      echo "android_build_tools=36.0.0"; \
      echo "app_version=$EXPECTED_APP_VERSION"; \
      echo "android_package=com.banataosystems.pandora_mobile"; \
      echo "artifact_class=validation-candidate"; \
      echo "production_release=false"; \
      echo "physical_device_verified=false"; \
      echo "apk_sha256=$APK_SHA"; \
      echo "apk_size_bytes=$APK_SIZE"; \
    } > vercel-apk-output/pandora-mobile-artifact-manifest.txt \
    && printf '<!doctype html><meta charset="utf-8"><title>Pandora Android validation</title><h1>Pandora Android validation</h1><p>Exact mobile source: %s</p><p>APK SHA-256: %s</p><ul><li><a href="/pandora-debug.apk">APK</a></li><li><a href="/pandora-mobile-artifact-manifest.txt">Manifest</a></li><li><a href="/flutter-analyze.log">Analyze log</a></li><li><a href="/flutter-test.log">Test log</a></li><li><a href="/flutter-build.log">Build log</a></li></ul>' "$SOURCE_SHA" "$APK_SHA" > vercel-apk-output/index.html

FROM alpine:3.22 AS runtime
COPY --from=builder /src/vercel-apk-output /www
EXPOSE 3000
CMD ["httpd","-f","-p","3000","-h","/www"]
