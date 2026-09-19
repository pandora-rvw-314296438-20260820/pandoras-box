
#!/usr/bin/env bash
set -euo pipefail

SOURCE_SHA=931c5775f0b4f439e769251c743157cb836f4671
EXPECTED_APPS_TREE=f3779eaa9b2965a20203cad33a7e2424b0e595d6
SCREEN_BLOB=3fe9c5fb2b1454d0ffda80209c74ff7e023051d6
TEST_BLOB=90dfb7234588e4714c4c5cf0e9fc92ef2e222e56
LOCK_BLOB=a20956199e8271a0c676293252b7a87424afc086
FLUTTER_VERSION=3.47.0
ROOT="$(git rev-parse --show-toplevel)"
OUT="$PWD/proof"

test "$(git -C "$ROOT" rev-parse HEAD:apps)" = "$EXPECTED_APPS_TREE"
test "$(git -C "$ROOT" rev-parse HEAD:apps/pandora-mobile/lib/features/operations/operations_room_screen.dart)" = "$SCREEN_BLOB"
test "$(git -C "$ROOT" rev-parse HEAD:apps/pandora-mobile/test/features/operations/operations_room_test.dart)" = "$TEST_BLOB"
test "$(git -C "$ROOT" rev-parse HEAD:apps/pandora-mobile/pubspec.lock)" = "$LOCK_BLOB"

mkdir -p .vercel-tools "$OUT"
export HOME="$PWD/.vercel-home"
mkdir -p "$HOME"

curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.0-stable.tar.xz" -o /tmp/flutter.tar.xz
tar -xJf /tmp/flutter.tar.xz -C .vercel-tools
export PATH="$PWD/.vercel-tools/flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/.vercel-tools/flutter"
flutter config --no-analytics >/dev/null
flutter --version > "$OUT/flutter-version.log" 2>&1
cat "$OUT/flutter-version.log"

cd "$ROOT/apps/pandora-mobile"
cp pubspec.lock /tmp/pubspec.lock.expected
flutter pub get --enforce-lockfile > "$OUT/pub-get.log" 2>&1
cat "$OUT/pub-get.log"
python3 - <<'PY'
from pathlib import Path
a=Path('/tmp/pubspec.lock.expected').read_bytes()
b=Path('pubspec.lock').read_bytes()
if a != b:
    raise SystemExit('pubspec.lock changed')
PY

set +e
flutter analyze   lib/features/operations/operations_room_screen.dart   test/features/operations/operations_room_test.dart   > "$OUT/flutter-analyze.log" 2>&1
ANALYZE_EXIT=$?
set -e
cat "$OUT/flutter-analyze.log"

python3 - "$ANALYZE_EXIT" "$OUT/flutter-analyze.log" <<'PY'
from pathlib import Path
import sys
code=int(sys.argv[1])
text=Path(sys.argv[2]).read_text(errors='replace')
if code not in (0,1):
    raise SystemExit(f'flutter analyze exited unexpectedly: {code}')
if 'error •' in text:
    raise SystemExit('flutter analyze reported an error-severity issue')
if code == 1 and 'issues found.' not in text:
    raise SystemExit('flutter analyze failed outside warning/lint policy')
PY

flutter test test/features/operations/operations_room_test.dart --reporter expanded   > "$OUT/flutter-test.log" 2>&1
cat "$OUT/flutter-test.log"

{
  echo "canonical_source_sha=$SOURCE_SHA"
  echo "apps_tree=$EXPECTED_APPS_TREE"
  echo "screen_blob=$SCREEN_BLOB"
  echo "test_blob=$TEST_BLOB"
  echo "lock_blob=$LOCK_BLOB"
  echo "verifier_commit_sha=$VERCEL_GIT_COMMIT_SHA"
  echo "flutter_version=$FLUTTER_VERSION"
  echo "analyze_exit=$ANALYZE_EXIT"
  echo "operations_room_test=pass"
  echo "verification_lane=vercel-dedicated-project"
} > "$OUT/manifest.txt"

cat > "$OUT/index.html" <<EOF
<!doctype html><meta charset="utf-8">
<title>Pandora exact-source verification</title>
<h1>PASS - Pandora exact-source verification</h1>
<p>Canonical source: $SOURCE_SHA</p>
<p>Apps tree: $EXPECTED_APPS_TREE</p>
<ul>
<li><a href="/manifest.txt">Manifest</a></li>
<li><a href="/flutter-version.log">Flutter version</a></li>
<li><a href="/pub-get.log">Dependency log</a></li>
<li><a href="/flutter-analyze.log">Analyze log</a></li>
<li><a href="/flutter-test.log">Operations Room tests</a></li>
</ul>
EOF
