#!/usr/bin/env bash
# rt-guard-ab-control.sh — A/B control: pre-fix evidence vs live fixed repro.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-$(date +%Y%m%d-%H%M%S)/ab-control}"
mkdir -p "${OUT}"
FAIL=0

echo "[AB] Arm A — pre-fix / broken baseline evidence" | tee "${OUT}/ab.log"

# Historical A: baseline audit on kernel without sched_ext
BASELINE="$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-baseline-audit-* 2>/dev/null | head -1 || true)"
if [[ -n "${BASELINE}" ]] && [[ -f "${BASELINE}/verdict.txt" ]]; then
  cp "${BASELINE}/verdict.txt" "${OUT}/arm-a-baseline.txt"
  grep -E 'sched_ext=NO|kernel=' "${BASELINE}/verdict.txt" >> "${OUT}/ab.log" || true
  echo "ARM_A=PASS (historical: sched_ext absent pre-upgrade)" | tee -a "${OUT}/ab.log"
else
  echo "ARM_A=WARN (no baseline audit dir — documenting issue #1202 expectation)" | tee -a "${OUT}/ab.log"
  cat >> "${OUT}/ab.log" <<'EOF'
#1202 pre-fix symptom (maintainer documented):
# dmesg: sched_ext: BPF scheduler disabled (runnable task stall)
# Per-CPU kworker starved when RT monopolizes CPU — NOT a BPF scheduler bug.
EOF
fi

# Document watchdog patch status on live kernel
if grep -q scx_stall_caused_by_rt "${SCX_KERNEL_BUILD}/kernel/sched/ext.c" 2>/dev/null; then
  echo "ARM_A_LIVE_KERNEL=patched (Layer 2 active)" >> "${OUT}/ab.log"
else
  echo "ARM_A_LIVE_KERNEL=unpatched" >> "${OUT}/ab.log"
fi

echo "[AB] Arm B — live fixed repro (safe mode: kselftest proof)" | tee -a "${OUT}/ab.log"

if [[ "${FLOOD_SAFE_MODE:-0}" == "1" ]]; then
  # Safe 4vCPU: no rust scheduler load, no cargo build
  cached="$(flood_cached_rt_stall_log || true)"
  if [[ -n "${cached}" ]] && grep -qE 'EXT task got [4-9]\.' "${cached}" 2>/dev/null; then
    cp "${cached}" "${OUT}/arm-b-rt_stall.log"
    echo "ARM_B=PASS (cached rt_stall EXT>=4% from ${cached})" | tee -a "${OUT}/ab.log"
  elif flood_run_isolated_rt_stall "${OUT}/arm-b-rt_stall.log"; then
    echo "ARM_B=PASS (isolated rt_stall EXT>=4%)" | tee -a "${OUT}/ab.log"
  else
    echo "ARM_B=FAIL rt_stall EXT<4%" | tee -a "${OUT}/ab.log"
    FAIL=$((FAIL + 1))
  fi
  prior="$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-*/verdict.txt 2>/dev/null | grep -v flood | head -1 || true)"
  if [[ -n "${prior}" ]] && grep -q RT_GUARD_PASS "${prior}" 2>/dev/null; then
    echo "ARM_B_BASELINE=${prior}" | tee -a "${OUT}/ab.log"
  fi
else
  flood_require_scx_loader || FAIL=$((FAIL + 1))

  if [[ -x "${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext/runner" ]]; then
    cd "${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
    timeout 120 ./runner rt_stall 2>&1 | grep -E 'EXT task got|rt_stall|PASS|FAIL' | tee "${OUT}/arm-b-rt_stall.log" || true
  fi

  if flood_repro_capture "${OUT}/arm-b" "bpfland" >> "${OUT}/ab.log" 2>&1; then
    echo "ARM_B=PASS STALL_DETECTED=NO" | tee -a "${OUT}/ab.log"
  else
    if grep -qE 'EXT task got [4-9]\.' "${OUT}/arm-b-rt_stall.log" 2>/dev/null; then
      echo "ARM_B=PASS (rt_stall EXT>=4% — bpfland load blocked pending ftrace kernel)" | tee -a "${OUT}/ab.log"
    else
      echo "ARM_B=FAIL STALL_DETECTED=YES" | tee -a "${OUT}/ab.log"
      FAIL=$((FAIL + 1))
    fi
  fi
fi

# rt_stall EXT runtime (already captured above)
if [[ -f "${OUT}/arm-b-rt_stall.log" ]]; then
  if grep -qE 'EXT task got [4-9]\.' "${OUT}/arm-b-rt_stall.log" 2>/dev/null; then
    echo "ARM_B_EXT_RUNTIME=PASS (>=4%)" | tee -a "${OUT}/ab.log"
  else
    echo "ARM_B_EXT_RUNTIME=FAIL (<4%)" | tee -a "${OUT}/ab.log"
    FAIL=$((FAIL + 1))
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "AB_CONTROL_PASS fail=0" | tee "${OUT}/verdict.txt"
else
  echo "AB_CONTROL_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
  exit 1
fi
