#!/usr/bin/env bash
# rt-guard-flood-phase.sh — single SSH-safe phase runner (P1-P5).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

PHASE="${1:-}"
GATES_DIR="$(script_dir)"
ROOT="$(repo_root)"
export FLOOD_SAFE_MODE=1

if [[ -z "${PHASE}" ]]; then
  echo "Usage: $0 {gate|recovery|P1|P2|P3|P4|P4b|P5|P5b-<sched>|P6-<sched>|P7-<sched>}" >&2
  exit 1
fi

case "${PHASE}" in
  gate)
    exec bash "${GATES_DIR}/flood-safe-gate.sh"
    ;;
  recovery)
    exec bash "${GATES_DIR}/flood-safe-recovery.sh"
    ;;
esac

if [[ -z "${FLOOD_OUT:-}" ]]; then
  latest="$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)"
  if [[ -n "${latest}" && -f "${latest}/checkpoint.json" ]]; then
    export FLOOD_OUT="${latest}"
  else
    FLOOD_OUT="${ROOT}/scripts/oneclick/results/rt-guard-flood-safe-$(date +%Y%m%d-%H%M%S)"
    export FLOOD_OUT
  fi
fi
mkdir -p "${FLOOD_OUT}"

bash "${GATES_DIR}/flood-safe-gate.sh" || { flood_checkpoint_write "${PHASE}" "GATE_FAIL"; exit 1; }
flood_pm2_before

FAIL=0
case "${PHASE}" in
  P1)
    if FLOOD_OUT="${FLOOD_OUT}/ab-control" FLOOD_SAFE_MODE=1 bash "${GATES_DIR}/rt-guard-ab-control.sh"; then
      flood_checkpoint_write P1 PASS
    else
      flood_checkpoint_write P1 FAIL
      FAIL=1
    fi
    ;;
  P2)
    if FLOOD_OUT="${FLOOD_OUT}/negative-control" FLOOD_SAFE_MODE=1 bash "${GATES_DIR}/rt-guard-negative-control.sh"; then
      flood_checkpoint_write P2 PASS
    else
      flood_checkpoint_write P2 FAIL
      FAIL=1
    fi
    ;;
  P3)
    OUT="${FLOOD_OUT}/kselftests"
    mkdir -p "${OUT}"
    if flood_run_isolated_rt_stall "${OUT}/rt_stall.log"; then
      echo "RT_STALL_PASS" | tee "${OUT}/rt_stall.verdict"
    else
      echo "RT_STALL_FAIL" | tee "${OUT}/rt_stall.verdict"
      FAIL=1
    fi
    sleep "${FLOOD_COOLDOWN_SEC}"
    if flood_run_isolated_rt_guard_stress "${OUT}/rt_guard_stress.log"; then
      echo "RT_GUARD_STRESS_PASS" | tee "${OUT}/rt_guard_stress.verdict"
    else
      echo "RT_GUARD_STRESS_FAIL" | tee "${OUT}/rt_guard_stress.verdict"
      FAIL=1
    fi
    if [[ "${FAIL}" -eq 0 ]]; then
      echo "KSELFTEST_PASS fail=0" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P3 PASS
    else
      echo "KSELFTEST_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P3 FAIL
    fi
    ;;
  P4)
    OUT="${FLOOD_OUT}/edge-cases"
    mkdir -p "${OUT}"
    # E1: RT on CPU1
    dmesg -C 2>/dev/null || true
    sp="$(flood_rt_stress 1 20)"
    sleep 25
    kill "${sp}" 2>/dev/null || true
    wait "${sp}" 2>/dev/null || true
    dmesg > "${OUT}/E1-dmesg.txt"
    if flood_stall_in_dmesg; then
      echo "E1=FAIL" | tee "${OUT}/E1.log"
      FAIL=1
    else
      echo "E1=PASS" | tee "${OUT}/E1.log"
    fi
    sleep "${FLOOD_COOLDOWN_SEC}"
    # E3: multi-CPU RT (max 2 CPUs on 4vCPU VPS)
    dmesg -C 2>/dev/null || true
    chrt -f 40 stress-ng --cpu 2 --cpu-method matrixprod --timeout 20s &
    sp=$!
    sleep 25
    kill "${sp}" 2>/dev/null || true
    wait "${sp}" 2>/dev/null || true
    dmesg > "${OUT}/E3-dmesg.txt"
    if flood_stall_in_dmesg; then
      echo "E3=FAIL" | tee "${OUT}/E3.log"
      FAIL=1
    else
      echo "E3=PASS" | tee "${OUT}/E3.log"
    fi
    flood_pm2_after
    echo "E7=PASS PM2 baseline captured" | tee "${OUT}/E7.log"
    if [[ "${FAIL}" -eq 0 ]]; then
      echo "EDGE_LITE_PASS fail=0" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P4 PASS
    else
      echo "EDGE_LITE_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P4 FAIL
    fi
    ;;
  P5)
    OUT="${FLOOD_OUT}/schedulers"
    mkdir -p "${OUT}"
    JSON="${FLOOD_OUT}/scheduler-matrix.json"
    ftrace=no
    [[ -f /proc/sys/kernel/ftrace_enabled ]] && ftrace=yes
    layer3_ok=0
    p3_pass=0
    if [[ -f "${FLOOD_OUT}/checkpoint.json" ]]; then
      p3_pass="$(python3 -c "
