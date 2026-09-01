#!/usr/bin/env bash
# rt-guard-endurance.sh — Tier-1 30min soaks for bpfland + lavd.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-$(date +%Y%m%d-%H%M%S)/endurance}"
mkdir -p "${OUT}"
FAIL=0
DURATION="${FLOOD_SOAK_LONG_SEC:-1800}"

flood_require_scx_loader
flood_pm2_before

endurance_soak() {
  local sched="$1"
  local sdir="${OUT}/${sched}-30min"
  mkdir -p "${sdir}"
  echo "[ENDURANCE] sched=${sched} duration=${DURATION}s" | tee "${sdir}/soak.log"

  dmesg -C 2>/dev/null || true
  local lp sp elapsed=0
  lp="$(flood_load_scheduler "${sched}")"
  sp="$(flood_rt_stress "${FLOOD_RT_CPU}" "${DURATION}")"

  while [[ "${elapsed}" -lt "${DURATION}" ]]; do
    sleep 60
    elapsed=$((elapsed + 60))
    if ! kill -0 "${lp}" 2>/dev/null; then
      echo "FAIL loader died at ${elapsed}s" | tee -a "${sdir}/soak.log"
      dmesg >> "${sdir}/dmesg.txt"
      return 1
    fi
    if flood_stall_in_dmesg; then
      echo "FAIL stall at ${elapsed}s" | tee -a "${sdir}/soak.log"
      dmesg | tail -40 >> "${sdir}/soak.log"
      dmesg >> "${sdir}/dmesg.txt"
      return 1
    fi
    echo "OK elapsed=${elapsed}s loader_pid=${lp}" >> "${sdir}/soak.log"
  done

  kill "${sp}" "${lp}" 2>/dev/null || true
  wait "${sp}" "${lp}" 2>/dev/null || true
  dmesg >> "${sdir}/dmesg.txt"
  echo "ENDURANCE_PASS sched=${sched} duration=${DURATION}s" | tee -a "${sdir}/soak.log"
  return 0
}

for sched in bpfland lavd; do
  if endurance_soak "${sched}"; then
    echo "${sched}=PASS" >> "${OUT}/verdict.txt"
  else
    echo "${sched}=FAIL" >> "${OUT}/verdict.txt"
    FAIL=$((FAIL + 1))
  fi
done

flood_pm2_after

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ENDURANCE_PASS fail=0 duration=${DURATION}s" >> "${OUT}/verdict.txt"
else
  echo "ENDURANCE_FAIL fail=${FAIL}" >> "${OUT}/verdict.txt"
  exit 1
fi
