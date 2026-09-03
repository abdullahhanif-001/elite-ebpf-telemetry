#!/usr/bin/env bash
# elite-zero-buffer-complete v1 — Phase0 + G6–G15 zero-buffer proofs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${ELITE_ZERO_BUFFER_LOG:-/tmp/elite-zero-buffer-v1-${STAMP}.log}"

export REAL_ONLY=1 PROOFS_ONLY=1 SKIP_PHYSICS_PROOF=1 ZERO_BUFFER_GATES=1
export ELITE_XDP_IFACE="${ELITE_XDP_IFACE:-lo}"
export ELITE_XDP_MODE="${ELITE_XDP_MODE:-skb}"
export ELITE_XDP_FORCE="${ELITE_XDP_FORCE:-1}"
export ELITE_BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"

exec > >(tee -a "${LOG}") 2>&1
echo "=== elite-zero-buffer-complete v1 ${STAMP} ==="

fail=0
run_step() {
  local name="$1" cmd="$2"
  echo "--- step: ${name} ---"
  if eval "${cmd}"; then
    echo "STEP_PASS ${name}"
  else
    echo "STEP_FAIL ${name}"
    fail=$((fail + 1))
  fi
}

run_step "matrix-g0" "bash \"${REPO_ROOT}/benchmarks/zero-buffer/matrix.sh\""
run_step "g10-priority" "bash \"${SCRIPT_DIR}/g10-priority-pass-proof.sh\""
run_step "g14-multicore" "bash \"${REPO_ROOT}/benchmarks/zero-buffer/g14-multicore.sh\""
run_step "g15-federate" "bash \"${SCRIPT_DIR}/g15-federate-propagation-proof.sh\""

WRAP="${REPO_ROOT}/scripts/server/pm2-guard-wrap.sh"
if [[ -f "${WRAP}" ]]; then
  run_step "elite-run-complete" "bash \"${WRAP}\" -- bash \"${SCRIPT_DIR}/elite-run-complete.sh\""
else
  run_step "elite-run-complete" "bash \"${SCRIPT_DIR}/elite-run-complete.sh\""
fi

run_step "traffic-engine" "bash \"${SCRIPT_DIR}/traffic-engine-proof.sh\""
run_step "w5-graduated" "bash \"${REPO_ROOT}/benchmarks/server-gates/w5-xdp-graduated-shed.sh\""
run_step "thundering-herd" "bash \"${SCRIPT_DIR}/thundering-herd-proof.sh\""

if [[ -f "${SCRIPT_DIR}/gates-checklist.sh" ]]; then
  run_step "gates" "bash \"${SCRIPT_DIR}/gates-checklist.sh\""
fi

if [[ -f "${SCRIPT_DIR}/write-phase-b-reports.sh" ]]; then
  run_step "reports" "bash \"${SCRIPT_DIR}/write-phase-b-reports.sh\""
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "ZERO_BUFFER_V1_COMPLETE"
  exit 0
fi
echo "ZERO_BUFFER_V1_INCOMPLETE fail_steps=${fail}"
exit 1
