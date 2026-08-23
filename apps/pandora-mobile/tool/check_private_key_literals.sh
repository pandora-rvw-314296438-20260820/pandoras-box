#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo 'Provide at least one mobile source path to scan.' >&2
  exit 2
fi

for target in "$@"; do
  if [[ ! -e "$target" ]]; then
    echo "Private-key scan target does not exist: $target" >&2
    exit 2
  fi
done

scan_temp_root="${RUNNER_TEMP:-${TMPDIR:-.}}"
scan_output="$(mktemp "${scan_temp_root%/}/pandora-mobile-private-key-scan.XXXXXX")"
trap 'rm -f "$scan_output"' EXIT
private_key_prefix='-----BEGIN '
private_key_suffix='PRIVATE KEY-----'
private_key_patterns=()
for key_label in '' 'RSA ' 'EC ' 'OPENSSH '; do
  private_key_patterns+=(-e "${private_key_prefix}${key_label}${private_key_suffix}")
done

set +e
LC_ALL=C grep -RIl \
  --binary-files=without-match \
  --exclude='*.md' \
  --exclude='*.patch' \
  --exclude='*.png' \
  --exclude-dir='.git' \
  "${private_key_patterns[@]}" \
  -- "$@" > "$scan_output"
scan_status=$?
set -e

if [[ "$scan_status" -gt 1 ]]; then
  echo 'Private-key marker scan failed before it could produce a verdict.' >&2
  exit "$scan_status"
fi

if [[ -s "$scan_output" ]]; then
  echo 'Private-key marker found in Pandora Mobile operational source:' >&2
  sed 's/^/  /' "$scan_output" >&2
  exit 1
fi

echo 'Pandora Mobile private-key marker scan passed.'
