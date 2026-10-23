#!/usr/bin/env bash
# bypass-claim-verify.sh — strict check of a research/claims/<ID> directory.
set -euo pipefail
# shellcheck source=scripts/research/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

research_forbid_offline

CLAIM_DIR="${1:?claim directory e.g. research/claims/BP-001}"
ROOT="$(research_repo_root)"
[[ "${CLAIM_DIR}" != /* ]] && CLAIM_DIR="${ROOT}/${CLAIM_DIR}"

FAIL=0
note_fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
note_ok() { echo "OK   $*"; }

[[ -d "${CLAIM_DIR}" ]] || { note_fail "missing directory ${CLAIM_DIR}"; exit 1; }

require_file() {
  [[ -f "${1}" ]] || note_fail "missing ${1}"
}

require_file "${CLAIM_DIR}/MANIFEST.json"
require_file "${CLAIM_DIR}/00-preflight.json"
require_file "${CLAIM_DIR}/IMPACT.md"
require_file "${CLAIM_DIR}/load.log"

if [[ ! -d "${CLAIM_DIR}/repro" ]]; then
  note_fail "missing repro/"
fi

impact="$(python3 -c "import json; print(json.load(open('${CLAIM_DIR}/MANIFEST.json')).get('impact',''))" 2>/dev/null || true)"
allowed="NONE DOS INFO_LEAK OOB CODE_EXEC USERSPACE HYPOTHESIS"
if ! echo "${allowed}" | grep -qw "${impact}"; then
  note_fail "MANIFEST impact must be one of: ${allowed} (got '${impact}')"
else
  note_ok "impact=${impact}"
fi

if [[ "${impact}" == "HYPOTHESIS" || "${impact}" == "USERSPACE" ]]; then
  note_ok "non-kernel impact — SECURITY bypass PASS not implied"
fi

if [[ "${impact}" == "OOB" || "${impact}" == "CODE_EXEC" || "${impact}" == "INFO_LEAK" ]]; then
  require_file "${CLAIM_DIR}/dmesg.txt"
fi

# Preflight must match this host if VERIFY_LIVE_HOST=1 (default)
VERIFY_LIVE_HOST="${VERIFY_LIVE_HOST:-1}"
if [[ "${VERIFY_LIVE_HOST}" == "1" ]]; then
  pf_host="$(python3 -c "import json; print(json.load(open('${CLAIM_DIR}/00-preflight.json'))['hostname'])" 2>/dev/null || echo "")"
  pf_kern="$(python3 -c "import json; print(json.load(open('${CLAIM_DIR}/00-preflight.json'))['kernel_release'])" 2>/dev/null || echo "")"
  if [[ "${pf_host}" != "$(hostname)" ]]; then
    note_fail "preflight hostname '${pf_host}' != $(hostname) (set VERIFY_LIVE_HOST=0 to audit bundle only)"
  else
    note_ok "preflight hostname matches"
  fi
  if [[ "${pf_kern}" != "$(uname -r)" ]]; then
    note_fail "preflight kernel '${pf_kern}' != $(uname -r)"
  else
    note_ok "preflight kernel matches"
  fi
fi

# Template claims must never PASS
claim_id="$(python3 -c "import json; print(json.load(open('${CLAIM_DIR}/MANIFEST.json')).get('claim_id',''))" 2>/dev/null || true)"
if [[ "${claim_id}" == *template* ]] || [[ "${CLAIM_DIR}" == *template* ]]; then
  note_fail "template claim cannot PASS verification"
fi

if grep -qiE 'ELITE_OFFLINE|SCX1202_MATRIX_PASS.*research|FUTURE_HOLES_PASS.*bypass' "${CLAIM_DIR}/IMPACT.md" "${CLAIM_DIR}/load.log" 2>/dev/null; then
  note_fail "forbidden offline/product gate strings in claim logs"
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "BYPASS_CLAIM_VERIFY=FAIL count=${FAIL} dir=${CLAIM_DIR}" >&2
  exit 1
fi

echo "BYPASS_CLAIM_VERIFY=PASS dir=${CLAIM_DIR} impact=${impact}"
exit 0
