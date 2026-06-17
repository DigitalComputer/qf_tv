#!/usr/bin/env bash
# Launcher for openbox autostart — software GL + analog audio + read api_host from config.
# Installed to /opt/qf-tv/run-qf-tv.sh by setup-tv-box.sh / install-qf-tv-update.sh

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/qf-tv}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GDK_SYNCHRONIZE="${GDK_SYNCHRONIZE:-0}"

configure_audio() {
  # PulseAudio/PipeWire — must run in kiosk graphical session (openbox autostart), not bare SSH.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

  start_audio_server() {
    if command -v pactl &>/dev/null && pactl info &>/dev/null 2>&1; then
      return 0
    fi
    if command -v pulseaudio &>/dev/null; then
      pulseaudio --start --exit-idle-time=-1 --daemonize 2>/dev/null || true
    fi
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.3
      if pactl info &>/dev/null 2>&1; then
        return 0
      fi
    done
    # Ubuntu 24.04+ may ship PipeWire without pulseaudio user session.
    if command -v pipewire &>/dev/null; then
      pipewire &>/dev/null &
      sleep 1
      if command -v wireplumber &>/dev/null; then
        wireplumber &>/dev/null &
        sleep 0.5
      fi
      if command -v pipewire-pulse &>/dev/null; then
        pipewire-pulse &>/dev/null &
        sleep 1
      fi
    fi
    for i in 1 2 3 4 5; do
      sleep 0.3
      if pactl info &>/dev/null 2>&1; then
        return 0
      fi
    done
    return 1
  }

  if command -v pactl &>/dev/null; then
    start_audio_server || echo "qf_tv: audio server not ready — ALSA fallback only" >&2

    local sink=""
    sink="$(pactl list short sinks 2>/dev/null \
      | grep -iE 'analog|headphone|hp|es8388|rk817|rk809|codec|pch|alc|hda|intel' \
      | head -1 | awk '{print $2}' || true)"
    if [[ -z "$sink" ]]; then
      sink="$(pactl list short sinks 2>/dev/null | grep -vi hdmi | head -1 | awk '{print $2}' || true)"
    fi
    if [[ -n "$sink" ]]; then
      pactl set-default-sink "$sink" 2>/dev/null || true
      pactl set-sink-mute "$sink" 0 2>/dev/null || true
      pactl set-sink-volume "$sink" 100% 2>/dev/null || true
      export QF_PULSE_SINK="$sink"
      export PULSE_SINK="$sink"
      export GST_AUDIO_SINK="pulsesink device=${sink}"
    else
      export GST_AUDIO_SINK="${GST_AUDIO_SINK:-pulsesink}"
    fi
  fi

  # ALSA fallback — analog codec on rk3568 (ES8388) or Intel mini-PC (ALC269/PCH)
  if command -v aplay &>/dev/null; then
    local card dev
    card="$(aplay -l 2>/dev/null | awk -F'[ :]' \
      '/card [0-9]+:.*(ES8388|RK817|RK809|codec|Analog|PCH|ALC|Intel|HDA)/{print $2; exit}')"
    dev="$(aplay -l 2>/dev/null | awk -v c="$card" -F'[ :]' '$2==c && /device/{print $4; exit}')"
    if [[ -n "$card" && -n "$dev" ]]; then
      export QF_ALSA_DEVICE="plughw:${card},${dev}"
    fi
  fi

  export AUDIODEV="${QF_ALSA_DEVICE:-default}"
  export PULSE_PROP="${PULSE_PROP:-media.role=music}"
}

configure_audio

# Local Kokoro TTS on TV box (queueflow-tts.service @ 127.0.0.1:5050)
export KOKORO_TTS_URL="${KOKORO_TTS_URL:-http://127.0.0.1:5050}"

exec "${INSTALL_DIR}/qf_tv" "$@"
