#!/usr/bin/env bash
# Download latest (or pinned) GitHub release into /opt/qf-tv and restart GUI.
#
# Usage:
#   sudo QF_API_IP=192.168.30.168 \
#        QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
#        QF_TV_VERSION=v1.0.1 \
#        bash -c "$(curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh)"

set -euo pipefail

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
CONFIG_DIR="/etc/qf-tv"
CONFIG_FILE="${CONFIG_DIR}/config.json"
GITHUB_REPO="${GITHUB_REPO:-DigitalComputer/qf_tv}"
QF_TV_VERSION="${QF_TV_VERSION:-latest}"
QF_API_HOST="${QF_API_HOST:-}"
QF_API_IP="${QF_API_IP:-}"

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"

if [[ "$QF_TV_VERSION" == "latest" ]]; then
  QF_TV_VERSION="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | jq -r '.tag_name')"
fi
[[ -n "$QF_TV_VERSION" && "$QF_TV_VERSION" != "null" ]] || die "No GitHub release found"

ASSET="qf_tv-linux-x64.tar.gz"
URL="https://github.com/${GITHUB_REPO}/releases/download/${QF_TV_VERSION}/${ASSET}"

log "Download ${QF_TV_VERSION}"
TMP="$(mktemp)"
curl -fsSL "$URL" -o "$TMP"

log "Install → ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
rm -rf "${INSTALL_DIR:?}"/*
tar xzf "$TMP" -C "$INSTALL_DIR"
rm -f "$TMP"
chmod +x "${INSTALL_DIR}/qf_tv"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m 755 "${SCRIPT_DIR}/run-qf-tv-kiosk.sh" "${INSTALL_DIR}/run-qf-tv.sh"

if [[ -n "$QF_API_HOST" ]]; then
  host="${QF_API_HOST%/}"
  if [[ -n "$QF_API_IP" && "$host" == https://* ]]; then
    printf '%s\n' "{\"api_host\":\"${host}\",\"allow_insecure_ssl\":true}" > "$CONFIG_FILE"
  else
    printf '%s\n' "{\"api_host\":\"${host}\"}" > "$CONFIG_FILE"
  fi
  chmod 644 "$CONFIG_FILE"
fi

if [[ -n "$QF_API_IP" && -n "$QF_API_HOST" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/scripts/setup-tv-dns.sh" \
    | QF_API_IP="$QF_API_IP" QF_API_HOST="$QF_API_HOST" bash
fi

KIOSK_HOME="$(eval echo "~$KIOSK_USER")"
AUTOSTART="${KIOSK_HOME}/.config/openbox/autostart"
if [[ -f "$AUTOSTART" ]]; then
  sed -i 's|/opt/qf-tv/qf_tv|/opt/qf-tv/run-qf-tv.sh|g' "$AUTOSTART"
fi
chown -R "${KIOSK_USER}:${KIOSK_USER}" "$INSTALL_DIR" "$CONFIG_DIR" 2>/dev/null || true

rm -rf "${KIOSK_HOME}/.local/share/com.example.qf_tv" 2>/dev/null || true

systemctl restart lightdm 2>/dev/null || true
ok "Installed ${QF_TV_VERSION} — config: $(cat "$CONFIG_FILE" 2>/dev/null || echo n/a)"
