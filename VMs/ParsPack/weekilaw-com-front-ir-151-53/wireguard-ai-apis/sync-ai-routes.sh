#!/bin/bash
# Resolve AI API hostnames and send only those IPs via WireGuard (wg-ai).
# Does not touch default route, SSTP, ens23, or iran-routing.
set -euo pipefail

WG_IF="${WG_IF:-wg-ai}"
DOMAINS_FILE="${DOMAINS_FILE:-/etc/wireguard/ai-apis-domains.list}"
STATE_DIR="${STATE_DIR:-/var/lib/ai-api-routes}"
STATIC_CIDRS="${STATIC_CIDRS:-160.79.104.0/23}"   # Anthropic published inbound
MARKER="# ai-api-routes"

mkdir -p "${STATE_DIR}"
PREV="${STATE_DIR}/ips.prev"
CUR="${STATE_DIR}/ips.cur"

if [[ ! -f "${DOMAINS_FILE}" ]]; then
  echo "missing ${DOMAINS_FILE}" >&2
  exit 1
fi

if ! ip link show "${WG_IF}" &>/dev/null; then
  echo "interface ${WG_IF} is down; start: systemctl start wg-quick@${WG_IF}" >&2
  exit 1
fi

PEER_PUB=$(wg show "${WG_IF}" peers | head -1 || true)
if [[ -z "${PEER_PUB}" ]]; then
  echo "no WireGuard peer on ${WG_IF}" >&2
  exit 1
fi

: > "${CUR}"
while read -r host || [[ -n "${host}" ]]; do
  [[ -z "${host}" || "${host}" =~ ^# ]] && continue
  # strip URL path if someone pasted full URL
  host="${host#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1}' | sort -u >> "${CUR}" || true
done < "${DOMAINS_FILE}"

sort -u "${CUR}" -o "${CUR}"

ALLOWED=()
while read -r cidr; do
  [[ -z "${cidr}" ]] && continue
  ALLOWED+=("${cidr}")
done < <(echo "${STATIC_CIDRS}" | tr ',' '\n')

while read -r ip; do
  [[ -z "${ip}" ]] && continue
  ALLOWED+=("${ip}/32")
  ip route replace "${ip}/32" dev "${WG_IF}"
done < "${CUR}"

for cidr in ${STATIC_CIDRS//,/ }; do
  ip route replace "${cidr}" dev "${WG_IF}"
done

# Update cryptokey routing
IFS=,
wg set "${WG_IF}" peer "${PEER_PUB}" allowed-ips "${ALLOWED[*]}"
unset IFS

# Drop stale /32 routes we previously installed that are no longer needed
if [[ -f "${PREV}" ]]; then
  while read -r old; do
    [[ -z "${old}" ]] && continue
    if ! grep -qxF "${old}" "${CUR}"; then
      ip route del "${old}/32" dev "${WG_IF}" 2>/dev/null || true
    fi
  done < "${PREV}"
fi

cp "${CUR}" "${PREV}"
echo "${MARKER}: $(wc -l < "${CUR}") IPs via ${WG_IF}"
cat "${CUR}"
