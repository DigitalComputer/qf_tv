#!/usr/bin/env bash
# Map QueueFlow tenant domains to a LAN API IP (dev / air-gapped DNS).
#
# Usage:
#   sudo QF_API_IP=192.168.30.168 QF_API_HOST=https://administra-o-maianga.queueflow.ao ./setup-tv-dns.sh
#
# Optional:
#   QF_EXTRA_HOSTS="queueflow.ao api.queueflow.ao"  — additional names

set -euo pipefail

QF_API_IP="${QF_API_IP:-}"
QF_API_HOST="${QF_API_HOST:-}"
QF_CENTRAL_HOST="${QF_CENTRAL_HOST:-}"
QF_EXTRA_HOSTS="${QF_EXTRA_HOSTS:-queueflow.ao}"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
[[ -n "$QF_API_IP" ]] || { echo "Set QF_API_IP (LAN IP of API server)" >&2; exit 1; }

url_hostname() {
  local raw="${1#*://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf '%s' "$raw"
}

HOSTS_FILE="/etc/hosts"
MARKER="# queueflow-tv-dns"

declare -A SEEN=()
add_host() {
  local name="$1"
  [[ -z "$name" ]] && return 0
  [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0
  [[ -n "${SEEN[$name]:-}" ]] && return 0
  SEEN[$name]=1

  if grep -qE "[[:space:]]${name}([[:space:]]|$)" "$HOSTS_FILE" 2>/dev/null; then
    # Replace existing line for this hostname
    sed -i "/[[:space:]]${name}\([[:space:]]\|$\)/d" "$HOSTS_FILE"
  fi
  echo "${QF_API_IP} ${name} ${MARKER}" >> "$HOSTS_FILE"
  echo "  + ${QF_API_IP} → ${name}"
}

echo "→ /etc/hosts (API at ${QF_API_IP})"
[[ -n "$QF_API_HOST" ]] && add_host "$(url_hostname "$QF_API_HOST")"
[[ -n "$QF_CENTRAL_HOST" ]] && add_host "$(url_hostname "$QF_CENTRAL_HOST")"
for h in $QF_EXTRA_HOSTS; do
  add_host "$h"
done

if [[ -n "$QF_API_HOST" ]]; then
  mkdir -p /etc/qf-tv
  printf '%s\n' "{\"api_host\":\"${QF_API_HOST%/}\"}" > /etc/qf-tv/config.json
  chmod 644 /etc/qf-tv/config.json
  echo "✓ /etc/qf-tv/config.json → ${QF_API_HOST%/}"
fi

echo "✓ DNS ready. Test: getent hosts $(url_hostname "${QF_API_HOST:-$QF_CENTRAL_HOST}")"
