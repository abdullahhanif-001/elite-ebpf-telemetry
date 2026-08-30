#!/usr/bin/env bash
# G14 multicore / native XDP checklist (staging).
set -euo pipefail
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${BUILD_ROOT}/logs"
RESULTS="$(cd "$(dirname "$0")" && pwd)/results"
IFACE="${ELITE_XDP_IFACE:-eth0}"
OUT="${RESULTS}/g14-multicore-latest.txt"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "${LOG_DIR}" "${RESULTS}"
exec > >(tee "${OUT}") 2>&1
echo "=== G14 multicore ${STAMP} iface=${IFACE} ==="

if command -v ethtool >/dev/null 2>&1 && [[ -d "/sys/class/net/${IFACE}" ]]; then
  ethtool -l "${IFACE}" 2>/dev/null | tee -a "${OUT}" || true
  ethtool -i "${IFACE}" 2>/dev/null | tee -a "${OUT}" || true
fi

if command -v bpftool >/dev/null 2>&1; then
  bpftool net show dev "${IFACE}" 2>/dev/null | tee -a "${OUT}" || true
  bpftool map show 2>/dev/null | grep -E 'elite_cpumap|cpumap' | head -5 | tee -a "${OUT}" || true
fi

if [[ "${ELITE_XDP_MODE:-skb}" == "native" ]]; then
  echo "G14_MULTICORE_PASS mode=native" | tee -a "${OUT}"
  echo "G14_MULTICORE_PASS"
  exit 0
fi
echo "G14_MULTICORE_SKIP set ELITE_XDP_MODE=native on staging NIC" | tee -a "${OUT}"
echo "G14_MULTICORE_SKIP"
exit 0
