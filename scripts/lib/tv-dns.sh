#!/usr/bin/env bash
# Shared: map QueueFlow hostnames in /etc/hosts when DNS does not resolve.
# API IP is discovered from curl to the tenant/central domain (no hardcoded LAN IP).

url_hostname() {
  local raw="${1#*://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf '%s' "$raw"
}

# GET {base}/api/v1/tv/ping — returns server IP curl connected to.
tv_resolve_remote_ip() {
  local base="${1%/}"
  local host_header="${2:-}"
  local -a curl_args=(-fsSL -o /dev/null -w '%{remote_ip}' --max-time 15)
  [[ -n "$host_header" ]] && curl_args+=(-H "Host: ${host_header}")
  curl "${curl_args[@]}" "${base}/api/v1/tv/ping" 2>/dev/null || true
}

host_resolves() {
  local name="$1"
  getent ahosts "$name" 2>/dev/null | grep -q .
}

# Write /etc/hosts entries when hostname has no DNS. Sets QF_API_IP when auto-detected.
tv_ensure_hosts_for_domains() {
  local api_ip="${QF_API_IP:-}"
  local name

  for name in "$@"; do
    [[ -z "$name" ]] && continue
    [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
    host_resolves "$name" && continue

    if [[ -z "$api_ip" && -n "${QF_API_HOST:-}" ]]; then
      api_ip="$(tv_resolve_remote_ip "${QF_API_HOST}" "$(url_hostname "$QF_API_HOST")")"
    fi
    if [[ -z "$api_ip" && -n "${QF_CENTRAL_HOST:-}" ]]; then
      api_ip="$(tv_resolve_remote_ip "${QF_CENTRAL_HOST}" "$(url_hostname "$QF_CENTRAL_HOST")")"
    fi
    [[ -n "$api_ip" ]] || return 1

    if grep -qE "[[:space:]]${name}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
      sed -i "/[[:space:]]${name}\([[:space:]]\|$\)/d" /etc/hosts
    fi
    echo "${api_ip} ${name} # queueflow-tv-dns" >> /etc/hosts
    printf '  + %s → %s (auto)\n' "$api_ip" "$name"
  done

  QF_API_IP="$api_ip"
  return 0
}
