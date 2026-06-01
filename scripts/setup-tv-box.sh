#!/usr/bin/env bash
# QueueFlow qf_tv — one-shot Ubuntu TV box setup
#
# Fresh Ubuntu Server 22.04/24.04 (or Desktop) → kiosk user + GUI + app + systemd
#
# Automatic tenant (single instance):
#   curl -fsSL https://demo.queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash
#
# Automatic self-hosted (all instances from central registry):
#   curl -fsSL https://queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash
#
# Manual override:
#   curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/setup-tv-box.sh \
#     | sudo QF_API_HOST=https://demo.queueflow.ao bash
#
# Or local:
#   sudo QF_CENTRAL_HOST=https://queueflow.ao ./scripts/setup-tv-box.sh
#
# Optional env (override API defaults):
#   QF_API_IP        — LAN IP of API server → writes /etc/hosts (fix NXDOMAIN on TV LAN)
#   QF_CENTRAL_HOST  — central registry URL (self-hosted multi-instance)
#   QF_API_HOST      — single tenant API URL
#   QF_TV_VERSION    — release tag, e.g. v1.0.0 or "latest"
#   GITHUB_REPO      — default DigitalComputer/qf_tv
#   KIOSK_USER       — default kiosk
#   INSTALL_DIR      — default /opt/qf-tv
#
# Update box later: re-run same bootstrap or script with same QF_API_HOST.

set -euo pipefail

QF_API_HOST="${QF_API_HOST:-}"
QF_API_IP="${QF_API_IP:-}"
QF_CENTRAL_HOST="${QF_CENTRAL_HOST:-}"
QF_TV_VERSION="${QF_TV_VERSION:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
CONFIG_DIR="/etc/qf-tv"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_NAME="qf-tv"

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

url_hostname() {
  local raw="${1#*://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf '%s' "$raw"
}

configure_local_dns() {
  [[ -n "$QF_API_IP" ]] || return 0

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "${script_dir}/setup-tv-dns.sh" ]]; then
    log "Mapping QueueFlow domains → ${QF_API_IP} (/etc/hosts)"
    QF_API_HOST="$QF_API_HOST" QF_CENTRAL_HOST="$QF_CENTRAL_HOST" \
      bash "${script_dir}/setup-tv-dns.sh"
    ok "Local DNS configured"
    return 0
  fi

  local host=""
  if [[ -n "$QF_API_HOST" ]]; then
    host="$(url_hostname "$QF_API_HOST")"
  elif [[ -n "$QF_CENTRAL_HOST" ]]; then
    host="$(url_hostname "$QF_CENTRAL_HOST")"
  fi
  [[ -n "$host" ]] || die "Set QF_API_HOST or QF_CENTRAL_HOST with QF_API_IP"

  log "Mapping ${host} → ${QF_API_IP}"
  grep -q "queueflow-tv-dns" /etc/hosts 2>/dev/null && \
    sed -i '/queueflow-tv-dns/d' /etc/hosts || true
  echo "${QF_API_IP} ${host} queueflow.ao # queueflow-tv-dns" >> /etc/hosts
  ok "Local DNS configured"
}

# DNS before any curl to tenant domain
configure_local_dns

