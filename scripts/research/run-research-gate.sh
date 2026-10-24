#!/usr/bin/env bash
# run-research-gate.sh — smoke gate: preflight + verifier oracle (no fake offline PASS).
set -euo pipefail
# shellcheck source=scripts/research/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=scripts/research/research-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/research-log.sh"

research_real_only_gate
research_ensure_ledger

ROOT="$(research_repo_root)"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="${RESEARCH_LEDGER_DIR}/gates/smoke-${STAMP}"
mkdir -p "${OUT}"

FAIL=0

echo "=== research smoke gate ${STAMP} ===" | tee "${OUT}/summary.log"

# 1) Live preflight
if RESEARCH_PREFLIGHT_OUT="${OUT}/00-preflight.json" bash "${ROOT}/scripts/research/live-preflight.sh" \
  | tee "${OUT}/preflight.log"; then
  research_log "R_gate_preflight" "PASS" "${OUT}/00-preflight.json" ""
else
  research_log "R_gate_preflight" "FAIL" "${OUT}" ""
  FAIL=$((FAIL + 1))
fi

# 2) Verifier load oracle
if bash "${ROOT}/research/verifier/run-load-oracle.sh" "${OUT}/verifier" | tee "${OUT}/verifier.log"; then
  research_log "R_gate_verifier" "PASS" "${OUT}/verifier" "load oracle"
else
  research_log "R_gate_verifier" "FAIL" "${OUT}/verifier" ""
  FAIL=$((FAIL + 1))
fi

# 3) Template claim must FAIL verify (sanity)
if bash "${ROOT}/scripts/research/bypass-claim-verify.sh" "${ROOT}/research/claims/BP-000-template" \
  >> "${OUT}/template-verify.log" 2>&1; then
  echo "FAIL: template claim must not verify PASS" | tee -a "${OUT}/summary.log"
  FAIL=$((FAIL + 1))
else
  echo "OK template claim correctly rejected" | tee -a "${OUT}/summary.log"
fi

# 4) Document tier limits on this host
tier="$(python3 -c "import json; print(json.load(open('${OUT}/00-preflight.json'))['research_tier'])")"
if [[ "${tier}" == "R0" ]]; then
  echo "NOTE: R0 host — SECURITY-IMPACT kernel bypass claims require R1 lab (sched_ext kernel)." \
    | tee -a "${OUT}/summary.log"
fi

if [[ "${FAIL}" -gt 0 ]]; then
  research_log "R_gate_smoke" "FAIL" "${OUT}" "fail=${FAIL}"
  echo "RESEARCH_GATE_FAIL fail=${FAIL} artifact=${OUT}" >&2
  exit 1
fi

research_log "R_gate_smoke" "PASS" "${OUT}" "tier=${tier}"
echo "RESEARCH_GATE_PASS artifact=${OUT} tier=${tier}"
