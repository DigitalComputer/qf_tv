#!/usr/bin/env bash
# Launcher for openbox autostart — software GL + analog audio + read api_host from config.
# Installed to /opt/qf-tv/run-qf-tv.sh by setup-tv-box.sh / install-qf-tv-update.sh

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GDK_SYNCHRONIZE="${GDK_SYNCHRONIZE:-0}"

configure_audio() {
  # PulseAudio/PipeWire — prefer 3.5mm analog over HDMI on rk3568 TV boxes.
  # Must run in kiosk graphical session (openbox autostart), not bare SSH.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

  if command -v pactl &>/dev/null; then
    if ! pactl info &>/dev/null 2>&1; then
      pulseaudio --start --daemonize 2>/dev/null || true
      sleep 1
    fi
    local sink=""
    sink="$(pactl list short sinks 2>/dev/null \
      | grep -iE 'analog|headphone|es8388|rk817|rk809|codec' \
      | head -1 | awk '{print $2}' || true)"
    if [[ -z "$sink" ]]; then
      sink="$(pactl list short sinks 2>/dev/null | grep -vi hdmi | head -1 | awk '{print $2}' || true)"
    fi
    if [[ -n "$sink" ]]; then
      pactl set-default-sink "$sink" 2>/dev/null || true
      export QF_PULSE_SINK="$sink"
    fi
  fi

  # ALSA fallback — first non-HDMI playback device
  if command -v aplay &>/dev/null; then
    local card dev
    card="$(aplay -l 2>/dev/null | awk -F'[ :]' '/card [0-9]+:.*(ES8388|RK817|codec|Analog)/{print $2; exit}')"
    dev="$(aplay -l 2>/dev/null | awk -v c="$card" -F'[ :]' '$2==c && /device/{print $4; exit}')"
    if [[ -n "$card" && -n "$dev" ]]; then
      export QF_ALSA_DEVICE="plughw:${card},${dev}"
      export QF_ESPEAK_DEVICE="${QF_ESPEAK_DEVICE:-$card}"
    fi
  fi
}

configure_audio

exec "${INSTALL_DIR}/qf_tv" "$@"
