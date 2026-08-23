#!/bin/bash
# Quick HTTPS connectivity check for AI API hostnames (IPv4).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAINS_FILE="${DOMAINS_FILE:-${SCRIPT_DIR}/domains.list}"
CURL="${CURL:-curl -4 -I --connect-timeout 15 --max-time 20 -sS}"

fail=0

while read -r host || [[ -n "${host}" ]]; do
  [[ -z "${host}" || "${host}" =~ ^# ]] && continue
  host="${host#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  url="https://${host}/"
  echo "== ${host}"
  ip=$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1; exit}' || true)
  if [[ -z "${ip}" ]]; then
    echo "  FAIL: no A record"
    fail=1
    continue
  fi
  echo "  A: ${ip}"
  if ${CURL} "${url}" | head -5; then
    echo "  OK"
  else
    echo "  FAIL: curl"
    fail=1
  fi
  echo
done < "${DOMAINS_FILE}"

# Anthropic static range sanity
echo "== route hint (host; pfSense decides WAN2)"
ip route get 160.79.104.10 2>/dev/null || true

exit "${fail}"
