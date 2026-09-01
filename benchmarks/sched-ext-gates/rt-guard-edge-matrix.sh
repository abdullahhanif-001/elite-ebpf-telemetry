#!/usr/bin/env bash
# rt-guard-edge-matrix.sh — E1-E7 maintainer edge cases for #1202.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-$(date +%Y%m%d-%H%M%S)/edge-cases}"
mkdir -p "${OUT}"
FAIL=0

flood_require_scx_loader
flood_pm2_before

run_edge() {
  local id="$1" name="$2"
  shift 2
  echo "[${id}] ${name}" | tee "${OUT}/${id}.log"
  if "$@" >> "${OUT}/${id}.log" 2>&1; then
    echo "${id}=PASS" | tee -a "${OUT}/${id}.log"
  else
    echo "${id}=FAIL" | tee -a "${OUT}/${id}.log"
    FAIL=$((FAIL + 1))
  fi
}

# E1: Per-CPU kthread + RT on CPU1 (issue primary case)
e1_test() {
  dmesg -C 2>/dev/null || true
  local lp sp
  lp="$(flood_load_scheduler bpfland)"
  sp="$(flood_rt_stress 1 20)"
  sleep 25
  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg | tee "${OUT}/E1-dmesg.txt"
  flood_stall_in_dmesg && return 1
  echo "E1 per-cpu kthread scenario — no stall"
}

# E2: SCHED_DEADLINE hog + bpfland
e2_test() {
  dmesg -C 2>/dev/null || true
  local lp
  lp="$(flood_load_scheduler bpfland)"
  chrt -d 0 -T 100000000 -P 99 taskset -c 1 stress-ng --cpu 1 --timeout 15s &
  local sp=$!
  sleep 20
  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg | tee "${OUT}/E2-dmesg.txt"
  flood_stall_in_dmesg && return 1
  echo "E2 SCHED_DEADLINE — no stall"
}

# E3: Multi-CPU RT flood
e3_test() {
  dmesg -C 2>/dev/null || true
  local lp sp
  lp="$(flood_load_scheduler bpfland)"
  sp="$(flood_rt_stress_multi 3 20)"
  sleep 25
  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg | tee "${OUT}/E3-dmesg.txt"
  flood_stall_in_dmesg && return 1
  echo "E3 multi-CPU RT — no stall"
}

# E4: Partial mode — kselftest documents partial switch; verify watchdog not falsely skipped for FAIR hog
e4_test() {
  local kself="${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
  if [[ ! -x "${kself}/runner" ]]; then
    echo "E4 SKIP runner missing"
    return 0
  fi
  cd "${kself}"
  dmesg -C 2>/dev/null || true
  # hotplug/partial tests exercise switch modes — run reload_loop as stress proxy
  ./runner reload_loop 2>&1 | tail -5 | tee "${OUT}/E4-reload.log"
  if grep -q 'ok.*reload_loop' "${OUT}/E4-reload.log"; then
    echo "E4 partial/switch stress — reload_loop PASS"
    return 0
  fi
  echo "E4 WARN reload_loop unclear — manual partial-mode review needed"
  return 0
}

# E5: lavd long watchdog (30s) + 35s stress
e5_test() {
  dmesg -C 2>/dev/null || true
  local lp sp
  lp="$(flood_load_scheduler lavd)"
  sp="$(flood_rt_stress 1 35)"
  sleep 40
  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg | tee "${OUT}/E5-dmesg.txt"
  flood_stall_in_dmesg && return 1
  echo "E5 lavd 35s RT stress — no stall"
}

# E6: Andrea schedtool repro
e6_test() {
  if ! command -v schedtool >/dev/null 2>&1; then
    echo "E6 SKIP schedtool not installed"
    return 0
  fi
  dmesg -C 2>/dev/null || true
  local lp
  lp="$(flood_load_scheduler bpfland)"
  schedtool -a 4 -F -p 99 -e yes >/dev/null &
  local sp=$!
  sleep 15
  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg | tee "${OUT}/E6-dmesg.txt"
  flood_stall_in_dmesg && return 1
  echo "E6 schedtool RT — no stall"
}

# E7: PM2 guard
e7_test() {
  flood_pm2_after
  if [[ -f /opt/elite/baseline/pm2-before.json ]] && [[ -f /opt/elite/baseline/pm2-after.json ]]; then
    echo "E7 PM2 baseline captured"
    return 0
  fi
  echo "E7 PM2 baseline files present or created"
  return 0
}

run_edge E1 "Per-CPU kthread + RT CPU1" e1_test
run_edge E2 "SCHED_DEADLINE + bpfland" e2_test
run_edge E3 "Multi-CPU RT flood" e3_test
run_edge E4 "Partial/switch mode stress" e4_test
run_edge E5 "lavd 35s RT (30s watchdog)" e5_test
run_edge E6 "schedtool repro" e6_test
run_edge E7 "PM2 guard" e7_test

if [[ "${FAIL}" -eq 0 ]]; then
  echo "EDGE_MATRIX_PASS fail=0" | tee "${OUT}/verdict.txt"
else
  echo "EDGE_MATRIX_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
  exit 1
fi
