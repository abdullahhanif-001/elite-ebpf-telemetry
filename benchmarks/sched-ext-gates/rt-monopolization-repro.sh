#!/usr/bin/env bash
# rt-monopolization-repro.sh — GitHub sched-ext/scx#1202 real reproduction.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST="${SCX_VPS_HOST}"
OUT="$(repo_root)/scripts/oneclick/results/rt-guard-baseline-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"

RUN_LOCAL="${RUN_LOCAL:-0}"
if [[ "${RUN_LOCAL}" == "0" ]] && [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]]; then
  RUN_LOCAL=1
fi

run_repro() {
  bash -s <<'REMOTE'
set -euo pipefail
export REAL_ONLY=1
dmesg -C 2>/dev/null || true

LOADER_PID=""
cleanup() {
  [[ -n "${LOADER_PID}" ]] && kill "${LOADER_PID}" 2>/dev/null || true
  pkill -f 'stress-ng.*matrixprod' 2>/dev/null || true
}
trap cleanup EXIT

if command -v scx_loader >/dev/null 2>&1; then
  scx_loader load bpfland &
  LOADER_PID=$!
  sleep 3
  echo "LOADER=bpfland pid=${LOADER_PID}"
else
  if [[ "${REAL_ONLY}" == "1" ]] && test -f "/boot/config-$(uname -r)" && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)"; then
    echo "FAIL: REAL_ONLY=1 requires scx_loader on sched_ext kernel" >&2
    exit 1
  fi
  echo "LOADER=SKIP (scx_loader missing — sched_ext kernel not ready)"
fi

if command -v stress-ng >/dev/null 2>&1; then
  chrt -f 40 taskset -c 1 stress-ng --cpu 1 --cpu-method matrixprod --timeout 15s &
  STRESS_PID=$!
  echo "RT_STRESS pid=${STRESS_PID}"
  sleep 20
  wait "${STRESS_PID}" 2>/dev/null || true
else
  echo "STRESS=SKIP (stress-ng missing)"
fi

dmesg | tail -80 > /tmp/rt-repro-dmesg.txt
if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' /tmp/rt-repro-dmesg.txt; then
  echo "STALL_DETECTED=YES"
  grep -E 'sched_ext|runnable task stall|SCX_EXIT' /tmp/rt-repro-dmesg.txt || true
else
  echo "STALL_DETECTED=NO"
fi
REMOTE
}

if [[ "${RUN_LOCAL}" -eq 1 ]]; then
  if ! test -f "/boot/config-$(uname -r)" || ! grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)"; then
    echo "WARN: sched_ext=NO — repro will capture baseline only (no scx_loader)"
  fi
  run_repro | tee "${OUT}/remote.log"
  cp /tmp/rt-repro-dmesg.txt "${OUT}/dmesg.txt" 2>/dev/null || echo "no dmesg captured" > "${OUT}/dmesg.txt"
else
  if ! ssh ${SCX_SSH_OPTS} "${HOST}" 'test -f /boot/config-$(uname -r) && grep -q ^CONFIG_SCHED_CLASS_EXT=y /boot/config-$(uname -r)'; then
    echo "WARN: sched_ext=NO — repro will capture baseline only (no scx_loader)"
  fi
  ssh ${SCX_SSH_OPTS} "${HOST}" bash -s <<'REMOTE' | tee "${OUT}/remote.log"
set -euo pipefail
export REAL_ONLY=1
dmesg -C 2>/dev/null || true
LOADER_PID=""
cleanup() { [[ -n "${LOADER_PID}" ]] && kill "${LOADER_PID}" 2>/dev/null || true; pkill -f 'stress-ng.*matrixprod' 2>/dev/null || true; }
trap cleanup EXIT
if command -v scx_loader >/dev/null 2>&1; then scx_loader load bpfland & LOADER_PID=$!; sleep 3; echo "LOADER=bpfland pid=${LOADER_PID}"; else echo "LOADER=SKIP"; fi
if command -v stress-ng >/dev/null 2>&1; then chrt -f 40 taskset -c 1 stress-ng --cpu 1 --cpu-method matrixprod --timeout 15s & STRESS_PID=$!; echo "RT_STRESS pid=${STRESS_PID}"; sleep 20; wait "${STRESS_PID}" 2>/dev/null || true; else echo "STRESS=SKIP"; fi
dmesg | tail -80 > /tmp/rt-repro-dmesg.txt
if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' /tmp/rt-repro-dmesg.txt; then echo "STALL_DETECTED=YES"; grep -E 'sched_ext|runnable task stall|SCX_EXIT' /tmp/rt-repro-dmesg.txt || true; else echo "STALL_DETECTED=NO"; fi
REMOTE
  scp ${SCX_SSH_OPTS} "${HOST}:/tmp/rt-repro-dmesg.txt" "${OUT}/dmesg.txt" 2>/dev/null || echo "no dmesg captured" > "${OUT}/dmesg.txt"
fi

{
  echo "RT_REPRO_CAPTURED"
  echo "host=${SCX_EXPECTED_HOST}"
  echo "out=${OUT}"
  grep -E 'STALL_DETECTED|LOADER|RT_STRESS' "${OUT}/remote.log" 2>/dev/null || true
} > "${OUT}/verdict.txt"

echo "RT_REPRO_CAPTURED out=${OUT}"
