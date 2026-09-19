
#!/usr/bin/env bash
set -euo pipefail

BASE="https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-m3-004-vault-file-writer-20260914"
NONCE="handoff-100430e9-q7N4m2"
WORK=".pandora-apk-handoff"
OUT="vercel-apk-handoff-output"
APK="$WORK/pandora-mobile-0.4.0-rc.4+11-100430e9.apk"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

for i in 0 1 2 3 4 5 6 7; do
  printf -v n "%03d" "$i"
  curl --fail --location --retry 3 --retry-all-errors     "$BASE?action=chunk&idx=$i"     -o "$WORK/part-$n"
done

printf '%s  %s
' "e3cc18d29dfa486a76de7de9c768a37757158d7d5a04e969b7a361b783b0a211" "$WORK/part-000" | sha256sum -c -
printf '%s  %s
' "5334923984e86cb453aa8f76dc98de288ec1c625b5c5eaf672025a38ec1ed3e8" "$WORK/part-001" | sha256sum -c -
printf '%s  %s
' "fe66c7a1be92d1db8fe691c91c551183184dc135194d2d82c24aa6f4b1c53e6a" "$WORK/part-002" | sha256sum -c -
printf '%s  %s
' "f7c262297a12eeac999b3394bf8f6b96a1c32cc6e1856f77f315e1299ce03af3" "$WORK/part-003" | sha256sum -c -
printf '%s  %s
' "5c27c789d6b4a2bf9962d5bdd895296caf0803183dc29fa0507f39c9fc0a1dbb" "$WORK/part-004" | sha256sum -c -
printf '%s  %s
' "4a1af749bf7a8bc5e272082606c70cd9918f3f25b4d83cd2c9a3354992320966" "$WORK/part-005" | sha256sum -c -
printf '%s  %s
' "3ea96cc73764fcfa54cab28d37be226451c668c3995d2a2bc9bad62e104ddbc0" "$WORK/part-006" | sha256sum -c -
printf '%s  %s
' "9728c16be79d668e65f7e6fa13ff1f568621f28ca3e03fe2d9e88bbd7ad840de" "$WORK/part-007" | sha256sum -c -

cat "$WORK"/part-* > "$APK"

SIZE="$(stat -c%s "$APK")"
test "$SIZE" = "180466940"
printf '%s  %s
' "35821b65f94f494764091bd74eb3b98e09786bae1573c7883354a0157cc0ee36" "$APK" | sha256sum -c -

UPLOAD_JSON="$(curl --fail --location "$BASE?action=upload-url&key=$NONCE")"
SIGNED_URL="$(printf '%s' "$UPLOAD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["signedUrl"])')"

curl --fail --location --request PUT   --header "Content-Type: application/vnd.android.package-archive"   --header "Cache-Control: max-age=3600"   --header "x-upsert: true"   --data-binary @"$APK"   "$SIGNED_URL"

cat > "$OUT/index.json" <<EOF
{
  "ok": true,
  "canonical_source_sha": "100430e90bb5740ca14cfce8ef035be0baf17d07",
  "app_version": "0.4.0-rc.4+11",
  "android_package": "com.banataosystems.pandora_mobile",
  "apk_sha256": "35821b65f94f494764091bd74eb3b98e09786bae1573c7883354a0157cc0ee36",
  "apk_size_bytes": 180466940,
  "storage_object": "android/100430e90bb5740ca14cfce8ef035be0baf17d07/pandora-mobile-0.4.0-rc.4+11-35821b65.apk"
}
EOF
