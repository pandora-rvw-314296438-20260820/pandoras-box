
#!/usr/bin/env bash
set -u
run_builder() {
  for _ in $(seq 1 180); do
    if [ -f /workspaces/pandoras-box/.devcontainer/build-apk.sh ]; then
      break
    fi
    sleep 2
  done
  if [ ! -f /workspaces/pandoras-box/.devcontainer/build-apk.sh ]; then
    echo "Pandora APK builder source did not mount in time." >/tmp/pandora-apk-builder.error
    return 1
  fi
  git config --global --add safe.directory /workspaces/pandoras-box || true
  cd /workspaces/pandoras-box || return 1
  bash .devcontainer/build-apk.sh >/tmp/pandora-apk-builder.log 2>&1
}
run_builder &
exec sleep infinity
