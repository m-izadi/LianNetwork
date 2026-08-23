#!/bin/bash
# Resolve AI API domains → IPs for pfSense Firewall Alias (URL Table or manual paste).
# Also prints static CIDRs (Anthropic published inbound range).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAINS_FILE="${DOMAINS_FILE:-${SCRIPT_DIR}/domains.list}"
STATIC_CIDRS="${STATIC_CIDRS:-160.79.104.0/23}"

if [[ ! -f "${DOMAINS_FILE}" ]]; then
  echo "missing ${DOMAINS_FILE}" >&2
  exit 1
fi

TMP=$(mktemp)
trap 'rm -f "${TMP}"' EXIT

while read -r host || [[ -n "${host}" ]]; do
  [[ -z "${host}" || "${host}" =~ ^# ]] && continue
  host="${host#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1}' >> "${TMP}" || true
done < "${DOMAINS_FILE}"

{
  for cidr in ${STATIC_CIDRS//,/ }; do
    echo "${cidr}"
  done
  sort -u "${TMP}"
} | sort -u
