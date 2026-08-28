#!/usr/bin/env bash
# elite-run-safe.sh — VPS real test suite with PM2 guard wrap (no mock inject).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${ELITE_RUN_SAFE_LOG:-/tmp/elite-run-safe-${STAMP}.log}"

exec > >(tee -a "${LOG}") 2>&1
echo "=== elite-run-safe ${STAMP} ==="

wrap() {
  if [[ -x "${REPO_ROOT}/scripts/contabo/pm2-guard-wrap.sh" ]]; then
    bash "${REPO_ROOT}/scripts/contabo/pm2-guard-wrap.sh" "$1" "$2"
  else
    bash "${REPO_ROOT}/deploy/contabo/pm2-guard.sh"
  fi
}

wrap before elite-run-safe

export REAL_ONLY=1
export PROOFS_ONLY=1
export SKIP_PHYSICS_PROOF=1

bash "${SCRIPT_DIR}/live-real-closed-loop-proof.sh"
bash "${SCRIPT_DIR}/forecaster-agrade.sh"
bash "${SCRIPT_DIR}/competitive-speed-proof.sh"
bash "${SCRIPT_DIR}/competitive-overhead-proof.sh"
bash "${SCRIPT_DIR}/competitive-live-predict-proof.sh"
bash "${SCRIPT_DIR}/soft-dcic-proof.sh" || true
bash "${SCRIPT_DIR}/category-bakeoff.sh" || true
bash "${REPO_ROOT}/deploy/contabo/final-stress-test.sh"
bash "${REPO_ROOT}/scripts/elite-adversarial-audit.sh" || true
bash "${SCRIPT_DIR}/gates-checklist.sh" || true

wrap after elite-run-safe

echo "ELITE_RUN_SAFE_DONE log=${LOG}"
