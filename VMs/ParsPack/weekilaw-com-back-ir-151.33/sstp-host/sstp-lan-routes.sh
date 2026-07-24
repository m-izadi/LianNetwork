#!/bin/bash
# Clear leftover iran-routing marks, wait for ppp, add LAN route via SSTP peer.
set -euo pipefail

PEER_IP="${SSTP_PEER_IP:-192.168.90.1}"
LAN_CIDR="${LAN_CIDR:-192.168.88.0/24}"

# Prevent blackhole via dead virbr0
ip rule del fwmark 1 table iran-bypass 2>/dev/null || true
iptables -t mangle -D OUTPUT -m set ! --match-set iran dst -j MARK --set-mark 1 2>/dev/null || true
iptables -t mangle -D PREROUTING ! -i virbr0 -m set ! --match-set iran dst -j MARK --set-mark 1 2>/dev/null || true

IFACE=""
for _ in $(seq 1 90); do
  IFACE=$(ip -o link show type ppp 2>/dev/null | awk -F': ' '{print $2; exit}' | awk '{print $1}')
  if [[ -n "${IFACE}" ]] && ip -o addr show "${IFACE}" 2>/dev/null | grep -q ' inet '; then
    break
  fi
  sleep 1
  IFACE=""
done

if [[ -z "${IFACE}" ]]; then
  echo "sstp-lan-routes: no ppp interface with IPv4 after wait" >&2
  ip -br a >&2 || true
  exit 1
fi

ip route replace "${LAN_CIDR}" via "${PEER_IP}" dev "${IFACE}"
echo "sstp-lan-routes: ${LAN_CIDR} via ${PEER_IP} dev ${IFACE}"
ip route get 192.168.88.242 || true
