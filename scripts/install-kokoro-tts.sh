#!/usr/bin/env bash
# Install Kokoro TTS microservice on QueueFlow TV box (127.0.0.1:5050).
#
# Usage (on TV box as root):
#   curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-kokoro-tts.sh \
#     -o /tmp/install-kokoro-tts.sh
#   sudo bash /tmp/install-kokoro-tts.sh
#
# Or from repo checkout:
#   sudo ./scripts/install-kokoro-tts.sh

set -euo pipefail

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-kokoro-tts}"
SERVICE_NAME="queueflow-tts"
GITHUB_REPO="${GITHUB_REPO:-DigitalComputer/qf_tv}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

log "System packages (Python, espeak-ng for Kokoro G2P, ALSA)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  python3 python3-venv python3-pip \
  espeak-ng alsa-utils \
  libportaudio2 \
  >/dev/null

log "Install → ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

if [[ -d "${REPO_ROOT}/services/kokoro-tts" ]]; then
  cp -a "${REPO_ROOT}/services/kokoro-tts/"* "$INSTALL_DIR/"
else
  TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/${GITHUB_REPO}/archive/refs/heads/main.tar.gz" -o "${TMP}/repo.tar.gz"
  tar xzf "${TMP}/repo.tar.gz" -C "$TMP"
  cp -a "${TMP}"/*/services/kokoro-tts/* "$INSTALL_DIR/"
  rm -rf "$TMP"
fi

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
  cp "${INSTALL_DIR}/.env.example" "${INSTALL_DIR}/.env"
  ok "Created ${INSTALL_DIR}/.env from example"
fi

# Detect analog jack (ALC269/PCH or rk3568 ES8388)
if command -v aplay &>/dev/null; then
  card="$(aplay -l 2>/dev/null | awk -F'[ :]' \
    '/card [0-9]+:.*(ES8388|RK817|RK809|codec|Analog|PCH|ALC|Intel|HDA)/{print $2; exit}')"
  dev="$(aplay -l 2>/dev/null | awk -v c="$card" -F'[ :]' '$2==c && /device/{print $4; exit}')"
  if [[ -n "$card" && -n "$dev" ]]; then
    alsa_dev="plughw:${card},${dev}"
    if ! grep -q '^AUDIO_DEVICE=' "${INSTALL_DIR}/.env" 2>/dev/null; then
      echo "AUDIO_DEVICE=${alsa_dev}" >> "${INSTALL_DIR}/.env"
    fi
    ok "ALSA device: ${alsa_dev}"
  fi
fi

log "Python venv + pip install (Kokoro model downloads on first speak)"
python3 -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install -q --upgrade pip
"${INSTALL_DIR}/venv/bin/pip" install -q -r "${INSTALL_DIR}/requirements.txt"

chown -R "${KIOSK_USER}:${KIOSK_USER}" "$INSTALL_DIR"

log "systemd unit ${SERVICE_NAME}"
cp "${INSTALL_DIR}/queueflow-tts.service" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

sleep 2
if curl -fsS "http://127.0.0.1:5050/health" >/dev/null 2>&1; then
  ok "Kokoro TTS listening on http://127.0.0.1:5050"
else
  printf '\033[1;33m!\033[0m Service started but /health not ready — check: journalctl -u %s -f\n' "$SERVICE_NAME"
fi

echo ""
echo "  Test:  curl -X POST http://127.0.0.1:5050/speak -H 'Content-Type: application/json' -d '{\"text\":\"Atenção. Senha um dois três.\"}'"
echo "  Logs:  journalctl -u ${SERVICE_NAME} -f"
echo "  qf_tv: export KOKORO_TTS_URL=http://127.0.0.1:5050 (set in run-qf-tv.sh)"
