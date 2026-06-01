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
  xorg openbox lightdm unclutter \
  dbus-x11 \
  libgtk-3-0 libblkid1 liblzma5 libstdc++6 libglu1-mesa \
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
cat > "${KIOSK_HOME}/.config/openbox/autostart" <<'EOF'
# Disable screen blanking / DPMS
xset s off
xset -dpms
xset s noblank
# Hide mouse cursor
unclutter -idle 0 -root &
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
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=QueueFlow TV Display (qf_tv)
After=network-online.target graphical.target lightdm.service
Wants=network-online.target

[Service]
Type=simple
User=${KIOSK_USER}
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/${KIOSK_UID}
Environment=XAUTHORITY=${KIOSK_HOME}/.Xauthority

WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/qf_tv

Restart=always
RestartSec=3
StartLimitIntervalSec=0

StandardOutput=journal
StandardError=journal
SyslogIdentifier=qf-tv

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null
systemctl restart "${SERVICE_NAME}" 2>/dev/null || systemctl start "${SERVICE_NAME}" 2>/dev/null || true
ok "Service ${SERVICE_NAME} enabled"

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
