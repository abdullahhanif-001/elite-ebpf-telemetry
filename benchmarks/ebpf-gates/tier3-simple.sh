#!/usr/bin/env bash
# tier3-simple.sh — one scheduler real loader test (simple, no subshell hang).
set -euo pipefail
SCHED="${1:?sched name e.g. bpfland}"
ROOT="${ELITE_SRC:-/opt/elite/src}"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}"
SDIR="${OUT}/schedulers/${SCHED}"
mkdir -p "${SDIR}"
BIN="/opt/scx/target/release/scx_${SCHED}"
source "${ROOT}/benchmarks/ebpf-gates/our-goal-log.sh" 2>/dev/null || true

echo "=== tier3-simple sched=${SCHED} ==="
dmesg -C 2>/dev/null || true
"${BIN}" &
LP=$!
sleep 4
if ! kill -0 "${LP}" 2>/dev/null; then
  echo "${SCHED}=FAIL_LOAD" | tee "${SDIR}/verdict.txt"
  our_goal_log "P5b-${SCHED}" "FAIL" "${SDIR}/verdict.txt" "loader died" 2>/dev/null || true
  exit 1
fi
chrt -f 40 taskset -c 1 stress-ng --cpu 1 --cpu-method matrixprod --timeout 20s &
SP=$!
sleep 25
kill "${SP}" "${LP}" 2>/dev/null || true
pkill -9 -f "/opt/scx/target/release/scx_${SCHED}" 2>/dev/null || true
wait "${SP}" 2>/dev/null || true
dmesg > "${SDIR}/dmesg.txt"
if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' "${SDIR}/dmesg.txt"; then
  echo "${SCHED}=FAIL_LOADER" | tee "${SDIR}/verdict.txt"
  our_goal_log "P5b-${SCHED}" "FAIL" "${SDIR}/verdict.txt" "stall dmesg" 2>/dev/null || true
  exit 1
fi
echo "${SCHED}=PASS_LOADER" | tee "${SDIR}/verdict.txt"
our_goal_log "P5b-${SCHED}" "PASS" "${SDIR}/verdict.txt" "ftrace loader OK" 2>/dev/null || true
echo "TIER3_SIMPLE_OK sched=${SCHED}"
