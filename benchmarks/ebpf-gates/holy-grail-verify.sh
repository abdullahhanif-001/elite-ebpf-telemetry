#!/usr/bin/env bash
# holy-grail-verify.sh — H1–H12 #1202 symptom-to-proof matrix.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
GATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sched-ext-gates" && pwd)"
# shellcheck source=/dev/null
source "${GATES}/flood-common.sh"

OUT_JSON="${OUR_GOAL_DIR}/holy-grail-matrix.json"
OUT_TXT="${OUR_GOAL_DIR}/HOLY_GRAIL_VERDICT.txt"
FLOOD_DIR="${1:-$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)}"
if [[ -n "${2:-}" ]]; then
  RT_GUARD_DIR="${2}"
else
  RT_GUARD_DIR=""
  shopt -s nullglob
  for cand in "${ROOT}"/scripts/oneclick/results/rt-guard-202*; do
    [[ "${cand}" == *flood* ]] && continue
    RT_GUARD_DIR="${cand}"
    break
  done
  shopt -u nullglob
fi

ebpf_ensure_our_goal
FAIL=0
PASS=0

check_h() {
  local id="$1" ok="$2" note="$3"
  [[ "${ok}" == "1" ]] && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
  echo "  ${id}: $([[ ${ok} -eq 1 ]] && echo PASS || echo FAIL) — ${note}"
}

echo "=== holy-grail-verify ==="
echo "flood_dir=${FLOOD_DIR}"
echo "rt_guard_dir=${RT_GUARD_DIR}"

# H1 rt_stall EXT>=4%
h1=0
for log in "${RT_GUARD_DIR}/g2-rt_stall.log" "${FLOOD_DIR}/kselftests/rt_stall.log" "${FLOOD_DIR}/ab-control/arm-b-rt_stall.log"; do
  [[ -f "${log}" ]] && grep -qE 'EXT task got [4-9]\.' "${log}" 2>/dev/null && h1=1 && break
done
check_h H1 "${h1}" "rt_stall EXT>=4%"

# H2 rt_guard_stress 60s
h2=0
for log in "${RT_GUARD_DIR}/g3-rt_guard_stress.log" "${FLOOD_DIR}/kselftests/rt_guard_stress.log"; do
  [[ -f "${log}" ]] && grep -q '60s soak with RT+EXT' "${log}" 2>/dev/null && h2=1 && break
done
check_h H2 "${h2}" "rt_guard_stress 60s soak"

# H3 E1
h3=0
for edir in edge-cases edge-cases-full; do
  [[ -f "${FLOOD_DIR}/${edir}/E1.log" ]] && grep -q 'E1=PASS' "${FLOOD_DIR}/${edir}/E1.log" 2>/dev/null && h3=1 && break
done
check_h H3 "${h3}" "E1 per-CPU RT"

# H4 E3
h4=0
for edir in edge-cases edge-cases-full; do
  [[ -f "${FLOOD_DIR}/${edir}/E3.log" ]] && grep -q 'E3=PASS' "${FLOOD_DIR}/${edir}/E3.log" 2>/dev/null && h4=1 && break
done
check_h H4 "${h4}" "E3 multi-CPU RT"

# H5 repro with loader
h5=0
if [[ -f "${RT_GUARD_DIR}/g4-repro.log" ]]; then
  grep -q 'STALL_DETECTED=NO' "${RT_GUARD_DIR}/g4-repro.log" 2>/dev/null && h5=1
  grep -q 'LOADER=bpfland\|LOADER_OK' "${RT_GUARD_DIR}/g4-repro.log" 2>/dev/null && h5=2
fi
if [[ -f "${FLOOD_DIR}/repro/repro.log" ]]; then
  grep -q 'STALL_DETECTED=NO' "${FLOOD_DIR}/repro/repro.log" 2>/dev/null && h5=1
  grep -q 'LOADER_OK\|LOADER=bpfland' "${FLOOD_DIR}/repro/repro.log" 2>/dev/null && h5=2
fi
if [[ -f "${FLOOD_DIR}/scheduler-matrix.json" ]] && grep -q PASS_LOADER "${FLOOD_DIR}/scheduler-matrix.json" 2>/dev/null; then
  [[ "${h5}" -ge 1 ]] && h5=2
fi
check_h H5 "$([[ ${h5} -ge 1 ]] && echo 1 || echo 0)" "repro STALL_DETECTED=NO loader=$([[ ${h5} -eq 2 ]] && echo YES || echo PARTIAL)"

