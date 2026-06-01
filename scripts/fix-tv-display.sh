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
apt-get install -y -qq \
  xorg xserver-xorg-video-all \
  openbox lightdm unclutter dbus-x11 x11-xserver-utils \
  >/dev/null 2>&1 || true

# Force LightDM as display manager (not GDM)
if [[ -x /usr/sbin/lightdm ]]; then
  echo '/usr/sbin/lightdm' >/etc/X11/default-display-manager
fi
systemctl disable gdm3 gdm 2>/dev/null || true
systemctl set-default graphical.target
systemctl enable lightdm
systemctl start lightdm || true
systemctl isolate graphical.target 2>/dev/null || true

log "Wait for display :0 (up to 90s — VGA/HDMI monitor connected)"
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
  cat >> "$OPENBOX_AUTOSTART" <<'AUTOSTART_TAIL'

# Enable all connected outputs (VGA, HDMI, DP, etc.)
xrandr --auto 2>/dev/null || true
# Prefer external monitor (HDMI/DP/VGA) over built-in eDP (mini PC internal panel)
external=""
for out in $(xrandr 2>/dev/null | awk '/ connected/{print $1}'); do
  case "$out" in
    eDP*|LVDS*) xrandr --output "$out" --auto 2>/dev/null || true ;;
    *)
      external="$out"
      xrandr --output "$out" --primary --auto 2>/dev/null || true
      ;;
  esac
done
# Cable plugged after boot: try common outputs even if "disconnected"
if [[ -z "$external" ]]; then
  for out in HDMI-1 HDMI-2 DP-1 DP-2 VGA-1 VGA1; do
    if xrandr 2>/dev/null | grep -qE "^${out} "; then
      if xrandr --output "$out" --primary --auto 2>/dev/null; then
        external="$out"
        break
      fi
    fi
  done
fi
if [[ -n "$external" ]]; then
  for out in $(xrandr 2>/dev/null | awk '/ connected/{print $1}'); do
    case "$out" in eDP*|LVDS*) xrandr --output "$out" --off 2>/dev/null || true ;; esac
  done
fi

# QueueFlow TV (started after X is up)
while true; do
  /opt/qf-tv/qf_tv
  sleep 3
done &
AUTOSTART_TAIL
fi
# Rewrite full autostart if missing xrandr (older installs)
if ! grep -q 'xrandr' "$OPENBOX_AUTOSTART" 2>/dev/null; then
  sed -i '/^while true; do/,/^done &$/d' "$OPENBOX_AUTOSTART" 2>/dev/null || true
  cat >> "$OPENBOX_AUTOSTART" <<'AUTOSTART_TAIL'

xrandr --auto 2>/dev/null || true
# Prefer external monitor (HDMI/DP/VGA) over built-in eDP (mini PC internal panel)
external=""
for out in $(xrandr 2>/dev/null | awk '/ connected/{print $1}'); do
  case "$out" in
    eDP*|LVDS*) xrandr --output "$out" --auto 2>/dev/null || true ;;
    *)
      external="$out"
      xrandr --output "$out" --primary --auto 2>/dev/null || true
      ;;
  esac
done
# Cable plugged after boot: try common outputs even if "disconnected"
if [[ -z "$external" ]]; then
  for out in HDMI-1 HDMI-2 DP-1 DP-2 VGA-1 VGA1; do
    if xrandr 2>/dev/null | grep -qE "^${out} "; then
      if xrandr --output "$out" --primary --auto 2>/dev/null; then
        external="$out"
        break
      fi
    fi
  done
fi
if [[ -n "$external" ]]; then
  for out in $(xrandr 2>/dev/null | awk '/ connected/{print $1}'); do
    case "$out" in eDP*|LVDS*) xrandr --output "$out" --off 2>/dev/null || true ;; esac
  done
fi
while true; do
  /opt/qf-tv/qf_tv
  sleep 3
done &
AUTOSTART_TAIL
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