fetch_setup_config() {
  if [[ -n "$QF_CENTRAL_HOST" ]]; then
    local url="${QF_CENTRAL_HOST%/}/api/v1/tv/setup"
    local cfg
    cfg="$(curl -fsSL "$url" 2>/dev/null)" || {
      log "Could not fetch ${url} — using env defaults"
      return 0
    }
    if [[ -z "$QF_TV_VERSION" ]]; then
      QF_TV_VERSION="$(printf '%s' "$cfg" | jq -r '.data.qf_tv_version // empty')"
    fi
    if [[ -z "$GITHUB_REPO" ]]; then
      GITHUB_REPO="$(printf '%s' "$cfg" | jq -r '.data.github_repo // empty')"
    fi
    local central_from_api
    central_from_api="$(printf '%s' "$cfg" | jq -r '.data.central_host // empty')"
    if [[ -n "$central_from_api" ]]; then
      QF_CENTRAL_HOST="$central_from_api"
    fi
    return 0
  fi

  [[ -n "$QF_API_HOST" ]] || return 0

  local url="${QF_API_HOST%/}/api/v1/tv/setup"
  local cfg
  cfg="$(curl -fsSL "$url" 2>/dev/null)" || {
    log "Could not fetch ${url} — using env defaults"
    return 0
  }

  if [[ -z "$QF_TV_VERSION" ]]; then
    QF_TV_VERSION="$(printf '%s' "$cfg" | jq -r '.data.qf_tv_version // empty')"
  fi
  if [[ -z "$GITHUB_REPO" ]]; then
    GITHUB_REPO="$(printf '%s' "$cfg" | jq -r '.data.github_repo // empty')"
  fi
  local api_from_api
  api_from_api="$(printf '%s' "$cfg" | jq -r '.data.api_host // empty')"
  if [[ -n "$api_from_api" ]]; then
    QF_API_HOST="$api_from_api"
  fi
}

fetch_setup_config

QF_TV_VERSION="${QF_TV_VERSION:-latest}"
GITHUB_REPO="${GITHUB_REPO:-DigitalComputer/qf_tv}"

[[ -n "$QF_CENTRAL_HOST" || -n "$QF_API_HOST" ]] || die "Set QF_CENTRAL_HOST or QF_API_HOST, or run bootstrap: curl -fsSL https://queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash"

export DEBIAN_FRONTEND=noninteractive

# ── 1. Base packages ────────────────────────────────────────────────────────
log "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
  curl jq ca-certificates \
  xorg xserver-xorg-video-all x11-xserver-utils \
  openbox lightdm unclutter \
  dbus-x11 \
  libgtk-3-0 libblkid1 liblzma5 libstdc++6 libglu1-mesa \
  libgl1 libegl1 libgles2 libgl1-mesa-dri \
  fonts-dejavu-core \
  >/dev/null 2>&1 || apt-get install -y -qq \
  libgtk-3-0t64 libblkid1 liblzma5 libstdc++6 libglu1-mesa \
  libgl1t64 libegl1t64 libgles2t64 libgl1-mesa-dri \
  fonts-dejavu-core \
  >/dev/null

ok "Packages installed"

# ── 2. Kiosk user ───────────────────────────────────────────────────────────
if ! id "$KIOSK_USER" &>/dev/null; then
  log "Creating user $KIOSK_USER..."
  useradd -m -s /bin/bash "$KIOSK_USER"
  ok "User $KIOSK_USER created"
else
  ok "User $KIOSK_USER exists"
fi

KIOSK_UID="$(id -u "$KIOSK_USER")"
KIOSK_HOME="$(eval echo "~$KIOSK_USER")"

# ── 3. LightDM auto-login + openbox ─────────────────────────────────────────
log "Configuring auto-login..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-qf-tv-autologin.conf <<EOF
[Seat:*]
autologin-user=${KIOSK_USER}
autologin-user-timeout=0
user-session=openbox
greeter-hide-users=true
EOF

mkdir -p "${KIOSK_HOME}/.config/openbox"
cat > "${KIOSK_HOME}/.config/openbox/autostart" <<EOF
# Disable screen blanking / DPMS
xset s off
xset -dpms
xset s noblank
# Hide mouse cursor
unclutter -idle 0 -root &
# Prefer HDMI/DP/VGA over built-in eDP (mini PC panel)
xrandr --auto 2>/dev/null || true
external=""
for out in \$(xrandr 2>/dev/null | awk '/ connected/{print \$1}'); do
  case "\$out" in
    eDP*|LVDS*) xrandr --output "\$out" --auto 2>/dev/null || true ;;
    *) external="\$out"; xrandr --output "\$out" --primary --auto 2>/dev/null || true ;;
  esac
done
if [ -z "\$external" ]; then
  for out in HDMI-1 HDMI-2 DP-1 DP-2 VGA-1 VGA1; do
    if xrandr 2>/dev/null | grep -qE "^\${out} "; then
      if xrandr --output "\$out" --primary --auto 2>/dev/null; then external="\$out"; break; fi
    fi
  done
