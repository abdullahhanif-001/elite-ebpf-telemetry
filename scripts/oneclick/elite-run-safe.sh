#!/usr/bin/env bash
# elite-run-safe.sh — VPS real test suite with PM2 guard wrap (no mock inject).
# Fail-closed: REQUIRED children must exit 0; suite exits ≠ 0 on any REQUIRED fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${ELITE_RUN_SAFE_LOG:-/tmp/elite-run-safe-${STAMP}.log}"

exec > >(tee -a "${LOG}") 2>&1
echo "=== elite-run-safe ${STAMP} ==="

FAILS=0
run_req() {
  local name="$1"
  shift
  echo "--- RUN_REQ ${name} ---"
  if [[ -x "${SCRIPT_DIR}/vps-resource-guard.sh" ]]; then
    bash "${SCRIPT_DIR}/vps-resource-guard.sh" || {
      echo "RUN_REQ_ABORT resource-guard before ${name}"
      FAILS=$((FAILS + 1))
      return 0
    }
  fi
  if "$@"; then
    echo "RUN_REQ_PASS ${name}"
  else
    local rc=$?
    echo "RUN_REQ_FAIL ${name} rc=${rc}"
    FAILS=$((FAILS + 1))
  fi
}

wrap() {
  if [[ -x "${REPO_ROOT}/scripts/server/pm2-guard-wrap.sh" ]]; then
    bash "${REPO_ROOT}/scripts/server/pm2-guard-wrap.sh" "$1" "$2"
  else
    bash "${REPO_ROOT}/deploy/server/pm2-guard.sh"
  fi
}

wrap before elite-run-safe

export REAL_ONLY=1
export PROOFS_ONLY=1
# Physics :9435 is OPTIONAL — document explicitly (not silent full-cover claim).
export SKIP_PHYSICS_PROOF="${SKIP_PHYSICS_PROOF:-1}"
echo "PHYSICS_LANE=OPTIONAL SKIP_PHYSICS_PROOF=${SKIP_PHYSICS_PROOF}"

run_req live-real-closed-loop bash "${SCRIPT_DIR}/live-real-closed-loop-proof.sh"
run_req forecaster-agrade bash "${SCRIPT_DIR}/forecaster-agrade.sh"
run_req competitive-speed bash "${SCRIPT_DIR}/competitive-speed-proof.sh"
run_req competitive-overhead bash "${SCRIPT_DIR}/competitive-overhead-proof.sh"
run_req competitive-live-predict bash "${SCRIPT_DIR}/competitive-live-predict-proof.sh"
run_req soft-dcic bash "${SCRIPT_DIR}/soft-dcic-proof.sh"
run_req category-bakeoff bash "${SCRIPT_DIR}/category-bakeoff.sh"
run_req final-stress bash "${REPO_ROOT}/deploy/server/final-stress-test.sh"
run_req adversarial bash "${REPO_ROOT}/scripts/elite-adversarial-audit.sh"
run_req gates-checklist bash "${SCRIPT_DIR}/gates-checklist.sh"

wrap after elite-run-safe

if [[ "${FAILS}" -gt 0 ]]; then
  echo "ELITE_RUN_SAFE_FAIL fails=${FAILS} log=${LOG}"
  exit 1
fi

echo "ELITE_RUN_SAFE_DONE log=${LOG}"
