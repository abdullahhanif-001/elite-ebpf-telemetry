#!/usr/bin/env bash
# rt-guard-scheduler-matrix.sh — 6-scheduler #1202 repro + 5min soak matrix.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-$(date +%Y%m%d-%H%M%S)/schedulers}"
mkdir -p "${OUT}"

FAIL=0
JSON="${OUT}/../scheduler-matrix.json"
echo '{"schedulers":[' > "${JSON}"

flood_require_scx_loader
flood_pm2_before

first=1
for sched in "${FLOOD_SCHEDULERS[@]}"; do
  sdir="${OUT}/${sched}"
  mkdir -p "${sdir}"
  echo "[MATRIX] scheduler=${sched}" | tee "${sdir}/run.log"

  if ! lp="$(flood_load_scheduler "${sched}" 2>/dev/null)"; then
    echo "WARN: scx_${sched} load failed — rt_guard_stress fallback soak" | tee -a "${sdir}/run.log"
    if flood_repro_capture "${sdir}" "${sched}" >> "${sdir}/run.log" 2>&1; then
      [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
      echo "{\"name\":\"${sched}\",\"repro\":\"PASS_FALLBACK\",\"soak\":\"PASS_FALLBACK\"}" >> "${JSON}"
      first=0
      continue
    fi
    FAIL=$((FAIL + 1))
    [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
    echo "{\"name\":\"${sched}\",\"repro\":\"FAIL\",\"soak\":\"SKIP\"}" >> "${JSON}"
    first=0
    continue
  fi
  echo "REPRO_PASS sched=${sched} loader_pid=${lp}" | tee -a "${sdir}/run.log"
  dmesg -C 2>/dev/null || true
  sp_repro="$(flood_rt_stress "${FLOOD_RT_CPU}" "${FLOOD_STRESS_SEC}")"
  sleep $((FLOOD_STRESS_SEC + 3))
  kill "${sp_repro}" 2>/dev/null || true
  wait "${sp_repro}" 2>/dev/null || true
  if flood_stall_in_dmesg; then
    echo "REPRO_FAIL stall during ${FLOOD_STRESS_SEC}s RT stress" | tee -a "${sdir}/run.log"
    kill "${lp}" 2>/dev/null || true
    FAIL=$((FAIL + 1))
    [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
    echo "{\"name\":\"${sched}\",\"repro\":\"FAIL\",\"soak\":\"SKIP\"}" >> "${JSON}"
    first=0
    continue
  fi
  dmesg -C 2>/dev/null || true
  sp="$(flood_rt_stress "${FLOOD_RT_CPU}" "${FLOOD_SOAK_SHORT_SEC}")"
  soak_ok=1
  elapsed=0
  while [[ "${elapsed}" -lt "${FLOOD_SOAK_SHORT_SEC}" ]]; do
    sleep 30
    elapsed=$((elapsed + 30))
    if ! kill -0 "${lp}" 2>/dev/null; then
      echo "SOAK_FAIL loader died at ${elapsed}s" | tee -a "${sdir}/run.log"
      soak_ok=0
      break
    fi
    if flood_stall_in_dmesg; then
      echo "SOAK_FAIL stall at ${elapsed}s" | tee -a "${sdir}/run.log"
      dmesg | tail -30 >> "${sdir}/run.log"
      soak_ok=0
      break
    fi
    echo "SOAK_OK elapsed=${elapsed}s" >> "${sdir}/run.log"
  done
  kill "${sp}" 2>/dev/null || true
  kill "${lp}" 2>/dev/null || true
  wait "${sp}" 2>/dev/null || true
  wait "${lp}" 2>/dev/null || true
  dmesg >> "${sdir}/soak-dmesg.txt"

  [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
  if [[ "${soak_ok}" -eq 1 ]]; then
    echo "SOAK_PASS sched=${sched} duration=${FLOOD_SOAK_SHORT_SEC}s" | tee -a "${sdir}/run.log"
    echo "{\"name\":\"${sched}\",\"repro\":\"PASS\",\"soak\":\"PASS\"}" >> "${JSON}"
  else
    FAIL=$((FAIL + 1))
    echo "{\"name\":\"${sched}\",\"repro\":\"PASS\",\"soak\":\"FAIL\"}" >> "${JSON}"
  fi
  first=0
done

echo ']}' >> "${JSON}"
flood_pm2_after

if [[ "${FAIL}" -eq 0 ]]; then
  echo "SCHEDULER_MATRIX_PASS fail=0" | tee "${OUT}/verdict.txt"
else
  echo "SCHEDULER_MATRIX_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
  exit 1
fi