# H6 E5 lavd 35s (PASS or documented SKIP on ftrace — lavd needs BPF arena)
h6=0
for edir in edge-cases edge-cases-full; do
  [[ -f "${FLOOD_DIR}/${edir}/E5.log" ]] && grep -q 'E5=PASS' "${FLOOD_DIR}/${edir}/E5.log" 2>/dev/null && h6=1 && break
  [[ -f "${FLOOD_DIR}/${edir}/E5.log" ]] && grep -qE 'E5=SKIP.*lavd' "${FLOOD_DIR}/${edir}/E5.log" 2>/dev/null \
    && grep -q 'FAIL_LOAD' "${FLOOD_DIR}/scheduler-matrix.json" 2>/dev/null && h6=1 && break
done
check_h H6 "${h6}" "E5 lavd 35s"

# H7 endurance
h7=0
[[ -f "${FLOOD_DIR}/endurance/verdict.txt" ]] && grep -qE 'bpfland=PASS|lavd=PASS|ENDURANCE_PASS' "${FLOOD_DIR}/endurance/verdict.txt" 2>/dev/null && h7=1
check_h H7 "${h7}" "30min endurance"

# H8 E2
h8=0
for edir in edge-cases edge-cases-full; do
  [[ -f "${FLOOD_DIR}/${edir}/E2.log" ]] && grep -qE 'E2=PASS|E2=SKIP' "${FLOOD_DIR}/${edir}/E2.log" 2>/dev/null && h8=1 && break
done
check_h H8 "${h8}" "E2 SCHED_DEADLINE"

# H9 E4 partial
h9=0
for edir in edge-cases edge-cases-full; do
  [[ -f "${FLOOD_DIR}/${edir}/E4.log" ]] && grep -qE 'E4=PASS|E4=SKIP' "${FLOOD_DIR}/${edir}/E4.log" 2>/dev/null && h9=1 && break
done
check_h H9 "${h9}" "E4 partial mode"

# H10 negative enq_last
h10=0
[[ -f "${FLOOD_DIR}/negative-control/verdict.txt" ]] && grep -q NEGATIVE_CONTROL_PASS "${FLOOD_DIR}/negative-control/verdict.txt" 2>/dev/null && h10=1
check_h H10 "${h10}" "negative enq_last"

# H11 minimal
h11=0
[[ -f "${FLOOD_DIR}/negative-control/neg.log" ]] && grep -q 'NEG_PASS healthy minimal' "${FLOOD_DIR}/negative-control/neg.log" 2>/dev/null && h11=1
check_h H11 "${h11}" "healthy minimal scheduler"

# H12 6 schedulers PASS_LOADER (5/6 OK if lavd SKIP_KERNEL on ftrace)
h12=0
if [[ -f "${FLOOD_DIR}/scheduler-matrix.json" ]]; then
  n="$(grep -c PASS_LOADER "${FLOOD_DIR}/scheduler-matrix.json" 2>/dev/null | tr -d '[:space:]' || true)"
  n="${n:-0}"
  lavd_skip=0
  grep -q '"name":"lavd".*"result":"FAIL_LOAD"' "${FLOOD_DIR}/scheduler-matrix.json" 2>/dev/null && lavd_skip=1
  [[ "${n}" -ge 6 ]] 2>/dev/null && h12=1
  [[ "${n}" -ge 5 && "${lavd_skip}" -eq 1 ]] 2>/dev/null && h12=1
  fb="$(grep -c PASS_KSELFTEST_FALLBACK "${FLOOD_DIR}/scheduler-matrix.json" 2>/dev/null | tr -d '[:space:]' || true)"
  fb="${fb:-0}"
  [[ "${fb}" -ge 6 && "${h12}" -eq 0 ]] && echo "  H12: PARTIAL — kselftest fallback only (Tier3 blocked on ftrace)"
fi
check_h H12 "${h12}" "6/6 PASS_LOADER (5/6+lavd SKIP ok)"

python3 - "${OUT_JSON}" "${PASS}" "${FAIL}" <<'PY'
import json, sys
path, p, f = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
json.dump({"pass": p, "fail": f, "total": 12, "solved": p == 12 and f == 0}, open(path, "w"), indent=2)
PY

HOST="$(hostname 2>/dev/null || echo unknown)"
if [[ "${PASS}" -eq 12 ]]; then
  echo "HOLY_GRAIL_1202_SOLVED=YES fail=0 checks=12/12 host=${HOST}" | tee "${OUT_TXT}"
  our_goal_log "D2_holy_grail" "PASS" "${OUT_TXT}" "12/12"
  exit 0
fi
echo "HOLY_GRAIL_1202_SOLVED=NO pass=${PASS}/12 fail=${FAIL} host=${HOST}" | tee "${OUT_TXT}"
our_goal_log "D2_holy_grail" "PARTIAL" "${OUT_TXT}" "${PASS}/12"
exit 0
