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

# kokoro-onnx 0.5.x requires Python >=3.10,<3.14 (Ubuntu 26.04 default may be 3.14+)
_python_ok() {
  local py="$1"
  "$py" -c 'import sys; v=sys.version_info; raise SystemExit(0 if (3,10) <= (v.major,v.minor) < (3,14) else 1)' 2>/dev/null
}

find_python() {
  local py
  for py in python3.13 python3.12 python3.11 python3; do
    if command -v "$py" &>/dev/null && _python_ok "$py"; then
      echo "$py"
      return 0
    fi
  done
  return 1
}

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

log "System packages (Python, espeak-ng for Kokoro G2P, ALSA)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  python3 python3-venv python3-pip \
  espeak-ng alsa-utils \
  libportaudio2 libsndfile1 \
  >/dev/null

log "Install → ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

if [[ -d "${REPO_ROOT}/services/kokoro-tts" ]]; then
  # Trailing /. copies dotfiles (.env.example); glob * skips them.
  cp -a "${REPO_ROOT}/services/kokoro-tts/." "$INSTALL_DIR/"
else
  TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/${GITHUB_REPO}/archive/refs/heads/main.tar.gz" -o "${TMP}/repo.tar.gz"
  tar xzf "${TMP}/repo.tar.gz" -C "$TMP"
  cp -a "${TMP}"/*/services/kokoro-tts/. "$INSTALL_DIR/"
  rm -rf "$TMP"
fi

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
  if [[ -f "${INSTALL_DIR}/.env.example" ]]; then
    cp "${INSTALL_DIR}/.env.example" "${INSTALL_DIR}/.env"
  else
    cat >"${INSTALL_DIR}/.env" <<'EOF'
TTS_HOST=127.0.0.1
TTS_PORT=5050
TTS_VOICE=pf_dora
TTS_LANG=pt-br
TTS_SPEED=1.0
AUDIO_DEVICE=default
EOF
  fi
  ok "Created ${INSTALL_DIR}/.env"
fi

# Detect analog jack (ALC269/PCH or rk3568 ES8388)
if command -v aplay &>/dev/null; then
  alsa_dev=""
  if aplay -l 2>/dev/null | grep -qE 'card [0-9]+:.*PCH|ALC269'; then
    alsa_dev="plughw:CARD=PCH,DEV=0"
  elif aplay -l 2>/dev/null | grep -qE 'card [0-9]+:.*ES8388|RK817|RK809'; then
    card="$(aplay -l 2>/dev/null | awk '/card [0-9]+:.*(ES8388|RK817|RK809)/{gsub(/:/,"",$2); print $2; exit}')"
    alsa_dev="plughw:${card},0"
  fi
  if [[ -n "$alsa_dev" ]]; then
    if grep -q '^AUDIO_DEVICE=' "${INSTALL_DIR}/.env" 2>/dev/null; then
      sed -i "s|^AUDIO_DEVICE=.*|AUDIO_DEVICE=${alsa_dev}|" "${INSTALL_DIR}/.env"
    else
      echo "AUDIO_DEVICE=${alsa_dev}" >> "${INSTALL_DIR}/.env"
    fi
    ok "ALSA device: ${alsa_dev}"
  fi
fi

log "Python venv + pip install (Kokoro ONNX model downloads on first speak)"
PYTHON="$(find_python || true)"
if [[ -z "${PYTHON}" ]]; then
  log "System Python >=3.14 detected — adding deadsnakes PPA for python3.12"
  apt-get install -y -qq software-properties-common
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -qq
  apt-get install -y -qq python3.12 python3.12-venv python3.12-dev \
    || die "python3.12 install failed — check distro or install via pyenv"
  PYTHON=python3.12
  _python_ok "$PYTHON" || die "python3.12 not usable after install"
fi
ok "Python: $("${PYTHON}" --version 2>&1 | awk '{print $1, $2}')"

rm -rf "${INSTALL_DIR}/venv"
"${PYTHON}" -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install -q --upgrade pip
"${INSTALL_DIR}/venv/bin/pip" install -q -r "${INSTALL_DIR}/requirements.txt"

chown -R "${KIOSK_USER}:${KIOSK_USER}" "$INSTALL_DIR"

log "Kokoro ONNX model files (~300MB total, skip if cached)"
MODEL_DIR="${INSTALL_DIR}/models"
mkdir -p "$MODEL_DIR"
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [[ ! -s "${MODEL_DIR}/${f}" ]]; then
    curl -fsSL --retry 3 --retry-delay 5 \
      "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/${f}" \
      -o "${MODEL_DIR}/${f}"
    ok "Downloaded ${f}"
  else
    ok "Cached ${f}"
  fi
done
chown -R "${KIOSK_USER}:${KIOSK_USER}" "$MODEL_DIR"

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
