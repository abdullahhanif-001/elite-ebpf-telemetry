#!/usr/bin/env bash
# vps-resource-guard.sh — abort proofs when 4vCPU/8GB VPS is under pressure.
# Exit 0 = safe to proceed; exit 1 = abort (do not start next lane).
set -euo pipefail

MIN_MEM_KB="${ELITE_MIN_MEM_KB:-4194304}"   # 4 GiB
MAX_LOAD="${ELITE_MAX_LOAD:-3.0}"
COOLDOWN_SEC="${ELITE_GUARD_COOLDOWN_SEC:-0}"

if [[ "${COOLDOWN_SEC}" -gt 0 ]]; then
  sleep "${COOLDOWN_SEC}"
fi

avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
load1="$(cut -d' ' -f1 /proc/loadavg)"

echo "RESOURCE_GUARD mem_available_kb=${avail_kb} min_kb=${MIN_MEM_KB} load1=${load1} max_load=${MAX_LOAD}"

if [[ -z "${avail_kb}" ]] || [[ "${avail_kb}" -lt "${MIN_MEM_KB}" ]]; then
  echo "RESOURCE_GUARD_ABORT low_mem available_kb=${avail_kb}"
  exit 1
fi

# bash float compare via awk
if awk -v l="${load1}" -v m="${MAX_LOAD}" 'BEGIN { exit !(l+0 > m+0) }'; then
  echo "RESOURCE_GUARD_ABORT high_load load1=${load1}"
  exit 1
fi

echo "RESOURCE_GUARD_OK"
exit 0
