#!/usr/bin/env bash
# Flutter Linux embedder runtime (libGLESv2.so.2, EGL). Ubuntu 22.04 + 24.04 names.
# Run on TV box: sudo bash scripts/install-flutter-runtime.sh

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

install_pkgs() {
  apt-get install -y -qq "$@" >/dev/null
}

# Ubuntu 24.04+ (t64) and 22.04 package names
if ! install_pkgs \
  libgtk-3-0 libblkid1 liblzma5 libstdc++6 libglu1-mesa \
  libgl1 libegl1 libgles2 libgl1-mesa-dri 2>/dev/null; then
  install_pkgs \
    libgtk-3-0t64 libblkid1 liblzma5 libstdc++6 libglu1-mesa \
    libgl1t64 libegl1t64 libgles2t64 libgl1-mesa-dri || true
fi

# Older Ubuntu / Debian
install_pkgs libgles2-mesa libegl1-mesa libgl1-mesa-glx 2>/dev/null || true

if ! ldconfig -p 2>/dev/null | grep -q libGLESv2; then
  echo "libGLESv2 still missing. Search:" >&2
  apt-cache search libGLESv2 2>/dev/null | head -5 >&2 || true
  exit 1
fi

echo "✓ libGLESv2: $(ldconfig -p | grep libGLESv2 | head -1)"
