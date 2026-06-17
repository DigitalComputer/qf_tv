#!/usr/bin/env bash
# Download latest (or pinned) GitHub release into /opt/qf-tv and restart GUI.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh \
#     -o /tmp/qf-tv-update.sh
#   sudo env QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
#        QF_TV_VERSION=v1.0.5 \
#        bash /tmp/qf-tv-update.sh

set -euo pipefail

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
CONFIG_DIR="/etc/qf-tv"
CONFIG_FILE="${CONFIG_DIR}/config.json"
GITHUB_REPO="${GITHUB_REPO:-DigitalComputer/qf_tv}"
QF_TV_VERSION="${QF_TV_VERSION:-latest}"
QF_API_HOST="${QF_API_HOST:-}"
QF_API_IP="${QF_API_IP:-}"
QF_API_PORT="${QF_API_PORT:-8000}"

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  die "Need root. Run:
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
  sudo env QF_API_HOST=${QF_API_HOST:-http://YOUR-TENANT.queueflow.ao:8000} QF_TV_VERSION=${QF_TV_VERSION:-latest} bash /tmp/qf-tv-update.sh"
fi

ensure_api_port() {
  local h="${1%/}"
  if [[ "$h" =~ ^https?://[^:/]+$ ]]; then
    h="${h}:${QF_API_PORT}"
  fi
  printf '%s' "$h"
}

write_config() {
  local host="$1"
  local central=""
  mkdir -p "$CONFIG_DIR"
  if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
    central="$(jq -r '.central_host // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  fi
  if [[ "$host" == https://* ]]; then
    if [[ -n "$central" ]]; then
      jq -n --arg api "$host" --arg central "$central" \
        '{api_host:$api, central_host:$central, allow_insecure_ssl:true}' > "$CONFIG_FILE"
    else
      printf '%s\n' "{\"api_host\":\"${host}\",\"allow_insecure_ssl\":true}" > "$CONFIG_FILE"
    fi
  elif [[ -n "$central" ]]; then
    jq -n --arg api "$host" --arg central "$central" \
      '{api_host:$api, central_host:$central}' > "$CONFIG_FILE"
  else
    printf '%s\n' "{\"api_host\":\"${host}\"}" > "$CONFIG_FILE"
  fi
  chmod 644 "$CONFIG_FILE"
}

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
[[ -f "${INSTALL_DIR}/qf_tv" ]] || die "qf_tv binary missing in release tarball"
chmod +x "${INSTALL_DIR}/qf_tv"

log "Install launcher"
LAUNCHER="${INSTALL_DIR}/run-qf-tv.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/run-qf-tv-kiosk.sh" ]]; then
  install -m 755 "${SCRIPT_DIR}/run-qf-tv-kiosk.sh" "$LAUNCHER"
else
  cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
exec "${INSTALL_DIR}/qf_tv" "$@"
EOF
  chmod 755 "$LAUNCHER"
fi

log "Disable legacy systemd qf-tv (openbox owns the app — avoids duplicate processes)"
if systemctl is-enabled qf-tv.service &>/dev/null; then
  systemctl disable --now qf-tv.service 2>/dev/null || true
fi
if [[ -f /etc/systemd/system/qf-tv.service ]] && grep -q 'ExecStart=.*qf_tv' /etc/systemd/system/qf-tv.service 2>/dev/null; then
  cp /etc/systemd/system/qf-tv.service "/etc/systemd/system/qf-tv.service.bak.$(date +%s)" 2>/dev/null || true
  cat > /etc/systemd/system/qf-tv.service <<'UNIT'
[Unit]
Description=QueueFlow TV (placeholder — openbox runs qf_tv)
After=lightdm.service
PartOf=lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=graphical.target
UNIT
  systemctl daemon-reload
  systemctl disable --now qf-tv.service 2>/dev/null || true
fi

log "TTS + audio + video (espeak-ng, GStreamer, WebKitGTK for YouTube/HLS)"
apt-get install -y -qq espeak-ng 2>/dev/null || apt-get install -y -qq espeak 2>/dev/null || true
apt-get install -y -qq \
  alsa-utils pulseaudio pulseaudio-utils mpg123 \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-plugins-ugly \
  libwebkit2gtk-4.1-0 libsoup-3.0-0 \
  2>/dev/null || true

if [[ -n "$QF_API_HOST" ]]; then
  host="$(ensure_api_port "${QF_API_HOST%/}")"
  log "Config api_host=${host}"
  write_config "$host"
  QF_API_HOST="$host"
fi

if [[ -n "$QF_API_HOST" ]]; then
  log "Auto DNS (/etc/hosts from domain)"
  TV_DNS="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/scripts/lib/tv-dns.sh" \
    -o "$TV_DNS"
  # shellcheck source=/dev/null
  source "$TV_DNS"
  rm -f "$TV_DNS"
  domain="$(url_hostname "$QF_API_HOST")"
  if host_resolves "$domain"; then
    ok "DNS OK — ${domain} already resolves"
  elif tv_ensure_hosts_for_domains "$domain"; then
    ok "DNS mapped ${domain}"
  else
    warn "DNS skip — ${domain} unreachable; fix /etc/hosts or set QF_API_IP"
  fi
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
