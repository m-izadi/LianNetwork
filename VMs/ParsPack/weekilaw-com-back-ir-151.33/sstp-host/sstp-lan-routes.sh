#!/bin/bash
# Wait for SSTP ppp interface, then add LAN route via tunnel peer.
set -euo pipefail

PEER_IP="${SSTP_PEER_IP:-192.168.90.1}"
LAN_CIDR="${LAN_CIDR:-192.168.88.0/24}"
IFACE=""

for _ in $(seq 1 60); do
  IFACE=$(ip -br link show type ppp 2>/dev/null | awk '{print $1; exit}')
  if [[ -n "${IFACE}" ]] && ip -br addr show "${IFACE}" 2>/dev/null | grep -q UP; then
    break
  fi
  # some systems show UNKNOWN but still work
  if [[ -n "${IFACE}" ]] && ip addr show "${IFACE}" 2>/dev/null | grep -q 'inet '; then
    break
  fi
  sleep 1
  IFACE=""
done

if [[ -z "${IFACE}" ]]; then
  echo "sstp-lan-routes: no ppp interface after wait" >&2
  exit 1
fi

ip route replace "${LAN_CIDR}" via "${PEER_IP}" dev "${IFACE}"
echo "sstp-lan-routes: ${LAN_CIDR} via ${PEER_IP} dev ${IFACE}"
