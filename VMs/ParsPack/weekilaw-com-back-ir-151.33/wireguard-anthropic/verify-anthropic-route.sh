#!/bin/bash
# Verify only Anthropic API traffic goes via WireGuard; LAN/default stay intact.
set -euo pipefail

DOMAIN="${DOMAIN:-api.anthropic.com}"
WG_IF="${WG_IF:-wg-anthropic}"
ANTHROPIC_CIDR="${ANTHROPIC_CIDR:-160.79.104.0/23}"

echo "=== interface ==="
ip -br link show "${WG_IF}" 2>/dev/null || { echo "missing ${WG_IF}"; exit 1; }
wg show "${WG_IF}" || true

echo
echo "=== DNS ${DOMAIN} ==="
mapfile -t IPS < <(getent ahostsv4 "${DOMAIN}" | awk '{print $1}' | sort -u)
if [[ ${#IPS[@]} -eq 0 ]]; then
  echo "no A records for ${DOMAIN}"
  exit 1
fi
printf '%s\n' "${IPS[@]}"

echo
echo "=== route for each IP (must be via ${WG_IF}) ==="
for ip in "${IPS[@]}"; do
  echo -n "${ip}: "
  ip route get "${ip}" | head -1
done

echo
echo "=== sanity: default / LAN must NOT use ${WG_IF} ==="
echo -n "1.1.1.1: "; ip route get 1.1.1.1 | head -1
echo -n "192.168.88.242: "; ip route get 192.168.88.242 2>/dev/null | head -1 || echo "(no LAN route)"

echo
echo "=== curl egress check (Anthropic may 401 without key; path matters) ==="
curl -4 -sS -o /dev/null -w "https://${DOMAIN}/ → HTTP %{http_code} via local %{local_ip}\n" \
  --connect-timeout 10 "https://${DOMAIN}/" || true

echo
echo "Expected: Anthropic IPs in ${ANTHROPIC_CIDR} via ${WG_IF}; other traffic via eth0/ppp."
