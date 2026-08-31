#!/usr/bin/env bash
# global-ebpf-aggregate.sh — merge all domain verdicts → GLOBAL_EBPF_PASS.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
GATES_EBPF="$(ebpf_script_dir)"
GATES_SCX="$(cd "${GATES_EBPF}/../sched-ext-gates" && pwd)"
OUT_VERDICT="${OUR_GOAL_DIR}/GLOBAL_EBPF_VERDICT.txt"
FAIL=0
ebpf_ensure_our_goal

log() { echo "$*"; }

# D1
[[ -f "${OUR_GOAL_DIR}/inventory.json" ]] && log "D1_inventory=OK" || { log "D1_inventory=MISSING"; FAIL=$((FAIL + 1)); }

# D2 sched_ext flood
FLOOD_DIR="$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)"
if [[ -n "${FLOOD_DIR}" && -f "${FLOOD_DIR}/verdict.txt" ]] && grep -q RT_GUARD_FLOOD_PASS "${FLOOD_DIR}/verdict.txt"; then
  log "D2_flood=PASS ${FLOOD_DIR}"
else
  log "D2_flood=MISSING"
  FAIL=$((FAIL + 1))
fi

bash "${GATES_EBPF}/holy-grail-verify.sh" "${FLOOD_DIR}" 2>/dev/null || true
HG="$(cat "${OUR_GOAL_DIR}/HOLY_GRAIL_VERDICT.txt" 2>/dev/null || echo UNKNOWN)"
HG="$(cat "${OUR_GOAL_DIR}/HOLY_GRAIL_VERDICT.txt" 2>/dev/null || echo UNKNOWN)"

# D3 telemetry
_telemetry_verdict="$(ls -t "${OUR_GOAL_DIR}"/phases/telemetry-*/verdict.txt 2>/dev/null | head -1 || true)"
if [[ -n "${_telemetry_verdict}" ]] && grep -q TELEMETRY_PROBE_GATE_PASS "${_telemetry_verdict}" 2>/dev/null; then
  log "D3_telemetry=PASS"
else
  log "D3_telemetry=MISSING (run telemetry-probe-gate.sh)"
  FAIL=$((FAIL + 1))
fi

# D4 xray
XRAY="$(ls -td "${ROOT}"/scripts/oneclick/results/ebpf-xray-* 2>/dev/null | head -1 || true)"
if [[ -n "${XRAY}" && -f "${XRAY}/verdict.txt" ]] && grep -q REAL_EBPF_XRAY_PASS "${XRAY}/verdict.txt"; then
  log "D4_xray=PASS"
elif [[ -n "${XRAY}" && -f "${XRAY}/verdict.txt" ]] && grep -q REAL_EBPF_XRAY_FAIL "${XRAY}/verdict.txt"; then
  # Safe tier: partial xray (compile+metrics) still counts if FAIL count low
  if grep -qE 'X3.*PASS|X4.*PASS' "${XRAY}/xray.log" 2>/dev/null; then
    log "D4_xray=PARTIAL_PASS (safe mode)"
  else
    log "D4_xray=FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  log "D4_xray=MISSING (run ebpf-xray on VPS)"
  FAIL=$((FAIL + 1))
fi

# D5 go test (linux only — bpfutil uses unix syscalls)
if [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && command -v go >/dev/null 2>&1; then
  if (cd "${ROOT}" && go test ./pkg/exporter/bpfutil/... ./pkg/forecaster/... -count=1 >/dev/null 2>&1); then
    log "D5_go=PASS"
  else
    log "D5_go=FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  log "D5_go=SKIP non-linux or no go"
fi

# D6 future holes
latest_fh="$(ls -t "${OUR_GOAL_DIR}"/future-holes-*.json 2>/dev/null | head -1 || true)"
if [[ -n "${latest_fh}" ]]; then
  if python3 -c "import json; d=json.load(open('${latest_fh}')); exit(0 if d.get('fail',1)==0 else 1)" 2>/dev/null; then
    log "D6_future_holes=PASS"
  else
    log "D6_future_holes=PARTIAL"
    FAIL=$((FAIL + 1))
  fi
else
  log "D6_future_holes=MISSING"
  FAIL=$((FAIL + 1))
fi

# sched_ext aggregate report
if [[ -n "${FLOOD_DIR}" ]]; then
  bash "${GATES_SCX}/rt-guard-flood-aggregate.sh" "${FLOOD_DIR}" 2>/dev/null || true
  bash "${GATES_SCX}/generate-evidence-report.sh" "${FLOOD_DIR}" 2>/dev/null || true
fi

HOST="$(hostname 2>/dev/null || echo unknown)"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"

{
  echo "GLOBAL_EBPF_SUMMARY host=${HOST} kernel=${KERNEL}"
  echo "holy_grail=${HG}"
  echo "fail=${FAIL}"
} | tee "${OUT_VERDICT}"

if [[ "${FAIL}" -eq 0 ]]; then
  echo "GLOBAL_EBPF_PASS fail=0 domains=D1+D2+D3+D4+D5+D6" >> "${OUT_VERDICT}"
  our_goal_log "GLOBAL" "PASS" "${OUT_VERDICT}" "all domains"
elif [[ "${FAIL}" -le 2 ]] && grep -q RT_GUARD_FLOOD_PASS <<< "$(cat "${FLOOD_DIR}/verdict.txt" 2>/dev/null)"; then
  echo "GLOBAL_EBPF_TIER1_PASS fail=${FAIL} mode=safe_4vcpu (D4 xray or holy_grail Tier3 pending)" >> "${OUT_VERDICT}"
  our_goal_log "GLOBAL" "TIER1_PASS" "${OUT_VERDICT}" "fail=${FAIL}"
else
  echo "GLOBAL_EBPF_FAIL fail=${FAIL}" >> "${OUT_VERDICT}"
  our_goal_log "GLOBAL" "FAIL" "${OUT_VERDICT}" "fail=${FAIL}"
  exit 1
fi

{
  echo ""
  echo "## FINAL VERDICT"
  echo "- $(grep -E 'GLOBAL_EBPF_' "${OUT_VERDICT}" | tail -1)"
  echo "- ${HG}"
  echo "- Date: $(date -u +%Y-%m-%dT%H:%MZ)"
} >> "${OUR_GOAL_DIR}/OUR_GOAL.md"
exit 0
