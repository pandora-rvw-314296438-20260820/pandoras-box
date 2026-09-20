#!/usr/bin/env bash
set -Eeuo pipefail
SRC_CS="pandora-apk-phone-local-9b682e35-pgv447759jc96xg"
REMOTE="/workspaces/pandoras-box/.pandora-codespace-artifact/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
WORK="/tmp/apk-inspect"
APK="$WORK/pandora-phone-local-9b682e3593afc2c0f53630d6ec95454d886afbe9.apk"
OUT=".pandora-apk-inspect"
mkdir -p "$WORK" "$OUT"
gh codespace cp -e -c "$SRC_CS" "remote:$REMOTE" "$APK"
ACTUAL="$(sha256sum "$APK" | awk '{print $1}')"
test "$ACTUAL" = "db895ee8f3d9f0954e520a5bf03c76dab00bc36d9b2bfbe7b716df159d03ba6f"
unzip -l "$APK" > "$OUT/unzip-list.txt"
unzip -l "$APK" | grep 'lib/arm64-v8a/' > "$OUT/arm64-libs.txt" || true
rm -rf "$WORK/extract"
mkdir -p "$WORK/extract"
unzip -q "$APK" 'lib/arm64-v8a/*' -d "$WORK/extract"
find "$WORK/extract/lib/arm64-v8a" -maxdepth 1 -type f -print | sort > "$OUT/lib-files.txt"
for f in "$WORK"/extract/lib/arm64-v8a/*.so; do
  echo "===== $(basename "$f") =====" >> "$OUT/readelf-needed.txt"
  readelf -d "$f" 2>/dev/null | grep -E 'NEEDED|SONAME' >> "$OUT/readelf-needed.txt" || true
  echo >> "$OUT/readelf-needed.txt"
done
python3 - "$OUT/status.json" "$ACTUAL" <<'PY'
import json,sys,glob,os
libs=sorted(os.path.basename(p) for p in glob.glob('/tmp/apk-inspect/extract/lib/arm64-v8a/*.so'))
json.dump({
 "outcome":"passed",
 "apkSha256":sys.argv[2],
 "libraries":libs,
 "hasAiChat":"libai-chat.so" in libs,
 "cpuBackendLibraries":[x for x in libs if "ggml" in x.lower() or "cpu" in x.lower() or "kleid" in x.lower()]
},open(sys.argv[1],"w"),indent=2)
PY
git config user.name "Pandora APK Inspector"
git config user.email "pandora-apk-inspector@users.noreply.github.com"
git add -f "$OUT"
git commit -m "build(android): inspect packaged native backends 9b682e35"
git push --force origin HEAD:refs/heads/build/phone-local-ai-apk-inspect-9b682e35-20260920
