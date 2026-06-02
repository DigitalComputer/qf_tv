#!/usr/bin/env bash
# Map QueueFlow domains in /etc/hosts when LAN DNS does not resolve *.queueflow.ao.
# API server IP is auto-detected by curling the tenant/central domain (no manual IP).
#
# Usage:
#   sudo QF_API_HOST=http://administra-o-maianga.queueflow.ao:8000 ./setup-tv-dns.sh
#
# Optional override:
#   QF_API_IP=1.2.3.4  — skip auto-detect

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/tv-dns.sh
source "${SCRIPT_DIR}/lib/tv-dns.sh"

QF_API_IP="${QF_API_IP:-}"
QF_API_HOST="${QF_API_HOST:-}"
QF_API_PORT="${QF_API_PORT:-8000}"
QF_CENTRAL_HOST="${QF_CENTRAL_HOST:-}"
QF_EXTRA_HOSTS="${QF_EXTRA_HOSTS:-queueflow.ao}"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
[[ -n "$QF_API_HOST" || -n "$QF_CENTRAL_HOST" ]] || {
  echo "Set QF_API_HOST or QF_CENTRAL_HOST (domain URL from /api/v1/tv/setup)" >&2
  exit 1
}

ensure_api_port() {
  local h="${1%/}"
  if [[ "$h" =~ ^https?://[^:/]+$ ]]; then
    h="${h}:${QF_API_PORT}"
  fi
  printf '%s' "$h"
}

names=()
[[ -n "$QF_API_HOST" ]] && names+=("$(url_hostname "$QF_API_HOST")")
[[ -n "$QF_CENTRAL_HOST" ]] && names+=("$(url_hostname "$QF_CENTRAL_HOST")")
for h in $QF_EXTRA_HOSTS; do
  names+=("$h")
done

echo "→ /etc/hosts (domain-based, IP auto-detected if needed)"
if ! tv_ensure_hosts_for_domains "${names[@]}"; then
  echo "✗ Could not map domains — ensure TV can reach QF_API_HOST (curl ping) or set QF_API_IP" >&2
  exit 1
fi

if [[ -n "$QF_API_HOST" ]]; then
  mkdir -p /etc/qf-tv
  host="$(ensure_api_port "${QF_API_HOST%/}")"
  if [[ "$host" == https://* ]]; then
    printf '%s\n' "{\"api_host\":\"${host}\",\"allow_insecure_ssl\":true}" > /etc/qf-tv/config.json
  else
    printf '%s\n' "{\"api_host\":\"${host}\"}" > /etc/qf-tv/config.json
  fi
  chmod 644 /etc/qf-tv/config.json
  echo "✓ /etc/qf-tv/config.json → $(cat /etc/qf-tv/config.json)"
fi

echo "✓ DNS ready. Test: getent hosts $(url_hostname "${QF_API_HOST:-$QF_CENTRAL_HOST}")"
