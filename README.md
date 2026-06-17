# qf_tv

Native Flutter Linux app for QueueFlow waiting-room TV displays (mini PC kiosk).

## TV box — one command (Ubuntu Server)

Full guide: **[docs/TV-BOX-SETUP.md](docs/TV-BOX-SETUP.md)**

```bash
# Self-hosted — all instances/screens from central
curl -fsSL https://queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash

# Single tenant
curl -fsSL https://demo.queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash

sudo reboot
```

Downloads the app from [GitHub Releases](https://github.com/DigitalComputer/qf_tv/releases), configures kiosk auto-login + systemd.

## v1.0.15

- Fix v1.0.14 black-screen regression: disable WebView on Linux — YouTube/iframe use thumbnail + title (native WebKit overlay cannot clip to Zone C)
- Fix announce/TTS audio on Intel ALC269/PCH boxes: ALSA default via PulseAudio (`~/.asoundrc`), stop passing card index to espeak-ng `-a`
- Kiosk launcher: unmute default sink, detect PCH/ALC/HDA sinks, set `XDG_RUNTIME_DIR` + `AUDIODEV`
- Direct video URLs play with sound (`video_player` volume 1.0)

## v1.0.14

- Fix YouTube error 153: iframe via `loadHtmlString` + Referer `baseUrl` (direct embed lacked HTTP Referer)
- Fix black-screen regression: defer WebView init until Zone C laid out; block YouTube fullscreen overlay
- YouTube embed failure → thumbnail + title fallback (queue zones stay visible)
- Docs: kernel-level audio troubleshooting when `aplay -l` empty

## v1.0.13

- Fix Zone C video: `video_player` + WebKit embed for YouTube/iframe (was title-only stub)
- HLS `.m3u8` fallback via WebKit + hls.js (qf_screen parity)
- Audio: route to analog jack (PulseAudio sink + ALSA), `paplay`/`mpg123` MP3 fallback
- Install deps: WebKitGTK, GStreamer bad/libav, pulseaudio, mpg123

## v1.0.12

- Sound: API neural TTS (`/api/v1/display/announce`) like qf_screen — espeak fallback
- Layout parity with qf_screen: split/default/full via `display/config` + Zone A–D grid
- Reverb `ticket.called` triggers instant announce + UI update (not poll-only)

## v1.0.11

- Fix queue refresh 403 (`GET /api/v1/tv/queue` — token only, no display id mismatch)
- Stop marking Reverb disconnected on HTTP errors
- TTS via `espeak-ng` (flutter_tts broken on Linux)
- Install script disables duplicate systemd `qf-tv` process

## v1.0.7

- TTS auto-enabled at boot (no sound activation overlay)

## v1.0.6

- Real Laravel Reverb WebSocket (`ticket.called` → instant queue refresh)
- HTTP poll fallback every 3s when WS down
- pt-PT TTS announcements on each call

## Flow

```
Boot → saved display? → DisplayScreen (template renderer)
      → no session     → DisplayPickerScreen → activate → DisplayScreen
Unlock: Ctrl+P then Alt+P (within 2s) → picker
```

## API (laravel-api-kit)

Host: `{tenant}.queueflow.ao` — set at install via `QF_API_HOST` → `/etc/qf-tv/config.json`

| Method | Path |
|--------|------|
| GET | `/api/v1/tv/registry` — **central only**: all instances + URLs |
| GET | `/api/v1/tv/screens` — **central only**: all displays across instances |
| GET | `/api/v1/tv/setup` — provisioning JSON (central or tenant) |
| GET | `/api/v1/tv/setup/bootstrap.sh` — one-shot install script |
| GET | `/api/v1/tv/ping` |
| GET | `/api/v1/tv/displays` |
| POST | `/api/v1/tv/displays/{id}/activate` |
| GET | `/api/v1/tv/displays/{id}/queue` (Bearer display token) |
| GET | `/api/v1/tv/templates/{id}` |
| GET | `/api/v1/tv/bootstrap` (Bearer display token) |

Templates: admin `/displays` → [docs/features/qf-tv-templates.md](../docs/features/qf-tv-templates.md)

## Publish a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

CI builds `qf_tv-linux-x64.tar.gz` → GitHub Releases.

## Dev build (from source)

```bash
flutter pub get
flutter build linux --release --dart-define=QF_API_HOST=https://demo.queueflow.ao
```

## Remote deploy (build machine → TV box)

```bash
./deploy.sh 192.168.1.101 https://demo.queueflow.ao
```

## systemd

```bash
systemctl status qf-tv
journalctl -u qf-tv -f
```
