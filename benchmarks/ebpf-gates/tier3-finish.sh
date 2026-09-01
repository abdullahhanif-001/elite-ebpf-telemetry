#!/usr/bin/env bash
# tier3-finish.sh — run remaining Holy Grail checks (simple one-shot on VPS).
set -euo pipefail
ROOT="${ELITE_SRC:-/opt/elite/src}"
G="${ROOT}/benchmarks/ebpf-gates"
export FLOOD_OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}"

echo "=== tier3-finish flood=${FLOOD_OUT} ==="
bash "${G}/tier3-edge-lite.sh"
bash "${G}/tier3-repro-simple.sh"
bash "${G}/tier3-layered-simple.sh" || true
bash "${G}/tier3-run-all.sh"
bash "${G}/tier3-build-matrix.sh"
bash "${G}/tier3-endurance-simple.sh" bpfland 1800
bash "${G}/holy-grail-verify.sh" "${FLOOD_OUT}"
bash "${G}/global-ebpf-aggregate.sh"
echo "TIER3_FINISH_DONE"
