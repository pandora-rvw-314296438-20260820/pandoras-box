#!/usr/bin/env bash
# Prints the Flutter web entrypoint for the Vercel web build.
#
# - PANDORA_WEB_TARGET wins when set (lib/main.dart or lib/main_plp.dart only).
# - The Vercel project "enterprise" (enterprise-omega-five.vercel.app) serves
#   the PLP Enterprise app, the same entrypoint as the PLP APK.
# - Every other project keeps the default Pandora app (lib/main.dart).
set -euo pipefail

PLP_ENTERPRISE_VERCEL_PROJECT_ID="prj_Aa4Dz7bWERhY88Iiav0m9oakeCXx"

target="${PANDORA_WEB_TARGET:-}"
if [[ -z "$target" && "${VERCEL_PROJECT_ID:-}" == "$PLP_ENTERPRISE_VERCEL_PROJECT_ID" ]]; then
  target="lib/main_plp.dart"
fi
target="${target:-lib/main.dart}"

case "$target" in
  lib/main.dart|lib/main_plp.dart) printf '%s\n' "$target" ;;
  *)
    echo "Unsupported PANDORA_WEB_TARGET: ${target}" >&2
    exit 1
    ;;
esac
