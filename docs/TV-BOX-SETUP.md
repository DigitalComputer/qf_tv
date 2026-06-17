# qf_tv — Ubuntu TV Box Setup

One script turns a **fresh Ubuntu Server** mini PC into a QueueFlow waiting-room display. No manual URL entry on the TV — configure the tenant API once at install time, pick the display on first boot, then it stays locked until **Ctrl+P → Alt+P**.

---

## Which machine? (168 vs 133)

| Task | Run on **API server** (`queueflow@…`) | Run on **TV box** (`qf_tv@…`) |
|------|----------------------------------------|-------------------------------|
| `git pull` laravel-api-kit / qf_orchestrator | Yes | **No** — repos not on TV |
| `docker compose` / `deploy-tv-api-fix.sh` | Yes | No |
| `curl http://127.0.0.1:8000/...` | Yes (API is local) | **No** — use tenant domain |
| `curl http://{tenant}.queueflow.ao:8000/...` | Yes | **Yes** — same as TV app |
| Edit `/etc/qf-tv/config.json` | No | Yes |
| `systemctl restart lightdm` | No | Yes |

TV app uses `http://{tenant}.queueflow.ao:8000` from config (not the browser dashboard URL `https://…/dashboard`).

---

## What you need

| Item | Notes |
|------|--------|
| Hardware | Mini PC + HDMI monitor (non-smart OK) |
| OS | **Ubuntu Server 22.04 or 24.04 LTS** (Desktop also works) |
| Network | Ethernet or Wi‑Fi configured before/after install |
| API | Tenant URL, e.g. `https://demo.queueflow.ao` or `http://demo.queueflow.ao:8000` (dev) |
| Admin | Display + template created in QueueFlow `/displays` |

---

## One-command install (recommended)

### Single tenant (SaaS / one instance)

```bash
curl -fsSL https://demo.queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash
sudo reboot
```

### Self-hosted — all instances from central registry

TV box only needs central URL. Núcleo lists registered instances → each instance exposes screens → picker shows **all screens** auto-synced.

```bash
curl -fsSL https://queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash
sudo reboot
```

Central endpoints (on `queueflow.ao`):

| Path | Purpose |
|------|---------|
| `GET /api/v1/tv/registry` | All registered instances + `api_host` URLs |
| `GET /api/v1/tv/screens` | Aggregated displays from every instance |
| `GET /api/v1/tv/setup` | Provisioning JSON |
| `GET /api/v1/tv/setup/bootstrap.sh` | One-shot install script |

Flow:

```
queueflow.ao/registry → instance URLs → each /tv/displays → unified picker
```

Re-run same bootstrap to update box later.

After reboot: auto-login → display picker → select screen → fullscreen queue.

---

## Local / air-gapped install

If the repo is already on the machine:

```bash
cd qf_tv
chmod +x scripts/setup-tv-box.sh
sudo QF_API_HOST=https://demo.queueflow.ao ./scripts/setup-tv-box.sh
sudo reboot
```

---

## LAN / dev (no public DNS for `*.queueflow.ao`)

Install uses **domain only** — no manual server IP. Scripts call your tenant URL, learn the API IP from `curl`, and write `/etc/hosts` only if DNS fails.

```bash
# One-shot (recommended) — domain from API bootstrap
curl -fsSL http://administra-o-maianga.queueflow.ao:8000/api/v1/tv/setup/bootstrap.sh | sudo bash
sudo reboot
```

Or upgrade app only:

```bash
sudo QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
  QF_TV_VERSION=latest \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh)"
```

Registry and `/tv/setup` return `api_host` with the **same scheme and port** as the request (e.g. `http://tenant.queueflow.ao:8000` on dev, `https://tenant.queueflow.ao` in production).

Use `http://…:8000` when dev stack has no TLS; use `https://` when nginx serves SSL on 443.

| Variable | Default | Description |
|----------|---------|-------------|
| `QF_CENTRAL_HOST` | from API / bootstrap | Central registry URL (`/etc/qf-tv/config.json`) — multi-instance self-hosted |
| `QF_API_HOST` | from API / bootstrap | Single tenant API URL |
| `QF_TV_VERSION` | from API or `latest` | GitHub release tag, e.g. `v1.0.0` |
| `GITHUB_REPO` | from API or `DigitalComputer/qf_tv` | Release source |
| `KIOSK_USER` | `kiosk` | Linux user for auto-login |
| `INSTALL_DIR` | `/opt/qf-tv` | Application directory |

