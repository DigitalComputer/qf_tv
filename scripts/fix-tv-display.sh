#!/usr/bin/env bash
# Fix "cannot open display: :0" — start LightDM/X, then qf_tv.
# Run on TV box: sudo bash scripts/fix-tv-display.sh

set -euo pipefail

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
KIOSK_HOME="$(eval echo "~$KIOSK_USER")"
OPENBOX_AUTOSTART="${KIOSK_HOME}/.config/openbox/autostart"

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

log "Stop qf-tv restart loop"
systemctl stop qf-tv 2>/dev/null || true

log "Ensure GUI stack"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xorg openbox lightdm unclutter dbus-x11 >/dev/null 2>&1 || true

systemctl set-default graphical.target
systemctl enable lightdm
systemctl start lightdm

log "Wait for display :0 (up to 90s — connect HDMI/monitor)"
ready=0
for _ in $(seq 1 90); do
  if [[ -S /tmp/.X11-unix/X0 ]] && sudo -u "$KIOSK_USER" DISPLAY=:0 xdpyinfo >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  echo "X still not up. Check: systemctl status lightdm" >&2
  echo "  journalctl -u lightdm -n 40" >&2
  echo "  Plug HDMI monitor, then: sudo reboot" >&2
  exit 1
fi
ok "Display :0 ready"

log "Ensure openbox starts qf_tv (kiosk session)"
mkdir -p "$(dirname "$OPENBOX_AUTOSTART")"
touch "$OPENBOX_AUTOSTART"
if ! grep -q 'qf_tv' "$OPENBOX_AUTOSTART" 2>/dev/null; then
  cat >> "$OPENBOX_AUTOSTART" <<EOF

# QueueFlow TV (started after X is up)
while true; do
  ${INSTALL_DIR}/qf_tv
  sleep 3
done &
EOF
fi
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config"
chmod +x "$OPENBOX_AUTOSTART"
ok "openbox autostart updated"

log "Disable systemd qf-tv (openbox owns the app — avoids :0 race)"
systemctl disable qf-tv 2>/dev/null || true
systemctl stop qf-tv 2>/dev/null || true

log "Restart graphical session"
systemctl restart lightdm
sleep 5

if pgrep -u "$KIOSK_USER" -f qf_tv >/dev/null; then
  ok "qf_tv running on display :0"
else
  echo "lightdm up but qf_tv not seen yet — wait 10s or: journalctl -u lightdm -n 30" >&2
  exit 1
fi
