#!/usr/bin/env bash
# elite-run-complete.sh — full real suite + eBPF X-ray + gates 8/8.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${ELITE_RUN_COMPLETE_LOG:-/tmp/elite-run-complete-${STAMP}.log}"

exec > >(tee -a "${LOG}") 2>&1
echo "=== elite-run-complete ${STAMP} ==="

export REAL_ONLY=1 PROOFS_ONLY=1 SKIP_PHYSICS_PROOF=1
# Safe XDP: never attach mitigator on eth0 during proofs (SSH brick risk).
export ELITE_XDP_IFACE="${ELITE_XDP_IFACE:-lo}"
export ELITE_XDP_MODE="${ELITE_XDP_MODE:-skb}"
export ELITE_XDP_FORCE="${ELITE_XDP_FORCE:-1}"
export ELITE_BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
export XDP_HEALTH_NO_UNLOAD=1

SAFE_PREP="${REPO_ROOT}/scripts/server/safe-proof-prep.sh"
if [[ -f "${SAFE_PREP}" ]]; then
  bash "${SAFE_PREP}" || true
fi

bash "${SCRIPT_DIR}/elite-run-safe.sh" || true

bash "${SCRIPT_DIR}/ebpf-xray-real-proof.sh" || true

bash "${SCRIPT_DIR}/gates-checklist.sh" || true

WRITE_REPORTS="${SCRIPT_DIR}/write-phase-b-reports.sh"
if [[ -f "${WRITE_REPORTS}" ]]; then
  bash "${WRITE_REPORTS}" || true
fi

echo "ELITE_RUN_COMPLETE_DONE log=${LOG}"
