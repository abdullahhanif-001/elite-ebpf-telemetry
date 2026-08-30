#!/usr/bin/env bash
# run-on-vps.sh — run gate suite locally on VPS (no SSH hop).
set -euo pipefail
export REAL_ONLY=1 PROOFS_ONLY=1
ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
cd "${ELITE_SRC}"
bash benchmarks/sched-ext-gates/rt-guard-pass.sh
