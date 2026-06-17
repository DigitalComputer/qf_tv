#!/usr/bin/env bash
# Shared kiosk audio setup — sourced by setup-tv-box.sh / install-qf-tv-update.sh

write_user_asoundrc() {
  local user="$1"
  local home
  home="$(eval echo "~$user")"
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
  chown "${user}:${user}" "${home}/.asoundrc"
}

install_kiosk_asoundrc() {
  local kiosk_user="${1:-kiosk}"
  write_user_asoundrc "$kiosk_user"
}

install_tv_box_asoundrc() {
  # Kiosk session + SSH admin user (qf_tv) for diagnostics.
  local kiosk_user="${1:-kiosk}"
  local admin_user="${2:-qf_tv}"
  install_kiosk_asoundrc "$kiosk_user"
  if id "$admin_user" &>/dev/null; then
    write_user_asoundrc "$admin_user"
  fi
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
