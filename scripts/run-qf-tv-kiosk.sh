#!/usr/bin/env bash
# Launcher for openbox autostart — software GL + read api_host from config.
# Installed to /opt/qf-tv/run-qf-tv.sh by setup-tv-box.sh / fix-tv-display.sh

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GDK_SYNCHRONIZE="${GDK_SYNCHRONIZE:-0}"

exec "${INSTALL_DIR}/qf_tv" "$@"
