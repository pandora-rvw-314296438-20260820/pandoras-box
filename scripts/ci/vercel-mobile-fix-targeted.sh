#!/usr/bin/env bash
set -euo pipefail
EXPECTED_APPS_TREE=823ba8c095b2cbdf034216e32e47705cc73d6b28
test "$(git rev-parse HEAD:apps)" = "$EXPECTED_APPS_TREE"
mkdir -p .vercel-tools vercel-apk-output
export HOME="$PWD/.vercel-home"
mkdir -p "$HOME"
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.0-stable.tar.xz" -o /tmp/flutter.tar.xz
tar -xJf /tmp/flutter.tar.xz -C .vercel-tools
export PATH="$PWD/.vercel-tools/flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/.vercel-tools/flutter"
flutter config --no-analytics >/dev/null
rm -rf .pandora-mobile-build
mkdir .pandora-mobile-build
cd .pandora-mobile-build
flutter create --platforms=web --org com.banataosystems --project-name pandora_mobile . >/dev/null
rm -rf lib test assets pubspec.yaml pubspec.lock analysis_options.yaml
cp -R ../apps/pandora-mobile/lib ./lib
cp -R ../apps/pandora-mobile/test ./test
cp -R ../apps/pandora-mobile/assets ./assets
cp ../apps/pandora-mobile/pubspec.yaml ./pubspec.yaml
cp ../apps/pandora-mobile/pubspec.lock ./pubspec.lock
cp ../apps/pandora-mobile/analysis_options.yaml ./analysis_options.yaml
flutter pub get --enforce-lockfile >/dev/null
flutter test test/app/pandora_chat_navigation_test.dart --reporter expanded 2>&1 | tee ../vercel-apk-output/navigation-test.log
flutter test test/goldens/owner_screens_visual_evidence_test.dart --name "obsidian_chat_shell" --reporter expanded 2>&1 | tee ../vercel-apk-output/workspace-responsive-test.log
cd ..
printf 'source_apps_tree=%s\nstatus=targeted-pass\n' "$EXPECTED_APPS_TREE" > vercel-apk-output/diagnostic.txt
printf '<a href="/navigation-test.log">navigation</a><br><a href="/workspace-responsive-test.log">responsive</a>' > vercel-apk-output/index.html
