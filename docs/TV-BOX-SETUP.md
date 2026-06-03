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

1. On live display, click once to **activar som** (fullscreen overlay).
2. Top bar **AO VIVO** = WebSocket to Reverb; **RECONECTANDO** = HTTP poll fallback (queue still updates every ~3s).
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
6. Update TV app: `sudo QF_TV_VERSION=v1.0.6 ./scripts/install-qf-tv-update.sh && sudo systemctl restart qf-tv`

Optional `.env` on API: `REVERB_CLIENT_PORT=6001` if Reverb is only exposed on 6001 while HTTP is on 8000.

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
