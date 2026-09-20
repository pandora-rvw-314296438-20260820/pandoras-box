#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_CODESPACE="pandora-apk-phone-local-9b682e35-pgv447759jc96xg"
REMOTE_APK="/workspaces/pandoras-box/.pandora-codespace-artifact/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
SERVE_DIR="/tmp/pandora-public-apk"
OUT="$SERVE_DIR/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
STATUS_DIR=".pandora-public-handoff"
mkdir -p "$SERVE_DIR" "$STATUS_DIR"
gh codespace cp -e -c "$SOURCE_CODESPACE" "remote:$REMOTE_APK" "$OUT"
ACTUAL_SHA="$(sha256sum "$OUT" | awk '{print $1}')"
ACTUAL_SIZE="$(stat -c '%s' "$OUT")"
test "$ACTUAL_SHA" = "db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f"
test "$ACTUAL_SIZE" = "119940817"
cat > "$STATUS_DIR/status.json" <<EOF
{"outcome":"passed","sourceSha":"9b682e3593afc2c0f53630d6ec95454d886afbe9","apkSha256":"$ACTUAL_SHA","apkSizeBytes":$ACTUAL_SIZE,"port":8080}
EOF
git config user.name "Pandora Public APK Handoff"
git config user.email "pandora-apk-handoff@users.noreply.github.com"
git add -f "$STATUS_DIR"
git commit -m "build(android): record public APK handoff 9b682e35" || true
git push --force origin HEAD:refs/heads/build/phone-local-ai-public-handoff-9b682e35-20260920
nohup python3 -m http.server 8080 --bind 0.0.0.0 --directory "$SERVE_DIR" >/tmp/pandora-apk-http.log 2>&1 &
sleep 2
gh codespace ports visibility 8080:public -c "$CODESPACE_NAME"
