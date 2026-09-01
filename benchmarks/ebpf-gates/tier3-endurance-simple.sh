#!/usr/bin/env bash
# tier3-endurance-simple.sh — 5min soak (VPS-safe; use 1800 for full H7).
set -euo pipefail
SCHED="${1:-bpfland}"
SEC="${2:-300}"
BIN="/opt/scx/target/release/scx_${SCHED}"
OUT="${FLOOD_OUT:-/opt/elite/src/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}/endurance"
SDIR="${OUT}/${SCHED}-${SEC}s"
mkdir -p "${SDIR}"
pkill -9 -f "/opt/scx/target/release/scx_" 2>/dev/null || true
sleep 2
dmesg -C 2>/dev/null || true
"${BIN}" &
LP=$!
sleep 4
chrt -f 40 taskset -c 1 stress-ng --cpu 1 --cpu-method matrixprod --timeout "${SEC}s" &
SP=$!
elapsed=0
while [[ "${elapsed}" -lt "${SEC}" ]]; do
  sleep 60
  elapsed=$((elapsed+60))
  kill -0 "${LP}" 2>/dev/null || { echo FAIL loader died; exit 1; }
  dmesg | grep -qE 'SCX_EXIT_ERROR_STALL|runnable task stall' && { echo FAIL stall; exit 1; }
  echo OK elapsed=${elapsed}s
done
kill "${SP}" "${LP}" 2>/dev/null || true
echo "${SCHED}=PASS" >> "${OUT}/verdict.txt"
echo "ENDURANCE_OK sched=${SCHED} sec=${SEC}"
