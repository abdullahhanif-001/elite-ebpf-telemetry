#!/usr/bin/env bash
# tier3-layered-simple.sh — load layered with bundled template.json.
set -euo pipefail
SCHED=layered
ROOT="${ELITE_SRC:-/opt/elite/src}"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}"
SDIR="${OUT}/schedulers/${SCHED}"
BIN=/opt/scx/target/release/scx_layered
pkill -9 -f '/opt/scx/target/release/scx_' 2>/dev/null || true
sleep 2
dmesg -C 2>/dev/null || true
"${BIN}" --run-example &
LP=$!
sleep 4
if ! kill -0 "${LP}" 2>/dev/null; then
  echo "${SCHED}=FAIL_LOAD" | tee "${SDIR}/verdict.txt"
  exit 1
fi
chrt -f 40 taskset -c 1 stress-ng --cpu 1 --timeout 20s &
SP=$!
sleep 25
kill "${SP}" "${LP}" 2>/dev/null || true
wait "${SP}" 2>/dev/null || true
dmesg > "${SDIR}/dmesg.txt"
if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' "${SDIR}/dmesg.txt"; then
  echo "${SCHED}=FAIL_LOADER" | tee "${SDIR}/verdict.txt"
  exit 1
fi
echo "${SCHED}=PASS_LOADER" | tee "${SDIR}/verdict.txt"
echo "TIER3_LAYERED_OK"
