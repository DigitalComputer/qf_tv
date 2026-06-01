# qf_tv

Native Flutter Linux app for QueueFlow waiting-room TV displays (mini PC kiosk).

## TV box — one command (Ubuntu Server)

Full guide: **[docs/TV-BOX-SETUP.md](docs/TV-BOX-SETUP.md)**

```bash
curl -fsSL https://demo.queueflow.ao/api/v1/tv/setup/bootstrap.sh | sudo bash

sudo reboot
```

Or manual env override:

```bash
curl -fsSL https://raw.githubusercontent.com/DigitalComputer/qf_tv/main/scripts/setup-tv-box.sh \
  | sudo QF_API_HOST=https://demo.queueflow.ao bash
```

Downloads the app from [GitHub Releases](https://github.com/DigitalComputer/qf_tv/releases), configures kiosk auto-login + systemd.

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
| GET | `/api/v1/tv/setup` — provisioning JSON (api_host, version, repo, install_command) |
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