import json
try:
  d=json.load(open('${FLOOD_OUT}/checkpoint.json'))
  print(1 if d.get('phases',{}).get('P3',{}).get('status')=='PASS' else 0)
except Exception:
  print(0)
" 2>/dev/null || echo 0)"
    fi
    if [[ "${p3_pass}" -eq 1 ]] && [[ -f "${FLOOD_OUT}/kselftests/rt_guard_stress.log" ]] && \
       grep -q '60s soak with RT+EXT' "${FLOOD_OUT}/kselftests/rt_guard_stress.log" 2>/dev/null; then
      layer3_ok=1
      echo "P5 layer3 from P3 kselftest (lite — skip duplicate 60s soak)" | tee "${OUT}/layer3-soak.log"
    elif flood_run_isolated_rt_guard_stress "${OUT}/layer3-soak.log"; then
      layer3_ok=1
    fi
    use_ftrace_loaders=0
    if [[ "${FLOOD_LITE_MODE:-0}" == "1" ]]; then
      use_ftrace_loaders=0
      echo "P5 lite mode — skip per-scheduler ftrace soaks (repro covered by P1/P3/tier1)" | tee -a "${OUT}/lite.log"
    elif [[ "${ftrace}" == "yes" ]]; then
      use_ftrace_loaders=1
    fi
    echo '{"mode":"'"$([[ "${FLOOD_LITE_MODE:-0}" == "1" ]] && echo lite_4vcpu || echo safe_4vcpu)"'","ftrace":"'"${ftrace}"'","schedulers":[' > "${JSON}"
    first=1
    for sched in "${FLOOD_SCHEDULERS[@]}"; do
      if [[ "${use_ftrace_loaders}" -eq 1 ]] && flood_sched_bin "${sched}" >/dev/null 2>&1; then
        sdir="${OUT}/${sched}"
        mkdir -p "${sdir}"
        if lp="$(flood_load_scheduler "${sched}" 2>/dev/null)"; then
          sp="$(flood_rt_stress 1 "${FLOOD_SOAK_SHORT_SEC}")"
          sleep $((FLOOD_SOAK_SHORT_SEC + 5))
          kill "${sp}" "${lp}" 2>/dev/null || true
          wait "${sp}" "${lp}" 2>/dev/null || true
          dmesg > "${sdir}/dmesg.txt"
          if flood_stall_in_dmesg; then result="FAIL"; FAIL=1; else result="PASS_LOADER"; fi
        else
          result="FAIL_LOADER"; FAIL=1
        fi
      elif [[ "${layer3_ok}" -eq 1 ]]; then
        result="PASS_KSELFTEST_FALLBACK"
      else
        result="FAIL_FALLBACK"; FAIL=1
      fi
      [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
      echo "{\"name\":\"${sched}\",\"result\":\"${result}\",\"ftrace\":\"${ftrace}\"}" >> "${JSON}"
      first=0
    done
    echo ']}' >> "${JSON}"
    flood_pm2_after
    if [[ "${FAIL}" -eq 0 ]]; then
      echo "SCHEDULER_LITE_PASS fail=0" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P5 PASS
    else
      echo "SCHEDULER_LITE_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write P5 FAIL
    fi
    ;;
  P4b)
    OUT="${FLOOD_OUT}/edge-cases-full"
    mkdir -p "${OUT}"
    export FLOOD_OUT="${OUT}"
    export FLOOD_SAFE_MODE=0
    if [[ -f /proc/sys/kernel/ftrace_enabled ]]; then
      if bash "${GATES_DIR}/rt-guard-edge-matrix.sh"; then
        flood_checkpoint_write P4b PASS
      else
        flood_checkpoint_write P4b FAIL
        FAIL=1
      fi
    else
      echo "P4b=SKIP ftrace=no — run Tier2 ftrace kernel first" | tee "${OUT}/P4b.log"
      flood_checkpoint_write P4b SKIP
    fi
    ;;
  P5b-*)
    sched="${PHASE#P5b-}"
    OUT="${FLOOD_OUT}/schedulers/${sched}"
    mkdir -p "${OUT}"
    export FLOOD_SAFE_MODE=0
    if [[ -f /proc/sys/kernel/ftrace_enabled ]] && flood_sched_bin "${sched}" >/dev/null 2>&1; then
      if lp="$(flood_load_scheduler "${sched}" 2>/dev/null)"; then
        sp="$(flood_rt_stress 1 "${FLOOD_STRESS_SEC:-15}")"
        sleep $((FLOOD_STRESS_SEC + 5))
        kill "${sp}" "${lp}" 2>/dev/null || true
        wait "${sp}" "${lp}" 2>/dev/null || true
        dmesg > "${OUT}/dmesg.txt"
        if flood_stall_in_dmesg; then
          echo "${sched}=FAIL_LOADER" | tee "${OUT}/verdict.txt"
          flood_checkpoint_write "${PHASE}" FAIL
          FAIL=1
        else
          echo "${sched}=PASS_LOADER" | tee "${OUT}/verdict.txt"
          flood_checkpoint_write "${PHASE}" PASS
        fi
      else
        echo "${sched}=FAIL_LOAD" | tee "${OUT}/verdict.txt"
        flood_checkpoint_write "${PHASE}" FAIL
        FAIL=1
      fi
    else
      echo "${sched}=SKIP_FTRACE" | tee "${OUT}/verdict.txt"
      flood_checkpoint_write "${PHASE}" SKIP
    fi
    ;;
  P6-*)
    sched="${PHASE#P6-}"
    OUT="${FLOOD_OUT}/endurance"
    mkdir -p "${OUT}"
    export FLOOD_SAFE_MODE=0
    if bash -c "
      source '${GATES_DIR}/flood-common.sh'
      export FLOOD_OUT='${OUT}'
      export FLOOD_SOAK_LONG_SEC=1800
      sdir='${OUT}/${sched}-30min'
      mkdir -p \"\${sdir}\"
      dmesg -C 2>/dev/null || true
      lp=\$(flood_load_scheduler '${sched}')
      sp=\$(flood_rt_stress 1 1800)
      elapsed=0
      while [[ \${elapsed} -lt 1800 ]]; do
        sleep 60
        elapsed=\$((elapsed+60))
        kill -0 \"\${lp}\" 2>/dev/null || { echo FAIL loader died; exit 1; }
        flood_stall_in_dmesg && { echo FAIL stall; exit 1; }
        echo OK elapsed=\${elapsed}s
      done
      kill \"\${sp}\" \"\${lp}\" 2>/dev/null || true
      echo '${sched}=PASS' >> '${OUT}/verdict.txt'
    "; then
      flood_checkpoint_write "${PHASE}" PASS
    else
      echo "${sched}=FAIL" >> "${OUT}/verdict.txt"
      flood_checkpoint_write "${PHASE}" FAIL
      FAIL=1
    fi
    ;;
  P7-*)
    sched="${PHASE#P7-}"
    OUT="${FLOOD_OUT}/endurance"
    mkdir -p "${OUT}"
    export FLOOD_SAFE_MODE=0
    if bash -c "
      source '${GATES_DIR}/flood-common.sh'
      export FLOOD_OUT='${OUT}'
      export FLOOD_SOAK_LONG_SEC=1800
      sdir='${OUT}/${sched}-30min'
      mkdir -p \"\${sdir}\"
      dmesg -C 2>/dev/null || true
      lp=\$(flood_load_scheduler '${sched}')
      sp=\$(flood_rt_stress 1 1800)
      elapsed=0
      while [[ \${elapsed} -lt 1800 ]]; do
        sleep 60
        elapsed=\$((elapsed+60))
        kill -0 \"\${lp}\" 2>/dev/null || { echo FAIL loader died; exit 1; }
        flood_stall_in_dmesg && { echo FAIL stall; exit 1; }
        echo OK elapsed=\${elapsed}s
      done
      kill \"\${sp}\" \"\${lp}\" 2>/dev/null || true
      echo '${sched}=PASS' >> '${OUT}/verdict.txt'
    "; then
      flood_checkpoint_write "${PHASE}" PASS
    else
      echo "${sched}=FAIL" >> "${OUT}/verdict.txt"
      flood_checkpoint_write "${PHASE}" FAIL
      FAIL=1
    fi
    ;;
  *)
    echo "Unknown phase: ${PHASE}" >&2
    exit 1
    ;;
esac

flood_pm2_after
echo "ssh_ok phase=${PHASE} out=${FLOOD_OUT}"
[[ "${FAIL}" -eq 0 ]] || exit 1
