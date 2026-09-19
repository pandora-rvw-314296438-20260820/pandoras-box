#!/usr/bin/env bash
set -u

run_builder() {
  for _ in $(seq 1 180); do
    if [ -f /workspaces/pandoras-box/.devcontainer/build-picker-apk.sh ]; then
      break
    fi
    sleep 2
  done

  if [ ! -f /workspaces/pandoras-box/.devcontainer/build-picker-apk.sh ]; then
    echo "Pandora builder source did not mount in time." >/tmp/pandora-container-builder.error
    return 1
  fi

  git config --global --add safe.directory /workspaces/pandoras-box || true

  su -s /bin/bash codespace -c '
    cd /workspaces/pandoras-box || exit 1
    bash .devcontainer/build-picker-apk.sh
  ' >/tmp/pandora-container-builder.log 2>&1
}

run_builder &
exec sleep infinity