fi
if [ -n "\$external" ]; then
  for out in \$(xrandr 2>/dev/null | awk '/ connected/{print \$1}'); do
    case "\$out" in eDP*|LVDS*) xrandr --output "\$out" --off 2>/dev/null || true ;; esac
  done
fi
# QueueFlow TV — must run inside kiosk X session (not before LightDM :0 exists)
install -m 755 "$(dirname "$0")/run-qf-tv-kiosk.sh" "${INSTALL_DIR}/run-qf-tv.sh"

while true; do
  ${INSTALL_DIR}/run-qf-tv.sh
  sleep 3
done &
EOF
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config"

systemctl enable lightdm >/dev/null 2>&1 || true
systemctl set-default graphical.target >/dev/null 2>&1 || true
ok "Auto-login configured"

# ── 4. Download release from GitHub ─────────────────────────────────────────
resolve_version() {
  if [[ "$QF_TV_VERSION" == "latest" ]]; then
    curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
      | jq -r '.tag_name // empty'
  else
    echo "$QF_TV_VERSION"
  fi
}

TAG="$(resolve_version)"
[[ -n "$TAG" && "$TAG" != "null" ]] || die "Could not resolve release (check GITHUB_REPO / QF_TV_VERSION)"

ASSET_NAME="qf_tv-linux-x64.tar.gz"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ASSET_NAME}"

log "Downloading ${TAG} from GitHub..."
mkdir -p "$INSTALL_DIR"
TMP="$(mktemp)"
if ! curl -fsSL "$DOWNLOAD_URL" -o "$TMP"; then
  die "Download failed: ${DOWNLOAD_URL}\n  Publish a release first or set QF_TV_VERSION to an existing tag."
fi

rm -rf "${INSTALL_DIR:?}"/*
tar xzf "$TMP" -C "$INSTALL_DIR"
rm -f "$TMP"
chmod +x "${INSTALL_DIR}/qf_tv" 2>/dev/null || chmod +x "${INSTALL_DIR}/"* 2>/dev/null || true
chown -R "${KIOSK_USER}:${KIOSK_USER}" "$INSTALL_DIR"
ok "App installed to ${INSTALL_DIR} (${TAG})"

# ── 5. Config ───────────────────────────────────────────────────────────────
log "Writing ${CONFIG_FILE}..."
mkdir -p "$CONFIG_DIR"
if [[ -n "$QF_CENTRAL_HOST" ]]; then
  cat > "$CONFIG_FILE" <<EOF
{
  "central_host": "${QF_CENTRAL_HOST}",
  "release": "${TAG}",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
else
  cat > "$CONFIG_FILE" <<EOF
{
  "api_host": "${QF_API_HOST}",
  "release": "${TAG}",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
fi
chmod 644 "$CONFIG_FILE"
ok "Config written"

# ── 6. systemd ──────────────────────────────────────────────────────────────
log "Installing systemd unit..."
# Optional watchdog unit — app is started from openbox autostart once :0 exists.
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=QueueFlow TV Display (qf_tv) — openbox starts the app; this unit is optional
After=lightdm.service
PartOf=lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
ok "qf_tv will start via openbox after LightDM (not systemd before :0)"

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  QueueFlow TV box ready"
echo ""
if [[ -n "$QF_CENTRAL_HOST" ]]; then
  echo "  Central: ${QF_CENTRAL_HOST}"
  echo "  Screens: ${QF_CENTRAL_HOST}/api/v1/tv/screens"
else
  echo "  API:     ${QF_API_HOST}"
fi
echo "  Release: ${TAG}"
echo "  App:     ${INSTALL_DIR}"
echo "  Config:  ${CONFIG_FILE}"
echo ""
echo "  Status:  systemctl status ${SERVICE_NAME}"
echo "  Logs:    journalctl -u ${SERVICE_NAME} -f"
echo "  Unlock:  Ctrl+P then Alt+P → pick display again"
echo ""
echo "  BIOS tip: enable 'Power on after AC loss'"
echo "  Reboot:  reboot"
echo "════════════════════════════════════════════════════════"
