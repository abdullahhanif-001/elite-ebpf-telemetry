#!/usr/bin/env bash
# tier3-repro-simple.sh — H5 repro with direct bpfland loader (no scx_loader).
set -euo pipefail
OUT="${FLOOD_OUT:-/opt/elite/src/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}/repro"
mkdir -p "${OUT}"
BIN=/opt/scx/target/release/scx_bpfland
pkill -9 -f '/opt/scx/target/release/scx_' 2>/dev/null || true
sleep 2
dmesg -C 2>/dev/null || true
"${BIN}" &
LP=$!
sleep 3
echo "LOADER=bpfland pid=${LP}" | tee "${OUT}/repro.log"
chrt -f 40 taskset -c 1 stress-ng --cpu 1 --cpu-method matrixprod --timeout 15s &
SP=$!
sleep 20
kill "${SP}" "${LP}" 2>/dev/null || true
wait "${SP}" 2>/dev/null || true
dmesg | tail -80 > "${OUT}/dmesg.txt"
if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' "${OUT}/dmesg.txt"; then
  echo "STALL_DETECTED=YES" | tee -a "${OUT}/repro.log"
  exit 1
fi
echo "STALL_DETECTED=NO" | tee -a "${OUT}/repro.log"
echo "LOADER_OK bpfland" | tee -a "${OUT}/repro.log"
echo "REPRO_SIMPLE_PASS"
