#!/usr/bin/env bash
# Shared kiosk audio setup — sourced by setup-tv-box.sh / install-qf-tv-update.sh

install_kiosk_asoundrc() {
  local kiosk_user="${1:-kiosk}"
  local home
  home="$(eval echo "~$kiosk_user")"
  [[ -d "$home" ]] || return 0

  cat > "${home}/.asoundrc" <<'EOF'
# QueueFlow TV — route ALSA apps (espeak-ng, mpg123) through PulseAudio
pcm.!default {
  type pulse
}
ctl.!default {
  type pulse
}
EOF
  chown "${kiosk_user}:${kiosk_user}" "${home}/.asoundrc"
}

install_system_asound_fallback() {
  mkdir -p /etc/asound.conf.d
  cat > /etc/asound.conf.d/qf-tv.conf <<'EOF'
# QueueFlow TV — ALSA default via PulseAudio when user has no ~/.asoundrc
pcm.!default {
  type pulse
}
ctl.!default {
  type pulse
}
EOF
}