Examples:

```bash
# Pin a specific release
sudo QF_API_HOST=https://acme.queueflow.ao QF_TV_VERSION=v1.0.0 \
  ./scripts/setup-tv-box.sh

# Local dev stack (orchestrator)
sudo QF_API_HOST=http://demo.queueflow.ao:8000 ./scripts/setup-tv-box.sh
```

---

## What the script does

1. Installs minimal GUI stack: **Xorg + Openbox + LightDM** (lightweight kiosk)
2. Creates **`kiosk`** user with **auto-login**
3. Disables screen blanking + hides cursor (`unclutter`)
4. Downloads **qf_tv** binary from [GitHub Releases](https://github.com/DigitalComputer/qf_tv/releases)
5. Writes **`/etc/qf-tv/config.json`** with `api_host`
6. Installs & enables **`qf-tv.service`** (systemd restart on crash)
7. Sets boot target **graphical**

---

## GitHub Releases

Binaries are built automatically when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions produces:

| Asset | Contents |
|-------|----------|
| `qf_tv-linux-x64.tar.gz` | Flutter Linux release bundle (`qf_tv` + `lib/` + `data/`) |
| `qf_tv-linux-x64.tar.gz.sha256` | Checksum |

Download manually:

```bash
curl -LO https://github.com/DigitalComputer/qf_tv/releases/latest/download/qf_tv-linux-x64.tar.gz
curl -LO https://github.com/DigitalComputer/qf_tv/releases/latest/download/qf_tv-linux-x64.tar.gz.sha256
sha256sum -c qf_tv-linux-x64.tar.gz.sha256
```

---

## BIOS (power loss recovery)

On the mini PC firmware:

- **Restore on AC power loss** → **Power On**
- Disable long boot delays if possible

After power returns: machine boots → auto-login → `qf-tv.service` starts → display resumes (or reconnects).

---

## First run on the TV

1. Box boots to **display picker** (lists displays from admin)
2. Select your screen (e.g. “Painel Principal”)
3. App saves choice locally — **no setup screen on next boot**
4. Queue updates via API polling

**Change display / re-pair:** press **Ctrl+P**, then **Alt+P** within 2 seconds.

---

## Day-2 operations

```bash
# Is the app running? (started by openbox on display :0, not TTY)
pgrep -a qf_tv
sudo -u kiosk DISPLAY=:0 xdpyinfo >/dev/null && echo "X OK"

# GUI session
systemctl status lightdm

# Logs (if using journal from openbox / old systemd unit)
journalctl -u lightdm -n 50
```

### `cannot open display: :0`

X not running — common after SSH `systemctl restart qf-tv` without LightDM.

```bash
sudo bash /path/to/qf_tv/scripts/fix-tv-display.sh
# or manually:
sudo systemctl stop qf-tv
sudo systemctl start lightdm
```

Plug **VGA or HDMI** monitor before starting GUI. TTY consoles never show the Flutter UI.

### VGA / HDMI monitor

Run `sudo -u kiosk DISPLAY=:0 xrandr` — only **connected** outputs get a signal.

| xrandr shows | What to do |
|--------------|------------|
| `HDMI-1 connected` | Plug monitor into **HDMI** on the box (best) |
| `VGA-1 connected` | Native VGA works |
| Only `eDP-1 connected` | Mini PC drives **internal panel only** — VGA cable not detected. Use **HDMI** or VGA dongle **on HDMI port** |

Black external monitor + only `eDP-1` = UI is on built-in screen (if any), not on VGA.

After plugging HDMI: `sudo systemctl restart lightdm`

### LightDM `inactive`

```bash
echo '/usr/sbin/lightdm' | sudo tee /etc/X11/default-display-manager
sudo systemctl disable gdm3 2>/dev/null
sudo systemctl set-default graphical.target
sudo systemctl enable --now lightdm
journalctl -u lightdm -n 40 --no-pager
```

Still failing → **reboot once** with VGA cable connected.

```bash
# Status (legacy unit may be disabled)
systemctl status qf-tv

# Logs when systemd managed the app
journalctl -u qf-tv -f

# Config
cat /etc/qf-tv/config.json

# Restart app
sudo systemctl restart qf-tv

# Update to latest release (re-download + restart)
sudo QF_API_HOST=https://demo.queueflow.ao ./scripts/setup-tv-box.sh
```

---

## Troubleshooting

### Download failed — no GitHub release

Publish a tag first (`v1.0.0`) or set `QF_TV_VERSION` to an existing tag.

### `libGLESv2.so.2: cannot open shared object` / app core dump

Ubuntu 24.04 package names changed (not `libgles2-mesa`):

```bash
sudo apt-get update
sudo apt-get install -y libgl1 libegl1 libgles2 libgl1-mesa-dri
# if that fails on 24.04:
sudo apt-get install -y libgl1t64 libegl1t64 libgles2t64
ldconfig -p | grep GLES
sudo systemctl restart lightdm
pgrep -a qf_tv
```

Or: `sudo bash -c "$(curl -fsSL .../install-flutter-runtime.sh)"`

### Black screen after reboot

```bash
systemctl status lightdm
pgrep -a qf_tv
journalctl -u lightdm -n 50
```

Ensure tenant DNS resolves from the box:

```bash
curl -s "$(
  jq -r .api_host /etc/qf-tv/config.json
)/api/v1/tv/ping"
```

### API unreachable / HTML instead of JSON on ping

Tenant TV API **only** answers on the instance host (`https://{slug}.queueflow.ao`), not `queueflow.ao` or raw IP.

```bash
# On API server (127.0.0.1 = same machine as Docker :8000)
curl -s -H "Host: administra-o-maianga.queueflow.ao" \
  http://127.0.0.1:8000/api/v1/tv/ping

# On TV box — tenant domain (not 127.0.0.1)
curl -s http://administra-o-maianga.queueflow.ao:8000/api/v1/tv/ping

cat /etc/qf-tv/config.json
getent hosts administra-o-maianga.queueflow.ao
ls -la /opt/qf-tv/qf_tv /opt/qf-tv/run-qf-tv.sh
```

- Check firewall / DNS for `{tenant}.queueflow.ao`
- Dev LAN: `/etc/hosts` auto-written by install when DNS missing (IP from curl to tenant domain)
- After API deploy: `cd ~/qf_orchestrator && ./scripts/fix-dev-stack.sh` (rebuilds `qf-api`, seeds domains)

### Calls from posto not showing / no sound (v1.0.6+)

**Symptoms:** `Forbidden (HTTP 403)` at bottom, **RECONECTANDO** after each call, two `qf_tv` processes.

**Root cause (fixed in v1.0.8):** stale `display_id` in prefs vs token; queue refresh 403; Reverb still connected but UI lied; `flutter_tts` broken on Linux.

**Immediate fix on TV box (SSH):**

```bash
# 1. Stop duplicate app (systemd + openbox)
sudo systemctl disable --now qf-tv
sudo pkill -u kiosk -f qf_tv

# 2. Sound
sudo apt-get install -y espeak-ng

# 3. Re-activate display (replace Principal with your ecrã name)
API=$(jq -r .api_host /etc/qf-tv/config.json)
DISPLAY_NAME="Principal"
DISPLAY_ID=$(curl -s -H "Accept: application/json" "$API/api/v1/tv/displays" \
  | jq -r --arg n "$DISPLAY_NAME" '.data.displays[] | select(.name==$n) | .id')
RESP=$(curl -s -X POST -H "Accept: application/json" "$API/api/v1/tv/displays/${DISPLAY_ID}/activate")
TOKEN=$(echo "$RESP" | jq -r .data.token)
sudo mkdir -p /home/kiosk/.local/share/com.example.qf_tv
sudo tee /home/kiosk/.local/share/com.example.qf_tv/shared_preferences.json > /dev/null <<EOF
{"flutter.display_id":"$DISPLAY_ID","flutter.display_name":"$DISPLAY_NAME","flutter.display_token":"$TOKEN","flutter.template_id":"$(echo "$RESP" | jq -r .data.template_id)","flutter.branch_id":"$(echo "$RESP" | jq -r .data.branch_id)","flutter.tenant_id":"$(echo "$RESP" | jq -r .data.tenant_id)","flutter.api_host":"$API"}
EOF
sudo chown -R kiosk:kiosk /home/kiosk/.local/share/com.example.qf_tv

# 4. Update app + API (orchestrator: deploy-tv-api-fix.sh --quick)
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
sudo env QF_TV_VERSION=v1.0.8 bash /tmp/qf-tv-update.sh
```

1. Top bar **AO VIVO** = WebSocket to Reverb; **RECONECTANDO** = HTTP poll fallback (queue still updates every ~3s).
2. TTS announces each new call automatically (no tap required).
3. From TV box, Reverb must be reachable (same host as API):

```bash
API=$(jq -r '.api_host // .central_host' /etc/qf-tv/config.json)
HOST=$(echo "$API" | sed -E 's#https?://([^:/]+).*#\1#')
PORT=$(echo "$API" | grep -oE ':[0-9]+' | tr -d :)
PORT=${PORT:-8000}
curl -sI "http://${HOST}:${PORT}/app/devkey123" | head -3
# or direct Reverb port:
curl -sI "http://${HOST}:6001/app/devkey123" | head -3
```

4. After API deploy, re-pick ecrã once (new `reverb.host` = tenant domain, not `qf-api`).
5. Deploy API fix: `cd ~/qf_orchestrator && ./scripts/deploy-tv-api-fix.sh --quick`
6. Update TV app (on **TV box** — script is not in `$HOME`; download first):

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
sudo env QF_TV_VERSION=v1.0.7 bash /tmp/qf-tv-update.sh
```

Uses existing `/etc/qf-tv/config.json` for `api_host`. Restarts `lightdm` (not `qf-tv` systemd).

Optional `.env` on API: `REVERB_CLIENT_PORT=6001` if Reverb is only exposed on 6001 while HTTP is on 8000.

### Video shows title only / no sound on 3.5mm jack (v1.0.13+)

**Symptoms:** Zone C shows media **title** text but no YouTube/video; announce MP3 silent on aux jack (VGA + 3.5mm rk3568).

**Root cause (fixed in v1.0.13):** `_ZoneC` was a stub — only `image`/`logo` rendered; `youtube`/`video`/`iframe` showed title placeholder. Audio went to default HDMI sink, not analog jack.

**Fix on TV box:**

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
sudo env QF_TV_VERSION=v1.0.15 \
     QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
     bash /tmp/qf-tv-update.sh
```

**Verify audio routing (SSH — use kiosk session, not bare TTY):**

```bash
# PulseAudio runs in kiosk GUI session; bare SSH often shows "Connection refused"
KUID=$(id -u kiosk)
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$KUID pactl list short sinks

aplay -l                        # must list ES8388/codec card — see below if empty
speaker-test -D plughw:N,0 -c 2 # replace N with card from aplay -l
espeak-ng -v pt "teste"         # TTS fallback
```

**Verify media config from API** (needs display token from activate):

```bash
API=$(jq -r .api_host /etc/qf-tv/config.json)
TOKEN=$(jq -r '.["flutter.display_token"]' /home/kiosk/.local/share/com.example.qf_tv/shared_preferences.json)
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "$API/api/v1/display/config" | jq '.data.media_items[] | {kind,title,url}'
```

Expect `kind: youtube` with YouTube URL, or `kind: video` with `.m3u8`/mp4 URL. API returns raw `url` from `tv_media_items` table — no transform.

### Black screen — queue UI hidden behind WebView (v1.0.14–v1.0.19, mitigated v1.0.20)

**Symptoms:** Zone C shows YouTube/video but zones A/B/D are black — queue ticket number, waiting list, ticker invisible.

**Root cause:** `webview_win_floating` renders a **native WebKitGTK overlay above the entire Flutter window**. Loading before Zone C bounds are set, or YouTube fullscreen, can cover the whole window.

**App fix (v1.0.20):** Keep overlay hidden until 4 layout frames + `LayoutBuilder` confirms Zone C size; YouTube embed uses `fs=0` and no `fullscreen` allow; show overlay only when loading. If queue UI still black, force thumbnail mode:

```bash
# In /opt/qf-tv/run-qf-tv.sh (before exec qf_tv):
export QF_TV_NO_WEBVIEW=1
```

Zone C then shows YouTube thumbnail + title + URL; queue zones A/B/D stay visible.

**App fix (v1.0.16):** Re-enable bounded WebView on Linux — mount `WebViewWidget` in Zone C first, wait two frames for `updateBounds`, then load YouTube/iframe/HLS with `autoplay=1`. Direct mp4 autoplays via `video_player`. Queue zones stay visible.

**App fix (v1.0.15):** On Linux, **no WebView** for YouTube/iframe/HLS — Zone C shows YouTube thumbnail + title (or `video_player` for direct mp4 URLs). Queue UI always visible.

**Install v1.0.20:**

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
sudo env QF_TV_VERSION=v1.0.20 \
     QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
     bash /tmp/qf-tv-update.sh
```

### Kokoro TTS — natural voice on TV box (v1.0.20)

**Architecture:** TTS runs **on the TV box** (`192.168.30.60`), not on the API server (`192.168.30.168`). qf_tv POSTs ticket text to `http://127.0.0.1:5050/speak`; Kokoro plays on the analog jack (ALC269/PCH). Laravel `/display/announce` (edge-tts MP3) remains for **qf_screen** browsers; TV uses local Kokoro first, then API MP3, then espeak.

**Install on TV box:**

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-kokoro-tts.sh -o /tmp/install-kokoro-tts.sh
sudo bash /tmp/install-kokoro-tts.sh
```

Or with full TV setup: `INSTALL_KOKORO=1` is default in `setup-tv-box.sh`; for update-only: `sudo INSTALL_KOKORO=1 bash install-qf-tv-update.sh`.

**Verify:**

```bash
systemctl status queueflow-tts
curl -s http://127.0.0.1:5050/health
curl -X POST http://127.0.0.1:5050/speak \
  -H 'Content-Type: application/json' \
  -d '{"text":"Atenção. Senha um dois três."}'
```

**Config** (`/opt/qf-kokoro-tts/.env`):

| Variable | Default | Notes |
|----------|---------|-------|
| `TTS_VOICE` | `pf_dora` | pt-BR female |
| `TTS_LANG` | `pt-br` | Kokoro lang code `p` |
| `AUDIO_DEVICE` | `plughw:CARD=PCH,DEV=0` | ALSA analog jack |
| `TTS_PORT` | `5050` | Local only |

**qf_tv env** (set in `/opt/qf-tv/run-qf-tv.sh`):

```bash
export KOKORO_TTS_URL=http://127.0.0.1:5050
export QF_TV_KOKORO=1   # set 0 to disable Kokoro, use API MP3 only
```

**Troubleshooting:**

```bash
journalctl -u queueflow-tts -f          # first speak downloads Kokoro model (~100MB)
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$(id -u kiosk) aplay -l
# sounddevice fails → tts_engine falls back to aplay automatically
```

**Disable Kokoro** (use API edge-tts MP3 from Docker host):

```bash
export QF_TV_KOKORO=0
```

API server still needs `edge-tts` in `qf-api` container — see “Robotic voice” below.


### Black screen + YouTube error 153 (v1.0.13 regression, fixed v1.0.14)

**Symptoms:** Entire display black except YouTube “Error 153 — Video player configuration error”; queue zones (ticket number, waiting list, ticker) invisible.

**Root causes:**

1. **YouTube 153:** `loadRequest()` to `youtube.com/embed/…` sends no HTTP Referer. YouTube now requires Referer (error code 153 per [IFrame API](https://developers.google.com/youtube/iframe_api_reference)).
2. **Layout blackout:** `webview_win_floating` renders a **native WebKit overlay on top of Flutter**. Loading before Zone C has layout bounds, or YouTube entering fullscreen, can cover the whole window — Flutter queue UI sits underneath and disappears.

**App fix (v1.0.14):** YouTube/iframe load via `loadHtmlString` + iframe + `baseUrl: https://queueflow.local`; WebView init deferred until after first frame; fullscreen requests blocked on Linux; thumbnail fallback on embed failure.

**Install:**

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/install-qf-tv-update.sh -o /tmp/qf-tv-update.sh
sudo env QF_TV_VERSION=v1.0.15 \
     QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 \
     bash /tmp/qf-tv-update.sh
```

After install: queue zones A/B/D visible again; Zone C shows YouTube thumbnail + title on Linux (no embedded player until proper GTK embedding exists).

### No sound — card present but TTS/announce silent (ALC269 / Intel PCH, fixed v1.0.17)

**Symptoms:** `/proc/asound/cards` shows `HDA Intel PCH` / `ALC269VC`; bare SSH `espeak-ng` → `ALSA cannot find card '0'`; `pactl` → Connection refused without `XDG_RUNTIME_DIR`; v1.0.15–v1.0.16 still silent.

**Root causes:**

1. **Openbox never starts PulseAudio** — unlike GNOME, openbox autostart does not launch the audio server; v1.0.15 only tried `pulseaudio --start` once with no wait/retry.
2. **audioplayers/GStreamer silent** — announce MP3 played via GStreamer with no sink env; system `paplay` fallback only ran on exception.
3. **Wrong espeak device (v1.0.14)** — `QF_ESPEAK_DEVICE=0` passed card index to `-a`.
4. **ALSA default unset** — apps need `~/.asoundrc` routing to PulseAudio.

**Fix (v1.0.17):** launcher creates `XDG_RUNTIME_DIR`, starts PulseAudio/PipeWire with retry, sets `PULSE_SINK` + `GST_AUDIO_SINK` for video; announce uses `paplay`/`pw-play`/`mpg123` first on Linux; `~/.asoundrc` for kiosk + `qf_tv` users.

**Verify in kiosk session (not bare SSH):**

```bash
KUID=$(id -u kiosk)
export XDG_RUNTIME_DIR=/run/user/$KUID

# PulseAudio sinks (expect analog / hdmi)
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$KUID pactl list short sinks

# ALSA card (Intel PCH example)
cat /proc/asound/cards
aplay -l

# TTS — must use kiosk env
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$KUID espeak-ng -v pt "teste de som"

# MP3 playback test
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$KUID paplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null \
  || speaker-test -D plughw:0,0 -c 2 -t wav -l 1
```

After `install-qf-tv-update.sh` with v1.0.17: reboot or `systemctl restart lightdm`, trigger a queue call — announce MP3 should play on 3.5mm jack.

### Robotic voice — API still serving old TTS cache

qf_tv v1.0.18+ fetches neural MP3 from `GET /api/v1/display/announce` (`pt-PT-RaquelNeural` via `edge-tts`). Espeak fallback = API fetch/playback failed **or** cached MP3 from old voice.

On the **API Docker host** (container `qf-api`):

```bash
docker exec qf-api rm -rf /var/www/storage/app/display-tts/*
docker exec qf-api php artisan config:clear
docker exec qf-api which edge-tts
docker exec qf-api php artisan tinker --execute="echo config('queueflow.display.tts_voice');"
```

Set `DISPLAY_TTS_VOICE=pt-PT-RaquelNeural` in `laravel-api-kit/.env` (or orchestrator env), redeploy API if needed, then clear cache again.

### No soundcards at OS level (`aplay -l` empty)

**Symptoms:** `aplay -l` → no cards; `espeak-ng` → “cannot find card '0'”; `pactl` → Connection refused over SSH.

This is a **kernel / device-tree driver issue**, not qf_tv app code. The analog codec (ES8388 on rk3568 TV boxes) is not probed.

**Diagnose on TV box:**

```bash
uname -r
lsmod | grep snd
cat /proc/asound/cards
dmesg | grep -iE 'es8388|es8328|audio|snd|i2s' | tail -30
```

| Check | Healthy | Broken |
|-------|---------|--------|
| `/proc/asound/cards` | `ES8388` or `rockchip-es8388` | `- no soundcards -` |
| `lsmod \| grep snd_soc` | `snd_soc_es8328` or similar loaded | empty |
| `pactl` (kiosk session) | lists analog sink | Connection refused (SSH) or no sinks |

**Fixes (hardware/kernel — pick what matches your board):**

1. **Wrong kernel image** — TV boxes need vendor or Armbian build with ES8388 DTS enabled. Generic Ubuntu server ISO may ship kernel without analog codec nodes.
2. **Module not loaded** — try `sudo modprobe snd-soc-es8328` then `aplay -l` again (harmless if DTS missing).
3. **PipeWire vs PulseAudio** — install script adds `pulseaudio`; if distro uses PipeWire only, install `pipewire-pulse` and reboot.
4. **Test in GUI session** — audio daemons attach to kiosk login, not SSH:

```bash
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$(id -u kiosk) pactl list short sinks
```

5. **Board firmware** — rk3568 analog jack needs I2S + ES8388 in device tree (regulators + MCLK). May require vendor BIOS/kernel update or Armbian image with correct DT overlay.

Until `aplay -l` shows a card, `run-qf-tv-kiosk.sh` cannot route TTS/announce to the 3.5mm jack — fix kernel/driver first, then re-run update script for PulseAudio packages.

### Wrong display stuck

**Ctrl+P** then **Alt+P** → picker → select again.

---

## Dev stack (orchestrator)

With Docker stack running locally:

```bash
cd qf_orchestrator
./up.sh
# on host with Flutter:
./run-qf-tv.sh
```

For a real TV box pointing at dev API:

```bash
sudo QF_API_HOST=http://demo.queueflow.ao:8000 \
  ./scripts/setup-tv-box.sh
```

---

## Related docs

- [Template schema](../../docs/features/qf-tv-templates.md)
- [qf_tv README](../README.md)
- Admin: create displays at `/displays` in tenant dashboard
